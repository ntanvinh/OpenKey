//
//  WordRestore.m
//  VOpenKey
//

#import "WordRestore.h"
#import "ShortcutRecorder.h"

int vRestoreHotKey = VOK_RESTORE_DEFAULT_HOTKEY;

static NSString* const kHotKeyKey = @"RestoreHotKey";
static NSString* const kMigratedKey = @"RestoreNonVietnameseMigrated";

@implementation WordRestore

+(void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{kHotKeyKey: @(VOK_RESTORE_DEFAULT_HOTKEY)}];
}

+(void)migrateSettings {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:kMigratedKey])
        return;
    [defaults setBool:YES forKey:kMigratedKey];
    [defaults setInteger:1 forKey:@"RestoreIfInvalidWord"];
}

+(void)start {
    vRestoreHotKey = (int)[[NSUserDefaults standardUserDefaults] integerForKey:kHotKeyKey];
    //0 would be "the A key alone": every A typed would restore the word
    if (vRestoreHotKey == 0)
        vRestoreHotKey = VOK_SHORTCUT_NONE;
}

@end
