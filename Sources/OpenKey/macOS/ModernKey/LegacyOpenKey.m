//
//  LegacyOpenKey.m
//  VOpenKey
//

#import "LegacyOpenKey.h"
#import "AppInfo.h"
#include <libproc.h>
#include <sys/proc_info.h>

static NSString* const kImportedKey = @"VOKImportedLegacySettings";

@implementation LegacyOpenKey

+(void)importSettingsIfNeeded {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    //"NonFirstTime" is what tells the app its default configuration has been written already
    if ([defaults boolForKey:@"NonFirstTime"] || [defaults boolForKey:kImportedKey])
        return;

    NSDictionary* legacy = [defaults persistentDomainForName:VOK_LEGACY_BUNDLE_ID];
    for (NSString* key in legacy) {
        //window frames, Apple's own keys: not settings of the app
        if ([key hasPrefix:@"NS"] || [key hasPrefix:@"Apple"])
            continue;
        [defaults setObject:legacy[key] forKey:key];
    }
    [defaults setBool:YES forKey:kImportedKey];
    if (legacy.count > 0)
        NSLog(@"Imported %lu settings of %@", (unsigned long)legacy.count, VOK_LEGACY_BUNDLE_ID);
}

+(NSRunningApplication*)runningLegacyApp {
    //only the current user's copy matters, other users can have their own (Fast User Switching)
    uid_t currentUID = getuid();
    for (NSRunningApplication* app in [NSRunningApplication runningApplicationsWithBundleIdentifier:VOK_LEGACY_BUNDLE_ID]) {
        struct proc_bsdinfo proc;
        int size = proc_pidinfo(app.processIdentifier, PROC_PIDTBSDINFO, 0, &proc, sizeof(proc));
        if (size == sizeof(proc) && proc.pbi_uid == currentUID)
            return app;
    }
    return nil;
}

+(void)resolveConflictIfRunning {
    NSRunningApplication* legacy = [self runningLegacyApp];
    if (legacy == nil)
        return;

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"OpenKey (bản gốc) đang chạy";
    alert.informativeText = [NSString stringWithFormat:@"%@ và OpenKey không nên chạy cùng lúc vì mỗi phím gõ sẽ bị chuyển dấu hai lần. Bạn có muốn thoát OpenKey không?", VOK_APP_NAME];
    [alert addButtonWithTitle:@"Thoát OpenKey"];
    [alert addButtonWithTitle:@"Bỏ qua"];
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] != NSAlertFirstButtonReturn)
        return;

    [legacy terminate];
    //give it a moment to go; force it if it does not
    for (int i = 0; i < 20 && !legacy.terminated; i++)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    if (!legacy.terminated)
        [legacy forceTerminate];
}

@end
