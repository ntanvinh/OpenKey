//
//  WordRestore.h
//  VOpenKey
//
//  Giving back what was typed when a word is not Vietnamese: "restore" typed in Telex comes out as "rétỏe".
//
//  - By itself: a word that is over (a space, a comma, Return...) and is not Vietnamese gets its keys back. It is the
//    setting "Tự khôi phục từ không phải tiếng Việt" (vRestoreIfWrongSpelling, saved as RestoreIfInvalidWord), which the
//    typing engine reads. It no longer needs spell checking to be on.
//  - By hand: the restore shortcut, ⌥Space unless changed, gives the keys back for the word being typed, at any moment.
//    The rest of that word is then typed as it comes, without conversion.
//
//  The typing engine does the work (engine/Engine.h, vRestoreWord); the event tap calls it when the shortcut is pressed.
//

#import <Foundation/Foundation.h>

/// ⌥Space, in the format of ShortcutRecorder
#define VOK_RESTORE_DEFAULT_HOTKEY 0x20000231

#ifdef __cplusplus
extern "C" {
#endif
/// The shortcut, in the format of ShortcutRecorder. VOK_SHORTCUT_NONE when there is none. The event tap reads it for every key.
extern int vRestoreHotKey;
#ifdef __cplusplus
}
#endif

@interface WordRestore : NSObject

/// The values of the settings before the user has changed them. Call at launch, before any window shows them.
+(void)registerDefaults;

/// Restoring words by themselves was an option that depended on spell checking and was off. It is on for everybody once,
/// when this version first runs: the user can turn it off again. Call at launch, before the typing engine reads its settings.
+(void)migrateSettings;

/// Reads the shortcut. Call at launch, and again after the settings were reset.
+(void)start;

@end
