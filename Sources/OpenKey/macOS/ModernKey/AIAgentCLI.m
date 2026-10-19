//
//  AIAgentCLI.m
//  VOpenKey
//

#import "AIAgentCLI.h"
#import "AIAgentProcess.h"

NSString* const AIAgentEffortProgramDefault = @"default";

static NSError* MakeError(VOKAIErrorCode code, NSString* message) {
    return [NSError errorWithDomain:VOKAIErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString* Shorten(NSString* text, NSUInteger limit) {
    return text.length <= limit ? text : [[text substringToIndex:limit] stringByAppendingString:@"…"];
}

//whether one of `words` is a word of `text`: "mini" is a word of "gpt-5-mini" and of "A mini model", not a part of "gemini" or "minimal"
static BOOL HasWord(NSString* text, NSArray<NSString*>* words) {
    NSArray<NSString*>* parts = [text.lowercaseString componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
    for (NSString* word in words)
        if ([parts containsObject:word])
            return YES;
    return NO;
}

//what a program prints is not to be trusted to have the shape it should: a value of another kind is nothing
static NSString* StringOf(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSDictionary* DictionaryOf(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

#pragma mark - Models

@implementation AIAgentModel
@end

static AIAgentModel* Model(NSString* identifier, NSString* name, NSString* summary, BOOL light) {
    AIAgentModel* model = [[AIAgentModel alloc] init];
    model.identifier = identifier;
    model.name = name;
    model.summary = summary;
    model.light = light;
    return model;
}

//the models that were asked of the programs, by program: the menus of the assistant use them without waiting for the program again
static NSMutableDictionary<NSNumber*, NSArray<AIAgentModel*>*>* LoadedModels(void) {
    static NSMutableDictionary* loaded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ loaded = [NSMutableDictionary dictionary]; });
    return loaded;
}

#pragma mark - Reading the output

//Turns the bytes of a program into text. A letter of UTF-8 can be cut between two reads: its first bytes wait for the rest.
@interface AIAgentTextDecoder : NSObject
-(NSString*)feed:(NSData*)data;
-(NSString*)finish;
@end

@implementation AIAgentTextDecoder {
    NSMutableData* _pending;
}

-(instancetype)init {
    self = [super init];
    if (self)
        _pending = [NSMutableData data];
    return self;
}

//how many bytes at the end of `bytes` are the start of a letter whose end has not come
static NSUInteger IncompleteTail(const uint8_t* bytes, NSUInteger length) {
    for (NSUInteger back = 1; back <= 3 && back <= length; back++) {
        uint8_t byte = bytes[length - back];
        if ((byte & 0xC0) == 0x80)
            continue;                                   //a continuation: look further back for its start
        NSUInteger needed = byte >= 0xF0 ? 4 : (byte >= 0xE0 ? 3 : (byte >= 0xC0 ? 2 : 1));
        return needed > back ? back : 0;
    }
    return 0;
}

-(NSString*)feed:(NSData*)data {
    [_pending appendData:data];
    NSUInteger keep = IncompleteTail(_pending.bytes, _pending.length);
    NSUInteger usable = _pending.length - keep;
    if (usable == 0)
        return @"";
    NSData* head = [_pending subdataWithRange:NSMakeRange(0, usable)];
    [_pending replaceBytesInRange:NSMakeRange(0, usable) withBytes:NULL length:0];
    return [[NSString alloc] initWithData:head encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithBytes:head.bytes length:head.length encoding:NSISOLatin1StringEncoding] ?: @"";
}

-(NSString*)finish {
    if (_pending.length == 0)
        return @"";
    NSString* text = [[NSString alloc] initWithData:_pending encoding:NSUTF8StringEncoding] ?: @"";    //a cut letter at the very end is dropped
    [_pending setLength:0];
    return text;
}
@end

//what a program that thinks it is in a terminal adds to its text: colours and the like
static NSString* WithoutEscapes(NSString* text) {
    if ([text rangeOfString:@"\x1B"].location == NSNotFound)
        return text;
    static NSRegularExpression* escapes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        escapes = [NSRegularExpression regularExpressionWithPattern:@"\x1B(\\[[0-9;?]*[ -/]*[@-~]|\\][^\x07\x1B]*(\x07|\x1B\\\\)|[@-Z\\\\-_])" options:0 error:nil];
    });
    return [escapes stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@""];
}

@implementation AIAgentOutputParser {
    NSString* _threadIdentifier;
    AIAgentOutput _format;
    AIAgentTextDecoder* _decoder;
    NSMutableData* _line;               //stream-json: the bytes of the line that is not complete yet
    NSMutableString* _fallback;         //stream-json: the whole text of the messages, used when no piece arrived in pieces
    NSString* _resultText;
    NSMutableString* _leftover;
    BOOL _sawPiece;
}

-(instancetype)initWithFormat:(AIAgentOutput)format {
    self = [super init];
    if (self) {
        _format = format;
        _decoder = [[AIAgentTextDecoder alloc] init];
        _line = [NSMutableData data];
        _fallback = [NSMutableString string];
        _leftover = [NSMutableString string];
    }
    return self;
}

-(NSString*)leftover {
    return [_leftover copy];
}

-(NSString*)threadIdentifier {
    return _threadIdentifier;
}

-(NSArray<NSString*>*)feed:(NSData*)data {
    if (_format == AIAgentOutputPlain) {
        NSString* text = WithoutEscapes([_decoder feed:data]);
        return text.length > 0 ? @[text] : @[];
    }
    NSMutableArray<NSString*>* pieces = [NSMutableArray array];
    const uint8_t* bytes = data.bytes;
    NSUInteger start = 0;
    for (NSUInteger i = 0; i < data.length; i++) {
        if (bytes[i] != '\n')
            continue;
        [_line appendBytes:bytes + start length:i - start];
        start = i + 1;
        [self takeLine:_line into:pieces];
        [_line setLength:0];
    }
    [_line appendBytes:bytes + start length:data.length - start];
    if (_line.length > (1 << 22))
        [_line setLength:0];            //a line of 4 MB is not one of ours
    return pieces;
}

-(NSArray<NSString*>*)finish {
    if (_format == AIAgentOutputPlain) {
        NSString* text = WithoutEscapes([_decoder finish]);
        return text.length > 0 ? @[text] : @[];
    }
    NSMutableArray<NSString*>* pieces = [NSMutableArray array];
    if (_line.length > 0) {
        [self takeLine:_line into:pieces];
        [_line setLength:0];
    }
    if (!_sawPiece && _errorMessage == nil) {
        //the answer did not come in pieces: it is in the message that completes it, or in the result
        NSString* whole = _fallback.length > 0 ? [_fallback copy] : _resultText;
        if (whole.length > 0) {
            [pieces addObject:whole];
            _sawPiece = YES;
        }
    }
    return pieces;
}

//one line of stream-json
-(void)takeLine:(NSData*)line into:(NSMutableArray<NSString*>*)pieces {
    NSString* text = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
    NSString* trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0)
        return;
    id json = [trimmed hasPrefix:@"{"] ? [NSJSONSerialization JSONObjectWithData:[trimmed dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (_leftover.length < 4000)
            [_leftover appendFormat:@"%@\n", trimmed];
        return;
    }
    NSString* type = StringOf(json[@"type"]);
    if (_format == AIAgentOutputCodexJSON) {
        //the events of `codex exec --json`: which thread, what the agent says, and how it ended
        if ([type isEqualToString:@"thread.started"]) {
            _threadIdentifier = StringOf(json[@"thread_id"]);
        } else if ([type isEqualToString:@"item.completed"]) {
            NSDictionary* item = DictionaryOf(json[@"item"]);
            NSString* message = StringOf(item[@"text"]);
            if ([StringOf(item[@"type"]) isEqualToString:@"agent_message"] && message.length > 0) {
                [pieces addObject:_fallback.length > 0 ? [@"\n\n" stringByAppendingString:message] : message];     //one message after the other
                _sawPiece = YES;
                [_fallback appendString:message];
            }
        } else if ([type isEqualToString:@"turn.failed"]) {
            NSString* reason = StringOf(DictionaryOf(json[@"error"])[@"message"]);
            if (_errorMessage == nil)                   //the first reason stays: an "error" event has said it already
                _errorMessage = reason.length > 0 ? reason : @"error";
        } else if ([type isEqualToString:@"error"]) {
            NSString* reason = StringOf(json[@"message"]);
            if (_errorMessage == nil)
                _errorMessage = reason.length > 0 ? reason : @"error";
        }
        return;
    }
    if ([type isEqualToString:@"stream_event"]) {
        NSDictionary* event = DictionaryOf(json[@"event"]);
        NSDictionary* delta = DictionaryOf(event[@"delta"]);
        NSString* piece = StringOf(delta[@"text"]);
        //only the answer: what the model thinks (thinking_delta) is not part of it
        if ([StringOf(event[@"type"]) isEqualToString:@"content_block_delta"] && [StringOf(delta[@"type"]) isEqualToString:@"text_delta"] && piece.length > 0) {
            _sawPiece = YES;
            [pieces addObject:piece];
        }
    } else if ([type isEqualToString:@"assistant"]) {
        NSDictionary* message = DictionaryOf(json[@"message"]);
        id content = message[@"content"];
        if ([content isKindOfClass:[NSArray class]]) {
            for (id block in content) {
                NSDictionary* part = DictionaryOf(block);
                if ([StringOf(part[@"type"]) isEqualToString:@"text"] && StringOf(part[@"text"]) != nil)
                    [_fallback appendString:part[@"text"]];
            }
        }
        //a message that is an error ("authentication_failed"...) says what went wrong in its text
        if (StringOf(message[@"error"]) != nil && _errorMessage == nil && _fallback.length > 0)
            _errorMessage = [_fallback copy];
    } else if ([type isEqualToString:@"result"]) {
        NSString* result = StringOf(json[@"result"]);
        BOOL failed = ([json[@"is_error"] isKindOfClass:[NSNumber class]] && [json[@"is_error"] boolValue]) || [StringOf(json[@"subtype"]) hasPrefix:@"error"];
        if (failed) {
            id errors = json[@"errors"];
            NSString* detail = result.length > 0 ? result : ([errors isKindOfClass:[NSArray class]] ? [(NSArray*)errors componentsJoinedByString:@" "] : nil);
            _errorMessage = detail.length > 0 ? detail : @"error";
        } else {
            _resultText = result;
        }
    }
}

@end

#pragma mark - The agents

@implementation AIAgentCLI

+(AIAgentCLI*)forProvider:(AIProvider*)provider {
    if (!provider.isAgentCLI)
        return nil;
    static NSDictionary<NSString*, AIAgentCLI*>* all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        all = @{
            @"codex-cli": [[AIAgentCLI alloc] initWithKind:AIAgentKindCodex command:@"codex" name:@"Codex CLI" output:AIAgentOutputPlain
                                                 loginHint:@"codex login" installHint:@"npm install -g @openai/codex"],
            @"claude-cli": [[AIAgentCLI alloc] initWithKind:AIAgentKindClaude command:@"claude" name:@"Claude Code CLI" output:AIAgentOutputClaudeJSON
                                                  loginHint:@"claude auth login" installHint:@"npm install -g @anthropic-ai/claude-code"],
            @"agy-cli": [[AIAgentCLI alloc] initWithKind:AIAgentKindAntigravity command:@"agy" name:@"Antigravity CLI" output:AIAgentOutputPlain
                                               loginHint:@"agy" installHint:nil],
        };
    });
    return all[provider.identifier];
}

-(instancetype)initWithKind:(AIAgentKind)kind command:(NSString*)command name:(NSString*)name output:(AIAgentOutput)output
                  loginHint:(NSString*)loginHint installHint:(NSString*)installHint {
    self = [super init];
    if (self) {
        _kind = kind;
        _command = [command copy];
        _displayName = [name copy];
        _output = output;
        _loginHint = [loginHint copy];
        _installHint = [installHint copy];
        if (kind == AIAgentKindAntigravity)
            _storageNote = @"Antigravity CLI tự lưu mỗi lần hỏi thành một cuộc trò chuyện trong ~/.gemini/antigravity-cli; VOpenKey AI không xóa được.";
    }
    return self;
}

#pragma mark Finding the program

+(BOOL)isRunnableFile:(NSString*)path {
    BOOL directory = NO;
    return path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && !directory &&
           [[NSFileManager defaultManager] isExecutableFileAtPath:path];
}

//the folders under `parent` that are the `bin` of a version of a program manager, the newest version first
static NSArray<NSString*>* VersionedBins(NSString* parent, NSString* below) {
    NSArray<NSString*>* versions = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:parent error:nil];
    versions = [versions sortedArrayUsingComparator:^NSComparisonResult(NSString* a, NSString* b) {
        return [b compare:a options:NSNumericSearch];
    }];
    NSMutableArray<NSString*>* bins = [NSMutableArray array];
    for (NSString* version in versions)
        [bins addObject:below.length > 0 ? [[parent stringByAppendingPathComponent:version] stringByAppendingPathComponent:below] : [parent stringByAppendingPathComponent:version]];
    return bins;
}

+(NSArray<NSString*>*)searchDirectoriesForHome:(NSString*)home environmentPath:(NSString*)path {
    NSMutableArray<NSString*>* candidates = [NSMutableArray array];
    for (NSString* relative in @[@".local/bin", @".claude/local", @".bun/bin", @".volta/bin", @".npm-global/bin", @".yarn/bin", @".cargo/bin"])
        [candidates addObject:[home stringByAppendingPathComponent:relative]];
    //the managers of versions of Node, where `npm install -g` puts the programs
    [candidates addObjectsFromArray:VersionedBins([home stringByAppendingPathComponent:@".nvm/versions/node"], @"bin")];
    [candidates addObjectsFromArray:VersionedBins([home stringByAppendingPathComponent:@"Library/Application Support/fnm/node-versions"], @"installation/bin")];
    [candidates addObjectsFromArray:VersionedBins([home stringByAppendingPathComponent:@".local/share/fnm/node-versions"], @"installation/bin")];
    for (NSString* relative in @[@".asdf/shims", @".local/share/mise/shims", @"Library/pnpm", @".local/share/pnpm"])
        [candidates addObject:[home stringByAppendingPathComponent:relative]];
    //what the user installed comes before what the system has
    [candidates addObjectsFromArray:@[@"/opt/homebrew/bin", @"/usr/local/bin"]];
    [candidates addObjectsFromArray:[path componentsSeparatedByString:@":"]];
    [candidates addObjectsFromArray:@[@"/usr/bin", @"/bin"]];

    NSMutableArray<NSString*>* directories = [NSMutableArray array];
    NSMutableSet<NSString*>* seen = [NSMutableSet set];
    for (NSString* candidate in candidates) {
        BOOL isDirectory = NO;
        if (candidate.length == 0 || ![candidate hasPrefix:@"/"] || [seen containsObject:candidate])
            continue;
        [seen addObject:candidate];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate isDirectory:&isDirectory] && isDirectory)
            [directories addObject:candidate];
    }
    return directories;
}

static NSArray<NSString*>* sSearchDirectoriesForTesting;

+(void)setSearchDirectoriesForTesting:(NSArray<NSString*>*)directories {
    sSearchDirectoriesForTesting = [directories copy];
}

+(NSArray<NSString*>*)searchDirectories {
    if (sSearchDirectoriesForTesting != nil)
        return sSearchDirectoriesForTesting;
    return [self searchDirectoriesForHome:NSHomeDirectory() environmentPath:[[NSProcessInfo processInfo] environment][@"PATH"] ?: @""];
}

-(NSString*)locateExecutableWithOverride:(NSString*)override home:(NSString*)home environmentPath:(NSString*)path {
    if (override.length > 0 && [AIAgentCLI isRunnableFile:override])
        return override;
    for (NSString* directory in [AIAgentCLI searchDirectoriesForHome:home environmentPath:path]) {
        NSString* candidate = [directory stringByAppendingPathComponent:_command];
        if ([AIAgentCLI isRunnableFile:candidate])
            return candidate;
    }
    return nil;
}

-(NSString*)locateExecutableWithOverride:(NSString*)override {
    if (override.length > 0 && [AIAgentCLI isRunnableFile:override])
        return override;
    for (NSString* directory in [AIAgentCLI searchDirectories]) {
        NSString* candidate = [directory stringByAppendingPathComponent:_command];
        if ([AIAgentCLI isRunnableFile:candidate])
            return candidate;
    }
    return nil;
}

+(NSString*)pathForExecutable:(NSString*)executable home:(NSString*)home environmentPath:(NSString*)path {
    NSMutableArray<NSString*>* directories = [NSMutableArray array];
    //a script that starts with `env node` finds the node that was installed with it, next to it, in its folder
    [directories addObject:[executable stringByDeletingLastPathComponent]];
    NSString* real = [executable stringByResolvingSymlinksInPath];
    if (real.length > 0)
        [directories addObject:[real stringByDeletingLastPathComponent]];
    [directories addObjectsFromArray:[self searchDirectoriesForHome:home environmentPath:path]];
    NSMutableArray<NSString*>* unique = [NSMutableArray array];
    for (NSString* directory in directories)
        if (directory.length > 0 && ![unique containsObject:directory])
            [unique addObject:directory];
    return [unique componentsJoinedByString:@":"];
}

#pragma mark Models and thinking levels

+(NSArray<NSString*>*)commonEfforts {
    return @[@"low", @"medium", @"high", @"xhigh", @"max"];
}

+(NSString*)nameOfEffort:(NSString*)effort {
    static NSDictionary<NSString*, NSString*>* names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{@"minimal": @"Tối thiểu", @"low": @"Thấp (nhanh nhất)", @"medium": @"Vừa", @"high": @"Cao", @"xhigh": @"Rất cao",
                  @"max": @"Tối đa", @"ultra": @"Siêu cao"};
    });
    return names[effort] ?: effort;
}

-(NSArray<AIAgentModel*>*)knownModels {
    if (_kind == AIAgentKindClaude)
        return [AIAgentCLI claudeModels];
    return LoadedModels()[@(_kind)] ?: @[];
}

//Claude Code has no command that lists its models; it takes these names for "the latest of the family" (or a full model name)
+(NSArray<AIAgentModel*>*)claudeModels {
    return @[
        Model(@"haiku", @"Haiku", @"Nhanh và nhẹ nhất, đủ cho viết, dịch và sửa chữ thông thường", YES),
        Model(@"sonnet", @"Sonnet", @"Cân bằng giữa tốc độ và chất lượng", NO),
        Model(@"opus", @"Opus", @"Mạnh hơn, chậm hơn, tốn hạn mức hơn", NO),
        Model(@"fable", @"Fable", @"Mạnh, chậm hơn, tốn hạn mức hơn", NO),
    ];
}

+(NSArray<AIAgentModel*>*)modelsFromCodexCatalog:(NSData*)json {
    id root = json.length > 0 ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    NSArray* list = [root isKindOfClass:[NSDictionary class]] ? root[@"models"] : ([root isKindOfClass:[NSArray class]] ? root : nil);
    if (![list isKindOfClass:[NSArray class]])
        return @[];
    NSArray<NSString*>* lightWords = @[@"fast", @"affordable", @"efficient", @"lightweight", @"small", @"cheap", @"quick", @"mini"];
    NSArray<NSString*>* heavyWords = @[@"older", @"previous", @"legacy", @"deprecated", @"frontier", @"demanding"];
    NSMutableArray<NSDictionary*>* entries = [NSMutableArray array];
    NSUInteger index = 0;
    for (id each in list) {
        index++;
        NSDictionary* item = DictionaryOf(each);
        if (StringOf(item[@"slug"]).length == 0)
            continue;
        NSString* visibility = StringOf(item[@"visibility"]) ?: @"list";
        if (![visibility isEqualToString:@"list"])
            continue;                                   //meant for the program itself (automatic review...), not for a menu
        AIAgentModel* model = [[AIAgentModel alloc] init];
        model.identifier = item[@"slug"];
        model.name = StringOf(item[@"display_name"]).length > 0 ? item[@"display_name"] : item[@"slug"];
        NSString* description = StringOf(item[@"description"]);
        model.summary = description.length > 0 ? description : nil;
        NSMutableArray<NSString*>* efforts = [NSMutableArray array];
        for (id level in ([item[@"supported_reasoning_levels"] isKindOfClass:[NSArray class]] ? item[@"supported_reasoning_levels"] : @[])) {
            NSString* effort = DictionaryOf(level) != nil ? StringOf(level[@"effort"]) : StringOf(level);
            if (effort.length > 0 && ![efforts containsObject:effort])
                [efforts addObject:effort];
        }
        model.efforts = efforts.count > 0 ? efforts : nil;
        model.defaultEffort = StringOf(item[@"default_reasoning_level"]);
        model.light = HasWord(description, lightWords) && !HasWord(description, heavyWords);
        NSNumber* priority = [item[@"priority"] isKindOfClass:[NSNumber class]] ? item[@"priority"] : @(1000);
        [entries addObject:@{@"model": model, @"priority": priority, @"index": @(index)}];
    }
    //the program lists the newest and most prominent first by `priority`; the order of the file breaks ties
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
        NSComparisonResult byPriority = [a[@"priority"] compare:b[@"priority"]];
        return byPriority != NSOrderedSame ? byPriority : [a[@"index"] compare:b[@"index"]];
    }];
    NSMutableArray<AIAgentModel*>* models = [NSMutableArray array];
    NSMutableSet<NSString*>* seen = [NSMutableSet set];
    for (NSDictionary* entry in entries) {
        AIAgentModel* model = entry[@"model"];
        if (![seen containsObject:model.identifier]) {
            [seen addObject:model.identifier];
            [models addObject:model];
        }
    }
    return models;
}

//the levels in the order of their strength, which is the order of a menu
static NSArray<NSString*>* EffortOrder(void) {
    return @[@"minimal", @"low", @"medium", @"high", @"xhigh", @"max", @"ultra"];
}

+(NSArray<AIAgentModel*>*)modelsFromAntigravityList:(NSString*)text {
    //the lines: "identifier<TAB>name". Another program may print a status line ("Fetching...") on its output, so when there are
    //tabs, only the lines with one are models. Without any, the line is the name and what --model takes (a bullet in front is dropped)
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    BOOL anyTab = NO;
    for (NSString* raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString* line = WithoutEscapes(raw);
        NSRange tab = [line rangeOfString:@"\t"];
        if (tab.location != NSNotFound && [[line substringToIndex:tab.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length > 0)
            anyTab = YES;
        [lines addObject:line];
    }
    NSCharacterSet* bullets = [NSCharacterSet characterSetWithCharactersInString:@"-*•✓✔>▶ \t"];
    NSMutableArray<NSArray<NSString*>*>* entries = [NSMutableArray array];             //@[identifier, name]
    NSMutableSet<NSString*>* seen = [NSMutableSet set];
    for (NSString* raw in lines) {
        NSString* line = raw;
        NSString* identifier = nil, *name = nil;
        NSRange tab = [line rangeOfString:@"\t"];
        if (anyTab) {
            if (tab.location == NSNotFound)
                continue;
            identifier = [[line substringToIndex:tab.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            name = [[line substringFromIndex:tab.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else {
            while (line.length > 0 && [bullets characterIsMember:[line characterAtIndex:0]])
                line = [line substringFromIndex:1];
            line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (line.length == 0 || [line hasSuffix:@":"] || [line hasPrefix:@"#"])
                continue;
            //"id    Name": a column of identifiers, then the name
            NSRange gap = [line rangeOfString:@"  "];
            identifier = gap.location != NSNotFound && gap.location > 0 ? [line substringToIndex:gap.location] : line;
            name = gap.location != NSNotFound && gap.location > 0 ? [[line substringFromIndex:gap.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] : line;
        }
        if (identifier.length == 0 || identifier.length > 120 || [seen containsObject:identifier])
            continue;
        [seen addObject:identifier];
        [entries addObject:@[identifier, name.length > 0 ? name : identifier]];
    }

    //models that only differ by their level are one model with levels
    NSArray<NSString*>* lightWords = @[@"flash", @"mini", @"lite", @"haiku", @"nano", @"small", @"fast"];
    NSMutableArray<AIAgentModel*>* models = [NSMutableArray array];
    NSMutableDictionary<NSString*, AIAgentModel*>* families = [NSMutableDictionary dictionary];
    for (NSArray<NSString*>* entry in entries) {
        NSString* identifier = entry[0], *name = entry[1];
        NSString* level = nil;
        for (NSString* candidate in EffortOrder()) {
            BOOL inIdentifier = [identifier hasSuffix:[@"-" stringByAppendingString:candidate]] && identifier.length > candidate.length + 1;
            BOOL inName = [name.lowercaseString hasSuffix:[NSString stringWithFormat:@" (%@)", candidate]] && name.length > candidate.length + 3;
            if (inIdentifier && inName) {
                level = candidate;
                break;
            }
        }
        if (level == nil) {
            AIAgentModel* model = [[AIAgentModel alloc] init];
            model.identifier = identifier;
            model.name = name;
            [models addObject:model];
            continue;
        }
        NSString* family = [identifier substringToIndex:identifier.length - level.length - 1];
        AIAgentModel* model = families[family];
        if (model == nil) {
            model = [[AIAgentModel alloc] init];
            model.identifier = family;
            model.name = [name substringToIndex:name.length - level.length - 3];
            model.variants = @{};
            model.light = HasWord(family, lightWords);
            families[family] = model;
            [models addObject:model];
        }
        NSMutableDictionary* variants = [model.variants mutableCopy];
        variants[level] = identifier;
        model.variants = variants;
    }
    for (AIAgentModel* model in models) {
        if (model.variants == nil)
            continue;
        NSMutableArray<NSString*>* efforts = [NSMutableArray array];
        for (NSString* level in EffortOrder())
            if (model.variants[level] != nil)
                [efforts addObject:level];
        model.efforts = efforts;
    }
    return models;
}

-(void)loadModelsFromExecutable:(NSString*)executable completion:(void (^)(NSArray<AIAgentModel*>*, NSError*))completion {
    if (_kind == AIAgentKindClaude) {
        completion([AIAgentCLI claudeModels], nil);
        return;
    }
    if (![AIAgentCLI isRunnableFile:executable]) {
        completion(nil, [self errorForLaunchFailure:@"không tìm thấy"]);
        return;
    }
    NSArray<NSString*>* arguments = _kind == AIAgentKindCodex ? @[@"debug", @"models"] : @[@"models"];
    AIAgentKind kind = _kind;
    NSString* name = _displayName;
    [AIAgentProcess captureOutputOfExecutable:executable arguments:arguments environment:[self environmentForExecutable:executable]
                                      timeout:20 limit:8 << 20 completion:^(NSData* output, NSString* errorOutput, NSError* error) {
        NSArray<AIAgentModel*>* models = @[];
        if (kind == AIAgentKindCodex)
            models = [AIAgentCLI modelsFromCodexCatalog:output];
        else if (output.length > 0)
            models = [AIAgentCLI modelsFromAntigravityList:[[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] ?: @""];
        if (models.count > 0) {
            LoadedModels()[@(kind)] = models;
            completion(models, nil);
            return;
        }
        if (error == nil || error.code != VOKAIErrorNoProgram)
            error = MakeError(VOKAIErrorEmpty, [NSString stringWithFormat:@"%@ không cho biết danh sách model. Bạn vẫn có thể nhập tên model bằng tay.", name]);
        completion(nil, error);
    }];
}

+(AIAgentModel*)modelWithIdentifier:(NSString*)identifier among:(NSArray<AIAgentModel*>*)models {
    for (AIAgentModel* model in models)
        if ([model.identifier isEqualToString:identifier])
            return model;
    return nil;
}

-(NSString*)modelToPassForSaved:(NSString*)saved models:(NSArray<AIAgentModel*>*)models {
    NSString* chosen = [saved stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (chosen.length > 0)
        return chosen;
    switch (_kind) {
        case AIAgentKindClaude:
            return @"haiku";
        case AIAgentKindCodex:
            for (AIAgentModel* model in models)
                if (model.light)
                    return model.identifier;
            return nil;                                 //the catalog is not known: the program uses its own default
        case AIAgentKindAntigravity:
            for (AIAgentModel* model in models)
                if (model.light)
                    return model.identifier;
            return nil;                                 //the list is not known: the program uses its own default
    }
    return nil;
}

-(NSString*)effortToPassForSaved:(NSString*)saved modelToPass:(NSString*)modelIdentifier models:(NSArray<AIAgentModel*>*)models {
    if ([saved isEqualToString:AIAgentEffortProgramDefault])
        return nil;
    AIAgentModel* model = modelIdentifier.length > 0 ? [AIAgentCLI modelWithIdentifier:modelIdentifier among:models] : nil;
    NSArray<NSString*>* allowed = model.efforts ?: [AIAgentCLI commonEfforts];
    if (saved.length > 0 && [allowed containsObject:saved])
        return saved;
    //"choose for me": the fast level. A model of Antigravity that is not known to have levels keeps the one in its name.
    if (_kind == AIAgentKindAntigravity && model.efforts == nil)
        return nil;
    return [allowed containsObject:@"low"] ? @"low" : allowed.firstObject;
}

-(NSString*)effectiveEffortForSavedModel:(NSString*)savedModel effort:(NSString*)savedEffort models:(NSArray<AIAgentModel*>*)models {
    NSString* model = [self modelToPassForSaved:savedModel models:models];
    NSString* effort = [self effortToPassForSaved:savedEffort modelToPass:model models:models];
    AIAgentModel* known = model.length > 0 ? [AIAgentCLI modelWithIdentifier:model among:models] : nil;
    if (known.variants.count > 0) {
        //the same choice as -resolveModel:...: the level asked for, or the program's own default level, which has to be some level
        if (effort.length > 0 && known.variants[effort] != nil)
            return effort;
        NSString* own = known.defaultEffort ?: @"medium";
        return known.variants[own] != nil ? own : known.efforts.firstObject;
    }
    return effort;
}

+(NSString*)speedNoteForEffort:(NSString*)effort {
    if ([self isFastEffort:effort] && effort != nil)
        return @"Nhanh nhất, thường vài giây";
    if ([effort isEqualToString:@"medium"])
        return @"Chậm hơn nhiều, có thể 15 đến 40 giây";
    if ([effort isEqualToString:@"high"])
        return @"Chậm, có thể cả phút";
    if (effort.length > 0)
        return @"Rất chậm, có thể vài phút";
    return @"Tùy chương trình, thường chậm hơn mức thấp";
}

+(BOOL)isFastEffort:(NSString*)effort {
    return effort.length == 0 || [effort isEqualToString:@"low"] || [effort isEqualToString:@"minimal"];
}

-(NSString*)summaryForSavedModel:(NSString*)savedModel effort:(NSString*)savedEffort models:(NSArray<AIAgentModel*>*)models {
    NSString* model = [self modelToPassForSaved:savedModel models:models];
    NSString* effort = [self effectiveEffortForSavedModel:savedModel effort:savedEffort models:models];
    AIAgentModel* known = model.length > 0 ? [AIAgentCLI modelWithIdentifier:model among:models] : nil;
    NSString* modelText = known.name ?: (model.length > 0 ? model : @"model mặc định của CLI");
    NSString* effortText = effort.length > 0 ? [AIAgentCLI nameOfEffort:effort] : @"mức mặc định của CLI";
    return [NSString stringWithFormat:@"%@ · %@", modelText, effortText];
}

-(void)resolveModel:(NSString*)savedModel effort:(NSString*)savedEffort models:(NSArray<AIAgentModel*>*)models
      modelArgument:(NSString**)modelArgument effortArgument:(NSString**)effortArgument {
    NSString* model = [self modelToPassForSaved:savedModel models:models];
    NSString* effort = [self effortToPassForSaved:savedEffort modelToPass:model models:models];
    AIAgentModel* known = model.length > 0 ? [AIAgentCLI modelWithIdentifier:model among:models] : nil;
    if (known.variants.count > 0) {
        //the levels of this model are models of the program: the one of the level asked for, and no level besides
        NSString* variant = effort.length > 0 ? known.variants[effort] : nil;
        if (variant == nil)
            variant = known.variants[known.defaultEffort ?: @"medium"] ?: known.variants[known.efforts.firstObject];
        model = variant ?: model;
        effort = nil;
    }
    if (modelArgument != NULL)
        *modelArgument = model;
    if (effortArgument != NULL)
        *effortArgument = effort;
}

#pragma mark Running it

+(NSString*)instructionWithSystemPrompt:(NSString*)systemPrompt {
    NSString* rule = @"You are the writing assistant of a typing application. Reply with the text that was asked for and nothing else. "
                     @"You have no tools here: do not run commands, do not read, create or change files, do not browse the web.";
    return systemPrompt.length > 0 ? [NSString stringWithFormat:@"%@\n\n%@", rule, systemPrompt] : rule;
}

//a name that can be given to a program as the value of --model: no flag, no control characters
+(BOOL)isPlausibleModelName:(NSString*)name {
    if (name.length == 0 || name.length > 120 || [name hasPrefix:@"-"])
        return NO;
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        if (c < 0x20 || c == 0x7F)
            return NO;
    }
    return YES;
}

//A thinking level goes into an argument that Codex reads as TOML: letters, digits and dashes, and it starts with a letter (so it can
//not be taken for a flag either).
+(BOOL)isPlausibleEffort:(NSString*)effort {
    if (effort.length == 0 || effort.length > 16)
        return NO;
    NSCharacterSet* lower = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz"];
    NSCharacterSet* allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_-"];
    return [lower characterIsMember:[effort characterAtIndex:0]] && [effort rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

-(NSArray<NSString*>*)argumentsWithModel:(NSString*)model effort:(NSString*)effort systemPrompt:(NSString*)systemPrompt
                                  prompt:(NSString*)prompt workDirectory:(NSString*)workDirectory {
    BOOL hasModel = [AIAgentCLI isPlausibleModelName:model];
    BOOL hasEffort = [AIAgentCLI isPlausibleEffort:effort];
    NSMutableArray<NSString*>* arguments = [NSMutableArray array];
    switch (_kind) {
        case AIAgentKindCodex:
            //`exec` runs once without asking anything. The user's own configuration (hooks, MCP servers, rules) is left out, nothing is
            //saved, the files can only be read, the program may not run commands, and the request comes on the standard input ("-")
            [arguments addObjectsFromArray:@[@"exec", @"--ignore-user-config", @"--ignore-rules", @"--skip-git-repo-check", @"--ephemeral",
                                             @"--color", @"never", @"-s", @"read-only", @"--disable", @"shell_tool", @"-C", workDirectory ?: @"."]];
            if (hasModel)
                [arguments addObjectsFromArray:@[@"-m", model]];
            if (hasEffort)
                [arguments addObjectsFromArray:@[@"-c", [NSString stringWithFormat:@"model_reasoning_effort=\"%@\"", effort]]];
            [arguments addObject:@"-"];
            break;
        case AIAgentKindClaude:
            //safe mode: nothing of the user's (CLAUDE.md, hooks, MCP servers, plugins, skills); no tools at all; nothing saved; the
            //answer comes as it is written
            [arguments addObjectsFromArray:@[@"-p", @"--safe-mode", @"--tools", @"", @"--no-session-persistence", @"--output-format", @"stream-json",
                                             @"--include-partial-messages", @"--verbose", @"--system-prompt", [AIAgentCLI instructionWithSystemPrompt:systemPrompt]]];
            if (hasModel)
                [arguments addObjectsFromArray:@[@"--model", model]];
            if (hasEffort)
                [arguments addObjectsFromArray:@[@"--effort", effort]];
            break;
        case AIAgentKindAntigravity:
            if (hasModel)
                [arguments addObjectsFromArray:@[@"--model", model]];
            if (hasEffort)
                [arguments addObjectsFromArray:@[@"--effort", effort]];
            //the flags come first: what follows -p is the prompt, which starts with our own text so it can never look like a flag
            [arguments addObjectsFromArray:@[@"--output-format", @"text", @"-p",
                                             [NSString stringWithFormat:@"%@\n\n%@", [AIAgentCLI instructionWithSystemPrompt:systemPrompt], prompt]]];
            break;
    }
    return arguments;
}

#pragma mark Pictures

+(NSString*)defaultImagePromptTemplate {
    return @"Use $imagegen skill to create picture {prompt}, follow our design system.";
}

+(NSString*)imagePromptForRequest:(NSString*)request template:(NSString*)template {
    NSString* trimmed = [request stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString* pattern = [template stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (pattern.length == 0)
        pattern = [self defaultImagePromptTemplate];
    if ([pattern rangeOfString:@"{prompt}"].location == NSNotFound)
        return [NSString stringWithFormat:@"%@ %@", pattern, trimmed];
    return [pattern stringByReplacingOccurrencesOfString:@"{prompt}" withString:trimmed];
}

-(BOOL)canMakeImages {
    return _kind == AIAgentKindCodex;
}

-(NSArray<NSString*>*)imageArgumentsWithModel:(NSString*)model effort:(NSString*)effort workDirectory:(NSString*)workDirectory {
    //the arguments of a text, with the events in JSON; the skill makes the picture with a tool of Codex itself, no command is needed
    NSMutableArray<NSString*>* arguments = [[self argumentsWithModel:model effort:effort systemPrompt:nil prompt:@"" workDirectory:workDirectory] mutableCopy];
    [arguments insertObject:@"--json" atIndex:1];
    return arguments;
}

-(NSData*)standardInputForImagePrompt:(NSString*)prompt {
    return [prompt dataUsingEncoding:NSUTF8StringEncoding];
}

+(NSString*)codexHomeForEnvironment:(NSDictionary<NSString*, NSString*>*)environment {
    NSString* chosen = environment[@"CODEX_HOME"];
    return chosen.length > 0 ? chosen : [NSHomeDirectory() stringByAppendingPathComponent:@".codex"];
}

static BOOL IsPicture(NSString* name) {
    NSString* extension = name.pathExtension.lowercaseString;
    return [@[@"png", @"jpg", @"jpeg", @"webp", @"gif"] containsObject:extension];
}

//the newest picture in a folder, with its time; nil when there is none
static NSURL* NewestPicture(NSString* folder, NSDate* since, NSDate** time) {
    NSURL* newest = nil;
    NSDate* newestTime = nil;
    for (NSString* name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:nil]) {
        if (!IsPicture(name))
            continue;
        NSURL* url = [NSURL fileURLWithPath:[folder stringByAppendingPathComponent:name]];
        NSDate* modified = nil;
        [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
        if (modified == nil || (since != nil && [modified compare:since] == NSOrderedAscending))
            continue;
        if (newestTime == nil || [modified compare:newestTime] == NSOrderedDescending) {
            newest = url;
            newestTime = modified;
        }
    }
    if (time != NULL)
        *time = newestTime;
    return newest;
}

+(NSURL*)generatedImageForThread:(NSString*)thread codexHome:(NSString*)codexHome since:(NSDate*)since {
    NSString* generated = [codexHome stringByAppendingPathComponent:@"generated_images"];
    //the name of a thread comes from the output of a program: only what a name of a thread is made of goes into a path
    NSCharacterSet* allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"];
    if (thread.length > 0 && thread.length <= 80 && [thread rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound) {
        NSURL* found = NewestPicture([generated stringByAppendingPathComponent:thread], nil, NULL);
        if (found != nil)
            return found;
    }
    //not found by its thread: the newest picture of the folders, if it was made since the run started. No leeway: the time of the file and
    //the time of the run are of the same Mac, and a picture of the run before must not be taken for this one
    if (since == nil)
        return nil;
    NSURL* newest = nil;
    NSDate* newestTime = nil;
    for (NSString* folder in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:generated error:nil]) {
        NSDate* time = nil;
        NSURL* candidate = NewestPicture([generated stringByAppendingPathComponent:folder], since, &time);
        if (candidate != nil && (newestTime == nil || [time compare:newestTime] == NSOrderedDescending)) {
            newest = candidate;
            newestTime = time;
        }
    }
    return newest;
}

-(NSData*)standardInputForPrompt:(NSString*)prompt systemPrompt:(NSString*)systemPrompt {
    switch (_kind) {
        case AIAgentKindCodex:
            return [[NSString stringWithFormat:@"%@\n\n%@", [AIAgentCLI instructionWithSystemPrompt:systemPrompt], prompt] dataUsingEncoding:NSUTF8StringEncoding];
        case AIAgentKindClaude:
            return [prompt dataUsingEncoding:NSUTF8StringEncoding];
        case AIAgentKindAntigravity:
            return nil;
    }
    return nil;
}

-(NSDictionary<NSString*, NSString*>*)environmentForExecutable:(NSString*)executable {
    NSDictionary<NSString*, NSString*>* own = [[NSProcessInfo processInfo] environment];
    NSMutableDictionary<NSString*, NSString*>* environment = [own mutableCopy];
    environment[@"PATH"] = [AIAgentCLI pathForExecutable:executable home:NSHomeDirectory() environmentPath:own[@"PATH"] ?: @""];
    environment[@"NO_COLOR"] = @"1";
    environment[@"TERM"] = @"dumb";
    return environment;
}

#pragma mark Errors

+(NSString*)gistOfErrorOutput:(NSString*)text {
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    for (NSString* raw in [WithoutEscapes(text) componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString* line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (line.length > 0)
            [lines addObject:line];
    }
    //the lines that start with "error" (a log may put a time in front) are the program saying what went wrong; the lines that only
    //mention it may be the request that was echoed; and with neither, the last lines
    static NSRegularExpression* startsWithError;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        startsWithError = [NSRegularExpression regularExpressionWithPattern:@"^(?:\\S+\\s+)?(?:error|fatal|panic)\\b" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSArray<NSString*>* markers = @[@"error", @"failed", @"denied", @"unauthor", @"not logged", @"login", @"limit", @"quota", @"invalid", @"unsupported", @"not found", @"unknown"];
    NSMutableArray<NSString*>* about = [NSMutableArray array];
    NSMutableArray<NSString*>* mentions = [NSMutableArray array];
    for (NSString* line in lines) {
        if ([startsWithError firstMatchInString:line options:0 range:NSMakeRange(0, line.length)] != nil) {
            [about addObject:line];
            continue;
        }
        NSString* lowered = line.lowercaseString;
        for (NSString* marker in markers)
            if ([lowered containsString:marker]) {
                [mentions addObject:line];
                break;
            }
    }
    if (about.count == 0)
        about = mentions;
    NSArray<NSString*>* chosen = about.count > 0 ? about : lines;
    NSUInteger count = MIN((NSUInteger)3, chosen.count);
    NSMutableArray<NSString*>* last = [NSMutableArray array];
    for (NSString* line in [chosen subarrayWithRange:NSMakeRange(chosen.count - count, count)])
        [last addObject:Shorten(line, 220)];
    return VOKAIRedact(Shorten([last componentsJoinedByString:@" "], 420), nil);
}

-(NSError*)errorForMessage:(NSString*)message exitStatus:(int)status model:(NSString*)model effort:(NSString*)effort {
    NSString* gist = [AIAgentCLI gistOfErrorOutput:message ?: @""];
    NSString* detail = gist.length > 0 ? [NSString stringWithFormat:@" (%@)", gist] : @"";
    NSString* lowered = gist.lowercaseString;
    BOOL (^has)(NSArray<NSString*>*) = ^BOOL(NSArray<NSString*>* words) {
        for (NSString* word in words)
            if ([lowered containsString:word])
                return YES;
        return NO;
    };
    if (effort.length > 0 && has(@[@"effort", @"reasoning"]) && has(@[@"unsupported", @"not supported", @"invalid", @"unknown", @"not allowed", @"expected"]))
        return MakeError(VOKAIErrorModel, [NSString stringWithFormat:@"%@ không nhận mức suy nghĩ “%@” cho model này. Chọn mức khác, hoặc “Mặc định của CLI”, trong Cài đặt > AI.%@",
                                           _displayName, effort, detail]);
    if (has(@[@"model"]) && has(@[@"not found", @"not exist", @"does not exist", @"unsupported", @"not supported", @"invalid", @"unknown", @"no access", @"not available", @"not allowed"]))
        return MakeError(VOKAIErrorModel, [NSString stringWithFormat:@"%@ không dùng được model “%@”. Chọn model khác trong Cài đặt > AI (nút “Tải danh sách”).%@",
                                           _displayName, model.length > 0 ? model : @"đang chọn", detail]);
    if (has(@[@"not logged in", @"not signed in", @"please run /login", @"codex login", @"login required", @"log in", @"sign in", @"authenticat",
              @"unauthorized", @"401", @"invalid api key", @"credentials", @"expired token", @"token expired", @"oauth"]))
        return MakeError(VOKAIErrorLogin, [NSString stringWithFormat:@"%@ chưa đăng nhập, hoặc phiên đăng nhập đã hết hạn. Mở Terminal, chạy `%@` rồi thử lại.%@",
                                           _displayName, _loginHint, detail]);
    //an option of the program that this version does not know: it is older (or newer) than the call that was written for it
    if (has(@[@"unknown option", @"unrecognized option", @"unexpected argument", @"unknown argument", @"unrecognized argument", @"invalid option", @"unknown flag", @"flag provided but not defined"]))
        return MakeError(VOKAIErrorServer, [NSString stringWithFormat:@"%@ không nhận một tùy chọn mà VOpenKey AI dùng: bản của chương trình có thể quá cũ, hoặc đã đổi cách gọi. Cập nhật chương trình rồi thử lại.%@",
                                            _displayName, detail]);
    if (has(@[@"rate limit", @"rate_limit", @"usage limit", @"quota", @"429", @"too many requests", @"overloaded", @"limit reached", @"credit"]))
        return MakeError(VOKAIErrorRateLimit, [NSString stringWithFormat:@"%@ báo đã hết hạn mức hoặc bị giới hạn tốc độ. Thử lại sau, hoặc chọn model nhẹ hơn.%@", _displayName, detail]);
    if (has(@[@"enotfound", @"econnrefused", @"econnreset", @"network", @"offline", @"timed out", @"timeout", @"dns", @"fetch failed", @"connection"]))
        return MakeError(VOKAIErrorNetwork, [NSString stringWithFormat:@"%@ không kết nối được tới dịch vụ. Kiểm tra mạng rồi thử lại.%@", _displayName, detail]);
    if (gist.length > 0)
        return MakeError(VOKAIErrorServer, [NSString stringWithFormat:@"%@ báo lỗi: %@", _displayName, gist]);
    return MakeError(VOKAIErrorServer, [NSString stringWithFormat:@"%@ dừng bất ngờ (mã %d) mà không nói lý do. Thử chạy `%@` trong Terminal để xem.", _displayName, status, _command]);
}

-(NSError*)errorForLaunchFailure:(NSString*)reason {
    NSString* install = _installHint.length > 0 ? [NSString stringWithFormat:@" Cài bằng: %@.", _installHint] : @"";
    return MakeError(VOKAIErrorNoProgram, [NSString stringWithFormat:@"Không chạy được chương trình `%@`%@.%@ Hoặc bấm “Chọn…” trong Cài đặt > AI để chỉ đường dẫn.",
                                           _command, reason.length > 0 ? [NSString stringWithFormat:@" (%@)", reason] : @"", install]);
}

@end
