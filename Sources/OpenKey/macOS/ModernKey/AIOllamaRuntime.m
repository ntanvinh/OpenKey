//
//  AIOllamaRuntime.m
//  VOpenKey
//

#import "AIOllamaRuntime.h"
#import "AIOllama.h"
#import "AIOllamaInstaller.h"
#import <libproc.h>
#import <signal.h>

static NSError* RuntimeError(VOKAILocalErrorCode code, NSString* message) {
    return [NSError errorWithDomain:VOKAILocalErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation AIOllamaStatus
-(uint64_t)loadedBytes {
    uint64_t total = 0;
    for (NSDictionary* model in self.loadedModels)
        total += [model[@"size"] unsignedLongLongValue];
    return total;
}
-(BOOL)canStop {
    return self.running && (self.origin == AIOllamaOriginManaged || self.origin == AIOllamaOriginLeftover);
}
@end

/// The process that listens on a port of this Mac (0 when none, or not found).
static int ListeningProcess(NSNumber* port) {
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/lsof"];
    task.arguments = @[@"-nP", [NSString stringWithFormat:@"-iTCP:%@", port], @"-sTCP:LISTEN", @"-Fp"];
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil])
        return 0;
    NSData* data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    for (NSString* line in [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"])
        if ([line hasPrefix:@"p"] && line.length > 1)
            return (int)[[line substringFromIndex:1] intValue];
    return 0;
}

static NSString* PathOfProcess(int pid) {
    char buffer[PROC_PIDPATHINFO_MAXSIZE];
    if (pid <= 0 || proc_pidpath(pid, buffer, sizeof(buffer)) <= 0)
        return nil;
    return @(buffer);
}

static int ParentOfProcess(int pid) {
    struct proc_bsdinfo info;
    if (pid <= 0 || proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, PROC_PIDTBSDINFO_SIZE) != PROC_PIDTBSDINFO_SIZE)
        return -1;
    return (int)info.pbi_ppid;
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
        _ownPrograms = @[[[NSHomeDirectory() stringByAppendingPathComponent:@"Applications"] stringByAppendingPathComponent:
                          [[AIOllamaInstaller applicationName] stringByAppendingString:@"/Contents/Resources/ollama"]]];
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

#pragma mark Looking and stopping

-(void)statusWithCompletion:(void (^)(AIOllamaStatus*))completion {
    AIOllamaStatus* status = [[AIOllamaStatus alloc] init];
    status.installed = self.isInstalled;
    status.loadedModels = @[];
    [_api versionWithTimeout:2 completion:^(NSString* version, NSError* error) {
        if (version == nil) {
            status.origin = AIOllamaOriginNone;
            completion(status);
            return;
        }
        status.running = YES;
        status.version = version;
        [self->_api loadedModelsWithCompletion:^(NSArray<NSDictionary*>* models, NSError* psError) {
            status.loadedModels = models ?: @[];
            //who started it: found out away from the main thread (lsof takes a moment)
            NSNumber* port = self->_baseURL.port ?: @11434;
            NSTask* mine;
            @synchronized (self) { mine = self->_task; }
            int managedPid = mine.isRunning ? mine.processIdentifier : 0;
            NSArray<NSString*>* own = self->_ownPrograms;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                int pid = ListeningProcess(port);
                AIOllamaOrigin origin = AIOllamaOriginOther;
                if (managedPid != 0 && (pid == managedPid || pid == 0)) {
                    origin = AIOllamaOriginManaged;
                    pid = managedPid;
                } else if (pid > 0 && ParentOfProcess(pid) == 1) {
                    //nobody owns it: it is VOpenKey's own if it is the program VOpenKey installs
                    NSString* path = [PathOfProcess(pid) stringByResolvingSymlinksInPath];
                    for (NSString* program in own)
                        if (path != nil && [[program stringByResolvingSymlinksInPath] isEqualToString:path])
                            origin = AIOllamaOriginLeftover;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    status.processIdentifier = pid;
                    status.origin = origin;
                    completion(status);
                });
            });
        }];
    }];
}

-(void)stopWithCompletion:(void (^)(NSError*))completion {
    [self statusWithCompletion:^(AIOllamaStatus* status) {
        if (!status.running) {
            completion(nil);
            return;
        }
        if (!status.canStop) {
            completion(RuntimeError(VOKAILocalErrorFailed, @"Ollama đang chạy do một ứng dụng khác mở (ví dụ ứng dụng Ollama hoặc cửa sổ Terminal), nên VOpenKey AI không tắt giúp. Hãy thoát ứng dụng đó, hoặc dùng “Giải phóng RAM” để model rời khỏi bộ nhớ."));
            return;
        }
        int pid = status.processIdentifier;
        AIOllamaOrigin origin = status.origin;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            if (origin == AIOllamaOriginManaged) {
                [self stopWaiting:5];
            } else if (pid > 1) {                                                   //a leftover of VOpenKey: asked to stop, forced if it does not
                kill(pid, SIGTERM);
                NSDate* end = [NSDate dateWithTimeIntervalSinceNow:5];
                while (kill(pid, 0) == 0 && [end timeIntervalSinceNow] > 0)
                    [NSThread sleepForTimeInterval:0.1];
                if (kill(pid, 0) == 0)
                    kill(pid, SIGKILL);
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        });
    }];
}

-(void)unloadModelsWithCompletion:(void (^)(NSError*))completion {
    [_api loadedModelsWithCompletion:^(NSArray<NSDictionary*>* models, NSError* error) {
        if (error != nil) {
            completion(error.code == VOKAILocalErrorNotRunning ? nil : error);       //nothing runs: nothing is in memory
            return;
        }
        [self unloadModels:[models mutableCopy] completion:completion];
    }];
}

-(void)unloadModels:(NSMutableArray<NSDictionary*>*)models completion:(void (^)(NSError*))completion {
    if (models.count == 0) {
        completion(nil);
        return;
    }
    NSString* name = models.firstObject[@"name"];
    [models removeObjectAtIndex:0];
    [_api unloadModel:name completion:^(NSError* error) {
        if (error != nil && error.code != VOKAILocalErrorNotFound) {
            completion(error);
            return;
        }
        [self unloadModels:models completion:completion];
    }];
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
