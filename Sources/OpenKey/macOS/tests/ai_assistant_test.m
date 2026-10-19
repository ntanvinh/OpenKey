// Tests of the AI window (AIAssistant): what it shows when it opens, a request against the fake server (mock_ai_server.py), the
// answer arriving in pieces, stopping, errors, putting the answer into the application, and what is forgotten when it closes.
// Run with run-ai-assistant-test.sh, which starts the fake server.
//
//   ai_assistant_test <port of the fake server>
//
// No real AI service is contacted and no real key is used. The window is shown for a moment; the clipboard of the test is not the
// clipboard of the user.
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "AIAssistant.h"
#import "AIAgentCLI.h"
#import "AIKeychain.h"
#import "AISettings.h"
#import "AIOllamaRuntime.h"
#import "SnippetInserter.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSString* gBase;

static void Spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static BOOL SpinUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [end timeIntervalSinceNow] > 0)
        Spin(0.01);
    return done();
}

static NSDictionary* LastRequest(void) {
    __block NSDictionary* result = nil;
    __block BOOL finished = NO;
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:[gBase stringByAppendingString:@"/_last"]]
                                 completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
        result = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil][@"last"] : nil;
        finished = YES;
    }] resume];
    SpinUntil(^BOOL { return finished; }, 5);
    return result;
}

//the provider "ollama" is pointed at the fake server, so that no key is needed; `model` chooses what the server does
static void UseServer(NSString* model) {
    AIProvider* ollama = [AIProvider providerWithIdentifier:@"ollama"];
    [AISettings setBaseURL:[gBase stringByAppendingString:@"/v1"] forProvider:ollama];
    [AISettings setModel:model forProvider:ollama];
    AISettings.providerIdentifier = @"ollama";
}

static BOOL ScreenIsLocked(void) {
    NSDictionary* session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    return [session[@"CGSSessionScreenIsLocked"] boolValue];
}

static NSString *gFakeOllama, *gFakePort, *gWorkFolder, *gFakeAgent;
static NSString* gPasted;
static int gPastes;

static AIAssistant* MakeAssistant(NSPasteboard* board) {
    SnippetInserter* inserter = [[SnippetInserter alloc] init];
    inserter.pasteboard = board;
    inserter.restoreDelay = 0.05;
    inserter.pasteCommand = ^{ gPastes++; gPasted = [board stringForType:NSPasteboardTypeString]; };
    return [[AIAssistant alloc] initWithInserter:inserter];
}

static void WaitForState(AIAssistant* assistant, AIAssistantState state) {
    SpinUntil(^BOOL { return assistant.state == state; }, 15);
}

#pragma mark - Tests

static void TestOpening(AIAssistant* assistant) {
    printf("-- opening\n");
    UseServer(@"normal");
    [assistant presentWithSelection:@"Xin chào thế giới" application:nil];
    Spin(0.2);
    CHECK(assistant.panel.visible);
    CHECK([assistant.inputView.string isEqualToString:@"\n\nXin chào thế giới"]);       // the instruction goes in front of it
    CHECK(assistant.inputView.selectedRange.location == 0 && assistant.inputView.selectedRange.length == 0);
    CHECK(!assistant.contextLabel.hidden && [assistant.contextLabel.stringValue containsString:@"17 ký tự"]);
    CHECK([assistant.insertButton.title isEqualToString:@"Thay thế vùng chọn"]);
    CHECK([assistant.actionButton.title isEqualToString:@"Tạo"]);
    CHECK(!assistant.insertButton.isEnabled && !assistant.copyButton.isEnabled);       // nothing to use yet
    CHECK(assistant.state == AIAssistantStateIdle && assistant.resultText.length == 0);
    CHECK([assistant.providerPopUp.selectedItem.title isEqualToString:@"Ollama (chạy trên máy)"]);
    CHECK([assistant.infoLabel.stringValue containsString:@"Chạy trên máy"] && [assistant.infoLabel.stringValue containsString:@"normal"]);
    if (!ScreenIsLocked()) {
        CHECK(assistant.panel.keyWindow);
        CHECK([AIAssistant isVisible]);
    }
    [assistant hideAssistant];
    CHECK(!assistant.panel.visible && ![AIAssistant isVisible]);

    //nothing selected
    [assistant presentWithSelection:nil application:nil];
    CHECK(assistant.inputView.string.length == 0 && assistant.contextLabel.hidden);
    CHECK([assistant.insertButton.title isEqualToString:@"Chèn"]);
    [assistant hideAssistant];

    //a selection that is far too long is cut, and the user is told
    [assistant presentWithSelection:[@"" stringByPaddingToLength:50000 withString:@"a" startingAtIndex:0] application:nil];
    CHECK(assistant.inputView.string.length == 30000 + 2 && [assistant.contextLabel.stringValue containsString:@"cắt bớt"]);
    [assistant hideAssistant];
}

static void TestAsking(AIAssistant* assistant) {
    printf("-- asking\n");
    UseServer(@"normal");
    [assistant presentWithSelection:@"Xin chào" application:nil];
    assistant.inputView.string = @"Dịch sang tiếng Anh:\n\nXin chào";
    [assistant ask];
    CHECK(assistant.state == AIAssistantStateGenerating);
    CHECK([assistant.actionButton.title isEqualToString:@"Dừng"]);
    CHECK([assistant.statusLabel.stringValue containsString:@"Đang tạo"]);
    WaitForState(assistant, AIAssistantStateDone);
    CHECK(assistant.state == AIAssistantStateDone);
    CHECK([assistant.resultText isEqualToString:@"Xin chào các bạn ❤️ đẹp"]);
    CHECK([assistant.outputView.string isEqualToString:assistant.resultText]);       // what is written is what is kept
    CHECK([assistant.actionButton.title isEqualToString:@"Tạo lại"]);
    CHECK(assistant.insertButton.isEnabled && assistant.copyButton.isEnabled);
    CHECK([assistant.statusLabel.stringValue containsString:@"Xong"]);

    //what the server got: the text of the box, the instruction of the settings
    NSDictionary* last = LastRequest();
    CHECK([last[@"body"][@"messages"][1][@"content"] isEqualToString:@"Dịch sang tiếng Anh:\n\nXin chào"]);
    CHECK([last[@"body"][@"messages"][0][@"role"] isEqualToString:@"system"] && [last[@"body"][@"model"] isEqualToString:@"normal"]);

    //asking again replaces the answer
    [assistant ask];
    CHECK(assistant.resultText.length == 0 || assistant.state == AIAssistantStateGenerating);
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([assistant.resultText isEqualToString:@"Xin chào các bạn ❤️ đẹp"]);

    //nothing typed: no request
    assistant.inputView.string = @"  \n ";
    NSDictionary* before = LastRequest();
    [assistant ask];
    CHECK(assistant.state == AIAssistantStateDone);                                  // unchanged
    CHECK([assistant.statusLabel.stringValue containsString:@"nhập yêu cầu"]);
    CHECK([LastRequest() isEqualToDictionary:before]);
    [assistant hideAssistant];
}

static void TestUsingTheAnswer(AIAssistant* assistant, NSPasteboard* board) {
    printf("-- using the answer\n");
    UseServer(@"normal");
    [assistant presentWithSelection:@"Xin chào" application:nil];
    assistant.inputView.string = @"Dịch";
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);

    //copy
    [board clearContents];
    [board setString:@"cũ" forType:NSPasteboardTypeString];
    [assistant copyResult];
    CHECK([[board stringForType:NSPasteboardTypeString] isEqualToString:@"Xin chào các bạn ❤️ đẹp"]);
    CHECK([assistant.statusLabel.stringValue containsString:@"Đã sao chép"]);

    //put it in the application: the window goes, the text is pasted as it is, the clipboard comes back
    [board clearContents];
    [board setString:@"của người dùng" forType:NSPasteboardTypeString];
    gPastes = 0; gPasted = nil;
    [assistant.inputView insertText:@" thêm" replacementRange:NSMakeRange(NSNotFound, 0)];      // typing, which the undo history records
    [assistant insertResult];
    CHECK(!assistant.panel.visible);
    Spin(0.3);
    CHECK(gPastes == 1 && [gPasted isEqualToString:@"Xin chào các bạn ❤️ đẹp"]);
    Spin(0.3);
    CHECK([[board stringForType:NSPasteboardTypeString] isEqualToString:@"của người dùng"]);
    //and nothing is kept, not even where ⌘Z would find it
    CHECK(assistant.inputView.string.length == 0 && assistant.outputView.string.length == 0 && assistant.resultText.length == 0);
    CHECK(!assistant.inputView.undoManager.canUndo && !assistant.outputView.undoManager.canUndo);
    CHECK(assistant.state == AIAssistantStateIdle);

    //text that looks like a placeholder is inserted as it is, not replaced
    UseServer(@"normal");
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"x";
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);
    [assistant hideAssistant];

    //nothing to insert before an answer
    [assistant presentWithSelection:nil application:nil];
    gPastes = 0;
    [assistant insertResult];
    Spin(0.2);
    CHECK(gPastes == 0 && assistant.panel.visible);
    [assistant hideAssistant];
}

static void TestStopping(AIAssistant* assistant) {
    printf("-- stopping\n");
    UseServer(@"slow");
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"đếm";
    [assistant ask];
    SpinUntil(^BOOL { return assistant.resultText.length >= 4; }, 10);
    CHECK(assistant.state == AIAssistantStateGenerating && assistant.resultText.length >= 4);
    CHECK(!assistant.insertButton.isEnabled);                       // not while it is still writing
    CHECK(assistant.copyButton.isEnabled);
    [assistant stop];
    NSString* kept = assistant.resultText;
    CHECK(assistant.state == AIAssistantStateDone && [assistant.statusLabel.stringValue containsString:@"Đã dừng"]);
    CHECK([assistant.actionButton.title isEqualToString:@"Tạo lại"] && assistant.insertButton.isEnabled);
    Spin(0.8);
    CHECK([assistant.resultText isEqualToString:kept]);              // nothing more arrives after the stop
    [assistant hideAssistant];

    //closing while it writes stops it too
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"đếm";
    [assistant ask];
    SpinUntil(^BOOL { return assistant.resultText.length >= 2; }, 10);
    [assistant hideAssistant];
    Spin(0.6);
    CHECK(assistant.resultText.length == 0 && assistant.outputView.string.length == 0);
}

static void TestFailures(AIAssistant* assistant) {
    printf("-- failures\n");
    __block int settingsOpened = 0;
    [AIAssistant setSettingsHandler:^{ settingsOpened++; }];

    UseServer(@"missing");
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"hi";
    [assistant ask];
    WaitForState(assistant, AIAssistantStateFailed);
    CHECK(assistant.state == AIAssistantStateFailed);
    CHECK([assistant.statusLabel.stringValue containsString:@"missing"]);
    CHECK(!assistant.settingsButton.hidden);                         // the settings can help: a model that is not there
    CHECK(!assistant.insertButton.isEnabled && [assistant.actionButton.title isEqualToString:@"Tạo"]);

    //the button opens the settings and closes the window
    [assistant.settingsButton performClick:nil];
    CHECK(settingsOpened == 1 && !assistant.panel.visible);

    //a server error that the settings cannot cure
    UseServer(@"boom");
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"hi";
    [assistant ask];
    WaitForState(assistant, AIAssistantStateFailed);
    CHECK(assistant.settingsButton.hidden && [assistant.statusLabel.stringValue containsString:@"500"]);

    //a long message makes the window taller, it is not cut off
    CGFloat heightBefore = assistant.panel.frame.size.height;
    UseServer(@"limited");
    [assistant ask];
    WaitForState(assistant, AIAssistantStateFailed);
    CHECK([assistant.statusLabel.stringValue containsString:@"hạn mức"]);
    NSSize fit = assistant.panel.contentView.fittingSize;
    CHECK(assistant.panel.frame.size.height >= heightBefore - 1);
    (void)fit;
    [assistant hideAssistant];

    //a key that the server refuses: the message names the service and does not repeat the key
    AIKeychain.service = [NSString stringWithFormat:@"vn.io.lssoft.vopenkey.test-%@.ai", [NSUUID UUID].UUIDString];
    [AIKeychain setKey:@"wrong-key-4567890" forProvider:@"openai" error:nil];
    AIProvider* openai = [AIProvider providerWithIdentifier:@"openai"];
    [AISettings setBaseURL:[gBase stringByAppendingString:@"/v1"] forProvider:openai];
    [AISettings setModel:@"normal" forProvider:openai];
    AISettings.providerIdentifier = @"openai";
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"hi";
    [assistant ask];
    WaitForState(assistant, AIAssistantStateFailed);
    CHECK([assistant.statusLabel.stringValue containsString:@"OpenAI"] && ![assistant.statusLabel.stringValue containsString:@"wrong-key-4567890"]);
    CHECK(!assistant.settingsButton.hidden);
    [assistant hideAssistant];
    [AIKeychain removeKeyForProvider:@"openai"];
}

static void TestProviders(AIAssistant* assistant) {
    printf("-- providers\n");
    NSString* original = AIKeychain.service;
    AIKeychain.service = [NSString stringWithFormat:@"vn.io.lssoft.vopenkey.test-%@.ai", [NSUUID UUID].UUIDString];
    __block int settingsOpened = 0;
    [AIAssistant setSettingsHandler:^{ settingsOpened++; }];
    UseServer(@"normal");

    //only what is usable is offered, and the settings
    [assistant presentWithSelection:nil application:nil];
    NSArray* titles = [assistant.providerPopUp.itemTitles copy];
    CHECK([titles containsObject:@"Ollama (chạy trên máy)"] && [titles containsObject:@"LM Studio (chạy trên máy)"]);
    CHECK(![titles containsObject:@"OpenAI (ChatGPT)"]);                 // no key: not offered
    CHECK([titles.lastObject isEqualToString:@"Cài đặt AI…"]);
    [assistant hideAssistant];

    //with a key it is offered, and choosing it is remembered
    [AIKeychain setKey:@"sk-test-1" forProvider:@"openai" error:nil];
    [assistant presentWithSelection:nil application:nil];
    CHECK([assistant.providerPopUp.itemTitles containsObject:@"OpenAI (ChatGPT)"]);
    [assistant.providerPopUp selectItemWithTitle:@"OpenAI (ChatGPT)"];
    [assistant.providerPopUp sendAction:assistant.providerPopUp.action to:assistant.providerPopUp.target];
    CHECK([AISettings.providerIdentifier isEqualToString:@"openai"]);
    CHECK([assistant.infoLabel.stringValue containsString:@"Nội dung gửi tới OpenAI"]);          // what leaves the Mac is said on the window
    CHECK(![assistant.infoLabel.stringValue containsString:@"sk-test-1"]);

    //"Cài đặt AI…" opens the settings and leaves the provider alone
    [assistant.providerPopUp selectItemWithTitle:@"Cài đặt AI…"];
    [assistant.providerPopUp sendAction:assistant.providerPopUp.action to:assistant.providerPopUp.target];
    CHECK(settingsOpened == 1 && [AISettings.providerIdentifier isEqualToString:@"openai"]);
    [AIKeychain removeKeyForProvider:@"openai"];
    AISettings.providerIdentifier = @"ollama";

    //nothing usable at all: the window says so and offers the settings
    for (NSString* identifier in @[@"ollama", @"lmstudio"])
        [AISettings setBaseURL:@"http://api.openai.com/v1" forProvider:[AIProvider providerWithIdentifier:identifier]];
    [assistant presentWithSelection:nil application:nil];
    CHECK([assistant.statusLabel.stringValue containsString:@"Chưa kết nối AI"] && !assistant.settingsButton.hidden);
    CHECK(assistant.providerPopUp.itemTitles.count >= 2 && [assistant.providerPopUp.itemTitles.firstObject isEqualToString:@"Chưa kết nối AI"]);
    assistant.inputView.string = @"hi";
    [assistant ask];
    CHECK(assistant.state == AIAssistantStateFailed);                    // refused before anything was sent
    [assistant hideAssistant];
    for (NSString* identifier in @[@"ollama", @"lmstudio"])
        [AISettings setBaseURL:@"" forProvider:[AIProvider providerWithIdentifier:identifier]];
    AIKeychain.service = original;
}

//a model that runs on this Mac is heavy: when the Mac is busy the window says it will be slow, and only then, and only for such a model
static void TestBusyMac(AIAssistant* assistant) {
    printf("-- a busy Mac\n");
    AIHardware* (^mac)(double) = ^AIHardware*(double load) {
        AIHardware* hardware = [AIHardware appleSiliconWithMemoryGiB:16 freeDiskGiB:100];
        hardware.cpuLoadRatio = load;
        return hardware;
    };
    UseServer(@"normal");
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"Chào";
    assistant.hardwareProvider = ^AIHardware*{ return mac(1.5); };
    [assistant ask];
    CHECK([assistant.statusLabel.stringValue containsString:@"Máy đang bận nên AI chạy trên máy sẽ chậm"]);
    WaitForState(assistant, AIAssistantStateDone);
    assistant.hardwareProvider = ^AIHardware*{ return mac(0.1); };
    [assistant ask];
    CHECK([assistant.statusLabel.stringValue containsString:@"Đang tạo"] && ![assistant.statusLabel.stringValue containsString:@"bận"]);
    WaitForState(assistant, AIAssistantStateDone);
    //a service on the internet does not care how busy this Mac is (the key is in a keychain of the test, deleted after)
    NSString* originalService = AIKeychain.service;
    AIKeychain.service = [NSString stringWithFormat:@"vn.io.lssoft.vopenkey.test-%@.ai", [NSUUID UUID].UUIDString];
    [AIKeychain setKey:@"test-key-123" forProvider:@"openai" error:nil];
    AIProvider* openai = [AIProvider providerWithIdentifier:@"openai"];
    [AISettings setBaseURL:[gBase stringByAppendingString:@"/v1"] forProvider:openai];
    [AISettings setModel:@"normal" forProvider:openai];
    AISettings.providerIdentifier = @"openai";
    [assistant hideAssistant];
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"Chào";
    assistant.hardwareProvider = ^AIHardware*{ return mac(1.5); };
    [assistant ask];
    CHECK([assistant.providerPopUp.titleOfSelectedItem containsString:@"OpenAI"]);
    CHECK([assistant.statusLabel.stringValue containsString:@"Đang tạo"] && ![assistant.statusLabel.stringValue containsString:@"bận"]);
    [assistant stop];
    [AIKeychain removeKeyForProvider:@"openai"];
    AIKeychain.service = originalService;
    [AISettings setBaseURL:@"" forProvider:openai];
    [AISettings setModel:@"" forProvider:openai];
    AISettings.providerIdentifier = @"ollama";
    assistant.hardwareProvider = nil;
    [assistant hideAssistant];
}

//the AI on this Mac that is not running when the window asks: its server is started first (a stand-in, fake_ollama.py)
static void TestLocalServer(AIAssistant* assistant) {
    if (gFakeOllama == nil)
        return;
    printf("-- starting the AI of this Mac\n");
    NSString* log = [gWorkFolder stringByAppendingPathComponent:@"starts.log"];
    setenv("FAKE_OLLAMA_LOG", log.UTF8String, 1);
    setenv("FAKE_OLLAMA_MODELS", [gWorkFolder stringByAppendingPathComponent:@"models.json"].UTF8String, 1);
    setenv("FAKE_OLLAMA_MODE", "normal", 1);
    setenv("FAKE_OLLAMA_DELAY", "1.5", 1);
    NSURL* base = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%@", gFakePort]];
    AIOllamaRuntime* runtime = [[AIOllamaRuntime alloc] initWithBaseURL:base searchPaths:@[gFakeOllama]];
    [AIOllamaRuntime setShared:runtime];
    AIProvider* ollama = [AIProvider providerWithIdentifier:@"ollama"];
    [AISettings setBaseURL:[base.absoluteString stringByAppendingString:@"/v1"] forProvider:ollama];
    [AISettings setModel:@"tiny:1b" forProvider:ollama];
    AISettings.providerIdentifier = @"ollama";
    NSUInteger (^starts)(void) = ^NSUInteger {
        NSString* text = [NSString stringWithContentsOfFile:log encoding:NSUTF8StringEncoding error:nil] ?: @"";
        return [[text componentsSeparatedByString:@"\n"] count] - 1;
    };
    CHECK(starts() == 0 && !runtime.isManaged);

    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"Chào bạn";
    [assistant ask];
    CHECK(assistant.state == AIAssistantStateGenerating);
    SpinUntil(^BOOL { return [assistant.statusLabel.stringValue containsString:@"Đang khởi động AI trên máy"]; }, 5);
    CHECK([assistant.statusLabel.stringValue containsString:@"Đang khởi động AI trên máy"]);     //said when it takes time
    WaitForState(assistant, AIAssistantStateDone);
    CHECK(assistant.state == AIAssistantStateDone && [assistant.resultText isEqualToString:@"Xin chào bạn, mình khỏe."]);
    CHECK(runtime.isManaged && starts() == 1);

    //running: asked again, nothing is started and nothing is said about starting
    [assistant ask];
    CHECK(![assistant.statusLabel.stringValue containsString:@"khởi động"]);
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([assistant.resultText isEqualToString:@"Xin chào bạn, mình khỏe."] && starts() == 1);

    //stopped while the server starts: the question is not sent when it is up
    [runtime stopWaiting:5];
    SpinUntil(^BOOL { return NO; }, 0.5);
    CHECK(!runtime.isManaged);
    [assistant ask];
    SpinUntil(^BOOL { return NO; }, 0.3);
    [assistant stop];
    CHECK(assistant.state != AIAssistantStateGenerating);
    SpinUntil(^BOOL { return NO; }, 3.0);
    CHECK(assistant.state != AIAssistantStateGenerating && assistant.resultText.length == 0);
    [runtime stopWaiting:5];

    //a server that cannot start: the reason is shown
    setenv("FAKE_OLLAMA_MODE", "die", 1);
    [assistant ask];
    WaitForState(assistant, AIAssistantStateFailed);
    CHECK(assistant.state == AIAssistantStateFailed && [assistant.statusLabel.stringValue containsString:@"dừng ngay khi khởi động"]);
    setenv("FAKE_OLLAMA_MODE", "normal", 1);

    //Ollama is not installed and nothing runs: the usual error, with the way to install it
    AIOllamaRuntime* none = [[AIOllamaRuntime alloc] initWithBaseURL:base searchPaths:@[]];
    [AIOllamaRuntime setShared:none];
    [assistant ask];
    WaitForState(assistant, AIAssistantStateFailed);
    CHECK([assistant.statusLabel.stringValue containsString:@"Cài AI chạy trên máy"]);
    //another address than the one of the server of the application: it is left alone
    [AIOllamaRuntime setShared:runtime];
    UseServer(@"normal");
    NSUInteger before = starts();
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);
    CHECK(assistant.state == AIAssistantStateDone && starts() == before && !runtime.isManaged);
    [runtime stopWaiting:5];
    [AIOllamaRuntime setShared:nil];
    [assistant hideAssistant];
}

#pragma mark - Programs on this Mac

static NSString* gAgentLog;

static NSDictionary* AgentLog(void) {
    SpinUntil(^BOOL { return [[NSFileManager defaultManager] fileExistsAtPath:gAgentLog]; }, 3);
    NSData* data = [NSData dataWithContentsOfFile:gAgentLog];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

static void AgentMode(NSString* mode) {
    setenv("FAKE_AGENT_MODE", mode.UTF8String, 1);
    [[NSFileManager defaultManager] removeItemAtPath:gAgentLog error:nil];
}

static NSString* ValueAfterFlag(NSArray* args, NSString* flag) {
    NSUInteger index = [args indexOfObject:flag];
    return index != NSNotFound && index + 1 < args.count ? args[index + 1] : nil;
}

//selects an item of a menu of the window by its title, the way a click does
static void Choose(NSPopUpButton* popUp, NSString* title) {
    [popUp selectItemWithTitle:title];
    [popUp sendAction:popUp.action to:popUp.target];
}

static void TestAgentPrograms(AIAssistant* assistant) {
    if (gFakeAgent == nil || gWorkFolder == nil) {
        printf("-- programs on this Mac: SKIPPED (no fake program given)\n");
        return;
    }
    printf("-- programs on this Mac (Codex, Claude Code, Antigravity)\n");
    NSString* bin = [gWorkFolder stringByAppendingPathComponent:@"agent-bin"];
    [[NSFileManager defaultManager] createDirectoryAtPath:bin withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString* command in @[@"codex", @"claude", @"agy"])
        [[NSFileManager defaultManager] createSymbolicLinkAtPath:[bin stringByAppendingPathComponent:command] withDestinationPath:gFakeAgent error:nil];
    gAgentLog = [gWorkFolder stringByAppendingPathComponent:@"agent-log.json"];
    setenv("FAKE_AGENT_LOG", gAgentLog.UTF8String, 1);
    AgentMode(@"ok");
    [AISettings resetToDefaults];
    __block int settingsOpened = 0;
    [AIAssistant setSettingsHandler:^{ settingsOpened++; }];

    //found programs are offered like any other service; the menus of model and level are only for them
    [AIAgentCLI setSearchDirectoriesForTesting:@[bin]];
    UseServer(@"normal");
    [assistant presentWithSelection:nil application:nil];
    NSArray* titles = assistant.providerPopUp.itemTitles;
    CHECK([titles containsObject:@"Codex CLI (ChatGPT)"] && [titles containsObject:@"Claude Code CLI (Claude)"] && [titles containsObject:@"Antigravity CLI (Gemini)"]);
    CHECK(assistant.modelPopUp.hidden && assistant.effortPopUp.hidden);                    //an ordinary service has no such menus
    [assistant hideAssistant];

    //Codex: the models come from the program, the first choice is a light model at the fast level
    AISettings.providerIdentifier = @"codex-cli";
    [assistant presentWithSelection:@"Xin chào" application:nil];
    CHECK(!assistant.modelPopUp.hidden && !assistant.effortPopUp.hidden);
    SpinUntil(^BOOL { return assistant.modelPopUp.numberOfItems > 1; }, 10);
    CHECK(([assistant.modelPopUp.itemTitles isEqualToArray:@[@"Tự chọn (model nhẹ)", @"Fake-Workhorse", @"Fake-Frontier", @"Fake-Mini", @"Fake-Old-Mini"]]));
    CHECK([assistant.modelPopUp.selectedItem.title isEqualToString:@"Tự chọn (model nhẹ)"]);
    CHECK([assistant.effortPopUp.itemTitles.firstObject isEqualToString:@"Tự động (nhanh)"] && [assistant.effortPopUp.itemTitles.lastObject isEqualToString:@"Mặc định của CLI"]);
    CHECK([assistant.effortPopUp.selectedItem.title isEqualToString:@"Tự động (nhanh)"]);
    CHECK([assistant.infoLabel.stringValue containsString:@"Codex CLI (ChatGPT)"] && [assistant.infoLabel.stringValue containsString:@"Fake-Mini"] && [assistant.infoLabel.stringValue containsString:@"Thấp"]);
    CHECK([assistant.infoLabel.stringValue containsString:@"Nội dung gửi tới"] && [assistant.infoLabel.toolTip containsString:@"đã đăng nhập"]);   //where the text goes, and with whose account

    //another model: its own levels, and what was chosen is saved for the settings too
    AIProvider* codex = [AIProvider providerWithIdentifier:@"codex-cli"];
    Choose(assistant.modelPopUp, @"Fake-Frontier");
    CHECK([[AISettings modelForProvider:codex] isEqualToString:@"fake-frontier"]);
    CHECK([assistant.effortPopUp.itemTitles containsObject:@"Siêu cao"] && [assistant.modelPopUp.selectedItem.title isEqualToString:@"Fake-Frontier"]);
    CHECK([assistant.infoLabel.stringValue containsString:@"Fake-Frontier"]);
    Choose(assistant.effortPopUp, @"Cao");
    CHECK([[AISettings effortForProvider:codex] isEqualToString:@"high"] && [assistant.infoLabel.stringValue containsString:@"Cao"]);
    assistant.inputView.string = @"Dịch sang tiếng Anh:\n\nXin chào";
    [assistant ask];
    CHECK(assistant.state == AIAssistantStateGenerating);
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([assistant.resultText isEqualToString:@"Xin chào, đây là câu trả lời."] && [assistant.statusLabel.stringValue containsString:@"Xong"]);
    NSDictionary* log = AgentLog();
    CHECK([ValueAfterFlag(log[@"args"], @"-m") isEqualToString:@"fake-frontier"] && [ValueAfterFlag(log[@"args"], @"-c") isEqualToString:@"model_reasoning_effort=\"high\""]);
    CHECK([log[@"stdin_head"] containsString:@"Dịch sang tiếng Anh:"]);                     //the request, on the input of the program
    //back to "choose for me": the choices are forgotten, not kept as an empty name
    Choose(assistant.modelPopUp, @"Tự chọn (model nhẹ)");
    Choose(assistant.effortPopUp, @"Tự động (nhanh)");
    CHECK([AISettings effortForProvider:codex] == nil && [[AISettings modelForProvider:codex] isEqualToString:@""]);
    CHECK([assistant.infoLabel.stringValue containsString:@"Fake-Mini"]);
    [assistant hideAssistant];

    //a program that takes a while: the seconds are shown, and stopping works
    AgentMode(@"delayed");
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"Viết thư";
    [assistant ask];
    CHECK([assistant.statusLabel.stringValue containsString:@"Đang tạo"]);
    SpinUntil(^BOOL { return [assistant.statusLabel.stringValue containsString:@"giây"]; }, 5);
    CHECK([assistant.statusLabel.stringValue containsString:@"Codex CLI"] && [assistant.statusLabel.stringValue containsString:@"giây"]);
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([assistant.statusLabel.stringValue containsString:@"Xong"] && ![assistant.statusLabel.stringValue containsString:@"giây"]);
    [assistant ask];                                                                       //asked again, and stopped
    Spin(0.3);
    [assistant stop];
    CHECK([assistant.statusLabel.stringValue containsString:@"Đã dừng"]);
    Spin(2.5);                                                                              //the timer is gone: the message stays
    CHECK([assistant.statusLabel.stringValue containsString:@"Đã dừng"]);
    [assistant hideAssistant];
    AgentMode(@"ok");

    //Claude Code: Haiku is the start, there is no "automatic" model; the answer comes in pieces
    AISettings.providerIdentifier = @"claude-cli";
    [assistant presentWithSelection:nil application:nil];
    CHECK(([assistant.modelPopUp.itemTitles isEqualToArray:@[@"Haiku", @"Sonnet", @"Opus", @"Fable"]]) && [assistant.modelPopUp.selectedItem.title isEqualToString:@"Haiku"]);
    CHECK([assistant.infoLabel.stringValue containsString:@"Claude Code CLI"] && [assistant.infoLabel.stringValue containsString:@"Haiku"]);
    assistant.inputView.string = @"Viết thư";
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);
    log = AgentLog();
    CHECK([assistant.resultText isEqualToString:@"Xin chào, đây là câu trả lời."]);
    CHECK([ValueAfterFlag(log[@"args"], @"--model") isEqualToString:@"haiku"] && [ValueAfterFlag(log[@"args"], @"--effort") isEqualToString:@"low"]);
    Choose(assistant.modelPopUp, @"Opus");
    Choose(assistant.effortPopUp, @"Mặc định của CLI");
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);
    log = AgentLog();
    CHECK([ValueAfterFlag(log[@"args"], @"--model") isEqualToString:@"opus"] && ![log[@"args"] containsObject:@"--effort"]);
    [assistant hideAssistant];

    //Antigravity: it keeps what is asked, and the window says so before anything is asked; a model with levels is one entry
    AISettings.providerIdentifier = @"agy-cli";
    AgentMode(@"ok");
    [assistant presentWithSelection:nil application:nil];
    CHECK([assistant.statusLabel.stringValue containsString:@"Antigravity CLI tự lưu"]);
    SpinUntil(^BOOL { return assistant.modelPopUp.numberOfItems > 1; }, 10);
    CHECK(([assistant.modelPopUp.itemTitles isEqualToArray:@[@"Tự chọn (model nhẹ)", @"Gemini 4 Argon", @"Gemini 3.8 Flash", @"Claude Opus 5.5", @"Claude Sonnet 5.5", @"GPT-OSS 120B", @"A Model Without Levels"]]));
    CHECK([assistant.infoLabel.stringValue containsString:@"Gemini 3.8 Flash"] && [assistant.infoLabel.stringValue containsString:@"Thấp"]);
    assistant.inputView.string = @"Viết thư";
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);
    log = AgentLog();
    CHECK([ValueAfterFlag(log[@"args"], @"--model") isEqualToString:@"gemini-3.8-flash-low"] && ![log[@"args"] containsObject:@"--effort"]);
    Choose(assistant.modelPopUp, @"Claude Sonnet 5.5");
    CHECK(([assistant.effortPopUp.itemTitles containsObject:@"Cao"]));
    Choose(assistant.effortPopUp, @"Cao");
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([ValueAfterFlag(AgentLog()[@"args"], @"--model") isEqualToString:@"claude-sonnet-5-5-high"]);
    //changing the service in the window shows or hides what is only for programs, and the note
    Choose(assistant.providerPopUp, @"Ollama (chạy trên máy)");
    CHECK(assistant.modelPopUp.hidden && assistant.effortPopUp.hidden);
    [assistant hideAssistant];

    //what goes wrong: not signed in (the settings cannot help, the Terminal can), the program gone (the settings can)
    AISettings.providerIdentifier = @"codex-cli";
    AgentMode(@"login");
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"hi";
    [assistant ask];
    WaitForState(assistant, AIAssistantStateFailed);
    CHECK([assistant.statusLabel.stringValue containsString:@"codex login"] && assistant.settingsButton.hidden);
    AgentMode(@"ok");
    NSString* link = [bin stringByAppendingPathComponent:@"codex"];
    NSString* moved = [bin stringByAppendingPathComponent:@"codex-away"];
    [[NSFileManager defaultManager] moveItemAtPath:link toPath:moved error:nil];
    [assistant ask];                                                                        //the window was open when the program went away
    WaitForState(assistant, AIAssistantStateFailed);
    CHECK([assistant.statusLabel.stringValue containsString:@"codex"] && !assistant.settingsButton.hidden);
    CHECK([assistant.statusLabel.stringValue containsString:@"npm install -g @openai/codex"]);
    [assistant.settingsButton performClick:nil];
    CHECK(settingsOpened == 1 && !assistant.panel.visible);
    [[NSFileManager defaultManager] moveItemAtPath:moved toPath:link error:nil];

    //a program that is not installed is not offered
    [AIAgentCLI setSearchDirectoriesForTesting:@[]];
    UseServer(@"normal");
    [assistant presentWithSelection:nil application:nil];
    CHECK(![assistant.providerPopUp.itemTitles containsObject:@"Codex CLI (ChatGPT)"] && assistant.modelPopUp.hidden);
    [assistant hideAssistant];
    [AISettings resetToDefaults];
}

static void TestEscape(AIAssistant* assistant) {
    printf("-- escape\n");
    UseServer(@"slow");
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"đếm";
    [assistant ask];
    SpinUntil(^BOOL { return assistant.resultText.length >= 2; }, 10);
    [assistant.panel cancelOperation:nil];                               // the first ⎋ stops
    CHECK(assistant.panel.visible && assistant.state != AIAssistantStateGenerating);
    [assistant.panel cancelOperation:nil];                               // the next one closes
    CHECK(!assistant.panel.visible);
    //an empty window closes at once
    [assistant presentWithSelection:nil application:nil];
    [assistant.panel cancelOperation:nil];
    CHECK(!assistant.panel.visible);
}

int main(int argc, char** argv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (argc < 2) {
            printf("usage: ai_assistant_test <port>\n");
            return 2;
        }
        gBase = [NSString stringWithFormat:@"http://127.0.0.1:%s", argv[1]];
        if (argc >= 5) {                                                     //the stand-in for Ollama, a free port and a folder
            gFakeOllama = @(argv[2]);
            gFakePort = @(argv[3]);
            gWorkFolder = @(argv[4]);
        }
        if (argc >= 6)
            gFakeAgent = @(argv[5]);                                        //the stand-in for Codex, Claude Code and Antigravity
        [AIAgentCLI setSearchDirectoriesForTesting:@[]];                     //the programs of the Mac that runs the test are not used
        NSPasteboard* board = [NSPasteboard pasteboardWithUniqueName];
        AIAssistant* assistant = MakeAssistant(board);
        __block int boundaries = 0;
        [AIAssistant setTypingBoundaryHandler:^{ boundaries++; }];

        TestOpening(assistant);
        CHECK(boundaries >= 2);                                              // told when it opened and closed
        TestAsking(assistant);
        TestUsingTheAnswer(assistant, board);
        TestStopping(assistant);
        TestFailures(assistant);
        TestProviders(assistant);
        TestBusyMac(assistant);
        TestLocalServer(assistant);
        TestAgentPrograms(assistant);
        TestEscape(assistant);

        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[NSProcessInfo processInfo].processName];
        printf(failures ? "\n%d FAILURES\n" : "ALL OK\n", failures);
    }
    return failures ? 1 : 0;
}
