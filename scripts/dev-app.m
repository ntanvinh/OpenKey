// App lifecycle checks for dev.sh. Match the bundle ID and owner, not a process-name substring.
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include <libproc.h>
#include <signal.h>
#include <unistd.h>

static NSArray<NSRunningApplication*>* RunningApps(NSString* bundleID) {
    NSMutableArray* apps = [NSMutableArray array];
    for (NSRunningApplication* app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID]) {
        struct proc_bsdinfo info;
        if (!app.terminated &&
            proc_pidinfo(app.processIdentifier, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == sizeof(info) &&
            info.pbi_uid == getuid())
            [apps addObject:app];
    }
    return apps;
}

static void Poll(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}

static BOOL WaitForExit(NSString* bundleID, NSTimeInterval timeout) {
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    do {
        if (RunningApps(bundleID).count == 0)
            return YES;
        Poll();
    } while (deadline.timeIntervalSinceNow > 0);
    return NO;
}

static BOOL HasTypingTap(pid_t pid) {
    uint32_t count = 0;
    if (CGGetEventTapList(0, NULL, &count) != kCGErrorSuccess || count == 0)
        return NO;
    CGEventTapInformation* taps = calloc(count, sizeof(*taps));
    if (taps == NULL)
        return NO;
    BOOL found = NO;
    if (CGGetEventTapList(count, taps, &count) == kCGErrorSuccess) {
        for (uint32_t i = 0; i < count; i++) {
            if (taps[i].tappingProcess == pid && taps[i].enabled &&
                taps[i].options == kCGEventTapOptionDefault &&
                (taps[i].eventsOfInterest & CGEventMaskBit(kCGEventKeyDown)))
                found = YES;
        }
    }
    free(taps);
    return found;
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        if (argc < 3)
            return 1;
        NSString* command = @(argv[1]);
        NSString* bundleID = @(argv[2]);
        if ([command isEqualToString:@"stop"]) {
            for (NSRunningApplication* app in RunningApps(bundleID)) {
                fprintf(stderr, "Closing PID %d (%s)\n", app.processIdentifier, app.bundleURL.path.UTF8String);
                [app terminate];
            }
            if (WaitForExit(bundleID, 8))
                return 0;
            for (NSRunningApplication* app in RunningApps(bundleID))
                kill(app.processIdentifier, SIGTERM);
            if (WaitForExit(bundleID, 3))
                return 0;
            for (NSRunningApplication* app in RunningApps(bundleID))
                [app forceTerminate];
            if (WaitForExit(bundleID, 3))
                return 0;
            fprintf(stderr, "The old app is still running; refusing to replace it.\n");
            return 1;
        }
        if (argc != 4 || !([command isEqualToString:@"wait"] || [command isEqualToString:@"ready"]))
            return 1;
        NSString* path = [@(argv[3]) stringByResolvingSymlinksInPath];
        NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        do {
            NSArray* apps = RunningApps(bundleID);
            if (apps.count == 1) {
                NSRunningApplication* app = apps.firstObject;
                if (app.finishedLaunching && [[app.bundleURL.path stringByResolvingSymlinksInPath] isEqualToString:path]) {
                    if ([command isEqualToString:@"wait"] || HasTypingTap(app.processIdentifier)) {
                        fprintf(stderr, "Started PID %d%s\n", app.processIdentifier,
                                [command isEqualToString:@"ready"] ? " with an enabled keyboard hook" : "");
                        return 0;
                    }
                }
            }
            Poll();
        } while (deadline.timeIntervalSinceNow > 0);
        fprintf(stderr, "The installed app did not become ready%s.\n",
                [command isEqualToString:@"ready"] ? " with an enabled keyboard hook (check macOS permissions or Secure Input)" : "");
        return 1;
    }
}
