//
//  AIProvider.m
//  VOpenKey
//

#import "AIProvider.h"

NSString* const VOKAIErrorDomain = @"vn.io.lssoft.vopenkey.ai";

@implementation AIProvider

-(instancetype)initWithIdentifier:(NSString*)identifier name:(NSString*)name protocol:(AIProtocol)protocol
                          baseURL:(NSString*)baseURL model:(NSString*)model local:(BOOL)local needsKey:(BOOL)needsKey
                          keyPage:(NSString*)keyPage note:(NSString*)note {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _name = [name copy];
        _protocol = protocol;
        _defaultBaseURL = [baseURL copy];
        _defaultModel = [model copy];
        _isLocal = local;
        _needsKey = needsKey;
        _keyPageURL = [keyPage copy];
        _note = [note copy];
    }
    return self;
}

-(BOOL)isAgentCLI {
    return _protocol == AIProtocolAgentCLI;
}

+(NSArray<AIProvider*>*)allProviders {
    static NSArray<AIProvider*>* all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        all = @[
            [[AIProvider alloc] initWithIdentifier:@"openai" name:@"OpenAI (ChatGPT)" protocol:AIProtocolOpenAI
                                           baseURL:@"https://api.openai.com/v1" model:@"gpt-4o-mini" local:NO needsKey:YES
                                           keyPage:@"https://platform.openai.com/api-keys" note:nil],
            [[AIProvider alloc] initWithIdentifier:@"gemini" name:@"Google Gemini" protocol:AIProtocolGemini
                                           baseURL:@"https://generativelanguage.googleapis.com/v1beta" model:@"gemini-flash-latest"
                                             local:NO needsKey:YES keyPage:@"https://aistudio.google.com/apikey" note:nil],
            [[AIProvider alloc] initWithIdentifier:@"anthropic" name:@"Anthropic (Claude)" protocol:AIProtocolAnthropic
                                           baseURL:@"https://api.anthropic.com/v1" model:@"claude-haiku-4-5-20251001"
                                             local:NO needsKey:YES keyPage:@"https://console.anthropic.com/settings/keys" note:nil],
            [[AIProvider alloc] initWithIdentifier:@"deepseek" name:@"DeepSeek" protocol:AIProtocolOpenAI
                                           baseURL:@"https://api.deepseek.com/v1" model:@"deepseek-chat" local:NO needsKey:YES
                                           keyPage:@"https://platform.deepseek.com/api_keys" note:nil],
            [[AIProvider alloc] initWithIdentifier:@"qwen" name:@"Qwen (Alibaba Cloud)" protocol:AIProtocolOpenAI
                                           baseURL:@"https://dashscope-intl.aliyuncs.com/compatible-mode/v1" model:@"qwen-plus"
                                             local:NO needsKey:YES keyPage:@"https://www.alibabacloud.com/help/en/model-studio/get-api-key"
                                              note:@"Địa chỉ mặc định là máy chủ quốc tế. Tài khoản ở Trung Quốc dùng dashscope.aliyuncs.com."],
            [[AIProvider alloc] initWithIdentifier:@"openrouter" name:@"OpenRouter" protocol:AIProtocolOpenAI
                                           baseURL:@"https://openrouter.ai/api/v1" model:@"openai/gpt-4o-mini" local:NO needsKey:YES
                                           keyPage:@"https://openrouter.ai/keys"
                                              note:@"Một key dùng được nhiều AI. Tên model có dạng nhà-cung-cấp/tên-model."],
            [[AIProvider alloc] initWithIdentifier:@"ollama" name:@"Ollama (chạy trên máy)" protocol:AIProtocolOpenAI
                                           baseURL:@"http://localhost:11434/v1" model:@"llama3.2" local:YES needsKey:NO
                                           keyPage:nil note:@"Không cần key. Bấm “Cài AI chạy trên máy…” ở phần trên để VOpenKey AI cài giúp, hoặc tự chạy `ollama serve` rồi tải model bằng `ollama pull`."],
            [[AIProvider alloc] initWithIdentifier:@"lmstudio" name:@"LM Studio (chạy trên máy)" protocol:AIProtocolOpenAI
                                           baseURL:@"http://localhost:1234/v1" model:@"local-model" local:YES needsKey:NO
                                           keyPage:nil note:@"Không cần key. Bật Local Server trong LM Studio."],
            [[AIProvider alloc] initWithIdentifier:@"custom" name:@"Khác (tương thích OpenAI)" protocol:AIProtocolOpenAI
                                           baseURL:@"" model:@"" local:NO needsKey:NO keyPage:nil
                                              note:@"Cho llama.cpp, vLLM, LocalAI hoặc dịch vụ khác. Địa chỉ dạng https://máy-chủ/v1. Key để trống nếu máy chủ không đòi."],
            //agents that are already signed in on this Mac: no key, VOpenKey AI only runs the program
            [[AIProvider alloc] initWithIdentifier:@"codex-cli" name:@"Codex CLI (ChatGPT)" protocol:AIProtocolAgentCLI
                                           baseURL:@"" model:@"" local:NO needsKey:NO keyPage:nil
                                              note:@"Dùng chương trình codex đã đăng nhập sẵn trên máy này (codex login): không cần API key."],
            [[AIProvider alloc] initWithIdentifier:@"claude-cli" name:@"Claude Code CLI (Claude)" protocol:AIProtocolAgentCLI
                                           baseURL:@"" model:@"haiku" local:NO needsKey:NO keyPage:nil
                                              note:@"Dùng chương trình claude đã đăng nhập sẵn trên máy này (tài khoản Claude hoặc API của chính CLI): không cần API key."],
            [[AIProvider alloc] initWithIdentifier:@"agy-cli" name:@"Antigravity CLI (Gemini)" protocol:AIProtocolAgentCLI
                                           baseURL:@"" model:@"" local:NO needsKey:NO keyPage:nil
                                              note:@"Dùng chương trình agy (Antigravity) đã đăng nhập sẵn trên máy này: không cần API key."],
        ];
    });
    return all;
}

+(AIProvider*)providerWithIdentifier:(NSString*)identifier {
    for (AIProvider* provider in [self allProviders])
        if ([provider.identifier isEqualToString:identifier])
            return provider;
    return nil;
}

+(AIProvider*)defaultProvider {
    return [self allProviders].firstObject;
}

@end

#pragma mark - Address of the server

BOOL VOKAIHostIsLocal(NSString* host) {
    host = host.lowercaseString;
    if ([host hasPrefix:@"["] && [host hasSuffix:@"]"])
        host = [host substringWithRange:NSMakeRange(1, host.length - 2)];
    if (host.length == 0)
        return NO;
    if ([host isEqualToString:@"localhost"] || [host hasSuffix:@".localhost"] || [host hasSuffix:@".local"])
        return YES;
    if ([host containsString:@":"]) //IPv6: this Mac, link-local and the private ranges
        return [host isEqualToString:@"::1"] || [host hasPrefix:@"fe80:"] || [host hasPrefix:@"fc"] || [host hasPrefix:@"fd"];
    //IPv4 in the private ranges, loopback and link-local
    NSArray<NSString*>* parts = [host componentsSeparatedByString:@"."];
    if (parts.count == 4) {
        int octets[4];
        for (int i = 0; i < 4; i++) {
            NSScanner* scanner = [NSScanner scannerWithString:parts[i]];
            int value = 0;
            if (![scanner scanInt:&value] || !scanner.atEnd || value < 0 || value > 255)
                return NO;
            octets[i] = value;
        }
        if (octets[0] == 127 || octets[0] == 10) return YES;
        if (octets[0] == 192 && octets[1] == 168) return YES;
        if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return YES;
        if (octets[0] == 169 && octets[1] == 254) return YES;
        return NO;
    }
    //a name without a dot is something of the local network ("mac-mini")
    return ![host containsString:@"."];
}

//the reason for refusing something, handed to the caller; always returns nil
static NSString* Refuse(NSString** reason, NSString* why) {
    if (reason != NULL)
        *reason = why;
    return nil;
}

NSString* VOKAICleanBaseURL(NSString* address, NSString** reason) {
    NSString* text = [address stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([text hasSuffix:@"/"])
        text = [text substringToIndex:text.length - 1];
    if (text.length == 0)
        return Refuse(reason, @"Chưa nhập địa chỉ máy chủ.");
    NSURLComponents* components = [NSURLComponents componentsWithString:text];
    NSString* scheme = components.scheme.lowercaseString;
    if (components == nil || components.host.length == 0 || scheme == nil)
        return Refuse(reason, @"Địa chỉ không hợp lệ. Ví dụ: https://api.openai.com/v1");
    if (components.user != nil || components.password != nil)
        return Refuse(reason, @"Địa chỉ không được chứa tên người dùng hay mật khẩu. Hãy nhập key ở ô API key.");
    if (components.query != nil || components.fragment != nil)
        return Refuse(reason, @"Địa chỉ không được có dấu ? hay #. Chỉ nhập đến phần /v1.");
    if ([scheme isEqualToString:@"https"])
        return text;
    if ([scheme isEqualToString:@"http"]) {
        if (VOKAIHostIsLocal(components.host))
            return text;
        return Refuse(reason, @"Địa chỉ ngoài internet phải dùng https để key và nội dung không bị lộ. Chỉ máy chạy cục bộ hoặc trong mạng nội bộ mới được dùng http.");
    }
    return Refuse(reason, @"Địa chỉ phải bắt đầu bằng https:// (hoặc http:// cho máy trong mạng nội bộ).");
}

#pragma mark - Key

NSString* VOKAICleanKey(NSString* key, NSString** reason) {
    NSString* text = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        if (reason != NULL)
            *reason = @"Chưa nhập key.";
        return nil;
    }
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c < 0x21 || c > 0x7E) {
            if (reason != NULL)
                *reason = @"Key có khoảng trắng hoặc ký tự lạ ở giữa. Hãy sao chép lại cả key, không thêm gì khác.";
            return nil;
        }
    }
    if (text.length > 512) {
        if (reason != NULL)
            *reason = @"Key dài bất thường. Hãy kiểm tra lại.";
        return nil;
    }
    return text;
}

NSString* VOKAIRedact(NSString* message, NSString* key) {
    if (message.length == 0)
        return message;
    NSMutableString* text = [message mutableCopy];
    if (key.length >= 6)
        [text replaceOccurrencesOfString:key withString:@"••••" options:0 range:NSMakeRange(0, text.length)];
    static NSRegularExpression* patterns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        //OpenAI and Anthropic ("sk-...", "sk-ant-..."), Google ("AIza..."), a bearer token of any service
        patterns = [NSRegularExpression regularExpressionWithPattern:@"(sk-[A-Za-z0-9_\\-]{6,}|AIza[0-9A-Za-z_\\-]{10,}|(?i:bearer)\\s+[A-Za-z0-9._\\-]{8,})"
                                                              options:0 error:nil];
    });
    [patterns replaceMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"••••"];
    return text;
}
