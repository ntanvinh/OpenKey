// Tests of the window "Cài AI chạy trên máy" (AILocalSetupController): what it says about different Macs, which models it lets the
// user install, what it shows while installing, cancelling, removing. The Mac is described by the test (AIHardware); the
// installation underneath is the one of ai_local_setup_test (stand-ins for GitHub and for Ollama). Needs a screen: a window is made.
//
//   ai_local_ui_test <fixtures> <mock port> <free port> <fake_ollama.py> <work folder> [folder for screenshots]
#import <Cocoa/Cocoa.h>
#import <sys/stat.h>
#import "AILocalSetupController.h"
#import "AISettings.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSString *gFixtures, *gMockBase, *gBase, *gWork, *gShots, *gFake;
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

@interface FakeVerifier : AIOllamaVerifier
@end
@implementation FakeVerifier
-(instancetype)init { return [super initWithTeamIdentifier:@"ABCDE12345" bundleIdentifier:@"x.y"]; }
-(BOOL)verifyApplication:(NSURL*)app minimumOS:(NSOperatingSystemVersion*)minimumOS error:(NSError**)error { if (minimumOS) *minimumOS = (NSOperatingSystemVersion){0, 0, 0}; return YES; }
-(BOOL)verifySignatureOfApplication:(NSURL*)app error:(NSError**)error { return YES; }
@end

static NSURL* ModelsDirectory(NSArray<NSString*>* installed) {
    gCounter++;
    NSString* dir = [gWork stringByAppendingPathComponent:[NSString stringWithFormat:@"models-%d", gCounter]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString* tag in installed) {
        NSArray* parts = [tag componentsSeparatedByString:@":"];
        NSString* file = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"manifests/registry.ollama.ai/library/%@/%@", parts[0], parts[1]]];
        [[NSFileManager defaultManager] createDirectoryAtPath:[file stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        [@"{}" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return [NSURL fileURLWithPath:dir];
}

static AILocalSetupController* MakeController(AIHardware* hardware, NSArray<NSString*>* installedModels, BOOL runtimeInstalled) {
    gCounter++;
    NSURL* apps = [NSURL fileURLWithPath:[gWork stringByAppendingPathComponent:[NSString stringWithFormat:@"apps-%d", gCounter]] isDirectory:YES];
    NSURL* tmp = [NSURL fileURLWithPath:[gWork stringByAppendingPathComponent:[NSString stringWithFormat:@"tmp-%d", gCounter]] isDirectory:YES];
    NSString* program = [apps.path stringByAppendingPathComponent:@"Ollama.app/Contents/Resources/ollama"];
    if (runtimeInstalled) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[program stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSFileManager defaultManager] copyItemAtPath:gFake toPath:program error:nil];          //an Ollama that is installed (and answers)
        chmod(program.UTF8String, 0755);
    }
    AIOllamaRuntime* runtime = [[AIOllamaRuntime alloc] initWithBaseURL:[NSURL URLWithString:gBase] searchPaths:@[program]];
    runtime.startTimeout = 20;
    [gRuntimes addObject:runtime];
    AIOllamaInstaller* installer = [[AIOllamaInstaller alloc] initWithReleaseURL:[NSURL URLWithString:[gMockBase stringByAppendingString:@"/repos/ollama/ollama/releases/latest"]]
        fallbackURL:nil installDirectory:apps workDirectory:tmp verifier:[[FakeVerifier alloc] init]];
    AILocalSetup* setup = [[AILocalSetup alloc] initWithInstaller:installer runtime:runtime];
    AILocalSetupController* controller = [[AILocalSetupController alloc] initWithSetup:setup hardware:hardware catalog:[AILocalModels catalogFromFile:
        [NSURL fileURLWithPath:[gFixtures stringByAppendingPathComponent:@"local-models.json"]]] modelsDirectory:ModelsDirectory(installedModels)];
    controller.libraryURL = [NSURL URLWithString:gMockBase];
    return controller;
}

static NSString* SelectedTag(AILocalSetupController* c) { return c.selectedModel.tag; }

static BOOL Contains(NSString* text, NSString* needle) { return [text containsString:needle]; }

static void Shot(AILocalSetupController* c, NSString* name) {
    if (gShots.length == 0)
        return;
    NSWindow* window = c.window;
    if (getenv("VOK_LIGHT") != NULL)
        window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];         //to look at the window in light mode too
    [c present];
    //the window as tall as what it shows, so that nothing needs scrolling
    NSScrollView* scroll = (NSScrollView*)window.contentView;
    [scroll.documentView layoutSubtreeIfNeeded];
    CGFloat height = MIN(1400, scroll.documentView.frame.size.height);
    [window setContentSize:NSMakeSize(720, height)];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    NSView* frame = window.contentView.superview;
    NSBitmapImageRep* rep = [frame bitmapImageRepForCachingDisplayInRect:frame.bounds];
    [frame cacheDisplayInRect:frame.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[gShots stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES];
    [window setContentSize:NSMakeSize(720, 760)];
}

#pragma mark - The advice

static void TestAdvice(void) {
    //a Mac with 16 GB: the recommended model is selected, and the window says what it will do
    AILocalSetupController* c = MakeController([AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:300], @[], NO);
    CHECK(c.window != nil && [c.window.title isEqualToString:@"Cài AI chạy trên máy"]);
    CHECK([c.machineLabel.stringValue containsString:@"16 GB RAM"] && [c.machineLabel.stringValue containsString:@"Apple M-test"]);
    CHECK([c.overviewLabel.stringValue containsString:@"Qwen 2.5 7B"]);
    CHECK(c.modelPopUp.numberOfItems == 9);                                        //the eight of the list and "other"
    CHECK([SelectedTag(c) isEqualToString:@"qwen2.5:7b"]);
    CHECK([c.modelPopUp.titleOfSelectedItem containsString:@"★ Khuyên dùng"]);
    CHECK([c.modelPopUp.lastItem.title containsString:@"Model khác"]);
    CHECK([c.verdictLabel.stringValue isEqualToString:@"Chạy mượt trên máy này"]);
    CHECK(c.installButton.enabled && [c.installButton.title isEqualToString:@"Cài đặt"] && c.cancelButton.hidden);
    CHECK(c.removeButton.hidden);
    CHECK(c.window.tabbingMode == NSWindowTabbingModeDisallowed);
    CHECK([c.overviewLabel.stringValue hasPrefix:@"Với 16 GB RAM"] && ![c.overviewLabel.stringValue containsString:@"Máy của bạn"]);   //the Mac is described once
    CHECK(c.customField.superview.hidden);                                          //the field for another model is not shown
    CHECK([c.summaryLabel.stringValue containsString:@"Chất lượng ★★★☆☆"] && [c.summaryLabel.stringValue containsString:@"Tiếng Việt: Khá"]);
    CHECK([c.requirementsLabel.stringValue containsString:@"Cần RAM từ 16 GB; máy bạn có 16 GB"]);
    CHECK([c.requirementsLabel.stringValue containsString:@"Dung lượng tải: 4,7 GB"]);
    CHECK([c.problemsLabel.stringValue containsString:@"✓ Máy bạn đủ sức"]);
    NSString* notes = c.notesLabel.stringValue;
    CHECK([notes containsString:@"~/Applications"] && [notes containsString:@"macOS 14"] && [notes containsString:@"207 MB"] && [notes containsString:@"SHA-256"]);
    CHECK([notes containsString:@"127.0.0.1"] && [notes containsString:@"~/.ollama/models"] && [notes containsString:@"20 đến 40 giây"] && [notes containsString:@"tải tiếp"]);
    for (int i = 0; i < AILocalStepCount; i++) {}
    Shot(c, @"01-recommended-16gb");

    //every model of the list has a coloured dot, green, orange or red as the advisor says
    for (NSInteger i = 0; i < 8; i++) {
        NSMenuItem* item = c.modelPopUp.itemArray[i];
        CHECK(item.image != nil && [item.title containsString:@"·"]);
    }

    //a model that is tight: allowed, with the warning
    [c selectModelWithTag:@"gemma3:12b"];
    CHECK([c.verdictLabel.stringValue isEqualToString:@"Chạy được nhưng sát giới hạn"] && c.installButton.enabled);
    CHECK([c.problemsLabel.stringValue containsString:@"⚠️"] && [c.problemsLabel.stringValue containsString:@"phần lớn bộ nhớ"]);
    Shot(c, @"02-tight");
    //a model that does not fit: not allowed, and it says why
    [c selectModelWithTag:@"gemma3:27b"];
    CHECK([c.verdictLabel.stringValue isEqualToString:@"Quá nặng cho máy này"] && !c.installButton.enabled);
    CHECK([c.problemsLabel.stringValue containsString:@"⛔"] && [c.problemsLabel.stringValue containsString:@"32 GB RAM"]);
    Shot(c, @"03-too-big");
    [c selectModelWithTag:@"gemma3:1b"];
    CHECK(c.installButton.enabled && [c.verdictLabel.stringValue isEqualToString:@"Chạy mượt trên máy này"]);

    //8 GB
    c = MakeController([AIHardware appleSiliconWithMemoryGiB:8 freeDiskGiB:300], @[], NO);
    CHECK([SelectedTag(c) isEqualToString:@"qwen2.5:3b"]);
    [c selectModelWithTag:@"qwen2.5:7b"];
    CHECK(!c.installButton.enabled && [c.problemsLabel.stringValue containsString:@"16 GB RAM"] && [c.problemsLabel.stringValue containsString:@"8 GB"]);
    //2 GB: nothing fits
    c = MakeController([AIHardware appleSiliconWithMemoryGiB:2 freeDiskGiB:300], @[], NO);
    CHECK([c.overviewLabel.stringValue containsString:@"trực tuyến"]);
    for (NSInteger i = 0; i < 8; i++) {
        [c.modelPopUp selectItemAtIndex:i];
        [c.modelPopUp sendAction:c.modelPopUp.action to:c.modelPopUp.target];
        CHECK(!c.installButton.enabled);
    }

    //macOS too old for Ollama
    AIHardware* old = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:300];
    old.osMajor = 12;
    c = MakeController(old, @[], NO);
    CHECK(!c.installButton.enabled && [c.problemsLabel.stringValue containsString:@"macOS 14"] && [c.verdictLabel.stringValue isEqualToString:@"Chưa thể cài trên máy này"]);
    //... unless Ollama is already there
    c = MakeController(old, @[], YES);
    CHECK(c.installButton.enabled && [c.notesLabel.stringValue containsString:@"đã có trên máy, không cài lại"]);

    //no room on the disk
    c = MakeController([AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:3], @[], NO);
    CHECK(!c.installButton.enabled && [c.problemsLabel.stringValue containsString:@"Ổ đĩa"] && [c.requirementsLabel.stringValue containsString:@"Ổ đĩa cần trống"]);
    Shot(c, @"04-no-disk");

    //the moment: battery and heat are warnings, not blocks
    AIHardware* busy = [AIHardware appleSiliconWithMemoryGiB:32 freeDiskGiB:300];
    busy.onBattery = YES; busy.thermalState = 2;
    c = MakeController(busy, @[], NO);
    CHECK(c.installButton.enabled && [c.problemsLabel.stringValue containsString:@"pin"] && [c.problemsLabel.stringValue containsString:@"nóng"]);
    Shot(c, @"05-warnings");

    //an Intel Mac
    AIHardware* intel = [AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:300];
    intel.isAppleSilicon = NO;
    c = MakeController(intel, @[], NO);
    CHECK(c.installButton.enabled && [c.problemsLabel.stringValue containsString:@"Intel"] && [c.overviewLabel.stringValue containsString:@"Intel"]);

    //the Mac is looked at again when the user asks
    c = MakeController([AIHardware appleSiliconWithMemoryGiB:8 freeDiskGiB:300], @[], NO);
    [c selectModelWithTag:@"gemma3:4b"];
    CHECK([c.verdictLabel.stringValue isEqualToString:@"Chạy được nhưng sát giới hạn"]);
    c.hardware = [AIHardware appleSiliconWithMemoryGiB:64 freeDiskGiB:300];
    CHECK([c.machineLabel.stringValue containsString:@"64 GB RAM"] && [SelectedTag(c) isEqualToString:@"gemma3:4b"]);        //the choice made stays
    CHECK([c.verdictLabel.stringValue isEqualToString:@"Chạy mượt trên máy này"]);                                          //and is judged for the new Mac
}

static void TestInstalledModel(void) {
    AILocalSetupController* c = MakeController([AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:300], @[@"qwen2.5:7b"], YES);
    [c selectModelWithTag:@"qwen2.5:7b"];
    CHECK([c.modelPopUp.titleOfSelectedItem containsString:@"✓ Đã cài"]);
    CHECK([c.installButton.title isEqualToString:@"Dùng model này"] && c.installButton.enabled);
    CHECK(!c.removeButton.hidden && c.removeButton.enabled);
    CHECK([c.requirementsLabel.stringValue containsString:@"đã có trong máy, không cần tải thêm"]);
    [c selectModelWithTag:@"gemma3:4b"];
    CHECK([c.installButton.title isEqualToString:@"Cài đặt"] && c.removeButton.hidden);
    Shot(c, @"06-installed");
}

#pragma mark - A model typed by the user

static void Type(AILocalSetupController* c, NSString* text) {
    c.customField.stringValue = text;
    [c customModelEntered:c.customField];
}

static void TestCustomModel(void) {
    AILocalSetupController* c = MakeController([AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:300], @[], YES);
    [c.modelPopUp selectItem:c.modelPopUp.lastItem];
    [c.modelPopUp sendAction:c.modelPopUp.action to:c.modelPopUp.target];
    CHECK(!c.customField.superview.hidden && c.selectedModel == nil && !c.installButton.enabled);
    CHECK([c.summaryLabel.stringValue containsString:@"ollama.com/library"]);
    Shot(c, @"07-custom-empty");

    Type(c, @"a b; rm -rf /");
    CHECK(c.selectedModel == nil && !c.installButton.enabled);
    Type(c, @"../../evil");
    CHECK(c.selectedModel == nil && !c.installButton.enabled);
    //a model of the library: its size is looked up, then it is judged like the others
    Type(c, @"gemma3:1b");
    CHECK(SpinUntil(^BOOL { return c.selectedModel != nil; }, 10));
    CHECK([c.selectedModel.tag isEqualToString:@"gemma3:1b"] && c.selectedModel.isCustom && c.selectedModel.bytes == 800007400);
    CHECK(c.installButton.enabled && [c.verdictLabel.stringValue isEqualToString:@"Chạy mượt trên máy này"]);
    CHECK([c.requirementsLabel.stringValue containsString:@"800 MB"] || [c.requirementsLabel.stringValue containsString:@"Dung lượng tải: 800 MB"]);
    Shot(c, @"08-custom-found");
    //it does not exist
    Type(c, @"nothere:9b");
    CHECK(SpinUntil(^BOOL { return c.selectedModel == nil && [c.problemsLabel.stringValue length] == 0; }, 10));
    CHECK(!c.installButton.enabled);
    //from another source: the size is not known, and it says so
    Type(c, @"hf.co/someone/model:Q4_K_M");
    CHECK(SpinUntil(^BOOL { return c.selectedModel != nil; }, 10));
    CHECK(c.installButton.enabled && [c.verdictLabel.stringValue isEqualToString:@"Chưa rõ máy có chạy nổi không"] && [c.problemsLabel.stringValue containsString:@"Chưa biết dung lượng"]);
    //two names typed quickly: the answer of the first one is not used
    Type(c, @"tiny:1b");
    Type(c, @"gemma3:1b");
    CHECK(SpinUntil(^BOOL { return [c.selectedModel.tag isEqualToString:@"gemma3:1b"]; }, 10));
    SpinUntil(^BOOL { return NO; }, 0.4);
    CHECK([c.selectedModel.tag isEqualToString:@"gemma3:1b"]);
    //emptied: nothing is selected
    Type(c, @"   ");
    CHECK(c.selectedModel == nil && !c.installButton.enabled);
}

#pragma mark - Installing

static NSString* StepsText(AILocalSetupController* c) {
    NSMutableString* text = [NSMutableString string];
    for (int i = 0; i < AILocalStepCount; i++)
        [text appendFormat:@"%@ ", [c.setup detailOfStep:(AILocalStep)i]];
    return text;
}

static void TestInstall(void) {
    setenv("FAKE_OLLAMA_MODE", "normal", 1);
    setenv("FAKE_OLLAMA_DELAY", "0.5", 1);
    [AISettings resetToDefaults];
    MockControl(@{@"zip_path": [gFixtures stringByAppendingPathComponent:@"fakeollama.zip"], @"zip_mode": @"good", @"digest_mode": @"good", @"size_mode": @"good", @"no_asset": @NO});
    AILocalSetupController* c = MakeController([AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:300], @[], NO);
    [c.modelPopUp selectItem:c.modelPopUp.lastItem];
    [c.modelPopUp sendAction:c.modelPopUp.action to:c.modelPopUp.target];
    Type(c, @"tiny:1b");
    SpinUntil(^BOOL { return c.selectedModel != nil; }, 10);
    CHECK(c.installButton.enabled && c.selectedModel.bytes == 1000600);
    CHECK(c.resultLabel.hidden);
    CHECK(c.progressSection.hidden);                                              //nothing to show before the first installation

    [c install:nil];
    CHECK(!c.progressSection.hidden);
    CHECK(c.setup.running && !c.installButton.enabled && !c.cancelButton.hidden && c.cancelButton.enabled && !c.modelPopUp.enabled && !c.customField.isEnabled);
    CHECK(!c.refreshButton.enabled);
    SpinUntil(^BOOL { return c.setup.running == NO; }, 120);
    CHECK(c.setup.succeeded);
    CHECK(!c.resultLabel.hidden && [c.resultLabel.stringValue containsString:@"Xong"] && [c.resultLabel.stringValue containsString:@"tiny:1b"]);
    CHECK(c.installButton.enabled && c.cancelButton.hidden && c.modelPopUp.enabled);
    CHECK([AISettings.providerIdentifier isEqualToString:@"ollama"]);
    Shot(c, @"09-installed-ok");
    [c.setup.runtime stopWaiting:5];
    SpinUntil(^BOOL { return !Answers(); }, 8);

    //a model that does not run when asked: the window says which step failed and what to do
    c = MakeController([AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:300], @[], YES);
    [c.modelPopUp selectItem:c.modelPopUp.lastItem];
    [c.modelPopUp sendAction:c.modelPopUp.action to:c.modelPopUp.target];
    Type(c, @"silent:1b");
    SpinUntil(^BOOL { return c.selectedModel != nil; }, 10);
    [AISettings resetToDefaults];
    [c install:nil];
    SpinUntil(^BOOL { return c.setup.running == NO; }, 120);
    CHECK(!c.setup.succeeded && c.setup.failedStep == AILocalStepTest);
    CHECK(Contains(c.resultLabel.stringValue, @"Chưa xong") && c.installButton.enabled);
    CHECK(Contains(StepsText(c), @"chạy thử không được"));
    Shot(c, @"10-failed");

    //cancelled while it downloads
    c = MakeController([AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:300], @[], YES);
    [c.modelPopUp selectItem:c.modelPopUp.lastItem];
    [c.modelPopUp sendAction:c.modelPopUp.action to:c.modelPopUp.target];
    Type(c, @"slow:1b");
    SpinUntil(^BOOL { return c.selectedModel != nil; }, 10);
    [c install:nil];
    SpinUntil(^BOOL { return [c.setup stateOfStep:AILocalStepModel] == AILocalStepRunning && [c.setup fractionOfStep:AILocalStepModel] > 0.05; }, 60);
    Shot(c, @"11-downloading");
    [c cancel:nil];
    CHECK(!c.setup.running && c.setup.wasCancelled);
    CHECK([c.resultLabel.stringValue containsString:@"Đã dừng"] && c.installButton.enabled && c.cancelButton.hidden && c.modelPopUp.enabled);
    [c.setup.runtime stopWaiting:5];
    SpinUntil(^BOOL { return !Answers(); }, 8);

    //install does nothing when the model was refused
    c = MakeController([AIHardware appleSiliconWithMemoryGiB:4 freeDiskGiB:300], @[], NO);
    [c selectModelWithTag:@"qwen2.5:7b"];
    [c install:nil];
    CHECK(!c.setup.running);
}

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 6) { printf("usage: ai_local_ui_test <fixtures> <mock port> <free port> <fake_ollama.py> <work> [shots]\n"); return 2; }
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        gFixtures = @(argv[1]);
        gMockBase = [NSString stringWithFormat:@"http://127.0.0.1:%s", argv[2]];
        gBase = [NSString stringWithFormat:@"http://127.0.0.1:%s", argv[3]];
        gFake = @(argv[4]);
        gWork = @(argv[5]);
        gShots = argc > 6 ? @(argv[6]) : @"";
        setenv("FAKE_OLLAMA_LOG", [gWork stringByAppendingPathComponent:@"ui-starts.log"].UTF8String, 1);
        setenv("FAKE_OLLAMA_MODELS", [gWork stringByAppendingPathComponent:@"ui-models.json"].UTF8String, 1);
        if (gShots.length > 0)
            [[NSFileManager defaultManager] createDirectoryAtPath:gShots withIntermediateDirectories:YES attributes:nil error:nil];
        gRuntimes = [NSMutableArray array];
        [AISettings registerDefaults];
        TestAdvice();
        TestInstalledModel();
        TestCustomModel();
        TestInstall();
        for (AIOllamaRuntime* runtime in gRuntimes)
            [runtime stopWaiting:5];
        [AISettings resetToDefaults];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[NSProcessInfo processInfo].processName];
        printf(failures == 0 ? "ai_local_ui_test: all passed\n" : "ai_local_ui_test: %d FAILED\n", failures);
        return failures == 0 ? 0 : 1;
    }
}
