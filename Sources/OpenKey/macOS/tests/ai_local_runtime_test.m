// Tests of AIOllamaRuntime: finding Ollama, starting its server as a child process, using one that already runs, stopping it. The
// server is a stand-in (fake_ollama.py), so nothing of the real Ollama runs. Run with run-ai-local-test.sh.
//
//   ai_local_runtime_test <fake_ollama.py> <free port> <port of mock_ollama_server> <folder>
#import <Foundation/Foundation.h>
#import <signal.h>
#import <sys/stat.h>
#import "AIOllama.h"
#import "AIOllamaRuntime.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSString* gFake;
static NSString* gPort;
static NSString* gMockBase;
static NSString* gFolder;
static NSString* gLog;

static BOOL SpinUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return done();
}

static NSArray<NSDictionary*>* Starts(void) {
    NSMutableArray* starts = [NSMutableArray array];
    NSString* text = [NSString stringWithContentsOfFile:gLog encoding:NSUTF8StringEncoding error:nil] ?: @"";
    for (NSString* line in [text componentsSeparatedByString:@"\n"]) {
        id object = line.length ? [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
        if (object) [starts addObject:object];
    }
    return starts;
}

static BOOL Answers(NSString* base) {
    __block BOOL done = NO, ok = NO;
    AIOllama* api = [[AIOllama alloc] initWithBaseURL:[NSURL URLWithString:base]];
    [api versionWithTimeout:1 completion:^(NSString* v, NSError* e) { ok = v != nil; done = YES; }];
    SpinUntil(^BOOL { return done; }, 5);
    return ok;
}

static BOOL ProcessExists(pid_t pid) { return kill(pid, 0) == 0; }

static AIOllamaRuntime* Runtime(NSArray<NSString*>* paths) {
    return [[AIOllamaRuntime alloc] initWithBaseURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%@", gPort]] searchPaths:paths];
}

static NSError* Ensure(AIOllamaRuntime* runtime, NSTimeInterval timeout, BOOL* finished) {
    __block NSError* error = nil; __block BOOL done = NO;
    [runtime ensureRunning:^(NSError* e) { error = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, timeout);
    if (finished) *finished = done;
    return error;
}

static void Mode(NSString* mode, NSString* delay) {
    setenv("FAKE_OLLAMA_MODE", mode.UTF8String, 1);
    setenv("FAKE_OLLAMA_DELAY", delay.UTF8String, 1);
}

static void TestFinding(void) {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSString* dir = [gFolder stringByAppendingPathComponent:@"finding"];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString* first = [dir stringByAppendingPathComponent:@"first"], *second = [dir stringByAppendingPathComponent:@"second"], *notExecutable = [dir stringByAppendingPathComponent:@"plain"];
    NSString* folder = [dir stringByAppendingPathComponent:@"folder"];
    [fm copyItemAtPath:gFake toPath:first error:nil];
    [fm copyItemAtPath:gFake toPath:second error:nil];
    [@"text" writeToFile:notExecutable atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    CHECK(!Runtime(@[]).isInstalled && Runtime(@[]).serverProgram == nil);
    CHECK(!Runtime(@[[dir stringByAppendingPathComponent:@"missing"]]).isInstalled);
    CHECK(!Runtime(@[notExecutable]).isInstalled);                  //not a program
    CHECK(!Runtime(@[folder]).isInstalled);                         //a folder is not a program even if it can be "executed"
    CHECK([Runtime(@[notExecutable, folder, second, first]).serverProgram.path isEqualToString:second]);    //the first that is a program
    //what remains of an Ollama that was uninstalled: /usr/local/bin/ollama pointing to an application that is gone
    NSString* broken = [dir stringByAppendingPathComponent:@"broken-link"], *good = [dir stringByAppendingPathComponent:@"good-link"];
    [fm createSymbolicLinkAtPath:broken withDestinationPath:[dir stringByAppendingPathComponent:@"Ollama.app/Contents/Resources/ollama"] error:nil];
    [fm createSymbolicLinkAtPath:good withDestinationPath:first error:nil];
    CHECK(!Runtime(@[broken]).isInstalled);
    CHECK([Runtime(@[broken, good]).serverProgram.path isEqualToString:good]);
    CHECK(Runtime(@[first]).isInstalled);
    NSArray* defaults = [AIOllamaRuntime defaultSearchPaths];
    CHECK(defaults.count == 4 && [defaults[0] isEqualToString:[NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Ollama.app/Contents/Resources/ollama"]]);
    CHECK([defaults[1] isEqualToString:@"/Applications/Ollama.app/Contents/Resources/ollama"]);
    //found again each time: installed after the object was made
    NSString* later = [dir stringByAppendingPathComponent:@"later"];
    AIOllamaRuntime* runtime = Runtime(@[later]);
    CHECK(!runtime.isInstalled);
    [fm copyItemAtPath:gFake toPath:later error:nil];
    CHECK(runtime.isInstalled);
    //only this Mac
    CHECK([[AIOllamaRuntime alloc] initWithBaseURL:[NSURL URLWithString:@"http://192.168.1.2:11434"] searchPaths:@[]] == nil);
}

static void TestNotInstalledAndAlreadyRunning(void) {
    BOOL finished = NO;
    NSError* error = Ensure(Runtime(@[]), 10, &finished);
    CHECK(finished && error.code == VOKAILocalErrorNotInstalled && [error.localizedDescription containsString:@"Chưa cài Ollama"]);

    //an Ollama that already runs is used as it is: nothing is started and nothing will be stopped
    AIOllamaRuntime* user = [[AIOllamaRuntime alloc] initWithBaseURL:[NSURL URLWithString:gMockBase] searchPaths:@[gFake]];
    NSUInteger starts = Starts().count;
    error = Ensure(user, 10, &finished);
    CHECK(finished && error == nil && !user.isManaged && Starts().count == starts);
    [user stopWaiting:1];
    CHECK(Answers(gMockBase));                                       //still there

    //the port answers, but not as Ollama
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[gMockBase stringByAppendingString:@"/_control"]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [@"{\"version_html\": true}" dataUsingEncoding:NSUTF8StringEncoding];
    __block BOOL sent = NO;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* d, NSURLResponse* r, NSError* e) { sent = YES; }] resume];
    SpinUntil(^BOOL { return sent; }, 5);
    error = Ensure(user, 10, &finished);
    CHECK(finished && error != nil && [error.localizedDescription containsString:@"khác dùng"] && Starts().count == starts && !user.isManaged);
    request.HTTPBody = [@"{\"version_html\": false}" dataUsingEncoding:NSUTF8StringEncoding];
    sent = NO;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* d, NSURLResponse* r, NSError* e) { sent = YES; }] resume];
    SpinUntil(^BOOL { return sent; }, 5);
}

static void TestStartAndStop(void) {
    setenv("FAKE_OLLAMA_LOG", gLog.UTF8String, 1);
    unsetenv("OLLAMA_KEEP_ALIVE");
    Mode(@"normal", @"1.5");
    AIOllamaRuntime* runtime = Runtime(@[gFake]);
    NSString* base = [NSString stringWithFormat:@"http://127.0.0.1:%@", gPort];
    CHECK(!Answers(base));
    NSUInteger before = Starts().count;

    //it takes a while to answer; two calls meanwhile share one start
    __block NSError* e1 = nil, *e2 = nil; __block int calls = 0;
    NSDate* began = [NSDate date];
    [runtime ensureRunning:^(NSError* e) { e1 = e; calls++; }];
    [runtime ensureRunning:^(NSError* e) { e2 = e; calls++; }];
    CHECK(SpinUntil(^BOOL { return calls == 2; }, 30));
    SpinUntil(^BOOL { return NO; }, 0.3);
    CHECK(calls == 2 && e1 == nil && e2 == nil && [[NSDate date] timeIntervalSinceDate:began] >= 1.4);
    CHECK(runtime.isManaged && Answers(base));
    NSArray* starts = Starts();
    CHECK(starts.count == before + 1);
    NSDictionary* start = starts.lastObject;
    CHECK([start[@"argv"] isEqualToArray:@[@"serve"]]);
    CHECK([start[@"host"] isEqualToString:[NSString stringWithFormat:@"127.0.0.1:%@", gPort]]);   //this Mac only, on the chosen port
    CHECK([start[@"keep_alive"] isEqualToString:@"10m"]);
    CHECK([[start[@"cwd"] stringByResolvingSymlinksInPath] isEqualToString:[NSHomeDirectory() stringByResolvingSymlinksInPath]]);
    pid_t pid = [start[@"pid"] intValue];
    CHECK(ProcessExists(pid));

    //running: asked again, it answers at once and starts nothing
    BOOL finished = NO;
    NSDate* t = [NSDate date];
    CHECK(Ensure(runtime, 10, &finished) == nil && finished && [[NSDate date] timeIntervalSinceDate:t] < 3 && Starts().count == before + 1);

    //stopped: the process is gone and the port is free
    [runtime stopWaiting:5];
    CHECK(!runtime.isManaged && !ProcessExists(pid));
    SpinUntil(^BOOL { return !Answers(base); }, 5);
    CHECK(!Answers(base));
    [runtime stopWaiting:5];                                           //stopping twice does nothing

    //and it can be started again
    Mode(@"normal", @"0");
    CHECK(Ensure(runtime, 30, &finished) == nil && finished && runtime.isManaged && Starts().count == before + 2);
    pid = [Starts().lastObject[@"pid"] intValue];
    //the choice of the user for the time a model stays in memory is respected
    [runtime stopWaiting:5];
    setenv("OLLAMA_KEEP_ALIVE", "1h", 1);
    CHECK(Ensure(runtime, 30, &finished) == nil && [[Starts().lastObject objectForKey:@"keep_alive"] isEqualToString:@"1h"]);
    unsetenv("OLLAMA_KEEP_ALIVE");
    [runtime stopWaiting:5];
    SpinUntil(^BOOL { return !Answers(base); }, 5);
    (void)pid;
}

static void TestFailures(void) {
    NSString* base = [NSString stringWithFormat:@"http://127.0.0.1:%@", gPort];
    BOOL finished = NO;
    //it stops at once: the reason it printed is given
    Mode(@"die", @"0");
    AIOllamaRuntime* runtime = Runtime(@[gFake]);
    NSError* error = Ensure(runtime, 30, &finished);
    CHECK(finished && error != nil && [error.localizedDescription containsString:@"dừng ngay khi khởi động"] && [error.localizedDescription containsString:@"address already in use"]);
    CHECK(!runtime.isManaged && [runtime.lastOutput containsString:@"address already in use"]);
    //a later start is not blocked by the failure
    Mode(@"normal", @"0");
    CHECK(Ensure(runtime, 30, &finished) == nil && runtime.isManaged);
    [runtime stopWaiting:5];
    SpinUntil(^BOOL { return !Answers(base); }, 5);

    //it never answers: the wait ends, the process is stopped
    Mode(@"hang", @"0");
    runtime = Runtime(@[gFake]);
    runtime.startTimeout = 3;
    NSDate* began = [NSDate date];
    error = Ensure(runtime, 30, &finished);
    NSTimeInterval took = [[NSDate date] timeIntervalSinceDate:began];
    CHECK(finished && error != nil && [error.localizedDescription containsString:@"không trả lời"] && took >= 2.5 && took < 15);
    CHECK(!runtime.isManaged);
    pid_t hung = [Starts().lastObject[@"pid"] intValue];
    SpinUntil(^BOOL { return !ProcessExists(hung); }, 5);
    CHECK(!ProcessExists(hung));

    //a program that will not stop is forced
    Mode(@"ignore-term", @"0");
    runtime = Runtime(@[gFake]);
    CHECK(Ensure(runtime, 30, &finished) == nil && runtime.isManaged);
    pid_t stubborn = [Starts().lastObject[@"pid"] intValue];
    began = [NSDate date];
    [runtime stopWaiting:1];
    CHECK([[NSDate date] timeIntervalSinceDate:began] < 5);
    SpinUntil(^BOOL { return !ProcessExists(stubborn); }, 5);
    CHECK(!ProcessExists(stubborn) && !runtime.isManaged);
    SpinUntil(^BOOL { return !Answers(base); }, 5);

    //something that is not a program
    NSString* broken = [gFolder stringByAppendingPathComponent:@"broken-ollama"];
    [@"#!/nonexistent/interpreter\n" writeToFile:broken atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod(broken.UTF8String, 0755);
    runtime = Runtime(@[broken]);
    error = Ensure(runtime, 30, &finished);
    CHECK(finished && error != nil && !runtime.isManaged);
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 5) { printf("usage: ai_local_runtime_test <fake_ollama.py> <port> <mock port> <folder>\n"); return 2; }
        gFake = @(argv[1]);
        gPort = @(argv[2]);
        gMockBase = [NSString stringWithFormat:@"http://127.0.0.1:%s", argv[3]];
        gFolder = @(argv[4]);
        gLog = [gFolder stringByAppendingPathComponent:@"starts.log"];
        TestFinding();
        TestNotInstalledAndAlreadyRunning();
        TestStartAndStop();
        TestFailures();
        printf(failures == 0 ? "ai_local_runtime_test: all passed\n" : "ai_local_runtime_test: %d FAILED\n", failures);
        return failures == 0 ? 0 : 1;
    }
}
