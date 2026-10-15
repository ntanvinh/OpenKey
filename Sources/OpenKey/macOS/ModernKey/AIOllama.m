//
//  AIOllama.m
//  VOpenKey
//

#import "AIOllama.h"
#import "AIProvider.h"

NSString* const VOKAILocalErrorDomain = @"vn.io.lssoft.vopenkey.ai.local";

static NSError* LocalError(VOKAILocalErrorCode code, NSString* message) {
    return [NSError errorWithDomain:VOKAILocalErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL HostIsThisMac(NSString* host) {
    host = host.lowercaseString;
    if ([host hasPrefix:@"["] && [host hasSuffix:@"]"])
        host = [host substringWithRange:NSMakeRange(1, host.length - 2)];
    return [host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"localhost"] || [host isEqualToString:@"::1"];
}

static NSURLSession* MakeSession(id<NSURLSessionDelegate> delegate, NSTimeInterval idleTimeout) {
    NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    configuration.HTTPShouldSetCookies = NO;
    configuration.URLCredentialStorage = nil;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    configuration.timeoutIntervalForRequest = idleTimeout;          //between two pieces of data
    configuration.timeoutIntervalForResource = 12 * 3600;           //a model of 20 GB on a slow line
    NSOperationQueue* queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;
    return [NSURLSession sessionWithConfiguration:configuration delegate:delegate delegateQueue:queue];
}

/// The text of an error that Ollama or the library sent as {"error":"..."}.
static NSString* ServerMessage(NSData* data) {
    id object = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([object isKindOfClass:[NSDictionary class]]) {
        id message = object[@"error"];
        if ([message isKindOfClass:[NSString class]] && [message length] > 0)
            return message;
        if ([message isKindOfClass:[NSDictionary class]] && [message[@"message"] isKindOfClass:[NSString class]])
            return message[@"message"];
        if ([object[@"errors"] isKindOfClass:[NSArray class]] && [object[@"errors"] count] > 0 &&
            [object[@"errors"][0] isKindOfClass:[NSDictionary class]] && [object[@"errors"][0][@"message"] isKindOfClass:[NSString class]])
            return object[@"errors"][0][@"message"];
    }
    return nil;
}

/// What the message of Ollama says about the connection, whatever the wording of the library of Go: "EOF", "connection reset by
/// peer", "i/o timeout", "TLS handshake timeout", "no such host", "dial tcp"...
static BOOL MessageIsNetwork(NSString* message) {
    if ([message containsString:@"EOF"])                    //how Go writes it; in lower case it could be the end of another word
        return YES;
    NSString* lower = message.lowercaseString;
    for (NSString* sign in @[@"connection reset", @"connection refused", @"timeout", @"timed out", @"deadline exceeded", @"no such host", @"dial tcp",
                             @"broken pipe", @"tls", @"network is unreachable", @"no route to host", @"stalled", @"max retries exceeded", @"unexpected"])
        if ([lower containsString:sign])
            return YES;
    return NO;
}

/// The message as sent by Ollama, to show as the detail of an error: the signed addresses it often contains lose their parameters
/// (those are credentials of the library, and make a line of several hundred characters), and it is cut at a reasonable length.
static NSString* Detail(NSString* message) {
    static NSRegularExpression* signedAddress;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        signedAddress = [NSRegularExpression regularExpressionWithPattern:@"(https?://[^\\s\"?]+)\\?[^\\s\"]*" options:0 error:nil];
    });
    NSString* clean = [signedAddress stringByReplacingMatchesInString:message options:0 range:NSMakeRange(0, message.length) withTemplate:@"$1"];
    clean = [clean stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
    return clean.length <= 260 ? clean : [[clean substringToIndex:260] stringByAppendingString:@"…"];
}

static NSString* FromOllama(NSString* message) {
    if ([message containsString:@"file does not exist"] || [message containsString:@"not found"])
        return @"Không tìm thấy model này trong thư viện Ollama. Kiểm tra lại tên.";
    if ([message containsString:@"no space left"])
        return @"Ổ đĩa đã hết chỗ trống. Hãy dọn ổ đĩa rồi thử lại.";
    if (MessageIsNetwork(message))
        return [NSString stringWithFormat:@"Mất kết nối mạng khi tải model. Phần đã tải được giữ nguyên, tải lại sẽ tiếp tục. Chi tiết: %@", Detail(message)];
    return [@"Ollama báo lỗi: " stringByAppendingString:Detail(message)];
}

#pragma mark - Progress

@implementation AIPullProgress
@end

@implementation AIPullParser {
    uint64_t _expected;
    NSMutableData* _buffer;
    NSMutableDictionary<NSString*, NSArray<NSNumber*>*>* _layers;       //digest -> [completed, total]
    BOOL _stopped;
}

static const NSUInteger kMaxLine = 1 << 20;

-(instancetype)initWithExpectedBytes:(uint64_t)expectedBytes {
    self = [super init];
    if (self) {
        _expected = expectedBytes;
        _buffer = [NSMutableData data];
        _layers = [NSMutableDictionary dictionary];
    }
    return self;
}

-(NSArray<AIPullProgress*>*)feed:(NSData*)data {
    NSMutableArray* reports = [NSMutableArray array];
    if (_stopped)
        return reports;
    [_buffer appendData:data];
    for (;;) {
        const char* bytes = _buffer.bytes;
        const char* end = memchr(bytes, '\n', _buffer.length);
        if (end == NULL)
            break;
        NSData* line = [_buffer subdataWithRange:NSMakeRange(0, end - bytes)];
        [_buffer replaceBytesInRange:NSMakeRange(0, end - bytes + 1) withBytes:NULL length:0];
        AIPullProgress* report = [self reportForLine:line];
        if (report != nil)
            [reports addObject:report];
        if (_stopped)
            return reports;
    }
    if (_buffer.length > kMaxLine) {                         //a line that never ends is not what Ollama sends
        _errorMessage = @"Ollama trả về dữ liệu không hợp lệ khi tải model.";
        _stopped = YES;
    }
    return reports;
}

-(AIPullProgress*)reportForLine:(NSData*)line {
    NSString* text = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
    if ([text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0)
        return nil;
    id object = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) {
        _errorMessage = @"Ollama trả về dữ liệu không hợp lệ khi tải model.";
        _stopped = YES;
        return nil;
    }
    NSString* error = [object[@"error"] isKindOfClass:[NSString class]] ? object[@"error"] : nil;
    if (error != nil) {
        _errorMessage = FromOllama(error);
        _errorIsNetwork = MessageIsNetwork(error) && ![error containsString:@"file does not exist"] && ![error containsString:@"no space left"];
        _stopped = YES;
        return nil;
    }
    NSString* status = [object[@"status"] isKindOfClass:[NSString class]] ? object[@"status"] : @"";
    AIPullProgress* report = [[AIPullProgress alloc] init];
    report.fraction = -1;
    if ([status isEqualToString:@"success"]) {
        _succeeded = YES;
        _stopped = YES;
        report.status = @"Xong";
        report.finished = YES;
        report.fraction = 1;
        [self fillTotals:report];
        return report;
    }
    if ([status hasPrefix:@"pulling "] && ![status isEqualToString:@"pulling manifest"]) {
        NSString* digest = [object[@"digest"] isKindOfClass:[NSString class]] ? object[@"digest"] : status;
        double total = [object[@"total"] isKindOfClass:[NSNumber class]] ? [object[@"total"] doubleValue] : 0;
        double completed = [object[@"completed"] isKindOfClass:[NSNumber class]] ? [object[@"completed"] doubleValue] : 0;
        total = MAX(0, total);
        completed = MIN(MAX(0, completed), total);
        _layers[digest] = @[@((uint64_t)completed), @((uint64_t)total)];
        report.status = @"Đang tải model";
        [self fillTotals:report];
        report.fraction = report.totalBytes > 0 ? MIN(1.0, (double)report.completedBytes / (double)report.totalBytes) : -1;
        return report;
    }
    if ([status isEqualToString:@"pulling manifest"])
        report.status = @"Đang lấy thông tin model";
    else if ([status hasPrefix:@"verifying"])
        report.status = @"Đang kiểm tra file tải về";
    else if ([status hasPrefix:@"writing"])
        report.status = @"Đang ghi model vào máy";
    else
        report.status = @"Đang xử lý";
    [self fillTotals:report];
    return report;
}

-(void)fillTotals:(AIPullProgress*)report {
    uint64_t completed = 0, total = 0;
    for (NSArray<NSNumber*>* layer in _layers.allValues) {
        completed += layer[0].unsignedLongLongValue;
        total += layer[1].unsignedLongLongValue;
    }
    report.completedBytes = _expected > 0 ? MIN(completed, _expected) : completed;
    report.totalBytes = _expected > 0 ? _expected : total;
}

@end

#pragma mark - Requests

@implementation AIOllamaTask {
    __weak NSURLSessionTask* _task;
    BOOL _cancelled;
}
-(void)attach:(NSURLSessionTask*)task {
    @synchronized (self) {
        _task = task;
        if (_cancelled)
            [task cancel];
    }
}
-(BOOL)cancelled {
    @synchronized (self) { return _cancelled; }
}
/// Closes the connection without the caller having asked: what comes cannot be understood, no use to keep downloading.
-(void)abandon {
    @synchronized (self) { [_task cancel]; }
}
-(void)cancel {
    @synchronized (self) {
        _cancelled = YES;
        [_task cancel];
    }
}
@end

@interface AIOllama () <NSURLSessionDataDelegate>
@end

/// What one request has received, kept by the delegate while it runs.
@interface AIOllamaCall : NSObject
@property (nonatomic, copy) void (^onData)(NSData* data);
@property (nonatomic, copy) void (^onDone)(NSData* body, NSInteger status, NSError* error);
@property (nonatomic) NSInteger status;
@property (nonatomic, strong) NSMutableData* body;      //kept only when nobody reads the data as it comes
@end
@implementation AIOllamaCall
@end

/// Follows a redirect only to https, and never with anything but the same kind of request.
@interface AILibraryHelper : NSObject <NSURLSessionTaskDelegate>
@end
@implementation AILibraryHelper
-(void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task willPerformHTTPRedirection:(NSHTTPURLResponse*)response
        newRequest:(NSURLRequest*)request completionHandler:(void (^)(NSURLRequest*))completionHandler {
    NSString* scheme = request.URL.scheme.lowercaseString;
    BOOL ok = [scheme isEqualToString:@"https"] || ([scheme isEqualToString:@"http"] && HostIsThisMac(request.URL.host ?: @""));
    completionHandler(ok ? request : nil);
}
@end

@implementation AIOllama {
    NSURLSession* _session;
    NSMutableDictionary<NSNumber*, AIOllamaCall*>* _calls;
}

+(NSURL*)defaultBaseURL { return [NSURL URLWithString:@"http://127.0.0.1:11434"]; }
+(NSURL*)defaultRegistryURL { return [NSURL URLWithString:@"https://registry.ollama.ai"]; }

-(instancetype)initWithBaseURL:(NSURL*)baseURL {
    NSURLComponents* components = baseURL != nil ? [NSURLComponents componentsWithURL:baseURL resolvingAgainstBaseURL:NO] : nil;
    if (components.host == nil || !HostIsThisMac(components.host) || ![@[@"http", @"https"] containsObject:components.scheme.lowercaseString])
        return nil;
    self = [super init];
    if (self) {
        _baseURL = baseURL;
        _calls = [NSMutableDictionary dictionary];
    }
    return self;
}

-(void)dealloc {
    [_session invalidateAndCancel];
}

/// Runs a request. `onData` gets the body as it arrives (nil: the body is kept and handed to `onDone`).
-(NSURLSessionDataTask*)run:(NSURLRequest*)request idleTimeout:(NSTimeInterval)idle onData:(void (^)(NSData*))onData
                     onDone:(void (^)(NSData* body, NSInteger status, NSError* error))onDone {
    @synchronized (self) {
        if (_session == nil)
            _session = MakeSession(self, 120);
    }
    NSMutableURLRequest* mutable = [request mutableCopy];
    mutable.timeoutInterval = idle;
    NSURLSessionDataTask* task = [_session dataTaskWithRequest:mutable];
    AIOllamaCall* call = [[AIOllamaCall alloc] init];
    call.onData = onData;
    call.onDone = onDone;
    call.body = onData == nil ? [NSMutableData data] : nil;
    @synchronized (self) {
        _calls[@(task.taskIdentifier)] = call;
    }
    [task resume];
    return task;
}

-(AIOllamaCall*)callForTask:(NSURLSessionTask*)task {
    @synchronized (self) { return _calls[@(task.taskIdentifier)]; }
}

-(void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task didReceiveResponse:(NSURLResponse*)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    [self callForTask:task].status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse*)response statusCode] : 0;
    completionHandler(NSURLSessionResponseAllow);
}

-(void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)task didReceiveData:(NSData*)data {
    AIOllamaCall* call = [self callForTask:task];
    if (call.status >= 400 || call.onData == nil) {                      //an error body is small: kept to read the message
        if (call.body == nil)
            call.body = [NSMutableData data];
        if (call.body.length < 65536)
            [call.body appendData:data];
    } else {
        call.onData(data);
    }
}

//Ollama never redirects, and a download must not be sent somewhere else
-(void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task willPerformHTTPRedirection:(NSHTTPURLResponse*)response
        newRequest:(NSURLRequest*)request completionHandler:(void (^)(NSURLRequest*))completionHandler {
    completionHandler(nil);
}

-(void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
    AIOllamaCall* call;
    @synchronized (self) {
        call = _calls[@(task.taskIdentifier)];
        [_calls removeObjectForKey:@(task.taskIdentifier)];
    }
    if (call.onDone != nil)
        call.onDone(call.body, call.status, error);
}

static NSError* NetworkError(NSError* error) {
    if (error.code == NSURLErrorCancelled)
        return LocalError(VOKAILocalErrorCancelled, @"Đã hủy.");
    if (error.code == NSURLErrorCannotConnectToHost || error.code == NSURLErrorCannotFindHost || error.code == NSURLErrorNetworkConnectionLost)
        return LocalError(VOKAILocalErrorNotRunning, @"Ollama chưa chạy trên máy.");
    if (error.code == NSURLErrorTimedOut)
        return LocalError(VOKAILocalErrorNotRunning, @"Ollama không trả lời kịp.");
    return LocalError(VOKAILocalErrorNotRunning, @"Không kết nối được tới Ollama.");
}

-(NSMutableURLRequest*)requestWithPath:(NSString*)path method:(NSString*)method body:(NSDictionary*)body {
    NSURL* url = [NSURL URLWithString:path relativeToURL:self.baseURL];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    if (body != nil) {
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    return request;
}

static void OnMain(void (^block)(void)) {
    if ([NSThread isMainThread]) block(); else dispatch_async(dispatch_get_main_queue(), block);
}

-(void)versionWithTimeout:(NSTimeInterval)timeout completion:(void (^)(NSString*, NSError*))completion {
    [self run:[self requestWithPath:@"/api/version" method:@"GET" body:nil] idleTimeout:timeout onData:nil
       onDone:^(NSData* body, NSInteger status, NSError* error) {
        NSString* version = nil;
        NSError* failure = nil;
        if (error != nil) {
            failure = NetworkError(error);
        } else {
            id object = body.length > 0 ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
            version = status == 200 && [object isKindOfClass:[NSDictionary class]] && [object[@"version"] isKindOfClass:[NSString class]] ? object[@"version"] : nil;
            if (version == nil)
                failure = LocalError(VOKAILocalErrorBadResponse, @"Địa chỉ này không phải Ollama.");
        }
        OnMain(^{ completion(version, failure); });
    }];
}

-(void)installedModelsWithCompletion:(void (^)(NSArray<NSDictionary*>*, NSError*))completion {
    [self run:[self requestWithPath:@"/api/tags" method:@"GET" body:nil] idleTimeout:15 onData:nil
       onDone:^(NSData* body, NSInteger status, NSError* error) {
        NSMutableArray* models = nil;
        NSError* failure = nil;
        if (error != nil) {
            failure = NetworkError(error);
        } else {
            id object = body.length > 0 ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
            NSArray* list = status == 200 && [object isKindOfClass:[NSDictionary class]] ? object[@"models"] : nil;
            if (![list isKindOfClass:[NSArray class]] && !([object isKindOfClass:[NSDictionary class]] && status == 200 && object[@"models"] == [NSNull null])) {
                failure = LocalError(VOKAILocalErrorBadResponse, @"Ollama trả lời không đúng định dạng.");
            } else {
                models = [NSMutableArray array];
                for (id item in [list isKindOfClass:[NSArray class]] ? list : @[]) {
                    if ([item isKindOfClass:[NSDictionary class]] && [item[@"name"] isKindOfClass:[NSString class]])
                        [models addObject:@{@"name": item[@"name"], @"size": [item[@"size"] isKindOfClass:[NSNumber class]] ? item[@"size"] : @0}];
                }
            }
        }
        OnMain(^{ completion(models, failure); });
    }];
}

+(BOOL)errorIsRetryable:(NSError*)error {
    return [error.domain isEqualToString:VOKAILocalErrorDomain] && (error.code == VOKAILocalErrorNetwork || error.code == VOKAILocalErrorInterrupted);
}

+(BOOL)tag:(NSString*)tag isAmongInstalled:(NSArray<NSDictionary*>*)models {
    NSString* wanted = [tag containsString:@":"] ? tag : [tag stringByAppendingString:@":latest"];
    for (NSDictionary* model in models) {
        NSString* name = model[@"name"];
        NSString* full = [name containsString:@":"] ? name : [name stringByAppendingString:@":latest"];
        if ([full isEqualToString:wanted])
            return YES;
    }
    return NO;
}

-(void)loadedModelsWithCompletion:(void (^)(NSArray<NSDictionary*>*, NSError*))completion {
    [self run:[self requestWithPath:@"/api/ps" method:@"GET" body:nil] idleTimeout:10 onData:nil
       onDone:^(NSData* body, NSInteger status, NSError* error) {
        NSMutableArray* models = nil;
        NSError* failure = nil;
        if (error != nil) {
            failure = NetworkError(error);
        } else {
            id object = body.length > 0 ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
            id list = status == 200 && [object isKindOfClass:[NSDictionary class]] ? object[@"models"] : nil;
            if (status != 200 || ![object isKindOfClass:[NSDictionary class]] || (list != nil && list != [NSNull null] && ![list isKindOfClass:[NSArray class]])) {
                failure = LocalError(VOKAILocalErrorBadResponse, @"Ollama trả lời không đúng định dạng.");
            } else {
                models = [NSMutableArray array];
                for (id item in [list isKindOfClass:[NSArray class]] ? list : @[]) {
                    if (![item isKindOfClass:[NSDictionary class]] || ![item[@"name"] isKindOfClass:[NSString class]])
                        continue;
                    //"size" is what the model takes in all, "size_vram" the part of it in the memory of the GPU (the same memory on a Mac)
                    NSNumber* size = [item[@"size"] isKindOfClass:[NSNumber class]] ? item[@"size"] : @0;
                    [models addObject:@{@"name": item[@"name"], @"size": size}];
                }
            }
        }
        OnMain(^{ completion(models, failure); });
    }];
}

-(void)unloadModel:(NSString*)tag completion:(void (^)(NSError*))completion {
    [self run:[self requestWithPath:@"/api/generate" method:@"POST" body:@{@"model": tag, @"keep_alive": @0, @"stream": @NO}] idleTimeout:30 onData:nil
       onDone:^(NSData* body, NSInteger status, NSError* error) {
        NSError* failure = nil;
        if (error != nil)
            failure = NetworkError(error);
        else if (status == 404)
            failure = LocalError(VOKAILocalErrorNotFound, @"Model này không còn trong máy.");
        else if (status != 200)
            failure = LocalError(VOKAILocalErrorFailed, ServerMessage(body) ? FromOllama(ServerMessage(body)) : @"Ollama không giải phóng được model.");
        OnMain(^{ completion(failure); });
    }];
}

-(AIOllamaTask*)pullModel:(NSString*)tag expectedBytes:(uint64_t)expectedBytes
                 progress:(void (^)(AIPullProgress*))progress completion:(void (^)(NSError*))completion {
    AIOllamaTask* handle = [[AIOllamaTask alloc] init];
    AIPullParser* parser = [[AIPullParser alloc] initWithExpectedBytes:expectedBytes];
    NSMutableURLRequest* request = [self requestWithPath:@"/api/pull" method:@"POST" body:@{@"model": tag, @"stream": @YES}];
    __block CFAbsoluteTime lastReport = 0;
    __block AIPullProgress* pending = nil;                  //the latest report, when it was not shown yet (too soon after the last one)
    NSObject* lock = [[NSObject alloc] init];
    NSURLSessionDataTask* task = [self run:request idleTimeout:120
        onData:^(NSData* data) {
            NSArray<AIPullProgress*>* reports = [parser feed:data];
            if (parser.errorMessage != nil)
                [handle abandon];                           //the server then stops sending (and downloading)
            for (AIPullProgress* report in reports) {
                CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
                BOOL show;
                @synchronized (lock) {
                    show = report.finished || report.fraction < 0 || now - lastReport >= 0.1;
                    pending = show ? nil : report;
                    if (show) lastReport = now;
                }
                if (show && progress != nil)
                    OnMain(^{ progress(report); });
            }
        }
        onDone:^(NSData* body, NSInteger status, NSError* error) {
            NSError* failure = nil;
            if ([handle cancelled]) {
                failure = LocalError(VOKAILocalErrorCancelled, @"Đã hủy.");
            } else if (parser.errorMessage != nil) {             //what Ollama said, or what could not be understood
                failure = LocalError([parser.errorMessage hasPrefix:@"Không tìm thấy"] ? VOKAILocalErrorNotFound
                                     : (parser.errorIsNetwork ? VOKAILocalErrorNetwork : VOKAILocalErrorFailed), parser.errorMessage);
            } else if (error != nil) {
                failure = error.code == NSURLErrorTimedOut || error.code == NSURLErrorNetworkConnectionLost
                    ? LocalError(VOKAILocalErrorInterrupted, @"Quá trình tải bị ngắt. Hãy bấm cài lại: phần đã tải được giữ nguyên, sẽ tải tiếp.")
                    : NetworkError(error);
            } else if (status >= 400) {
                NSString* message = ServerMessage(body);
                failure = message != nil
                    ? LocalError([message containsString:@"file does not exist"] ? VOKAILocalErrorNotFound
                                 : (MessageIsNetwork(message) && ![message containsString:@"no space left"] ? VOKAILocalErrorNetwork : VOKAILocalErrorFailed), FromOllama(message))
                    : LocalError(VOKAILocalErrorFailed, [NSString stringWithFormat:@"Ollama trả về lỗi %ld khi tải model.", (long)status]);
            } else if (!parser.succeeded) {
                failure = LocalError(VOKAILocalErrorInterrupted, @"Quá trình tải bị ngắt giữa chừng. Hãy bấm cài lại: phần đã tải được giữ nguyên, sẽ tải tiếp.");
            }
            AIPullProgress* last;
            @synchronized (lock) { last = pending; pending = nil; }
            OnMain(^{
                if (last != nil && failure.code != VOKAILocalErrorCancelled && progress != nil)
                    progress(last);                      //the last report was held back by the throttle: it says how far the failed try got
                completion(failure);
            });
        }];
    [handle attach:task];
    return handle;
}

-(void)deleteModel:(NSString*)tag completion:(void (^)(NSError*))completion {
    [self run:[self requestWithPath:@"/api/delete" method:@"DELETE" body:@{@"model": tag}] idleTimeout:30 onData:nil
       onDone:^(NSData* body, NSInteger status, NSError* error) {
        NSError* failure = nil;
        if (error != nil)
            failure = NetworkError(error);
        else if (status == 404)
            failure = LocalError(VOKAILocalErrorNotFound, @"Model này không còn trong máy.");
        else if (status != 200)
            failure = LocalError(VOKAILocalErrorFailed, ServerMessage(body) ? FromOllama(ServerMessage(body)) : @"Ollama không xóa được model.");
        OnMain(^{ completion(failure); });
    }];
}

#pragma mark - The library

+(void)librarySizeOfTag:(NSString*)tag registry:(NSURL*)registry completion:(void (^)(uint64_t, NSError*))completion {
    NSString* name = tag, *version = @"latest";
    NSRange colon = [tag rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        name = [tag substringToIndex:colon.location];
        version = [tag substringFromIndex:colon.location + 1];
    }
    NSArray<NSString*>* parts = [name componentsSeparatedByString:@"/"];
    NSString* repository;
    if (parts.count == 1)
        repository = [@"library/" stringByAppendingString:name];
    else if (parts.count == 2 && ![parts[0] containsString:@"."])
        repository = name;
    else {
        OnMain(^{ completion(0, nil); });                  //hf.co/... or another registry: no way to know the size from here
        return;
    }
    NSURL* url = [registry URLByAppendingPathComponent:[NSString stringWithFormat:@"v2/%@/manifests/%@", repository, version]];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"application/vnd.docker.distribution.manifest.v2+json" forHTTPHeaderField:@"Accept"];
    request.timeoutInterval = 20;
    AILibraryHelper* helper = [[AILibraryHelper alloc] init];
    NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    NSURLSession* session = [NSURLSession sessionWithConfiguration:configuration delegate:helper delegateQueue:nil];
    [[session dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse*)response statusCode] : 0;
        uint64_t bytes = 0;
        NSError* failure = nil;
        if (error != nil) {
            failure = LocalError(VOKAILocalErrorFailed, @"Không tra được dung lượng model: không kết nối được tới thư viện Ollama.");
        } else if (status == 404) {
            failure = LocalError(VOKAILocalErrorNotFound, @"Không tìm thấy model này trong thư viện Ollama. Kiểm tra lại tên và phần sau dấu hai chấm.");
        } else {
            id object = status == 200 && data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSArray* layers = [object isKindOfClass:[NSDictionary class]] ? object[@"layers"] : nil;
            if (![layers isKindOfClass:[NSArray class]] || layers.count == 0) {
                failure = LocalError(VOKAILocalErrorFailed, @"Thư viện Ollama trả lời không đúng định dạng.");
            } else {
                for (id layer in layers)
                    if ([layer isKindOfClass:[NSDictionary class]] && [layer[@"size"] isKindOfClass:[NSNumber class]])
                        bytes += [layer[@"size"] unsignedLongLongValue];
                id config = object[@"config"];
                if ([config isKindOfClass:[NSDictionary class]] && [config[@"size"] isKindOfClass:[NSNumber class]])
                    bytes += [config[@"size"] unsignedLongLongValue];
            }
        }
        [session finishTasksAndInvalidate];
        OnMain(^{ completion(bytes, failure); });
    }] resume];
}

@end
