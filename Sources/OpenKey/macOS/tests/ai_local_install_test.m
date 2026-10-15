// Tests of the installation of Ollama (AIOllamaInstaller, AIOllamaVerifier) against the fake server mock_ollama_server.py, which
// plays GitHub: the description of the release and the zip. Run with run-ai-local-test.sh, which makes the fixtures:
//
//   ai_local_install_test <port> <dead port> <fixtures folder>
//
// The folder has fake.zip (an application signed only ad hoc, as an attacker would make it), extra.zip, wrongname.zip,
// notzip.zip, and, when the official download is available (VOK_OLLAMA_ZIP), real.zip and tampered.zip (the same with one file
// changed). Without real.zip the tests that need it are skipped and say so. Nothing is installed outside a temporary folder.
#import <Foundation/Foundation.h>
#import "AIOllama.h"
#import "AIOllamaInstaller.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSString* gBase;
static NSString* gDeadBase;
static NSString* gFixtures;
static NSString* gRoot;
static int gScenario = 0;

static BOOL SpinUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return done();
}

static NSMutableDictionary* ServerState(void) {
    __block NSMutableDictionary* result = nil;
    __block BOOL finished = NO;
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:[gBase stringByAppendingString:@"/_state"]]
                                 completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
        result = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
        finished = YES;
    }] resume];
    SpinUntil(^BOOL { return finished; }, 5);
    return result;
}

static void Control(NSDictionary* values) {
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[gBase stringByAppendingString:@"/_control"]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:values options:0 error:nil];
    __block BOOL finished = NO;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* d, NSURLResponse* r, NSError* e) { finished = YES; }] resume];
    SpinUntil(^BOOL { return finished; }, 10);
}

static void Serve(NSString* zipName) {
    Control(@{@"zip_path": [gFixtures stringByAppendingPathComponent:zipName], @"zip_mode": @"good", @"digest_mode": @"good", @"size_mode": @"good",
              @"no_asset": @NO, @"evil_url": @NO});
}

/// A verifier that says what the test wants, to test the installer without signatures.
@interface FakeVerifier : AIOllamaVerifier
@property (nonatomic) BOOL passes;
@property (nonatomic) NSOperatingSystemVersion minimum;
@property (nonatomic) int calls;
@end
@implementation FakeVerifier
-(instancetype)init { self = [super initWithTeamIdentifier:@"ABCDE12345" bundleIdentifier:@"x.y"]; _passes = YES; return self; }
-(BOOL)verifyApplication:(NSURL*)app minimumOS:(NSOperatingSystemVersion*)minimumOS error:(NSError**)error {
    self.calls++;
    if (!self.passes) { if (error) *error = [NSError errorWithDomain:VOKAILocalErrorDomain code:VOKAILocalErrorUnsafeDownload userInfo:@{NSLocalizedDescriptionKey: @"fake refusal"}]; return NO; }
    if (minimumOS) *minimumOS = self.minimum;
    return YES;
}
-(BOOL)verifySignatureOfApplication:(NSURL*)app error:(NSError**)error { return YES; }
@end

typedef struct { NSURL* app; NSError* error; int completions; } Outcome;

@interface Run : NSObject
@property (nonatomic, strong) AIOllamaInstaller* installer;
@property (nonatomic, strong) NSURL* installDir;
@property (nonatomic, strong) NSURL* workDir;
@property (nonatomic, strong) NSMutableArray<NSArray*>* progress;       //@[phase, fraction, done, total]
@property (nonatomic, strong) NSURL* app;
@property (nonatomic, strong) NSError* error;
@property (nonatomic) int completions;
@property (nonatomic) BOOL done;
@end
@implementation Run
@end

static Run* Setup(AIOllamaVerifier* verifier, NSString* releaseBase, NSString* fallbackPath) {
    Run* run = [[Run alloc] init];
    gScenario++;
    run.installDir = [NSURL fileURLWithPath:[gRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"install-%d", gScenario]] isDirectory:YES];
    run.workDir = [NSURL fileURLWithPath:[gRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"work-%d", gScenario]] isDirectory:YES];
    NSURL* release = [NSURL URLWithString:[(releaseBase ?: gBase) stringByAppendingString:@"/repos/ollama/ollama/releases/latest"]];
    NSURL* fallback = fallbackPath ? [NSURL URLWithString:[gBase stringByAppendingString:fallbackPath]] : nil;
    run.installer = [[AIOllamaInstaller alloc] initWithReleaseURL:release fallbackURL:fallback installDirectory:run.installDir
                                                    workDirectory:run.workDir verifier:verifier];
    run.progress = [NSMutableArray array];
    return run;
}

static void Start(Run* run) {
    [run.installer installWithProgress:^(AIInstallPhase phase, double fraction, uint64_t done, uint64_t total) {
        [run.progress addObject:@[@(phase), @(fraction), @(done), @(total)]];
    } completion:^(NSURL* app, NSError* error) {
        run.app = app; run.error = error; run.completions++; run.done = YES;
    }];
}

static Run* Install(AIOllamaVerifier* verifier, NSTimeInterval timeout) {
    Run* run = Setup(verifier, nil, nil);
    Start(run);
    SpinUntil(^BOOL { return run.done; }, timeout);
    return run;
}

static BOOL WorkIsClean(Run* run) {
    return [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:run.workDir.path error:nil] count] == 0;
}

static NSArray<NSString*>* Items(NSURL* dir) {
    return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir.path error:nil] ?: @[];
}

static BOOL ProgressIsSound(Run* run) {
    //the phases come in order, and the download only goes forward
    NSInteger phase = -1; double fraction = -1;
    for (NSArray* p in run.progress) {
        if ([p[0] integerValue] < phase) return NO;
        if ([p[0] integerValue] == AIInstallPhaseDownloading) {
            if ([p[1] doubleValue] < fraction - 1e-9 || [p[1] doubleValue] > 1.0) return NO;
            fraction = [p[1] doubleValue];
        }
        phase = [p[0] integerValue];
    }
    return YES;
}

#pragma mark - With a verifier that says what the test wants

static void TestInstallerLogic(void) {
    //the normal way: everything goes through, in order, and nothing is left behind
    Serve(@"fake.zip");
    FakeVerifier* verifier = [[FakeVerifier alloc] init];
    Run* run = Install(verifier, 60);
    CHECK(run.done && run.error == nil && run.completions == 1);
    CHECK([run.app.lastPathComponent isEqualToString:@"Ollama.app"] && [[run.app.URLByDeletingLastPathComponent.path stringByResolvingSymlinksInPath] isEqualToString:[run.installDir.path stringByResolvingSymlinksInPath]]);
    CHECK([[NSFileManager defaultManager] fileExistsAtPath:[run.app.path stringByAppendingPathComponent:@"Contents/Info.plist"]]);
    CHECK(WorkIsClean(run) && verifier.calls == 1);
    CHECK(run.progress.count >= 3 && ProgressIsSound(run));
    CHECK([run.progress.firstObject[0] integerValue] == AIInstallPhaseLooking && [run.progress.lastObject[0] integerValue] == AIInstallPhaseInstalling);
    BOOL sawDownload = NO, sawVerify = NO;
    for (NSArray* p in run.progress) { sawDownload |= [p[0] integerValue] == AIInstallPhaseDownloading; sawVerify |= [p[0] integerValue] == AIInstallPhaseVerifying; }
    CHECK(sawVerify);
    (void)sawDownload;
    NSDictionary* state = ServerState();
    CHECK([state[@"zip_downloads"] integerValue] >= 1);
    CHECK([[[NSFileManager defaultManager] attributesOfItemAtPath:run.workDir.path error:nil][NSFilePosixPermissions] integerValue] != 0);

    //an application that is already there is replaced; the old one leaves nothing behind
    run = Setup(verifier, nil, nil);
    NSURL* old = [run.installDir URLByAppendingPathComponent:@"Ollama.app" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:old withIntermediateDirectories:YES attributes:nil error:nil];
    [@"old" writeToURL:[old URLByAppendingPathComponent:@"marker.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Start(run);
    SpinUntil(^BOOL { return run.done; }, 60);
    CHECK(run.error == nil && ![[NSFileManager defaultManager] fileExistsAtPath:[old.path stringByAppendingPathComponent:@"marker.txt"]]);
    CHECK([Items(run.installDir) isEqualToArray:@[@"Ollama.app"]]);

    //refused by the verifier: nothing installed, and the old application is still there, untouched
    FakeVerifier* refusing = [[FakeVerifier alloc] init];
    refusing.passes = NO;
    run = Setup(refusing, nil, nil);
    old = [run.installDir URLByAppendingPathComponent:@"Ollama.app" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:old withIntermediateDirectories:YES attributes:nil error:nil];
    [@"old" writeToURL:[old URLByAppendingPathComponent:@"marker.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Start(run);
    SpinUntil(^BOOL { return run.done; }, 60);
    CHECK(run.error.code == VOKAILocalErrorUnsafeDownload && [run.error.localizedDescription isEqualToString:@"fake refusal"] && run.app == nil);
    CHECK([[NSFileManager defaultManager] fileExistsAtPath:[old.path stringByAppendingPathComponent:@"marker.txt"]]);
    CHECK([Items(run.installDir) isEqualToArray:@[@"Ollama.app"]] && WorkIsClean(run));
    //nothing installed when there was nothing before
    run = Install(refusing, 60);
    CHECK(run.error != nil && ![[NSFileManager defaultManager] fileExistsAtPath:run.installDir.path] || Items(run.installDir).count == 0);

    //the application asks for a macOS that is newer than this one
    FakeVerifier* newer = [[FakeVerifier alloc] init];
    newer.minimum = (NSOperatingSystemVersion){99, 1, 0};
    run = Install(newer, 60);
    CHECK(run.error.code == VOKAILocalErrorUnsupported && [run.error.localizedDescription containsString:@"macOS 99.1"] && run.app == nil && WorkIsClean(run));
    CHECK(Items(run.installDir).count == 0);
    newer.minimum = (NSOperatingSystemVersion){10, 15, 0};
    CHECK(Install(newer, 60).error == nil);
    newer.minimum = (NSOperatingSystemVersion){0, 0, 0};
    CHECK(Install(newer, 60).error == nil);

    //the zip is not what Ollama's is
    for (NSArray* pair in @[@[@"extra.zip", @"không đúng cấu trúc"], @[@"wrongname.zip", @"không đúng cấu trúc"], @[@"notzip.zip", @"không giải nén"]]) {
        Serve(pair[0]);
        run = Install(verifier, 60);
        CHECK(run.error.code == VOKAILocalErrorUnsafeDownload && [run.error.localizedDescription containsString:pair[1]] && run.app == nil);
        CHECK(WorkIsClean(run) && Items(run.installDir).count == 0);
    }
    Serve(@"fake.zip");
}

static void TestDownloadChecks(void) {
    FakeVerifier* verifier = [[FakeVerifier alloc] init];
    Serve(@"fake.zip");
    Run* run;
    struct { NSString* key; NSString* value; NSString* mustSay; VOKAILocalErrorCode code; } cases[] = {
        {@"digest_mode", @"wrong", @"SHA-256", VOKAILocalErrorUnsafeDownload},
        {@"digest_mode", @"malformed", @"SHA-256", VOKAILocalErrorUnsafeDownload},
        {@"size_mode", @"wrong", @"dung lượng", VOKAILocalErrorUnsafeDownload},
        {@"zip_mode", @"corrupt", @"SHA-256", VOKAILocalErrorUnsafeDownload},
        {@"zip_mode", @"short", @"dung lượng", VOKAILocalErrorUnsafeDownload},
        {@"zip_mode", @"status500", @"500", VOKAILocalErrorFailed},
        {@"zip_mode", @"redirect-http", @"gián đoạn", VOKAILocalErrorFailed},
        {@"zip_mode", @"claims-huge", @"lớn bất thường", VOKAILocalErrorUnsafeDownload},
        {@"evil_url", @"yes", @"không an toàn", VOKAILocalErrorUnsafeDownload},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        Serve(@"fake.zip");
        Control(@{cases[i].key: [cases[i].value isEqualToString:@"yes"] ? (id)@YES : (id)cases[i].value});
        run = Install(verifier, 60);
        if (!(run.error.code == cases[i].code && [run.error.localizedDescription containsString:cases[i].mustSay])) {
            printf("  case %s=%s gave: %s\n", [cases[i].key UTF8String], [cases[i].value UTF8String], [run.error.description UTF8String] ?: "(no error)");
        }
        CHECK(run.done && run.error.code == cases[i].code && [run.error.localizedDescription containsString:cases[i].mustSay]);
        CHECK(run.app == nil && verifier.calls >= 0 && WorkIsClean(run) && Items(run.installDir).count == 0);
    }
    Serve(@"fake.zip");

    //no digest published: the size is still checked, the signature is still asked for
    int calls = verifier.calls;
    Control(@{@"digest_mode": @"missing"});
    run = Install(verifier, 60);
    CHECK(run.error == nil && verifier.calls == calls + 1);
    Control(@{@"digest_mode": @"missing", @"size_mode": @"wrong"});
    CHECK(Install(verifier, 60).error.code == VOKAILocalErrorUnsafeDownload);
    Serve(@"fake.zip");

    //a redirect to this Mac is followed
    Control(@{@"zip_mode": @"redirect-local"});
    int before = [ServerState()[@"zip_downloads"] intValue];
    run = Install(verifier, 60);
    CHECK(run.error == nil && [ServerState()[@"zip_downloads"] intValue] == before + 2);
    Serve(@"fake.zip");

    //the description of the release is not available
    run = Setup(verifier, gDeadBase, nil);                          //nothing listens, and no other address
    Start(run); SpinUntil(^BOOL { return run.done; }, 30);
    CHECK(run.error.code == VOKAILocalErrorFailed && [run.error.localizedDescription containsString:@"GitHub"] && WorkIsClean(run));
    run = Setup(verifier, gDeadBase, @"/files/Ollama-darwin.zip");  //then the file itself, without size or hash
    Start(run); SpinUntil(^BOOL { return run.done; }, 60);
    CHECK(run.error == nil && run.app != nil);
    Control(@{@"no_asset": @YES});                                  //the description does not list the file
    run = Setup(verifier, nil, nil);
    Start(run); SpinUntil(^BOOL { return run.done; }, 30);
    CHECK(run.error.code == VOKAILocalErrorFailed && run.app == nil);
    run = Setup(verifier, nil, @"/files/Ollama-darwin.zip");
    Start(run); SpinUntil(^BOOL { return run.done; }, 60);
    CHECK(run.error == nil);
    Serve(@"fake.zip");
    //an address that cannot be trusted is not even asked
    AIOllamaInstaller* plain = [[AIOllamaInstaller alloc] initWithReleaseURL:[NSURL URLWithString:@"http://example.com/release"] fallbackURL:nil
        installDirectory:[NSURL fileURLWithPath:gRoot] workDirectory:[NSURL fileURLWithPath:gRoot] verifier:verifier];
    __block NSError* plainError = nil; __block BOOL plainDone = NO;
    [plain installWithProgress:nil completion:^(NSURL* a, NSError* e) { plainError = e; plainDone = YES; }];
    SpinUntil(^BOOL { return plainDone; }, 10);
    CHECK(plainError != nil && [plainError.localizedDescription containsString:@"không hợp lệ"]);
    CHECK([[AIOllamaInstaller alloc] initWithReleaseURL:nil fallbackURL:nil installDirectory:[NSURL fileURLWithPath:gRoot] workDirectory:[NSURL fileURLWithPath:gRoot] verifier:verifier] == nil);
}

static void TestCancelAndReuse(void) {
    FakeVerifier* verifier = [[FakeVerifier alloc] init];
    Serve(@"big.zip");                                              //4 MB, sent slowly
    Control(@{@"zip_mode": @"slow"});
    NSUInteger aborted = [ServerState()[@"aborted"] unsignedIntegerValue];
    Run* run = Setup(verifier, nil, nil);
    Start(run);
    SpinUntil(^BOOL { return [run.progress count] >= 3 || run.done; }, 30);
    CHECK(!run.done);
    //a second start while it runs is refused without disturbing the first
    __block NSError* second = nil; __block BOOL secondDone = NO;
    [run.installer installWithProgress:nil completion:^(NSURL* a, NSError* e) { second = e; secondDone = YES; }];
    SpinUntil(^BOOL { return secondDone; }, 5);
    CHECK(secondDone && second != nil && !run.done);
    [run.installer cancel];
    SpinUntil(^BOOL { return run.done; }, 10);
    SpinUntil(^BOOL { return NO; }, 0.3);
    CHECK(run.done && run.error.code == VOKAILocalErrorCancelled && run.completions == 1 && run.app == nil);
    CHECK(WorkIsClean(run) && Items(run.installDir).count == 0);
    SpinUntil(^BOOL { return [ServerState()[@"aborted"] unsignedIntegerValue] > aborted; }, 5);
    CHECK([ServerState()[@"aborted"] unsignedIntegerValue] > aborted);
    NSUInteger reports = run.progress.count;
    SpinUntil(^BOOL { return NO; }, 0.5);
    CHECK(run.progress.count == reports);
    //the same installer can be used again
    Control(@{@"zip_mode": @"good"});
    Start(run);
    SpinUntil(^BOOL { return run.completions == 2; }, 60);
    CHECK(run.error == nil && run.app != nil);
    //cancelled before it began
    Control(@{@"zip_mode": @"slow"});
    Run* early = Setup(verifier, nil, nil);
    Start(early);
    [early.installer cancel];
    SpinUntil(^BOOL { return early.done; }, 10);
    CHECK(early.error.code == VOKAILocalErrorCancelled && WorkIsClean(early));
    Serve(@"fake.zip");

    //leftovers of a run that was interrupted are removed, and only those
    NSURL* work = [NSURL fileURLWithPath:[gRoot stringByAppendingPathComponent:@"leftovers"] isDirectory:YES];
    NSFileManager* fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:[work URLByAppendingPathComponent:@"ollama-install-1234/extracted"] withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtURL:[work URLByAppendingPathComponent:@"ollama-install-5678"] withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtURL:[work URLByAppendingPathComponent:@"snippets"] withIntermediateDirectories:YES attributes:nil error:nil];
    [@"x" writeToURL:[work URLByAppendingPathComponent:@"settings.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [AIOllamaInstaller removeLeftoversInWorkDirectory:work];
    CHECK([[Items(work) sortedArrayUsingSelector:@selector(compare:)] isEqualToArray:(@[@"settings.json", @"snippets"])]);
    [AIOllamaInstaller removeLeftoversInWorkDirectory:[NSURL fileURLWithPath:@"/nonexistent/dir"]];
}

#pragma mark - The real signature checks

static NSURL* Extract(NSString* zipName, NSString* into) {
    NSString* dir = [gRoot stringByAppendingPathComponent:into];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
    task.arguments = @[@"-x", @"-k", [gFixtures stringByAppendingPathComponent:zipName], dir];
    [task launchAndReturnError:nil];
    [task waitUntilExit];
    return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"Ollama.app"] isDirectory:YES];
}

static void TestVerifier(BOOL haveReal) {
    CHECK([[AIOllamaVerifier alloc] initWithTeamIdentifier:@"" bundleIdentifier:@"a.b"] == nil);
    CHECK([[AIOllamaVerifier alloc] initWithTeamIdentifier:@"ABC" bundleIdentifier:@""] == nil);
    CHECK([[AIOllamaVerifier alloc] initWithTeamIdentifier:@"AB\"C" bundleIdentifier:@"a.b"] == nil);           //would change the requirement
    CHECK([[AIOllamaVerifier alloc] initWithTeamIdentifier:@"ABC" bundleIdentifier:@"a.b\" or anchor apple or identifier \""] == nil);
    CHECK([[AIOllamaVerifier alloc] initWithTeamIdentifier:@"ABC DEF" bundleIdentifier:@"a.b"] == nil);
    CHECK([[AIOllamaVerifier alloc] initWithTeamIdentifier:@"ABC" bundleIdentifier:@"a.b"] != nil);
    AIOllamaVerifier* standard = [AIOllamaVerifier standard];
    CHECK([standard.teamIdentifier isEqualToString:@"3MU9H2V9Y9"] && [standard.bundleIdentifier isEqualToString:@"com.electron.ollama"] && standard.requiresNotarization);

    //an application signed only ad hoc, whatever it is called, is not Ollama; the system says the same
    NSURL* fake = Extract(@"fake.zip", @"verify-fake");
    NSError* error = nil; NSOperatingSystemVersion minimum;
    CHECK(![standard verifyApplication:fake minimumOS:&minimum error:&error] && error.code == VOKAILocalErrorUnsafeDownload);
    CHECK(error.localizedDescription.length > 0);
    AIOllamaVerifier* lax = [AIOllamaVerifier standard];
    lax.requiresNotarization = NO;
    error = nil;
    CHECK(![lax verifyApplication:fake minimumOS:&minimum error:&error] && error != nil);       //the signature is checked even so
    CHECK(![standard verifySignatureOfApplication:fake error:&error]);
    CHECK(![standard verifyApplication:[NSURL fileURLWithPath:@"/nonexistent/Ollama.app"] minimumOS:&minimum error:&error]);
    NSTask* spctl = [[NSTask alloc] init];                                  //the system itself does not accept it either
    spctl.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/spctl"];
    spctl.arguments = @[@"--assess", @"--type", @"execute", fake.path];
    spctl.standardError = [NSFileHandle fileHandleWithNullDevice];
    [spctl launchAndReturnError:nil];
    [spctl waitUntilExit];
    CHECK(spctl.terminationStatus != 0);

    if (!haveReal) { printf("SKIPPED: the checks on the official download (VOK_OLLAMA_ZIP is not set)\n"); return; }

    NSURL* real = Extract(@"real.zip", @"verify-real");
    error = nil;
    CHECK([standard verifyApplication:real minimumOS:&minimum error:&error] && error == nil);
    CHECK(minimum.majorVersion >= 11 && minimum.majorVersion <= 30);       //it says which macOS it needs (14 at the time of writing)
    CHECK([standard verifySignatureOfApplication:real error:&error]);
    AIOllamaVerifier* otherTeam = [[AIOllamaVerifier alloc] initWithTeamIdentifier:@"AAAAAAAAAA" bundleIdentifier:@"com.electron.ollama"];
    CHECK(![otherTeam verifySignatureOfApplication:real error:&error] && error.code == VOKAILocalErrorUnsafeDownload);
    AIOllamaVerifier* otherId = [[AIOllamaVerifier alloc] initWithTeamIdentifier:@"3MU9H2V9Y9" bundleIdentifier:@"com.example.other"];
    CHECK(![otherId verifyApplication:real minimumOS:&minimum error:&error]);
    NSURL* tampered = Extract(@"tampered.zip", @"verify-tampered");
    error = nil;
    CHECK(![standard verifyApplication:tampered minimumOS:&minimum error:&error] && error.code == VOKAILocalErrorUnsafeDownload);
    //the server inside the application is the one that was signed
    NSString* server = [real.path stringByAppendingPathComponent:@"Contents/Resources/ollama"];
    CHECK([[NSFileManager defaultManager] isExecutableFileAtPath:server]);
}

static void TestRealInstall(void) {
    Serve(@"real.zip");
    Run* run = Install([AIOllamaVerifier standard], 180);
    CHECK(run.done && run.error == nil && run.app != nil);
    CHECK(WorkIsClean(run) && [Items(run.installDir) isEqualToArray:@[@"Ollama.app"]]);
    CHECK(run.progress.count > 5 && ProgressIsSound(run));
    uint64_t lastDone = 0, lastTotal = 0;
    for (NSArray* p in run.progress) if ([p[0] integerValue] == AIInstallPhaseDownloading) { lastDone = [p[2] unsignedLongLongValue]; lastTotal = [p[3] unsignedLongLongValue]; }
    CHECK(lastTotal > 100000000 && lastDone == lastTotal);              //the whole file was reported
    //the program installed runs
    NSTask* task = [[NSTask alloc] init];
    task.executableURL = [run.app URLByAppendingPathComponent:@"Contents/Resources/ollama"];
    task.arguments = @[@"--version"];
    NSPipe* pipe = [NSPipe pipe];
    task.standardOutput = pipe; task.standardError = pipe;
    NSError* launch = nil;
    CHECK([task launchAndReturnError:&launch]);
    [task waitUntilExit];
    NSString* out = [[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    CHECK(task.terminationStatus == 0 && [out containsString:@"version"]);
    //and a second installation over it works
    Run* again = Setup([AIOllamaVerifier standard], nil, nil);
    again.installDir = run.installDir;
    again.installer = [[AIOllamaInstaller alloc] initWithReleaseURL:[NSURL URLWithString:[gBase stringByAppendingString:@"/repos/ollama/ollama/releases/latest"]] fallbackURL:nil
                                                   installDirectory:run.installDir workDirectory:again.workDir verifier:[AIOllamaVerifier standard]];
    Start(again);
    SpinUntil(^BOOL { return again.done; }, 180);
    CHECK(again.error == nil && [Items(run.installDir) isEqualToArray:@[@"Ollama.app"]]);

    //a download that was changed on the way is refused by the signature (the hash is the one of the changed file, as an attacker
    //who controls the server would publish it)
    Serve(@"tampered.zip");
    run = Install([AIOllamaVerifier standard], 180);
    CHECK(run.error.code == VOKAILocalErrorUnsafeDownload && run.app == nil && Items(run.installDir).count == 0 && WorkIsClean(run));
    //and an application that only looks like Ollama
    Serve(@"fake.zip");
    run = Install([AIOllamaVerifier standard], 60);
    CHECK(run.error.code == VOKAILocalErrorUnsafeDownload && [run.error.localizedDescription containsString:@"không phải bản chính thức"] && run.app == nil && Items(run.installDir).count == 0);
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 4) { printf("usage: ai_local_install_test <port> <dead port> <fixtures>\n"); return 2; }
        gBase = [NSString stringWithFormat:@"http://127.0.0.1:%s", argv[1]];
        gDeadBase = [NSString stringWithFormat:@"http://127.0.0.1:%s", argv[2]];
        gFixtures = @(argv[3]);
        gRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"vok-install-test-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
        [[NSFileManager defaultManager] createDirectoryAtPath:gRoot withIntermediateDirectories:YES attributes:nil error:nil];
        BOOL haveReal = [[NSFileManager defaultManager] fileExistsAtPath:[gFixtures stringByAppendingPathComponent:@"real.zip"]];
        TestInstallerLogic();
        TestDownloadChecks();
        TestCancelAndReuse();
        TestVerifier(haveReal);
        if (haveReal) TestRealInstall();
        [[NSFileManager defaultManager] removeItemAtPath:gRoot error:nil];
        printf(failures == 0 ? "ai_local_install_test: all passed\n" : "ai_local_install_test: %d FAILED\n", failures);
        return failures == 0 ? 0 : 1;
    }
}
