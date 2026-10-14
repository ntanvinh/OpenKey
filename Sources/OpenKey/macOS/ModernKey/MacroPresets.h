//
//  MacroPresets.h
//  VOpenKey
//
//  The table of common Vietnamese abbreviations (ko = không, dc = được...) that comes with the app, for the user to add
//  to their own table of abbreviations. Never replaces one the user already has.
//

#import <Foundation/Foundation.h>

/// Posted when the table of abbreviations changed, for the windows that show it.
extern NSString* const VOKMacrosDidChangeNotification;

@interface MacroPresets : NSObject

/// How many abbreviations the list has, and how many of them the user does not have yet.
+(void)countTotal:(NSUInteger*)total missing:(NSUInteger*)missing;

/// Adds the missing ones and saves. Returns how many were added.
+(NSUInteger)addMissing;

/// A few of them as a sentence: "ko → không, dc → được, vs → với".
+(NSString*)examples;

@end
