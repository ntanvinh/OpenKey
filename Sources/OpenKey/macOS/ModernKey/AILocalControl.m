//
//  AILocalControl.m
//  VOpenKey
//

#import "AILocalControl.h"
#import "AIOllama.h"

@implementation AILocalControl {
    AIOllamaRuntime* _runtime;
    AIOllamaStatus* _status;
    AIHardware* _hardware;
    BOOL _busy, _busyLookup;
    NSString* _problem;
    NSString* _doing;                       //"Đang khởi động…" while an action runs
}

+(AILocalControl*)shared {
    static AILocalControl* shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[AILocalControl alloc] initWithRuntime:[AIOllamaRuntime shared]]; });
    return shared;
}

-(instancetype)initWithRuntime:(AIOllamaRuntime*)runtime {
    self = [super init];
    if (self) {
        _runtime = runtime;
        _hardwareProvider = ^AIHardware*{ return [AIHardware current]; };
    }
    return self;
}

-(void)changed {
    void (^block)(void) = self.onChange;
    if (block != nil)
        block();
}

#pragma mark What is shown

-(BOOL)detected { return _status.installed || _status.running; }
-(BOOL)busy { return _busy; }
-(BOOL)canStart { return !_busy && _status != nil && !_status.running && _status.installed; }
-(BOOL)canStop { return !_busy && _status.canStop; }
-(BOOL)canUnload { return !_busy && _status.running && _status.loadedModels.count > 0; }
-(NSString*)problemText { return _problem; }
-(BOOL)macIsBusy { return [_hardware isBusy]; }

-(NSString*)statusText {
    if (_doing != nil)
        return _doing;
    if (_status == nil)
        return @"Đang kiểm tra…";
    if (!_status.running)
        return _status.installed ? @"Ollama đã cài và đang tắt: không tốn RAM hay điện." : @"Chưa cài Ollama trên máy này.";
    NSString* who;
    switch (_status.origin) {
        case AIOllamaOriginManaged:  who = @"do VOpenKey AI mở"; break;
        case AIOllamaOriginLeftover: who = @"do VOpenKey AI mở từ lần trước, chưa ai tắt"; break;
        default:                     who = @"do ứng dụng khác mở, ví dụ ứng dụng Ollama hoặc Terminal; VOpenKey AI không tắt giúp"; break;
    }
    NSString* loaded;
    if (_status.loadedModels.count == 0) {
        loaded = @"Chưa nạp model nào nên chưa chiếm RAM.";
    } else {
        NSMutableArray* names = [NSMutableArray array];
        for (NSDictionary* model in _status.loadedModels)
            [names addObject:model[@"name"]];
        loaded = [NSString stringWithFormat:@"Đang giữ trong RAM: %@, chiếm khoảng %@.", [names componentsJoinedByString:@", "], VOKAIFormatBytes(_status.loadedBytes)];
    }
    return [NSString stringWithFormat:@"Ollama đang chạy (%@). %@", who, loaded];
}

-(NSString*)loadText {
    if (_hardware == nil)
        return @"";
    NSString* text = [NSString stringWithFormat:@"Máy của bạn %@ (bộ xử lý dùng khoảng %.0f%%, bộ nhớ %@).", [_hardware loadDescription],
                      MIN(_hardware.cpuLoadRatio, 1.0) * 100,
                      _hardware.memoryPressure == AIMemoryPressureNormal ? @"ổn" : (_hardware.memoryPressure == AIMemoryPressureWarning ? @"khá đầy" : @"quá tải")];
    if ([_hardware isBusy])
        return [text stringByAppendingString:@" AI chạy trên máy rất nặng, chỉ nên dùng khi máy đang rảnh: lúc này nên đợi, hoặc dùng dịch vụ trực tuyến."];
    return [text stringByAppendingString:@" AI chạy trên máy chỉ hợp khi máy ít việc; thấy máy ì thì bấm Dừng."];
}

#pragma mark Looking

-(void)refresh {
    if (_busyLookup)
        return;
    _busyLookup = YES;
    [_runtime statusWithCompletion:^(AIOllamaStatus* status) {
        self->_busyLookup = NO;
        self->_status = status;
        self->_hardware = self.hardwareProvider();
        [self changed];
    }];
}

#pragma mark Doing

/// The action is over. The buttons wait until the state has been read again, so that they never show what it was before the action.
-(void)finishedWithError:(NSError*)error {
    _problem = error.localizedDescription;
    _busyLookup = NO;
    [_runtime statusWithCompletion:^(AIOllamaStatus* status) {
        self->_status = status;
        self->_hardware = self.hardwareProvider();
        self->_busy = NO;
        self->_doing = nil;
        [self changed];
    }];
}

-(void)begin:(NSString*)words {
    _busy = YES;
    _doing = words;
    _problem = nil;
    [self changed];
}

-(void)start {
    if (!self.canStart)
        return;
    [self begin:@"Đang khởi động Ollama (lần đầu có thể mất 20 đến 40 giây)…"];
    [_runtime ensureRunning:^(NSError* error) { [self finishedWithError:error]; }];
}

-(void)stop {
    if (!self.canStop)
        return;
    [self begin:@"Đang dừng Ollama…"];
    [_runtime stopWithCompletion:^(NSError* error) { [self finishedWithError:error]; }];
}

-(void)unload {
    if (!self.canUnload)
        return;
    [self begin:@"Đang giải phóng RAM…"];
    [_runtime unloadModelsWithCompletion:^(NSError* error) { [self finishedWithError:error]; }];
}

@end
