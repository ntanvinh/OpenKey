//
//  ShortcutRecorder.h
//  VOpenKey
//
//  A field in which a keyboard shortcut is recorded by pressing it, like the ones in System Settings > Keyboard >
//  Keyboard Shortcuts. Click it, then press the shortcut: modifiers and a key (⌃Space, ⌥Z), or only modifiers (⌃⇧,
//  pressed and released together).
//
//  The shortcut is the same integer the engine reads for the language switch and the quick convert:
//      bits 0-7    key code, 0xFE when the shortcut is made of modifiers only
//      bit 8 ⌃, 9 ⌥, 10 ⌘, 11 ⇧
//      bit 15      beep when switching (belongs to the language switch, the recorder keeps it as it is)
//      bits 24-31  the character of the key (for showing it on a menu), 0xFE when there is none
//  0xFE0000FE is "no shortcut".
//

#import <Cocoa/Cocoa.h>

#define VOK_SHORTCUT_NONE 0xFE0000FE

#ifdef __cplusplus
extern "C" {
#endif

/// 1 while a recorder waits for a shortcut. The event tap lets every key through meanwhile: otherwise the shortcut
/// being replaced would switch the language instead of being recorded.
extern int vRecordingShortcut;

BOOL VOKShortcutIsEmpty(int data);
BOOL VOKShortcutsEqual(int a, int b);

/// "⌃ Space", "⌥Z", "⌃⇧"; nil when there is no shortcut.
NSString* VOKShortcutDescription(int data);

/// What a menu item needs to show the shortcut on its right: the key as text, @"" when the shortcut has none (modifiers
/// only, or a key without a text such as an arrow).
NSString* VOKShortcutKeyEquivalent(int data);

/// The modifier flags of the shortcut, for a menu item.
NSEventModifierFlags VOKShortcutModifierMask(int data);

#ifdef __cplusplus
}
#endif

@interface ShortcutRecorder : NSControl

/// The shortcut shown. Setting it does not call onChange.
@property (nonatomic) int value;

/// Called when the user has recorded or cleared a shortcut.
@property (nonatomic, copy) void (^onChange)(int value);

/// Asked before a recorded shortcut is accepted: the name of what already uses it, or nil.
@property (nonatomic, copy) NSString* (^conflict)(int value);

/// What the field says when there is no shortcut.
@property (nonatomic, copy) NSString* placeholder;

@end
