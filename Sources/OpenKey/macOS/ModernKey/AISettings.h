//
//  AISettings.h
//  VOpenKey
//
//  What the user chose for the AI assistant: which service, which model, the address of the server, the instruction given with
//  every request, and the shortcut that opens the window. Saved in the preferences of the macOS account, except the API key,
//  which is in the keychain (AIKeychain).
//

#import <Foundation/Foundation.h>
#import "AIProvider.h"

/// ⌃⌥A, in the format of ShortcutRecorder
#define VOK_AI_DEFAULT_HOTKEY 0x61000300

#ifdef __cplusplus
extern "C" {
#endif
/// The shortcut opens the window. The event tap reads these for every key, hence plain variables.
extern int vAIEnabled;
/// The shortcut, in the format of ShortcutRecorder. VOK_SHORTCUT_NONE when there is none.
extern int vAIHotKey;
/// When Accessibility cannot tell what is selected, copy it with ⌘C (the clipboard is put back afterwards).
extern int vAICopySelection;
#ifdef __cplusplus
}
#endif

/// Everything needed to make one request.
@interface AIConfiguration : NSObject
@property (nonatomic, strong) AIProvider* provider;
/// Cleaned (VOKAICleanBaseURL).
@property (nonatomic, copy) NSString* baseURL;
@property (nonatomic, copy) NSString* model;
/// nil when the provider does not need one and the user entered none.
@property (nonatomic, copy) NSString* key;
@property (nonatomic, copy) NSString* systemPrompt;
@end

@interface AISettings : NSObject

/// The values of the settings before the user has changed them. Call at launch, before any window shows them.
+(void)registerDefaults;

/// Reads the shortcut and the switches. Call at launch, and again after the settings were reset.
+(void)start;

/// What the assistant is told before every request.
+(NSString*)defaultSystemPrompt;
@property (class, nonatomic, copy) NSString* systemPrompt;

/// The service in use, saved.
@property (class, nonatomic, copy) NSString* providerIdentifier;
@property (class, nonatomic, readonly) AIProvider* provider;

/// Address and model of a provider as the user set them, the provider's own when the user did not.
+(NSString*)baseURLForProvider:(AIProvider*)provider;
+(void)setBaseURL:(NSString*)baseURL forProvider:(AIProvider*)provider;
+(NSString*)modelForProvider:(AIProvider*)provider;
+(void)setModel:(NSString*)model forProvider:(AIProvider*)provider;

/// A provider can be used now: it has a key, or it does not need one (and has an address and a model).
+(BOOL)isProviderReady:(AIProvider*)provider;

/// Same, but without asking for a model: to list the models the service has, when the user has not chosen one yet.
+(AIConfiguration*)configurationForListingModelsOfProvider:(AIProvider*)provider error:(NSError**)error;

/// The configuration of a provider, with its key read from the keychain. nil with the reason (ready to show) when it cannot be
/// used: no key, address that is not allowed, no model.
+(AIConfiguration*)configurationForProvider:(AIProvider*)provider error:(NSError**)error;

/// Forgets the choices (service, models, addresses, instruction, shortcut). The keys stay where they are.
+(void)resetToDefaults;

@end
