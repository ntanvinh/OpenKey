// Tests of AIOllama: the reading of the progress of a download, and the calls to Ollama and to the library of models, against
// the fake server mock_ollama_server.py. Run with run-ai-local-test.sh, which starts the fake server.
//
//   ai_ollama_test <port of the fake server> <port where nothing listens>
//
// Nothing is downloaded from the real library and no real Ollama is contacted.
#import <Foundation/Foundation.h>
#import "AIOllama.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSString* gBase;         //http://127.0.0.1:<port>
static AIOllama* gOllama;
static AIOllama* gNobody;       //an address where nothing listens

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
    SpinUntil(^BOOL { return finished; }, 5);
}

static NSData* Bytes(NSString* text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; }

//the lines of a real download of a small model (shortened), as Ollama 0.x sent them
static NSString* RealSample(void) {
    return @"{\"status\":\"pulling manifest\"}\n"
    "{\"status\":\"pulling 735af2139dc6\",\"digest\":\"sha256:735af2139dc6\",\"total\":1000}\n"
    "{\"status\":\"pulling 735af2139dc6\",\"digest\":\"sha256:735af2139dc6\",\"total\":1000,\"completed\":400}\n"
    "{\"status\":\"pulling 735af2139dc6\",\"digest\":\"sha256:735af2139dc6\",\"total\":1000,\"completed\":1000}\n"
    "{\"status\":\"pulling 3e2c24001f9e\",\"digest\":\"sha256:3e2c24001f9e\",\"total\":100}\n"
    "{\"status\":\"pulling 3e2c24001f9e\",\"digest\":\"sha256:3e2c24001f9e\",\"total\":100,\"completed\":100}\n"
    "{\"status\":\"verifying sha256 digest\"}\n"
    "{\"status\":\"writing manifest\"}\n"
    "{\"status\":\"success\"}\n";
}

static void TestParser(void) {
    //whole
    AIPullParser* parser = [[AIPullParser alloc] initWithExpectedBytes:0];
    NSArray<AIPullProgress*>* reports = [parser feed:Bytes(RealSample())];
    CHECK(reports.count == 9 && parser.succeeded && parser.errorMessage == nil);
    CHECK([reports[0].status isEqualToString:@"Đang lấy thông tin model"] && reports[0].fraction < 0);
    CHECK([reports[1].status isEqualToString:@"Đang tải model"] && reports[1].totalBytes == 1000 && reports[1].completedBytes == 0);
    CHECK(reports[2].completedBytes == 400 && fabs(reports[2].fraction - 0.4) < 1e-9);
    CHECK(reports[3].completedBytes == 1000 && reports[3].fraction == 1.0);
    CHECK(reports[4].totalBytes == 1100 && reports[4].completedBytes == 1000);       //without the size in advance the total grows
    CHECK(reports[6].completedBytes == 1100 && [reports[6].status isEqualToString:@"Đang kiểm tra file tải về"] && reports[6].fraction < 0);
    CHECK([reports[7].status isEqualToString:@"Đang ghi model vào máy"]);
    CHECK([reports[8].status isEqualToString:@"Xong"] && reports[8].finished && reports[8].fraction == 1.0);

    //with the size known in advance, the bar does not go back when the small files come after the big one
    parser = [[AIPullParser alloc] initWithExpectedBytes:1100];
    reports = [parser feed:Bytes(RealSample())];
    double last = 0;
    for (AIPullProgress* r in reports) {
        if (r.fraction >= 0) { CHECK(r.fraction >= last - 1e-12); last = r.fraction; }
        CHECK(r.totalBytes == 1100);
    }
    CHECK(fabs(reports[3].fraction - 1000.0 / 1100.0) < 1e-9);
    //an expected size smaller than what comes is not exceeded
    parser = [[AIPullParser alloc] initWithExpectedBytes:500];
    reports = [parser feed:Bytes(RealSample())];
    CHECK(reports[3].completedBytes == 500 && reports[3].fraction == 1.0);

    //cut anywhere, a byte at a time, gives the same reports
    NSData* sample = Bytes(RealSample());
    parser = [[AIPullParser alloc] initWithExpectedBytes:0];
    NSMutableArray* all = [NSMutableArray array];
    for (NSUInteger i = 0; i < sample.length; i++)
        [all addObjectsFromArray:[parser feed:[sample subdataWithRange:NSMakeRange(i, 1)]]];
    CHECK(all.count == 9 && parser.succeeded);
    for (NSUInteger i = 0; i < all.count && i < reports.count; i++) {
        AIPullProgress* a = all[i];
        CHECK([a.status length] > 0);
    }

    //the line is complete only with its line break
    parser = [[AIPullParser alloc] initWithExpectedBytes:0];
    CHECK([parser feed:Bytes(@"{\"status\":\"success\"}")].count == 0 && !parser.succeeded);
    CHECK([parser feed:Bytes(@"\n")].count == 1 && parser.succeeded);
    //nothing more is read after the end
    CHECK([parser feed:Bytes(@"{\"status\":\"pulling manifest\"}\n")].count == 0);

    //empty lines and the Windows line break are tolerated
    parser = [[AIPullParser alloc] initWithExpectedBytes:0];
    CHECK([parser feed:Bytes(@"\n  \n{\"status\":\"pulling manifest\"}\r\n\n")].count == 1 && parser.errorMessage == nil);

    //an error of Ollama stops the reading and keeps what it says
    parser = [[AIPullParser alloc] initWithExpectedBytes:0];
    reports = [parser feed:Bytes(@"{\"status\":\"pulling manifest\"}\n{\"error\":\"pull model manifest: file does not exist\"}\n{\"status\":\"success\"}\n")];
    CHECK(reports.count == 1 && !parser.succeeded && [parser.errorMessage hasPrefix:@"Không tìm thấy model"]);
    parser = [[AIPullParser alloc] initWithExpectedBytes:0];
    [parser feed:Bytes(@"{\"error\":\"write: no space left on device\"}\n")];
    CHECK([parser.errorMessage containsString:@"hết chỗ"]);
    parser = [[AIPullParser alloc] initWithExpectedBytes:0];
    [parser feed:Bytes(@"{\"error\":\"Get https://x: dial tcp: no such host\"}\n")];
    CHECK([parser.errorMessage containsString:@"mạng"]);
    parser = [[AIPullParser alloc] initWithExpectedBytes:0];
    [parser feed:Bytes(@"{\"error\":\"something unforeseen\"}\n")];
    CHECK([parser.errorMessage isEqualToString:@"Ollama báo lỗi: something unforeseen"]);

    //what Ollama does not send
    for (NSString* bad in @[@"this is not json\n", @"[1,2,3]\n", @"\"text\"\n", @"123\n", @"{\"status\":\n"]) {
        parser = [[AIPullParser alloc] initWithExpectedBytes:0];
        [parser feed:Bytes(bad)];
        CHECK(parser.errorMessage != nil && !parser.succeeded);
    }
    //numbers that make no sense do not crash or overflow the progress
    parser = [[AIPullParser alloc] initWithExpectedBytes:0];
    reports = [parser feed:Bytes(@"{\"status\":\"pulling a\",\"digest\":\"d1\",\"total\":-5,\"completed\":10}\n"
                                 "{\"status\":\"pulling b\",\"digest\":\"d2\",\"total\":100,\"completed\":999}\n"
                                 "{\"status\":\"pulling c\",\"digest\":\"d3\",\"total\":\"many\",\"completed\":\"some\"}\n"
                                 "{\"status\":\"pulling d\",\"digest\":\"d4\",\"total\":1e30,\"completed\":1e29}\n"
                                 "{\"status\":\"pulling e\"}\n"
                                 "{\"status\":7}\n{\"status\":\"mystery\"}\n")];
    CHECK(reports.count == 7 && parser.errorMessage == nil);
    CHECK(reports[0].completedBytes == 0 && reports[0].totalBytes == 0 && reports[0].fraction < 0);
    CHECK(reports[1].completedBytes == 100 && reports[1].totalBytes == 100);       //completed cannot be more than the total
    CHECK(reports[6].status.length > 0);
    //a line that never ends
    parser = [[AIPullParser alloc] initWithExpectedBytes:0];
    NSData* chunk = [NSMutableData dataWithLength:65536];
    for (int i = 0; i < 20; i++)
        [parser feed:chunk];
    CHECK(parser.errorMessage != nil && [parser feed:Bytes(@"{\"status\":\"success\"}\n")].count == 0 && !parser.succeeded);
    //two digests count together, one digest repeated counts once
    parser = [[AIPullParser alloc] initWithExpectedBytes:0];
    reports = [parser feed:Bytes(@"{\"status\":\"pulling a\",\"digest\":\"d1\",\"total\":100,\"completed\":50}\n"
                                 "{\"status\":\"pulling a\",\"digest\":\"d1\",\"total\":100,\"completed\":60}\n"
                                 "{\"status\":\"pulling b\",\"digest\":\"d2\",\"total\":100,\"completed\":10}\n")];
    CHECK(reports.lastObject.completedBytes == 70 && reports.lastObject.totalBytes == 200);
}

static void TestAddresses(void) {
    CHECK([[AIOllama alloc] initWithBaseURL:[NSURL URLWithString:@"http://127.0.0.1:11434"]] != nil);
    CHECK([[AIOllama alloc] initWithBaseURL:[NSURL URLWithString:@"http://localhost:11434"]] != nil);
    CHECK([[AIOllama alloc] initWithBaseURL:[NSURL URLWithString:@"http://[::1]:11434"]] != nil);
    CHECK([[AIOllama alloc] initWithBaseURL:[AIOllama defaultBaseURL]] != nil);
    for (NSString* bad in @[@"http://example.com", @"http://192.168.1.5:11434", @"http://10.0.0.2", @"http://127.0.0.1.evil.com",
                            @"http://evil.com/127.0.0.1", @"ftp://127.0.0.1", @"file:///tmp", @"127.0.0.1:11434", @"http://0.0.0.0:11434", @"http://mac.local:11434"])
        CHECK([[AIOllama alloc] initWithBaseURL:[NSURL URLWithString:bad]] == nil);
    CHECK([[AIOllama alloc] initWithBaseURL:nil] == nil);
}

static void TestVersionAndModels(void) {
    __block NSString* version = nil; __block NSError* error = nil; __block BOOL done = NO;
    [gOllama versionWithTimeout:5 completion:^(NSString* v, NSError* e) { version = v; error = e; done = YES; }];
    CHECK(SpinUntil(^BOOL { return done; }, 5) && [version isEqualToString:@"0.0.0-mock"] && error == nil);

    done = NO; version = nil; error = nil;
    [gNobody versionWithTimeout:5 completion:^(NSString* v, NSError* e) { version = v; error = e; done = YES; }];
    CHECK(SpinUntil(^BOOL { return done; }, 8) && version == nil && error.code == VOKAILocalErrorNotRunning);
    CHECK([error.domain isEqualToString:VOKAILocalErrorDomain] && [error.localizedDescription containsString:@"chưa chạy"]);

    //the server answers, but it is not Ollama
    Control(@{@"version_html": @YES});
    done = NO; version = nil; error = nil;
    [gOllama versionWithTimeout:5 completion:^(NSString* v, NSError* e) { version = v; error = e; done = YES; }];
    CHECK(SpinUntil(^BOOL { return done; }, 5) && version == nil && error.code == VOKAILocalErrorBadResponse);
    Control(@{@"version_html": @NO});

    //it cuts the connection while it starts (a GET is tried again by the system, so every try is cut)
    Control(@{@"version_failures": @100});
    done = NO; version = nil; error = nil;
    [gOllama versionWithTimeout:5 completion:^(NSString* v, NSError* e) { version = v; error = e; done = YES; }];
    CHECK(SpinUntil(^BOOL { return done; }, 5) && version == nil && error != nil);

    Control(@{@"version_failures": @0});

    __block NSArray* models = nil;
    done = NO;
    [gOllama installedModelsWithCompletion:^(NSArray* m, NSError* e) { models = m; error = e; done = YES; }];
    CHECK(SpinUntil(^BOOL { return done; }, 5) && models.count == 0 && error == nil);
    CHECK(![AIOllama tag:@"gemma3:1b" isAmongInstalled:models]);
    done = NO; models = nil; error = nil;
    [gNobody installedModelsWithCompletion:^(NSArray* m, NSError* e) { models = m; error = e; done = YES; }];
    CHECK(SpinUntil(^BOOL { return done; }, 8) && models == nil && error.code == VOKAILocalErrorNotRunning);

    //"gemma3" and "gemma3:latest" are the same
    NSArray* has = @[@{@"name": @"gemma3:latest", @"size": @1}, @{@"name": @"qwen2.5:7b"}, @{@"name": @"llama3.2"}];
    CHECK([AIOllama tag:@"gemma3" isAmongInstalled:has] && [AIOllama tag:@"gemma3:latest" isAmongInstalled:has]);
    CHECK([AIOllama tag:@"qwen2.5:7b" isAmongInstalled:has] && ![AIOllama tag:@"qwen2.5" isAmongInstalled:has] && ![AIOllama tag:@"qwen2.5:3b" isAmongInstalled:has]);
    CHECK([AIOllama tag:@"llama3.2:latest" isAmongInstalled:has] && ![AIOllama tag:@"gemma3:4b" isAmongInstalled:has]);
    CHECK(![AIOllama tag:@"x" isAmongInstalled:@[]]);
}

typedef struct { NSError* error; NSUInteger reports; BOOL done; } PullResult;

static PullResult Pull(NSString* tag, uint64_t expected, NSMutableArray<AIPullProgress*>* collected, AIOllamaTask** taskOut, NSTimeInterval cancelAfter) {
    __block PullResult result = {nil, 0, NO};
    AIOllamaTask* task = [gOllama pullModel:tag expectedBytes:expected progress:^(AIPullProgress* p) {
        result.reports++;
        [collected addObject:p];
    } completion:^(NSError* e) { result.error = e; result.done = YES; }];
    if (taskOut) *taskOut = task;
    if (cancelAfter > 0) {
        SpinUntil(^BOOL { return NO; }, cancelAfter);
        [task cancel];
    }
    SpinUntil(^BOOL { return result.done; }, 20);
    return result;
}

static void TestPull(void) {
    NSMutableArray<AIPullProgress*>* progress = [NSMutableArray array];
    PullResult r = Pull(@"ok:1b", 1008982, progress, NULL, 0);
    CHECK(r.done && r.error == nil);
    CHECK(progress.count > 4 && progress.count < 25);                   //throttled: the stream has 48 lines
    CHECK(progress.lastObject.finished && [progress.lastObject.status isEqualToString:@"Xong"]);
    CHECK(progress.lastObject.completedBytes == 1008982 && progress.lastObject.totalBytes == 1008982);
    double last = 0; BOOL monotonic = YES;
    for (AIPullProgress* p in progress) { if (p.fraction >= 0) { if (p.fraction < last - 1e-12) monotonic = NO; last = p.fraction; } }
    CHECK(monotonic);
    BOOL sawManifest = NO, sawVerify = NO;
    for (AIPullProgress* p in progress) { sawManifest |= [p.status containsString:@"thông tin"]; sawVerify |= [p.status containsString:@"kiểm tra"]; }
    CHECK(sawManifest && sawVerify);                                    //the phases without a number are shown too
    NSDictionary* state = ServerState();
    CHECK([state[@"pulls"] containsObject:@"ok:1b"] && [state[@"models"] containsObject:@"ok:1b"]);

    __block NSArray* models = nil; __block BOOL done = NO;
    [gOllama installedModelsWithCompletion:^(NSArray* m, NSError* e) { models = m; done = YES; }];
    SpinUntil(^BOOL { return done; }, 5);
    CHECK([AIOllama tag:@"ok:1b" isAmongInstalled:models]);

    //the model does not exist: in the stream, with the HTTP status 200
    r = Pull(@"missing:1b", 0, [NSMutableArray array], NULL, 0);
    CHECK(r.done && r.error.code == VOKAILocalErrorNotFound && [r.error.localizedDescription containsString:@"Không tìm thấy"]);
    r = Pull(@"boom:1b", 0, [NSMutableArray array], NULL, 0);
    CHECK(r.done && r.error.code == VOKAILocalErrorFailed && [r.error.localizedDescription isEqualToString:@"Ollama báo lỗi: the server exploded"]);
    r = Pull(@"cut:1b", 0, [NSMutableArray array], NULL, 0);
    CHECK(r.done && r.error.code == VOKAILocalErrorInterrupted && [r.error.localizedDescription containsString:@"tải tiếp"]);
    r = Pull(@"garbled:1b", 0, [NSMutableArray array], NULL, 0);
    CHECK(r.done && r.error.code == VOKAILocalErrorFailed && [r.error.localizedDescription containsString:@"không hợp lệ"]);
    CHECK(![[ServerState()[@"models"] description] containsString:@"garbled"]);
    NSDate* before = [NSDate date];
    r = Pull(@"huge:1b", 0, [NSMutableArray array], NULL, 0);
    CHECK(r.done && r.error != nil && [[NSDate date] timeIntervalSinceDate:before] < 10);
    r = Pull(@"full:1b", 0, [NSMutableArray array], NULL, 0);
    CHECK(r.done && r.error.code == VOKAILocalErrorFailed && [r.error.localizedDescription containsString:@"hết chỗ"]);

    //nothing listens
    __block PullResult dead = {nil, 0, NO};
    [gNobody pullModel:@"ok:1b" expectedBytes:0 progress:nil completion:^(NSError* e) { dead.error = e; dead.done = YES; }];
    SpinUntil(^BOOL { return dead.done; }, 8);
    CHECK(dead.done && dead.error.code == VOKAILocalErrorNotRunning);

    //cancelled in the middle: the server sees the connection close and the caller hears "cancelled", once
    NSUInteger aborted = [ServerState()[@"aborted"] unsignedIntegerValue];
    NSMutableArray* slowProgress = [NSMutableArray array];
    __block int completions = 0;
    PullResult c = {nil, 0, NO};
    __block PullResult cr = c;
    AIOllamaTask* task = [gOllama pullModel:@"slow:1b" expectedBytes:1008982 progress:^(AIPullProgress* p) { [slowProgress addObject:p]; }
                                 completion:^(NSError* e) { cr.error = e; cr.done = YES; completions++; }];
    SpinUntil(^BOOL { return slowProgress.count >= 3; }, 10);
    CHECK(slowProgress.count >= 3 && !cr.done);
    [task cancel];
    SpinUntil(^BOOL { return cr.done; }, 5);
    SpinUntil(^BOOL { return NO; }, 0.5);
    CHECK(cr.done && cr.error.code == VOKAILocalErrorCancelled && completions == 1);
    SpinUntil(^BOOL { return [ServerState()[@"aborted"] unsignedIntegerValue] > aborted; }, 5);
    CHECK([ServerState()[@"aborted"] unsignedIntegerValue] > aborted);
    NSUInteger after = slowProgress.count;
    SpinUntil(^BOOL { return NO; }, 0.5);
    CHECK(slowProgress.count == after);                                 //nothing is reported after the cancellation
    CHECK(![ServerState()[@"models"] containsObject:@"slow:1b"]);
    //cancelling a second time, or after the end, does nothing
    [task cancel];
    AIOllamaTask* finished = nil;
    r = Pull(@"ok:1b", 0, [NSMutableArray array], &finished, 0);
    CHECK(r.error == nil);
    [finished cancel];
    //cancelled at once, before anything arrives
    __block PullResult early = {nil, 0, NO};
    AIOllamaTask* immediate = [gOllama pullModel:@"slow:1b" expectedBytes:0 progress:nil completion:^(NSError* e) { early.error = e; early.done = YES; }];
    [immediate cancel];
    SpinUntil(^BOOL { return early.done; }, 5);
    CHECK(early.done && early.error.code == VOKAILocalErrorCancelled);
}

static void TestDelete(void) {
    __block NSError* error = nil; __block BOOL done = NO;
    [gOllama deleteModel:@"ok:1b" completion:^(NSError* e) { error = e; done = YES; }];
    CHECK(SpinUntil(^BOOL { return done; }, 5) && error == nil && [ServerState()[@"deleted"] containsObject:@"ok:1b"]);
    done = NO;
    [gOllama deleteModel:@"ok:1b" completion:^(NSError* e) { error = e; done = YES; }];
    CHECK(SpinUntil(^BOOL { return done; }, 5) && error.code == VOKAILocalErrorNotFound);
    done = NO; error = nil;
    [gNobody deleteModel:@"ok:1b" completion:^(NSError* e) { error = e; done = YES; }];
    CHECK(SpinUntil(^BOOL { return done; }, 8) && error.code == VOKAILocalErrorNotRunning);
}

static void TestLibrary(void) {
    NSURL* registry = [NSURL URLWithString:gBase];
    __block uint64_t bytes = 0; __block NSError* error = nil; __block BOOL done = NO;
    void (^ask)(NSString*) = ^(NSString* tag) {
        bytes = 0; error = nil; done = NO;
        [AIOllama librarySizeOfTag:tag registry:registry completion:^(uint64_t b, NSError* e) { bytes = b; error = e; done = YES; }];
        SpinUntil(^BOOL { return done; }, 8);
    };
    ask(@"gemma3:1b");
    CHECK(done && error == nil && bytes == 800000000 + 6000 + 1000 + 400);       //the layers and the config
    ask(@"nothere:1b");
    CHECK(done && bytes == 0 && error.code == VOKAILocalErrorNotFound);
    ask(@"gemma3");                                                              //"latest" is not in the fake library
    CHECK(done && error.code == VOKAILocalErrorNotFound);
    NSUInteger requests = [ServerState()[@"manifest_requests"] count];
    ask(@"hf.co/someone/model:Q4_K_M");                                          //another registry: not asked, not an error
    CHECK(done && bytes == 0 && error == nil && [ServerState()[@"manifest_requests"] count] == requests);
    ask(@"registry.example.com/team/model:1b");
    CHECK(done && bytes == 0 && error == nil && [ServerState()[@"manifest_requests"] count] == requests);
    ask(@"someone/tiny:1b");                                                     //a model of a user of the library: namespace/name
    CHECK(done && error.code == VOKAILocalErrorNotFound);
    NSArray* paths = ServerState()[@"manifest_requests"];
    CHECK([paths containsObject:@"/v2/library/gemma3/manifests/1b"] && [paths containsObject:@"/v2/library/gemma3/manifests/latest"]);
    CHECK([paths containsObject:@"/v2/someone/tiny/manifests/1b"]);
    //the library is not reachable
    done = NO;
    [AIOllama librarySizeOfTag:@"gemma3:1b" registry:[NSURL URLWithString:@"http://127.0.0.1:1"] completion:^(uint64_t b, NSError* e) { bytes = b; error = e; done = YES; }];
    SpinUntil(^BOOL { return done; }, 8);
    CHECK(done && bytes == 0 && error.code == VOKAILocalErrorFailed);
    //a redirect to the internet in the clear is not followed; one to this Mac, or in https, is
    Control(@{@"manifest_redirect": @"external"});
    ask(@"gemma3:1b");
    CHECK(done && bytes == 0 && error != nil && error.code != VOKAILocalErrorNotFound);
    Control(@{@"manifest_redirect": @"local"});
    ask(@"gemma3:1b");
    CHECK(done && error == nil && bytes == 800007400);
    Control(@{@"manifest_redirect": @NO});
    CHECK([[AIOllama defaultRegistryURL].absoluteString isEqualToString:@"https://registry.ollama.ai"]);
    CHECK([[AIOllama defaultBaseURL].absoluteString isEqualToString:@"http://127.0.0.1:11434"]);
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 3) { printf("usage: ai_ollama_test <port> <dead port>\n"); return 2; }
        gBase = [NSString stringWithFormat:@"http://127.0.0.1:%s", argv[1]];
        gOllama = [[AIOllama alloc] initWithBaseURL:[NSURL URLWithString:gBase]];
        gNobody = [[AIOllama alloc] initWithBaseURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%s", argv[2]]]];
        TestParser();
        TestAddresses();
        TestVersionAndModels();
        TestPull();
        TestDelete();
        TestLibrary();
        printf(failures == 0 ? "ai_ollama_test: all passed\n" : "ai_ollama_test: %d FAILED\n", failures);
        return failures == 0 ? 0 : 1;
    }
}
