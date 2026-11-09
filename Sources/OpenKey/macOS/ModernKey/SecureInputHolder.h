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

// An application that is running and is known to take secure input (remote desktop, virtual machine, password manager, a terminal
// with Secure Keyboard Entry on). macOS names only ONE process, and not always the right one, so this is what else may be holding it.
@interface SecureInputSuspect : NSObject
@property (nonatomic, readonly) pid_t pid;
@property (nonatomic, readonly, copy) NSString* name;
@property (nonatomic, readonly, copy) NSString* bundleIdentifier;
// Why it is a suspect, in a few words: "Điều khiển từ xa", "Trình quản lý mật khẩu"...
@property (nonatomic, readonly, copy) NSString* reason;

// nil when the application is not known to take secure input. A terminal only counts while its Secure Keyboard Entry is on.
+(NSString*)reasonForBundleIdentifier:(NSString*)bundleIdentifier name:(NSString*)name secureKeyboardEntry:(BOOL)secureKeyboardEntry;

// `applications` are dictionaries with @"pid" (NSNumber), @"name", @"bundleID" and @"secureKeyboardEntry" (NSNumber BOOL), the order is kept.
+(NSArray<SecureInputSuspect*>*)suspectsAmongApplications:(NSArray<NSDictionary*>*)applications excludingPIDs:(NSArray<NSNumber*>*)pids;
// YES when the application that runs under this process number is a terminal (Terminal, iTerm2) whose Secure Keyboard Entry is on:
// then it holds secure input itself while it is in front, which confirms the name macOS gave.
+(BOOL)secureKeyboardEntryIsOnForPID:(pid_t)pid;
// The same over the applications that run now (NSWorkspace), or over what `+setApplicationsProvider:` returns.
+(NSArray<SecureInputSuspect*>*)runningSuspectsExcludingPIDs:(NSArray<NSNumber*>*)pids;
// For tests: stands in for NSWorkspace. nil puts NSWorkspace back.
+(void)setApplicationsProvider:(NSArray<NSDictionary*>* (^)(void))provider;

-(instancetype)initWithPID:(pid_t)pid name:(NSString*)name bundleIdentifier:(NSString*)bundleIdentifier reason:(NSString*)reason;
@end

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

// What SecureInputMonitor found out by checking what macOS says against what it can see itself. What macOS names is the application
// in FRONT, not the one that holds secure input (measured on macOS 15: a process in the background that holds it is never named, and
// the name follows the front application): it named VOpenKey AI itself while a remote desktop manager held secure input.
// Why the name is not confirmed, in a sentence; nil when something confirms it (the lock screen and the password prompts of macOS,
// a terminal whose Secure Keyboard Entry is on, a password field of this very process).
@property (nonatomic, readonly, copy) NSString* doubt;
// The other processes macOS named earlier during the same time secure input has been on, oldest first (not this one): the
// applications the person typed in while it stayed on, since macOS names the one in front.
@property (nonatomic, readonly, copy) NSArray<SecureInputHolder*>* earlierReports;
// Other running applications that are known to take secure input, apart from this one.
@property (nonatomic, readonly, copy) NSArray<SecureInputSuspect*>* suspects;

// A copy with those three facts. The monitor adds them to what `holderForPID:` looked up.
-(instancetype)holderWithDoubt:(NSString*)doubt earlierReports:(NSArray<SecureInputHolder*>*)earlierReports
                      suspects:(NSArray<SecureInputSuspect*>*)suspects;

// Same process, same role, same facts: the start time and the icon do not count.
-(BOOL)isEqualToHolder:(SecureInputHolder*)other;

// "Terminal", "tiến trình 1234" or "một ứng dụng khác": how to name it in a sentence.
-(NSString*)displayName;

@end
