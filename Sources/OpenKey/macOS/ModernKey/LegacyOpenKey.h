//
//  LegacyOpenKey.h
//  VOpenKey
//
//  VOpenKey is forked from OpenKey and has its own bundle id, so it starts with empty settings and its own
//  permissions. This brings the settings over once, and keeps both apps from converting every key twice.
//

#import <Cocoa/Cocoa.h>

@interface LegacyOpenKey : NSObject

// On the very first launch, copies the settings (typing options, macros, per-app memory...) of the original OpenKey.
+(void)importSettingsIfNeeded;

// If the original OpenKey is running for the current user, offers to quit it. Returns once the user has answered.
+(void)resolveConflictIfRunning;

@end
