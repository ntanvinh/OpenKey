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

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        TestRoles();
        TestFacts();
        TestInit();
        TestMonitor();
        printf(failures == 0 ? "secure_input_holder_test: ALL OK\n" : "secure_input_holder_test: %d FAILED\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
