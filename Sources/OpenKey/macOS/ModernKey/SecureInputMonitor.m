//
//  SecureInputMonitor.m
//  ModernKey
//
//  See SecureInputMonitor.h
//

#import "SecureInputMonitor.h"
#import <Carbon/Carbon.h>
#import "Diagnostics.h"

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
static BOOL _publishedSecure, _publishedActive;

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

    BOOL secure = IsSecureEventInputEnabled();
    if (secure != _secure) {
        _secure = secure;
        _noSourceAvailable = NO;
        //keys typed while macOS hides them were never seen, what OpenKey remembers of the current word is stale
        RequestNewSession();
    }

    NSString* holderName = nil;
    BOOL wantFallback = NO;
    if (secure) {
        NSDictionary* session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
        pid_t holderPID = [session[kSecureInputPIDKey] intValue];
        NSRunningApplication* holder = holderPID > 0 ? [NSRunningApplication runningApplicationWithProcessIdentifier:holderPID] : nil;
        holderName = holder.localizedName;

        NSNumber* onConsole = session[(__bridge NSString*)kCGSessionOnConsoleKey];
        BOOL sessionInFront = (onConsole == nil || onConsole.boolValue) && ![session[kScreenIsLockedKey] boolValue];
        //NSApplicationActivationPolicyRegular is 0, which is also what a nil holder answers
        BOOL holderIsRegularApp = holder != nil && holder.activationPolicy == NSApplicationActivationPolicyRegular;

        //nothing to hand over while OpenKey is in English mode
        wantFallback = vLanguage == 1 && [[NSUserDefaults standardUserDefaults] boolForKey:kFallbackKey] &&
            !HolderIsTheAppBeingTypedIn(sessionInFront, holderPID, holderIsRegularApp,
                                        [NSWorkspace sharedWorkspace].frontmostApplication.processIdentifier);
    }

    if (wantFallback && !_active)
        [self engage];
    else if (!wantFallback && _active)
        [self disengage];

    static BOOL loggedSecure = NO;
    if (secure != loggedSecure) {
        loggedSecure = secure;
        VOKDiag(@"secure", @"secure input %@ (holder: %@, VOpenKey in Vietnamese: %d, macOS' Vietnamese source stands in: %d)",
                secure ? @"ON" : @"released", holderName ?: @"none/unknown", vLanguage == 1, _active);
    }
    _holderName = secure ? holderName : nil;
    NSString* description = nil;
    if (secure) {
        NSString* by = holderName != nil ? holderName : @"một ứng dụng khác";
        if (_active) {
            description = [NSString stringWithFormat:@"Secure Input đang bật bởi %@: đang dùng bộ gõ Vietnamese của macOS thay cho OpenKey.", by];
        } else if (vLanguage != 1) {
            description = [NSString stringWithFormat:@"Secure Input đang bật bởi %@.", by];
        } else {
            description = [NSString stringWithFormat:@"Secure Input đang bật bởi %@: macOS không cho OpenKey đọc phím nên tạm chuyển sang tiếng Anh.", by];
            if (_noSourceAvailable)
                description = [description stringByAppendingString:@"\nHãy bật bộ gõ Vietnamese của macOS (Cài đặt hệ thống > Bàn phím > Nguồn đầu vào) để OpenKey tự chuyển sang khi cần."];
        }
    }
    [self publishDescription:description];
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
    if (_secure == _publishedSecure && _active == _publishedActive && sameDescription)
        return;
    _publishedSecure = _secure;
    _publishedActive = _active;
    _description = description;
    [[NSNotificationCenter defaultCenter] postNotificationName:SecureInputMonitorDidChangeNotification object:self];
}

@end
