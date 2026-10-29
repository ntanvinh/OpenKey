// Tests of the AI window (AIAssistant): what it shows when it opens, a request against the fake server (mock_ai_server.py), the
// answer arriving in pieces, stopping, errors, putting the answer into the application, and what is forgotten when it closes.
// Run with run-ai-assistant-test.sh, which starts the fake server.
//
//   ai_assistant_test <port of the fake server>
//
// No real AI service is contacted and no real key is used. The window is shown for a moment; the clipboard of the test is not the
// clipboard of the user.
//
// VOK_PRESETS_JSON=<engine/ai/ai-presets.json> also compares that file (which the Windows program reads) with AIPresets.m.
// VOK_ONLY=presets runs only the part about the ready-made conversions. VOK_SNAPSHOT_DIR=<folder> also writes pictures of the window
// there (light and dark). Never run two copies of this test at once: they share one defaults domain, and each would send its requests
// to the fake server of the other.
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "AIAssistant.h"
#import "AIAgentCLI.h"
#import "AIPresets.h"
#import "AIProgress.h"
#import "AILightbox.h"
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
static NSData* gPastedImage;
static int gPastes;

//A clipboard that rejects writes, so a failed copy must keep the answer available.
@interface RejectingPasteboard : NSObject
@end
@implementation RejectingPasteboard
-(NSInteger)clearContents { return 0; }
-(BOOL)setString:(NSString*)string forType:(NSPasteboardType)type { return NO; }
-(BOOL)writeObjects:(NSArray<id<NSPasteboardWriting>>*)objects { return NO; }
@end

static AIAssistant* MakeAssistant(NSPasteboard* board) {
    SnippetInserter* inserter = [[SnippetInserter alloc] init];
    inserter.pasteboard = board;
    inserter.restoreDelay = 0.05;
    inserter.pasteCommand = ^{ gPastes++; gPasted = [board stringForType:NSPasteboardTypeString]; gPastedImage = [board dataForType:NSPasteboardTypePNG]; };
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
    CHECK([assistant.copyButton.title isEqualToString:@"Sao chép và đóng"]);
    CHECK(!assistant.insertButton.isEnabled && !assistant.copyButton.isEnabled);       // nothing to use yet
    CHECK(assistant.state == AIAssistantStateIdle && assistant.resultText.length == 0);
    CHECK([assistant.providerPopUp.selectedItem.title isEqualToString:@"Ollama (chạy trên máy)"]);
    CHECK([assistant.infoLabel.stringValue containsString:@"Chạy trên máy"] && [assistant.infoLabel.stringValue containsString:@"normal"]);
    if (!ScreenIsLocked() && !assistant.offscreenForTesting) {          //VOK_UI_VISIBLE=1: the window is really shown and takes the keys
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

//A picture of the window for somebody to look at (VOK_SNAPSHOT_DIR): drawn from its views, not from the screen, on a grey ground, as
//the blur behind it cannot be drawn without showing it
static void Snapshot(AIAssistant* assistant, NSString* name, BOOL dark) {
    const char* folder = getenv("VOK_SNAPSHOT_DIR");
    if (folder == NULL || folder[0] == 0)
        return;
    NSView* content = assistant.panel.contentView;
    assistant.panel.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    [content layoutSubtreeIfNeeded];
    NSBitmapImageRep* cached = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
    //drawn explicitly in this appearance: the one a previous picture left current would colour the text of the next one
    [content.effectiveAppearance performAsCurrentDrawingAppearance:^{ [content cacheDisplayInRect:content.bounds toBitmapImageRep:cached]; }];
    NSBitmapImageRep* out = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:cached.pixelsWide pixelsHigh:cached.pixelsHigh
                                                                bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                               colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    out.size = content.bounds.size;
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:out]];
    [[NSColor colorWithSRGBRed:dark ? 0.22 : 0.93 green:dark ? 0.22 : 0.93 blue:dark ? 0.23 : 0.93 alpha:1] setFill];
    NSRectFill(NSMakeRect(0, 0, content.bounds.size.width, content.bounds.size.height));
    [cached drawInRect:NSMakeRect(0, 0, content.bounds.size.width, content.bounds.size.height)];
    [NSGraphicsContext restoreGraphicsState];
    NSString* file = [NSString stringWithFormat:@"%@-%@.png", name, dark ? @"dark" : @"light"];
    [[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[@(folder) stringByAppendingPathComponent:file] atomically:YES];
    assistant.panel.appearance = nil;
}

//The Windows program reads its conversions from engine/ai/ai-presets.json; this program has the same words in AIPresets.m. A word changed in one
//and not in the other would make the two programs ask the AI different things, so the file is compared with the code (VOK_PRESETS_JSON).
static void TestPresetsFileMatches(void) {
    const char* path = getenv("VOK_PRESETS_JSON");
    if (path == NULL)
        return;
    printf("-- the file of the presets of the Windows program\n");
    NSData* data = [NSData dataWithContentsOfFile:@(path)];
    NSDictionary* file = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    CHECK(file != nil);
    NSArray* list = file[@"presets"];
    NSArray<AIPreset*>* all = [AIPresets all];
    CHECK(list.count == all.count);
    for (NSUInteger i = 0; i < list.count && i < all.count; i++) {
        CHECK([list[i][@"id"] isEqualToString:all[i].identifier]);
        CHECK([list[i][@"title"] isEqualToString:all[i].title]);
        CHECK([list[i][@"summary"] isEqualToString:all[i].summary]);
        CHECK([list[i][@"instruction"] isEqualToString:all[i].instruction]);
        CHECK([list[i][@"poem"] boolValue] == all[i].isPoem);
        //the request: the template of the file with the instruction and the text put in is the prompt of this program
        NSString* made = [[file[@"promptTemplate"] stringByReplacingOccurrencesOfString:@"{instruction}" withString:all[i].instruction]
                          stringByReplacingOccurrencesOfString:@"{text}" withString:@"xin chao"];
        CHECK([made isEqualToString:[AIPresets promptForPreset:all[i] draft:@"  xin chao \n"]]);
    }
}

//the ready-made conversions: the buttons under the box, what one click sends, when it is lit and when it goes out
static void TestPresets(AIAssistant* assistant) {
    printf("-- presets\n");
    UseServer(@"normal");
    NSArray<AIPreset*>* all = [AIPresets all];

    //the list itself: one button each, nothing repeated, no empty instruction, the poems are the ones that say so
    CHECK(all.count == 14);
    NSMutableSet* identifiers = [NSMutableSet set];
    NSMutableSet* titles = [NSMutableSet set];
    NSMutableArray* poems = [NSMutableArray array];
    for (AIPreset* preset in all) {
        [identifiers addObject:preset.identifier];
        [titles addObject:preset.title];
        CHECK(preset.title.length > 0 && preset.summary.length > 0 && preset.instruction.length > 20);
        if (preset.isPoem)
            [poems addObject:preset.identifier];
        CHECK([AIPresets presetWithIdentifier:preset.identifier] == preset);
    }
    CHECK(identifiers.count == all.count && titles.count == all.count);
    CHECK([poems isEqualToArray:@[@"poetry", @"rhyme", @"lucBat", @"tuTuyet"]]);
    CHECK([AIPresets presetWithIdentifier:@"nope"] == nil);
    NSString* sample = [AIPresets promptForPreset:[AIPresets presetWithIdentifier:@"polite"] draft:@"\n\n  xin chào anh  \n"];
    CHECK([sample hasPrefix:[AIPresets presetWithIdentifier:@"polite"].instruction]);
    CHECK([sample hasSuffix:@"\nxin chào anh"]);                                    //the text, trimmed, comes last
    CHECK([sample containsString:@"không phải yêu cầu"]);

    //an empty box: the buttons are there, off; a click (not possible with the mouse, possible from code) only says what is missing
    [assistant presentWithSelection:nil application:nil];
    CHECK(assistant.presetButtons.count == all.count && assistant.activePreset == nil);
    for (NSUInteger i = 0; i < all.count; i++) {
        NSButton* button = assistant.presetButtons[i];
        CHECK([button.title isEqualToString:all[i].title] && !button.isEnabled && button.state == NSControlStateValueOff);
        CHECK(button.toolTip.length > 0 && [button.accessibilityLabel hasPrefix:@"Chuyển đổi: "]);
    }
    [assistant applyPresetWithIdentifier:@"fix"];
    CHECK(assistant.state == AIAssistantStateIdle && assistant.activePreset == nil);
    CHECK([assistant.statusLabel.stringValue containsString:@"chọn đoạn văn"]);
    [assistant ask];                                                                 //⌘↩ on an empty box says it too
    CHECK(assistant.state == AIAssistantStateIdle && [assistant.statusLabel.stringValue containsString:@"Hãy nhập"]);

    //typing a text turns them on (the notification is what the text view sends when the user types)
    [assistant.inputView insertText:@"xin chao ban, toi muon xin nghi phep" replacementRange:NSMakeRange(NSNotFound, 0)];
    for (NSButton* button in assistant.presetButtons)
        CHECK(button.isEnabled);
    CHECK(assistant.statusLabel.stringValue.length == 0);                            //the request for a text is taken back

    Snapshot(assistant, @"ai-presets-typed", NO);
    Snapshot(assistant, @"ai-presets-typed", YES);
    //the buttons fit in the width of the window, in rows, without one over another
    [assistant.panel.contentView layoutSubtreeIfNeeded];
    NSView* strip = assistant.presetButtons[0].superview.superview;
    NSMutableSet* rows = [NSMutableSet set];
    for (NSButton* button in assistant.presetButtons) {
        //the alignment rect is what the layout works with: the bezel and shadow of a button stand outside it
        NSRect frame = [button.superview convertRect:[button alignmentRectForFrame:button.frame] toView:strip];
        //inside the strip, and as wide as the button wants to be: a row that is too long squeezes its last buttons to a sliver
        BOOL inside = NSMaxX(frame) <= strip.bounds.size.width + 0.5 && NSMinX(frame) >= -0.5 && frame.size.width >= button.intrinsicContentSize.width - 0.5;
        if (!inside)
            printf("   %s is at %s, the strip is %.0f wide\n", button.title.UTF8String, NSStringFromRect(frame).UTF8String, strip.bounds.size.width);
        CHECK(inside);
        [rows addObject:@((NSInteger)round(NSMidY(frame)))];
    }
    CHECK(rows.count >= 2 && rows.count <= 3);

    //one click: chosen, lit, and asked at once. What the server gets is the instruction and the text; the box is left as it was.
    NSString* typed = assistant.inputView.string;
    NSButton* polite = assistant.presetButtons[1];
    CHECK([polite.title isEqualToString:@"Lịch sự"]);
    [polite performClick:nil];
    CHECK(assistant.state == AIAssistantStateGenerating && [assistant.activePreset.identifier isEqualToString:@"polite"]);
    CHECK(polite.state == NSControlStateValueOn);
    for (NSButton* button in assistant.presetButtons)
        CHECK(!button.isEnabled);                                                  //while the answer is on its way
    [assistant applyPresetWithIdentifier:@"fix"];                                  //ignored meanwhile
    CHECK([assistant.activePreset.identifier isEqualToString:@"polite"]);
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([assistant.resultText isEqualToString:@"Xin chào các bạn ❤️ đẹp"]);
    CHECK([assistant.inputView.string isEqualToString:typed]);
    NSString* expected = [AIPresets promptForPreset:[AIPresets presetWithIdentifier:@"polite"] draft:typed];
    CHECK([LastRequest()[@"body"][@"messages"][1][@"content"] isEqualToString:expected]);
    CHECK([[LastRequest()[@"body"][@"messages"][1][@"content"] description] containsString:@"xin nghi phep"]);
    CHECK([assistant.statusLabel.stringValue isEqualToString:@"Xong. ⇧⌘↩ để dùng kết quả."]);   //not a poem: no warning
    CHECK(polite.state == NSControlStateValueOn && polite.isEnabled);
    Snapshot(assistant, @"ai-presets-answer", NO);
    Snapshot(assistant, @"ai-presets-answer", YES);
    for (NSUInteger i = 0; i < all.count; i++)
        if (i != 1)
            CHECK(assistant.presetButtons[i].state == NSControlStateValueOff && assistant.presetButtons[i].isEnabled);

    //"Tạo lại" asks the same conversion again, even with the text changed by the program
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([LastRequest()[@"body"][@"messages"][1][@"content"] isEqualToString:expected]);

    //another conversion takes over
    [assistant applyPresetWithIdentifier:@"toEnglish"];
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([assistant.activePreset.identifier isEqualToString:@"toEnglish"] && polite.state == NSControlStateValueOff);
    CHECK([[LastRequest()[@"body"][@"messages"][1][@"content"] description] hasPrefix:@"Dịch sang tiếng Anh"]);

    //the user edits the text: no conversion applies any more, and what is sent is the box as it is
    [assistant.inputView insertText:@"!" replacementRange:NSMakeRange(assistant.inputView.string.length, 0)];
    CHECK(assistant.activePreset == nil);
    for (NSButton* button in assistant.presetButtons)
        CHECK(button.state == NSControlStateValueOff);
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([LastRequest()[@"body"][@"messages"][1][@"content"] isEqualToString:assistant.inputView.string]);

    //a poem: the answer says its rhymes were not checked
    [assistant applyPresetWithIdentifier:@"lucBat"];
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([assistant.statusLabel.stringValue containsString:@"chưa được kiểm tra"]);
    CHECK([[LastRequest()[@"body"][@"messages"][1][@"content"] description] containsString:@"Luật lục bát"]);
    [assistant hideAssistant];
    CHECK(assistant.activePreset == nil);

    //a selection from another application: it is in the box after a blank line, and it is what gets converted
    [assistant presentWithSelection:@"Xin chào" application:nil];
    for (NSButton* button in assistant.presetButtons)
        CHECK(button.isEnabled);
    [assistant applyPresetWithIdentifier:@"toEnglish"];
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([LastRequest()[@"body"][@"messages"][1][@"content"] isEqualToString:
           [AIPresets promptForPreset:[AIPresets presetWithIdentifier:@"toEnglish"] draft:@"Xin chào"]]);
    CHECK([assistant.insertButton.title isEqualToString:@"Thay thế vùng chọn"]);       //the answer replaces the selection
    [assistant hideAssistant];

    //opening the window again: nothing is chosen
    [assistant presentWithSelection:@"Một đoạn" application:nil];
    CHECK(assistant.activePreset == nil);
    for (NSButton* button in assistant.presetButtons)
        CHECK(button.state == NSControlStateValueOff);
    [assistant hideAssistant];
}

static void TestUsingTheAnswer(AIAssistant* assistant, NSPasteboard* board) {
    printf("-- using the answer\n");
    UseServer(@"normal");
    [assistant presentWithSelection:@"Xin chào" application:nil];
    assistant.inputView.string = @"Dịch";
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);

    //A rejected clipboard write preserves the window and the answer for retry.
    SnippetInserter* inserter = [assistant valueForKey:@"inserter"];
    inserter.pasteboard = (NSPasteboard*)[[RejectingPasteboard alloc] init];
    [assistant.copyButton performClick:nil];
    CHECK(assistant.panel.visible && assistant.state == AIAssistantStateDone);
    CHECK([assistant.resultText isEqualToString:@"Xin chào các bạn ❤️ đẹp"]);
    CHECK([assistant.statusLabel.stringValue containsString:@"Không sao chép được"]);
    inserter.pasteboard = board;

    //copy
    [board clearContents];
    [board setString:@"cũ" forType:NSPasteboardTypeString];
    [assistant.copyButton performClick:nil];
    CHECK([[board stringForType:NSPasteboardTypeString] isEqualToString:@"Xin chào các bạn ❤️ đẹp"]);
    CHECK(!assistant.panel.visible && assistant.state == AIAssistantStateIdle);
    CHECK(assistant.resultText.length == 0 && assistant.inputView.string.length == 0 && assistant.outputView.string.length == 0);
    CHECK(!assistant.inputView.undoManager.canUndo && !assistant.outputView.undoManager.canUndo);
    Spin(0.2);
    CHECK([[board stringForType:NSPasteboardTypeString] isEqualToString:@"Xin chào các bạn ❤️ đẹp"]);

    [assistant presentWithSelection:@"Xin chào" application:nil];
    assistant.inputView.string = @"Dịch";
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);
    NSEvent* copyKey = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                                 modifierFlags:NSEventModifierFlagCommand | NSEventModifierFlagShift
                                     timestamp:0 windowNumber:assistant.panel.windowNumber context:nil
                                    characters:@"C" charactersIgnoringModifiers:@"c" isARepeat:NO keyCode:8];
    CHECK([assistant.panel performKeyEquivalent:copyKey]);
    CHECK(!assistant.panel.visible);
    CHECK([[board stringForType:NSPasteboardTypeString] isEqualToString:@"Xin chào các bạn ❤️ đẹp"]);

    [assistant presentWithSelection:@"Xin chào" application:nil];
    assistant.inputView.string = @"Dịch";
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);

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
    CHECK(!assistant.glowing && !((AIShimmerLabel*)assistant.progressLabel).shimmering);        //the wait is over: nothing keeps moving
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
    CHECK([assistant.progressLabel.stringValue containsString:@"Codex CLI (ChatGPT)"]);                       //who was asked, in the place of the answer
    SpinUntil(^BOOL { return [assistant.statusLabel.stringValue containsString:@"giây"]; }, 5);
    CHECK([assistant.statusLabel.stringValue containsString:@"Đã chờ"] && [assistant.statusLabel.stringValue containsString:@"giây"]);
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([assistant.statusLabel.stringValue containsString:@"Xong"] && ![assistant.statusLabel.stringValue containsString:@"giây"]);
    [assistant ask];                                                                       //asked again, and stopped
    Spin(0.3);
    [assistant stop];
    CHECK([assistant.statusLabel.stringValue containsString:@"Đã dừng"]);
    Spin(2.5);                                                                              //the timer is gone: the message stays
    CHECK([assistant.statusLabel.stringValue containsString:@"Đã dừng"]);
    [assistant hideAssistant];

    //a long wait at a high level: the window offers to ask again at the lowest one, which is what makes it fast
    AgentMode(@"delayed");
    assistant.slowHintDelay = 1;
    [AISettings setEffort:@"medium" forProvider:codex];                                    //the light model of the fake has no "high"
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"Viết thư";
    [assistant ask];
    CHECK(assistant.speedButton.hidden);                                                    //not at once
    SpinUntil(^BOOL { return !assistant.speedButton.hidden; }, 5);
    CHECK(!assistant.speedButton.hidden && [assistant.speedButton.title containsString:@"Thấp"]);
    CHECK([assistant.statusLabel.stringValue containsString:@"Mức “Vừa”"]);                 //the cause, in the words of the menu
    [assistant.speedButton performClick:nil];
    CHECK([AISettings effortForProvider:codex] == nil && [assistant.effortPopUp.selectedItem.title isEqualToString:@"Tự động (nhanh)"]);
    CHECK(assistant.state == AIAssistantStateGenerating && assistant.speedButton.hidden);   //asked again, at once
    WaitForState(assistant, AIAssistantStateDone);
    CHECK([ValueAfterFlag(AgentLog()[@"args"], @"-c") isEqualToString:@"model_reasoning_effort=\"low\""]);
    CHECK([assistant.resultText isEqualToString:@"Xin chào, đây là câu trả lời."]);
    //at the lowest level there is nothing to offer
    [assistant ask];
    Spin(1.6);
    CHECK(assistant.speedButton.hidden && ![assistant.statusLabel.stringValue containsString:@"Mức “"]);
    WaitForState(assistant, AIAssistantStateDone);
    assistant.slowHintDelay = 8;
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

#pragma mark - Waiting

static void TestProgressText(void) {
    printf("-- sentences of the wait\n");
    NSString* first = [AIProgressText messageAfterSeconds:0 provider:@"Codex CLI"];
    CHECK([first containsString:@"Codex CLI"] && [first containsString:@"gửi"]);                      //at first: what is happening, and to whom
    CHECK([[AIProgressText messageAfterSeconds:-5 provider:@"X"] isEqualToString:[AIProgressText messageAfterSeconds:0 provider:@"X"]]);
    CHECK([[AIProgressText messageAfterSeconds:3 provider:@"X"] isEqualToString:@"AI đang suy nghĩ…"]);
    CHECK(![[AIProgressText messageAfterSeconds:3 provider:@"X"] isEqualToString:[AIProgressText messageAfterSeconds:6 provider:@"X"]]);      //it changes: never a window that looks stuck
    CHECK([[AIProgressText messageAfterSeconds:9 provider:@"X"] containsString:@"kiên nhẫn"]);
    CHECK([[AIProgressText messageAfterSeconds:18 provider:@"X"] containsString:@"Sắp có kết quả"]);
    CHECK([[AIProgressText messageAfterSeconds:37 provider:@"Antigravity CLI"] containsString:@"không bị treo"] &&
          [[AIProgressText messageAfterSeconds:37 provider:@"Antigravity CLI"] containsString:@"Antigravity CLI"]);                       //a long wait: it is not the application
    CHECK([[AIProgressText messageAfterSeconds:75 provider:@"X"] containsString:@"Dừng"]);                                              //and it can be stopped
    NSString* previous = nil;
    int changes = 0;
    for (NSInteger seconds = 0; seconds <= 600; seconds++) {
        NSString* text = [AIProgressText messageAfterSeconds:seconds provider:@"Codex CLI (ChatGPT)"];
        CHECK(text.length > 0 && ![text containsString:@"%@"]);
        if (previous != nil && ![text isEqualToString:previous])
            changes++;
        previous = text;
    }
    CHECK(changes >= 100);                                                                                  //still moving after ten minutes
    CHECK([[AIProgressText elapsedAfterSeconds:0] isEqualToString:@"Đã chờ 0 giây"]);
    CHECK([[AIProgressText elapsedAfterSeconds:7] isEqualToString:@"Đã chờ 7 giây"]);
    CHECK([[AIProgressText elapsedAfterSeconds:65] isEqualToString:@"Đã chờ 1 phút 05 giây"]);
}

static void TestWaiting(AIAssistant* assistant) {
    printf("-- the wait is shown\n");
    __block int settingsOpened = 0;
    [AIAssistant setSettingsHandler:^{ settingsOpened++; }];
    UseServer(@"wait");                                                                                       //nothing for 3.6 s
    [assistant presentWithSelection:nil application:nil];
    AIShimmerLabel* progress = (AIShimmerLabel*)assistant.progressLabel;
    CHECK(!assistant.glowing && !progress.shimmering && [progress.stringValue isEqualToString:@"Câu trả lời của AI sẽ hiện ở đây."]);
    assistant.inputView.string = @"hi";
    [assistant ask];
    //at once: the light runs, the words shimmer and say who was asked; the first words of the status are the old ones
    CHECK(assistant.glowing && progress.shimmering);
    CHECK([progress.stringValue containsString:@"Ollama"] && [assistant.statusLabel.stringValue containsString:@"Đang tạo"]);
    CHECK(!progress.hidden && assistant.speedButton.hidden);
    //it goes on: the sentence changes, the seconds are counted
    SpinUntil(^BOOL { return ![progress.stringValue containsString:@"gửi yêu cầu"]; }, 5);
    CHECK([progress.stringValue isEqualToString:@"AI đang suy nghĩ…"] && assistant.glowing);
    SpinUntil(^BOOL { return [assistant.statusLabel.stringValue containsString:@"Đã chờ"]; }, 5);
    CHECK([assistant.statusLabel.stringValue containsString:@"giây"]);
    //the gear stays there while it waits
    CHECK(!assistant.openSettingsButton.hidden && assistant.openSettingsButton.enabled);
    WaitForState(assistant, AIAssistantStateDone);
    //over: everything is still, the place of the answer is itself again, and the answer is where the sentences were
    CHECK(!assistant.glowing && !progress.shimmering && [progress.stringValue isEqualToString:@"Câu trả lời của AI sẽ hiện ở đây."]);
    CHECK(progress.hidden && assistant.speedButton.hidden && [assistant.statusLabel.stringValue containsString:@"Xong"]);
    CHECK(![assistant.statusLabel.stringValue containsString:@"giây"]);
    [assistant hideAssistant];

    //stopped, an error, and the window closed all end it too
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"hi";
    [assistant ask];
    CHECK(assistant.glowing);
    [assistant stop];
    CHECK(!assistant.glowing && !progress.shimmering && [progress.stringValue isEqualToString:@"Câu trả lời của AI sẽ hiện ở đây."]);
    UseServer(@"missing");
    [assistant ask];
    WaitForState(assistant, AIAssistantStateFailed);
    CHECK(!assistant.glowing && !progress.shimmering);
    UseServer(@"wait");
    [assistant ask];
    CHECK(assistant.glowing);
    [assistant hideAssistant];
    CHECK(!assistant.glowing && !progress.shimmering);
    Spin(0.5);

    //the gear opens the settings, closes the window, and is there when nothing is going on
    [assistant presentWithSelection:nil application:nil];
    CHECK(!assistant.openSettingsButton.hidden && [assistant.openSettingsButton.toolTip containsString:@"Cài đặt AI"]);
    CHECK(assistant.settingsButton.hidden);                                                                   //the button of the messages is not the gear
    [assistant.openSettingsButton performClick:nil];
    CHECK(settingsOpened == 1 && !assistant.panel.visible);
    //also while it waits: the request is stopped with the window
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"hi";
    [assistant ask];
    [assistant.openSettingsButton performClick:nil];
    CHECK(settingsOpened == 2 && !assistant.panel.visible && !assistant.glowing && assistant.state == AIAssistantStateIdle);
    Spin(0.3);
}

#pragma mark - Pictures

static void TestImages(AIAssistant* assistant, NSPasteboard* board) {
    if (gFakeAgent == nil || gWorkFolder == nil) {
        printf("-- pictures: SKIPPED (no fake program given)\n");
        return;
    }
    printf("-- pictures (Codex CLI)\n");
    NSString* bin = [gWorkFolder stringByAppendingPathComponent:@"agent-bin"];
    [[NSFileManager defaultManager] createDirectoryAtPath:bin withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString* command in @[@"codex", @"claude", @"agy"])
        [[NSFileManager defaultManager] createSymbolicLinkAtPath:[bin stringByAppendingPathComponent:command] withDestinationPath:gFakeAgent error:nil];
    gAgentLog = [gWorkFolder stringByAppendingPathComponent:@"agent-log.json"];
    setenv("FAKE_AGENT_LOG", gAgentLog.UTF8String, 1);
    NSString* home = [gWorkFolder stringByAppendingPathComponent:@"codexhome-ui"];
    setenv("CODEX_HOME", home.UTF8String, 1);
    AgentMode(@"image");
    [AISettings resetToDefaults];
    [AIAgentCLI setSearchDirectoriesForTesting:@[bin]];

    //the button is there for every AI, and off for those that cannot make a picture, with the reason
    UseServer(@"normal");
    [assistant presentWithSelection:nil application:nil];
    CHECK(assistant.imageButton != nil && !assistant.imageButton.hidden && !assistant.imageButton.enabled);
    CHECK([assistant.imageButton.toolTip containsString:@"Codex CLI"]);
    assistant.inputView.string = @"con mèo";
    [assistant askForImage];                                                                    //not by the button, but the key
    CHECK(assistant.state == AIAssistantStateIdle && [assistant.statusLabel.stringValue containsString:@"Chỉ tạo được ảnh khi dùng Codex CLI"]);
    [assistant hideAssistant];
    for (NSString* other in @[@"claude-cli", @"agy-cli"]) {
        AISettings.providerIdentifier = other;
        [assistant presentWithSelection:nil application:nil];
        CHECK(!assistant.imageButton.enabled);
        [assistant hideAssistant];
    }

    //Codex: on; the status of the window follows the choice of the AI in the window
    AISettings.providerIdentifier = @"codex-cli";
    [assistant presentWithSelection:nil application:nil];
    CHECK(assistant.imageButton.enabled && [assistant.imageButton.toolTip containsString:@"imagegen"]);
    Choose(assistant.providerPopUp, @"Claude Code CLI (Claude)");
    CHECK(!assistant.imageButton.enabled);
    Choose(assistant.providerPopUp, @"Codex CLI (ChatGPT)");
    CHECK(assistant.imageButton.enabled);

    //nothing described: nothing asked
    assistant.inputView.string = @"  ";
    [assistant.imageButton performClick:nil];
    CHECK(assistant.state == AIAssistantStateIdle && [assistant.statusLabel.stringValue containsString:@"mô tả bức ảnh"]);

    //the picture, with the request of the settings; the wait says that a picture takes time
    AgentMode(@"image-delayed");
    AISettings.imagePrompt = @"Use $imagegen skill to create picture {prompt}, in flat style.";
    assistant.inputView.string = @"một chú mèo cam đang ngủ";
    [assistant.imageButton performClick:nil];
    CHECK(assistant.state == AIAssistantStateGenerating && assistant.glowing && !assistant.imageButton.enabled);
    CHECK([assistant.statusLabel.stringValue containsString:@"Đang tạo ảnh"] && [assistant.progressLabel.stringValue containsString:@"Codex CLI (ChatGPT)"]);
    SpinUntil(^BOOL { return [assistant.progressLabel.stringValue containsString:@"phác thảo"]; }, 8);
    CHECK([assistant.progressLabel.stringValue containsString:@"phác thảo"] && assistant.speedButton.hidden);        //the words of a picture; no offer of a lower level
    WaitForState(assistant, AIAssistantStateDone);
    CHECK(assistant.state == AIAssistantStateDone && !assistant.glowing);
    NSURL* picture = assistant.resultImageURL;
    CHECK(picture != nil && [picture.path hasPrefix:home] && [[NSFileManager defaultManager] fileExistsAtPath:picture.path]);
    CHECK(!assistant.imageView.hidden && assistant.imageView.image.size.width == 16 && assistant.progressLabel.hidden);       //in the place of the answer
    CHECK([assistant.statusLabel.stringValue containsString:@"Codex lưu ảnh ở"] && [assistant.statusLabel.stringValue containsString:@"generated_images"]);   //where it is kept is said
    CHECK(!assistant.revealButton.hidden && assistant.imageButton.enabled);
    CHECK([assistant.insertButton.title isEqualToString:@"Chèn ảnh"] && assistant.insertButton.isEnabled && assistant.copyButton.isEnabled);
    CHECK([assistant.actionButton.title isEqualToString:@"Tạo"]);                                                      //"Tạo lại" is for a text
    CHECK([AgentLog()[@"stdin_head"] isEqualToString:@"Use $imagegen skill to create picture một chú mèo cam đang ngủ, in flat style."]);
    CHECK([ValueAfterFlag(AgentLog()[@"args"], @"-m") isEqualToString:@"fake-mini"]);                                  //the model and the level of the window

    //saved: in Downloads (a folder of the test), under a name of its own, never over a file
    NSURL* downloads = [NSURL fileURLWithPath:[gWorkFolder stringByAppendingPathComponent:@"Downloads"]];
    [AILightbox setDownloadsFolderForTesting:downloads];
    CHECK(!assistant.saveImageButton.hidden);
    [assistant saveImage];
    NSArray* saved = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:downloads.path error:nil];
    CHECK(saved.count == 1 && [[saved.firstObject precomposedStringWithCanonicalMapping] hasPrefix:@"Ảnh AI "] && [saved.firstObject hasSuffix:@".png"]);   //the disk gives the name decomposed
    CHECK([[NSData dataWithContentsOfURL:[downloads URLByAppendingPathComponent:saved.firstObject]] isEqualToData:[NSData dataWithContentsOfURL:picture]]);
    CHECK([assistant.statusLabel.stringValue containsString:@"Đã lưu vào Downloads"]);
    [assistant saveImage];
    CHECK([[NSFileManager defaultManager] contentsOfDirectoryAtPath:downloads.path error:nil].count == 2);

    //the lightbox of the application, not another application
    AILightbox* box = [AILightbox shared];
    CHECK(!box.visible);
    [assistant openImage];
    CHECK(box.visible && box.zoom > 0 && [box.panel.title isEqualToString:picture.lastPathComponent]);
    CGFloat fitted = box.zoom;
    [box zoomIn];
    CHECK(fabs(box.zoom - fitted * 1.25) < 0.01);
    [box zoomOut];
    CHECK(fabs(box.zoom - fitted) < 0.01);
    [box zoomToActualSize];
    CHECK(fabs(box.zoom - 1) < 0.001);
    [box zoomToFit];
    CHECK(fabs(box.zoom - fitted) < 0.01);
    for (int i = 0; i < 40; i++)
        [box zoomIn];
    CHECK(box.zoom <= 8.001);                                                                                  //limits
    [board clearContents];
    [box copyImage];
    CHECK([[board dataForType:NSPasteboardTypePNG] isEqualToData:[NSData dataWithContentsOfURL:picture]] && box.showsCopied);
    NSError* saveError = nil;
    NSURL* boxSaved = [box saveImage:&saveError];
    CHECK(boxSaved != nil && saveError == nil && box.showsSaved && [box.savedURL isEqual:boxSaved] && [[NSFileManager defaultManager] fileExistsAtPath:boxSaved.path]);
    CHECK([boxSaved.path hasPrefix:downloads.path] && [[NSFileManager defaultManager] contentsOfDirectoryAtPath:downloads.path error:nil].count == 3);
    Spin(2.5);
    CHECK(!box.showsCopied && !box.showsSaved);
    [box close];
    CHECK(!box.visible);
    [assistant openImage];
    CHECK(box.visible);
    [assistant hideAssistant];
    CHECK(!box.visible);                                                                                        //closing the window closes it too
    [AILightbox setDownloadsFolderForTesting:nil];
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"con mèo";
    [assistant askForImage];
    WaitForState(assistant, AIAssistantStateDone);

    //Image writes can fail too; keep the generated image for another try.
    SnippetInserter* inserter = [assistant valueForKey:@"inserter"];
    inserter.pasteboard = (NSPasteboard*)[[RejectingPasteboard alloc] init];
    [assistant copyResult];
    CHECK(assistant.panel.visible && assistant.resultImageURL != nil && assistant.imageView.image != nil);
    CHECK([assistant.statusLabel.stringValue containsString:@"Không sao chép được"]);
    inserter.pasteboard = board;

    //copied: the picture is on the clipboard, as PNG and as TIFF
    [board clearContents];
    [board setString:@"của người dùng" forType:NSPasteboardTypeString];
    [assistant copyResult];
    CHECK([[board dataForType:NSPasteboardTypePNG] isEqualToData:[NSData dataWithContentsOfURL:picture]] && [board dataForType:NSPasteboardTypeTIFF].length > 0);
    CHECK(!assistant.panel.visible && assistant.resultImageURL == nil && assistant.imageView.image == nil);
    CHECK(assistant.state == AIAssistantStateIdle && assistant.resultText.length == 0);

    //Reopen and generate again to check insertion independently of copy-and-close.
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"một chú mèo cam đang ngủ";
    [assistant askForImage];
    WaitForState(assistant, AIAssistantStateDone);
    //put into the application: pasted as a PNG, the window goes, the clipboard comes back
    [board clearContents];
    [board setString:@"của người dùng" forType:NSPasteboardTypeString];
    gPastes = 0; gPastedImage = nil;
    [assistant insertResult];
    CHECK(!assistant.panel.visible && assistant.imageView.hidden && assistant.resultImageURL == nil && assistant.imageView.image == nil);
    Spin(0.4);
    CHECK(gPastes == 1 && [gPastedImage isEqualToData:[NSData dataWithContentsOfURL:picture]]);
    Spin(0.3);
    CHECK([[board stringForType:NSPasteboardTypeString] isEqualToString:@"của người dùng"] && [board dataForType:NSPasteboardTypePNG] == nil);
    CHECK([[NSFileManager defaultManager] fileExistsAtPath:picture.path]);                                          //the file is Codex's: it is not removed

    //a text request after a picture: the picture is gone, and the other way round
    AgentMode(@"image");
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"con mèo";
    [assistant askForImage];
    WaitForState(assistant, AIAssistantStateDone);
    CHECK(assistant.resultImageURL != nil);
    AgentMode(@"ok");
    [assistant ask];
    WaitForState(assistant, AIAssistantStateDone);
    CHECK(assistant.resultImageURL == nil && assistant.imageView.hidden && [assistant.resultText isEqualToString:@"Xin chào, đây là câu trả lời."]);
    CHECK([assistant.insertButton.title isEqualToString:@"Chèn"]);
    AgentMode(@"image");
    [assistant askForImage];
    WaitForState(assistant, AIAssistantStateDone);
    CHECK(assistant.resultImageURL != nil && assistant.resultText.length == 0 && assistant.outputView.string.length == 0);
    [assistant hideAssistant];
    CHECK(assistant.imageView.hidden && assistant.resultImageURL == nil);                                           //nothing is kept in the window

    //what goes wrong: no picture, an error; stopping
    AgentMode(@"image-none");
    [assistant presentWithSelection:nil application:nil];
    assistant.inputView.string = @"con mèo";
    [assistant askForImage];
    WaitForState(assistant, AIAssistantStateFailed);
    CHECK([assistant.statusLabel.stringValue containsString:@"không tạo ra ảnh nào"] && assistant.imageView.hidden && !assistant.glowing && assistant.imageButton.enabled);
    AgentMode(@"image-error");
    [assistant askForImage];
    WaitForState(assistant, AIAssistantStateFailed);
    CHECK([assistant.statusLabel.stringValue containsString:@"hạn mức"] && assistant.settingsButton.hidden);
    AgentMode(@"image-delayed");
    [assistant askForImage];
    Spin(0.5);
    [assistant stop];
    CHECK(assistant.state == AIAssistantStateIdle && !assistant.glowing && assistant.imageView.hidden && assistant.imageButton.enabled);
    Spin(4.0);
    CHECK(assistant.resultImageURL == nil && assistant.state == AIAssistantStateIdle);                                //it ended: nothing arrives later
    [assistant hideAssistant];

    unsetenv("CODEX_HOME");
    [AIAgentCLI setSearchDirectoriesForTesting:@[]];
    AgentMode(@"ok");
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
        //by default the window stays off the screen and the keyboard stays where it is; VOK_UI_VISIBLE=1 shows it for real
        assistant.offscreenForTesting = getenv("VOK_UI_VISIBLE") == NULL;
        __block int boundaries = 0;
        [AIAssistant setTypingBoundaryHandler:^{ boundaries++; }];

        //VOK_ONLY=presets runs that part alone, to work on it without waiting for the whole test
        if (getenv("VOK_ONLY") != NULL && strcmp(getenv("VOK_ONLY"), "presets") == 0) {
            TestPresetsFileMatches();
            TestPresets(assistant);
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[NSProcessInfo processInfo].processName];
            printf(failures ? "\n%d FAILURES\n" : "ALL OK\n", failures);
            return failures ? 1 : 0;
        }
        TestOpening(assistant);
        CHECK(boundaries >= 2);                                              // told when it opened and closed
        TestAsking(assistant);
        TestPresetsFileMatches();
        TestPresets(assistant);
        TestUsingTheAnswer(assistant, board);
        TestStopping(assistant);
        TestFailures(assistant);
        TestProviders(assistant);
        TestBusyMac(assistant);
        TestLocalServer(assistant);
        TestProgressText();
        TestWaiting(assistant);
        TestAgentPrograms(assistant);
        TestImages(assistant, board);
        TestEscape(assistant);

        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[NSProcessInfo processInfo].processName];
        printf(failures ? "\n%d FAILURES\n" : "ALL OK\n", failures);
    }
    return failures ? 1 : 0;
}
