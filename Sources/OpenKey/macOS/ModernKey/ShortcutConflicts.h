//
//  ShortcutConflicts.h
//  VOpenKey
//
//  Two things of VOpenKey cannot have the same shortcut: the event tap would do only the first one it checks. Every field
//  that records a shortcut asks here what already uses it.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, VOKShortcutOwner) {
    VOKShortcutOwnerSwitch,     //switch between Vietnamese and English
    VOKShortcutOwnerConvert,    //convert the code table of the clipboard
    VOKShortcutOwnerSnippet,    //open the snippets
    VOKShortcutOwnerRestore     //give back the keys of the word being typed
};

#ifdef __cplusplus
extern "C" {
#endif

/// The name of what already uses `data` among the shortcuts of the app, other than `owner` (the one being recorded); nil
/// when it is free. The shortcut of the snippets only counts while snippets are on.
NSString* VOKShortcutConflict(int data, VOKShortcutOwner owner);

#ifdef __cplusplus
}
#endif
