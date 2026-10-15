// Tests of AILocalSetup, the whole installation from a Mac that has nothing: Ollama (a stand-in zip from mock_ollama_server.py),
// its server (fake_ollama.py), a model, a question to it, the settings of the assistant. Run with run-ai-local-test.sh.
//
//   ai_local_setup_test <fixtures folder> <mock port> <free port> <fake_ollama.py> <work folder>
//
// The settings go to the preferences of this test program, which are deleted at the end. Nothing real is downloaded or started.
#import <Foundation/Foundation.h>
#import <signal.h>
#import "AILocalSetup.h"
#import "AISettings.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSString *gFixtures, *gMockBase, *gPort, *gFake, *gWork, *gBase;
static int gCounter = 0;
static NSMutableArray<AIOllamaRuntime*>* gRuntimes;             //every server this test may have started, stopped at the end

static BOOL SpinUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return done();
}

static void MockControl(NSDictionary* values) {
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[gMockBase stringByAppendingString:@"/_control"]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:values options:0 error:nil];
    __block BOOL finished = NO;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* d, NSURLResponse* r, NSError* e) { finished = YES; }] resume];
    SpinUntil(^BOOL { return finished; }, 10);
}

static BOOL Answers(void) {
    __block BOOL done = NO, ok = NO;
    AIOllama* api = [[AIOllama alloc] initWithBaseURL:[NSURL URLWithString:gBase]];
    [api versionWithTimeout:1 completion:^(NSString* v, NSError* e) { ok = v != nil; done = YES; }];
    SpinUntil(^BOOL { return done; }, 5);
    return ok;
}

static void StopServer(AIOllamaRuntime* runtime) {
    [runtime stopWaiting:5];
    SpinUntil(^BOOL { return !Answers(); }, 8);
}

@interface FakeVerifier : AIOllamaVerifier
@property (nonatomic) BOOL passes;
@end
@implementation FakeVerifier
-(instancetype)init { self = [super initWithTeamIdentifier:@"ABCDE12345" bundleIdentifier:@"x.y"]; _passes = YES; return self; }
-(BOOL)verifyApplication:(NSURL*)app minimumOS:(NSOperatingSystemVersion*)minimumOS error:(NSError**)error {
    if (!self.passes) { if (error) *error = [NSError errorWithDomain:VOKAILocalErrorDomain code:VOKAILocalErrorUnsafeDownload userInfo:@{NSLocalizedDescriptionKey: @"fake refusal"}]; return NO; }
    if (minimumOS) *minimumOS = (NSOperatingSystemVersion){0, 0, 0};
    return YES;
}
-(BOOL)verifySignatureOfApplication:(NSURL*)app error:(NSError**)error { return YES; }
@end

@interface Rig : NSObject
@property (nonatomic, strong) AILocalSetup* setup;
@property (nonatomic, strong) AIOllamaRuntime* runtime;
@property (nonatomic, strong) NSURL* installDir;
@property (nonatomic, strong) NSURL* workDir;
@property (nonatomic, strong) NSMutableArray<NSString*>* log;        //"step:state" each time a step changes state
@property (nonatomic, strong) NSMutableArray<NSString*>* details;    //every detail text of every step
@property (nonatomic) int changes;
@end
@implementation Rig
@end

static AILocalModel* Tiny(NSString* tag) { return [AILocalModel customModelWithTag:tag bytes:1000]; }

/// Everything new: an empty folder for the applications, a server that is not running, the settings emptied.
static Rig* NewRig(AIOllamaVerifier* verifier) {
    Rig* rig = [[Rig alloc] init];
    gCounter++;
    rig.installDir = [NSURL fileURLWithPath:[gWork stringByAppendingPathComponent:[NSString stringWithFormat:@"apps-%d", gCounter]] isDirectory:YES];
    rig.workDir = [NSURL fileURLWithPath:[gWork stringByAppendingPathComponent:[NSString stringWithFormat:@"tmp-%d", gCounter]] isDirectory:YES];
    NSString* program = [rig.installDir.path stringByAppendingPathComponent:@"Ollama.app/Contents/Resources/ollama"];
    rig.runtime = [[AIOllamaRuntime alloc] initWithBaseURL:[NSURL URLWithString:gBase] searchPaths:@[program]];
    rig.runtime.startTimeout = 20;
    [gRuntimes addObject:rig.runtime];
    AIOllamaInstaller* installer = [[AIOllamaInstaller alloc] initWithReleaseURL:[NSURL URLWithString:[gMockBase stringByAppendingString:@"/repos/ollama/ollama/releases/latest"]]
        fallbackURL:nil installDirectory:rig.installDir workDirectory:rig.workDir verifier:verifier ?: [[FakeVerifier alloc] init]];
    rig.setup = [[AILocalSetup alloc] initWithInstaller:installer runtime:rig.runtime];
    rig.log = [NSMutableArray array];
    rig.details = [NSMutableArray array];
    __weak Rig* weak = rig;
    NSMutableArray<NSNumber*>* last = [NSMutableArray array];
    for (int i = 0; i < AILocalStepCount; i++) [last addObject:@(AILocalStepPending)];
    rig.setup.onChange = ^{
        Rig* r = weak;
        r.changes++;
        for (int i = 0; i < AILocalStepCount; i++) {
            AILocalStepState state = [r.setup stateOfStep:(AILocalStep)i];
            if (state != [last[i] integerValue]) {
                last[i] = @(state);
                [r.log addObject:[NSString stringWithFormat:@"%d:%d", i, (int)state]];
            }
            NSString* detail = [r.setup detailOfStep:(AILocalStep)i];
            if (detail.length) [r.details addObject:detail];
        }
    };
    return rig;
}

static void RunToEnd(Rig* rig, AILocalModel* model, NSTimeInterval timeout) {
    [rig.setup installModel:model];
    SpinUntil(^BOOL { return !rig.setup.running; }, timeout);
}

static NSString* Mark(AILocalStep step, AILocalStepState state) { return [NSString stringWithFormat:@"%d:%d", (int)step, (int)state]; }

static BOOL Happened(Rig* rig, AILocalStep step, AILocalStepState state) { return [rig.log containsObject:Mark(step, state)]; }

static BOOL DetailContains(Rig* rig, NSString* text) {
    for (NSString* d in rig.details) if ([d containsString:text]) return YES;
    return NO;
}

static NSArray<NSString*>* ServerModels(void) {
    __block NSArray* names = nil; __block BOOL done = NO;
    AIOllama* api = [[AIOllama alloc] initWithBaseURL:[NSURL URLWithString:gBase]];
    [api installedModelsWithCompletion:^(NSArray* models, NSError* e) { names = [models valueForKey:@"name"]; done = YES; }];
    SpinUntil(^BOOL { return done; }, 5);
    return names ?: @[];
}

static void ResetSettings(void) {
    [AISettings resetToDefaults];
}

#pragma mark - The tests

static void TestFullInstallation(void) {
    setenv("FAKE_OLLAMA_MODE", "normal", 1);
    setenv("FAKE_OLLAMA_DELAY", "0.5", 1);
    ResetSettings();
    MockControl(@{@"zip_path": [gFixtures stringByAppendingPathComponent:@"fakeollama.zip"], @"zip_mode": @"good", @"digest_mode": @"good", @"size_mode": @"good", @"no_asset": @NO});
    Rig* rig = NewRig(nil);
    __block int notifications = 0;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:VOKAILocalSetupDidFinishNotification object:rig.setup queue:nil usingBlock:^(NSNotification* n) { notifications++; }];
    CHECK(!rig.runtime.isInstalled && !Answers());

    RunToEnd(rig, Tiny(@"tiny:1b"), 120);
    CHECK(!rig.setup.running && rig.setup.succeeded && rig.setup.error == nil);
    for (int i = 0; i < AILocalStepCount; i++)
        CHECK([rig.setup stateOfStep:(AILocalStep)i] == AILocalStepDone && [rig.setup fractionOfStep:(AILocalStep)i] == 1);
    //the steps went one after the other: each started after the one before ended
    NSArray* expected = @[Mark(AILocalStepRuntime, AILocalStepRunning), Mark(AILocalStepRuntime, AILocalStepDone), Mark(AILocalStepStart, AILocalStepRunning),
                          Mark(AILocalStepStart, AILocalStepDone), Mark(AILocalStepModel, AILocalStepRunning), Mark(AILocalStepModel, AILocalStepDone),
                          Mark(AILocalStepTest, AILocalStepRunning), Mark(AILocalStepTest, AILocalStepDone), Mark(AILocalStepApply, AILocalStepRunning), Mark(AILocalStepApply, AILocalStepDone)];
    CHECK([rig.log isEqualToArray:expected]);
    CHECK(rig.runtime.isInstalled && rig.runtime.isManaged && Answers());
    CHECK([ServerModels() containsObject:@"tiny:1b"]);
    CHECK([[rig.setup detailOfStep:AILocalStepTest] containsString:@"Model trả lời sau"]);
    CHECK(DetailContains(rig, @"Đang tải Ollama") || DetailContains(rig, @"Đang kiểm tra: mã SHA-256"));
    CHECK(DetailContains(rig, @"Đã tải xong"));
    //the assistant now uses it
    CHECK([AISettings.providerIdentifier isEqualToString:@"ollama"]);
    AIProvider* ollama = [AIProvider providerWithIdentifier:@"ollama"];
    CHECK([[AISettings modelForProvider:ollama] isEqualToString:@"tiny:1b"]);
    CHECK([[AISettings baseURLForProvider:ollama] isEqualToString:[gBase stringByAppendingString:@"/v1"]]);
    CHECK([AISettings isProviderReady:ollama]);
    CHECK(notifications == 1);
    CHECK([[NSFileManager defaultManager] contentsOfDirectoryAtPath:rig.workDir.path error:nil].count == 0);
    CHECK([[rig.setup.model tag] isEqualToString:@"tiny:1b"]);

    //again, with everything there: nothing is downloaded, nothing started
    [rig.log removeAllObjects];
    RunToEnd(rig, Tiny(@"tiny:1b"), 60);
    CHECK(rig.setup.succeeded);
    CHECK(Happened(rig, AILocalStepRuntime, AILocalStepSkipped) && Happened(rig, AILocalStepStart, AILocalStepSkipped) && Happened(rig, AILocalStepModel, AILocalStepSkipped));
    CHECK(!Happened(rig, AILocalStepRuntime, AILocalStepDone) && !Happened(rig, AILocalStepModel, AILocalStepDone));
    CHECK(notifications == 2);

    //Ollama is installed but its server is not running: it is started, the rest is skipped
    StopServer(rig.runtime);
    [rig.log removeAllObjects];
    RunToEnd(rig, Tiny(@"tiny:1b"), 60);
    CHECK(rig.setup.succeeded && Happened(rig, AILocalStepRuntime, AILocalStepSkipped) && Happened(rig, AILocalStepStart, AILocalStepDone) && Happened(rig, AILocalStepModel, AILocalStepSkipped));
    CHECK(rig.runtime.isManaged);

    //another model on the same server: only the model is downloaded
    [rig.log removeAllObjects];
    RunToEnd(rig, Tiny(@"other:2b"), 60);
    CHECK(rig.setup.succeeded && Happened(rig, AILocalStepModel, AILocalStepDone) && Happened(rig, AILocalStepStart, AILocalStepSkipped));
    CHECK([[AISettings modelForProvider:ollama] isEqualToString:@"other:2b"]);
    NSArray* models = ServerModels();
    CHECK([models containsObject:@"tiny:1b"] && [models containsObject:@"other:2b"]);

    //starting again while it runs does nothing
    __block NSUInteger changesAfter = 0;
    [rig.setup installModel:Tiny(@"third:1b")];
    NSUInteger before = rig.changes;
    [rig.setup installModel:Tiny(@"fourth:1b")];
    CHECK(rig.changes == before && [rig.setup.model.tag isEqualToString:@"third:1b"]);
    SpinUntil(^BOOL { return !rig.setup.running; }, 60);
    changesAfter = rig.changes;
    CHECK(rig.setup.succeeded && ![ServerModels() containsObject:@"fourth:1b"] && changesAfter > before);

    //removing a model
    __block NSError* removeError = nil; __block BOOL removed = NO;
    [rig.setup removeModel:Tiny(@"third:1b") completion:^(NSError* e) { removeError = e; removed = YES; }];
    SpinUntil(^BOOL { return removed; }, 30);
    CHECK(removed && removeError == nil && ![ServerModels() containsObject:@"third:1b"]);
    removed = NO;
    [rig.setup removeModel:Tiny(@"third:1b") completion:^(NSError* e) { removeError = e; removed = YES; }];
    SpinUntil(^BOOL { return removed; }, 30);
    CHECK(removeError.code == VOKAILocalErrorNotFound);
    //removed while the server is stopped: it is started for that
    StopServer(rig.runtime);
    removed = NO; removeError = nil;
    [rig.setup removeModel:Tiny(@"other:2b") completion:^(NSError* e) { removeError = e; removed = YES; }];
    SpinUntil(^BOOL { return removed; }, 30);
    CHECK(removed && removeError == nil && ![ServerModels() containsObject:@"other:2b"]);
    StopServer(rig.runtime);
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

static void TestFailures(void) {
    ResetSettings();
    MockControl(@{@"zip_path": [gFixtures stringByAppendingPathComponent:@"fakeollama.zip"], @"zip_mode": @"good"});
    setenv("FAKE_OLLAMA_MODE", "normal", 1);
    setenv("FAKE_OLLAMA_DELAY", "0", 1);

    //the download of Ollama is refused by the checks: nothing else is attempted
    FakeVerifier* refusing = [[FakeVerifier alloc] init];
    refusing.passes = NO;
    Rig* rig = NewRig(refusing);
    RunToEnd(rig, Tiny(@"tiny:1b"), 60);
    CHECK(!rig.setup.running && !rig.setup.succeeded && rig.setup.failedStep == AILocalStepRuntime && !rig.setup.wasCancelled);
    CHECK([rig.setup.error.localizedDescription isEqualToString:@"fake refusal"] && [[rig.setup detailOfStep:AILocalStepRuntime] isEqualToString:@"fake refusal"]);
    CHECK([rig.setup stateOfStep:AILocalStepRuntime] == AILocalStepFailed && [rig.setup stateOfStep:AILocalStepStart] == AILocalStepPending && [rig.setup stateOfStep:AILocalStepModel] == AILocalStepPending);
    CHECK(!rig.runtime.isInstalled && !Answers() && [AISettings.providerIdentifier isEqualToString:AIProvider.defaultProvider.identifier]);
    //and it can be tried again once the cause is gone
    refusing.passes = YES;
    RunToEnd(rig, Tiny(@"tiny:1b"), 60);
    CHECK(rig.setup.succeeded && rig.setup.error == nil);
    StopServer(rig.runtime);

    //the server will not start
    rig = NewRig(nil);
    setenv("FAKE_OLLAMA_MODE", "die", 1);
    RunToEnd(rig, Tiny(@"tiny:1b"), 60);
    CHECK(rig.setup.failedStep == AILocalStepStart && [rig.setup.error.localizedDescription containsString:@"dừng ngay khi khởi động"]);
    CHECK([rig.setup stateOfStep:AILocalStepRuntime] == AILocalStepDone && [rig.setup stateOfStep:AILocalStepModel] == AILocalStepPending);
    setenv("FAKE_OLLAMA_MODE", "normal", 1);

    //the model does not exist
    rig = NewRig(nil);
    ResetSettings();
    RunToEnd(rig, Tiny(@"missing:1b"), 60);
    CHECK(rig.setup.failedStep == AILocalStepModel && rig.setup.error.code == VOKAILocalErrorNotFound && [rig.setup.error.localizedDescription containsString:@"Không tìm thấy"]);
    CHECK([rig.setup stateOfStep:AILocalStepTest] == AILocalStepPending && [AISettings.providerIdentifier isEqualToString:AIProvider.defaultProvider.identifier]);

    //downloaded, but the model says nothing, or the server fails when asked: reported, and the assistant is not switched to it
    ResetSettings();
    RunToEnd(rig, Tiny(@"silent:1b"), 60);
    CHECK(rig.setup.failedStep == AILocalStepTest && [rig.setup.error.localizedDescription containsString:@"chạy thử không được"] && [rig.setup.error.localizedDescription containsString:@"không trả về nội dung"]);
    CHECK([rig.setup stateOfStep:AILocalStepModel] == AILocalStepDone && [rig.setup stateOfStep:AILocalStepApply] == AILocalStepPending);
    CHECK([ServerModels() containsObject:@"silent:1b"] && [AISettings.providerIdentifier isEqualToString:AIProvider.defaultProvider.identifier]);
    RunToEnd(rig, Tiny(@"crash:1b"), 60);
    CHECK(rig.setup.failedStep == AILocalStepTest && [rig.setup.error.localizedDescription containsString:@"chạy thử không được"]);
    CHECK([AISettings.providerIdentifier isEqualToString:AIProvider.defaultProvider.identifier]);
    StopServer(rig.runtime);
}

static void TestCancel(void) {
    ResetSettings();
    setenv("FAKE_OLLAMA_MODE", "normal", 1);
    setenv("FAKE_OLLAMA_DELAY", "0", 1);
    MockControl(@{@"zip_path": [gFixtures stringByAppendingPathComponent:@"fakeollama.zip"], @"zip_mode": @"good"});

    //during the download of a model
    Rig* rig = NewRig(nil);
    [rig.setup installModel:[AILocalModel customModelWithTag:@"slow:1b" bytes:3000]];
    SpinUntil(^BOOL { return DetailContains(rig, @"Đang tải model") && DetailContains(rig, @"%"); }, 60);
    SpinUntil(^BOOL { return DetailContains(rig, @"/giây"); }, 10);
    CHECK(DetailContains(rig, @"/giây") && DetailContains(rig, @"còn khoảng"));         //speed and time left, after a few seconds
    CHECK(rig.setup.running && [rig.setup stateOfStep:AILocalStepModel] == AILocalStepRunning);
    double fraction = [rig.setup fractionOfStep:AILocalStepModel];
    CHECK(fraction > 0 && fraction < 1);
    [rig.setup cancel];
    CHECK(!rig.setup.running && rig.setup.wasCancelled && rig.setup.failedStep == AILocalStepModel && !rig.setup.succeeded);
    CHECK([rig.setup.error.localizedDescription containsString:@"Đã dừng"] && [rig.setup stateOfStep:AILocalStepModel] == AILocalStepFailed);
    NSUInteger changes = rig.changes;
    SpinUntil(^BOOL { return NO; }, 1.0);
    CHECK(rig.changes == changes);                                                      //nothing more is reported after the cancellation
    CHECK(![ServerModels() containsObject:@"slow:1b"] && [AISettings.providerIdentifier isEqualToString:AIProvider.defaultProvider.identifier]);
    [rig.setup cancel];                                                                  //cancelling again does nothing
    CHECK(rig.changes == changes);
    //a new run after a cancellation works, and the old one does not disturb it
    RunToEnd(rig, Tiny(@"tiny:1b"), 60);
    CHECK(rig.setup.succeeded && rig.setup.error == nil && !rig.setup.wasCancelled);
    StopServer(rig.runtime);

    //during the download of Ollama
    MockControl(@{@"zip_path": [gFixtures stringByAppendingPathComponent:@"bigollama.zip"], @"zip_mode": @"slow"});
    rig = NewRig(nil);
    [rig.setup installModel:Tiny(@"tiny:1b")];
    SpinUntil(^BOOL { return DetailContains(rig, @"Đang tải Ollama"); }, 30);
    CHECK(rig.setup.running);
    [rig.setup cancel];
    CHECK(rig.setup.wasCancelled && rig.setup.failedStep == AILocalStepRuntime);
    SpinUntil(^BOOL { return NO; }, 1.0);
    CHECK([[NSFileManager defaultManager] contentsOfDirectoryAtPath:rig.workDir.path error:nil].count == 0 && !rig.runtime.isInstalled);
    MockControl(@{@"zip_path": [gFixtures stringByAppendingPathComponent:@"fakeollama.zip"], @"zip_mode": @"good"});

    //while the server starts
    setenv("FAKE_OLLAMA_DELAY", "3", 1);
    rig = NewRig(nil);
    [rig.setup installModel:Tiny(@"tiny:1b")];
    SpinUntil(^BOOL { return [rig.setup stateOfStep:AILocalStepStart] == AILocalStepRunning; }, 30);
    [rig.setup cancel];
    CHECK(rig.setup.wasCancelled && rig.setup.failedStep == AILocalStepStart);
    SpinUntil(^BOOL { return Answers(); }, 15);                                          //the server finishes starting, harmlessly
    setenv("FAKE_OLLAMA_DELAY", "0", 1);
    RunToEnd(rig, Tiny(@"tiny:1b"), 60);                                                //and the next run uses it
    CHECK(rig.setup.succeeded && [rig.setup stateOfStep:AILocalStepRuntime] == AILocalStepSkipped);
    StopServer(rig.runtime);
}

static void TestDisk(void) {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSString* dir = [gWork stringByAppendingPathComponent:@"models"];
    for (NSString* path in @[@"manifests/registry.ollama.ai/library/gemma3/4b", @"manifests/registry.ollama.ai/library/qwen2.5/7b",
                             @"manifests/registry.ollama.ai/someone/tiny/1b", @"manifests/registry.ollama.ai/library/llama3.2/latest",
                             @"manifests/hf.co/org/model/Q4", @"manifests/registry.ollama.ai/library/emptydir/x/y"]) {
        NSString* full = [dir stringByAppendingPathComponent:path];
        [fm createDirectoryAtPath:[full stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        if (![path hasSuffix:@"x/y"])
            [@"{}" writeToFile:full atomically:YES encoding:NSUTF8StringEncoding error:nil];
        else
            [fm createDirectoryAtPath:full withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"blobs"] withIntermediateDirectories:YES attributes:nil error:nil];
    [@"x" writeToFile:[dir stringByAppendingPathComponent:@"blobs/sha256-1"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSSet* expected = [NSSet setWithArray:@[@"gemma3:4b", @"qwen2.5:7b", @"someone/tiny:1b", @"llama3.2:latest"]];
    CHECK([[AILocalSetup installedTagsInModelsDirectory:[NSURL fileURLWithPath:dir]] isEqualToSet:expected]);
    CHECK([AILocalSetup installedTagsInModelsDirectory:[NSURL fileURLWithPath:[gWork stringByAppendingPathComponent:@"nothing-here"]]].count == 0);
    CHECK([AILocalSetup installedTagsInModelsDirectory:[NSURL fileURLWithPath:@"/"]].count == 0);

    unsetenv("OLLAMA_MODELS");
    CHECK([[AILocalSetup defaultModelsDirectory].path isEqualToString:[NSHomeDirectory() stringByAppendingPathComponent:@".ollama/models"]]);
    setenv("OLLAMA_MODELS", "/Volumes/Big/models", 1);
    CHECK([[AILocalSetup defaultModelsDirectory].path isEqualToString:@"/Volumes/Big/models"]);
    setenv("OLLAMA_MODELS", "relative/dir", 1);                                         //only a full path is believed
    CHECK([[AILocalSetup defaultModelsDirectory].path isEqualToString:[NSHomeDirectory() stringByAppendingPathComponent:@".ollama/models"]]);
    unsetenv("OLLAMA_MODELS");

    CHECK([[AILocalSetup titleOfStep:AILocalStepRuntime] containsString:@"Ollama"] && [[AILocalSetup titleOfStep:AILocalStepModel] length] > 0);
    for (int i = 0; i < AILocalStepCount; i++) CHECK([[AILocalSetup titleOfStep:(AILocalStep)i] length] > 0);
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 6) { printf("usage: ai_local_setup_test <fixtures> <mock port> <free port> <fake_ollama.py> <work>\n"); return 2; }
        gFixtures = @(argv[1]);
        gMockBase = [NSString stringWithFormat:@"http://127.0.0.1:%s", argv[2]];
        gPort = @(argv[3]);
        gBase = [NSString stringWithFormat:@"http://127.0.0.1:%s", argv[3]];
        gFake = @(argv[4]);
        gWork = @(argv[5]);
        setenv("FAKE_OLLAMA_LOG", [gWork stringByAppendingPathComponent:@"setup-starts.log"].UTF8String, 1);
        setenv("FAKE_OLLAMA_MODELS", [gWork stringByAppendingPathComponent:@"setup-models.json"].UTF8String, 1);
        gRuntimes = [NSMutableArray array];
        [AISettings registerDefaults];
        TestDisk();
        TestFullInstallation();
        TestFailures();
        TestCancel();
        for (AIOllamaRuntime* runtime in gRuntimes)
            [runtime stopWaiting:5];
        [AISettings resetToDefaults];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[NSProcessInfo processInfo].processName];
        printf(failures == 0 ? "ai_local_setup_test: all passed\n" : "ai_local_setup_test: %d FAILED\n", failures);
        return failures == 0 ? 0 : 1;
    }
}
