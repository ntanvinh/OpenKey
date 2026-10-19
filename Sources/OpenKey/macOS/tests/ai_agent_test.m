// Tests of the AI agent programs (Codex, Claude Code, Antigravity) used as the AI of the assistant: where the programs are looked for,
// which models and thinking levels are offered and chosen, what is passed to each program and what is not, how their output is read,
// how their errors are told, and real runs against fake programs (fake_agent_cli.py) that include stopping, a child that outlives
// its parent, a program that does not read its input, and one that never ends.
// Run with run-ai-agent-test.sh.
//
//   ai_agent_test <fake_agent_cli.py> [file with the output of `codex debug models`]
//
// No real AI program is run and nothing is sent anywhere. The second argument, when there is one, is only read: it is checked that
// the catalog of the real Codex can be understood.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <signal.h>
#import "AIProvider.h"
#import "AISettings.h"
#import "AIClient.h"
#import "AIAgentCLI.h"
#import "AIAgentProcess.h"
#import "AIAgentRunner.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSString* gFake;         //the fake program
static NSString* gWork;         //a temporary folder: gWork/bin has a link to the fake program for each name, gWork/runs is where requests work
static NSString* gLog;
static NSString* gPids;

static void Spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static BOOL SpinUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [end timeIntervalSinceNow] > 0)
        Spin(0.01);
    return done();
}

//the real path of a file, the way a program that asks for its folder gets it (/private/var/..., which NSString would shorten to /var/...)
static NSString* RealPath(NSString* path) {
    char buffer[PATH_MAX];
    return realpath(path.fileSystemRepresentation, buffer) != NULL ? [NSString stringWithUTF8String:buffer] : path;
}

static AIProvider* Provider(NSString* identifier) {
    return [AIProvider providerWithIdentifier:identifier];
}

static NSString* Link(NSString* command) {
    return [[gWork stringByAppendingPathComponent:@"bin"] stringByAppendingPathComponent:command];
}

static NSString* CommandOf(NSString* providerId) {
    return [AIAgentCLI forProvider:Provider(providerId)].command;
}

static void Mode(NSString* mode) {
    setenv("FAKE_AGENT_MODE", mode.UTF8String, 1);
    [[NSFileManager defaultManager] removeItemAtPath:gLog error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:gPids error:nil];
}

static NSDictionary* ReadLog(void) {
    SpinUntil(^BOOL { return [[NSFileManager defaultManager] fileExistsAtPath:gLog]; }, 3);
    NSData* data = [NSData dataWithContentsOfFile:gLog];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

static NSArray<NSNumber*>* ReadPids(void) {
    SpinUntil(^BOOL { return [[NSString stringWithContentsOfFile:gPids encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByString:@" "].count >= 2; }, 5);
    NSMutableArray* pids = [NSMutableArray array];
    for (NSString* part in [[NSString stringWithContentsOfFile:gPids encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]])
        if (part.intValue > 0)
            [pids addObject:@(part.intValue)];
    return pids;
}

static BOOL IsAlive(pid_t pid) {
    return kill(pid, 0) == 0;
}

static BOOL WaitUntilGone(NSArray<NSNumber*>* pids, NSTimeInterval timeout) {
    return SpinUntil(^BOOL {
        for (NSNumber* pid in pids)
            if (IsAlive(pid.intValue))
                return NO;
        return YES;
    }, timeout);
}

static void KillAll(NSArray<NSNumber*>* pids) {
    for (NSNumber* pid in pids)
        kill(pid.intValue, SIGKILL);
}

static AIConfiguration* Config(NSString* providerId, NSString* model, NSString* effort) {
    AIConfiguration* c = [[AIConfiguration alloc] init];
    c.provider = Provider(providerId);
    c.baseURL = @"";
    c.model = model ?: @"";
    c.effort = effort;
    c.executablePath = Link(CommandOf(providerId));
    c.systemPrompt = @"Trả lời ngắn.";
    return c;
}

//a request made to the end, through AIClient like the assistant does
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

static NSString* JoinedArguments(NSArray* args) {
    return [args componentsJoinedByString:@"␟"];      //a character that is in no argument
}

//the argument that follows `flag`, nil when the flag is not there
static NSString* ValueAfter(NSArray<NSString*>* args, NSString* flag) {
    NSUInteger index = [args indexOfObject:flag];
    return index != NSNotFound && index + 1 < args.count ? args[index + 1] : nil;
}

#pragma mark - Providers

static void TestProviders(void) {
    printf("-- providers\n");
    for (NSString* identifier in @[@"codex-cli", @"claude-cli", @"agy-cli"]) {
        AIProvider* p = Provider(identifier);
        CHECK(p != nil && p.isAgentCLI && p.protocol == AIProtocolAgentCLI);
        CHECK(!p.needsKey && !p.isLocal && p.defaultBaseURL.length == 0);       //no key, and nothing leaves through an address of ours
        CHECK(p.name.length > 0 && p.note.length > 0);
        AIAgentCLI* cli = [AIAgentCLI forProvider:p];
        CHECK(cli != nil && cli.command.length > 0 && cli.displayName.length > 0 && cli.loginHint.length > 0);
    }
    CHECK([[Provider(@"codex-cli") defaultModel] isEqualToString:@""]);          //"choose a light one for me"
    CHECK([[Provider(@"claude-cli") defaultModel] isEqualToString:@"haiku"]);
    CHECK([[AIAgentCLI forProvider:Provider(@"codex-cli")].command isEqualToString:@"codex"]);
    CHECK([[AIAgentCLI forProvider:Provider(@"claude-cli")].command isEqualToString:@"claude"]);
    CHECK([[AIAgentCLI forProvider:Provider(@"agy-cli")].command isEqualToString:@"agy"]);
    //the services that have an address are not programs
    CHECK([AIAgentCLI forProvider:Provider(@"openai")] == nil && !Provider(@"openai").isAgentCLI && !Provider(@"ollama").isAgentCLI);
    //the first one is still what it was: whoever had not chosen keeps what they had
    CHECK([[AIProvider defaultProvider].identifier isEqualToString:@"openai"]);
}

static void TestEffortNames(void) {
    printf("-- names of thinking levels\n");
    for (NSString* level in [AIAgentCLI commonEfforts])
        CHECK([AIAgentCLI nameOfEffort:level].length > 0 && ![[AIAgentCLI nameOfEffort:level] isEqualToString:level]);
    CHECK([AIAgentCLI commonEfforts].count == 5 && [[AIAgentCLI commonEfforts].firstObject isEqualToString:@"low"]);
    CHECK([[AIAgentCLI nameOfEffort:@"something-new"] isEqualToString:@"something-new"]);     //an unknown level is shown as it is
}

#pragma mark - Models

static NSData* Json(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

static void TestCatalog(const char* realCatalog) {
    printf("-- catalog of Codex\n");
    NSDictionary* catalog = @{@"models": @[
        @{@"slug": @"big", @"display_name": @"Big", @"description": @"Frontier intelligence for the most demanding work.", @"visibility": @"list", @"priority": @3,
          @"default_reasoning_level": @"low", @"supported_reasoning_levels": @[@{@"effort": @"low"}, @{@"effort": @"high"}, @{@"effort": @"ultra"}]},
        @{@"slug": @"work", @"display_name": @"Work", @"description": @"Latest workhorse model for coding and everyday work.", @"visibility": @"list", @"priority": @1,
          @"supported_reasoning_levels": @[@{@"effort": @"low"}, @{@"effort": @"medium"}]},
        @{@"slug": @"mini", @"display_name": @"Mini", @"description": @"Fast and affordable model for easier tasks.", @"visibility": @"list", @"priority": @4,
          @"default_reasoning_level": @"medium", @"supported_reasoning_levels": @[@"minimal", @"low", @"medium"]},
        @{@"slug": @"old-mini", @"description": @"Older fast and efficient model.", @"visibility": @"list", @"priority": @9},
        @{@"slug": @"hidden", @"description": @"Automatic review, fast.", @"visibility": @"hide", @"priority": @0},
        @{@"slug": @"", @"description": @"no name"},
        @{@"display_name": @"no slug"},
        @42, @"text", [NSNull null],
        @{@"slug": @"mini", @"description": @"a duplicate"},
    ]};
    NSArray<AIAgentModel*>* models = [AIAgentCLI modelsFromCodexCatalog:Json(catalog)];
    NSMutableArray* ids = [NSMutableArray array];
    for (AIAgentModel* m in models)
        [ids addObject:m.identifier];
    //by priority, what is only for the program itself left out, nothing twice
    CHECK(([ids isEqualToArray:@[@"work", @"big", @"mini", @"old-mini"]]));
    AIAgentModel* mini = [AIAgentCLI modelWithIdentifier:@"mini" among:models];
    CHECK([mini.name isEqualToString:@"Mini"] && mini.light && [mini.defaultEffort isEqualToString:@"medium"]);
    CHECK(([mini.efforts isEqualToArray:@[@"minimal", @"low", @"medium"]]));        //levels given as plain strings too
    CHECK(![AIAgentCLI modelWithIdentifier:@"big" among:models].light);             //"frontier", "demanding": not for everyday text
    CHECK(![AIAgentCLI modelWithIdentifier:@"work" among:models].light);
    CHECK(![AIAgentCLI modelWithIdentifier:@"old-mini" among:models].light);        //an older one is not what to start with
    CHECK([AIAgentCLI modelWithIdentifier:@"old-mini" among:models].efforts == nil && [[AIAgentCLI modelWithIdentifier:@"old-mini" among:models].name isEqualToString:@"old-mini"]);
    CHECK([AIAgentCLI modelWithIdentifier:@"hidden" among:models] == nil);
    //words, not pieces of words: "mini" is not in "Gemini" or "minimal", "fast" is not in "breakfast"
    NSArray<AIAgentModel*>* worded = [AIAgentCLI modelsFromCodexCatalog:Json(@{@"models": @[
        @{@"slug": @"a", @"description": @"Gemini based, minimal and breakfast ready", @"visibility": @"list"},
        @{@"slug": @"b", @"description": @"A mini model.", @"visibility": @"list"},
        @{@"slug": @"c", @"description": @"Quick, cheap answers", @"visibility": @"list"}]})];
    CHECK(worded.count == 3 && ![AIAgentCLI modelWithIdentifier:@"a" among:worded].light && [AIAgentCLI modelWithIdentifier:@"b" among:worded].light && [AIAgentCLI modelWithIdentifier:@"c" among:worded].light);
    //what is not a catalog is nothing, not a crash
    CHECK([AIAgentCLI modelsFromCodexCatalog:nil].count == 0);
    CHECK([AIAgentCLI modelsFromCodexCatalog:[@"not json" dataUsingEncoding:NSUTF8StringEncoding]].count == 0);
    CHECK([AIAgentCLI modelsFromCodexCatalog:Json(@{@"models": @"x"})].count == 0);
    CHECK([AIAgentCLI modelsFromCodexCatalog:Json(@[@{@"slug": @"as-array"}])].count == 1);     //a bare list too

    if (realCatalog != NULL) {
        printf("-- the catalog of the real Codex on this Mac\n");
        NSData* data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:realCatalog]];
        NSArray<AIAgentModel*>* real = [AIAgentCLI modelsFromCodexCatalog:data];
        CHECK(real.count >= 1);
        BOOL anyLight = NO;
        BOOL anyEfforts = NO;
        for (AIAgentModel* m in real) {
            CHECK(m.identifier.length > 0 && m.name.length > 0);
            anyEfforts |= m.efforts.count > 0;
            anyLight |= m.light;
        }
        CHECK(anyLight && anyEfforts);                                              //there is something light to start with, and levels to choose
        AIAgentCLI* codex = [AIAgentCLI forProvider:Provider(@"codex-cli")];
        NSString* chosen = [codex modelToPassForSaved:@"" models:real];
        NSString* effort = [codex effortToPassForSaved:nil modelToPass:chosen models:real];
        printf("   %lu models; light one chosen: %s, level %s\n", (unsigned long)real.count, chosen.UTF8String, effort.UTF8String);
        CHECK(chosen.length > 0 && effort.length > 0);
    }
}

//what `agy models` printed on a real Mac: models that only differ by the level at the end of their identifier and of their name
static NSString* const kRealAntigravityList =
    @"gemini-4-argon-medium\tGemini 4 Argon (Medium)\ngemini-4-argon-high\tGemini 4 Argon (High)\ngemini-4-argon-low\tGemini 4 Argon (Low)\n"
    @"gemini-3.8-flash-high\tGemini 3.8 Flash (High)\ngemini-3.8-flash-medium\tGemini 3.8 Flash (Medium)\ngemini-3.8-flash-low\tGemini 3.8 Flash (Low)\n"
    @"claude-opus-5-5-low\tClaude Opus 5.5 (Low)\nclaude-opus-5-5-medium\tClaude Opus 5.5 (Medium)\nclaude-opus-5-5-high\tClaude Opus 5.5 (High)\n"
    @"claude-sonnet-5-5-low\tClaude Sonnet 5.5 (Low)\nclaude-sonnet-5-5-medium\tClaude Sonnet 5.5 (Medium)\nclaude-sonnet-5-5-high\tClaude Sonnet 5.5 (High)\n"
    @"gpt-oss-120b-medium\tGPT-OSS 120B (Medium)\n";

static void TestAntigravityList(void) {
    printf("-- list of Antigravity\n");
    NSArray<AIAgentModel*>* models = [AIAgentCLI modelsFromAntigravityList:kRealAntigravityList];
    NSMutableArray* ids = [NSMutableArray array];
    for (AIAgentModel* m in models)
        [ids addObject:m.identifier];
    //one model for the entries that are its levels, in the order of the program
    CHECK(([ids isEqualToArray:@[@"gemini-4-argon", @"gemini-3.8-flash", @"claude-opus-5-5", @"claude-sonnet-5-5", @"gpt-oss-120b"]]));
    AIAgentModel* flash = [AIAgentCLI modelWithIdentifier:@"gemini-3.8-flash" among:models];
    CHECK([flash.name isEqualToString:@"Gemini 3.8 Flash"] && flash.light);
    CHECK(([flash.efforts isEqualToArray:@[@"low", @"medium", @"high"]]));                       //lowest first, whatever the order of the list
    CHECK([flash.variants[@"low"] isEqualToString:@"gemini-3.8-flash-low"] && [flash.variants[@"high"] isEqualToString:@"gemini-3.8-flash-high"]);
    CHECK(![AIAgentCLI modelWithIdentifier:@"gemini-4-argon" among:models].light && ![AIAgentCLI modelWithIdentifier:@"claude-opus-5-5" among:models].light);
    CHECK(([[AIAgentCLI modelWithIdentifier:@"gpt-oss-120b" among:models].efforts isEqualToArray:@[@"medium"]]));       //a model with a single level
    CHECK([[AIAgentCLI modelWithIdentifier:@"gpt-oss-120b" among:models].name isEqualToString:@"GPT-OSS 120B"]);

    //a status line on the output, a model without levels, one whose name does not match its identifier (so they are not levels)
    models = [AIAgentCLI modelsFromAntigravityList:@"Fetching available models...\nplain-model\tA Model Without Levels\nsome-low\tSomething Else\nx-high\tX (Low)\ny-high\tY (High)\n"];
    [ids removeAllObjects];
    for (AIAgentModel* m in models)
        [ids addObject:m.identifier];
    CHECK(([ids isEqualToArray:@[@"plain-model", @"some-low", @"x-high", @"y"]]));
    CHECK([AIAgentCLI modelWithIdentifier:@"plain-model" among:models].variants == nil && [AIAgentCLI modelWithIdentifier:@"plain-model" among:models].efforts == nil);
    CHECK([AIAgentCLI modelWithIdentifier:@"y" among:models].variants.count == 1);

    //without tabs: a line is the name and what --model takes, a bullet in front goes, "id    Name" is two columns
    models = [AIAgentCLI modelsFromAntigravityList:
        @"Available models:\n  - Gemini Flash (Low)\n* Gemini Pro (High)\n\n    fake-id    Name With Id\n# comment\n  Gemini Flash (Low)\n\x1B[1mBold One\x1B[0m\n"];
    [ids removeAllObjects];
    for (AIAgentModel* m in models)
        [ids addObject:m.identifier];
    CHECK(([ids isEqualToArray:@[@"Gemini Flash (Low)", @"Gemini Pro (High)", @"fake-id", @"Bold One"]]));
    CHECK([[AIAgentCLI modelWithIdentifier:@"fake-id" among:models].name isEqualToString:@"Name With Id"]);
    CHECK([AIAgentCLI modelsFromAntigravityList:@""].count == 0 && [AIAgentCLI modelsFromAntigravityList:@"\n\n"].count == 0);
}

static NSArray<AIAgentModel*>* SampleModels(void) {
    AIAgentModel* mini = [[AIAgentModel alloc] init];
    mini.identifier = @"mini"; mini.name = @"Mini"; mini.light = YES; mini.efforts = @[@"minimal", @"low", @"medium"];
    AIAgentModel* big = [[AIAgentModel alloc] init];
    big.identifier = @"big"; big.name = @"Big"; big.efforts = @[@"medium", @"high", @"ultra"];       //no "low"
    return @[big, mini];
}

static void TestChoosing(void) {
    printf("-- choosing the model and the thinking level\n");
    AIAgentCLI* codex = [AIAgentCLI forProvider:Provider(@"codex-cli")];
    AIAgentCLI* claude = [AIAgentCLI forProvider:Provider(@"claude-cli")];
    AIAgentCLI* agy = [AIAgentCLI forProvider:Provider(@"agy-cli")];
    NSArray* models = SampleModels();

    //the model: what the user chose, otherwise a light one
    CHECK([[codex modelToPassForSaved:@"" models:models] isEqualToString:@"mini"]);
    CHECK([[codex modelToPassForSaved:nil models:models] isEqualToString:@"mini"]);
    CHECK([[codex modelToPassForSaved:@"  big " models:models] isEqualToString:@"big"]);
    CHECK([[codex modelToPassForSaved:@"typed-by-hand" models:@[]] isEqualToString:@"typed-by-hand"]);
    CHECK([codex modelToPassForSaved:@"" models:@[]] == nil);                    //the catalog is not known: the program's own default
    CHECK([[claude modelToPassForSaved:@"" models:@[]] isEqualToString:@"haiku"]);
    CHECK([[claude modelToPassForSaved:@"opus" models:@[]] isEqualToString:@"opus"]);
    CHECK([agy modelToPassForSaved:@"" models:@[]] == nil);
    CHECK([[agy modelToPassForSaved:@"Gemini Flash (Low)" models:@[]] isEqualToString:@"Gemini Flash (Low)"]);
    CHECK([[AIAgentCLI forProvider:Provider(@"claude-cli")] knownModels].count == 4 && [[[claude knownModels].firstObject identifier] isEqualToString:@"haiku"]);
    CHECK([claude knownModels].firstObject.light && ![claude knownModels][1].light);

    //the level: "choose for me" is the fast one the model accepts
    CHECK([[codex effortToPassForSaved:nil modelToPass:@"mini" models:models] isEqualToString:@"low"]);
    CHECK([[codex effortToPassForSaved:@"" modelToPass:@"mini" models:models] isEqualToString:@"low"]);
    CHECK([[codex effortToPassForSaved:nil modelToPass:@"big" models:models] isEqualToString:@"medium"]);      //no "low": the lowest it has
    CHECK([[codex effortToPassForSaved:@"high" modelToPass:@"big" models:models] isEqualToString:@"high"]);
    CHECK([[codex effortToPassForSaved:@"medium" modelToPass:@"mini" models:models] isEqualToString:@"medium"]);
    CHECK([[codex effortToPassForSaved:@"ultra" modelToPass:@"mini" models:models] isEqualToString:@"low"]);    //not accepted by this model: back to automatic
    CHECK([codex effortToPassForSaved:AIAgentEffortProgramDefault modelToPass:@"mini" models:models] == nil);   //the program's own
    CHECK([[codex effortToPassForSaved:nil modelToPass:nil models:@[]] isEqualToString:@"low"]);                 //model not known: the common levels
    CHECK([[claude effortToPassForSaved:nil modelToPass:@"haiku" models:@[]] isEqualToString:@"low"]);
    CHECK([[claude effortToPassForSaved:@"max" modelToPass:@"opus" models:@[]] isEqualToString:@"max"]);
    CHECK([agy effortToPassForSaved:nil modelToPass:nil models:@[]] == nil);                                     //a model that is not known keeps its own level
    CHECK([[agy effortToPassForSaved:@"high" modelToPass:nil models:@[]] isEqualToString:@"high"]);

    //Antigravity with the list it really gave: a light model, and its levels are models
    NSArray<AIAgentModel*>* list = [AIAgentCLI modelsFromAntigravityList:kRealAntigravityList];
    CHECK([[agy modelToPassForSaved:@"" models:list] isEqualToString:@"gemini-3.8-flash"]);
    CHECK([[agy effortToPassForSaved:nil modelToPass:@"gemini-3.8-flash" models:list] isEqualToString:@"low"]);
    CHECK([[agy effortToPassForSaved:nil modelToPass:@"gpt-oss-120b" models:list] isEqualToString:@"medium"]);      //its only level
    CHECK([[agy effortToPassForSaved:@"xhigh" modelToPass:@"gemini-3.8-flash" models:list] isEqualToString:@"low"]); //not one of its levels: automatic
    __block NSString* model = nil, *effort = nil;
    void (^resolve)(AIAgentCLI*, NSString*, NSString*, NSArray*) = ^(AIAgentCLI* cli, NSString* savedModel, NSString* savedEffort, NSArray* known) {
        NSString* chosenModel = nil, *chosenEffort = nil;
        [cli resolveModel:savedModel effort:savedEffort models:known modelArgument:&chosenModel effortArgument:&chosenEffort];
        model = chosenModel;
        effort = chosenEffort;
    };
    resolve(agy, nil, nil, list);                                                       //nothing chosen: the light model, its fast level
    CHECK([model isEqualToString:@"gemini-3.8-flash-low"] && effort == nil);            //the level is in the name, nothing else is passed
    resolve(agy, @"gemini-3.8-flash", @"high", list);
    CHECK([model isEqualToString:@"gemini-3.8-flash-high"] && effort == nil);
    resolve(agy, @"claude-opus-5-5", nil, list);
    CHECK([model isEqualToString:@"claude-opus-5-5-low"] && effort == nil);
    resolve(agy, @"claude-sonnet-5-5", AIAgentEffortProgramDefault, list);              //"the program's own": a medium one, it has to be some
    CHECK([model isEqualToString:@"claude-sonnet-5-5-medium"] && effort == nil);
    resolve(agy, @"gpt-oss-120b", nil, list);
    CHECK([model isEqualToString:@"gpt-oss-120b-medium"] && effort == nil);
    resolve(agy, @"typed-by-hand", nil, list);                                          //not in the list: passed as it is
    CHECK([model isEqualToString:@"typed-by-hand"] && effort == nil);
    resolve(agy, @"typed-by-hand", @"high", list);
    CHECK([model isEqualToString:@"typed-by-hand"] && [effort isEqualToString:@"high"]);
    resolve(agy, @"gemini-3.8-flash-high", nil, list);                                  //the full name of a level, typed
    CHECK([model isEqualToString:@"gemini-3.8-flash-high"] && effort == nil);
    resolve(agy, nil, nil, @[]);                                                        //no list: the program's own
    CHECK(model == nil && effort == nil);
    //the others have no variants: what was chosen is what is passed
    resolve(codex, nil, nil, models);
    CHECK([model isEqualToString:@"mini"] && [effort isEqualToString:@"low"]);
    resolve(codex, @"big", @"high", models);
    CHECK([model isEqualToString:@"big"] && [effort isEqualToString:@"high"]);
    //the level that a request really has, and what it costs in time
    CHECK([[agy effectiveEffortForSavedModel:nil effort:nil models:list] isEqualToString:@"low"]);
    CHECK([[agy effectiveEffortForSavedModel:@"claude-opus-5-5" effort:@"high" models:list] isEqualToString:@"high"]);
    CHECK([[agy effectiveEffortForSavedModel:@"claude-sonnet-5-5" effort:AIAgentEffortProgramDefault models:list] isEqualToString:@"medium"]);   //a level it has to be
    CHECK([agy effectiveEffortForSavedModel:@"typed-by-hand" effort:nil models:list] == nil);
    CHECK([[codex effectiveEffortForSavedModel:nil effort:nil models:models] isEqualToString:@"low"]);
    CHECK([codex effectiveEffortForSavedModel:@"big" effort:AIAgentEffortProgramDefault models:models] == nil);
    CHECK([AIAgentCLI isFastEffort:nil] && [AIAgentCLI isFastEffort:@"low"] && [AIAgentCLI isFastEffort:@"minimal"]);
    CHECK(![AIAgentCLI isFastEffort:@"medium"] && ![AIAgentCLI isFastEffort:@"high"] && ![AIAgentCLI isFastEffort:@"max"]);
    for (NSString* level in @[@"low", @"medium", @"high", @"xhigh", @"max", @"ultra"])
        CHECK([AIAgentCLI speedNoteForEffort:level].length > 0);
    CHECK(![[AIAgentCLI speedNoteForEffort:@"low"] isEqualToString:[AIAgentCLI speedNoteForEffort:@"medium"]] && [[AIAgentCLI speedNoteForEffort:@"medium"] containsString:@"40 giây"]);
    CHECK([AIAgentCLI speedNoteForEffort:nil].length > 0);
    resolve(claude, nil, nil, @[]);
    CHECK([model isEqualToString:@"haiku"] && [effort isEqualToString:@"low"]);
    resolve(claude, @"opus", AIAgentEffortProgramDefault, @[]);
    CHECK([model isEqualToString:@"opus"] && effort == nil);
}

#pragma mark - What is passed

static void TestArguments(void) {
    printf("-- arguments\n");
    NSString* secret = @"NỘI DUNG RIÊNG TƯ CỦA NGƯỜI DÙNG";
    NSString* system = @"Hãy trả lời bằng tiếng Việt.";
    NSString* work = @"/tmp/work-folder";

    //Codex
    AIAgentCLI* codex = [AIAgentCLI forProvider:Provider(@"codex-cli")];
    NSArray<NSString*>* a = [codex argumentsWithModel:@"mini" effort:@"low" systemPrompt:system prompt:secret workDirectory:work];
    CHECK([a.firstObject isEqualToString:@"exec"] && [a.lastObject isEqualToString:@"-"]);               //the request is read from the input
    CHECK([a containsObject:@"--ignore-user-config"] && [a containsObject:@"--ignore-rules"]);           //nothing of the user's setup
    CHECK([a containsObject:@"--ephemeral"] && [a containsObject:@"--skip-git-repo-check"]);
    CHECK([ValueAfter(a, @"-s") isEqualToString:@"read-only"]);                                         //it may not write
    CHECK([ValueAfter(a, @"--disable") isEqualToString:@"shell_tool"]);                                 //it may not run commands
    CHECK([ValueAfter(a, @"-C") isEqualToString:work]);
    CHECK([ValueAfter(a, @"-m") isEqualToString:@"mini"]);
    CHECK([ValueAfter(a, @"-c") isEqualToString:@"model_reasoning_effort=\"low\""]);
    CHECK([ValueAfter(a, @"--color") isEqualToString:@"never"]);
    CHECK(![JoinedArguments(a) containsString:secret] && ![JoinedArguments(a) containsString:system]);   //not where every program can list it
    NSString* input = [[NSString alloc] initWithData:[codex standardInputForPrompt:secret systemPrompt:system] encoding:NSUTF8StringEncoding];
    CHECK([input containsString:secret] && [input containsString:system] && [input containsString:@"do not run commands"]);
    CHECK([input rangeOfString:system].location < [input rangeOfString:secret].location);
    a = [codex argumentsWithModel:nil effort:nil systemPrompt:system prompt:secret workDirectory:work];
    CHECK(![a containsObject:@"-m"] && ![a containsObject:@"-c"]);                                       //nothing chosen: nothing passed

    //Claude Code
    AIAgentCLI* claude = [AIAgentCLI forProvider:Provider(@"claude-cli")];
    a = [claude argumentsWithModel:@"haiku" effort:@"low" systemPrompt:system prompt:secret workDirectory:work];
    CHECK([a.firstObject isEqualToString:@"-p"] && [a containsObject:@"--safe-mode"] && [a containsObject:@"--no-session-persistence"]);
    NSUInteger tools = [a indexOfObject:@"--tools"];
    CHECK(tools != NSNotFound && [a[tools + 1] isEqualToString:@""]);                                     //no tool at all
    CHECK([ValueAfter(a, @"--output-format") isEqualToString:@"stream-json"] && [a containsObject:@"--include-partial-messages"] && [a containsObject:@"--verbose"]);
    CHECK([ValueAfter(a, @"--model") isEqualToString:@"haiku"] && [ValueAfter(a, @"--effort") isEqualToString:@"low"]);
    NSString* prompt = ValueAfter(a, @"--system-prompt");
    CHECK([prompt containsString:system] && [prompt containsString:@"no tools"]);
    CHECK(![JoinedArguments(a) containsString:secret]);
    CHECK([[[NSString alloc] initWithData:[claude standardInputForPrompt:secret systemPrompt:system] encoding:NSUTF8StringEncoding] isEqualToString:secret]);
    a = [claude argumentsWithModel:nil effort:nil systemPrompt:nil prompt:secret workDirectory:work];
    CHECK(![a containsObject:@"--model"] && ![a containsObject:@"--effort"]);
    CHECK([ValueAfter(a, @"--system-prompt") containsString:@"no tools"]);                                //the rule is there even without an instruction

    //Antigravity: the prompt is the last argument, after the flags
    AIAgentCLI* agy = [AIAgentCLI forProvider:Provider(@"agy-cli")];
    a = [agy argumentsWithModel:@"Gemini Flash (Low)" effort:nil systemPrompt:system prompt:secret workDirectory:work];
    CHECK([ValueAfter(a, @"--model") isEqualToString:@"Gemini Flash (Low)"] && ![a containsObject:@"--effort"]);
    CHECK([a[a.count - 2] isEqualToString:@"-p"] && [a.lastObject containsString:secret] && [a.lastObject containsString:system]);
    CHECK([a.lastObject hasPrefix:@"You are"]);                                                          //never looks like a flag
    CHECK([agy standardInputForPrompt:secret systemPrompt:system] == nil);
    CHECK([ValueAfter(a, @"--output-format") isEqualToString:@"text"]);

    //what a person typed in the settings can not become a flag or a piece of the configuration
    a = [codex argumentsWithModel:@"--dangerously-bypass-approvals-and-sandbox" effort:@"low\"\nsandbox_mode=\"danger-full-access" systemPrompt:system prompt:secret workDirectory:work];
    CHECK(![a containsObject:@"-m"] && ![a containsObject:@"-c"] && ![JoinedArguments(a) containsString:@"danger"]);
    a = [claude argumentsWithModel:@"-x" effort:@"-y" systemPrompt:system prompt:secret workDirectory:work];
    CHECK(![a containsObject:@"--model"] && ![a containsObject:@"--effort"]);
    CHECK(![AIAgentCLI isPlausibleModelName:@""] && ![AIAgentCLI isPlausibleModelName:@"-m"] && ![AIAgentCLI isPlausibleModelName:@"a\nb"]);
    CHECK([AIAgentCLI isPlausibleModelName:@"gpt-6-luna"] && [AIAgentCLI isPlausibleModelName:@"Gemini 4 Argon (Medium)"] && [AIAgentCLI isPlausibleModelName:@"claude-haiku-4-5-20251001"]);
}

#pragma mark - Reading the output

static NSString* FeedPlain(AIAgentOutput format, NSData* data, NSUInteger chunk, NSString** error) {
    AIAgentOutputParser* parser = [[AIAgentOutputParser alloc] initWithFormat:format];
    NSMutableString* all = [NSMutableString string];
    for (NSUInteger i = 0; i < data.length; i += chunk)
        for (NSString* piece in [parser feed:[data subdataWithRange:NSMakeRange(i, MIN(chunk, data.length - i))]])
            [all appendString:piece];
    for (NSString* piece in [parser finish])
        [all appendString:piece];
    if (error != NULL)
        *error = parser.errorMessage;
    return all;
}

static NSData* Lines(NSArray<NSDictionary*>* objects) {
    NSMutableString* text = [NSMutableString string];
    for (NSDictionary* object in objects)
        [text appendFormat:@"%@\n", [[NSString alloc] initWithData:Json(object) encoding:NSUTF8StringEncoding]];
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

static NSDictionary* Delta(NSString* kind, NSString* key, NSString* text) {
    return @{@"type": @"stream_event", @"event": @{@"type": @"content_block_delta", @"index": @0, @"delta": @{@"type": kind, key: text}}};
}

static void TestOutputParsers(void) {
    printf("-- reading the output\n");
    //plain text, cut anywhere, byte by byte: a letter of Vietnamese or an emoji cut in two is still one letter
    NSString* text = @"Tiếng Việt ❤️ 😀 đẹp\nDòng hai";
    NSData* data = [text dataUsingEncoding:NSUTF8StringEncoding];
    for (NSUInteger chunk = 1; chunk <= 7; chunk++)
        CHECK([FeedPlain(AIAgentOutputPlain, data, chunk, NULL) isEqualToString:text]);
    //colours of a program that thinks it is in a terminal
    CHECK([FeedPlain(AIAgentOutputPlain, [@"\x1B[1mXin\x1B[0m \x1B[38;5;12mchào\x1B[0m\x1B]0;title\x07!" dataUsingEncoding:NSUTF8StringEncoding], 1000, NULL) isEqualToString:@"Xin chào!"]);
    CHECK([FeedPlain(AIAgentOutputPlain, [NSData data], 10, NULL) length] == 0);

    //stream-json of Claude Code: the answer in pieces, not what it thought, byte by byte
    NSData* stream = Lines(@[
        @{@"type": @"system", @"subtype": @"init"},
        Delta(@"thinking_delta", @"thinking", @"let me think about it"),
        Delta(@"text_delta", @"text", @"Xin "),
        Delta(@"text_delta", @"text", @"chào ❤️"),
        @{@"type": @"assistant", @"message": @{@"content": @[@{@"type": @"text", @"text": @"Xin chào ❤️"}]}},
        @{@"type": @"result", @"subtype": @"success", @"is_error": @NO, @"result": @"Xin chào ❤️"}]);
    NSString* error = nil;
    for (NSUInteger chunk = 1; chunk <= 5; chunk++) {
        NSString* result = FeedPlain(AIAgentOutputClaudeJSON, stream, chunk, &error);
        CHECK([result isEqualToString:@"Xin chào ❤️"] && error == nil);                                   //once, not twice: not the pieces and the complete message
    }
    AIAgentOutputParser* parser = [[AIAgentOutputParser alloc] initWithFormat:AIAgentOutputClaudeJSON];
    NSArray* pieces = [parser feed:stream];
    CHECK(pieces.count == 2 && [pieces[0] isEqualToString:@"Xin "]);                                       //it arrives in pieces
    //no pieces: the message that completes them, or the result
    CHECK([FeedPlain(AIAgentOutputClaudeJSON, Lines(@[@{@"type": @"assistant", @"message": @{@"content": @[@{@"type": @"text", @"text": @"Cả khối"}]}},
                                                      @{@"type": @"result", @"is_error": @NO, @"result": @"Cả khối"}]), 9, &error) isEqualToString:@"Cả khối"]);
    CHECK([FeedPlain(AIAgentOutputClaudeJSON, Lines(@[@{@"type": @"result", @"is_error": @NO, @"result": @"Chỉ kết quả"}]), 9, &error) isEqualToString:@"Chỉ kết quả"]);
    //the last line without the line break
    NSData* noBreak = [@"{\"type\":\"result\",\"is_error\":false,\"result\":\"Không xuống dòng\"}" dataUsingEncoding:NSUTF8StringEncoding];
    CHECK([FeedPlain(AIAgentOutputClaudeJSON, noBreak, 4, &error) isEqualToString:@"Không xuống dòng"]);
    //a failure says so, and gives no text
    NSString* none = FeedPlain(AIAgentOutputClaudeJSON, Lines(@[@{@"type": @"result", @"subtype": @"success", @"is_error": @YES, @"result": @"Not logged in · Please run /login"}]), 7, &error);
    CHECK(none.length == 0 && [error isEqualToString:@"Not logged in · Please run /login"]);
    FeedPlain(AIAgentOutputClaudeJSON, Lines(@[@{@"type": @"result", @"subtype": @"error_max_turns"}]), 7, &error);
    CHECK(error != nil);
    //what is not JSON is kept for the message of an error; values of another kind than expected are nothing, not a crash
    parser = [[AIAgentOutputParser alloc] initWithFormat:AIAgentOutputClaudeJSON];
    [parser feed:[@"Warning: something\n{broken\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [parser feed:Lines(@[@{@"type": @5}, @{@"type": @"stream_event", @"event": @"x"}, @{@"type": @"stream_event", @"event": @{@"delta": @[]}},
                         @{@"type": @"assistant", @"message": @{@"content": @[@3, @{@"type": @9}]}}, @{@"type": @"result", @"is_error": @"yes", @"result": @7}])];
    [parser finish];
    CHECK([parser.leftover containsString:@"Warning: something"] && parser.errorMessage == nil);
}

#pragma mark - Errors

static void TestErrors(void) {
    printf("-- errors\n");
    AIAgentCLI* codex = [AIAgentCLI forProvider:Provider(@"codex-cli")];
    AIAgentCLI* claude = [AIAgentCLI forProvider:Provider(@"claude-cli")];

    NSString* codexLogin = @"OpenAI Codex v0.0\n--------\nworkdir: /x\nuser\nviết thư cho sếp\nERROR: Not logged in. Run `codex login` first.\n";
    NSError* e = [codex errorForMessage:codexLogin exitStatus:1 model:@"mini" effort:@"low"];
    CHECK(e.code == VOKAIErrorLogin && [e.localizedDescription containsString:@"codex login"] && [e.localizedDescription containsString:@"Codex CLI"]);
    CHECK(![e.localizedDescription containsString:@"viết thư cho sếp"]);                                 //what the user wrote is not repeated back
    e = [claude errorForMessage:@"Not logged in · Please run /login" exitStatus:1 model:@"haiku" effort:@"low"];
    CHECK(e.code == VOKAIErrorLogin && [e.localizedDescription containsString:@"claude auth login"]);
    e = [claude errorForMessage:@"API Error: 401 {\"error\":{\"message\":\"invalid x-api-key\"}}" exitStatus:1 model:@"haiku" effort:nil];
    CHECK(e.code == VOKAIErrorLogin);
    e = [codex errorForMessage:@"ERROR: You've hit your usage limit. Try again later (429)." exitStatus:1 model:nil effort:nil];
    CHECK(e.code == VOKAIErrorRateLimit);
    e = [claude errorForMessage:@"Claude usage limit reached. Your limit will reset at 5pm." exitStatus:1 model:nil effort:nil];
    CHECK(e.code == VOKAIErrorRateLimit);
    e = [codex errorForMessage:@"ERROR: The model `nope` does not exist or you do not have access to it." exitStatus:1 model:@"nope" effort:@"low"];
    CHECK(e.code == VOKAIErrorModel && [e.localizedDescription containsString:@"nope"]);
    e = [claude errorForMessage:@"There's an issue with the selected model (nope). It may not exist or you may not have access to it." exitStatus:1 model:@"nope" effort:nil];
    CHECK(e.code == VOKAIErrorModel);
    e = [codex errorForMessage:@"error: invalid value for reasoning effort 'ultra': unsupported for this model" exitStatus:2 model:@"mini" effort:@"ultra"];
    CHECK(e.code == VOKAIErrorModel && [e.localizedDescription containsString:@"ultra"] && [e.localizedDescription containsString:@"Mặc định của CLI"]);
    e = [codex errorForMessage:@"ERROR: stream error: getaddrinfo ENOTFOUND api.example.com" exitStatus:1 model:nil effort:nil];
    CHECK(e.code == VOKAIErrorNetwork);
    e = [claude errorForMessage:@"error: unknown option '--safe-mode'" exitStatus:1 model:nil effort:nil];
    CHECK(e.code == VOKAIErrorServer && [e.localizedDescription containsString:@"Cập nhật chương trình"] && [e.localizedDescription containsString:@"--safe-mode"]);
    e = [codex errorForMessage:@"ERROR: something nobody has seen" exitStatus:1 model:nil effort:nil];
    CHECK(e.code == VOKAIErrorServer && [e.localizedDescription containsString:@"something nobody has seen"]);
    e = [codex errorForMessage:@"" exitStatus:7 model:nil effort:nil];
    CHECK(e.code == VOKAIErrorServer && [e.localizedDescription containsString:@"7"] && [e.localizedDescription containsString:@"codex"]);
    e = [codex errorForMessage:nil exitStatus:1 model:nil effort:nil];
    CHECK(e.code == VOKAIErrorServer);
    //what looks like a key is not shown
    e = [codex errorForMessage:@"ERROR: failed with key sk-abcdefghijklmnop123456 and Bearer abcdefgh12345678 here" exitStatus:1 model:nil effort:nil];
    CHECK(![e.localizedDescription containsString:@"sk-abcdefghijklmnop123456"] && ![e.localizedDescription containsString:@"abcdefgh12345678"]);
    //the lines about the error, not the whole log; a long line is cut
    NSString* gist = [AIAgentCLI gistOfErrorOutput:@"a\nb\nc\nd\nERROR: first\nnoise\nERROR: second\nERROR: third\nERROR: fourth\ne\n"];
    CHECK([gist containsString:@"fourth"] && [gist containsString:@"third"] && [gist containsString:@"second"] && ![gist containsString:@"first"] && ![gist containsString:@"noise"]);
    CHECK([AIAgentCLI gistOfErrorOutput:[@"" stringByPaddingToLength:5000 withString:@"error x " startingAtIndex:0]].length <= 440);
    CHECK([[AIAgentCLI gistOfErrorOutput:@"line one\nline two\nline three\nline four"] isEqualToString:@"line two line three line four"]);
    CHECK([AIAgentCLI gistOfErrorOutput:@""].length == 0);
    e = [codex errorForLaunchFailure:@"đường dẫn sai"];
    CHECK(e.code == VOKAIErrorNoProgram && [e.localizedDescription containsString:@"npm install -g @openai/codex"] && [e.localizedDescription containsString:@"Chọn…"]);
    e = [[AIAgentCLI forProvider:Provider(@"agy-cli")] errorForLaunchFailure:nil];
    CHECK(e.code == VOKAIErrorNoProgram);
}

#pragma mark - Finding the program

static void MakeExecutable(NSString* path, BOOL executable) {
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    [@"#!/bin/sh\nexit 0\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: executable ? @0755 : @0644} ofItemAtPath:path error:nil];
}

static void TestLocating(void) {
    printf("-- finding the programs\n");
    NSString* home = [gWork stringByAppendingPathComponent:@"home"];
    AIAgentCLI* claude = [AIAgentCLI forProvider:Provider(@"claude-cli")];
    AIAgentCLI* codex = [AIAgentCLI forProvider:Provider(@"codex-cli")];
    AIAgentCLI* agy = [AIAgentCLI forProvider:Provider(@"agy-cli")];

    //nvm: the newest version of Node, the way a person reads numbers
    for (NSString* version in @[@"v9.0.0", @"v22.1.0", @"v18.20.0"])
        MakeExecutable([home stringByAppendingFormat:@"/.nvm/versions/node/%@/bin/claude", version], YES);
    CHECK([[claude locateExecutableWithOverride:nil home:home environmentPath:@""] isEqualToString:[home stringByAppendingString:@"/.nvm/versions/node/v22.1.0/bin/claude"]]);
    //~/.local/bin comes before them
    MakeExecutable([home stringByAppendingString:@"/.local/bin/claude"], YES);
    CHECK([[claude locateExecutableWithOverride:nil home:home environmentPath:@""] isEqualToString:[home stringByAppendingString:@"/.local/bin/claude"]]);
    //what the user chose comes first, when it can be run
    NSString* chosen = [gWork stringByAppendingString:@"/chosen/claude"];
    MakeExecutable(chosen, YES);
    CHECK([[claude locateExecutableWithOverride:chosen home:home environmentPath:@""] isEqualToString:chosen]);
    NSString* broken = [gWork stringByAppendingString:@"/chosen/not-executable"];
    MakeExecutable(broken, NO);
    CHECK([[claude locateExecutableWithOverride:broken home:home environmentPath:@""] isEqualToString:[home stringByAppendingString:@"/.local/bin/claude"]]);
    CHECK([[claude locateExecutableWithOverride:@"/nonexistent/claude" home:home environmentPath:@""] isEqualToString:[home stringByAppendingString:@"/.local/bin/claude"]]);
    CHECK([[claude locateExecutableWithOverride:[gWork stringByAppendingString:@"/chosen"] home:home environmentPath:@""] isEqualToString:[home stringByAppendingString:@"/.local/bin/claude"]]);   //a folder is not a program
    //a file without the permission to run is not found, a folder with the name is not either
    MakeExecutable([home stringByAppendingString:@"/.local/bin/agy"], NO);
    CHECK(![[agy locateExecutableWithOverride:nil home:home environmentPath:@""] isEqualToString:[home stringByAppendingString:@"/.local/bin/agy"]]);
    [[NSFileManager defaultManager] createDirectoryAtPath:[home stringByAppendingString:@"/.local/bin/codex"] withIntermediateDirectories:YES attributes:nil error:nil];
    CHECK(![[codex locateExecutableWithOverride:nil home:home environmentPath:@""] isEqualToString:[home stringByAppendingString:@"/.local/bin/codex"]]);
    //the PATH of the application, last
    MakeExecutable([gWork stringByAppendingString:@"/onpath/agy"], YES);
    CHECK([[agy locateExecutableWithOverride:nil home:home environmentPath:[gWork stringByAppendingString:@"/onpath"]] isEqualToString:[gWork stringByAppendingString:@"/onpath/agy"]]);

    //the folders: only those that exist, once each, the folder of the program first in the PATH of the program
    NSArray* dirs = [AIAgentCLI searchDirectoriesForHome:home environmentPath:[NSString stringWithFormat:@"/nonexistent:%@/.local/bin:/usr/bin::relative/dir", home]];
    CHECK(![dirs containsObject:@"/nonexistent"] && ![dirs containsObject:@"relative/dir"] && [dirs containsObject:@"/usr/bin"]);
    CHECK([[NSSet setWithArray:dirs] count] == dirs.count);                                  //once each, though ~/.local/bin was in the PATH too
    NSString* path = [AIAgentCLI pathForExecutable:chosen home:home environmentPath:@"/usr/bin:/bin"];
    CHECK([path hasPrefix:[[gWork stringByAppendingString:@"/chosen"] stringByAppendingString:@":"]]);
    CHECK([path containsString:@"/usr/bin"]);
    NSArray* parts = [path componentsSeparatedByString:@":"];
    CHECK([[NSSet setWithArray:parts] count] == parts.count);
    NSDictionary* env = [claude environmentForExecutable:chosen];
    CHECK([env[@"PATH"] hasPrefix:[gWork stringByAppendingString:@"/chosen:"]] && [env[@"NO_COLOR"] isEqualToString:@"1"] && env[@"HOME"] != nil);
}

#pragma mark - Settings

static void TestSettings(void) {
    printf("-- settings\n");
    AIProvider* codex = Provider(@"codex-cli");
    AIProvider* claude = Provider(@"claude-cli");
    [AISettings resetToDefaults];
    CHECK([AISettings effortForProvider:codex] == nil && [AISettings programForProvider:codex] == nil);
    CHECK([[AISettings modelForProvider:claude] isEqualToString:@"haiku"] && [[AISettings modelForProvider:codex] isEqualToString:@""]);

    [AISettings setEffort:@"high" forProvider:codex];
    CHECK([[AISettings effortForProvider:codex] isEqualToString:@"high"] && [AISettings effortForProvider:claude] == nil);       //each has its own
    [AISettings setEffort:AIAgentEffortProgramDefault forProvider:claude];
    CHECK([[AISettings effortForProvider:claude] isEqualToString:AIAgentEffortProgramDefault]);
    [AISettings setEffort:nil forProvider:codex];
    CHECK([AISettings effortForProvider:codex] == nil);
    [AISettings setEffort:@"  " forProvider:claude];
    CHECK([AISettings effortForProvider:claude] == nil);

    //a program the user chose is the one used
    [AISettings setProgram:Link(@"codex") forProvider:codex];
    CHECK([[AISettings executablePathForProvider:codex] isEqualToString:Link(@"codex")] && [AISettings isProviderReady:codex]);
    NSError* error = nil;
    AIConfiguration* c = [AISettings configurationForProvider:codex error:&error];
    CHECK(c != nil && error == nil && [c.executablePath isEqualToString:Link(@"codex")] && c.baseURL.length == 0 && c.key == nil);
    CHECK(c.model.length == 0 && c.effort == nil && c.systemPrompt.length > 0);                                                   //nothing chosen: "choose for me"
    [AISettings setModel:@"fake-mini" forProvider:codex];
    [AISettings setEffort:@"medium" forProvider:codex];
    c = [AISettings configurationForProvider:codex error:&error];
    CHECK([c.model isEqualToString:@"fake-mini"] && [c.effort isEqualToString:@"medium"]);
    //listing the models needs no model
    CHECK([AISettings configurationForListingModelsOfProvider:codex error:&error] != nil);
    //no key is asked for, and none is read from the keychain
    CHECK(c.key == nil && !codex.needsKey);

    //a program that is not there: the reason, in words, and settings can help
    [AISettings setProgram:@"/nonexistent/codex" forProvider:codex];
    NSString* found = [AISettings executablePathForProvider:codex];       //the usual places may still have a real one on this Mac
    CHECK(found == nil || ![found isEqualToString:@"/nonexistent/codex"]);
    if (found == nil) {
        CHECK(![AISettings isProviderReady:codex]);
        CHECK([AISettings configurationForProvider:codex error:&error] == nil && error.code == VOKAIErrorNoProgram && [error.localizedDescription containsString:@"codex"]);
    }

    //"Khôi phục mặc định" forgets the choices
    [AISettings setProgram:Link(@"claude") forProvider:claude];
    [AISettings setEffort:@"max" forProvider:claude];
    [AISettings setModel:@"opus" forProvider:claude];
    [AISettings resetToDefaults];
    CHECK([AISettings programForProvider:claude] == nil && [AISettings effortForProvider:claude] == nil && [[AISettings modelForProvider:claude] isEqualToString:@"haiku"]);
    CHECK([AISettings programForProvider:codex] == nil && [AISettings effortForProvider:codex] == nil && [[AISettings modelForProvider:codex] isEqualToString:@""]);
}

#pragma mark - Running a program

static void TestProcess(void) {
    printf("-- process\n");
    __block NSData* output = nil;
    __block NSString* errors = nil;
    __block NSError* error = nil;
    __block BOOL done = NO;
    void (^capture)(NSString*, NSArray*, NSTimeInterval) = ^(NSString* exe, NSArray* args, NSTimeInterval timeout) {
        output = nil; errors = nil; error = nil; done = NO;
        [AIAgentProcess captureOutputOfExecutable:exe arguments:args environment:nil timeout:timeout limit:1 << 20
                                       completion:^(NSData* o, NSString* e, NSError* f) { output = o; errors = e; error = f; done = YES; }];
        SpinUntil(^BOOL { return done; }, 15);
    };
    capture(@"/bin/echo", @[@"xin chào"], 5);
    CHECK(error == nil && [[[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] isEqualToString:@"xin chào\n"]);
    capture(@"/bin/sh", @[@"-c", @"echo out; echo oops >&2; exit 3"], 5);
    CHECK(error != nil && [[[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] isEqualToString:@"out\n"] && [errors containsString:@"oops"]);
    NSDate* start = [NSDate date];
    capture(@"/bin/sleep", @[@"30"], 0.5);
    CHECK(error != nil && [start timeIntervalSinceNow] > -6);                           //stopped at the timeout, not after 30 s
    capture(@"/nonexistent/program", @[], 5);
    CHECK(error.code == VOKAIErrorNoProgram);
    //a limit on what is kept
    __block NSData* limited = nil;
    done = NO;
    [AIAgentProcess captureOutputOfExecutable:@"/bin/sh" arguments:@[@"-c", @"head -c 400000 /dev/zero"] environment:nil timeout:10 limit:1000
                                   completion:^(NSData* o, NSString* e, NSError* f) { limited = o; done = YES; }];
    SpinUntil(^BOOL { return done; }, 10);
    CHECK(limited.length >= 1000 && limited.length < 400000);
}

static void TestModelLists(void) {
    printf("-- models asked of the programs\n");
    __block NSArray<AIAgentModel*>* models = nil;
    __block NSError* error = nil;
    __block BOOL done = NO;
    void (^load)(NSString*) = ^(NSString* providerId) {
        models = nil; error = nil; done = NO;
        [[AIAgentCLI forProvider:Provider(providerId)] loadModelsFromExecutable:Link(CommandOf(providerId)) completion:^(NSArray<AIAgentModel*>* m, NSError* e) {
            models = m; error = e; done = YES;
        }];
        SpinUntil(^BOOL { return done; }, 15);
    };
    Mode(@"ok");
    AIAgentCLI* codex = [AIAgentCLI forProvider:Provider(@"codex-cli")];
    load(@"codex-cli");
    CHECK(error == nil && models.count == 4 && [models.firstObject.identifier isEqualToString:@"fake-workhorse"]);
    CHECK([codex knownModels].count == 4);                                              //remembered for the menus
    CHECK([[codex modelToPassForSaved:@"" models:models] isEqualToString:@"fake-mini"]);
    load(@"agy-cli");
    NSMutableArray* ids = [NSMutableArray array];
    for (AIAgentModel* m in models)
        [ids addObject:m.identifier];
    CHECK(error == nil && ([ids isEqualToArray:@[@"gemini-4-argon", @"gemini-3.8-flash", @"claude-opus-5-5", @"claude-sonnet-5-5", @"gpt-oss-120b", @"plain-model"]]));
    CHECK([[AIAgentCLI forProvider:Provider(@"agy-cli")] knownModels].count == 6);
    load(@"claude-cli");
    CHECK(error == nil && models.count == 4);                                           //built in: nothing is run
    Mode(@"models-empty");
    load(@"agy-cli");
    CHECK(models == nil && error.code == VOKAIErrorEmpty);
    CHECK([[AIAgentCLI forProvider:Provider(@"agy-cli")] knownModels].count == 6);       //the last list that was good stays
    //the program is not there
    done = NO;
    [codex loadModelsFromExecutable:@"/nonexistent/codex" completion:^(NSArray<AIAgentModel*>* m, NSError* e) { models = m; error = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 5);
    CHECK(models == nil && error.code == VOKAIErrorNoProgram);
    //through AIClient, the way the settings ask for names
    Mode(@"ok");
    __block NSArray* names = nil;
    done = NO;
    [AIClient listModelsForConfiguration:Config(@"codex-cli", nil, nil) completion:^(NSArray<NSString*>* n, NSError* e) { names = n; done = YES; }];
    SpinUntil(^BOOL { return done; }, 10);
    CHECK([names containsObject:@"fake-mini"]);
}

static void TestRuns(void) {
    printf("-- real runs against the fake programs\n");
    NSString* prompt = @"Dịch sang tiếng Anh: xin chào ❤️";
    NSString* text = nil;
    NSError* error = nil;
    NSUInteger pieces = 0;

    //Codex, the model and the level chosen for the user from the catalog the program gave
    Mode(@"ok");
    Generate(Config(@"codex-cli", nil, nil), prompt, &text, &error, &pieces);
    CHECK(error == nil && [text isEqualToString:@"Xin chào, đây là câu trả lời."]);
    NSDictionary* log = ReadLog();
    NSArray* args = log[@"args"];
    CHECK([log[@"name"] isEqualToString:@"codex"] && [ValueAfter(args, @"-m") isEqualToString:@"fake-mini"]);
    CHECK([ValueAfter(args, @"-c") isEqualToString:@"model_reasoning_effort=\"low\""] && [args.firstObject isEqualToString:@"exec"] && [args.lastObject isEqualToString:@"-"]);
    CHECK([log[@"stdin_head"] containsString:prompt] && [log[@"stdin_head"] containsString:@"Trả lời ngắn."] && ![JoinedArguments(args) containsString:prompt]);
    CHECK([log[@"no_color"] isEqualToString:@"1"] && [log[@"path"] hasPrefix:[[gWork stringByAppendingString:@"/bin"] stringByAppendingString:@":"]]);

    //what the user chose
    Generate(Config(@"codex-cli", @"fake-frontier", @"high"), prompt, &text, &error, NULL);
    log = ReadLog();
    CHECK(error == nil && [ValueAfter(log[@"args"], @"-m") isEqualToString:@"fake-frontier"] && [ValueAfter(log[@"args"], @"-c") isEqualToString:@"model_reasoning_effort=\"high\""]);
    Generate(Config(@"codex-cli", @"fake-frontier", AIAgentEffortProgramDefault), prompt, &text, &error, NULL);
    CHECK(error == nil && ![ReadLog()[@"args"] containsObject:@"-c"]);                  //the program's own level: nothing passed

    //Claude Code: the answer comes in pieces, what it thinks does not
    Mode(@"ok");
    Generate(Config(@"claude-cli", nil, nil), prompt, &text, &error, &pieces);
    CHECK(error == nil && [text isEqualToString:@"Xin chào, đây là câu trả lời."] && pieces == 3);
    log = ReadLog();
    args = log[@"args"];
    CHECK([log[@"name"] isEqualToString:@"claude"] && [ValueAfter(args, @"--model") isEqualToString:@"haiku"] && [ValueAfter(args, @"--effort") isEqualToString:@"low"]);
    CHECK([args containsObject:@"--safe-mode"] && [ValueAfter(args, @"--tools") isEqualToString:@""]);
    CHECK([log[@"stdin_head"] isEqualToString:prompt]);                                  //only the request on the input
    NSString* instruction = ValueAfter(args, @"--system-prompt");
    CHECK([instruction rangeOfString:@"Trả lời ngắn." options:NSLiteralSearch].location != NSNotFound);   //the instruction of the user, as written
    CHECK([instruction isEqualToString:[instruction precomposedStringWithCanonicalMapping]]);
    Generate(Config(@"claude-cli", @"opus", @"max"), prompt, &text, &error, NULL);
    log = ReadLog();
    CHECK([ValueAfter(log[@"args"], @"--model") isEqualToString:@"opus"] && [ValueAfter(log[@"args"], @"--effort") isEqualToString:@"max"]);
    Mode(@"claude-no-deltas");
    Generate(Config(@"claude-cli", nil, nil), prompt, &text, &error, NULL);
    CHECK(error == nil && [text isEqualToString:@"Cả khối."]);
    Mode(@"claude-result-only");
    Generate(Config(@"claude-cli", nil, nil), prompt, &text, &error, NULL);
    CHECK(error == nil && [text isEqualToString:@"Chỉ có kết quả."]);

    //Antigravity: the request is the last argument
    Mode(@"ok");
    Generate(Config(@"agy-cli", nil, nil), prompt, &text, &error, &pieces);
    CHECK(error == nil && [text isEqualToString:@"Xin chào, đây là câu trả lời."] && pieces >= 1);
    log = ReadLog();
    args = log[@"args"];
    CHECK([log[@"name"] isEqualToString:@"agy"] && [args[args.count - 2] isEqualToString:@"-p"] && [args.lastObject containsString:prompt] && [log[@"stdin_length"] intValue] == 0);
    //nothing chosen: the light model of the list the program gave, at its fast level, which is in its name
    CHECK([ValueAfter(args, @"--model") isEqualToString:@"gemini-3.8-flash-low"] && ![args containsObject:@"--effort"]);
    //Vietnamese in an argument arrives as it was written (precomposed). NSTask decomposes every argument ("à" becomes "a" and an
    //accent), which is why the programs are started with posix_spawn; containsString: would not see the difference, a literal search does
    CHECK([args.lastObject rangeOfString:prompt options:NSLiteralSearch].location != NSNotFound);
    CHECK([args.lastObject isEqualToString:[args.lastObject precomposedStringWithCanonicalMapping]]);

    Generate(Config(@"agy-cli", @"claude-sonnet-5-5", @"high"), prompt, &text, &error, NULL);
    log = ReadLog();
    CHECK(error == nil && [ValueAfter(log[@"args"], @"--model") isEqualToString:@"claude-sonnet-5-5-high"] && ![log[@"args"] containsObject:@"--effort"]);
    Generate(Config(@"agy-cli", @"plain-model", @"high"), prompt, &text, &error, NULL);
    log = ReadLog();
    CHECK(error == nil && [ValueAfter(log[@"args"], @"--model") isEqualToString:@"plain-model"] && [ValueAfter(log[@"args"], @"--effort") isEqualToString:@"high"]);

    //text with escapes, a letter cut in two
    Mode(@"ansi");
    Generate(Config(@"agy-cli", nil, nil), prompt, &text, &error, NULL);
    CHECK(error == nil && [text isEqualToString:@"Xin chào bạn\n"]);
    Mode(@"split-utf8");
    Generate(Config(@"codex-cli", nil, nil), prompt, &text, &error, &pieces);
    CHECK(error == nil && [text isEqualToString:@"Tiếng Việt: ế"] && pieces >= 2);

    //the errors of the programs
    for (NSString* providerId in @[@"codex-cli", @"claude-cli"]) {
        Mode(@"login");
        Generate(Config(providerId, nil, nil), prompt, &text, &error, NULL);
        CHECK(error.code == VOKAIErrorLogin && text.length == 0 && [error.localizedDescription containsString:[AIAgentCLI forProvider:Provider(providerId)].loginHint]);
        Mode(@"ratelimit");
        Generate(Config(providerId, nil, nil), prompt, &text, &error, NULL);
        CHECK(error.code == VOKAIErrorRateLimit);
        Mode(@"badmodel");
        Generate(Config(providerId, @"nope", nil), prompt, &text, &error, NULL);
        CHECK(error.code == VOKAIErrorModel);
    }
    Mode(@"badeffort");
    Generate(Config(@"codex-cli", @"fake-mini", @"medium"), prompt, &text, &error, NULL);
    CHECK(error.code == VOKAIErrorModel);
    Mode(@"secret");
    Generate(Config(@"codex-cli", nil, nil), prompt, &text, &error, NULL);
    CHECK(error != nil && ![error.localizedDescription containsString:@"sk-abcdefghijklmnop123456"] && ![error.localizedDescription containsString:@"abcdefgh12345678"]);
    Mode(@"empty");
    Generate(Config(@"codex-cli", nil, nil), prompt, &text, &error, NULL);
    CHECK(error.code == VOKAIErrorEmpty);
    Mode(@"crash");
    Generate(Config(@"agy-cli", nil, nil), prompt, &text, &error, NULL);
    CHECK(error.code == VOKAIErrorServer && [error.localizedDescription containsString:@"3"]);

    //a model name that could be a flag is refused before anything is run
    Mode(@"ok");
    [[NSFileManager defaultManager] removeItemAtPath:gLog error:nil];
    Generate(Config(@"codex-cli", @"--dangerously-bypass-approvals-and-sandbox", nil), prompt, &text, &error, NULL);
    CHECK(error.code == VOKAIErrorModel && ![[NSFileManager defaultManager] fileExistsAtPath:gLog]);

    //a program that is not there, or cannot run
    AIConfiguration* gone = Config(@"codex-cli", nil, nil);
    gone.executablePath = @"/nonexistent/codex";
    Generate(gone, prompt, &text, &error, NULL);
    CHECK(error.code == VOKAIErrorNoProgram);
    NSString* noRun = [gWork stringByAppendingString:@"/chosen/not-executable"];       //made by TestLocating
    gone.executablePath = noRun;
    Generate(gone, prompt, &text, &error, NULL);
    CHECK(error.code == VOKAIErrorNoProgram);
    NSString* badInterpreter = [gWork stringByAppendingString:@"/chosen/bad-interpreter"];
    [@"#!/nonexistent/interpreter\n" writeToFile:badInterpreter atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:badInterpreter error:nil];
    gone.executablePath = badInterpreter;
    Generate(gone, prompt, &text, &error, NULL);
    CHECK(error.code == VOKAIErrorNoProgram);
}

//what the folder of a request is like: private, empty, gone afterwards
static void TestWorkFolder(void) {
    printf("-- folder of a request\n");
    NSString* runs = [gWork stringByAppendingPathComponent:@"runs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:runs withIntermediateDirectories:YES attributes:nil error:nil];
    Mode(@"ok");
    __block BOOL done = NO;
    __block NSError* failure = nil;
    AIAgentRunner* runner = [[AIAgentRunner alloc] initWithConfiguration:Config(@"claude-cli", nil, nil)];
    runner.workRoot = runs;
    [runner generateWithPrompt:@"x" onText:^(NSString* p) {} completion:^(NSError* e) { failure = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 10);
    NSDictionary* log = ReadLog();
    CHECK(failure == nil && [log[@"cwd"] hasPrefix:RealPath(runs)]);
    CHECK([log[@"cwd_listing"] count] == 0 && [log[@"cwd_mode"] isEqualToString:@"0o700"]);          //empty, and only the user can enter
    SpinUntil(^BOOL { return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:runs error:nil].count == 0; }, 3);
    CHECK([[NSFileManager defaultManager] contentsOfDirectoryAtPath:runs error:nil].count == 0);   //removed when it ended

    //also when it failed
    Mode(@"crash");
    done = NO;
    runner = [[AIAgentRunner alloc] initWithConfiguration:Config(@"claude-cli", nil, nil)];
    runner.workRoot = runs;
    [runner generateWithPrompt:@"x" onText:^(NSString* p) {} completion:^(NSError* e) { failure = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 10);
    SpinUntil(^BOOL { return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:runs error:nil].count == 0; }, 3);
    CHECK(failure != nil && [[NSFileManager defaultManager] contentsOfDirectoryAtPath:runs error:nil].count == 0);
}

static void TestBigPrompt(void) {
    printf("-- a long request, a program that does not read it\n");
    NSMutableString* big = [NSMutableString string];
    while (big.length < 300000)
        [big appendString:@"Một đoạn văn dài, có tiếng Việt và ❤️. "];
    NSString* text = nil;
    NSError* error = nil;
    Mode(@"echo-length");
    Generate(Config(@"claude-cli", nil, nil), big, &text, &error, NULL);
    CHECK(error == nil && [text isEqualToString:[NSString stringWithFormat:@"got %lu bytes", (unsigned long)[big lengthOfBytesUsingEncoding:NSUTF8StringEncoding]]]);
    Generate(Config(@"codex-cli", nil, nil), big, &text, &error, NULL);
    CHECK(error == nil && [text hasPrefix:@"got "] && [[text substringFromIndex:4] intValue] > (int)[big lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);   //and the instruction
    NSDictionary* log = ReadLog();
    CHECK([log[@"stdin_length"] intValue] > 300000);
    //a program that ends without reading: writing to it must not kill this process (SIGPIPE)
    Mode(@"no-read");
    Generate(Config(@"codex-cli", nil, nil), big, &text, &error, NULL);
    CHECK(error != nil);                                                                 //we are still here
}

static void TestStopping(void) {
    printf("-- stopping, children, time\n");
    NSString* text = nil;
    NSError* error = nil;

    //stopping stops the program and the child it started
    Mode(@"slow");
    __block NSUInteger delivered = 0;
    __block BOOL completed = NO;
    AIClient* client = [[AIClient alloc] initWithConfiguration:Config(@"codex-cli", nil, nil)];
    [client generateWithPrompt:@"x" onText:^(NSString* p) { delivered++; } completion:^(NSError* e) { completed = YES; }];
    NSArray<NSNumber*>* pids = ReadPids();
    CHECK(pids.count == 2 && IsAlive(pids[0].intValue) && IsAlive(pids[1].intValue));
    Spin(0.3);
    NSUInteger before = delivered;
    [client cancel];
    CHECK(WaitUntilGone(pids, 6));
    KillAll(pids);
    Spin(0.5);
    CHECK(!completed && delivered == before);                                            //nothing is delivered after stopping

    //a child that holds the output open does not make the request wait
    Mode(@"lingering");
    NSDate* start = [NSDate date];
    Generate(Config(@"codex-cli", nil, nil), @"x", &text, &error, NULL);
    CHECK(error == nil && [text isEqualToString:@"xong rồi"] && [start timeIntervalSinceNow] > -5);
    pids = ReadPids();
    KillAll(pids);

    //too long: stopped, with the reason
    Mode(@"slow");
    start = [NSDate date];
    AIAgentRunner* runner = [[AIAgentRunner alloc] initWithConfiguration:Config(@"claude-cli", nil, nil)];
    runner.timeout = 1;
    __block NSError* failure = nil;
    __block BOOL done = NO;
    [runner generateWithPrompt:@"x" onText:^(NSString* p) {} completion:^(NSError* e) { failure = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 15);
    CHECK(failure.code == VOKAIErrorServer && [failure.localizedDescription containsString:@"không trả lời sau"] && [start timeIntervalSinceNow] > -8);
    pids = ReadPids();
    CHECK(WaitUntilGone(pids, 6));
    KillAll(pids);

    //more text than any answer: stopped
    Mode(@"flood");
    start = [NSDate date];
    Generate(Config(@"agy-cli", nil, nil), @"x", &text, &error, NULL);
    CHECK(error != nil && [error.localizedDescription containsString:@"quá nhiều"] && [start timeIntervalSinceNow] > -15);
    CHECK(text.length >= (2 << 20) && text.length < (6 << 20));

    //stopped right after it was started
    Mode(@"ok");
    completed = NO;
    client = [[AIClient alloc] initWithConfiguration:Config(@"claude-cli", nil, nil)];
    [client generateWithPrompt:@"x" onText:^(NSString* p) { delivered++; } completion:^(NSError* e) { completed = YES; }];
    [client cancel];
    Spin(1.0);
    CHECK(!completed);
}

#pragma mark - Pictures

static void TestImagePrompt(void) {
    printf("-- the request for a picture\n");
    NSString* template = [AIAgentCLI defaultImagePromptTemplate];
    CHECK([template containsString:@"$imagegen"] && [template containsString:@"{prompt}"]);                //the skill is named: without it the pictures are poor
    CHECK([[AIAgentCLI imagePromptForRequest:@"một con mèo" template:template] isEqualToString:@"Use $imagegen skill to create picture một con mèo, follow our design system."]);
    CHECK([[AIAgentCLI imagePromptForRequest:@"  một con mèo \n\n" template:template] isEqualToString:@"Use $imagegen skill to create picture một con mèo, follow our design system."]);
    CHECK([[AIAgentCLI imagePromptForRequest:@"a {prompt} b" template:@"X {prompt} Y {prompt}"] isEqualToString:@"X a {prompt} b Y a {prompt} b"]);   //what is asked is not read again as a template
    CHECK([[AIAgentCLI imagePromptForRequest:@"cat" template:@"Use $imagegen skill, picture:"] isEqualToString:@"Use $imagegen skill, picture: cat"]);   //no {prompt}: the request comes after
    CHECK([[AIAgentCLI imagePromptForRequest:@"cat" template:@"  "] isEqualToString:@"Use $imagegen skill to create picture cat, follow our design system."]);
    CHECK([[AIAgentCLI imagePromptForRequest:@"cat" template:nil] isEqualToString:@"Use $imagegen skill to create picture cat, follow our design system."]);
    CHECK([AIAgentCLI forProvider:Provider(@"codex-cli")].canMakeImages && ![AIAgentCLI forProvider:Provider(@"claude-cli")].canMakeImages && ![AIAgentCLI forProvider:Provider(@"agy-cli")].canMakeImages);

    AIAgentCLI* codex = [AIAgentCLI forProvider:Provider(@"codex-cli")];
    NSArray<NSString*>* a = [codex imageArgumentsWithModel:@"mini" effort:@"low" workDirectory:@"/tmp/work"];
    NSArray<NSString*>* text = [codex argumentsWithModel:@"mini" effort:@"low" systemPrompt:@"x" prompt:@"y" workDirectory:@"/tmp/work"];
    CHECK([a[0] isEqualToString:@"exec"] && [a[1] isEqualToString:@"--json"] && a.count == text.count + 1);         //the same run, with the events
    NSMutableArray* without = [a mutableCopy];
    [without removeObject:@"--json"];
    CHECK([without isEqualToArray:text]);
    CHECK([ValueAfter(a, @"-s") isEqualToString:@"read-only"] && [ValueAfter(a, @"--disable") isEqualToString:@"shell_tool"] && [a containsObject:@"--ephemeral"] && [a.lastObject isEqualToString:@"-"]);
    CHECK([[[NSString alloc] initWithData:[codex standardInputForImagePrompt:@"Use $imagegen skill: ế"] encoding:NSUTF8StringEncoding] isEqualToString:@"Use $imagegen skill: ế"]);   //as it is: no rule about texts in front

    CHECK([[AIAgentCLI codexHomeForEnvironment:@{@"CODEX_HOME": @"/x/codex"}] isEqualToString:@"/x/codex"]);
    CHECK([[AIAgentCLI codexHomeForEnvironment:@{}] isEqualToString:[NSHomeDirectory() stringByAppendingPathComponent:@".codex"]]);
    CHECK([[AIAgentCLI codexHomeForEnvironment:@{@"CODEX_HOME": @""}] hasSuffix:@"/.codex"]);

    //the settings
    [AISettings resetToDefaults];
    CHECK([AISettings.imagePrompt isEqualToString:[AISettings defaultImagePrompt]]);
    AISettings.imagePrompt = @"  Use $imagegen skill: {prompt}  ";
    CHECK([AISettings.imagePrompt isEqualToString:@"Use $imagegen skill: {prompt}"]);
    AISettings.imagePrompt = [AISettings defaultImagePrompt];
    CHECK([[NSUserDefaults standardUserDefaults] stringForKey:@"AIImagePrompt"] == nil);                      //the default is not kept as a choice
    AISettings.imagePrompt = @"x {prompt}";
    [AISettings resetToDefaults];
    CHECK([AISettings.imagePrompt isEqualToString:[AISettings defaultImagePrompt]]);
}

static void TestCodexEvents(void) {
    printf("-- the events of codex exec --json\n");
    NSData* stream = Lines(@[
        @{@"type": @"thread.started", @"thread_id": @"01a1539b-a6e8-7fa1-a860-f7cd426576ff"},
        @{@"type": @"turn.started"},
        @{@"type": @"item.completed", @"item": @{@"id": @"item_0", @"type": @"agent_message", @"text": @"Tôi dùng kỹ năng imagegen."}},
        @{@"type": @"item.started", @"item": @{@"id": @"item_1", @"type": @"command_execution", @"command": @"ls"}},
        @{@"type": @"item.completed", @"item": @{@"id": @"item_2", @"type": @"agent_message", @"text": @"Xong rồi ❤️"}},
        @{@"type": @"turn.completed", @"usage": @{@"input_tokens": @1}}]);
    for (NSUInteger chunk = 1; chunk <= 6; chunk += 5) {
        AIAgentOutputParser* parser = [[AIAgentOutputParser alloc] initWithFormat:AIAgentOutputCodexJSON];
        NSMutableString* all = [NSMutableString string];
        for (NSUInteger i = 0; i < stream.length; i += chunk)
            for (NSString* piece in [parser feed:[stream subdataWithRange:NSMakeRange(i, MIN(chunk, stream.length - i))]])
                [all appendString:piece];
        for (NSString* piece in [parser finish])
            [all appendString:piece];
        CHECK([all isEqualToString:@"Tôi dùng kỹ năng imagegen.\n\nXong rồi ❤️"]);                       //the messages of the agent, one after the other
        CHECK([parser.threadIdentifier isEqualToString:@"01a1539b-a6e8-7fa1-a860-f7cd426576ff"] && parser.errorMessage == nil);
    }
    AIAgentOutputParser* parser = [[AIAgentOutputParser alloc] initWithFormat:AIAgentOutputCodexJSON];
    CHECK(parser.threadIdentifier == nil);
    [parser feed:Lines(@[@{@"type": @"error", @"message": @"usage limit (429)"}, @{@"type": @"turn.failed", @"error": @{@"message": @"another"}}])];
    CHECK([parser.errorMessage isEqualToString:@"usage limit (429)"]);                                       //the first reason stays
    parser = [[AIAgentOutputParser alloc] initWithFormat:AIAgentOutputCodexJSON];
    [parser feed:Lines(@[@{@"type": @"turn.failed", @"error": @{@"message": @"model not found"}}])];
    CHECK([parser.errorMessage isEqualToString:@"model not found"]);
    //values of another kind than expected are nothing, not a crash
    parser = [[AIAgentOutputParser alloc] initWithFormat:AIAgentOutputCodexJSON];
    [parser feed:Lines(@[@{@"type": @5}, @{@"type": @"thread.started", @"thread_id": @7}, @{@"type": @"item.completed", @"item": @"x"},
                          @{@"type": @"item.completed", @"item": @{@"type": @"agent_message", @"text": @3}}, @{@"type": @"turn.failed", @"error": @"x"}])];
    [parser finish];
    CHECK(parser.threadIdentifier == nil);
}

static void MakeFile(NSString* path, NSTimeInterval age) {
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    [@"x" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:-age]} ofItemAtPath:path error:nil];
}

static void TestFindingPictures(void) {
    printf("-- finding the picture of a run\n");
    NSString* home = [gWork stringByAppendingPathComponent:@"codexhome"];
    NSString* generated = [home stringByAppendingPathComponent:@"generated_images"];
    NSDate* started = [NSDate dateWithTimeIntervalSinceNow:-10];
    MakeFile([generated stringByAppendingString:@"/thread-a/old.png"], 100);
    MakeFile([generated stringByAppendingString:@"/thread-a/new.png"], 5);
    MakeFile([generated stringByAppendingString:@"/thread-a/notes.txt"], 1);                                  //not a picture
    MakeFile([generated stringByAppendingString:@"/thread-b/other.jpg"], 3);
    //by its thread: the newest picture of it, whenever it was made
    CHECK([[AIAgentCLI generatedImageForThread:@"thread-a" codexHome:home since:started].lastPathComponent isEqualToString:@"new.png"]);
    CHECK([[AIAgentCLI generatedImageForThread:@"thread-a" codexHome:home since:nil].lastPathComponent isEqualToString:@"new.png"]);
    //a thread that has no folder: the newest picture made since the run started, in any folder
    CHECK([[AIAgentCLI generatedImageForThread:@"nothing" codexHome:home since:started].lastPathComponent isEqualToString:@"other.jpg"]);
    CHECK([[AIAgentCLI generatedImageForThread:nil codexHome:home since:started].lastPathComponent isEqualToString:@"other.jpg"]);
    CHECK([AIAgentCLI generatedImageForThread:@"nothing" codexHome:home since:[NSDate dateWithTimeIntervalSinceNow:1]] == nil);  //nothing was made since
    CHECK([AIAgentCLI generatedImageForThread:@"nothing" codexHome:home since:nil] == nil);                    //without a time there is no guessing
    CHECK([AIAgentCLI generatedImageForThread:@"thread-a" codexHome:[gWork stringByAppendingString:@"/none"] since:started] == nil);
    //a thread name comes out of a program: it cannot lead out of the folder
    MakeFile([home stringByAppendingString:@"/evil/secret.png"], 1);
    for (NSString* bad in @[@"../evil", @"/etc", @"thread-a/../../evil", @"a b", [@"" stringByPaddingToLength:200 withString:@"x" startingAtIndex:0]])
        CHECK([AIAgentCLI generatedImageForThread:bad codexHome:home since:nil] == nil);
    NSURL* viaFallback = [AIAgentCLI generatedImageForThread:@"../evil" codexHome:home since:started];
    CHECK(![viaFallback.path containsString:@"/evil/"]);                                                       //the fallback looks only in generated_images
}

static void TestImageRuns(void) {
    printf("-- real runs for a picture against the fake program\n");
    NSString* home = [gWork stringByAppendingPathComponent:@"codexhome2"];
    setenv("CODEX_HOME", home.UTF8String, 1);
    NSString* prompt = @"Use $imagegen skill to create picture con mèo màu cam, follow our design system.";

    __block NSURL* image = nil;
    __block NSError* error = nil;
    __block BOOL done = NO;
    __block NSMutableString* notes = nil;
    void (^make)(AIConfiguration*) = ^(AIConfiguration* c) {
        image = nil; error = nil; done = NO; notes = [NSMutableString string];
        AIClient* client = [[AIClient alloc] initWithConfiguration:c];
        [client generateImageWithPrompt:prompt onNote:^(NSString* note) { [notes appendString:note]; }
                             completion:^(NSURL* url, NSError* e) { image = url; error = e; done = YES; }];
        SpinUntil(^BOOL { return done; }, 30);
    };

    Mode(@"image");
    make(Config(@"codex-cli", nil, nil));
    CHECK(error == nil && image != nil && [image.pathExtension isEqualToString:@"png"] && [[NSFileManager defaultManager] fileExistsAtPath:image.path]);
    CHECK([image.path hasPrefix:[home stringByAppendingString:@"/generated_images/"]]);                        //where Codex keeps it
    CHECK([[[NSImage alloc] initWithContentsOfURL:image] isValid] && [[NSImage alloc] initWithContentsOfURL:image].size.width == 16);
    CHECK([notes containsString:@"imagegen skill"] && [notes containsString:@"Generated the picture."]);       //what the agent said on the way
    NSDictionary* log = ReadLog();
    NSArray* args = log[@"args"];
    CHECK([args[1] isEqualToString:@"--json"] && [ValueAfter(args, @"-m") isEqualToString:@"fake-mini"] && [ValueAfter(args, @"-c") isEqualToString:@"model_reasoning_effort=\"low\""]);
    CHECK([log[@"stdin_head"] isEqualToString:prompt]);                                                         //exactly the request: no rule of texts in front of it
    CHECK(![JoinedArguments(args) containsString:@"imagegen"]);                                                //and not in the arguments

    //the level and the model that were chosen are the ones used ("it is using the current reasoning level")
    make(Config(@"codex-cli", @"fake-frontier", @"high"));
    log = ReadLog();
    CHECK(error == nil && [ValueAfter(log[@"args"], @"-m") isEqualToString:@"fake-frontier"] && [ValueAfter(log[@"args"], @"-c") isEqualToString:@"model_reasoning_effort=\"high\""]);

    //the picture is in another folder than the thread's: the newest one since the start
    Mode(@"image-elsewhere");
    make(Config(@"codex-cli", nil, nil));
    CHECK(error == nil && image != nil && [[NSFileManager defaultManager] fileExistsAtPath:image.path]);
    //a thread name that is a way out of the folder: it is not followed, the picture is found the other way
    Mode(@"image-evil");
    make(Config(@"codex-cli", nil, nil));
    CHECK(error == nil && image != nil && [image.path containsString:@"/generated_images/somewhere/"]);

    //nothing came: what the agent said is told
    Mode(@"image-none");
    make(Config(@"codex-cli", nil, nil));
    CHECK(image == nil && error.code == VOKAIErrorEmpty && [error.localizedDescription containsString:@"không tạo ra ảnh"] &&
          [error.localizedDescription containsString:@"I cannot make pictures"]);
    //an error of the program
    Mode(@"image-error");
    make(Config(@"codex-cli", nil, nil));
    CHECK(image == nil && error.code == VOKAIErrorRateLimit);
    Mode(@"login");
    make(Config(@"codex-cli", nil, nil));
    CHECK(image == nil && error.code == VOKAIErrorLogin);
    //the others do not make pictures; nothing is run for them
    Mode(@"image");
    [[NSFileManager defaultManager] removeItemAtPath:gLog error:nil];
    for (NSString* providerId in @[@"claude-cli", @"agy-cli"]) {
        make(Config(providerId, nil, nil));
        CHECK(image == nil && error != nil && [error.localizedDescription containsString:@"không tạo được ảnh"]);
    }
    CHECK(![[NSFileManager defaultManager] fileExistsAtPath:gLog]);
    AIConfiguration* ollama = Config(@"codex-cli", nil, nil);
    ollama.provider = Provider(@"ollama");
    make(ollama);
    CHECK(image == nil && error != nil);

    //stopped while it works: nothing is delivered, the program and its children are gone
    Mode(@"image-delayed");
    __block BOOL delivered = NO;
    AIClient* client = [[AIClient alloc] initWithConfiguration:Config(@"codex-cli", nil, nil)];
    [client generateImageWithPrompt:prompt onNote:^(NSString* n) { delivered = YES; } completion:^(NSURL* url, NSError* e) { delivered = YES; }];
    Spin(1.0);
    [client cancel];
    Spin(4.5);
    CHECK(!delivered);
    unsetenv("CODEX_HOME");
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 2) {
            printf("usage: ai_agent_test <fake_agent_cli.py> [catalog of the real codex]\n");
            return 2;
        }
        gFake = [NSString stringWithUTF8String:argv[1]];
        gWork = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"ai_agent_test-" stringByAppendingString:[NSUUID UUID].UUIDString]];
        NSString* bin = [gWork stringByAppendingPathComponent:@"bin"];
        [[NSFileManager defaultManager] createDirectoryAtPath:bin withIntermediateDirectories:YES attributes:nil error:nil];
        gWork = RealPath(gWork);                    //after it exists: realpath needs the folder
        bin = [gWork stringByAppendingPathComponent:@"bin"];
        for (NSString* command in @[@"codex", @"claude", @"agy"])
            [[NSFileManager defaultManager] createSymbolicLinkAtPath:[bin stringByAppendingPathComponent:command] withDestinationPath:gFake error:nil];
        gLog = [gWork stringByAppendingPathComponent:@"log.json"];
        gPids = [gWork stringByAppendingPathComponent:@"pids.txt"];
        setenv("FAKE_AGENT_LOG", gLog.UTF8String, 1);
        setenv("FAKE_AGENT_PIDS", gPids.UTF8String, 1);

        TestProviders();
        TestEffortNames();
        TestCatalog(argc > 2 && strlen(argv[2]) > 0 ? argv[2] : NULL);
        TestAntigravityList();
        TestChoosing();
        TestArguments();
        TestOutputParsers();
        TestErrors();
        TestLocating();
        TestSettings();
        TestProcess();
        TestRuns();                 //before the lists of models: the first request of Codex asks for its catalog by itself
        TestModelLists();
        TestWorkFolder();
        TestBigPrompt();
        TestStopping();
        TestImagePrompt();
        TestCodexEvents();
        TestFindingPictures();
        TestImageRuns();
        [[NSFileManager defaultManager] removeItemAtPath:gWork error:nil];
        printf(failures ? "\n%d FAILURES\n" : "ALL OK\n", failures);
    }
    return failures ? 1 : 0;
}
