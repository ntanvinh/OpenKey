// Tests of the AI side of VOpenKey: the providers, the rules for addresses and keys, the keychain, the reading of streams, and
// the client against a fake server (mock_ai_server.py). Run with run-ai-test.sh, which starts the fake server.
//
//   ai_test <port of the fake server>
//
// Nothing here talks to a real AI service and no real key is used. The keychain items made by the test have a name of their own
// and are deleted at the end.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "AIProvider.h"
#import "AIKeychain.h"
#import "AISettings.h"
#import "AIClient.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSString* gBase;      //http://127.0.0.1:<port>

static void Spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static BOOL SpinUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [end timeIntervalSinceNow] > 0)
        Spin(0.01);
    return done();
}

static NSDictionary* LastRequestOfServer(void) {
    __block NSDictionary* result = nil;
    __block BOOL finished = NO;
    NSURL* url = [NSURL URLWithString:[gBase stringByAppendingString:@"/_last"]];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
        result = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        finished = YES;
    }] resume];
    SpinUntil(^BOOL { return finished; }, 5);
    return result;
}

static AIConfiguration* Config(NSString* providerId, NSString* path, NSString* model, NSString* key) {
    AIConfiguration* c = [[AIConfiguration alloc] init];
    c.provider = [AIProvider providerWithIdentifier:providerId];
    c.baseURL = [gBase stringByAppendingString:path];
    c.model = model;
    c.key = key;
    c.systemPrompt = @"Trả lời ngắn.";
    return c;
}

static NSString* const kGoodKey = @"test-key-123";

//a request made to the end: all the text, the error (nil on success), the number of pieces it came in
static void Generate(AIConfiguration* c, NSString* prompt, NSString** text, NSError** error, NSUInteger* pieceCount) {
    __block NSMutableString* all = [NSMutableString string];
    __block NSError* failure = nil;
    __block BOOL finished = NO;
    __block NSUInteger pieces = 0;
    AIClient* client = [[AIClient alloc] initWithConfiguration:c];
    [client generateWithPrompt:prompt onText:^(NSString* piece) { [all appendString:piece]; pieces++; }
                    completion:^(NSError* e) { failure = e; finished = YES; }];
    if (!SpinUntil(^BOOL { return finished; }, 20))
        printf("(a request did not finish in 20 s)\n");
    if (text != NULL) *text = all;
    if (error != NULL) *error = failure;
    if (pieceCount != NULL) *pieceCount = pieces;
}

#pragma mark - Providers, addresses, keys

static void TestProviders(void) {
    printf("-- providers\n");
    NSArray<AIProvider*>* all = [AIProvider allProviders];
    CHECK(all.count >= 8);
    NSMutableSet* ids = [NSMutableSet set];
    BOOL hasOpenAI = NO, hasGemini = NO, hasAnthropic = NO, hasDeepSeek = NO, hasQwen = NO, hasLocal = NO;
    for (AIProvider* p in all) {
        CHECK(p.identifier.length > 0 && p.name.length > 0);
        CHECK(![ids containsObject:p.identifier]);
        [ids addObject:p.identifier];
        if (p.defaultBaseURL.length > 0) {
            NSString* reason = nil;
            CHECK(VOKAICleanBaseURL(p.defaultBaseURL, &reason) != nil);        //its own default must be allowed
            CHECK(p.isLocal ? [p.defaultBaseURL hasPrefix:@"http://"] : [p.defaultBaseURL hasPrefix:@"https://"]);
        }
        if (p.isLocal)
            CHECK(!p.needsKey);
        if (p.needsKey)
            CHECK(!p.isLocal);
        if (![p.identifier isEqualToString:@"custom"])
            CHECK(p.defaultModel.length > 0);
        hasOpenAI |= [p.identifier isEqualToString:@"openai"];
        hasGemini |= [p.identifier isEqualToString:@"gemini"] && p.protocol == AIProtocolGemini;
        hasAnthropic |= [p.identifier isEqualToString:@"anthropic"] && p.protocol == AIProtocolAnthropic;
        hasDeepSeek |= [p.identifier isEqualToString:@"deepseek"];
        hasQwen |= [p.identifier isEqualToString:@"qwen"];
        hasLocal |= p.isLocal;
    }
    CHECK(hasOpenAI && hasGemini && hasAnthropic && hasDeepSeek && hasQwen && hasLocal);
    CHECK([AIProvider providerWithIdentifier:@"nonsense"] == nil);
    CHECK([[AIProvider defaultProvider].identifier isEqualToString:@"openai"]);
}

static void TestAddresses(void) {
    printf("-- addresses\n");
    NSString* reason = nil;
    CHECK([VOKAICleanBaseURL(@"https://api.openai.com/v1", &reason) isEqualToString:@"https://api.openai.com/v1"]);
    CHECK([VOKAICleanBaseURL(@"  https://api.openai.com/v1//  ", &reason) isEqualToString:@"https://api.openai.com/v1"]);
    CHECK(VOKAICleanBaseURL(@"HTTPS://Example.com/v1", &reason) != nil);
    //http only for this Mac and the local network
    CHECK(VOKAICleanBaseURL(@"http://localhost:11434/v1", &reason) != nil);
    CHECK(VOKAICleanBaseURL(@"http://127.0.0.1:1234/v1", &reason) != nil);
    CHECK(VOKAICleanBaseURL(@"http://192.168.1.20:11434/v1", &reason) != nil);
    CHECK(VOKAICleanBaseURL(@"http://10.0.0.5/v1", &reason) != nil);
    CHECK(VOKAICleanBaseURL(@"http://172.16.0.1/v1", &reason) != nil);
    CHECK(VOKAICleanBaseURL(@"http://[::1]:8080/v1", &reason) != nil);
    CHECK(VOKAICleanBaseURL(@"http://mac-mini.local:11434/v1", &reason) != nil);
    CHECK(VOKAICleanBaseURL(@"http://mac-mini:11434/v1", &reason) != nil);
    CHECK(VOKAICleanBaseURL(@"http://fdserver:8080/v1", &reason) != nil);
    //never in the clear over the internet, where the key could be read on the way
    reason = nil;
    CHECK(VOKAICleanBaseURL(@"http://api.openai.com/v1", &reason) == nil && reason.length > 0);
    CHECK(VOKAICleanBaseURL(@"http://8.8.8.8/v1", &reason) == nil);
    CHECK(VOKAICleanBaseURL(@"http://172.32.0.1/v1", &reason) == nil);          //just outside the private range
    CHECK(VOKAICleanBaseURL(@"http://192.169.1.1/v1", &reason) == nil);
    CHECK(VOKAICleanBaseURL(@"http://fcbarcelona.com/v1", &reason) == nil);
    CHECK(VOKAICleanBaseURL(@"http://localhost.evil.com/v1", &reason) == nil);
    CHECK(VOKAICleanBaseURL(@"http://127.0.0.1.evil.com/v1", &reason) == nil);
    //what is not an address of a server
    CHECK(VOKAICleanBaseURL(@"", &reason) == nil);
    CHECK(VOKAICleanBaseURL(@"   ", &reason) == nil);
    CHECK(VOKAICleanBaseURL(@"api.openai.com/v1", &reason) == nil);
    CHECK(VOKAICleanBaseURL(@"ftp://example.com/v1", &reason) == nil);
    CHECK(VOKAICleanBaseURL(@"file:///etc/passwd", &reason) == nil);
    CHECK(VOKAICleanBaseURL(@"https://user:pass@example.com/v1", &reason) == nil);   //the key does not go in the address
    CHECK(VOKAICleanBaseURL(@"https://example.com/v1?key=abc", &reason) == nil);
    CHECK(VOKAICleanBaseURL(@"https://example.com/v1#x", &reason) == nil);
    CHECK(VOKAICleanBaseURL(@"https://", &reason) == nil);
}

static void TestKeysAndRedaction(void) {
    printf("-- keys and redaction\n");
    NSString* reason = nil;
    CHECK([VOKAICleanKey(@"  sk-abc123  \n", &reason) isEqualToString:@"sk-abc123"]);
    CHECK([VOKAICleanKey(@"AIzaSyA-1_b", &reason) isEqualToString:@"AIzaSyA-1_b"]);
    CHECK(VOKAICleanKey(@"", &reason) == nil && reason.length > 0);
    CHECK(VOKAICleanKey(@" \n ", &reason) == nil);
    CHECK(VOKAICleanKey(@"sk-abc def", &reason) == nil);                       // a space inside: a copy gone wrong
    CHECK(VOKAICleanKey(@"sk-abc\ndef", &reason) == nil);                      // a line break would split a header
    CHECK(VOKAICleanKey(@"sk-abc\r\nX-Evil: 1", &reason) == nil);
    CHECK(VOKAICleanKey(@"sk-ábc", &reason) == nil);
    CHECK(VOKAICleanKey([@"" stringByPaddingToLength:600 withString:@"a" startingAtIndex:0], &reason) == nil);

    //the messages of servers sometimes repeat the key
    NSString* redacted = VOKAIRedact(@"Incorrect API key provided: my-secret-key-9999. Try again.", @"my-secret-key-9999");
    CHECK(![redacted containsString:@"my-secret-key-9999"] && [redacted containsString:@"Try again"]);
    CHECK(![VOKAIRedact(@"bad key sk-proj-ABCDEFGH123456", nil) containsString:@"ABCDEFGH123456"]);
    CHECK(![VOKAIRedact(@"bad key sk-ant-api03-XYZ_xyz-123456", nil) containsString:@"xyz-123456"]);
    CHECK(![VOKAIRedact(@"key=AIzaSyDdI0hCZtE6vySjMm-WEfRq3CPzqKqqsHI", nil) containsString:@"AIzaSyDdI0"]);
    CHECK(![VOKAIRedact(@"Authorization: Bearer abcdef0123456789xyz", nil) containsString:@"abcdef0123456789"]);
    CHECK([VOKAIRedact(@"nothing secret here", @"abc") isEqualToString:@"nothing secret here"]);
    CHECK([VOKAIRedact(nil, @"abc") length] == 0);
}

#pragma mark - Keychain

static void TestKeychain(void) {
    printf("-- keychain\n");
    NSString* original = AIKeychain.service;
    AIKeychain.service = [NSString stringWithFormat:@"vn.io.lssoft.vopenkey.test-%@.ai", [NSUUID UUID].UUIDString];
    NSString* service = AIKeychain.service;
    NSString* secret = @"sk-test-SECRET-0123456789";

    CHECK(![AIKeychain hasKeyForProvider:@"openai"]);
    CHECK([AIKeychain keyForProvider:@"openai"] == nil);
    NSError* error = nil;
    CHECK([AIKeychain setKey:secret forProvider:@"openai" error:&error]);
    CHECK(error == nil);
    CHECK([AIKeychain hasKeyForProvider:@"openai"]);
    CHECK([[AIKeychain keyForProvider:@"openai"] isEqualToString:secret]);

    //every provider has its own, and a key is replaced, not added
    CHECK(![AIKeychain hasKeyForProvider:@"gemini"]);
    CHECK([AIKeychain setKey:@"AIza-gemini-key" forProvider:@"gemini" error:nil]);
    CHECK([[AIKeychain keyForProvider:@"gemini"] isEqualToString:@"AIza-gemini-key"]);
    CHECK([[AIKeychain keyForProvider:@"openai"] isEqualToString:secret]);
    CHECK([AIKeychain setKey:@"sk-test-NEW-99" forProvider:@"openai" error:nil]);
    CHECK([[AIKeychain keyForProvider:@"openai"] isEqualToString:@"sk-test-NEW-99"]);
    NSDictionary* query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword, (__bridge id)kSecAttrService: service,
                            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll, (__bridge id)kSecReturnAttributes: @YES};
    CFTypeRef items = NULL;
    CHECK(SecItemCopyMatching((__bridge CFDictionaryRef)query, &items) == errSecSuccess);
    NSArray* list = CFBridgingRelease(items);
    CHECK(list.count == 2);

    //what the item says about itself: not synchronised, with a readable label
    for (NSDictionary* item in list) {
        id sync = item[(__bridge id)kSecAttrSynchronizable];
        CHECK(sync == nil || [sync isEqual:@NO] || [sync isEqual:@0]);
        CHECK([item[(__bridge id)kSecAttrLabel] hasPrefix:@"VOpenKey"]);
        CHECK([item[(__bridge id)kSecAttrService] isEqualToString:service]);
    }

    //the key is nowhere else: not in the preferences of this program
    NSString* all = [NSString stringWithFormat:@"%@", [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];
    CHECK(![all containsString:@"sk-test-NEW-99"] && ![all containsString:secret] && ![all containsString:@"AIza-gemini-key"]);

    CHECK(![AIKeychain setKey:@"" forProvider:@"openai" error:&error] && error != nil);
    CHECK([[AIKeychain keyForProvider:@"openai"] isEqualToString:@"sk-test-NEW-99"]);      //the failed call changed nothing

    //removing
    CHECK([AIKeychain removeKeyForProvider:@"openai"]);
    CHECK(![AIKeychain hasKeyForProvider:@"openai"] && [AIKeychain keyForProvider:@"openai"] == nil);
    CHECK([AIKeychain hasKeyForProvider:@"gemini"]);
    CHECK([AIKeychain removeKeyForProvider:@"openai"]);                      // nothing to remove is not an error
    CHECK([AIKeychain removeKeyForProvider:@"gemini"]);
    CHECK(![AIKeychain hasKeyForProvider:@"gemini"]);

    //another name is another keychain entry: a test build does not see the real app's keys
    CHECK([AIKeychain setKey:@"x-one" forProvider:@"openai" error:nil]);
    AIKeychain.service = [service stringByAppendingString:@".other"];
    CHECK(![AIKeychain hasKeyForProvider:@"openai"]);
    AIKeychain.service = service;
    CHECK([AIKeychain removeKeyForProvider:@"openai"]);
    CHECK(![AIKeychain hasKeyForProvider:@"openai"]);
    AIKeychain.service = original;
}

#pragma mark - Settings

static void TestSettings(void) {
    printf("-- settings\n");
    NSString* original = AIKeychain.service;
    AIKeychain.service = [NSString stringWithFormat:@"vn.io.lssoft.vopenkey.test-%@.ai", [NSUUID UUID].UUIDString];
    AIProvider* openai = [AIProvider providerWithIdentifier:@"openai"];
    AIProvider* ollama = [AIProvider providerWithIdentifier:@"ollama"];
    AIProvider* custom = [AIProvider providerWithIdentifier:@"custom"];

    //nothing is ready without a key, except what runs locally
    NSError* error = nil;
    CHECK(![AISettings isProviderReady:openai]);
    CHECK([AISettings configurationForProvider:openai error:&error] == nil && error.code == VOKAIErrorNoKey);
    CHECK([error.localizedDescription containsString:@"OpenAI"]);
    CHECK([AISettings isProviderReady:ollama]);
    AIConfiguration* local = [AISettings configurationForProvider:ollama error:&error];
    CHECK(local != nil && local.key == nil && [local.baseURL isEqualToString:@"http://localhost:11434/v1"] && [local.model isEqualToString:@"llama3.2"]);

    //with a key
    CHECK([AIKeychain setKey:@"sk-test-1" forProvider:@"openai" error:nil]);
    CHECK([AISettings isProviderReady:openai]);
    AIConfiguration* c = [AISettings configurationForProvider:openai error:&error];
    CHECK(c != nil && [c.key isEqualToString:@"sk-test-1"] && c.systemPrompt.length > 0);

    //models and addresses: the user's choice, or the provider's own
    CHECK([[AISettings modelForProvider:openai] isEqualToString:openai.defaultModel]);
    [AISettings setModel:@"  my-model  " forProvider:openai];
    CHECK([[AISettings modelForProvider:openai] isEqualToString:@"my-model"]);
    [AISettings setModel:openai.defaultModel forProvider:openai];                      // back to the default: nothing is kept
    CHECK([[NSUserDefaults standardUserDefaults] objectForKey:@"AIProvider.openai.model"] == nil);
    [AISettings setBaseURL:@"http://api.openai.com/v1" forProvider:openai];            // a bad address is kept as typed but refused when used
    CHECK([AISettings configurationForProvider:openai error:&error] == nil && error.code == VOKAIErrorBadAddress);
    CHECK(![AISettings isProviderReady:openai]);
    [AISettings setBaseURL:@"" forProvider:openai];
    CHECK([AISettings isProviderReady:openai]);

    //the custom provider needs an address and a model
    CHECK(![AISettings isProviderReady:custom]);
    [AISettings setBaseURL:@"http://192.168.1.9:8080/v1" forProvider:custom];
    CHECK(![AISettings isProviderReady:custom]);                                       // still no model
    [AISettings setModel:@"qwen2.5" forProvider:custom];
    CHECK([AISettings isProviderReady:custom]);
    CHECK([AISettings configurationForProvider:custom error:nil].key == nil);

    //the chosen provider
    AISettings.providerIdentifier = @"gemini";
    CHECK([AISettings.provider.identifier isEqualToString:@"gemini"]);
    AISettings.providerIdentifier = @"nonsense";
    CHECK([AISettings.provider.identifier isEqualToString:@"gemini"]);                 // an unknown name is ignored
    [[NSUserDefaults standardUserDefaults] setObject:@"gone" forKey:@"AIProvider"];
    CHECK([AISettings.provider.identifier isEqualToString:@"openai"]);                 // a name that no longer exists falls back

    //the instruction
    CHECK([AISettings.systemPrompt isEqualToString:[AISettings defaultSystemPrompt]]);
    AISettings.systemPrompt = @"Chỉ trả lời bằng thơ.";
    CHECK([AISettings.systemPrompt isEqualToString:@"Chỉ trả lời bằng thơ."]);
    AISettings.systemPrompt = @"   ";
    CHECK([AISettings.systemPrompt isEqualToString:[AISettings defaultSystemPrompt]]);

    //resetting forgets the choices and leaves the keys
    [AISettings resetToDefaults];
    CHECK([[AISettings modelForProvider:custom] isEqualToString:@""]);
    CHECK([[AISettings baseURLForProvider:custom] isEqualToString:@""]);
    CHECK([AIKeychain hasKeyForProvider:@"openai"]);

    [AIKeychain removeKeyForProvider:@"openai"];
    AIKeychain.service = original;
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[NSProcessInfo processInfo].processName];
}

#pragma mark - The reading of a stream

static NSArray<NSString*>* FeedByteByByte(AIProtocol protocol, NSString* stream, NSError** error, BOOL* finished) {
    AIStreamParser* parser = [[AIStreamParser alloc] initWithProtocol:protocol];
    NSData* data = [stream dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableArray* pieces = [NSMutableArray array];
    for (NSUInteger i = 0; i < data.length; i++) {
        NSError* e = nil;
        [pieces addObjectsFromArray:[parser feed:[data subdataWithRange:NSMakeRange(i, 1)] error:&e]];
        if (e != nil && error != NULL)
            *error = e;
    }
    if (finished != NULL) *finished = parser.finished;
    return pieces;
}

static void TestParser(void) {
    printf("-- stream parser\n");
    NSError* error = nil;
    BOOL finished = NO;

    //OpenAI: cut at every byte, so every Vietnamese letter and the emoji are cut in the middle
    NSString* openai = @"data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"\"}}]}\n\n"
                       @": comment\r\n\r\n"
                       @"data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"thinking\"}}]}\n\n"
                       @"data: {\"choices\":[{\"delta\":{\"content\":null}}]}\n\n"
                       @"data: {\"choices\":[{\"delta\":{\"content\":\"Xin chào\"}}]}\r\n\r\n"
                       @"data:{\"choices\":[{\"delta\":{\"content\":\" ❤️ đẹp\"}}]}\n\n"
                       @"data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
                       @"data: [DONE]\n\n";
    NSArray* pieces = FeedByteByByte(AIProtocolOpenAI, openai, &error, &finished);
    CHECK(error == nil && finished);
    CHECK([[pieces componentsJoinedByString:@""] isEqualToString:@"Xin chào ❤️ đẹp"]);

    //the reasoning written inside the text is not part of the answer; the tag is cut in the middle by the pieces
    error = nil;
    NSString* inlineThinking = @"data: {\"choices\":[{\"delta\":{\"content\":\"<thi\"}}]}\n\n"
                       @"data: {\"choices\":[{\"delta\":{\"content\":\"nk>suy nghĩ</th\"}}]}\n\n"
                       @"data: {\"choices\":[{\"delta\":{\"content\":\"ink>\\n\\nĐáp án\"}}]}\n\n"
                       @"data: [DONE]\n\n";
    pieces = FeedByteByByte(AIProtocolOpenAI, inlineThinking, &error, &finished);
    CHECK(error == nil && [[pieces componentsJoinedByString:@""] isEqualToString:@"Đáp án"]);
    //the other protocols are not touched by it
    pieces = FeedByteByByte(AIProtocolAnthropic, @"data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"<think>giữ nguyên</think>\"}}\n\n", &error, NULL);
    CHECK([[pieces componentsJoinedByString:@""] isEqualToString:@"<think>giữ nguyên</think>"]);
    //the end of the stream gives back what was held in case it was a tag
    AIStreamParser* tail = [[AIStreamParser alloc] initWithProtocol:AIProtocolOpenAI];
    NSMutableArray* tailPieces = [NSMutableArray arrayWithArray:[tail feed:[@"data: {\"choices\":[{\"delta\":{\"content\":\"<t\"}}]}\n\n" dataUsingEncoding:NSUTF8StringEncoding] error:nil]];
    CHECK(tailPieces.count == 0);
    [tailPieces addObjectsFromArray:[tail flush]];
    CHECK([[tailPieces componentsJoinedByString:@""] isEqualToString:@"<t"] && [tail flush].count == 0);

    //an error in the middle of the stream stops it
    error = nil;
    pieces = FeedByteByByte(AIProtocolOpenAI, @"data: {\"choices\":[{\"delta\":{\"content\":\"A\"}}]}\n\ndata: {\"error\":{\"message\":\"overloaded\",\"type\":\"overloaded_error\"}}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"B\"}}]}\n\n", &error, NULL);
    CHECK([[pieces componentsJoinedByString:@""] isEqualToString:@"A"]);                   // nothing after the error
    CHECK(error != nil && error.code == VOKAIErrorRateLimit && [error.localizedDescription containsString:@"overloaded"]);
    //"error": null is not an error
    error = nil;
    pieces = FeedByteByByte(AIProtocolOpenAI, @"data: {\"error\":null,\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n", &error, NULL);
    CHECK(error == nil && pieces.count == 1);

    //junk lines and a line that is not JSON do no harm
    error = nil;
    pieces = FeedByteByByte(AIProtocolOpenAI, @"event: ping\nretry: 10\nid: 4\ndata: not json\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"z\"}}]}\n\n", &error, NULL);
    CHECK(error == nil && [[pieces componentsJoinedByString:@""] isEqualToString:@"z"]);

    //Gemini: the parts that are thinking are not the answer, a block is an error
    error = nil;
    pieces = FeedByteByByte(AIProtocolGemini, @"data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"nghĩ\",\"thought\":true}]}}]}\r\n\r\n"
                                              @"data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Đáp \"},{\"text\":\"án\"}]},\"finishReason\":\"STOP\"}]}\r\n\r\n", &error, &finished);
    CHECK(error == nil && finished && [[pieces componentsJoinedByString:@""] isEqualToString:@"Đáp án"]);
    error = nil;
    FeedByteByByte(AIProtocolGemini, @"data: {\"promptFeedback\":{\"blockReason\":\"SAFETY\"}}\n\n", &error, NULL);
    CHECK(error != nil && error.code == VOKAIErrorRejected && [error.localizedDescription containsString:@"SAFETY"]);
    error = nil;
    FeedByteByByte(AIProtocolGemini, @"data: {\"candidates\":[{\"finishReason\":\"SAFETY\"}]}\n\n", &error, NULL);
    CHECK(error != nil && error.code == VOKAIErrorRejected);
    error = nil;
    FeedByteByByte(AIProtocolGemini, @"data: {\"error\":{\"code\":429,\"message\":\"quota\",\"status\":\"RESOURCE_EXHAUSTED\"}}\n\n", &error, NULL);
    CHECK(error != nil);

    //Anthropic
    error = nil;
    pieces = FeedByteByByte(AIProtocolAnthropic,
        @"event: message_start\ndata: {\"type\":\"message_start\",\"message\":{}}\n\n"
        @"event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Chào\"}}\n\n"
        @"event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{}\"}}\n\n"
        @"event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" bạn\"}}\n\n"
        @"event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n", &error, &finished);
    CHECK(error == nil && finished && [[pieces componentsJoinedByString:@""] isEqualToString:@"Chào bạn"]);
    error = nil;
    FeedByteByByte(AIProtocolAnthropic, @"event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}\n\n", &error, NULL);
    CHECK(error != nil && error.code == VOKAIErrorRateLimit);

    //an answer that was not streamed
    error = nil;
    NSData* complete = [@"{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Cả khối\"}}]}" dataUsingEncoding:NSUTF8StringEncoding];
    CHECK([[AIStreamParser textOfCompleteAnswer:complete protocol:AIProtocolOpenAI error:&error] isEqualToString:@"Cả khối"]);
    complete = [@"{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"<think>nghĩ</think>\\n\\nCả khối\"}}]}" dataUsingEncoding:NSUTF8StringEncoding];
    CHECK([[AIStreamParser textOfCompleteAnswer:complete protocol:AIProtocolOpenAI error:&error] isEqualToString:@"Cả khối"]);
    complete = [@"{\"content\":[{\"type\":\"text\",\"text\":\"A\"},{\"type\":\"text\",\"text\":\"B\"}]}" dataUsingEncoding:NSUTF8StringEncoding];
    CHECK([[AIStreamParser textOfCompleteAnswer:complete protocol:AIProtocolAnthropic error:&error] isEqualToString:@"AB"]);
    complete = [@"{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"G\"}]},\"finishReason\":\"STOP\"}]}" dataUsingEncoding:NSUTF8StringEncoding];
    CHECK([[AIStreamParser textOfCompleteAnswer:complete protocol:AIProtocolGemini error:&error] isEqualToString:@"G"]);
    complete = [@"{\"error\":{\"message\":\"nope\"}}" dataUsingEncoding:NSUTF8StringEncoding];
    error = nil;
    CHECK([AIStreamParser textOfCompleteAnswer:complete protocol:AIProtocolOpenAI error:&error] == nil && error != nil);
    CHECK([AIStreamParser textOfCompleteAnswer:[@"<html>" dataUsingEncoding:NSUTF8StringEncoding] protocol:AIProtocolOpenAI error:nil] == nil);
}

//the text of the answer after it went through the filter in pieces of `size` characters (0: all at once)
static NSString* Filtered(NSString* text, NSUInteger size) {
    AIThinkFilter* filter = [[AIThinkFilter alloc] init];
    NSMutableString* out = [NSMutableString string];
    NSUInteger step = size == 0 ? MAX(text.length, 1) : size;
    NSUInteger i = 0;
    while (i < text.length) {
        NSUInteger end = MIN(text.length, i + step);
        //do not cut a letter made of two units of UTF-16
        if (end < text.length && CFStringIsSurrogateHighCharacter([text characterAtIndex:end - 1]))
            end++;
        [out appendString:[filter feed:[text substringWithRange:NSMakeRange(i, end - i)]]];
        i = end;
    }
    [out appendString:[filter flush]];
    return out;
}

static void TestThinkFilter(void) {
    printf("-- reasoning in the text\n");
    NSArray<NSArray<NSString*>*>* cases = @[
        @[@"<think>hmm, let me see</think>\n\nXin chào", @"Xin chào"],
        @[@"  <think>\nsuy nghĩ\nnhiều dòng\n</think>\n\nĐáp án: <b>đậm</b>", @"Đáp án: <b>đậm</b>"],
        @[@"<think></think>Ngay sau", @"Ngay sau"],
        @[@"Không suy nghĩ gì cả", @"Không suy nghĩ gì cả"],
        @[@"  Chữ đầu có khoảng trắng", @"  Chữ đầu có khoảng trắng"],
        @[@"Trong HTML có thẻ <think> để làm gì đó</think>", @"Trong HTML có thẻ <think> để làm gì đó</think>"],      //not at the start: it is the answer
        @[@"<thinking>không phải thẻ này</thinking>", @"<thinking>không phải thẻ này</thinking>"],
        @[@"<th", @"<th"],                                                                  //the stream ended while it could still be a tag
        @[@"<think>chưa bao giờ đóng", @""],                                                //the reasoning never ended: there is no answer
        @[@"<think>a</think>X<think>b</think>Y", @"X<think>b</think>Y"],                    //only the first block is the reasoning
        @[@"<think>nghĩ</think>   \n  ", @""],
        @[@"<think>nghĩ </think> ❤️ 😀 xong", @"❤️ 😀 xong"],
        @[@"", @""],
    ];
    for (NSArray<NSString*>* c in cases) {
        for (NSNumber* size in @[@0, @1, @2, @3, @5, @7, @8, @9, @50]) {
            NSString* got = Filtered(c[0], size.unsignedIntegerValue);
            if (![got isEqualToString:c[1]])
                printf("  input %s in pieces of %d gave %s\n", [[c[0] description] UTF8String], size.intValue, [got UTF8String]);
            CHECK([got isEqualToString:c[1]]);
        }
    }
    //after the reasoning, later pieces pass untouched, spaces included
    AIThinkFilter* filter = [[AIThinkFilter alloc] init];
    NSMutableString* out = [NSMutableString string];
    for (NSString* piece in @[@"<think>x", @"</think>", @"\n\n", @"Xin", @" chào", @" ", @"bạn"])
        [out appendString:[filter feed:piece]];
    CHECK([out isEqualToString:@"Xin chào bạn"]);
}

#pragma mark - The requests

static void TestRequests(void) {
    printf("-- requests\n");
    NSError* error = nil;

    AIConfiguration* c = Config(@"openai", @"/v1", @"gpt-test", @"sk-test-777");
    NSURLRequest* r = [AIClient requestForConfiguration:c prompt:@"Dịch sang tiếng Anh: xin chào" error:&error];
    CHECK(r != nil);
    CHECK([r.HTTPMethod isEqualToString:@"POST"]);
    CHECK([r.URL.absoluteString isEqualToString:[gBase stringByAppendingString:@"/v1/chat/completions"]]);
    CHECK([[r valueForHTTPHeaderField:@"Authorization"] isEqualToString:@"Bearer sk-test-777"]);
    CHECK(![r.URL.absoluteString containsString:@"sk-test-777"]);
    NSDictionary* body = [NSJSONSerialization JSONObjectWithData:r.HTTPBody options:0 error:nil];
    CHECK([body[@"model"] isEqualToString:@"gpt-test"] && [body[@"stream"] boolValue]);
    NSArray* messages = body[@"messages"];
    CHECK(messages.count == 2 && [messages[0][@"role"] isEqualToString:@"system"] && [messages[0][@"content"] isEqualToString:@"Trả lời ngắn."]);
    CHECK([messages[1][@"role"] isEqualToString:@"user"] && [messages[1][@"content"] isEqualToString:@"Dịch sang tiếng Anh: xin chào"]);
    CHECK(![[[NSString alloc] initWithData:r.HTTPBody encoding:NSUTF8StringEncoding] containsString:@"sk-test-777"]);   // the key is not in the body either

    //no key (a server on this Mac): no header; no instruction: no system message
    c = Config(@"ollama", @"/v1", @"llama3.2", nil);
    c.systemPrompt = @"";
    r = [AIClient requestForConfiguration:c prompt:@"hi" error:&error];
    CHECK([r valueForHTTPHeaderField:@"Authorization"] == nil);
    CHECK([[NSJSONSerialization JSONObjectWithData:r.HTTPBody options:0 error:nil][@"messages"] count] == 1);

    //Gemini: the key in a header, never in the address; the model is part of the path
    c = Config(@"gemini", @"/v1beta", @"models/gemini-x y", @"AIza-key-1");
    r = [AIClient requestForConfiguration:c prompt:@"hi" error:&error];
    CHECK([r.URL.absoluteString isEqualToString:[gBase stringByAppendingString:@"/v1beta/models/gemini-x%20y:streamGenerateContent?alt=sse"]]);
    CHECK([[r valueForHTTPHeaderField:@"x-goog-api-key"] isEqualToString:@"AIza-key-1"]);
    CHECK(![r.URL.absoluteString containsString:@"AIza-key-1"] && [r valueForHTTPHeaderField:@"Authorization"] == nil);
    body = [NSJSONSerialization JSONObjectWithData:r.HTTPBody options:0 error:nil];
    CHECK([body[@"contents"][0][@"parts"][0][@"text"] isEqualToString:@"hi"] && [body[@"systemInstruction"][@"parts"][0][@"text"] isEqualToString:@"Trả lời ngắn."]);

    //Anthropic
    c = Config(@"anthropic", @"/anthropic/v1", @"claude-x", @"sk-ant-key-1");
    r = [AIClient requestForConfiguration:c prompt:@"hi" error:&error];
    CHECK([r.URL.path isEqualToString:@"/anthropic/v1/messages"]);
    CHECK([[r valueForHTTPHeaderField:@"x-api-key"] isEqualToString:@"sk-ant-key-1"] && [r valueForHTTPHeaderField:@"anthropic-version"].length > 0);
    body = [NSJSONSerialization JSONObjectWithData:r.HTTPBody options:0 error:nil];
    CHECK([body[@"system"] isEqualToString:@"Trả lời ngắn."] && [body[@"max_tokens"] intValue] > 0 && [body[@"stream"] boolValue]);

    //an address that is not allowed makes no request
    c = Config(@"openai", @"", @"m", @"k");
    c.baseURL = @"http://api.openai.com/v1";
    CHECK([AIClient requestForConfiguration:c prompt:@"hi" error:&error] == nil && error.code == VOKAIErrorBadAddress);
}

#pragma mark - Against the fake server

static void ExpectTextInPieces(NSString* title, AIConfiguration* c, NSString* expected, NSUInteger minPieces) {
    NSString* text = nil;
    NSError* error = nil;
    NSUInteger pieces = 0;
    Generate(c, @"Chào", &text, &error, &pieces);
    if (error != nil || ![text isEqualToString:expected]) {
        printf("FAIL %s: got \"%s\", error \"%s\"\n", title.UTF8String, text.UTF8String, error.localizedDescription.UTF8String);
        failures++;
    }
    CHECK(pieces >= minPieces);                             // it came as a stream, in pieces
}

static void ExpectText(NSString* title, AIConfiguration* c, NSString* expected) {
    ExpectTextInPieces(title, c, expected, 2);
}

static NSError* ExpectError(NSString* title, AIConfiguration* c, VOKAIErrorCode code) {
    NSString* text = nil;
    NSError* error = nil;
    Generate(c, @"Chào", &text, &error, NULL);
    if (error == nil || error.code != code) {
        printf("FAIL %s: expected error %ld, got %ld (%s)\n", title.UTF8String, (long)code, (long)error.code, error.localizedDescription.UTF8String);
        failures++;
    }
    return error;
}

static void TestServer(void) {
    printf("-- against the fake server\n");
    NSString* normal = @"Xin chào các bạn ❤️ đẹp";

    // the three ways of talking
    ExpectText(@"openai", Config(@"openai", @"/v1", @"normal", kGoodKey), normal);
    ExpectText(@"gemini", Config(@"gemini", @"/v1beta", @"normal", kGoodKey), normal);
    ExpectText(@"anthropic", Config(@"anthropic", @"/anthropic/v1", @"normal", kGoodKey), normal);

    //what the server received
    NSDictionary* last = LastRequestOfServer()[@"last"];
    CHECK([last[@"path"] isEqualToString:@"/anthropic/v1/messages"]);
    CHECK([last[@"headers"][@"x-api-key"] isEqualToString:kGoodKey]);
    ExpectText(@"openai again", Config(@"openai", @"/v1", @"normal", kGoodKey), normal);
    last = LastRequestOfServer()[@"last"];
    CHECK([last[@"headers"][@"authorization"] isEqualToString:@"Bearer test-key-123"]);
    CHECK([last[@"body"][@"model"] isEqualToString:@"normal"] && [last[@"body"][@"stream"] boolValue]);
    CHECK([last[@"body"][@"messages"][1][@"content"] isEqualToString:@"Chào"]);
    CHECK(![last[@"path"] containsString:kGoodKey]);
    CHECK(last[@"headers"][@"cookie"] == nil);

    //a server on this Mac with no key at all
    ExpectText(@"no key", Config(@"ollama", @"/v1", @"normal", nil), normal);
    last = LastRequestOfServer()[@"last"];
    CHECK(last[@"headers"][@"authorization"] == nil);

    //the models that think first, and an answer that is not a stream
    ExpectText(@"reasoning written in the text", Config(@"openai", @"/v1", @"thinkinline", kGoodKey), normal);
    ExpectTextInPieces(@"answer that is only the start of a tag", Config(@"openai", @"/v1", @"thinktail", kGoodKey), @"<t", 1);
    ExpectTextInPieces(@"gemini thinking", Config(@"gemini", @"/v1beta", @"thinking", kGoodKey), @"Đáp án", 1);
    NSString* text = nil;
    NSError* error = nil;
    Generate(Config(@"openai", @"/v1", @"plain", kGoodKey), @"hi", &text, &error, NULL);
    CHECK(error == nil && [text isEqualToString:@"Trả lời nguyên khối"]);

    //the key is wrong: a clear message, and the key never in it
    AIConfiguration* wrong = Config(@"openai", @"/v1", @"normal", @"wrong-key-4567890");
    error = ExpectError(@"openai 401", wrong, VOKAIErrorAuthentication);
    CHECK(error != nil && ![error.localizedDescription containsString:@"wrong-key-4567890"]);
    CHECK([error.localizedDescription containsString:@"OpenAI"]);
    wrong = Config(@"gemini", @"/v1beta", @"normal", @"AIzaSyWrongKeyForTesting123");
    error = ExpectError(@"gemini 403", wrong, VOKAIErrorAuthentication);
    CHECK(error != nil && ![error.localizedDescription containsString:@"AIzaSyWrongKeyForTesting123"]);
    wrong = Config(@"anthropic", @"/anthropic/v1", @"normal", @"sk-ant-wrong-key-1234567");
    error = ExpectError(@"anthropic 401", wrong, VOKAIErrorAuthentication);
    CHECK(error != nil && ![error.localizedDescription containsString:@"sk-ant-wrong-key-1234567"]);

    //the other failures
    error = ExpectError(@"404", Config(@"openai", @"/v1", @"missing", kGoodKey), VOKAIErrorModel);
    CHECK([error.localizedDescription containsString:@"missing"]);
    ExpectError(@"429", Config(@"openai", @"/v1", @"limited", kGoodKey), VOKAIErrorRateLimit);
    ExpectError(@"500", Config(@"openai", @"/v1", @"boom", kGoodKey), VOKAIErrorServer);
    ExpectError(@"empty", Config(@"openai", @"/v1", @"empty", kGoodKey), VOKAIErrorEmpty);
    error = ExpectError(@"mid-stream", Config(@"openai", @"/v1", @"midstream", kGoodKey), VOKAIErrorRateLimit);
    CHECK([error.localizedDescription containsString:@"overloaded"]);
    ExpectError(@"gemini blocked", Config(@"gemini", @"/v1beta", @"blocked", kGoodKey), VOKAIErrorRejected);
    ExpectError(@"anthropic error event", Config(@"anthropic", @"/anthropic/v1", @"err", kGoodKey), VOKAIErrorRateLimit);

    //a redirect is not followed: the key must not go to another address
    NSDictionary* before = LastRequestOfServer();
    int stolenBefore = [before[@"stolen"] intValue];
    error = ExpectError(@"redirect", Config(@"openai", @"/v1", @"redirect", kGoodKey), VOKAIErrorServer);
    CHECK([error.localizedDescription containsString:@"chuyển hướng"]);
    CHECK([LastRequestOfServer()[@"stolen"] intValue] == stolenBefore);

    //nothing listens: a message that names the program for a local server
    AIConfiguration* nobody = Config(@"ollama", @"/v1", @"normal", nil);
    nobody.baseURL = @"http://127.0.0.1:1/v1";
    error = ExpectError(@"refused", nobody, VOKAIErrorNetwork);
    CHECK([error.localizedDescription containsString:@"Ollama"]);
    nobody = Config(@"openai", @"/v1", @"normal", kGoodKey);
    nobody.baseURL = @"http://127.0.0.1:1/v1";
    error = ExpectError(@"refused remote", nobody, VOKAIErrorNetwork);
    CHECK(![error.localizedDescription containsString:kGoodKey]);

    //an address that is not allowed
    AIConfiguration* clear = Config(@"openai", @"/v1", @"normal", kGoodKey);
    clear.baseURL = @"http://api.openai.com/v1";
    ExpectError(@"http over the internet", clear, VOKAIErrorBadAddress);
}

static void TestCancel(void) {
    printf("-- cancelling\n");
    __block NSUInteger pieces = 0;
    __block BOOL completed = NO;
    AIClient* client = [[AIClient alloc] initWithConfiguration:Config(@"openai", @"/v1", @"slow", kGoodKey)];
    __block AIClient* weakClient = client;
    [client generateWithPrompt:@"hi" onText:^(NSString* piece) {
        pieces++;
        if (pieces == 2)
            [weakClient cancel];
    } completion:^(NSError* e) { completed = YES; }];
    SpinUntil(^BOOL { return pieces >= 2; }, 10);
    NSUInteger atCancel = pieces;
    Spin(1.0);                                              // the server goes on for 3 s
    CHECK(atCancel == 2);
    CHECK(pieces == atCancel);                              // nothing is delivered after the cancel
    CHECK(!completed);                                      // and no completion either
    Spin(0.5);
    CHECK([LastRequestOfServer()[@"slow_aborted"] intValue] >= 1);  // the server saw the connection closed
}

static void TestModelList(void) {
    printf("-- list of models\n");
    __block NSArray* models = nil;
    __block NSError* error = nil;
    __block BOOL done = NO;
    void (^list)(AIConfiguration*) = ^(AIConfiguration* c) {
        models = nil; error = nil; done = NO;
        [AIClient listModelsForConfiguration:c completion:^(NSArray<NSString*>* m, NSError* e) { models = m; error = e; done = YES; }];
        SpinUntil(^BOOL { return done; }, 10);
    };

    // OpenAI style: sorted the way a person reads numbers, no text-embedding or whisper for api.openai.com only
    list(Config(@"ollama", @"/v1", @"x", nil));
    CHECK(error == nil);
    NSArray* expected = @[@"alpha-1", @"alpha-2", @"alpha-10", @"gpt-4o-mini", @"text-embedding-3-small", @"whisper-1", @"zeta-large"];
    CHECK([models isEqualToArray:expected]);
    AIConfiguration* openai = Config(@"openai", @"/v1", @"x", kGoodKey);
    openai.baseURL = [gBase stringByAppendingString:@"/v1"];
    list(openai);
    CHECK([models containsObject:@"alpha-1"]);                       //the fake is not api.openai.com: nothing is filtered out

    list(Config(@"gemini", @"/v1beta", @"x", kGoodKey));
    CHECK(error == nil && [models isEqualToArray:@[@"gemini-flash-latest", @"gemini-pro-latest"]]);   // no embeddings, no "models/"
    list(Config(@"anthropic", @"/anthropic/v1", @"x", kGoodKey));
    CHECK(error == nil && [models isEqualToArray:@[@"claude-a", @"claude-b"]]);

    // the same call tells that a key does not work
    list(Config(@"gemini", @"/v1beta", @"x", @"AIzaSyWrongKeyForTesting123"));
    CHECK(models == nil && error.code == VOKAIErrorAuthentication && ![error.localizedDescription containsString:@"AIzaSyWrongKeyForTesting123"]);
    list(Config(@"anthropic", @"/anthropic/v1", @"x", @"sk-ant-wrong"));
    CHECK(models == nil && error.code == VOKAIErrorAuthentication);
    AIConfiguration* bad = Config(@"openai", @"/v1", @"x", kGoodKey);
    bad.baseURL = @"http://api.openai.com/v1";
    list(bad);
    CHECK(models == nil && error.code == VOKAIErrorBadAddress);
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 2) {
            printf("usage: ai_test <port>\n");
            return 2;
        }
        gBase = [NSString stringWithFormat:@"http://127.0.0.1:%s", argv[1]];
        TestProviders();
        TestAddresses();
        TestKeysAndRedaction();
        TestKeychain();
        TestSettings();
        TestParser();
        TestThinkFilter();
        TestRequests();
        TestServer();
        TestCancel();
        TestModelList();
        printf(failures ? "\n%d FAILURES\n" : "ALL OK\n", failures);
    }
    return failures ? 1 : 0;
}
