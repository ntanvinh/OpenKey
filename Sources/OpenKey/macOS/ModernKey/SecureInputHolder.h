//
//  SecureInputHolder.h
//  VOpenKey
//
//  What can be found out about the process that holds macOS' secure event input, so that a person can track it down:
//  its name, bundle id, process number, where it lives on disk, since when it runs, which process started it, and what
//  kind of process it is (the app being typed in, an app in the background, a helper, the system, nothing macOS names).
//
//  An immutable snapshot taken by SecureInputMonitor; SecureInputWindow shows it.
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, SecureInputHolderRole) {
    SecureInputHolderRoleUnknown,           // macOS names no process
    SecureInputHolderRoleFrontApp,          // the app being typed in: a password field or "Secure Keyboard Entry" there
    SecureInputHolderRoleBackgroundApp,     // an ordinary app that is not the one being typed in (often one that forgot to release it)
    SecureInputHolderRoleHelper,            // a menu bar app, an agent or a helper that is not a system program
    SecureInputHolderRoleSystem,            // part of macOS: login window, password prompts of the system
    SecureInputHolderRoleLockedSession      // the lock screen, or the session of another user
};

@interface SecureInputHolder : NSObject

// 0 when macOS does not say.
@property (nonatomic, readonly) pid_t pid;
@property (nonatomic, readonly) SecureInputHolderRole role;
// NO when macOS names a process number that no longer runs.
@property (nonatomic, readonly) BOOL processExists;

// "Terminal", or the name of the program for a process that is not an app. nil when nothing is known.
@property (nonatomic, readonly, copy) NSString* name;
@property (nonatomic, readonly, copy) NSString* bundleIdentifier;
@property (nonatomic, readonly, copy) NSString* version;
// The .app folder for an app, the program file otherwise: what "Hiện trong Finder" shows.
@property (nonatomic, readonly, copy) NSString* path;
@property (nonatomic, readonly, copy) NSDate* startDate;
// The process that started it, nil when that is launchd (every app opened from the Dock or Finder) or unknown.
@property (nonatomic, readonly) pid_t parentPID;
@property (nonatomic, readonly, copy) NSString* parentName;
@property (nonatomic, readonly, strong) NSImage* icon;

// What kind of process it is: the same rules SecureInputMonitor uses to decide whether macOS' own Vietnamese input
// source may take over (it may only for an ordinary app in the background).
+(SecureInputHolderRole)roleForSessionInFront:(BOOL)sessionInFront holderPID:(pid_t)holderPID processExists:(BOOL)processExists
                                   regularApp:(BOOL)regularApp systemProgram:(BOOL)systemProgram frontmostPID:(pid_t)frontmostPID;

// Looks the process up. `frontmostPID` is the app the person is typing in.
+(instancetype)holderForPID:(pid_t)pid sessionInFront:(BOOL)sessionInFront frontmostPID:(pid_t)frontmostPID;

// For tests and for a holder that is not looked up.
-(instancetype)initWithPID:(pid_t)pid role:(SecureInputHolderRole)role processExists:(BOOL)processExists name:(NSString*)name
          bundleIdentifier:(NSString*)bundleIdentifier version:(NSString*)version path:(NSString*)path startDate:(NSDate*)startDate
                 parentPID:(pid_t)parentPID parentName:(NSString*)parentName icon:(NSImage*)icon;

// Same process, same role, same facts: the start time and the icon do not count.
-(BOOL)isEqualToHolder:(SecureInputHolder*)other;

// "Terminal", "tiến trình 1234" or "một ứng dụng khác": how to name it in a sentence.
-(NSString*)displayName;

@end
