//
//  CapsLockMonitor.h
//  VOpenKey
//
//  Knows whether Caps Lock is on and tells the rest of the application when it changes: the icon in the menu bar turns red while it
//  is on (StatusMenuController listens) and a toast says "Caps Lock đang bật" / "Caps Lock đã tắt" (CapsLockToast).
//
//  The state is read from the session (`+[NSEvent modifierFlags]`), not counted from the key presses, so it is right when Caps Lock was
//  changed by something else, and it is looked at both when a modifier key changes (instant, but macOS hides the keys from the
//  application while any application holds secure input, in a password field for example, which is when a person wants to know) and
//  a few times a second.
//

#import <Cocoa/Cocoa.h>

/// Posted on the main thread when Caps Lock was switched, and once when the monitor starts.
extern NSString* const CapsLockMonitorDidChangeNotification;

/// "CapsLockToast" in the user defaults, on unless it is set to NO: the message is shown. The icon is red either way.
extern NSString* const CapsLockToastDefaultsKey;

@interface CapsLockMonitor : NSObject

+(void)registerDefaults;
+(void)start;
+(void)stop;

/// Caps Lock is on now (as of the last look).
+(BOOL)isOn;

/// Looks at the keyboard now.
+(void)check;

/// Takes `on` as the state of Caps Lock now. A change posts the notification and shows the toast; the same state again does nothing.
+(void)noteState:(BOOL)on;

@end
