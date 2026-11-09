//
//  Tests of what is found out about the process that holds secure input (SecureInputHolder) and of how SecureInputMonitor hands it
//  on: the rules that tell the app being typed in from one in the background, a helper, the system, the lock screen and
//  nothing; the facts of a real process (this one, a child that runs /bin/sleep, a running app, one that is gone); and the monitor
//  with a faked session (who holds secure input, whether the screen is locked) telling the window about it.
//
//  SecureInputMonitor.m is compiled with IsSecureEventInputEnabled and CGSessionCopyCurrentDictionary replaced by fakes: no real
//  secure input is used and nothing is shown. Run with run-secure-input-holder-test.sh.
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "SecureInputMonitor.h"
#import "SuggestionController.h"
#import "Diagnostics.h"

static BOOL fakeSecure;
static pid_t fakeHolderPID;
static BOOL fakeLocked;
Boolean FakeSecure(void) { return fakeSecure; }
CFDictionaryRef FakeSession(void) {
    NSDictionary* session = @{@"kCGSSessionSecureInputPID": @(fakeHolderPID), @"CGSSessionScreenIsLocked": @(fakeLocked)};
    return (CFDictionaryRef)CFBridgingRetain(session);
}

//The input sources: macOS' Vietnamese ones are always "enabled" here, and selecting one only changes what the fake says is selected
static NSString* fakeSelectedSource = @"com.apple.keylayout.ABC";
static int fakeSelections;
static NSDictionary* FakeSource(NSString* identifier) {
    return @{(__bridge NSString*)kTISPropertyInputSourceID: identifier,
             (__bridge NSString*)kTISPropertyInputSourceType: (__bridge NSString*)kTISTypeKeyboardLayout,
             (__bridge NSString*)kTISPropertyInputSourceIsSelectCapable: @YES};
}
TISInputSourceRef FakeCurrentSource(void) { return (TISInputSourceRef)CFBridgingRetain(FakeSource(fakeSelectedSource)); }
CFArrayRef FakeSourceList(CFDictionaryRef filter, Boolean includeAllInstalled) {
    NSString* identifier = ((__bridge NSDictionary*)filter)[(__bridge NSString*)kTISPropertyInputSourceID];
    return (CFArrayRef)CFBridgingRetain(identifier != nil ? @[FakeSource(identifier)] : @[]);
}
OSStatus FakeSelectSource(TISInputSourceRef source) {
    fakeSelections++;
    fakeSelectedSource = ((__bridge NSDictionary*)source)[(__bridge NSString*)kTISPropertyInputSourceID];
    return noErr;
}
void* FakeSourceProperty(TISInputSourceRef source, CFStringRef key) {
    return (__bridge void*)((__bridge NSDictionary*)source)[(__bridge NSString*)key];
}

int vLanguage = 1;
int vInputType = 0;
int vDiagnostics = 0;
int vUseMacro = 0;
void RequestNewSession(void) {}

#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation SuggestionController
+(void)reset {}
@end
@implementation VOKDiagnostics
+(void)log:(NSString*)category message:(NSString*)message {}
@end

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static void Evaluate(void) {
    [SecureInputMonitor performSelector:NSSelectorFromString(@"evaluate")];
}

static SecureInputHolderRole Role(BOOL front, pid_t pid, BOOL exists, BOOL regular, BOOL system, pid_t frontmost) {
    return [SecureInputHolder roleForSessionInFront:front holderPID:pid processExists:exists regularApp:regular systemProgram:system frontmostPID:frontmost];
}

static void TestRoles(void) {
    printf("-- roles\n");
    //an ordinary app: the one being typed in, or one in the background
    CHECK(Role(YES, 100, YES, YES, NO, 100) == SecureInputHolderRoleFrontApp);
    CHECK(Role(YES, 100, YES, YES, NO, 200) == SecureInputHolderRoleBackgroundApp);
    CHECK(Role(YES, 100, YES, YES, YES, 200) == SecureInputHolderRoleBackgroundApp);   //Safari lives under /System/Applications
    //not an ordinary app: a helper, or part of macOS
    CHECK(Role(YES, 100, YES, NO, NO, 200) == SecureInputHolderRoleHelper);
    CHECK(Role(YES, 100, YES, NO, YES, 200) == SecureInputHolderRoleSystem);
    CHECK(Role(YES, 100, YES, NO, NO, 100) == SecureInputHolderRoleHelper);            //being in front does not make a helper an app
    //the lock screen and another user's session come first, whoever macOS names
    CHECK(Role(NO, 100, YES, YES, NO, 200) == SecureInputHolderRoleLockedSession);
    CHECK(Role(NO, 0, NO, NO, NO, 200) == SecureInputHolderRoleLockedSession);
    //nothing named, or a number that no longer runs
    CHECK(Role(YES, 0, NO, NO, NO, 200) == SecureInputHolderRoleUnknown);
    CHECK(Role(YES, 100, NO, NO, NO, 200) == SecureInputHolderRoleUnknown);
}

static void TestFacts(void) {
    printf("-- facts of real processes\n");
    //this very process: not an app of the Dock, not part of macOS
    SecureInputHolder* me = [SecureInputHolder holderForPID:getpid() sessionInFront:YES frontmostPID:1];
    CHECK(me.pid == getpid() && me.processExists);
    CHECK(me.name.length > 0);
    CHECK(me.path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:me.path]);
    CHECK(me.startDate != nil && fabs([me.startDate timeIntervalSinceNow]) < 3600);
    CHECK(me.parentPID > 1);                                  //started by the shell, not by launchd
    CHECK(me.role == SecureInputHolderRoleHelper || me.role == SecureInputHolderRoleFrontApp || me.role == SecureInputHolderRoleBackgroundApp);

    //a program that is not an app: named after the program, found by its path, started by this process
    NSTask* sleeper = [NSTask launchedTaskWithLaunchPath:@"/bin/sleep" arguments:@[@"120"]];
    pid_t child = sleeper.processIdentifier;
    SecureInputHolder* sleep = [SecureInputHolder holderForPID:child sessionInFront:YES frontmostPID:1];
    CHECK(sleep.processExists);
    CHECK([sleep.name isEqualToString:@"sleep"]);
    CHECK([sleep.path isEqualToString:@"/bin/sleep"]);
    CHECK(sleep.bundleIdentifier == nil);
    CHECK(sleep.role == SecureInputHolderRoleSystem);
    CHECK(sleep.parentPID == getpid());
    CHECK(sleep.parentName.length > 0);
    CHECK([[sleep displayName] isEqualToString:@"sleep"]);
    CHECK([SecureInputHolder holderForPID:child sessionInFront:NO frontmostPID:1].role == SecureInputHolderRoleLockedSession);

    //once it has exited the number names nothing
    [sleeper terminate];
    [sleeper waitUntilExit];
    SecureInputHolder* gone = [SecureInputHolder holderForPID:child sessionInFront:YES frontmostPID:1];
    CHECK(!gone.processExists);
    CHECK(gone.role == SecureInputHolderRoleUnknown);
    CHECK(gone.pid == child);
    CHECK([[gone displayName] isEqualToString:[NSString stringWithFormat:@"tiến trình %d", child]]);

    //nothing named
    SecureInputHolder* none = [SecureInputHolder holderForPID:0 sessionInFront:YES frontmostPID:1];
    CHECK(none.role == SecureInputHolderRoleUnknown && none.pid == 0 && none.name == nil && none.path == nil);
    CHECK([[none displayName] isEqualToString:@"một ứng dụng khác"]);

    //an ordinary app, if the Mac has one running (Finder always is)
    NSRunningApplication* finder = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"].firstObject;
    if (finder != nil) {
        SecureInputHolder* background = [SecureInputHolder holderForPID:finder.processIdentifier sessionInFront:YES frontmostPID:getpid()];
        CHECK(background.role == SecureInputHolderRoleBackgroundApp);
        CHECK([background.bundleIdentifier isEqualToString:@"com.apple.finder"]);
        CHECK([background.path hasSuffix:@".app"]);
        CHECK(background.version.length > 0);
        CHECK(background.icon != nil);
        CHECK(background.name.length > 0);
        SecureInputHolder* front = [SecureInputHolder holderForPID:finder.processIdentifier sessionInFront:YES frontmostPID:finder.processIdentifier];
        CHECK(front.role == SecureInputHolderRoleFrontApp);
        CHECK([front isEqualToHolder:front]);
        CHECK(![front isEqualToHolder:background]);           //the role differs
        CHECK([background isEqualToHolder:[SecureInputHolder holderForPID:finder.processIdentifier sessionInFront:YES frontmostPID:getpid()]]);
    } else {
        printf("   (Finder is not running: the check of an ordinary app is skipped)\n");
    }
    CHECK(![me isEqualToHolder:nil]);
}

//the facts a test hands to the window are not looked up: the same type is used
static void TestInit(void) {
    printf("-- built by hand\n");
    SecureInputHolder* a = [[SecureInputHolder alloc] initWithPID:7 role:SecureInputHolderRoleBackgroundApp processExists:YES name:@"Terminal"
        bundleIdentifier:@"com.apple.Terminal" version:@"2.14 (455)" path:@"/System/Applications/Utilities/Terminal.app"
        startDate:nil parentPID:0 parentName:nil icon:nil];
    SecureInputHolder* b = [[SecureInputHolder alloc] initWithPID:7 role:SecureInputHolderRoleBackgroundApp processExists:YES name:@"Terminal"
        bundleIdentifier:@"com.apple.Terminal" version:@"2.14 (455)" path:@"/System/Applications/Utilities/Terminal.app"
        startDate:[NSDate date] parentPID:0 parentName:nil icon:[NSImage imageNamed:NSImageNameApplicationIcon]];
    CHECK([a isEqualToHolder:b]);                              //start time and icon do not count
    SecureInputHolder* c = [[SecureInputHolder alloc] initWithPID:8 role:SecureInputHolderRoleBackgroundApp processExists:YES name:@"Terminal"
        bundleIdentifier:@"com.apple.Terminal" version:@"2.14 (455)" path:@"/System/Applications/Utilities/Terminal.app"
        startDate:nil parentPID:0 parentName:nil icon:nil];
    CHECK(![a isEqualToHolder:c]);
    CHECK([[a displayName] isEqualToString:@"Terminal"]);
}

static int notifications;

static void TestMonitor(void) {
    printf("-- monitor\n");
    [[NSNotificationCenter defaultCenter] addObserverForName:SecureInputMonitorDidChangeNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification* note) { notifications++; }];
    fakeSecure = NO;
    fakeLocked = NO;
    fakeHolderPID = 0;
    [SecureInputMonitor start];
    Evaluate();
    CHECK([SecureInputMonitor currentHolder] == nil);
    CHECK([SecureInputMonitor lastHolder] == nil);
    CHECK([SecureInputMonitor lastReleaseDate] == nil);

    NSTask* sleeper = [NSTask launchedTaskWithLaunchPath:@"/bin/sleep" arguments:@[@"120"]];
    fakeHolderPID = sleeper.processIdentifier;
    fakeSecure = YES;
    int before = notifications;
    Evaluate();
    SecureInputHolder* holder = [SecureInputMonitor currentHolder];
    CHECK(holder != nil && holder.pid == sleeper.processIdentifier);
    CHECK([holder.name isEqualToString:@"sleep"]);
    CHECK(holder.role == SecureInputHolderRoleSystem);
    CHECK([[SecureInputMonitor holderName] isEqualToString:@"sleep"]);      //a process that is not an app is named too
    CHECK(notifications == before + 1);
    CHECK([SecureInputMonitor isOpenKeyBlind]);
    CHECK([SecureInputMonitor statusDescription] != nil);

    //polling again changes nothing: the window is not told again and again
    Evaluate();
    Evaluate();
    CHECK(notifications == before + 1);
    CHECK([SecureInputMonitor currentHolder] == holder || [[SecureInputMonitor currentHolder] isEqualToHolder:holder]);

    //another process takes over: told again
    NSTask* other = [NSTask launchedTaskWithLaunchPath:@"/bin/sleep" arguments:@[@"121"]];
    fakeHolderPID = other.processIdentifier;
    Evaluate();
    CHECK([SecureInputMonitor currentHolder].pid == other.processIdentifier);
    CHECK(notifications == before + 2);

    //the lock screen: whoever macOS names, it is the session
    fakeLocked = YES;
    Evaluate();
    CHECK([SecureInputMonitor currentHolder].role == SecureInputHolderRoleLockedSession);
    CHECK(notifications == before + 3);
    fakeLocked = NO;
    Evaluate();

    //macOS names nobody
    fakeHolderPID = 0;
    Evaluate();
    CHECK([SecureInputMonitor currentHolder].role == SecureInputHolderRoleUnknown);
    CHECK([SecureInputMonitor holderName] == nil);
    CHECK([[SecureInputMonitor statusDescription] containsString:@"một ứng dụng khác"]);

    //released: nobody holds it, but who did stays known, and when it ended
    fakeHolderPID = other.processIdentifier;
    Evaluate();
    int beforeRelease = notifications;
    NSDate* beforeDate = [NSDate date];
    fakeSecure = NO;
    Evaluate();
    CHECK([SecureInputMonitor currentHolder] == nil);
    CHECK([SecureInputMonitor lastHolder].pid == other.processIdentifier);
    CHECK([SecureInputMonitor lastReleaseDate] != nil && [[SecureInputMonitor lastReleaseDate] timeIntervalSinceDate:beforeDate] >= 0);
    CHECK(notifications == beforeRelease + 1);
    CHECK(![SecureInputMonitor isOpenKeyBlind]);

    [SecureInputMonitor stop];
    CHECK([SecureInputMonitor currentHolder] == nil);
    for (NSTask* task in @[sleeper, other]) {
        [task terminate];
        [task waitUntilExit];
    }
}

static NSDictionary* App(int pid, NSString* name, NSString* bundleID, BOOL secureKeyboardEntry) {
    return @{@"pid": @(pid), @"name": name, @"bundleID": bundleID ?: @"", @"secureKeyboardEntry": @(secureKeyboardEntry)};
}

static NSString* Reason(NSString* bundleID, NSString* name, BOOL secureKeyboardEntry) {
    return [SecureInputSuspect reasonForBundleIdentifier:bundleID name:name secureKeyboardEntry:secureKeyboardEntry];
}

//macOS names one process only. These are the applications that are known to take secure input and may be the one it did not name.
static void TestSuspects(void) {
    printf("-- suspects\n");
    //the one seen on the owner's Mac: its bundle id is the one in the diagnostics log
    CHECK([Reason(@"com.devolutions.remotedesktopmanager", @"Remote Desktop Manager", NO) containsString:@"từ xa"]);
    CHECK([Reason(@"com.microsoft.rdc.macos", @"Windows App", NO) containsString:@"từ xa"]);
    CHECK([Reason(@"com.1password.1password", @"1Password", NO) containsString:@"mật khẩu"]);
    CHECK([Reason(@"com.hicknhacksoftware.MacPass", @"MacPass", NO) containsString:@"mật khẩu"]);
    CHECK([Reason(@"com.vmware.fusion", @"VMware Fusion", NO) containsString:@"máy ảo"]);
    //an application nobody listed, but its name says what it is
    CHECK([Reason(@"com.example.unlisted", @"AnyDesk", NO) containsString:@"từ xa"]);
    //a terminal only counts while its Secure Keyboard Entry is on
    CHECK(Reason(@"com.apple.Terminal", @"Terminal", NO) == nil);
    CHECK([Reason(@"com.apple.Terminal", @"Terminal", YES) containsString:@"Secure Keyboard Entry"]);
    CHECK(Reason(@"com.googlecode.iterm2", @"iTerm2", NO) == nil);
    CHECK([Reason(@"com.googlecode.iterm2", @"iTerm2", YES) containsString:@"Secure Keyboard Entry"]);
    //ordinary applications are not suspects
    CHECK(Reason(@"com.apple.finder", @"Finder", NO) == nil);
    CHECK(Reason(@"com.google.Chrome", @"Google Chrome", NO) == nil);
    CHECK(Reason(nil, nil, NO) == nil);

    NSArray* apps = @[App(10, @"Remote Desktop Manager", @"com.devolutions.remotedesktopmanager", NO), App(11, @"Finder", @"com.apple.finder", NO),
                      App(12, @"1Password", @"com.1password.1password", NO), App(13, @"Terminal", @"com.apple.Terminal", NO),
                      App(14, @"iTerm2", @"com.googlecode.iterm2", YES), App(15, @"AnyDesk", @"com.example.unlisted", NO),
                      App(0, @"Nobody", @"com.devolutions.remotedesktopmanager", NO)];
    NSArray<SecureInputSuspect*>* found = [SecureInputSuspect suspectsAmongApplications:apps excludingPIDs:@[@12]];
    CHECK(found.count == 3);
    if (found.count == 3) {
        CHECK(found[0].pid == 10 && [found[0].name isEqualToString:@"Remote Desktop Manager"]);
        CHECK([found[0].bundleIdentifier isEqualToString:@"com.devolutions.remotedesktopmanager"]);
        CHECK([found[0].reason containsString:@"từ xa"]);
        CHECK(found[1].pid == 14 && found[2].pid == 15);                       //the order of the list is kept
    }
    CHECK([SecureInputSuspect suspectsAmongApplications:apps excludingPIDs:@[@10, @12, @14, @15]].count == 0);

    //the applications that run now come from a provider, so that a test does not depend on the Mac it runs on
    [SecureInputSuspect setApplicationsProvider:^NSArray<NSDictionary*>* { return apps; }];
    CHECK([SecureInputSuspect runningSuspectsExcludingPIDs:@[]].count == 4);
    //whether the terminal that runs under a process number has its Secure Keyboard Entry on
    CHECK([SecureInputSuspect secureKeyboardEntryIsOnForPID:14]);
    CHECK(![SecureInputSuspect secureKeyboardEntryIsOnForPID:13]);
    CHECK(![SecureInputSuspect secureKeyboardEntryIsOnForPID:999]);
    [SecureInputSuspect setApplicationsProvider:nil];
    CHECK([SecureInputSuspect runningSuspectsExcludingPIDs:@[@(getpid())]] != nil);   //what NSWorkspace says, whatever the Mac runs
}

static pid_t SuspectPIDsInclude(SecureInputHolder* holder, pid_t pid) {
    for (SecureInputSuspect* suspect in holder.suspects) {
        if (suspect.pid == pid)
            return pid;
    }
    return 0;
}

//The monitor checks what macOS names against what it can see itself, and keeps who macOS named during one stretch of secure input
static void TestAnnotations(void) {
    printf("-- what the monitor adds to the holder\n");
    //English mode: these checks are about what is added to the holder, the input source that takes over in Vietnamese mode has its
    //own test below. (The input sources are faked: without that a named application in the background switched the REAL input
    //source of the Mac to macOS' Vietnamese one while this test was being written, and a test must not touch the keyboard.)
    vLanguage = 0;
    fakeSecure = NO;
    fakeLocked = NO;
    fakeHolderPID = 0;
    __block NSArray* running = @[App(5000, @"Remote Desktop Manager", @"com.devolutions.remotedesktopmanager", NO), App(5001, @"Finder", @"com.apple.finder", NO)];
    [SecureInputSuspect setApplicationsProvider:^NSArray<NSDictionary*>* { return running; }];
    [SecureInputMonitor start];
    Evaluate();

    NSTask* a = [NSTask launchedTaskWithLaunchPath:@"/bin/sleep" arguments:@[@"130"]];
    NSTask* b = [NSTask launchedTaskWithLaunchPath:@"/bin/sleep" arguments:@[@"131"]];

    //an ordinary application is named: the remote desktop manager that runs is mentioned as a suspect (Finder always runs)
    SecureInputHolder* holder = nil;
    NSRunningApplication* finder = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"].firstObject;
    if (finder != nil) {
        fakeHolderPID = finder.processIdentifier;
        fakeSecure = YES;
        Evaluate();
        holder = [SecureInputMonitor currentHolder];
        CHECK(holder.pid == finder.processIdentifier);
        CHECK(holder.role == SecureInputHolderRoleFrontApp || holder.role == SecureInputHolderRoleBackgroundApp);
        CHECK(holder.suspects.count == 1 && SuspectPIDsInclude(holder, 5000) == 5000);
        CHECK([[SecureInputMonitor statusDescription] containsString:@"Remote Desktop Manager"]);

        //macOS names the application in FRONT, not the one that holds secure input (measured on macOS 15: a process in the background
        //that holds it is never named, and the name follows the front application). So the name only says where the person types
        CHECK([holder.doubt containsString:@"đang ở phía trước"]);
        CHECK([[SecureInputMonitor statusDescription] containsString:@"có thể không đúng"]);

        //confirmed: a terminal with its Secure Keyboard Entry switched on holds secure input itself while it is in front
        running = @[App(finder.processIdentifier, @"Terminal", @"com.apple.Terminal", YES), App(5000, @"Remote Desktop Manager", @"com.devolutions.remotedesktopmanager", NO)];
        Evaluate();
        CHECK([SecureInputMonitor currentHolder].doubt == nil);
        CHECK(![[SecureInputMonitor statusDescription] containsString:@"có thể không đúng"]);
        //the same terminal with the switch off confirms nothing
        running = @[App(finder.processIdentifier, @"Terminal", @"com.apple.Terminal", NO), App(5000, @"Remote Desktop Manager", @"com.devolutions.remotedesktopmanager", NO)];
        Evaluate();
        CHECK([SecureInputMonitor currentHolder].doubt.length > 0);

        //the process macOS names is not listed a second time as a suspect
        running = @[App(finder.processIdentifier, @"Remote Desktop Manager", @"com.devolutions.remotedesktopmanager", NO)];
        Evaluate();
        CHECK([SecureInputMonitor currentHolder].suspects.count == 0);
        running = @[App(5000, @"Remote Desktop Manager", @"com.devolutions.remotedesktopmanager", NO)];
        fakeSecure = NO;
        Evaluate();
    } else {
        printf("   (Finder is not running: the check of an ordinary application is skipped)\n");
    }

    //first one named, a program of macOS: nothing before it; what an application in the background takes is not listed for the lock screen
    fakeHolderPID = a.processIdentifier;
    fakeSecure = YES;
    Evaluate();
    holder = [SecureInputMonitor currentHolder];
    CHECK(holder.pid == a.processIdentifier);
    CHECK(holder.role == SecureInputHolderRoleSystem);
    CHECK(holder.earlierReports.count == 0);
    CHECK(holder.doubt == nil);
    CHECK(holder.suspects.count == 0);

    //macOS names another process while secure input stays on: the first one is remembered, the window is told
    int told = notifications;
    fakeHolderPID = b.processIdentifier;
    Evaluate();
    holder = [SecureInputMonitor currentHolder];
    CHECK(holder.pid == b.processIdentifier);
    CHECK(holder.earlierReports.count == 1 && holder.earlierReports[0].pid == a.processIdentifier);
    CHECK(notifications == told + 1);
    Evaluate();
    Evaluate();
    CHECK(notifications == told + 1);                                          //polling again changes nothing

    //back to the first one: still two processes named, each only once
    fakeHolderPID = a.processIdentifier;
    Evaluate();
    holder = [SecureInputMonitor currentHolder];
    CHECK(holder.pid == a.processIdentifier && holder.earlierReports.count == 1 && holder.earlierReports[0].pid == b.processIdentifier);

    //released: who was named stays in view; a new stretch starts again from nothing
    fakeSecure = NO;
    Evaluate();
    CHECK([SecureInputMonitor currentHolder] == nil);
    CHECK([SecureInputMonitor lastHolder].earlierReports.count == 1);
    fakeHolderPID = b.processIdentifier;
    fakeSecure = YES;
    Evaluate();
    CHECK([SecureInputMonitor currentHolder].pid == b.processIdentifier);
    CHECK([SecureInputMonitor currentHolder].earlierReports.count == 0);

    //macOS names this very process, which holds secure input only while a password field of its own is being edited
    fakeHolderPID = getpid();
    Evaluate();
    holder = [SecureInputMonitor currentHolder];
    CHECK(holder.pid == getpid());
    CHECK(holder.doubt.length > 0);
    CHECK([[SecureInputMonitor statusDescription] containsString:@"có thể không đúng"]);
    CHECK([holder.doubt containsString:holder.name]);
    CHECK(holder.earlierReports.count == 1 && holder.earlierReports[0].pid == b.processIdentifier);

    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(-20000, -20000, 300, 80) styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:NO];
    NSSecureTextField* field = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(10, 10, 200, 24)];
    [window.contentView addSubview:field];
    [window orderBack:nil];
    CHECK([window makeFirstResponder:field]);
    CHECK([window.firstResponder isKindOfClass:[NSTextView class]]);           //the field is being edited: the precondition of this check
    Evaluate();
    CHECK([SecureInputMonitor currentHolder].pid == getpid());
    CHECK([SecureInputMonitor currentHolder].doubt == nil);                    //it does hold it: the name is right
    CHECK(![[SecureInputMonitor statusDescription] containsString:@"có thể không đúng"]);
    [window makeFirstResponder:nil];
    Evaluate();
    CHECK([SecureInputMonitor currentHolder].doubt.length > 0);                //editing is over: macOS' answer is doubtful again
    [window orderOut:nil];

    //an ordinary text field is not a password field
    NSTextField* plain = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 40, 200, 24)];
    NSWindow* plainWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(-20000, -20000, 300, 80) styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered defer:NO];
    [plainWindow.contentView addSubview:plain];
    [plainWindow orderBack:nil];
    [plainWindow makeFirstResponder:plain];
    Evaluate();
    CHECK([SecureInputMonitor currentHolder].doubt.length > 0);
    [plainWindow orderOut:nil];

    [SecureInputMonitor stop];
    [SecureInputSuspect setApplicationsProvider:nil];
    vLanguage = 1;
    for (NSTask* task in @[a, b]) {
        [task terminate];
        [task waitUntilExit];
    }
}

static double fakeNow = 100;

static NSArray<NSRunningApplication*>* RegularApplications(void) {
    NSMutableArray* list = [NSMutableArray array];
    for (NSRunningApplication* app in [NSWorkspace sharedWorkspace].runningApplications) {
        if (app.activationPolicy == NSApplicationActivationPolicyRegular && app.processIdentifier != getpid() && !app.terminated)
            [list addObject:app];
    }
    return list;
}

//lets the main queue deliver what a background queue answered; gives up after three seconds
static void WaitUntil(BOOL (^condition)(void)) {
    for (int i = 0; i < 300 && !condition(); i++)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

//macOS names the application in FRONT. So "an ordinary application that is not in front holds secure input", which makes macOS' Vietnamese
//input source take over, is true only when the name is that of an application that is not in front for good: for a moment after the person
//switched to another application macOS still names the one before, and the input source must not move for that.
static void TestFallbackDelay(void) {
    printf("-- macOS' input source takes over only for a holder that stays\n");
    pid_t front = [NSWorkspace sharedWorkspace].frontmostApplication.processIdentifier;
    NSRunningApplication* background = nil;
    for (NSRunningApplication* app in RegularApplications()) {
        if (app.processIdentifier != front) {
            background = app;
            break;
        }
    }
    if (front <= 0 || background == nil) {
        printf("   (no application in front and a second ordinary one: skipped)\n");
        return;
    }
    vLanguage = 1;
    vInputType = 0;
    fakeSecure = NO;
    fakeLocked = NO;
    fakeHolderPID = 0;
    fakeSelectedSource = @"com.apple.keylayout.ABC";
    fakeSelections = 0;
    double d = SecureInputFallbackDelay;
    fakeNow = 100;
    [SecureInputMonitor setClockForTesting:^NSTimeInterval { return fakeNow; }];
    [SecureInputSuspect setApplicationsProvider:^NSArray<NSDictionary*>* { return @[]; }];
    [SecureInputMonitor start];
    Evaluate();
    CHECK(d >= 0.5 && d <= 3);                                                  //long enough for the lag of a switch, short for a real holder

    //macOS names an ordinary application that is not in front: not yet
    fakeSecure = YES;
    fakeHolderPID = background.processIdentifier;
    Evaluate();
    CHECK(![SecureInputMonitor isFallbackActive] && fakeSelections == 0);
    fakeNow = 100 + 0.8 * d;
    Evaluate();
    CHECK(![SecureInputMonitor isFallbackActive] && fakeSelections == 0);

    //the name catches up with the application in front (what it does within a moment of a switch): nothing was handed over...
    fakeHolderPID = front;
    fakeNow = 100 + 0.9 * d;
    Evaluate();
    CHECK(![SecureInputMonitor isFallbackActive] && fakeSelections == 0);
    //...and the wait starts again when the other name comes back, the time before does not count
    fakeHolderPID = background.processIdentifier;
    fakeNow = 100 + 1.0 * d;
    Evaluate();
    fakeNow = 100 + 1.9 * d;
    Evaluate();
    CHECK(![SecureInputMonitor isFallbackActive] && fakeSelections == 0);

    //named for the whole delay without a break: macOS' Vietnamese source takes over
    fakeNow = 100 + 2.0 * d;
    Evaluate();
    CHECK([SecureInputMonitor isFallbackActive]);
    CHECK(fakeSelections == 1 && [fakeSelectedSource isEqualToString:@"com.apple.inputmethod.VietnameseIM.VietnameseTelex"]);

    //it gives the input source back at once when the name is that of the application in front again
    fakeHolderPID = front;
    fakeNow = 100 + 2.1 * d;
    Evaluate();
    CHECK(![SecureInputMonitor isFallbackActive]);
    CHECK(fakeSelections == 2 && [fakeSelectedSource isEqualToString:@"com.apple.keylayout.ABC"]);

    //and when secure input is released
    fakeHolderPID = background.processIdentifier;
    fakeNow = 100 + 3.0 * d;
    Evaluate();
    fakeNow = 100 + 4.0 * d;
    Evaluate();
    CHECK([SecureInputMonitor isFallbackActive]);
    fakeSecure = NO;
    Evaluate();
    CHECK(![SecureInputMonitor isFallbackActive]);
    CHECK([fakeSelectedSource isEqualToString:@"com.apple.keylayout.ABC"]);

    [SecureInputMonitor stop];
    [SecureInputMonitor setClockForTesting:nil];
    [SecureInputSuspect setApplicationsProvider:nil];
}

//A password field in the application macOS names confirms that it is the one holding secure input; asked off the main thread, once each
//time macOS names another application
static void TestFieldConfirmation(void) {
    printf("-- a password field in the application macOS names confirms the name\n");
    NSArray<NSRunningApplication*>* apps = RegularApplications();
    if (apps.count < 2) {
        printf("   (two ordinary applications are needed: skipped)\n");
        return;
    }
    pid_t first = apps[0].processIdentifier, second = apps[1].processIdentifier;
    vLanguage = 0;
    fakeSecure = NO;
    fakeLocked = NO;
    fakeHolderPID = 0;
    fakeNow = 200;
    [SecureInputMonitor setClockForTesting:^NSTimeInterval { return fakeNow; }];
    [SecureInputSuspect setApplicationsProvider:^NSArray<NSDictionary*>* { return @[]; }];

    NSMutableArray<NSNumber*>* asked = [NSMutableArray array];
    NSMutableDictionary<NSNumber*, NSNumber*>* verdicts = [NSMutableDictionary dictionary];
    __block BOOL askedOnMainThread = NO;
    [SecureInputMonitor setFieldVerdictProvider:^SensitiveFieldVerdict(pid_t pid) {
        @synchronized (asked) {
            [asked addObject:@(pid)];
            if ([NSThread isMainThread])
                askedOnMainThread = YES;
            NSNumber* verdict = verdicts[@(pid)];
            return verdict != nil ? (SensitiveFieldVerdict)verdict.integerValue : SensitiveFieldNormal;
        }
    }];
    NSUInteger (^askedCount)(void) = ^NSUInteger { @synchronized (asked) { return asked.count; } };
    verdicts[@(second)] = @(SensitiveFieldSensitive);

    [SecureInputMonitor start];
    Evaluate();

    //an ordinary application is named: its name is not confirmed while the field is looked at, nor when it is an ordinary one
    fakeSecure = YES;
    fakeHolderPID = first;
    Evaluate();
    CHECK([SecureInputMonitor currentHolder].doubt.length > 0);
    WaitUntil(^BOOL { return askedCount() == 1; });
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    CHECK(askedCount() == 1 && [asked.firstObject intValue] == first);
    CHECK(!askedOnMainThread);                                                  //a stalled application must never stall the main thread
    CHECK([SecureInputMonitor currentHolder].doubt.length > 0);
    //polling again does not ask again
    Evaluate();
    Evaluate();
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    CHECK(askedCount() == 1);

    //another application is named, with a password field in it: confirmed, and the window is told
    int told = notifications;
    fakeHolderPID = second;
    Evaluate();
    CHECK([SecureInputMonitor currentHolder].doubt.length > 0);                 //not before the answer
    WaitUntil(^BOOL { return [SecureInputMonitor currentHolder].doubt == nil; });
    CHECK(askedCount() == 2 && [SecureInputMonitor currentHolder].pid == second);
    CHECK([SecureInputMonitor currentHolder].doubt == nil);
    CHECK(![[SecureInputMonitor statusDescription] containsString:@"có thể không đúng"]);
    CHECK([SecureInputMonitor currentHolder].earlierReports.count == 1);        //that secure input stayed on across the switch is still said
    CHECK(notifications > told);

    //back to the first: asked again, and what was said about the other one does not carry over
    fakeHolderPID = first;
    Evaluate();
    CHECK([SecureInputMonitor currentHolder].doubt.length > 0);
    WaitUntil(^BOOL { return askedCount() == 3; });
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    CHECK(askedCount() == 3 && [SecureInputMonitor currentHolder].doubt.length > 0);

    //a program of macOS is not asked about: the lock screen and the password prompts are confirmed in their own way
    NSTask* system = [NSTask launchedTaskWithLaunchPath:@"/bin/sleep" arguments:@[@"140"]];
    fakeHolderPID = system.processIdentifier;
    Evaluate();
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    CHECK(askedCount() == 3 && [SecureInputMonitor currentHolder].doubt == nil);
    [system terminate];
    [system waitUntilExit];
    //it has exited and macOS still names it: a number that names nothing is not "the application in front". Nobody is asked about it, and
    //the advice stays that of a process that is gone (the timer of the monitor may also run while waiting for the exit above)
    Evaluate();
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    CHECK(askedCount() == 3);
    CHECK([SecureInputMonitor currentHolder].pid == system.processIdentifier && ![SecureInputMonitor currentHolder].processExists);
    CHECK([SecureInputMonitor currentHolder].doubt == nil);

    //a new time secure input is on starts again: what was answered before is forgotten
    fakeSecure = NO;
    Evaluate();
    fakeSecure = YES;
    fakeHolderPID = second;
    Evaluate();
    CHECK([SecureInputMonitor currentHolder].doubt.length > 0);
    WaitUntil(^BOOL { return askedCount() == 4; });
    WaitUntil(^BOOL { return [SecureInputMonitor currentHolder].doubt == nil; });
    CHECK(askedCount() == 4 && [SecureInputMonitor currentHolder].doubt == nil);

    //nothing to look with: nothing is confirmed
    fakeSecure = NO;
    Evaluate();
    [SecureInputMonitor setFieldVerdictProvider:nil];
    fakeSecure = YES;
    fakeHolderPID = second;
    Evaluate();
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    CHECK(askedCount() == 4 && [SecureInputMonitor currentHolder].doubt.length > 0);

    [SecureInputMonitor stop];
    [SecureInputMonitor setClockForTesting:nil];
    [SecureInputSuspect setApplicationsProvider:nil];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        TestRoles();
        TestFacts();
        TestInit();
        TestMonitor();
        TestSuspects();
        TestAnnotations();
        TestFallbackDelay();
        TestFieldConfirmation();
        printf(failures == 0 ? "secure_input_holder_test: ALL OK\n" : "secure_input_holder_test: %d FAILED\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
