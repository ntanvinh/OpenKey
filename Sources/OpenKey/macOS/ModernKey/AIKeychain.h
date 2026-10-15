//
//  AIKeychain.h
//  VOpenKey
//
//  Where the API keys are kept: in the login keychain of the macOS account that is using the app. Every account has its own
//  keychain, so another account on the same Mac does not see the key and has to enter its own.
//
//  A key is never written anywhere else: not in the preferences, not in a file, not in a log. It is read from the keychain
//  when a request is made and not kept. The item is not synchronised with iCloud and not part of backups made for another
//  device, and other programs have to ask the user before they can read it (macOS lists VOpenKey as the only one trusted).
//

#import <Foundation/Foundation.h>

@interface AIKeychain : NSObject

/// The name under which items are kept: the bundle identifier of the app plus ".ai", so a test build next to the real app has
/// its own items. Tests change it.
@property (class, nonatomic, copy) NSString* service;

/// Whether a key is stored for a provider. Does not read the key, so it never makes macOS ask for permission.
+(BOOL)hasKeyForProvider:(NSString*)provider;

/// The key, nil when there is none or the user did not allow VOpenKey to read it.
+(NSString*)keyForProvider:(NSString*)provider;

/// Stores a key, replacing the one that was there. `key` must be clean already (VOKAICleanKey).
+(BOOL)setKey:(NSString*)key forProvider:(NSString*)provider error:(NSError**)error;

/// Deletes the key of a provider. YES also when there was none.
+(BOOL)removeKeyForProvider:(NSString*)provider;

@end
