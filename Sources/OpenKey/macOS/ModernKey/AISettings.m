//
//  AISettings.m
//  VOpenKey
//

#import "AISettings.h"
#import "AIAgentCLI.h"
#import "AIKeychain.h"
#import "ShortcutRecorder.h"

int vAIEnabled = 1;
int vAIHotKey = VOK_AI_DEFAULT_HOTKEY;
int vAICopySelection = 1;

static NSString* const kEnabledKey = @"AIEnabled";
static NSString* const kHotKeyKey = @"AIHotKey";
static NSString* const kCopyKey = @"AICopySelection";
static NSString* const kProviderKey = @"AIProvider";
static NSString* const kSystemPromptKey = @"AISystemPrompt";

static NSString* PerProviderKey(AIProvider* provider, NSString* what) {
    return [NSString stringWithFormat:@"AIProvider.%@.%@", provider.identifier, what];
}

//hands the reason for a failure to the caller; always returns nil
static AIConfiguration* Failure(NSError** error, VOKAIErrorCode code, NSString* why) {
    if (error != NULL)
        *error = [NSError errorWithDomain:VOKAIErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: why}];
    return nil;
}

@implementation AIConfiguration
@end

@interface AISettings ()
+(AIConfiguration*)configurationForProvider:(AIProvider*)provider requireModel:(BOOL)requireModel error:(NSError**)error;
@end

@implementation AISettings

+(void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kEnabledKey: @1, kHotKeyKey: @(VOK_AI_DEFAULT_HOTKEY), kCopyKey: @1, kProviderKey: [AIProvider defaultProvider].identifier}];
}

+(void)start {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    vAIEnabled = [defaults integerForKey:kEnabledKey] != 0;
    vAICopySelection = [defaults integerForKey:kCopyKey] != 0;
    vAIHotKey = (int)[defaults integerForKey:kHotKeyKey];
    //0 would be "the A key alone": every A typed would open the window
    if (vAIHotKey == 0)
        vAIHotKey = VOK_SHORTCUT_NONE;
}

+(NSString*)defaultSystemPrompt {
    return @"Bạn là trợ lý viết văn bản. Làm đúng yêu cầu của người dùng và chỉ trả về nội dung được yêu cầu, "
           @"không mở đầu, không giải thích thêm, không đặt trong dấu ngoặc kép hay khối code trừ khi được yêu cầu. "
           @"Giữ ngôn ngữ của người dùng, trừ khi họ yêu cầu ngôn ngữ khác.";
}

+(NSString*)systemPrompt {
    NSString* saved = [[NSUserDefaults standardUserDefaults] stringForKey:kSystemPromptKey];
    return saved.length > 0 ? saved : [self defaultSystemPrompt];
}

+(void)setSystemPrompt:(NSString*)prompt {
    NSString* trimmed = [prompt stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || [trimmed isEqualToString:[self defaultSystemPrompt]])
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSystemPromptKey];
    else
        [[NSUserDefaults standardUserDefaults] setObject:trimmed forKey:kSystemPromptKey];
}

+(NSString*)providerIdentifier {
    NSString* saved = [[NSUserDefaults standardUserDefaults] stringForKey:kProviderKey];
    return [AIProvider providerWithIdentifier:saved] != nil ? saved : [AIProvider defaultProvider].identifier;
}

+(void)setProviderIdentifier:(NSString*)identifier {
    if ([AIProvider providerWithIdentifier:identifier] != nil)
        [[NSUserDefaults standardUserDefaults] setObject:identifier forKey:kProviderKey];
}

+(AIProvider*)provider {
    return [AIProvider providerWithIdentifier:[self providerIdentifier]];
}

+(NSString*)baseURLForProvider:(AIProvider*)provider {
    NSString* saved = [[NSUserDefaults standardUserDefaults] stringForKey:PerProviderKey(provider, @"baseURL")];
    return saved.length > 0 ? saved : provider.defaultBaseURL;
}

+(void)setBaseURL:(NSString*)baseURL forProvider:(AIProvider*)provider {
    NSString* trimmed = [baseURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || [trimmed isEqualToString:provider.defaultBaseURL])
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:PerProviderKey(provider, @"baseURL")];
    else
        [[NSUserDefaults standardUserDefaults] setObject:trimmed forKey:PerProviderKey(provider, @"baseURL")];
}

+(NSString*)modelForProvider:(AIProvider*)provider {
    NSString* saved = [[NSUserDefaults standardUserDefaults] stringForKey:PerProviderKey(provider, @"model")];
    return saved.length > 0 ? saved : provider.defaultModel;
}

+(void)setModel:(NSString*)model forProvider:(AIProvider*)provider {
    NSString* trimmed = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || [trimmed isEqualToString:provider.defaultModel])
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:PerProviderKey(provider, @"model")];
    else
        [[NSUserDefaults standardUserDefaults] setObject:trimmed forKey:PerProviderKey(provider, @"model")];
}

+(NSString*)effortForProvider:(AIProvider*)provider {
    NSString* saved = [[NSUserDefaults standardUserDefaults] stringForKey:PerProviderKey(provider, @"effort")];
    return saved.length > 0 ? saved : nil;
}

+(void)setEffort:(NSString*)effort forProvider:(AIProvider*)provider {
    NSString* trimmed = [effort stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0)
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:PerProviderKey(provider, @"effort")];
    else
        [[NSUserDefaults standardUserDefaults] setObject:trimmed forKey:PerProviderKey(provider, @"effort")];
}

+(NSString*)programForProvider:(AIProvider*)provider {
    NSString* saved = [[NSUserDefaults standardUserDefaults] stringForKey:PerProviderKey(provider, @"program")];
    return saved.length > 0 ? saved : nil;
}

+(void)setProgram:(NSString*)path forProvider:(AIProvider*)provider {
    if (path.length == 0)
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:PerProviderKey(provider, @"program")];
    else
        [[NSUserDefaults standardUserDefaults] setObject:path forKey:PerProviderKey(provider, @"program")];
}

+(NSString*)executablePathForProvider:(AIProvider*)provider {
    return [[AIAgentCLI forProvider:provider] locateExecutableWithOverride:[self programForProvider:provider]];
}

+(BOOL)isProviderReady:(AIProvider*)provider {
    if (provider.isAgentCLI)
        return [self executablePathForProvider:provider] != nil;
    if (provider.needsKey && ![AIKeychain hasKeyForProvider:provider.identifier])
        return NO;
    return VOKAICleanBaseURL([self baseURLForProvider:provider], NULL) != nil && [self modelForProvider:provider].length > 0;
}

+(AIConfiguration*)configurationForProvider:(AIProvider*)provider error:(NSError**)error {
    return [self configurationForProvider:provider requireModel:YES error:error];
}

+(AIConfiguration*)configurationForListingModelsOfProvider:(AIProvider*)provider error:(NSError**)error {
    return [self configurationForProvider:provider requireModel:NO error:error];
}

+(AIConfiguration*)configurationForProvider:(AIProvider*)provider requireModel:(BOOL)requireModel error:(NSError**)error {
    AIAgentCLI* cli = [AIAgentCLI forProvider:provider];
    if (cli != nil) {
        //an agent program has no address and no key; an empty model is allowed, it means "choose a light one for me"
        NSString* program = [self executablePathForProvider:provider];
        if (program == nil)
            return Failure(error, VOKAIErrorNoProgram, [cli errorForLaunchFailure:@"không tìm thấy trên máy này"].localizedDescription);
        AIConfiguration* configuration = [[AIConfiguration alloc] init];
        configuration.provider = provider;
        configuration.baseURL = @"";
        configuration.model = [self modelForProvider:provider] ?: @"";
        configuration.effort = [self effortForProvider:provider];
        configuration.executablePath = program;
        configuration.systemPrompt = [self systemPrompt];
        return configuration;
    }
    NSString* reason = nil;
    NSString* address = VOKAICleanBaseURL([self baseURLForProvider:provider], &reason);
    if (address == nil)
        return Failure(error, VOKAIErrorBadAddress, reason);
    NSString* model = [self modelForProvider:provider];
    if (requireModel && model.length == 0)
        return Failure(error, VOKAIErrorModel, @"Chưa chọn model. Vào Cài đặt > AI để nhập tên model.");
    NSString* key = [AIKeychain keyForProvider:provider.identifier];
    if (provider.needsKey && key.length == 0)
        return Failure(error, VOKAIErrorNoKey, [NSString stringWithFormat:@"Chưa có API key của %@ cho tài khoản macOS này. Vào Cài đặt > AI để nhập.", provider.name]);
    AIConfiguration* configuration = [[AIConfiguration alloc] init];
    configuration.provider = provider;
    configuration.baseURL = address;
    configuration.model = model ?: @"";
    configuration.key = key.length > 0 ? key : nil;
    configuration.systemPrompt = [self systemPrompt];
    return configuration;
}

+(void)resetToDefaults {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    for (NSString* key in @[kEnabledKey, kHotKeyKey, kCopyKey, kProviderKey, kSystemPromptKey])
        [defaults removeObjectForKey:key];
    for (AIProvider* provider in [AIProvider allProviders]) {
        [defaults removeObjectForKey:PerProviderKey(provider, @"baseURL")];
        [defaults removeObjectForKey:PerProviderKey(provider, @"model")];
        [defaults removeObjectForKey:PerProviderKey(provider, @"effort")];
        [defaults removeObjectForKey:PerProviderKey(provider, @"program")];
    }
    [self start];
}

@end
