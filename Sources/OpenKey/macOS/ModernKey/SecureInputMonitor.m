//
//  SecureInputMonitor.m
//  ModernKey
//
//  See SecureInputMonitor.h
//

#import "SecureInputMonitor.h"
#import <Carbon/Carbon.h>
#import "Diagnostics.h"
#import "SuggestionController.h"

extern int vLanguage;
extern int vInputType;
extern void RequestNewSession(void);

NSString* const SecureInputMonitorDidChangeNotification = @"SecureInputMonitorDidChangeNotification";

//hidden switch, off with: defaults write vn.io.lssoft.vopenkey vSecureInputFallback -int 0
static NSString* const kFallbackKey = @"vSecureInputFallback";

//macOS' own Vietnamese input sources
static NSString* const kMacTelex = @"com.apple.inputmethod.VietnameseIM.VietnameseTelex";
static NSString* const kMacSimpleTelex = @"com.apple.inputmethod.VietnameseIM.VietnameseSimpleTelex";
static NSString* const kMacVNI = @"com.apple.inputmethod.VietnameseIM.VietnameseVNI";

//not public API, but the keys every tool that reports "secure input is on" relies on
static NSString* const kSecureInputPIDKey = @"kCGSSessionSecureInputPID";
static NSString* const kScreenIsLockedKey = @"CGSSessionScreenIsLocked";

static NSTimer* _timer;
static id _activationObserver;
static BOOL _secure;
static BOOL _active;                        //macOS' input source is standing in for OpenKey
static TISInputSourceRef _savedSource;      //what to give back once secure input is released
static TISInputSourceRef _fallbackSource;   //what we switched to
static BOOL _noSourceAvailable;
static NSString* _description;
static NSString* _holderName;
static SecureInputHolder* _holder;
static SecureInputHolder* _lastHolder;
static NSDate* _lastReleaseDate;
static pid_t _lastOtherFrontPID;            //the app the person was typing in, not counting VOpenKey AI's own windows
static BOOL _publishedSecure, _publishedActive;
static SecureInputHolder* _publishedHolder;
static NSMutableArray<SecureInputHolder*>* _period;   //every process macOS named during the current (or the last) time secure input was on, oldest first

static NSTimeInterval (^sClock)(void);                //a test's clock
static NSTimeInterval _fallbackWantedSince = -1;      //since when macOS' input source has been wanted without a break, -1 when it is not wanted
static SecureInputFieldVerdictProvider sFieldVerdictProvider;
static NSMutableDictionary<NSNumber*, NSNumber*>* _fieldVerdicts;   //what was found in the field of an application macOS named, this time secure input is on
static pid_t _fieldQueryPID;                          //the application whose field was asked about last: asked again only when macOS names another
static NSUInteger _stretch;                           //counts the times secure input went on: an answer that comes late is for an earlier one
static dispatch_queue_t _fieldQueue;                  //where the field of another application is looked into, never on the main thread

static NSTimeInterval Now(void) {
    return sClock != nil ? sClock() : [NSProcessInfo processInfo].systemUptime;
}

//macOS names one process only, and it is not always the right one: it has named VOpenKey AI itself while a remote desktop manager held
//secure input. This process holds secure input only while a password field of its own is being edited (AppKit turns it on when a
//NSSecureTextField starts editing and off when it stops, and VOpenKey AI has no other way to take it): so when macOS names it and no such
//field is being edited, the name is wrong.
static BOOL OwnProcessEditsSecureField(void) {
    for (NSWindow* window in [NSApp windows]) {
        NSResponder* responder = window.firstResponder;
        if ([responder isKindOfClass:[NSTextView class]] && ((NSTextView*)responder).fieldEditor &&
            [((NSTextView*)responder).delegate isKindOfClass:[NSSecureTextField class]])
            return YES;
    }
    return NO;
}

//Is the app being typed in the one that holds secure input? That is what a focused password field or Terminal's
//Secure Keyboard Entry look like, and typing there with macOS' Vietnamese input source would also convert the
//password. System helpers (SecurityAgent, loginwindow...) show password prompts and cannot be told apart from an
//app that forgot to release secure input, the lock screen and another user's session are not ours to touch either.
//Only an ordinary app in the background, which the user is not typing in, qualifies for the fallback.
static BOOL HolderIsTheAppBeingTypedIn(BOOL sessionInFront, pid_t holderPID, BOOL holderIsRegularApp, pid_t frontmostPID) {
    return !sessionInFront || holderPID <= 0 || !holderIsRegularApp || holderPID == frontmostPID;
}

static NSString* SourceID(TISInputSourceRef source) {
    return source != NULL ? (__bridge NSString*)TISGetInputSourceProperty(source, kTISPropertyInputSourceID) : nil;
}

static BOOL IsKeyboardLayout(TISInputSourceRef source) {
    CFStringRef type = (CFStringRef)TISGetInputSourceProperty(source, kTISPropertyInputSourceType);
    return type != NULL && CFEqual(type, kTISTypeKeyboardLayout);
}

//macOS' Vietnamese input source closest to the way OpenKey is typing, NULL if the user has not enabled one
static TISInputSourceRef CopyMacVietnameseSource(void) {
    NSArray* candidates;
    switch (vInputType) {
        case 1:  candidates = @[kMacVNI]; break;
        case 2:
        case 3:  candidates = @[kMacSimpleTelex, kMacTelex]; break;
        default: candidates = @[kMacTelex, kMacSimpleTelex]; break;
    }
    for (NSString* sourceID in candidates) {
        NSDictionary* filter = @{(__bridge NSString*)kTISPropertyInputSourceID: sourceID};
        CFArrayRef list = TISCreateInputSourceList((__bridge CFDictionaryRef)filter, false); //enabled sources only
        if (list == NULL)
            continue;
        TISInputSourceRef found = NULL;
        if (CFArrayGetCount(list) > 0) {
            TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(list, 0);
            CFBooleanRef selectable = (CFBooleanRef)TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable);
            if (selectable != NULL && CFBooleanGetValue(selectable))
                found = (TISInputSourceRef)CFRetain(source);
        }
        CFRelease(list);
        if (found != NULL)
            return found;
    }
    return NULL;
}

@implementation SecureInputMonitor

+(void)initialize {
    if (self == [SecureInputMonitor class])
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{kFallbackKey: @YES}];
}

const NSTimeInterval SecureInputFallbackDelay = 1.0;

+(void)setFieldVerdictProvider:(SecureInputFieldVerdictProvider)provider {
    sFieldVerdictProvider = [provider copy];
}

+(void)setClockForTesting:(NSTimeInterval (^)(void))clock {
    sClock = [clock copy];
}

+(BOOL)isOpenKeyBlind {
    return _secure && !_active;
}

+(BOOL)isFallbackActive {
    return _active;
}

+(NSString*)statusDescription {
    return _description;
}

+(NSString*)holderName {
    return _holderName;
}

+(SecureInputHolder*)currentHolder {
    return _holder;
}

+(SecureInputHolder*)lastHolder {
    return _lastHolder;
}

+(NSDate*)lastReleaseDate {
    return _lastReleaseDate;
}

//Everything here runs on the main thread, the same one the event tap callback runs on.
+(void)start {
    if (_timer != nil)
        return;

    //secure input can only be polled, macOS does not tell when it changes
    _timer = [NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(evaluate) userInfo:nil repeats:YES];
    _timer.tolerance = 0.1;
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];

    //what matters is whether the app being typed in is the one holding secure input, so look again on every focus change
    _activationObserver = [[[NSWorkspace sharedWorkspace] notificationCenter]
                           addObserverForName:NSWorkspaceDidActivateApplicationNotification
                           object:nil
                           queue:[NSOperationQueue mainQueue]
                           usingBlock:^(NSNotification* note) {
        [self evaluate];
    }];

    [self evaluate];
}

+(void)stop {
    if (_timer == nil)
        return;
    [_timer invalidate];
    _timer = nil;
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:_activationObserver];
    _activationObserver = nil;

    if (_active)
        [self disengage];
    _secure = NO;
    _noSourceAvailable = NO;
    _holder = nil;
    _fallbackWantedSince = -1;
    _fieldVerdicts = nil;
    _fieldQueryPID = 0;
    _stretch++;                                 //an answer still on its way is for a time that is over
    [self publishDescription:nil];
}

+(void)secureInputMayHaveEnded {
    //not worth slowing down the event tap callback for
    dispatch_async(dispatch_get_main_queue(), ^{
        [self evaluate];
    });
}

+(void)evaluate {
    if (_timer == nil)
        return;

    //VOpenKey AI's own windows (the one that lists the holder of secure input) take the focus away from the app the person
    //was typing in, but that app is the one the holder is compared with
    pid_t frontmostPID = [NSWorkspace sharedWorkspace].frontmostApplication.processIdentifier;
    if (frontmostPID != getpid())
        _lastOtherFrontPID = frontmostPID;

    BOOL secure = IsSecureEventInputEnabled();
    if (secure != _secure) {
        _secure = secure;
        _noSourceAvailable = NO;
        if (!secure)
            _lastReleaseDate = [NSDate date];
        else {
            _period = [NSMutableArray array];       //a new time secure input is on: nobody has been named yet,
            _fieldVerdicts = [NSMutableDictionary dictionary];   //and nothing is known about the fields
            _fieldQueryPID = 0;
            _stretch++;
        }
        //keys typed while macOS hides them were never seen, what OpenKey remembers of the current word is stale
        RequestNewSession();
        //and the suggestion bar of the field before would stay up over a password field, which no key can take away any more
        [SuggestionController reset];
    }

    NSString* holderName = nil;
    SecureInputHolder* snapshot = nil;
    BOOL wantFallback = NO;
    if (secure) {
        NSDictionary* session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
        pid_t holderPID = [session[kSecureInputPIDKey] intValue];
        NSRunningApplication* holder = holderPID > 0 ? [NSRunningApplication runningApplicationWithProcessIdentifier:holderPID] : nil;

        NSNumber* onConsole = session[(__bridge NSString*)kCGSessionOnConsoleKey];
        BOOL sessionInFront = (onConsole == nil || onConsole.boolValue) && ![session[kScreenIsLockedKey] boolValue];
        SecureInputHolder* named = [SecureInputHolder holderForPID:holderPID sessionInFront:sessionInFront frontmostPID:_lastOtherFrontPID];
        snapshot = [self checked:named];
        //not only apps have a name: a process that is not one is named by the program it runs
        holderName = holder.localizedName ?: snapshot.name;
        //NSApplicationActivationPolicyRegular is 0, which is also what a nil holder answers
        BOOL holderIsRegularApp = holder != nil && holder.activationPolicy == NSApplicationActivationPolicyRegular;

        //nothing to hand over while OpenKey is in English mode
        wantFallback = vLanguage == 1 && [[NSUserDefaults standardUserDefaults] boolForKey:kFallbackKey] &&
            !HolderIsTheAppBeingTypedIn(sessionInFront, holderPID, holderIsRegularApp,
                                        [NSWorkspace sharedWorkspace].frontmostApplication.processIdentifier);
    }

    //macOS names the application in front, so "an ordinary application that is not in front holds it" is what a switch of the front
    //application looks like for a moment (the name still is the one before): macOS' input source takes over only once that has
    //stayed true for SecureInputFallbackDelay, and gives the input source back at once when it stops being true
    NSTimeInterval now = Now();
    if (!wantFallback)
        _fallbackWantedSince = -1;
    else if (_fallbackWantedSince < 0)
        _fallbackWantedSince = now;
    if (wantFallback && !_active && now - _fallbackWantedSince >= SecureInputFallbackDelay)
        [self engage];
    else if (!wantFallback && _active)
        [self disengage];

    static BOOL loggedSecure = NO;
    if (secure != loggedSecure) {
        loggedSecure = secure;
        VOKDiag(@"secure", @"secure input %@ (holder: %@, VOpenKey AI in Vietnamese: %d, macOS' Vietnamese source stands in: %d)",
                secure ? @"ON" : @"released", holderName ?: @"none/unknown", vLanguage == 1, _active);
    }
    _holderName = secure ? holderName : nil;
    _holder = snapshot;
    if (snapshot != nil)
        _lastHolder = snapshot;
    NSString* description = nil;
    if (secure) {
        NSString* by = holderName != nil ? holderName : @"một ứng dụng khác";
        if (snapshot.doubt.length > 0)
            by = [by stringByAppendingString:@" (theo macOS, có thể không đúng)"];
        if (_active) {
            description = [NSString stringWithFormat:@"Secure Input đang bật bởi %@: đang dùng bộ gõ Vietnamese của macOS thay cho OpenKey.", by];
        } else if (vLanguage != 1) {
            description = [NSString stringWithFormat:@"Secure Input đang bật bởi %@.", by];
        } else {
            description = [NSString stringWithFormat:@"Secure Input đang bật bởi %@: macOS không cho OpenKey đọc phím nên tạm chuyển sang tiếng Anh.", by];
            if (_noSourceAvailable)
                description = [description stringByAppendingString:@"\nHãy bật bộ gõ Vietnamese của macOS (Cài đặt hệ thống > Bàn phím > Nguồn đầu vào) để OpenKey tự chuyển sang khi cần."];
        }
        if (snapshot.suspects.count > 0)
            description = [description stringByAppendingFormat:@"\nCũng đang chạy và hay giữ Secure Input: %@.",
                           [[snapshot.suspects valueForKey:@"name"] componentsJoinedByString:@", "]];
    }
    [self publishDescription:description];
}

//Looks into the field that has the keyboard in the application macOS names, off the main thread: a password field there confirms that
//the application holds secure input (what macOS names is the application in front, which says nothing about who holds it). Asked once
//each time macOS names another application; the answer comes back to the main thread and the situation is looked at again.
+(void)askFieldOf:(pid_t)pid {
    SecureInputFieldVerdictProvider provider = sFieldVerdictProvider;
    if (provider == nil || pid <= 0 || pid == _fieldQueryPID)
        return;
    _fieldQueryPID = pid;
    [_fieldVerdicts removeObjectForKey:@(pid)];         //what was found there last time no longer counts
    NSUInteger stretch = _stretch;
    if (_fieldQueue == nil)
        _fieldQueue = dispatch_queue_create("vn.io.lssoft.vopenkey.secureinput.field", DISPATCH_QUEUE_SERIAL);
    dispatch_async(_fieldQueue, ^{
        SensitiveFieldVerdict verdict = provider(pid);
        dispatch_async(dispatch_get_main_queue(), ^{
            //the answer is for the application that was named then: not for another one, nor for an earlier time secure input was on
            if (stretch != _stretch || pid != _fieldQueryPID || !_secure)
                return;
            _fieldVerdicts[@(pid)] = @(verdict);
            [self evaluate];
        });
    });
}

//What macOS named, checked against what can be seen from here: whom it named before during this time secure input has been on,
//whether the process it names could be holding it at all, and which other running applications are known to take it.
+(SecureInputHolder*)checked:(SecureInputHolder*)named {
    if (_period == nil)
        _period = [NSMutableArray array];
    BOOL first = NO;
    NSMutableArray<SecureInputHolder*>* earlier = [NSMutableArray array];
    if (named.pid > 0) {
        BOOL known = NO;
        for (SecureInputHolder* before in _period) {
            if (before.pid == named.pid)
                known = YES;
            else
                [earlier addObject:before];
        }
        if (!known) {
            [_period addObject:named];
            first = YES;
        }
    }

    //What macOS names is the application in FRONT, not the one that holds secure input: measured on macOS 15 with a process in the
    //background holding it, the name was the front application, followed it to the next one when the person switched, and the
    //process that really held it was never named. The name is a fact only where something confirms it.
    NSString* doubt = nil;
    if (named.pid == getpid()) {
        if (!OwnProcessEditsSecureField()) {
            //this process holds it only while a password field of its own is being edited: none is, so macOS named it as the one in front
            doubt = [NSString stringWithFormat:@"macOS báo chính %@ giữ Secure Input, nhưng %@ không có ô mật khẩu nào đang mở nên không phải nó. "
                     "macOS chỉ báo ứng dụng đang ở phía trước chứ không báo ứng dụng giữ Secure Input: ứng dụng giữ thật là ứng dụng khác, thường là một ứng dụng chạy nền.",
                     named.displayName, named.displayName];
        }
    } else if (named.pid > 0 && named.processExists && named.role != SecureInputHolderRoleSystem &&
               named.role != SecureInputHolderRoleLockedSession && ![SecureInputSuspect secureKeyboardEntryIsOnForPID:named.pid]) {
        //(a number that names no process any more is not the application in front: it is stale, the window says so on its own)
        //the lock screen and the password prompts of macOS hold it while they are in front, and so does a terminal whose Secure
        //Keyboard Entry is on: those are confirmed. For any other application the name only says where the person types, unless the
        //field that has the keyboard in it is a password field: that is asked once each time macOS names another application.
        [self askFieldOf:named.pid];
        NSNumber* found = _fieldVerdicts[@(named.pid)];
        BOOL passwordField = found != nil && found.integerValue == SensitiveFieldSensitive;
        if (!passwordField) {
            doubt = [NSString stringWithFormat:@"macOS chỉ báo ứng dụng đang ở phía trước chứ không báo ứng dụng giữ Secure Input: %@ chỉ chắc chắn là nơi bạn đang gõ. "
                     "Nếu con trỏ không ở ô mật khẩu của %@ thì ứng dụng giữ thật là ứng dụng khác, thường là một ứng dụng chạy nền.",
                     named.displayName, named.displayName];
        }
    }

    //the lock screen and the password prompts of macOS are not what an application that is running in the background takes
    NSArray<SecureInputSuspect*>* suspects = @[];
    if (named.role != SecureInputHolderRoleSystem && named.role != SecureInputHolderRoleLockedSession)
        suspects = [SecureInputSuspect runningSuspectsExcludingPIDs:@[@(named.pid), @(getpid())]];

    SecureInputHolder* checked = [named holderWithDoubt:doubt earlierReports:earlier suspects:suspects];
    if (first) {
        //the evidence for the next time the name is wrong: who macOS named, who was in front, whom it named before, what else could be it
        VOKDiag(@"secure", @"macOS names %@ (pid %d) as the holder; in front: %@; named before in this stretch: %@; also running and known to take it: %@%@",
                named.displayName, named.pid, [NSWorkspace sharedWorkspace].frontmostApplication.bundleIdentifier ?: @"?",
                earlier.count > 0 ? [[earlier valueForKey:@"displayName"] componentsJoinedByString:@", "] : @"nobody",
                suspects.count > 0 ? [[suspects valueForKey:@"name"] componentsJoinedByString:@", "] : @"none",
                doubt != nil ? @"; name unconfirmed (macOS names the application in front, not the holder)" : @"");
    }
    return checked;
}

+(void)engage {
    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    if (current == NULL)
        return;
    //OpenKey is the one converting keys only while a plain keyboard layout (ABC, US...) is selected; if an input
    //method such as macOS' own is selected already, there is nothing to hand over
    if (!IsKeyboardLayout(current)) {
        CFRelease(current);
        return;
    }

    TISInputSourceRef target = CopyMacVietnameseSource();
    if (target == NULL) {
        CFRelease(current);
        if (!_noSourceAvailable) {
            _noSourceAvailable = YES;
            NSLog(@"Secure input is on but no macOS Vietnamese input source is enabled, nothing to switch to");
        }
        return;
    }

    OSStatus status = TISSelectInputSource(target);
    if (status != noErr) {
        NSLog(@"Could not switch to %@ (error %d)", SourceID(target), (int)status);
        CFRelease(current);
        CFRelease(target);
        return;
    }

    _savedSource = current;
    _fallbackSource = target;
    _active = YES;
    NSLog(@"Secure input is on, using %@ until it is released", SourceID(target));
    RequestNewSession();
}

+(void)disengage {
    //if the user picked another input source in the meantime, leave their choice alone
    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    if (current != NULL) {
        if ([SourceID(current) isEqualToString:SourceID(_fallbackSource)])
            TISSelectInputSource(_savedSource);
        CFRelease(current);
    }
    NSLog(@"Back to %@", SourceID(_savedSource));

    CFRelease(_savedSource);
    CFRelease(_fallbackSource);
    _savedSource = NULL;
    _fallbackSource = NULL;
    _active = NO;
    RequestNewSession();
}

+(void)publishDescription:(NSString*)description {
    BOOL sameDescription = description == _description || [description isEqualToString:_description];
    BOOL sameHolder = _holder == _publishedHolder || [_holder isEqualToHolder:_publishedHolder];
    if (_secure == _publishedSecure && _active == _publishedActive && sameDescription && sameHolder)
        return;
    _publishedSecure = _secure;
    _publishedActive = _active;
    _publishedHolder = _holder;
    _description = description;
    [[NSNotificationCenter defaultCenter] postNotificationName:SecureInputMonitorDidChangeNotification object:self];
}

@end
