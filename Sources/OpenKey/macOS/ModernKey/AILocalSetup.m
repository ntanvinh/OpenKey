//
//  AILocalSetup.m
//  VOpenKey
//

#import "AILocalSetup.h"
#import "AIClient.h"
#import "AIHardware.h"
#import "AIProvider.h"
#import "AISettings.h"

NSString* const VOKAILocalSetupDidFinishNotification = @"VOKAILocalSetupDidFinish";

@implementation AILocalSetup {
    AIOllamaInstaller* _installer;
    AIOllamaRuntime* _runtime;
    AIOllama* _api;
    AIOllamaTask* _pullTask;
    AIClient* _testClient;
    AILocalModel* _model;
    AILocalStepState _states[AILocalStepCount];
    double _fractions[AILocalStepCount];
    NSString* _details[AILocalStepCount];
    BOOL _running, _succeeded, _cancelRequested;
    NSError* _error;
    AILocalStep _failedStep;
    NSMutableArray<NSArray<NSNumber*>*>* _samples;      //(time, bytes) of the download of the model, to tell its speed
    id _activity;                                       //keeps the Mac awake while installing
    uint64_t _bestBytes, _bytesAtLastFailure;           //the most of the model that was downloaded, and how much there was at the last failure
    NSUInteger _failuresInARow;
    NSUInteger _generation;                             //a run that was cancelled must not touch the next one
}

+(AILocalSetup*)standardSetup {
    return [[AILocalSetup alloc] initWithInstaller:[AIOllamaInstaller standardInstaller] runtime:[AIOllamaRuntime shared]];
}

-(instancetype)initWithInstaller:(AIOllamaInstaller*)installer runtime:(AIOllamaRuntime*)runtime {
    self = [super init];
    if (self) {
        _installer = installer;
        _runtime = runtime;
        _api = [[AIOllama alloc] initWithBaseURL:runtime.baseURL];
        [self resetStates];
        _retryDelays = @[@3, @6, @10, @15, @20, @30, @30, @30];
        __weak AILocalSetup* weakSelf = self;
        _applyHandler = ^(AILocalModel* model, NSURL* baseURL) { [weakSelf applySettingsForModel:model baseURL:baseURL]; };
        _testHandler = ^(AILocalModel* model, NSURL* baseURL, void (^done)(NSError*, NSString*)) { [weakSelf askModel:model baseURL:baseURL done:done]; };
    }
    return self;
}

-(AIOllamaRuntime*)runtime { return _runtime; }
-(AILocalModel*)model { return _model; }
-(BOOL)running { return _running; }
-(BOOL)succeeded { return _succeeded; }
-(NSError*)error { return _error; }
-(BOOL)wasCancelled { return _error.code == VOKAILocalErrorCancelled; }
-(BOOL)holdsPowerAssertion { return _activity != nil; }

-(void)beginActivity {
    if (_activity == nil)
        _activity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated | NSActivityIdleSystemSleepDisabled
                                                                    reason:@"Cài AI chạy trên máy"];
}

-(void)endActivity {
    if (_activity != nil)
        [[NSProcessInfo processInfo] endActivity:_activity];
    _activity = nil;
}
-(AILocalStep)failedStep { return _failedStep; }

+(NSString*)titleOfStep:(AILocalStep)step {
    switch (step) {
        case AILocalStepRuntime: return @"Cài Ollama (chương trình chạy model)";
        case AILocalStepStart:   return @"Khởi động Ollama";
        case AILocalStepModel:   return @"Tải model";
        case AILocalStepTest:    return @"Chạy thử model";
        case AILocalStepApply:   return @"Bật cho trợ lý AI";
        default: return @"";
    }
}

-(AILocalStepState)stateOfStep:(AILocalStep)step { return _states[step]; }
-(double)fractionOfStep:(AILocalStep)step { return _fractions[step]; }
-(NSString*)detailOfStep:(AILocalStep)step { return _details[step] ?: @""; }

-(void)resetStates {
    for (int i = 0; i < AILocalStepCount; i++) {
        _states[i] = AILocalStepPending;
        _fractions[i] = -1;
        _details[i] = nil;
    }
}

-(void)changed {
    void (^block)(void) = self.onChange;
    if (block != nil)
        block();
}

-(void)step:(AILocalStep)step state:(AILocalStepState)state fraction:(double)fraction detail:(NSString*)detail {
    _states[step] = state;
    _fractions[step] = fraction;
    _details[step] = [detail copy];
    [self changed];
}

#pragma mark Running

-(void)installModel:(AILocalModel*)model {
    if (_running || model == nil)
        return;
    _generation++;
    _model = model;
    _running = YES;
    _succeeded = NO;
    _cancelRequested = NO;
    _error = nil;
    _samples = [NSMutableArray array];
    [self resetStates];
    [self beginActivity];
    [self changed];
    [self stepRuntime:_generation];
}

-(void)cancel {
    if (!_running)
        return;
    _cancelRequested = YES;
    [_installer cancel];
    [_pullTask cancel];
    [_testClient cancel];
    //whatever the step was doing, the run is over now: what the step reports later is ignored (see isCurrent:)
    AILocalStep current = AILocalStepRuntime;
    for (int i = 0; i < AILocalStepCount; i++)
        if (_states[i] == AILocalStepRunning)
            current = (AILocalStep)i;
    [self failStep:current error:[NSError errorWithDomain:VOKAILocalErrorDomain code:VOKAILocalErrorCancelled userInfo:nil] generation:_generation];
}

-(BOOL)isCurrent:(NSUInteger)generation { return generation == _generation && _running; }

/// A step failed (or the user cancelled): the others stay as they are, the reason is kept.
-(void)failStep:(AILocalStep)step error:(NSError*)error generation:(NSUInteger)generation {
    if (![self isCurrent:generation])
        return;
    BOOL cancelled = error.code == VOKAILocalErrorCancelled || _cancelRequested;
    _running = NO;
    [self endActivity];
    _failedStep = step;
    _error = cancelled ? [NSError errorWithDomain:VOKAILocalErrorDomain code:VOKAILocalErrorCancelled
                                         userInfo:@{NSLocalizedDescriptionKey: @"Đã dừng. Phần đã tải được giữ lại: bấm Cài đặt để tiếp tục."}] : error;
    [self step:step state:AILocalStepFailed fraction:-1 detail:_error.localizedDescription];
}

-(void)stepRuntime:(NSUInteger)generation {
    //an Ollama that answers is enough, wherever it came from
    [self step:AILocalStepRuntime state:AILocalStepRunning fraction:-1 detail:@"Đang tìm Ollama trên máy"];
    [_api versionWithTimeout:2 completion:^(NSString* version, NSError* error) {
        if (![self isCurrent:generation])
            return;
        if (version != nil) {
            [self step:AILocalStepRuntime state:AILocalStepSkipped fraction:1 detail:@"Máy đã có Ollama đang chạy"];
            [self step:AILocalStepStart state:AILocalStepSkipped fraction:1 detail:@"Ollama đang chạy"];
            [self stepModel:generation];
        } else if (self->_runtime.isInstalled) {
            [self step:AILocalStepRuntime state:AILocalStepSkipped fraction:1 detail:@"Máy đã cài Ollama"];
            [self stepStart:generation];
        } else {
            [self installRuntime:generation];
        }
    }];
}

-(void)installRuntime:(NSUInteger)generation {
    [_installer installWithProgress:^(AIInstallPhase phase, double fraction, uint64_t done, uint64_t total) {
        if (![self isCurrent:generation])
            return;
        NSString* detail;
        switch (phase) {
            case AIInstallPhaseLooking:     detail = @"Đang tìm bản Ollama mới nhất"; break;
            case AIInstallPhaseDownloading: detail = [NSString stringWithFormat:@"Đang tải Ollama: %@ / %@", VOKAIFormatBytes(done), VOKAIFormatBytes(total)]; break;
            case AIInstallPhaseVerifying:   detail = @"Đang kiểm tra: mã SHA-256, chữ ký và công chứng của Apple"; break;
            default:                        detail = @"Đang cài vào thư mục Applications của bạn"; break;
        }
        [self step:AILocalStepRuntime state:AILocalStepRunning fraction:fraction detail:detail];
    } completion:^(NSURL* app, NSError* error) {
        if (![self isCurrent:generation])
            return;
        if (error != nil) {
            [self failStep:AILocalStepRuntime error:error generation:generation];
            return;
        }
        [self step:AILocalStepRuntime state:AILocalStepDone fraction:1 detail:@"Đã cài Ollama, bản chính thức có chữ ký của hãng"];
        [self stepStart:generation];
    }];
}

-(void)stepStart:(NSUInteger)generation {
    [self step:AILocalStepStart state:AILocalStepRunning fraction:-1 detail:@"Đang khởi động Ollama (lần đầu có thể mất 20 đến 40 giây)"];
    [_runtime ensureRunning:^(NSError* error) {
        if (![self isCurrent:generation])
            return;
        if (error != nil) {
            [self failStep:AILocalStepStart error:error generation:generation];
            return;
        }
        [self step:AILocalStepStart state:AILocalStepDone fraction:1 detail:@"Ollama đang chạy trên máy bạn (chỉ nhận kết nối từ chính máy này)"];
        [self stepModel:generation];
    }];
}

-(void)stepModel:(NSUInteger)generation {
    [self step:AILocalStepModel state:AILocalStepRunning fraction:-1 detail:@"Đang kiểm tra model đã có trên máy"];
    [_api installedModelsWithCompletion:^(NSArray<NSDictionary*>* models, NSError* error) {
        if (![self isCurrent:generation])
            return;
        if (error != nil) {
            [self failStep:AILocalStepModel error:error generation:generation];
            return;
        }
        if ([AIOllama tag:self->_model.tag isAmongInstalled:models]) {
            [self step:AILocalStepModel state:AILocalStepSkipped fraction:1 detail:@"Model đã có sẵn trên máy"];
            [self stepTest:generation];
            return;
        }
        [self pull:generation];
    }];
}

-(void)pull:(NSUInteger)generation {
    _bestBytes = 0;
    _bytesAtLastFailure = 0;
    _failuresInARow = 0;
    [self pullAttempt:generation];
}

/// One try at the download. When the connection breaks it is started again after a wait, as many times as `retryDelays` allows
/// without any progress: Ollama keeps what was downloaded and continues from it.
-(void)pullAttempt:(NSUInteger)generation {
    NSString* tag = _model.tag;
    _pullTask = [_api pullModel:tag expectedBytes:_model.bytes progress:^(AIPullProgress* progress) {
        if (![self isCurrent:generation])
            return;
        self->_bestBytes = MAX(self->_bestBytes, progress.completedBytes);
        [self step:AILocalStepModel state:AILocalStepRunning fraction:progress.fraction detail:[self detailForPull:progress]];
    } completion:^(NSError* error) {
        self->_pullTask = nil;
        if (![self isCurrent:generation])
            return;
        if (error == nil) {
            [self step:AILocalStepModel state:AILocalStepDone fraction:1 detail:[NSString stringWithFormat:@"Đã tải xong %@ (%@)", self->_model.name, VOKAIFormatBytes(self->_model.bytes)]];
            [self stepTest:generation];
            return;
        }
        if ([AIOllama errorIsRetryable:error] && !self->_cancelRequested) {
            if (self->_bestBytes > self->_bytesAtLastFailure + 5000000)
                self->_failuresInARow = 0;                                  //it moved forward since the last failure: the count starts again
            self->_bytesAtLastFailure = self->_bestBytes;
            if (self->_failuresInARow < self->_retryDelays.count) {
                NSTimeInterval wait = [self->_retryDelays[self->_failuresInARow] doubleValue];
                NSUInteger attempt = ++self->_failuresInARow;
                [self step:AILocalStepModel state:AILocalStepRunning fraction:[self fractionOfStep:AILocalStepModel]
                    detail:[NSString stringWithFormat:@"Mất kết nối khi tải model. Tự thử lại sau %.0f giây (lần %lu/%lu); phần đã tải được giữ nguyên.\n%@",
                            wait, (unsigned long)attempt, (unsigned long)self->_retryDelays.count, error.localizedDescription]];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if ([self isCurrent:generation])
                        [self pullAttempt:generation];
                });
                return;
            }
            NSString* advice = [NSString stringWithFormat:@"%@\nĐã thử lại %lu lần mà không tải thêm được. Hãy kiểm tra mạng (Wi-Fi, VPN, tường lửa), rồi bấm Cài đặt để tải tiếp: phần đã tải được giữ nguyên.",
                                error.localizedDescription, (unsigned long)self->_retryDelays.count];
            error = [NSError errorWithDomain:error.domain code:error.code userInfo:@{NSLocalizedDescriptionKey: advice}];
        }
        [self failStep:AILocalStepModel error:error generation:generation];
    }];
}

/// "Đã tải 1,2 GB / 4,7 GB (26%) · 11 MB/giây · còn khoảng 5 phút"
-(NSString*)detailForPull:(AIPullProgress*)progress {
    if (progress.fraction < 0)
        return progress.status;
    if (progress.finished)
        return @"Đã tải xong";
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    [_samples addObject:@[@(now), @(progress.completedBytes)]];
    while (_samples.count > 2 && now - [_samples[1][0] doubleValue] > 8)               //the last few seconds only
        [_samples removeObjectAtIndex:0];
    NSMutableString* text = [NSMutableString stringWithFormat:@"%@: %@ / %@ (%.0f%%)", progress.status, VOKAIFormatBytes(progress.completedBytes),
                             VOKAIFormatBytes(progress.totalBytes), progress.fraction * 100];
    double seconds = now - [_samples.firstObject[0] doubleValue];
    double bytes = (double)progress.completedBytes - [_samples.firstObject[1] doubleValue];
    if (seconds >= 2 && bytes > 0) {
        double speed = bytes / seconds;
        [text appendFormat:@" · %@/giây", VOKAIFormatBytes((uint64_t)speed)];
        double remaining = (double)(progress.totalBytes - progress.completedBytes) / speed;
        if (remaining >= 90)
            [text appendFormat:@" · còn khoảng %.0f phút", ceil(remaining / 60)];
        else if (progress.completedBytes < progress.totalBytes)
            [text appendFormat:@" · còn khoảng %.0f giây", MAX(5, ceil(remaining / 5) * 5)];
    }
    return text;
}

-(void)stepTest:(NSUInteger)generation {
    [self step:AILocalStepTest state:AILocalStepRunning fraction:-1 detail:@"Đang nạp model vào bộ nhớ và hỏi thử một câu (lần đầu hơi lâu)"];
    void (^handler)(AILocalModel*, NSURL*, void (^)(NSError*, NSString*)) = self.testHandler;
    handler(_model, _runtime.baseURL, ^(NSError* error, NSString* summary) {
        self->_testClient = nil;
        if (![self isCurrent:generation])
            return;
        if (error != nil) {
            [self failStep:AILocalStepTest error:[NSError errorWithDomain:VOKAILocalErrorDomain code:error.code == VOKAILocalErrorCancelled ? VOKAILocalErrorCancelled : VOKAILocalErrorFailed
                                                                 userInfo:@{NSLocalizedDescriptionKey: [@"Model đã tải xong nhưng chạy thử không được: " stringByAppendingString:error.localizedDescription ?: @""]}]
                   generation:generation];
            return;
        }
        [self step:AILocalStepTest state:AILocalStepDone fraction:1 detail:summary ?: @"Model trả lời bình thường"];
        [self stepApply:generation];
    });
}

-(void)stepApply:(NSUInteger)generation {
    [self step:AILocalStepApply state:AILocalStepRunning fraction:-1 detail:@""];
    self.applyHandler(_model, _runtime.baseURL);
    _running = NO;
    [self endActivity];
    _succeeded = YES;
    [self step:AILocalStepApply state:AILocalStepDone fraction:1 detail:@"Trợ lý AI (⌃⌥A) sẽ dùng model này"];
    [[NSNotificationCenter defaultCenter] postNotificationName:VOKAILocalSetupDidFinishNotification object:self];
}

#pragma mark The defaults of the hooks

-(void)applySettingsForModel:(AILocalModel*)model baseURL:(NSURL*)baseURL {
    AIProvider* ollama = [AIProvider providerWithIdentifier:@"ollama"];
    [AISettings setBaseURL:[baseURL.absoluteString stringByAppendingString:@"/v1"] forProvider:ollama];
    [AISettings setModel:model.tag forProvider:ollama];
    [AISettings setProviderIdentifier:@"ollama"];
}

-(void)askModel:(AILocalModel*)model baseURL:(NSURL*)baseURL done:(void (^)(NSError*, NSString*))done {
    AIConfiguration* configuration = [[AIConfiguration alloc] init];
    configuration.provider = [AIProvider providerWithIdentifier:@"ollama"];
    configuration.baseURL = [baseURL.absoluteString stringByAppendingString:@"/v1"];
    configuration.model = model.tag;
    configuration.systemPrompt = @"Trả lời thật ngắn bằng tiếng Việt.";
    AIClient* client = [[AIClient alloc] initWithConfiguration:configuration];
    _testClient = client;
    __block NSUInteger pieces = 0;
    __block CFAbsoluteTime first = 0;
    __block CFAbsoluteTime last = 0;
    __block NSMutableString* text = [NSMutableString string];
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    __block BOOL finished = NO;
    //a model that does not answer in three minutes is not usable
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!finished) { finished = YES; [client cancel]; done([NSError errorWithDomain:VOKAILocalErrorDomain code:VOKAILocalErrorFailed userInfo:@{NSLocalizedDescriptionKey: @"không trả lời trong 3 phút."}], nil); }
    });
    [client generateWithPrompt:@"Chào bạn, bạn khỏe không?" onText:^(NSString* piece) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (pieces == 0) first = now;
        pieces++;
        last = now;
        [text appendString:piece];
    } completion:^(NSError* error) {
        if (finished)
            return;
        finished = YES;
        if (error != nil) {
            done(error, nil);
        } else if ([text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) {
            done([NSError errorWithDomain:VOKAILocalErrorDomain code:VOKAILocalErrorFailed userInfo:@{NSLocalizedDescriptionKey: @"model không trả lời gì."}], nil);
        } else {
            NSString* summary = [NSString stringWithFormat:@"Model trả lời sau %.1f giây", first - started];
            if (pieces >= 5 && last - first > 0.2)
                summary = [summary stringByAppendingFormat:@", tốc độ khoảng %.0f token/giây (ước tính)", (pieces - 1) / (last - first)];
            done(nil, summary);
        }
    }];
}

#pragma mark Removing a model

-(void)removeModel:(AILocalModel*)model completion:(void (^)(NSError*))completion {
    [_runtime ensureRunning:^(NSError* error) {
        if (error != nil) {
            completion(error);
            return;
        }
        [self->_api deleteModel:model.tag completion:completion];
    }];
}

#pragma mark On the disk

+(NSURL*)defaultModelsDirectory {
    const char* custom = getenv("OLLAMA_MODELS");
    if (custom != NULL && custom[0] == '/')
        return [NSURL fileURLWithPath:@(custom) isDirectory:YES];
    return [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@".ollama/models"] isDirectory:YES];
}

+(NSSet<NSString*>*)installedTagsInModelsDirectory:(NSURL*)directory {
    //manifests/<registry>/<namespace>/<name>/<tag>: a file for each model that is complete (Ollama writes it last)
    NSMutableSet* tags = [NSMutableSet set];
    NSFileManager* fm = [NSFileManager defaultManager];
    NSString* root = [directory.path stringByAppendingPathComponent:@"manifests"];
    for (NSString* relative in [fm enumeratorAtPath:root]) {
        BOOL isDirectory = YES;
        if (![fm fileExistsAtPath:[root stringByAppendingPathComponent:relative] isDirectory:&isDirectory] || isDirectory)
            continue;
        NSArray<NSString*>* parts = [relative pathComponents];
        if (parts.count < 4 || ![parts[0] isEqualToString:@"registry.ollama.ai"])
            continue;
        NSString* name = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 2)] componentsJoinedByString:@"/"];
        if ([name hasPrefix:@"library/"])
            name = [name substringFromIndex:8];
        [tags addObject:[NSString stringWithFormat:@"%@:%@", name, parts.lastObject]];
    }
    return tags;
}

@end
