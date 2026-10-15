//
//  AIOllamaRuntime.m
//  VOpenKey
//

#import "AIOllamaRuntime.h"
#import "AIOllama.h"
#import "AIOllamaInstaller.h"
#import <signal.h>

static NSError* RuntimeError(VOKAILocalErrorCode code, NSString* message) {
    return [NSError errorWithDomain:VOKAILocalErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation AIOllamaRuntime {
    AIOllama* _api;
    NSArray<NSString*>* _searchPaths;
    NSTask* _task;                                  //the server that VOpenKey started
    NSMutableArray<void (^)(NSError*)>* _waiting;   //calls to ensureRunning during a start
    NSMutableData* _output;
    NSDate* _deadline;
    BOOL _starting;
}

static AIOllamaRuntime* sReplacement;

+(void)setShared:(AIOllamaRuntime*)runtime {
    sReplacement = runtime;
}

+(AIOllamaRuntime*)shared {
    if (sReplacement != nil)
        return sReplacement;
    static AIOllamaRuntime* shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[AIOllamaRuntime alloc] initWithBaseURL:[AIOllama defaultBaseURL] searchPaths:[self defaultSearchPaths]];
    });
    return shared;
}

+(NSArray<NSString*>*)defaultSearchPaths {
    NSString* app = [AIOllamaInstaller applicationName];
    return @[[[NSHomeDirectory() stringByAppendingPathComponent:@"Applications"] stringByAppendingPathComponent:[app stringByAppendingString:@"/Contents/Resources/ollama"]],
             [@"/Applications" stringByAppendingPathComponent:[app stringByAppendingString:@"/Contents/Resources/ollama"]],
             @"/opt/homebrew/bin/ollama",
             @"/usr/local/bin/ollama"];
}

-(instancetype)initWithBaseURL:(NSURL*)baseURL searchPaths:(NSArray<NSString*>*)searchPaths {
    self = [super init];
    if (self) {
        _api = [[AIOllama alloc] initWithBaseURL:baseURL];
        if (_api == nil)
            return nil;
        _baseURL = baseURL;
        _searchPaths = [searchPaths copy];
        _waiting = [NSMutableArray array];
        _output = [NSMutableData data];
        _startTimeout = 90;
    }
    return self;
}

-(NSURL*)serverProgram {
    NSFileManager* fm = [NSFileManager defaultManager];
    for (NSString* path in _searchPaths) {
        BOOL isDirectory = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory && [fm isExecutableFileAtPath:path])
            return [NSURL fileURLWithPath:path];
    }
    return nil;
}

-(BOOL)isInstalled { return self.serverProgram != nil; }

-(BOOL)isManaged {
    @synchronized (self) { return _task != nil && _task.isRunning; }
}

-(NSString*)lastOutput {
    @synchronized (_output) {
        NSString* text = [[NSString alloc] initWithData:_output encoding:NSUTF8StringEncoding] ?: @"";
        return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
}

#pragma mark Starting

-(void)ensureRunning:(void (^)(NSError*))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_waiting addObject:[completion copy]];
        if (self->_starting)
            return;
        self->_starting = YES;
        [self begin];
    });
}

-(void)finishWithError:(NSError*)error {
    _starting = NO;
    NSArray* waiting = [_waiting copy];
    [_waiting removeAllObjects];
    for (void (^block)(NSError*) in waiting)
        block(error);
}

-(void)begin {
    [_api versionWithTimeout:3 completion:^(NSString* version, NSError* error) {
        if (version != nil) {                                           //it runs already: the user's own, or the one started before
            [self finishWithError:nil];
        } else if (error.code == VOKAILocalErrorBadResponse) {
            [self finishWithError:RuntimeError(VOKAILocalErrorFailed, [NSString stringWithFormat:@"Cổng %@ trên máy đang bị một chương trình khác dùng, không phải Ollama. Hãy tắt chương trình đó rồi thử lại.",
                                                                       self->_baseURL.port ?: @11434])];
        } else {
            [self launch];
        }
    }];
}

-(void)launch {
    NSURL* program = self.serverProgram;
    if (program == nil) {
        [self finishWithError:RuntimeError(VOKAILocalErrorNotInstalled, @"Chưa cài Ollama trên máy. Hãy cài trong Cài đặt > AI > Cài AI chạy trên máy này.")];
        return;
    }
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = program;
    task.arguments = @[@"serve"];
    task.currentDirectoryURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    NSMutableDictionary* environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
    environment[@"OLLAMA_HOST"] = [NSString stringWithFormat:@"127.0.0.1:%@", _baseURL.port ?: @11434];     //this Mac only
    if (environment[@"OLLAMA_KEEP_ALIVE"] == nil)
        environment[@"OLLAMA_KEEP_ALIVE"] = @"10m";                                 //the model leaves the memory 10 minutes after the last use
    task.environment = environment;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    @synchronized (_output) { [_output setLength:0]; }
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle* handle) {
        NSData* data = [handle availableData];
        if (data.length == 0)
            return;
        @synchronized (self->_output) {                                             //only the end is kept
            [self->_output appendData:data];
            if (self->_output.length > 4096)
                [self->_output replaceBytesInRange:NSMakeRange(0, self->_output.length - 4096) withBytes:NULL length:0];
        }
    };
    __weak NSTask* weakTask = task;
    task.terminationHandler = ^(NSTask* finished) {
        pipe.fileHandleForReading.readabilityHandler = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL ours;
            @synchronized (self) { ours = self->_task == finished; if (ours) self->_task = nil; }
            if (ours && self->_starting && weakTask == finished) {
                NSString* output = self.lastOutput;
                NSString* last = [[output componentsSeparatedByString:@"\n"] lastObject];
                [self finishWithError:RuntimeError(VOKAILocalErrorFailed, [NSString stringWithFormat:@"Ollama dừng ngay khi khởi động%@", last.length > 0 ? [@": " stringByAppendingString:last] : @"."])];
            }
        });
    };
    NSError* launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        [self finishWithError:RuntimeError(VOKAILocalErrorFailed, [@"Không chạy được Ollama: " stringByAppendingString:launchError.localizedDescription ?: @""])];
        return;
    }
    @synchronized (self) { _task = task; }
    _deadline = [NSDate dateWithTimeIntervalSinceNow:_startTimeout];
    [self pollAfter:0.3 task:task];
}

/// Asks until the server answers, it dies, or the time is up.
-(void)pollAfter:(NSTimeInterval)delay task:(NSTask*)task {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self->_starting)
            return;                                                                 //it ended: the process died, or was stopped
        [self->_api versionWithTimeout:2 completion:^(NSString* version, NSError* error) {
            if (!self->_starting)
                return;
            if (version != nil) {
                [self finishWithError:nil];
            } else if ([self->_deadline timeIntervalSinceNow] <= 0) {
                [self stopWaiting:2];
                [self finishWithError:RuntimeError(VOKAILocalErrorFailed, @"Ollama không trả lời sau khi khởi động. Hãy thử lại, hoặc khởi động lại máy.")];
            } else {
                [self pollAfter:0.5 task:task];
            }
        }];
    });
}

#pragma mark Stopping

-(void)stopWaiting:(NSTimeInterval)seconds {
    NSTask* task;
    @synchronized (self) { task = _task; _task = nil; }
    if (task == nil)
        return;
    if (task.isRunning)
        [task terminate];
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (task.isRunning && [end timeIntervalSinceNow] > 0)
        [NSThread sleepForTimeInterval:0.05];
    if (task.isRunning)
        kill(task.processIdentifier, SIGKILL);                                      //it did not obey
}

@end
