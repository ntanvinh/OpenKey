//
//  AIClient.m
//  VOpenKey
//

#import "AIClient.h"
#import "AIAgentCLI.h"
#import "AIAgentRunner.h"
#import "AppInfo.h"

static NSError* MakeError(VOKAIErrorCode code, NSString* message) {
    return [NSError errorWithDomain:VOKAIErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString* Shorten(NSString* text, NSUInteger limit) {
    return text.length <= limit ? text : [[text substringToIndex:limit] stringByAppendingString:@"…"];
}

//what a server says in the body of an error, in whatever shape: {"error":{"message":..}}, {"error":".."}, {"message":..}, {"detail":..}
static NSString* ServerMessage(id json) {
    if ([json isKindOfClass:[NSDictionary class]]) {
        id error = json[@"error"];
        if ([error isKindOfClass:[NSDictionary class]] && [error[@"message"] isKindOfClass:[NSString class]])
            return error[@"message"];
        if ([error isKindOfClass:[NSString class]])
            return error;
        for (NSString* key in @[@"message", @"detail", @"msg"])
            if ([json[key] isKindOfClass:[NSString class]])
                return json[key];
    } else if ([json isKindOfClass:[NSArray class]] && [json count] > 0) {
        return ServerMessage(json[0]); //Gemini wraps an error in a list at times
    }
    return nil;
}

//the message of an error found in the stream or in the body: what to tell and which kind it is
static NSError* ErrorFromJSON(id json, NSString* key) {
    NSString* message = ServerMessage(json);
    if (message.length == 0)
        return nil;
    NSString* type = @"";
    id error = [json isKindOfClass:[NSDictionary class]] ? json[@"error"] : nil;
    if ([error isKindOfClass:[NSDictionary class]]) {
        type = [NSString stringWithFormat:@"%@ %@", error[@"type"] ?: @"", error[@"code"] ?: @""].lowercaseString;
    }
    VOKAIErrorCode code = VOKAIErrorServer;
    if ([type containsString:@"auth"] || [type containsString:@"api_key"] || [type containsString:@"invalid_key"] || [type containsString:@"permission"])
        code = VOKAIErrorAuthentication;
    else if ([type containsString:@"rate"] || [type containsString:@"quota"] || [type containsString:@"overloaded"])
        code = VOKAIErrorRateLimit;
    else if ([type containsString:@"model"] || [type containsString:@"not_found"])
        code = VOKAIErrorModel;
    return MakeError(code, [NSString stringWithFormat:@"AI báo lỗi: %@", Shorten(VOKAIRedact(message, key), 240)]);
}

#pragma mark - Reasoning in the text

static NSString* const kThinkOpen = @"<think>";
static NSString* const kThinkClose = @"</think>";

@implementation AIThinkFilter {
    enum { Undecided, Thinking, Passing } _state;
    NSMutableString* _held;                 //undecided: what came so far; thinking: the end of it, which may start the closing tag
    BOOL _trimStart;                        //right after the reasoning, the blank lines that separate it from the answer are dropped
}

-(instancetype)init {
    self = [super init];
    if (self) {
        _state = Undecided;
        _held = [NSMutableString string];
    }
    return self;
}

-(NSString*)take:(NSString*)text {
    if (!_trimStart || text.length == 0)
        return text;
    NSRange first = [text rangeOfCharacterFromSet:[[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet]];
    if (first.location == NSNotFound)
        return @"";
    _trimStart = NO;
    return [text substringFromIndex:first.location];
}

-(NSString*)feed:(NSString*)text {
    if (text.length == 0)
        return @"";
    if (_state == Passing)
        return [self take:text];
    [_held appendString:text];
    if (_state == Undecided) {
        NSString* start = [_held stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (start.length == 0)
            return @"";                                        //only blanks so far
        if (start.length < kThinkOpen.length && [kThinkOpen hasPrefix:start])
            return @"";                                        //could still become the opening tag
        if (![start hasPrefix:kThinkOpen]) {
            _state = Passing;
            NSString* all = [_held copy];
            [_held setString:@""];
            return all;
        }
        NSRange tag = [_held rangeOfString:kThinkOpen];
        [_held setString:[_held substringFromIndex:NSMaxRange(tag)]];
        _state = Thinking;
    }
    //inside the reasoning: everything is dropped up to the closing tag
    NSRange close = [_held rangeOfString:kThinkClose];
    if (close.location != NSNotFound) {
        NSString* answer = [_held substringFromIndex:NSMaxRange(close)];
        [_held setString:@""];
        _state = Passing;
        _trimStart = YES;
        return [self take:answer];
    }
    if (_held.length > kThinkClose.length)                     //only the end can be the start of the closing tag
        [_held deleteCharactersInRange:NSMakeRange(0, _held.length - (kThinkClose.length - 1))];
    return @"";
}

-(NSString*)flush {
    NSString* rest = _state == Undecided ? [_held copy] : @"";
    [_held setString:@""];
    _state = Passing;
    return rest;
}

@end

#pragma mark - The stream

@implementation AIStreamParser {
    AIProtocol _protocol;
    NSMutableData* _buffer;
    BOOL _stopped;
    AIThinkFilter* _thinkFilter;            //only for the services that speak the OpenAI way: see AIThinkFilter
}

-(instancetype)initWithProtocol:(AIProtocol)protocol {
    self = [super init];
    if (self) {
        _protocol = protocol;
        _buffer = [NSMutableData data];
        _thinkFilter = protocol == AIProtocolOpenAI ? [[AIThinkFilter alloc] init] : nil;
    }
    return self;
}

-(NSArray<NSString*>*)flush {
    NSString* rest = [_thinkFilter flush];
    return rest.length > 0 ? @[rest] : @[];
}

-(NSArray<NSString*>*)feed:(NSData*)data error:(NSError**)error {
    if (_stopped)
        return @[];
    [_buffer appendData:data];
    NSMutableArray<NSString*>* pieces = [NSMutableArray array];
    //a line is complete at its line feed, and a line feed is never inside a letter: lines can be decoded as soon as they are whole
    const uint8_t* bytes = _buffer.bytes;
    NSUInteger start = 0, length = _buffer.length;
    for (NSUInteger i = 0; i < length && !_stopped; i++) {
        if (bytes[i] != '\n')
            continue;
        NSUInteger end = i;
        if (end > start && bytes[end - 1] == '\r')
            end--;
        NSData* lineData = [NSData dataWithBytes:bytes + start length:end - start];
        start = i + 1;
        NSString* line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
        if (line == nil)
            continue;
        NSError* lineError = nil;
        NSString* piece = [self textOfLine:line error:&lineError];
        if (piece.length > 0)
            [pieces addObject:piece];
        if (lineError != nil) {
            _stopped = YES;
            if (error != NULL)
                *error = lineError;
        }
    }
    [_buffer replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
    //a stream that ends without a final line feed
    if (_buffer.length > 0 && _buffer.length > 1 << 20)
        [_buffer setLength:0];
    return pieces;
}

-(NSString*)textOfLine:(NSString*)line error:(NSError**)error {
    if (![line hasPrefix:@"data:"])
        return nil; //"event:", comments (":"), blank lines
    NSString* payload = [[line substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (payload.length == 0)
        return nil;
    if ([payload isEqualToString:@"[DONE]"]) {
        _finished = YES;
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:[payload dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]])
        return nil;
    NSError* problem = ErrorFromJSON(json, nil);
    if (problem != nil && json[@"error"] != nil) {
        *error = problem;
        return nil;
    }
    switch (_protocol) {
        case AIProtocolOpenAI: return [self openAIText:json];
        case AIProtocolGemini: return [self geminiText:json error:error];
        case AIProtocolAnthropic: return [self anthropicText:json error:error];
        case AIProtocolAgentCLI: return nil;        //a program prints its text, it does not answer in JSON
    }
    return nil;
}

-(NSString*)openAIText:(NSDictionary*)json {
    NSArray* choices = json[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || choices.count == 0)
        return nil;
    NSDictionary* choice = choices[0];
    if (![choice isKindOfClass:[NSDictionary class]])
        return nil;
    if ([choice[@"finish_reason"] isKindOfClass:[NSString class]] && [choice[@"finish_reason"] length] > 0)
        _finished = YES;
    NSDictionary* delta = choice[@"delta"];
    id content = [delta isKindOfClass:[NSDictionary class]] ? delta[@"content"] : nil; //"reasoning_content" is the thinking, not the answer
    if (![content isKindOfClass:[NSString class]])
        return nil;
    NSString* answer = [_thinkFilter feed:content];                                      //and so is what is between <think> and </think>
    return answer.length > 0 ? answer : nil;
}

-(NSString*)geminiText:(NSDictionary*)json error:(NSError**)error {
    NSDictionary* feedback = json[@"promptFeedback"];
    if ([feedback isKindOfClass:[NSDictionary class]] && [feedback[@"blockReason"] isKindOfClass:[NSString class]]) {
        *error = MakeError(VOKAIErrorRejected, [NSString stringWithFormat:@"Gemini từ chối yêu cầu này (%@).", feedback[@"blockReason"]]);
        return nil;
    }
    NSArray* candidates = json[@"candidates"];
    if (![candidates isKindOfClass:[NSArray class]] || candidates.count == 0)
        return nil;
    NSDictionary* candidate = candidates[0];
    NSMutableString* text = [NSMutableString string];
    NSDictionary* content = candidate[@"content"];
    for (NSDictionary* part in ([content isKindOfClass:[NSDictionary class]] ? content[@"parts"] : @[])) {
        if (![part isKindOfClass:[NSDictionary class]] || [part[@"thought"] boolValue])
            continue; //what the model thought before answering is not the answer
        if ([part[@"text"] isKindOfClass:[NSString class]])
            [text appendString:part[@"text"]];
    }
    NSString* finish = candidate[@"finishReason"];
    if ([finish isKindOfClass:[NSString class]] && finish.length > 0 && ![finish isEqualToString:@"STOP"] && ![finish isEqualToString:@"MAX_TOKENS"] && text.length == 0) {
        *error = MakeError(VOKAIErrorRejected, [NSString stringWithFormat:@"Gemini không trả lời được (%@).", finish]);
        return nil;
    }
    if ([finish isKindOfClass:[NSString class]] && finish.length > 0)
        _finished = YES;
    return text.length > 0 ? text : nil;
}

-(NSString*)anthropicText:(NSDictionary*)json error:(NSError**)error {
    NSString* type = json[@"type"];
    if ([type isEqualToString:@"message_stop"]) {
        _finished = YES;
        return nil;
    }
    if ([type isEqualToString:@"content_block_delta"]) {
        NSDictionary* delta = json[@"delta"];
        if ([delta isKindOfClass:[NSDictionary class]] && [delta[@"type"] isEqualToString:@"text_delta"] && [delta[@"text"] isKindOfClass:[NSString class]])
            return delta[@"text"];
    }
    return nil;
}

+(NSString*)textOfCompleteAnswer:(NSData*)data protocol:(AIProtocol)protocol error:(NSError**)error {
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]])
        return nil;
    NSError* problem = ErrorFromJSON(json, nil);
    if (problem != nil && json[@"error"] != nil) {
        if (error != NULL)
            *error = problem;
        return nil;
    }
    switch (protocol) {
        case AIProtocolOpenAI: {
            NSArray* choices = json[@"choices"];
            NSDictionary* message = [choices isKindOfClass:[NSArray class]] && choices.count > 0 ? choices[0][@"message"] : nil;
            id content = [message isKindOfClass:[NSDictionary class]] ? message[@"content"] : nil;
            if (![content isKindOfClass:[NSString class]])
                return nil;
            AIThinkFilter* filter = [[AIThinkFilter alloc] init];
            NSString* answer = [[filter feed:content] stringByAppendingString:[filter flush]];
            return answer.length > 0 ? answer : nil;
        }
        case AIProtocolGemini: {
            AIStreamParser* parser = [[AIStreamParser alloc] initWithProtocol:AIProtocolGemini];
            return [parser geminiText:json error:error];
        }
        case AIProtocolAnthropic: {
            NSMutableString* text = [NSMutableString string];
            for (NSDictionary* block in ([json[@"content"] isKindOfClass:[NSArray class]] ? json[@"content"] : @[]))
                if ([block isKindOfClass:[NSDictionary class]] && [block[@"text"] isKindOfClass:[NSString class]])
                    [text appendString:block[@"text"]];
            return text.length > 0 ? text : nil;
        }
        case AIProtocolAgentCLI:
            return nil;
    }
    return nil;
}

@end

#pragma mark - The request

static NSURLSession* MakeSession(id<NSURLSessionDelegate> delegate, NSOperationQueue* queue, NSTimeInterval idleTimeout) {
    NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    configuration.HTTPShouldSetCookies = NO;
    configuration.URLCredentialStorage = nil;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    configuration.timeoutIntervalForRequest = idleTimeout; //between two pieces of data, not for the whole answer
    configuration.timeoutIntervalForResource = 600;
    return [NSURLSession sessionWithConfiguration:configuration delegate:delegate delegateQueue:queue];
}

static NSString* ModelPathComponent(NSString* model) {
    NSString* name = [model hasPrefix:@"models/"] ? [model substringFromIndex:7] : model;
    return [name stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
}

static void SetKeyHeaders(NSMutableURLRequest* request, AIConfiguration* c) {
    if (c.key.length == 0)
        return;
    switch (c.provider.protocol) {
        case AIProtocolOpenAI:
            [request setValue:[@"Bearer " stringByAppendingString:c.key] forHTTPHeaderField:@"Authorization"];
            break;
        case AIProtocolGemini:
            [request setValue:c.key forHTTPHeaderField:@"x-goog-api-key"];
            break;
        case AIProtocolAnthropic:
            [request setValue:c.key forHTTPHeaderField:@"x-api-key"];
            [request setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
            break;
        case AIProtocolAgentCLI:
            break;      //a program that is signed in by itself: there is no request and no key
    }
}

@interface AIClient () <NSURLSessionDataDelegate>
@end

@implementation AIClient {
    AIConfiguration* _configuration;
    NSURLSession* _session;
    NSURLSessionDataTask* _task;
    NSOperationQueue* _queue;
    AIStreamParser* _parser;
    AIAgentRunner* _runner;         //for an agent program, which is run instead of a request being sent

    void (^_onText)(NSString*);
    void (^_completion)(NSError*);
    BOOL _cancelled;
    BOOL _delivered;

    //touched only on the session's own queue
    NSInteger _status;
    BOOL _streaming;
    NSMutableData* _body;
    NSError* _streamError;
    NSUInteger _pieces;
}

+(NSURLRequest*)requestForConfiguration:(AIConfiguration*)c prompt:(NSString*)prompt error:(NSError**)error {
    NSString* reason = nil;
    NSString* base = VOKAICleanBaseURL(c.baseURL, &reason);
    if (base == nil) {
        if (error != NULL)
            *error = MakeError(VOKAIErrorBadAddress, reason);
        return nil;
    }
    NSString* address;
    NSDictionary* body;
    switch (c.provider.protocol) {
        case AIProtocolOpenAI: {
            NSMutableArray* messages = [NSMutableArray array];
            if (c.systemPrompt.length > 0)
                [messages addObject:@{@"role": @"system", @"content": c.systemPrompt}];
            [messages addObject:@{@"role": @"user", @"content": prompt}];
            address = [base stringByAppendingString:@"/chat/completions"];
            body = @{@"model": c.model, @"messages": messages, @"stream": @YES};
            break;
        }
        case AIProtocolGemini: {
            NSMutableDictionary* b = [@{@"contents": @[@{@"role": @"user", @"parts": @[@{@"text": prompt}]}]} mutableCopy];
            if (c.systemPrompt.length > 0)
                b[@"systemInstruction"] = @{@"parts": @[@{@"text": c.systemPrompt}]};
            address = [NSString stringWithFormat:@"%@/models/%@:streamGenerateContent?alt=sse", base, ModelPathComponent(c.model)];
            body = b;
            break;
        }
        case AIProtocolAnthropic: {
            NSMutableDictionary* b = [@{@"model": c.model, @"max_tokens": @4096, @"stream": @YES,
                                        @"messages": @[@{@"role": @"user", @"content": prompt}]} mutableCopy];
            if (c.systemPrompt.length > 0)
                b[@"system"] = c.systemPrompt;
            address = [base stringByAppendingString:@"/messages"];
            body = b;
            break;
        }
        case AIProtocolAgentCLI:
            if (error != NULL)
                *error = MakeError(VOKAIErrorServer, @"Chương trình AI trên máy không nhận yêu cầu qua mạng.");
            return nil;
    }
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:address]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"text/event-stream, application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"%@/%@", VOK_APP_NAME, [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0"]
   forHTTPHeaderField:@"User-Agent"];
    SetKeyHeaders(request, c);
    return request;
}

-(instancetype)initWithConfiguration:(AIConfiguration*)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 1;
        _parser = [[AIStreamParser alloc] initWithProtocol:configuration.provider.protocol];
    }
    return self;
}

-(void)generateWithPrompt:(NSString*)prompt onText:(void (^)(NSString*))onText completion:(void (^)(NSError*))completion {
    if (_configuration.provider.isAgentCLI) {
        _runner = [[AIAgentRunner alloc] initWithConfiguration:_configuration];
        [_runner generateWithPrompt:prompt onText:onText completion:completion];
        return;
    }
    _onText = [onText copy];
    _completion = [completion copy];
    NSError* error = nil;
    NSURLRequest* request = [AIClient requestForConfiguration:_configuration prompt:prompt error:&error];
    if (request == nil) {
        [self deliverError:error];
        return;
    }
    _body = [NSMutableData data];
    _session = MakeSession(self, _queue, 45);
    _task = [_session dataTaskWithRequest:request];
    [_task resume];
}

-(void)generateImageWithPrompt:(NSString*)prompt onNote:(void (^)(NSString*))onNote completion:(void (^)(NSURL*, NSError*))completion {
    if (!_configuration.provider.isAgentCLI || ![AIAgentCLI forProvider:_configuration.provider].canMakeImages) {
        NSError* error = MakeError(VOKAIErrorServer, @"Dịch vụ này không tạo được ảnh. Chọn Codex CLI trong Cài đặt > AI.");
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
        return;
    }
    _runner = [[AIAgentRunner alloc] initWithConfiguration:_configuration];
    [_runner generateImageWithPrompt:prompt onNote:onNote completion:completion];
}

-(void)cancel {
    _cancelled = YES;
    _onText = nil;
    _completion = nil;
    [_runner cancel];
    [_task cancel];
    [_session invalidateAndCancel];
}

#pragma mark Delivering

-(void)deliverText:(NSString*)piece {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_cancelled && self->_onText != nil)
            self->_onText(piece);
    });
}

-(void)deliverError:(NSError*)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_cancelled || self->_delivered)
            return;
        self->_delivered = YES;
        void (^completion)(NSError*) = self->_completion;
        self->_completion = nil;
        self->_onText = nil;
        [self->_session finishTasksAndInvalidate];
        if (completion != nil)
            completion(error);
    });
}

#pragma mark Session delegate

-(void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task didReceiveResponse:(NSURLResponse*)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
    _status = [http isKindOfClass:[NSHTTPURLResponse class]] ? http.statusCode : 0;
    NSString* type = [http isKindOfClass:[NSHTTPURLResponse class]] ? [http valueForHTTPHeaderField:@"Content-Type"].lowercaseString : @"";
    _streaming = _status >= 200 && _status < 300 && [type containsString:@"event-stream"];
    completionHandler(NSURLSessionResponseAllow);
}

-(void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task didReceiveData:(NSData*)data {
    if (_streaming) {
        if (_streamError != nil)
            return;
        NSError* error = nil;
        for (NSString* piece in [_parser feed:data error:&error]) {
            _pieces++;
            [self deliverText:piece];
        }
        if (error != nil) {
            _streamError = error;
            [task cancel]; //nothing more to read
        }
    } else if (_body.length < 1 << 20) { //an error or a complete answer: whole, but not without limit
        [_body appendData:data];
    }
}

//a redirect would send the key to another address than the one the user chose
-(void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task willPerformHTTPRedirection:(NSHTTPURLResponse*)response
        newRequest:(NSURLRequest*)request completionHandler:(void (^)(NSURLRequest*))completionHandler {
    completionHandler(nil);
}

-(void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
    NSString* key = _configuration.key;
    if (_streamError != nil) {
        [self deliverError:_streamError];
        return;
    }
    if (error != nil) {
        [self deliverError:[AIClient errorFromTransport:error configuration:_configuration]];
        return;
    }
    if (_status < 200 || _status >= 300) {
        [self deliverError:[AIClient errorForStatus:_status body:_body configuration:_configuration]];
        return;
    }
    if (_streaming) {
        for (NSString* piece in [_parser flush]) {          //what was held back in case it was a tag
            _pieces++;
            [self deliverText:piece];
        }
    } else { //the whole answer in one piece
        NSError* problem = nil;
        NSString* text = [AIStreamParser textOfCompleteAnswer:_body protocol:_configuration.provider.protocol error:&problem];
        if (problem != nil) {
            [self deliverError:problem];
            return;
        }
        if (text.length > 0) {
            _pieces++;
            [self deliverText:text];
        }
    }
    if (_pieces == 0) {
        (void)key;
        [self deliverError:MakeError(VOKAIErrorEmpty, @"AI không trả về nội dung nào. Thử lại, hoặc đổi model.")];
        return;
    }
    [self deliverError:nil];
}

#pragma mark Errors

+(NSError*)errorFromTransport:(NSError*)error configuration:(AIConfiguration*)c {
    NSString* host = [NSURL URLWithString:c.baseURL].host ?: @"máy chủ";
    switch (error.code) {
        case NSURLErrorCancelled:
            return MakeError(VOKAIErrorCancelled, @"Đã dừng.");
        case NSURLErrorTimedOut:
            return MakeError(VOKAIErrorNetwork, @"Máy chủ không trả lời kịp. Thử lại, hoặc kiểm tra mạng.");
        case NSURLErrorNotConnectedToInternet:
        case NSURLErrorNetworkConnectionLost:
            return MakeError(VOKAIErrorNetwork, @"Máy không có kết nối mạng, hoặc kết nối bị ngắt giữa chừng.");
        case NSURLErrorCannotFindHost:
        case NSURLErrorCannotConnectToHost:
        case NSURLErrorDNSLookupFailed:
            if (c.provider.isLocal)
                return MakeError(VOKAIErrorNetwork, [NSString stringWithFormat:@"Không kết nối được tới %@. %@ đã chạy chưa, và địa chỉ có đúng không?%@", host, c.provider.name,
                                                     [c.provider.identifier isEqualToString:@"ollama"] ? @" Nếu chưa cài, vào Cài đặt > AI > Cài AI chạy trên máy." : @""]);
            return MakeError(VOKAIErrorNetwork, [NSString stringWithFormat:@"Không kết nối được tới %@. Kiểm tra mạng và địa chỉ máy chủ.", host]);
        case NSURLErrorSecureConnectionFailed:
        case NSURLErrorServerCertificateUntrusted:
        case NSURLErrorServerCertificateHasBadDate:
        case NSURLErrorServerCertificateHasUnknownRoot:
        case NSURLErrorServerCertificateNotYetValid:
        case NSURLErrorClientCertificateRejected:
            return MakeError(VOKAIErrorNetwork, [NSString stringWithFormat:@"Không thiết lập được kết nối an toàn tới %@ (chứng chỉ không hợp lệ).", host]);
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return MakeError(VOKAIErrorBadAddress, @"macOS chặn kết nối không an toàn (http) tới địa chỉ này. Hãy dùng https.");
    }
    return MakeError(VOKAIErrorNetwork, [NSString stringWithFormat:@"Lỗi mạng: %@", Shorten(VOKAIRedact(error.localizedDescription, c.key), 160)]);
}

+(NSError*)errorForStatus:(NSInteger)status body:(NSData*)body configuration:(AIConfiguration*)c {
    id json = body.length > 0 ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
    NSString* server = ServerMessage(json);
    NSString* detail = server.length > 0 ? [NSString stringWithFormat:@" (%@)", Shorten(VOKAIRedact(server, c.key), 200)] : @"";
    if (status == 401 || status == 403)
        return MakeError(VOKAIErrorAuthentication, [NSString stringWithFormat:@"%@ không chấp nhận key này, hoặc key không có quyền dùng model “%@”. Kiểm tra lại key trong Cài đặt > AI.%@", c.provider.name, c.model, detail]);
    if (status == 404)
        return MakeError(VOKAIErrorModel, [NSString stringWithFormat:@"Không tìm thấy model “%@” hoặc địa chỉ máy chủ sai. Dùng nút “Tải danh sách” trong Cài đặt > AI để chọn model.%@", c.model, detail]);
    if (status == 429)
        return MakeError(VOKAIErrorRateLimit, [NSString stringWithFormat:@"Đã vượt giới hạn yêu cầu hoặc hết hạn mức của %@. Thử lại sau, hoặc kiểm tra gói sử dụng.%@", c.provider.name, detail]);
    if (status >= 300 && status < 400)
        return MakeError(VOKAIErrorServer, @"Máy chủ chuyển hướng sang địa chỉ khác nên VOpenKey AI dừng lại để không gửi key đi nơi khác. Hãy sửa địa chỉ máy chủ trong Cài đặt > AI.");
    if (status >= 500)
        return MakeError(VOKAIErrorServer, [NSString stringWithFormat:@"Máy chủ AI đang gặp sự cố (mã %ld). Thử lại sau.%@", (long)status, detail]);
    return MakeError(VOKAIErrorServer, [NSString stringWithFormat:@"Máy chủ từ chối yêu cầu (mã %ld).%@", (long)status, detail]);
}

#pragma mark List of models

+(void)listModelsForConfiguration:(AIConfiguration*)c completion:(void (^)(NSArray<NSString*>*, NSError*))completion {
    AIAgentCLI* cli = [AIAgentCLI forProvider:c.provider];
    if (cli != nil) {
        [cli loadModelsFromExecutable:c.executablePath completion:^(NSArray<AIAgentModel*>* models, NSError* error) {
            NSMutableArray<NSString*>* names = [NSMutableArray array];
            for (AIAgentModel* model in models)
                [names addObject:model.identifier];
            completion(error == nil ? names : nil, error);
        }];
        return;
    }
    NSString* reason = nil;
    NSString* base = VOKAICleanBaseURL(c.baseURL, &reason);
    if (base == nil) {
        completion(nil, MakeError(VOKAIErrorBadAddress, reason));
        return;
    }
    NSString* address = c.provider.protocol == AIProtocolGemini ? [base stringByAppendingString:@"/models?pageSize=200"] : [base stringByAppendingString:@"/models"];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:address]];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 20;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    SetKeyHeaders(request, c);

    //a session with the same rules; the delegate refuses redirects
    AIClient* helper = [[AIClient alloc] initWithConfiguration:c];
    NSURLSession* session = MakeSession(helper, helper->_queue, 20);
    [[session dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
        NSError* failure = nil;
        NSArray<NSString*>* models = nil;
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse*)response).statusCode : 0;
        if (error != nil) {
            failure = [AIClient errorFromTransport:error configuration:c];
        } else if (status < 200 || status >= 300) {
            failure = [AIClient errorForStatus:status body:data configuration:c];
        } else {
            models = [AIClient modelNamesFromData:data configuration:c];
            if (models.count == 0)
                failure = MakeError(VOKAIErrorEmpty, @"Máy chủ không trả về danh sách model nào. Bạn vẫn có thể nhập tên model bằng tay.");
        }
        [session finishTasksAndInvalidate];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(failure == nil ? models : nil, failure); });
    }] resume];
}

+(NSArray<NSString*>*)modelNamesFromData:(NSData*)data configuration:(AIConfiguration*)c {
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]])
        return @[];
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    if (c.provider.protocol == AIProtocolGemini) {
        for (NSDictionary* model in ([json[@"models"] isKindOfClass:[NSArray class]] ? json[@"models"] : @[])) {
            if (![model isKindOfClass:[NSDictionary class]] || ![model[@"name"] isKindOfClass:[NSString class]])
                continue;
            NSArray* methods = model[@"supportedGenerationMethods"];
            if ([methods isKindOfClass:[NSArray class]] && ![methods containsObject:@"generateContent"])
                continue; //embeddings and the like
            NSString* name = model[@"name"];
            [names addObject:[name hasPrefix:@"models/"] ? [name substringFromIndex:7] : name];
        }
    } else {
        BOOL openAI = [c.baseURL containsString:@"api.openai.com"];
        NSArray<NSString*>* notForText = @[@"embedding", @"whisper", @"tts", @"dall-e", @"davinci", @"babbage", @"moderation", @"transcribe", @"realtime", @"audio", @"image"];
        for (NSDictionary* model in ([json[@"data"] isKindOfClass:[NSArray class]] ? json[@"data"] : @[])) {
            NSString* identifier = [model isKindOfClass:[NSDictionary class]] ? model[@"id"] : nil;
            if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0)
                continue;
            BOOL skip = NO;
            for (NSString* word in notForText)
                if (openAI && [identifier.lowercaseString containsString:word])
                    skip = YES;
            if (!skip)
                [names addObject:identifier];
        }
    }
    return [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

@end
