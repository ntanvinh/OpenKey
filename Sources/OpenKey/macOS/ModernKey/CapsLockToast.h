//
//  CapsLockToast.h
//  VOpenKey
//
//  The small message that says "Caps Lock đang bật" or "Caps Lock đã tắt" for a moment when the person presses Caps Lock: a rounded
//  panel with the material of menus, an icon and one line, near the bottom of the screen the pointer is on. Like the suggestion bar it never
//  takes the keyboard or the mouse from the application in front, and it also reads the message out for VoiceOver.
//

#import <Cocoa/Cocoa.h>

@interface CapsLockToast : NSPanel

/// Shows the message for the new state of Caps Lock. A toast that is still on the screen is changed in place and stays for the full time again.
+(void)showForState:(BOOL)on;

/// Takes it away at once.
+(void)hide;

/// The line the person reads: "Caps Lock đang bật" / "Caps Lock đã tắt". Also the text VoiceOver announces.
+(NSString*)messageForState:(BOOL)on;

/// The panel, nil before the first time it was shown.
+(CapsLockToast*)panel;

/// The line that is written on the panel now (what `messageForState:` gave when it was shown).
@property (nonatomic, readonly, copy) NSString* message;

/// Tests only: the panel is put far outside every screen, so nothing shows up where somebody works.
+(void)setOffscreenForTesting:(BOOL)offscreen;

@end
