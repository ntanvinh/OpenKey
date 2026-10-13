//
//  SecureInputMonitor.h
//  ModernKey
//
//  While any app holds macOS "secure event input" (password fields, Terminal's "Secure Keyboard Entry", or an app
//  that forgot to release it) macOS hides every key event from event taps, so OpenKey cannot convert anything.
//  This is by design and cannot be worked around from an event tap. What this class does instead:
//  - the app being typed in is the one holding secure input (or a system prompt / the lock screen does):
//    the status icon shows English until it is released.
//  - another, ordinary app in the background holds it: macOS' own Vietnamese input source takes over typing, and
//    OpenKey takes over again when secure input is released.
//  macOS' Vietnamese input source also converts what is typed into a password field, so it is never switched on
//  for the first case. The saved language setting is left alone on purpose: changing it would also teach Smart
//  Switch Key that the app holding secure input is an English app.
//

#ifndef SecureInputMonitor_h
#define SecureInputMonitor_h

#import <Cocoa/Cocoa.h>

// Posted when +isOpenKeyBlind, +isFallbackActive or +statusDescription changes.
extern NSString* const SecureInputMonitorDidChangeNotification;

@interface SecureInputMonitor : NSObject

+(void)start;
+(void)stop;

// YES while secure input is on and nothing types Vietnamese in OpenKey's place: the icon should show English.
+(BOOL)isOpenKeyBlind;

// YES while macOS' own Vietnamese input source is standing in for OpenKey. OpenKey must leave keys alone then.
+(BOOL)isFallbackActive;

// To be called when a key event reached the event tap while the fallback is active: keys only reach an event tap
// once secure input is released, so OpenKey should take over again without waiting for the next poll.
+(void)secureInputMayHaveEnded;

// Name of the app holding secure input, nil when it is off or unknown.
+(NSString*)holderName;

// For a tooltip: who is holding secure input and what is going on. nil while secure input is off.
+(NSString*)statusDescription;

@end

#endif /* SecureInputMonitor_h */
