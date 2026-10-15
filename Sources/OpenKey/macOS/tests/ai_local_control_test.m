// Tests of what the settings do about an AI that runs on the Mac (AILocalControl and the status, stop and unload of AIOllamaRuntime):
// start it, stop it, take the models out of memory, tell who started a server that is running, and say how busy the Mac is. The server is
// a stand-in (fake_ollama.py), started in the different ways a real one can be: by VOpenKey, left over by an earlier run, or by
// someone else. Run with run-ai-local-test.sh.
//
//   ai_local_control_test <fake_ollama.py> <free port> <folder>
#import <Foundation/Foundation.h>
#import <libproc.h>
#import <signal.h>
#import "AILocalControl.h"
#import "AIOllama.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSString *gFake, *gPort, *gBase, *gFolder;

static BOOL SpinUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return done();
}

static BOOL Answers(void) {
    __block BOOL done = NO, ok = NO;
    AIOllama* api = [[AIOllama alloc] initWithBaseURL:[NSURL URLWithString:gBase]];
    [api versionWithTimeout:1 completion:^(NSString* v, NSError* e) { ok = v != nil; done = YES; }];
    SpinUntil(^BOOL { return done; }, 5);
    return ok;
}

static void WaitForSilence(void) { SpinUntil(^BOOL { return !Answers(); }, 10); }

static AIOllamaRuntime* Runtime(BOOL installed) {
    AIOllamaRuntime* runtime = [[AIOllamaRuntime alloc] initWithBaseURL:[NSURL URLWithString:gBase] searchPaths:installed ? @[gFake] : @[]];
    runtime.startTimeout = 30;
    runtime.ownPrograms = @[@"/nonexistent/ollama"];
    return runtime;
}

static AIHardware* Mac(double load, AIMemoryPressure pressure) {
    AIHardware* mac = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:200];
    mac.cpuLoadRatio = load;
    mac.memoryPressure = pressure;
    return mac;
}

static AILocalControl* Control(AIOllamaRuntime* runtime, AIHardware* mac) {
    AILocalControl* control = [[AILocalControl alloc] initWithRuntime:runtime];
    control.hardwareProvider = ^AIHardware*{ return mac; };
    return control;
}

static void Refresh(AILocalControl* control) {
    __block BOOL done = NO;
    void (^previous)(void) = control.onChange;
    control.onChange = ^{ done = YES; if (previous) previous(); };
    [control refresh];
    SpinUntil(^BOOL { return done; }, 10);
    control.onChange = previous;
}

static void WaitFor(AILocalControl* control, BOOL (^condition)(void)) {
    SpinUntil(^BOOL { return condition(); }, 60);
}

//asks a model something, so that the server holds it in memory
static void Chat(NSString* model) {
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[gBase stringByAppendingString:@"/v1/chat/completions"]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"model": model, @"messages": @[@{@"role": @"user", @"content": @"hi"}], @"stream": @YES} options:0 error:nil];
    __block BOOL done = NO;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* d, NSURLResponse* r, NSError* e) { done = YES; }] resume];
    SpinUntil(^BOOL { return done; }, 10);
}

static NSString* PathOf(int pid) {
    char buffer[PROC_PIDPATHINFO_MAXSIZE];
    return proc_pidpath(pid, buffer, sizeof(buffer)) > 0 ? @(buffer) : nil;
}

static NSString* Spawn(NSTask** task, BOOL orphan, int* pid) {
    NSTask* t = [[NSTask alloc] init];
    NSMutableDictionary* env = [[[NSProcessInfo processInfo] environment] mutableCopy];
    env[@"OLLAMA_HOST"] = [@"127.0.0.1:" stringByAppendingString:gPort];
    t.environment = env;
    t.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    t.standardInput = [NSFileHandle fileHandleWithNullDevice];
    NSPipe* pipe = [NSPipe pipe];
    if (orphan) {
        //started by a shell that ends at once: the server is then nobody's child (its parent is launchd), like one left by a VOpenKey that quit
        t.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
        t.arguments = @[@"-c", [NSString stringWithFormat:@"%@ serve >/dev/null 2>&1 </dev/null & echo $!", gFake]];
        t.standardOutput = pipe;
    } else {
        t.executableURL = [NSURL fileURLWithPath:gFake];
        t.arguments = @[@"serve"];
    }
    [t launchAndReturnError:nil];
    if (task) *task = t;
    if (orphan) {
        NSData* data = [pipe.fileHandleForReading readDataToEndOfFile];
        [t waitUntilExit];
        *pid = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] intValue];
    } else {
        *pid = t.processIdentifier;
    }
    SpinUntil(^BOOL { return Answers(); }, 30);
    return PathOf(*pid);
}

#pragma mark - Tests

static void TestNothing(void) {
    AILocalControl* control = Control(Runtime(NO), Mac(0.1, AIMemoryPressureNormal));
    CHECK(!control.detected && [control.statusText isEqualToString:@"Đang kiểm tra…"]);         //before it has looked
    Refresh(control);
    CHECK(!control.detected && !control.canStart && !control.canStop && !control.canUnload && !control.busy);
    CHECK([control.statusText containsString:@"Chưa cài"] && control.problemText == nil);
    [control start]; [control stop]; [control unload];                                         //nothing to do: nothing happens
    CHECK(!control.busy);
}

static void TestInstalledNotRunning(void) {
    AIOllamaRuntime* runtime = Runtime(YES);
    AILocalControl* control = Control(runtime, Mac(0.1, AIMemoryPressureNormal));
    Refresh(control);
    CHECK(control.detected && control.canStart && !control.canStop && !control.canUnload);
    CHECK([control.statusText containsString:@"đang tắt"] && [control.statusText containsString:@"không tốn RAM"]);

    //start: the buttons wait while it starts, then it runs and VOpenKey owns it
    __block int changes = 0;
    control.onChange = ^{ changes++; };
    [control start];
    CHECK(control.busy && !control.canStart && [control.statusText containsString:@"Đang khởi động Ollama"]);
    [control start];                                                                           //a second click does nothing
    WaitFor(control, ^BOOL { return !control.busy && control.canStop; });
    CHECK(!control.busy && control.problemText == nil && runtime.isManaged && Answers());
    CHECK([control.statusText containsString:@"đang chạy (do VOpenKey AI mở)"] && [control.statusText containsString:@"Chưa nạp model nào"]);
    CHECK([control.briefStatusText hasPrefix:@"Ollama đang chạy"] && [control.briefStatusText containsString:@"chưa nạp model"] && control.briefStatusText.length < control.statusText.length);   //the short line the settings show
    CHECK(control.canStop && !control.canStart && !control.canUnload && changes >= 2);

    //a model is loaded when it answers: the memory it takes is said, and it can be freed without stopping the server
    Chat(@"tiny:1b");
    Refresh(control);
    CHECK([control.statusText containsString:@"tiny:1b"] && [control.statusText containsString:@"2,0 GB"] && control.canUnload);
    [control unload];
    CHECK(control.busy && [control.statusText containsString:@"Đang giải phóng RAM"]);
    WaitFor(control, ^BOOL { return !control.busy; });
    SpinUntil(^BOOL { return !control.canUnload && [control.statusText containsString:@"Chưa nạp model nào"]; }, 10);
    CHECK([control.statusText containsString:@"Chưa nạp model nào"] && !control.canUnload && Answers() && runtime.isManaged);

    //stop: the process ends, and it can be started again
    [control stop];
    CHECK(control.busy && [control.statusText containsString:@"Đang dừng"]);
    WaitFor(control, ^BOOL { return !control.busy; });
    WaitForSilence();
    CHECK(!Answers() && !runtime.isManaged);
    SpinUntil(^BOOL { return control.canStart; }, 10);
    CHECK(control.canStart && !control.canStop && [control.statusText containsString:@"đang tắt"] && control.problemText == nil);
}

static void TestStartFails(void) {
    setenv("FAKE_OLLAMA_MODE", "die", 1);
    AILocalControl* control = Control(Runtime(YES), Mac(0.1, AIMemoryPressureNormal));
    Refresh(control);
    [control start];
    WaitFor(control, ^BOOL { return !control.busy; });
    CHECK(!control.busy && [control.problemText containsString:@"dừng ngay khi khởi động"] && control.canStart);
    setenv("FAKE_OLLAMA_MODE", "normal", 1);
    [control start];                                                                           //the next action clears the problem
    CHECK(control.problemText == nil);
    WaitFor(control, ^BOOL { return !control.busy; });
    CHECK(control.problemText == nil && Answers());
    [control stop];
    WaitFor(control, ^BOOL { return !control.busy; });
    WaitForSilence();
}

static void TestServerOfSomeoneElse(void) {
    //the server is a child of another program (here, of this test): the Ollama application, a terminal... It is not VOpenKey's to stop
    NSTask* task = nil; int pid = 0;
    NSString* path = Spawn(&task, NO, &pid);
    CHECK(Answers() && path != nil);
    AIOllamaRuntime* runtime = Runtime(YES);
    runtime.ownPrograms = @[path];                                                              //even if it is the program VOpenKey uses
    AILocalControl* control = Control(runtime, Mac(0.1, AIMemoryPressureNormal));
    Refresh(control);
    CHECK(control.detected && !control.canStart && !control.canStop && !control.canUnload);
    CHECK([control.statusText containsString:@"do ứng dụng khác mở"]);
    [control stop];
    CHECK(!control.busy);
    __block AIOllamaStatus* status = nil;
    [runtime statusWithCompletion:^(AIOllamaStatus* s) { status = s; }];
    SpinUntil(^BOOL { return status != nil; }, 10);
    if (!(status.running && status.origin == AIOllamaOriginOther && status.processIdentifier == pid))
        printf("  status: running %d origin %ld pid %d (expected %d) canStop %d version %s\n", status.running, (long)status.origin, status.processIdentifier, pid, status.canStop, status.version.UTF8String);
    CHECK(status.running && status.origin == AIOllamaOriginOther && status.processIdentifier == pid && !status.canStop && [status.version isEqualToString:@"0.0.0-fake"]);
    __block NSError* stopError = nil; __block BOOL stopped = NO;
    [runtime stopWithCompletion:^(NSError* e) { stopError = e; stopped = YES; }];
    SpinUntil(^BOOL { return stopped; }, 10);
    CHECK(stopError != nil && [stopError.localizedDescription containsString:@"không tắt giúp"] && Answers() && kill(pid, 0) == 0);

    //but the memory can be freed
    Chat(@"qwen:1b");
    Refresh(control);
    CHECK(control.canUnload && [control.statusText containsString:@"qwen:1b"]);
    [control unload];
    WaitFor(control, ^BOOL { return !control.busy; });
    SpinUntil(^BOOL { return !control.canUnload; }, 10);
    CHECK(!control.canUnload && Answers());
    [task terminate];
    [task waitUntilExit];
    WaitForSilence();
}

static void TestLeftover(void) {
    //a server that VOpenKey started in an earlier run and nobody stopped: its parent is launchd and it is the program VOpenKey uses
    int pid = 0;
    NSString* path = Spawn(NULL, YES, &pid);
    CHECK(pid > 1 && Answers() && path != nil && kill(pid, 0) == 0);
    AIOllamaRuntime* runtime = Runtime(YES);
    AILocalControl* control = Control(runtime, Mac(0.1, AIMemoryPressureNormal));
    Refresh(control);                                                                           //not recognised as its own: the program is not in the list
    CHECK(!control.canStop && [control.statusText containsString:@"do ứng dụng khác mở"]);
    runtime.ownPrograms = @[path];
    Refresh(control);
    CHECK(control.canStop && !control.canStart && [control.statusText containsString:@"từ lần trước"]);
    __block AIOllamaStatus* status = nil;
    [runtime statusWithCompletion:^(AIOllamaStatus* s) { status = s; }];
    SpinUntil(^BOOL { return status != nil; }, 10);
    if (status.origin != AIOllamaOriginLeftover)
        printf("  leftover: origin %ld pid %d (expected %d) own %s actual path %s\n", (long)status.origin, status.processIdentifier, pid, [runtime.ownPrograms.firstObject UTF8String], [PathOf(status.processIdentifier) UTF8String]);
    CHECK(status.origin == AIOllamaOriginLeftover && status.processIdentifier == pid && status.canStop && !runtime.isManaged);
    [control stop];
    WaitFor(control, ^BOOL { return !control.busy; });
    WaitForSilence();
    CHECK(!Answers() && kill(pid, 0) != 0);
    CHECK(control.problemText == nil);
}

static void TestBusyMac(void) {
    AIOllamaRuntime* runtime = Runtime(YES);
    AILocalControl* control = Control(runtime, Mac(0.1, AIMemoryPressureNormal));
    Refresh(control);
    CHECK(!control.macIsBusy && [control.loadText containsString:@"đang rảnh"] && [control.loadText containsString:@"khoảng 10%"] && [control.loadText containsString:@"bộ nhớ ổn"]);
    CHECK([control.loadText containsString:@"chỉ hợp khi máy ít việc"]);
    CHECK([control.briefLoadText containsString:@"Máy đang rảnh"] && [control.briefLoadText containsString:@"CPU 10%"] && control.briefLoadText.length < control.loadText.length);
    control = Control(runtime, Mac(0.5, AIMemoryPressureNormal));
    Refresh(control);
    CHECK(!control.macIsBusy && [control.loadText containsString:@"hơi bận"]);
    control = Control(runtime, Mac(0.8, AIMemoryPressureNormal));
    Refresh(control);
    CHECK(control.macIsBusy && [control.loadText containsString:@"hơi bận"] && [control.loadText containsString:@"chỉ nên dùng khi máy đang rảnh"]);
    control = Control(runtime, Mac(1.6, AIMemoryPressureNormal));
    Refresh(control);
    CHECK(control.macIsBusy && [control.loadText containsString:@"đang bận"] && [control.loadText containsString:@"khoảng 100%"]);       //never more than 100%
    control = Control(runtime, Mac(0.1, AIMemoryPressureWarning));
    Refresh(control);
    CHECK(control.macIsBusy && [control.loadText containsString:@"bộ nhớ khá đầy"]);
    control = Control(runtime, Mac(0.1, AIMemoryPressureCritical));
    Refresh(control);
    CHECK(control.macIsBusy && [control.loadText containsString:@"đang bận"] && [control.loadText containsString:@"bộ nhớ quá tải"]);
}

static void TestApi(void) {
    //the server is not running
    AIOllama* api = [[AIOllama alloc] initWithBaseURL:[NSURL URLWithString:gBase]];
    __block NSError* error = nil; __block NSArray* models = @[@1]; __block BOOL done = NO;
    [api loadedModelsWithCompletion:^(NSArray* m, NSError* e) { models = m; error = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 10);
    CHECK(models == nil && error.code == VOKAILocalErrorNotRunning);
    done = NO; error = nil;
    [api unloadModel:@"x:1b" completion:^(NSError* e) { error = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 10);
    CHECK(error.code == VOKAILocalErrorNotRunning);
    //it runs
    NSTask* task = nil; int pid = 0;
    Spawn(&task, NO, &pid);
    done = NO; error = nil; models = nil;
    [api loadedModelsWithCompletion:^(NSArray* m, NSError* e) { models = m; error = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 10);
    CHECK(error == nil && models.count == 0);
    Chat(@"a:1b"); Chat(@"b:1b");
    done = NO;
    [api loadedModelsWithCompletion:^(NSArray* m, NSError* e) { models = m; error = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 10);
    CHECK(models.count == 2 && [models[0][@"name"] isEqualToString:@"a:1b"] && [models[0][@"size"] unsignedLongLongValue] == 2000000000ULL);
    done = NO; error = nil;
    [api unloadModel:@"a:1b" completion:^(NSError* e) { error = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 10);
    CHECK(error == nil);
    done = NO; error = nil;
    [api unloadModel:@"never-heard-of:1b" completion:^(NSError* e) { error = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 10);
    CHECK(error.code == VOKAILocalErrorNotFound);
    //all of them, through the runtime
    AIOllamaRuntime* runtime = Runtime(YES);
    done = NO; error = nil;
    [runtime unloadModelsWithCompletion:^(NSError* e) { error = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 20);
    CHECK(error == nil);
    done = NO;
    [api loadedModelsWithCompletion:^(NSArray* m, NSError* e) { models = m; done = YES; }];
    SpinUntil(^BOOL { return done; }, 10);
    CHECK(models.count == 0);
    [task terminate];
    [task waitUntilExit];
    WaitForSilence();
    //with nothing running there is nothing in memory, and that is not an error
    done = NO; error = nil;
    [runtime unloadModelsWithCompletion:^(NSError* e) { error = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 20);
    CHECK(error == nil);
    done = NO;
    __block NSError* stopError = (NSError*)@1;
    [runtime stopWithCompletion:^(NSError* e) { stopError = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 10);
    CHECK(stopError == nil);
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 4) { printf("usage: ai_local_control_test <fake_ollama.py> <port> <folder>\n"); return 2; }
        gFake = @(argv[1]);
        gPort = @(argv[2]);
        gBase = [@"http://127.0.0.1:" stringByAppendingString:gPort];
        gFolder = @(argv[3]);
        setenv("FAKE_OLLAMA_LOG", [gFolder stringByAppendingPathComponent:@"control-starts.log"].UTF8String, 1);
        setenv("FAKE_OLLAMA_MODELS", [gFolder stringByAppendingPathComponent:@"control-models.json"].UTF8String, 1);
        setenv("FAKE_OLLAMA_MODE", "normal", 1);
        setenv("FAKE_OLLAMA_DELAY", "0", 1);
        TestNothing();
        TestInstalledNotRunning();
        TestStartFails();
        TestServerOfSomeoneElse();
        TestLeftover();
        TestBusyMac();
        TestApi();
        printf(failures == 0 ? "ai_local_control_test: all passed\n" : "ai_local_control_test: %d FAILED\n", failures);
        return failures == 0 ? 0 : 1;
    }
}
