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
//  CAUTION, measured 2026-11-09 on macOS 15: the process number macOS gives (kCGSSessionSecureInputPID) is the one of the
//  application in FRONT, not of the one that holds secure input. With a process in the background holding it (a command line
//  tool and an accessory application were tried) macOS named the front application, named the next one as soon as the person
//  switched, and never named the real holder. So the name is a fact only where something confirms it (see SecureInputHolder
//  doubt), and the "ordinary app in the background" case above shows up only for the moment between a switch of the front
//  application and the next poll.
//

#ifndef SecureInputMonitor_h
#define SecureInputMonitor_h

#import <Cocoa/Cocoa.h>
#import "SecureInputHolder.h"
#import "SensitiveField.h"

// How long macOS' own Vietnamese input source has to be wanted without a break before it takes over (seconds). The process number
// macOS names is the one of the application in front, so for a moment after a switch of the front application it still names the
// one before: that is not "another application in the background holds secure input" and must not move the input source.
extern const NSTimeInterval SecureInputFallbackDelay;

// Asks whether the field that has the keyboard in an application holds a secret (SensitiveField is what VOpenKey AI passes). Called off
// the main thread, once each time macOS names another application: a password field in the application macOS names confirms that it
// is the one holding secure input.
typedef SensitiveFieldVerdict (^SecureInputFieldVerdictProvider)(pid_t pid);

// Posted when +isOpenKeyBlind, +isFallbackActive, +statusDescription or +currentHolder changes.
extern NSString* const SecureInputMonitorDidChangeNotification;

@interface SecureInputMonitor : NSObject

+(void)start;
+(void)stop;

// Gives the monitor the way to look into the field that has the keyboard. nil (the default): no name is confirmed that way.
+(void)setFieldVerdictProvider:(SecureInputFieldVerdictProvider)provider;

// For tests: the clock the monitor measures time with (seconds, steady). nil puts the system clock back.
+(void)setClockForTesting:(NSTimeInterval (^)(void))clock;

// YES while secure input is on and nothing types Vietnamese in OpenKey's place: the icon should show English.
+(BOOL)isOpenKeyBlind;

// YES while macOS' own Vietnamese input source is standing in for OpenKey. OpenKey must leave keys alone then.
+(BOOL)isFallbackActive;

// To be called when a key event reached the event tap while the fallback is active: keys only reach an event tap
// once secure input is released, so OpenKey should take over again without waiting for the next poll.
+(void)secureInputMayHaveEnded;

// Name of the app holding secure input, nil when it is off or unknown.
+(NSString*)holderName;

// Everything that can be found out about the process holding secure input (name, bundle id, process number, path, since
// when it runs...): nil while secure input is off. Its role says whether it is the app being typed in. SecureInputWindow
// shows it so that a person can track the program down.
+(SecureInputHolder*)currentHolder;

// The holder of the most recent time secure input was on: still there after it was released, so that the window can say
// who it was. nil if secure input has not been on since VOpenKey AI started.
+(SecureInputHolder*)lastHolder;
// When secure input was last released, nil if it has not been since VOpenKey AI started.
+(NSDate*)lastReleaseDate;

// For a tooltip: who is holding secure input and what is going on. nil while secure input is off.
+(NSString*)statusDescription;

@end

#endif /* SecureInputMonitor_h */
