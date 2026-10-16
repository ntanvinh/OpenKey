//
//  Diagnostics.m
//  VOpenKey
//
//  See Diagnostics.h.
//
//  Everything that touches the file happens on one serial queue, so logging from the event tap costs a message format and a
//  dispatch_async. The watchdog runs on that queue too, not on the main thread: it has to keep working when the main thread is stuck.
//

#import "Diagnostics.h"
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#import <stdatomic.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#import "AppInfo.h"

int vDiagnostics = 0;

static NSString* const kDiagnosticsKey = @"DiagnosticsLog";
static const NSUInteger kDefaultMaxFileBytes = 1024 * 1024;     //two files of this size: about 2 MB
static const NSTimeInterval kSnapshotInterval = 60;
static const NSTimeInterval kDeliveryQuietTime = 1.5;           //posted events have had this long to arrive
static NSTimeInterval sDeliveryReportEvery = 10;               //ten watchdog ticks

static dispatch_queue_t sQueue;
static dispatch_source_t sWatchdog;
static NSDateFormatter* sFormatter;                             //only used on sQueue
static int sFD = -1;
static NSUInteger sBytes, sMaxBytes = kDefaultMaxFileBytes;
static NSString* sPath;

static NSTimer* sBeatTimer;
static NSTimer* sSnapshotTimer;
static _Atomic uint64_t sBeat;                                  //last time the main thread answered, CLOCK_UPTIME_RAW in ns

static NSTimeInterval sStallThreshold = 2;
static BOOL sStalled;
static uint64_t sStallBeat;

static NSInteger sTapState = -2;                                //-2 never looked, -1 not made, 0 off, 1 on
static uint64_t sTapOffSince;

static _Atomic uint64_t sPosted[VOKEventKindCount][2];          //[kind][0 key downs, 1 key ups]
static _Atomic uint64_t sArrived[VOKEventKindCount][2];
static _Atomic uint64_t sLastPost;
static _Atomic int64_t sWatchedSource;
static uint64_t sReportedPosted[VOKEventKindCount][2];          //sQueue only
static uint64_t sReportedArrived[VOKEventKindCount][2];
static uint64_t sLastDeliveryReport;
static CFMachPortRef sArrivalTap;
static CFRunLoopRef sArrivalLoop;

static NSInteger (^sTapCheck)(void);
static NSString* (^sSnapshotProvider)(void);

static uint64_t NowNs(void) {
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

static NSString* KindName(VOKEventKind kind) {
    switch (kind) {
        case VOKEventKindBackspace: return @"backspace";
        case VOKEventKindEmptyChar: return @"empty-char";
        default: return @"text";
    }
}

#pragma mark - The file (sQueue only)

static void CloseFile(void) {
    if (sFD >= 0)
        close(sFD);
    sFD = -1;
}

static void OpenFile(void) {
    CloseFile();
    //only this user reads it: it says which applications were used, and when
    [[NSFileManager defaultManager] createDirectoryAtPath:sPath.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0700}
                                                    error:nil];
    sFD = open(sPath.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0600);
    struct stat info;
    sBytes = (sFD >= 0 && fstat(sFD, &info) == 0) ? (NSUInteger)info.st_size : 0;
}

static void Rotate(void) {
    CloseFile();
    NSString* previous = [[sPath stringByDeletingPathExtension] stringByAppendingString:@".1.log"];
    rename(sPath.fileSystemRepresentation, previous.fileSystemRepresentation);
    OpenFile();
}

static void LogOnQueue(NSString* category, NSString* message, NSDate* when) {
    if (sFD < 0)
        return;
    NSString* line = [NSString stringWithFormat:@"%@ [%@] %@\n", [sFormatter stringFromDate:when], category, message];
    NSData* data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (sBytes + data.length > sMaxBytes && sBytes > 0)
        Rotate();
    if (sFD >= 0 && write(sFD, data.bytes, data.length) == (ssize_t)data.length)
        sBytes += data.length;
}

#pragma mark - The watchdog (sQueue)

static void CheckMainThread(uint64_t now) {
    uint64_t beat = atomic_load(&sBeat);
    double idle = now > beat ? (double)(now - beat) / 1e9 : 0;
    if (idle > sStallThreshold) {
        if (!sStalled) {
            sStalled = YES;
            sStallBeat = beat;
            LogOnQueue(@"ANOMALY", [NSString stringWithFormat:@"MAIN THREAD STALL: no answer for %.1f s. Typing is converted on that thread, "
                                    "so keys are not converted while this lasts, and macOS switches the event tap off when a key waits "
                                    "about a second for it", idle], [NSDate date]);
        }
    } else if (sStalled) {
        sStalled = NO;
        LogOnQueue(@"stall", [NSString stringWithFormat:@"main thread answering again, it was blocked for about %.1f s",
                              beat > sStallBeat ? (double)(beat - sStallBeat) / 1e9 : 0], [NSDate date]);
    }
}

static void CheckTap(uint64_t now) {
    NSInteger (^check)(void);
    @synchronized ([VOKDiagnostics class]) {
        check = sTapCheck;
    }
    NSInteger state = check != nil ? check() : -1;
    if (state < 0 || state == sTapState)
        return;
    if (state == 0) {
        sTapOffSince = now;
        LogOnQueue(@"ANOMALY", @"TAP DISABLED: macOS switched the event tap off (its callback or the main thread was too slow, or the "
                   "user input of a protected field). VOpenKey converts nothing until the tap is on again", [NSDate date]);
    } else if (sTapState == 0) {
        LogOnQueue(@"tap", [NSString stringWithFormat:@"TAP enabled again after %.1f s", (double)(now - sTapOffSince) / 1e9], [NSDate date]);
    } else {
        LogOnQueue(@"tap", @"TAP enabled", [NSDate date]);
    }
    sTapState = state;
}

//Compares what the app posted with what reached the end of the event chain. Only counts that matter for the user: if the key downs of
//the text or the backspaces go missing, the screen shows less than the engine asked for.
static void CheckDelivery(uint64_t now) {
    if (atomic_load(&sWatchedSource) == 0 || sStalled || sTapState != 1 || IsSecureEventInputEnabled())
        return;
    uint64_t lastPost = atomic_load(&sLastPost);
    if (lastPost == 0 || now < lastPost || (double)(now - lastPost) / 1e9 < kDeliveryQuietTime)
        return;
    uint64_t posted[VOKEventKindCount][2], arrived[VOKEventKindCount][2];
    BOOL changed = NO;
    for (int k = 0; k < VOKEventKindCount; k++) {
        for (int d = 0; d < 2; d++) {
            posted[k][d] = atomic_load(&sPosted[k][d]);
            arrived[k][d] = atomic_load(&sArrived[k][d]);
            changed = changed || posted[k][d] != sReportedPosted[k][d];
        }
    }
    if (!changed || (sLastDeliveryReport != 0 && (double)(now - sLastDeliveryReport) / 1e9 < sDeliveryReportEvery))
        return;

    NSMutableString* summary = [NSMutableString string];
    NSMutableString* lost = [NSMutableString string];
    for (int k = 0; k < VOKEventKindCount; k++) {
        uint64_t postedNow = posted[k][0] - sReportedPosted[k][0], arrivedNow = arrived[k][0] - sReportedArrived[k][0];
        uint64_t postedUp = posted[k][1] - sReportedPosted[k][1], arrivedUp = arrived[k][1] - sReportedArrived[k][1];
        [summary appendFormat:@"%@ down %llu/%llu up %llu/%llu; ", KindName((VOKEventKind)k), arrivedNow, postedNow, arrivedUp, postedUp];
        //the invisible character is not counted as a loss: see the note where it is sent
        if ((VOKEventKind)k != VOKEventKindEmptyChar && (arrivedNow < postedNow || arrivedUp < postedUp)) {
            [lost appendFormat:@"%@ key downs %llu of %llu, key ups %llu of %llu; ", KindName((VOKEventKind)k), arrivedNow, postedNow, arrivedUp, postedUp];
        }
    }
    LogOnQueue(@"delivery", [NSString stringWithFormat:@"arrived/posted since the last report: %@", summary], [NSDate date]);
    if (lost.length > 0) {
        LogOnQueue(@"ANOMALY", [NSString stringWithFormat:@"DELIVERY: key events the app posted never reached the end of the event chain "
                                "(arrived of posted): %@", lost], [NSDate date]);
    }
    memcpy(sReportedPosted, posted, sizeof posted);
    memcpy(sReportedArrived, arrived, sizeof arrived);
    sLastDeliveryReport = now;
}

static void Watchdog(void) {
    uint64_t now = NowNs();
    CheckMainThread(now);
    CheckTap(now);
    CheckDelivery(now);
}

#pragma mark - What reaches the end of the event chain

//A listener at the very end of the chain, on a thread of its own so that it takes events as soon as they come. Only looks at events of
//the typing source, and of those only at what kind they are: never at what they say, apart from "is it the invisible character".
static CGEventRef ArrivalCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon) {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (sArrivalTap != NULL)
            CGEventTapEnable(sArrivalTap, true);
        return event;
    }
    int64_t watched = atomic_load(&sWatchedSource);
    if (watched == 0 || CGEventGetIntegerValueField(event, kCGEventSourceStateID) != watched)
        return event;
    if (CGEventGetFlags(event) & kCGEventFlagMaskCommand) //the ⌘V of a snippet
        return event;
    int64_t key = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    VOKEventKind kind;
    if (key == 51) {
        kind = VOKEventKindBackspace;
    } else if (key == 0) {
        UniChar characters[2];
        UniCharCount length = 0;
        CGEventKeyboardGetUnicodeString(event, 2, &length, characters);
        if (length == 0)
            return event; //a key without text
        kind = (length == 1 && (characters[0] == 0x202F || characters[0] == 0x200C)) ? VOKEventKindEmptyChar : VOKEventKindText;
    } else {
        return event;
    }
    [VOKDiagnostics countArrived:kind down:type == kCGEventKeyDown];
    return event;
}

static void StartArrivalListener(void) {
    if (sArrivalTap != NULL)
        return;
    [NSThread detachNewThreadWithBlock:^{
        CGEventMask mask = (1 << kCGEventKeyDown) | (1 << kCGEventKeyUp);
        CFMachPortRef tap = CGEventTapCreate(kCGAnnotatedSessionEventTap, kCGTailAppendEventTap, kCGEventTapOptionListenOnly,
                                             mask, ArrivalCallback, NULL);
        if (tap == NULL) {
            VOKDiag(@"delivery", @"the listener for what reaches the end of the event chain could not be made (no Input Monitoring permission?)");
            return;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        sArrivalTap = tap;
        sArrivalLoop = CFRunLoopGetCurrent();
        CFRunLoopAddSource(sArrivalLoop, source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);
        CFRunLoopRun();
        CFRunLoopRemoveSource(sArrivalLoop, source, kCFRunLoopCommonModes);
        CFRelease(source);
        sArrivalTap = NULL;
        sArrivalLoop = NULL;
        CFMachPortInvalidate(tap);
        CFRelease(tap);
    }];
}

#pragma mark -

@implementation VOKDiagnostics

+(NSString*)logDirectory {
    NSString* library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    return [[library stringByAppendingPathComponent:@"Logs"] stringByAppendingPathComponent:VOK_DATA_DIR_NAME];
}

+(BOOL)isOn {
    return vDiagnostics != 0;
}

+(void)start {
#ifdef DEBUG
    BOOL defaultOn = YES;
#else
    BOOL defaultOn = NO;
#endif
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:@{kDiagnosticsKey: @(defaultOn)}];
    [self startWithDirectory:[self logDirectory]
                     enabled:[defaults boolForKey:kDiagnosticsKey]
                maxFileBytes:kDefaultMaxFileBytes
            watchdogInterval:1.0
              stallThreshold:2.0];
}

+(void)startWithDirectory:(NSString*)directory
                  enabled:(BOOL)enabled
             maxFileBytes:(NSUInteger)maxBytes
         watchdogInterval:(NSTimeInterval)interval
           stallThreshold:(NSTimeInterval)stall {
    if (!enabled || sQueue != nil)
        return;

    sMaxBytes = maxBytes;
    sStallThreshold = stall;
    sDeliveryReportEvery = interval * 10;
    sPath = [directory stringByAppendingPathComponent:@"diagnostics.log"];
    sQueue = dispatch_queue_create("vn.io.lssoft.vopenkey.diagnostics", DISPATCH_QUEUE_SERIAL);
    sFormatter = [[NSDateFormatter alloc] init];
    sFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    sFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    sStalled = NO;
    sTapState = -2;
    memset(sReportedPosted, 0, sizeof sReportedPosted);
    memset(sReportedArrived, 0, sizeof sReportedArrived);
    sLastDeliveryReport = 0;
    for (int k = 0; k < VOKEventKindCount; k++) {
        for (int d = 0; d < 2; d++) {
            atomic_store(&sPosted[k][d], 0);
            atomic_store(&sArrived[k][d], 0);
        }
    }
    atomic_store(&sLastPost, 0);
    atomic_store(&sBeat, NowNs());

    dispatch_sync(sQueue, ^{
        OpenFile();
        NSDictionary* info = [NSBundle mainBundle].infoDictionary;
        LogOnQueue(@"start", [NSString stringWithFormat:@"---- %@ %@ (%@), pid %d, %@ ---- diagnostics on (defaults key %@; this build's default: %@)",
                              VOK_APP_NAME, info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"], getpid(),
                              [NSProcessInfo processInfo].operatingSystemVersionString, kDiagnosticsKey,
#ifdef DEBUG
                              @"on"
#else
                              @"off"
#endif
                              ], [NSDate date]);
    });
    vDiagnostics = 1;

    sWatchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, sQueue);
    dispatch_source_set_timer(sWatchdog, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
                              (uint64_t)(interval * NSEC_PER_SEC), (uint64_t)(interval * NSEC_PER_SEC / 10));
    dispatch_source_set_event_handler(sWatchdog, ^{ Watchdog(); });
    dispatch_resume(sWatchdog);

    //the heartbeat: only the main thread can make this move
    sBeatTimer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer* timer) {
        atomic_store(&sBeat, NowNs());
    }];
    [[NSRunLoop mainRunLoop] addTimer:sBeatTimer forMode:NSRunLoopCommonModes];

    sSnapshotTimer = [NSTimer timerWithTimeInterval:kSnapshotInterval repeats:YES block:^(NSTimer* timer) {
        [self logSnapshot];
    }];
    [[NSRunLoop mainRunLoop] addTimer:sSnapshotTimer forMode:NSRunLoopCommonModes];
    [self logSnapshot];
}

+(void)stop {
    if (sQueue == nil)
        return;
    vDiagnostics = 0;
    [sBeatTimer invalidate];
    sBeatTimer = nil;
    [sSnapshotTimer invalidate];
    sSnapshotTimer = nil;
    atomic_store(&sWatchedSource, 0);
    if (sArrivalLoop != NULL)
        CFRunLoopStop(sArrivalLoop);
    dispatch_source_cancel(sWatchdog);
    sWatchdog = nil;
    dispatch_sync(sQueue, ^{
        CloseFile();
    });
    sQueue = nil;
    sFormatter = nil;
}

+(void)setTapEnabledCheck:(NSInteger (^)(void))check {
    @synchronized (self) {
        sTapCheck = [check copy];
    }
}

+(void)setSnapshotProvider:(NSString* (^)(void))provider {
    @synchronized (self) {
        sSnapshotProvider = [provider copy];
    }
}

+(void)setWatchedSource:(int64_t)sourceStateID {
    atomic_store(&sWatchedSource, sourceStateID);
}

+(void)watchDeliveryFromSource:(int64_t)sourceStateID {
    if (sQueue == nil)
        return;
    [self setWatchedSource:sourceStateID];
    StartArrivalListener();
}

+(void)countPosted:(VOKEventKind)kind pairs:(NSUInteger)pairs {
    atomic_fetch_add(&sPosted[kind][0], pairs);
    atomic_fetch_add(&sPosted[kind][1], pairs);
    atomic_store(&sLastPost, NowNs());
}

+(void)countArrived:(VOKEventKind)kind down:(BOOL)down {
    atomic_fetch_add(&sArrived[kind][down ? 0 : 1], 1);
}

+(NSString*)currentInputSourceID {
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    if (source == NULL)
        return @"none";
    NSString* identifier = [(__bridge NSString*)TISGetInputSourceProperty(source, kTISPropertyInputSourceID) copy];
    CFRelease(source);
    return identifier ?: @"?";
}

+(void)log:(NSString*)category message:(NSString*)message {
    dispatch_queue_t queue = sQueue;
    if (queue == nil)
        return;
    NSDate* when = [NSDate date];
    dispatch_async(queue, ^{
        LogOnQueue(category, message, when);
    });
}

+(void)resetDeliveryCounters {
    dispatch_queue_t queue = sQueue;
    if (queue == nil)
        return;
    dispatch_sync(queue, ^{
        for (int k = 0; k < VOKEventKindCount; k++) {
            for (int d = 0; d < 2; d++) {
                atomic_store(&sPosted[k][d], 0);
                atomic_store(&sArrived[k][d], 0);
                sReportedPosted[k][d] = 0;
                sReportedArrived[k][d] = 0;
            }
        }
        atomic_store(&sLastPost, 0);
        sLastDeliveryReport = 0;
    });
}

+(void)flush {
    dispatch_queue_t queue = sQueue;
    if (queue != nil)
        dispatch_sync(queue, ^{});
}

//Every minute, and once at the start: where things stand
+(void)logSnapshot {
    NSString* (^provider)(void);
    NSInteger (^check)(void);
    @synchronized (self) {
        provider = sSnapshotProvider;
        check = sTapCheck;
    }
    NSString* front = [NSWorkspace sharedWorkspace].frontmostApplication.bundleIdentifier ?: @"?";
    NSString* detail = provider != nil ? provider() : @"";
    [self log:@"state" message:[NSString stringWithFormat:@"front=%@ inputSource=%@ secureInput=%d tap=%ld %@",
                                front, [self currentInputSourceID], IsSecureEventInputEnabled() ? 1 : 0,
                                (long)(check != nil ? check() : -1), detail]];
}

@end
