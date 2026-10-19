//
//  AIAgentRunner.m
//  VOpenKey
//

#import "AIAgentRunner.h"
#import "AIAgentProcess.h"

static const NSTimeInterval kDefaultTimeout = 600;
static const NSUInteger kMaxOutput = 2 << 20;       //an answer of 2 MB is a program gone wrong

static NSError* MakeError(VOKAIErrorCode code, NSString* message) {
    return [NSError errorWithDomain:VOKAIErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation AIAgentRunner {
    AIConfiguration* _configuration;
    AIAgentCLI* _cli;
    AIAgentProcess* _process;
    AIAgentOutputParser* _parser;
    void (^_onText)(NSString*);
    void (^_completion)(NSError*);
    NSString* _prompt;
    NSString* _model;
    NSString* _effort;
    BOOL _cancelled;                //the next fields are touched on the main thread only
    BOOL _timedOut;
    BOOL _tooMuch;
    BOOL _hasText;
}

-(instancetype)initWithConfiguration:(AIConfiguration*)configuration {
    self = [super init];
    if (self)
        _configuration = configuration;
    return self;
}

-(void)generateWithPrompt:(NSString*)prompt onText:(void (^)(NSString*))onText completion:(void (^)(NSError*))completion {
    _onText = [onText copy];
    _completion = [completion copy];
    _prompt = [prompt copy];
    _cli = [AIAgentCLI forProvider:_configuration.provider];
    NSString* executable = _configuration.executablePath;
    if (_cli == nil) {
        [self completeWithError:MakeError(VOKAIErrorServer, @"Dịch vụ này không phải là chương trình AI trên máy.")];
        return;
    }
    if (![AIAgentCLI isRunnableFile:executable]) {
        [self completeWithError:[_cli errorForLaunchFailure:@"không còn ở chỗ đã tìm thấy"]];
        return;
    }
    NSString* saved = [_configuration.model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (saved.length > 0 && ![AIAgentCLI isPlausibleModelName:saved]) {
        [self completeWithError:MakeError(VOKAIErrorModel, @"Tên model không hợp lệ. Chọn một model trong Cài đặt > AI.")];
        return;
    }
    NSArray<AIAgentModel*>* models = [_cli knownModels];
    //"choose for me" is a light model of the list, and a model of Antigravity stands for several (one by level): the list is asked of
    //the program (Codex: offline, in a moment)
    if (models.count == 0 && _cli.kind != AIAgentKindClaude) {
        __weak AIAgentRunner* weakSelf = self;
        [_cli loadModelsFromExecutable:executable completion:^(NSArray<AIAgentModel*>* loaded, NSError* error) {
            AIAgentRunner* strong = weakSelf;
            if (strong != nil && !strong->_cancelled)
                [strong startWithModels:loaded ?: @[]];
        }];
        return;
    }
    [self startWithModels:models];
}

-(void)startWithModels:(NSArray<AIAgentModel*>*)models {
    NSString* executable = _configuration.executablePath;
    NSString* model = nil, *effort = nil;
    [_cli resolveModel:_configuration.model effort:_configuration.effort models:models modelArgument:&model effortArgument:&effort];
    _model = model;
    _effort = effort;

    //a private folder, empty: what the program can see around it is nothing
    NSString* directory = [(self.workRoot ?: NSTemporaryDirectory()) stringByAppendingPathComponent:[@"VOpenKey-agent-" stringByAppendingString:[NSUUID UUID].UUIDString]];
    NSError* folderError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES
                                                    attributes:@{NSFilePosixPermissions: @0700} error:&folderError]) {
        [self completeWithError:MakeError(VOKAIErrorServer, [NSString stringWithFormat:@"Không tạo được thư mục tạm để chạy %@: %@", _cli.displayName, folderError.localizedDescription])];
        return;
    }
    NSString* system = _configuration.systemPrompt;
    NSArray<NSString*>* arguments = [_cli argumentsWithModel:_model effort:_effort systemPrompt:system prompt:_prompt workDirectory:directory];
    NSData* input = [_cli standardInputForPrompt:_prompt systemPrompt:system];

    AIAgentProcess* process = [[AIAgentProcess alloc] init];
    AIAgentOutputParser* parser = [[AIAgentOutputParser alloc] initWithFormat:_cli.output];
    _parser = parser;
    __weak AIAgentRunner* weakSelf = self;
    __block NSUInteger bytes = 0;                       //touched on the queue of the process only
    __block BOOL overLimit = NO;
    process.onOutput = ^(NSData* data) {
        bytes += data.length;
        for (NSString* piece in [parser feed:data])
            [weakSelf deliverText:piece];
        if (bytes > kMaxOutput && !overLimit) {
            overLimit = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                AIAgentRunner* strong = weakSelf;
                if (strong == nil)
                    return;
                strong->_tooMuch = YES;
                [strong->_process terminate];
            });
        }
    };
    process.onExit = ^(int status, BOOL signaled, NSString* errorOutput) {
        for (NSString* piece in [parser finish])
            [weakSelf deliverText:piece];
        [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf processEndedWithStatus:status signaled:signaled errorOutput:errorOutput]; });
    };
    NSError* launchError = nil;
    if (![process launchExecutable:executable arguments:arguments environment:[_cli environmentForExecutable:executable]
                         directory:directory input:input error:&launchError]) {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
        [self completeWithError:[_cli errorForLaunchFailure:launchError.localizedDescription]];
        return;
    }
    _process = process;
    NSTimeInterval limit = self.timeout > 0 ? self.timeout : kDefaultTimeout;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(limit * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AIAgentRunner* strong = weakSelf;
        if (strong != nil && !strong->_cancelled && strong->_completion != nil && strong->_process.running) {
            strong->_timedOut = YES;
            [strong->_process terminate];
        }
    });
}

-(void)cancel {
    _cancelled = YES;
    _onText = nil;
    _completion = nil;
    [_process terminate];
}

#pragma mark Delivering

-(void)deliverText:(NSString*)piece {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_cancelled || self->_onText == nil)
            return;
        if ([piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0)
            self->_hasText = YES;
        self->_onText(piece);
    });
}

-(void)completeWithError:(NSError*)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_cancelled || self->_completion == nil)
            return;
        void (^completion)(NSError*) = self->_completion;
        self->_completion = nil;
        self->_onText = nil;
        completion(error);
    });
}

-(void)processEndedWithStatus:(int)status signaled:(BOOL)signaled errorOutput:(NSString*)errorOutput {
    if (_cancelled || _completion == nil)
        return;
    NSError* error = nil;
    NSString* name = _cli.displayName;
    if (_timedOut) {
        NSTimeInterval limit = self.timeout > 0 ? self.timeout : kDefaultTimeout;
        error = MakeError(VOKAIErrorServer, [NSString stringWithFormat:@"%@ không trả lời sau %d phút nên đã bị dừng. Thử mức suy nghĩ thấp hơn, hoặc model nhẹ hơn.",
                                             name, MAX(1, (int)(limit / 60))]);
    } else if (_tooMuch) {
        error = MakeError(VOKAIErrorServer, [NSString stringWithFormat:@"%@ trả về quá nhiều chữ nên đã bị dừng. Thử lại với yêu cầu ngắn hơn.", name]);
    } else if (_parser.errorMessage != nil) {
        error = [_cli errorForMessage:_parser.errorMessage exitStatus:status model:_model effort:_effort];
    } else if (status != 0 || signaled) {
        error = [_cli errorForMessage:errorOutput.length > 0 ? errorOutput : _parser.leftover exitStatus:status model:_model effort:_effort];
    } else if (!_hasText) {
        NSString* gist = [AIAgentCLI gistOfErrorOutput:errorOutput ?: @""];
        error = MakeError(VOKAIErrorEmpty, [NSString stringWithFormat:@"%@ không trả về nội dung nào. Thử lại, hoặc đổi model.%@", name,
                                            gist.length > 0 ? [NSString stringWithFormat:@" (%@)", gist] : @""]);
    }
    [self completeWithError:error];
}

@end
