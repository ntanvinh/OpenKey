//
//  AIKeychain.m
//  VOpenKey
//

#import "AIKeychain.h"
#import "AIProvider.h"
#import <Security/Security.h>

static NSString* sService;

@implementation AIKeychain

+(NSString*)service {
    if (sService != nil)
        return sService;
    NSString* bundle = [[NSBundle mainBundle] bundleIdentifier];
    //a program without a bundle (a test) gets a name of its own, not the one of the app
    return [(bundle.length > 0 ? bundle : [NSString stringWithFormat:@"%@.unbundled", [NSProcessInfo processInfo].processName]) stringByAppendingString:@".ai"];
}

+(void)setService:(NSString*)service {
    sService = [service copy];
}

+(NSMutableDictionary*)queryForProvider:(NSString*)provider {
    return [@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: [self service],
              (__bridge id)kSecAttrAccount: provider,
              (__bridge id)kSecAttrSynchronizable: @NO} mutableCopy];
}

+(BOOL)hasKeyForProvider:(NSString*)provider {
    NSMutableDictionary* query = [self queryForProvider:provider];
    query[(__bridge id)kSecReturnAttributes] = @YES; //only what describes the item, not the secret: no permission is asked
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (result != NULL)
        CFRelease(result);
    return status == errSecSuccess || status == errSecInteractionNotAllowed;
}

+(NSString*)keyForProvider:(NSString*)provider {
    NSMutableDictionary* query = [self queryForProvider:provider];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || result == NULL)
        return nil;
    NSData* data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+(BOOL)setKey:(NSString*)key forProvider:(NSString*)provider error:(NSError**)error {
    NSData* data = [key dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0 || provider.length == 0) {
        if (error != NULL)
            *error = [NSError errorWithDomain:VOKAIErrorDomain code:VOKAIErrorBadKey userInfo:@{NSLocalizedDescriptionKey: @"Chưa nhập key."}];
        return NO;
    }
    NSMutableDictionary* query = [self queryForProvider:provider];
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: data});
    if (status == errSecItemNotFound) {
        AIProvider* known = [AIProvider providerWithIdentifier:provider];
        query[(__bridge id)kSecValueData] = data;
        query[(__bridge id)kSecAttrLabel] = [NSString stringWithFormat:@"VOpenKey AI: %@", known.name ?: provider];
        query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }
    if (status != errSecSuccess) {
        if (error != NULL) {
            NSString* text = CFBridgingRelease(SecCopyErrorMessageString(status, NULL));
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Không lưu được key vào Keychain (%@).", text ?: @"lỗi không rõ"]}];
        }
        return NO;
    }
    return YES;
}

+(BOOL)removeKeyForProvider:(NSString*)provider {
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)[self queryForProvider:provider]);
    return status == errSecSuccess || status == errSecItemNotFound;
}

@end
