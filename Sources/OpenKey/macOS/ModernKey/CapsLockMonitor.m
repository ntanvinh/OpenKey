//
//  CapsLockMonitor.m
//  VOpenKey
//

#import "CapsLockMonitor.h"
#import "CapsLockToast.h"

NSString* const CapsLockMonitorDidChangeNotification = @"CapsLockMonitorDidChangeNotification";
NSString* const CapsLockToastDefaultsKey = @"CapsLockToast";

//a safety net for what the monitors of events do not see; the look is one cheap call
static const NSTimeInterval kPollInterval = 0.3;

static BOOL sOn;
static BOOL sStarted;
static id sGlobalMonitor;
static id sLocalMonitor;
static NSTimer* sTimer;

//the real keyboard; the tests build this file with -DVOKReadCapsLock=<their stand-in> and define that function
#ifdef VOKReadCapsLock
BOOL VOKReadCapsLock(void);
#else
static BOOL VOKReadCapsLock(void) {
    return ([NSEvent modifierFlags] & NSEventModifierFlagCapsLock) != 0;
}
#endif

@implementation CapsLockMonitor

+(void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{CapsLockToastDefaultsKey: @YES}];
}

+(BOOL)isOn {
    return sOn;
}

+(void)start {
    if (sStarted)
        return;
    sStarted = YES;
    [self registerDefaults];

    //what is on now is not news: no toast for it, but the icon has to know
    sOn = VOKReadCapsLock();
    [[NSNotificationCenter defaultCenter] postNotificationName:CapsLockMonitorDidChangeNotification object:nil];

    sGlobalMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged handler:^(NSEvent* event) {
        [CapsLockMonitor check];
    }];
    //the events of our own windows do not reach a global monitor
    sLocalMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged handler:^NSEvent*(NSEvent* event) {
        [CapsLockMonitor check];
        return event;
    }];
    sTimer = [NSTimer scheduledTimerWithTimeInterval:kPollInterval repeats:YES block:^(NSTimer* timer) {
        [CapsLockMonitor check];
    }];
    sTimer.tolerance = kPollInterval / 3;
}

+(void)stop {
    if (!sStarted)
        return;
    sStarted = NO;
    if (sGlobalMonitor != nil)
        [NSEvent removeMonitor:sGlobalMonitor];
    if (sLocalMonitor != nil)
        [NSEvent removeMonitor:sLocalMonitor];
    sGlobalMonitor = nil;
    sLocalMonitor = nil;
    [sTimer invalidate];
    sTimer = nil;
}

+(void)check {
    [self noteState:VOKReadCapsLock()];
}

+(void)noteState:(BOOL)on {
    if (on == sOn)
        return;
    sOn = on;
    [[NSNotificationCenter defaultCenter] postNotificationName:CapsLockMonitorDidChangeNotification object:nil];
    //on unless the person (or a script) turned it off; not depending on registerDefaults having run
    id setting = [[NSUserDefaults standardUserDefaults] objectForKey:CapsLockToastDefaultsKey];
    if (setting == nil || [setting boolValue])
        [CapsLockToast showForState:on];
}

@end
