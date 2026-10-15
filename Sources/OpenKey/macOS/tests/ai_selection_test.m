// Tests of how VOpenKey finds the text the user has selected (AISelection): Accessibility against a real window of another
// program (ax_helper.m), and the copy that is used when Accessibility cannot say, with the clipboard that must always be given
// back. Run with run-ai-selection-test.sh.
//
// Nothing is typed or pressed: the "⌘C" of the test is a block that writes to a clipboard of its own.
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "AISelection.h"
#import "SnippetInserter.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static void Spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static BOOL SpinUntil(BOOL (^done)(void), NSTimeInterval timeout) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [end timeIntervalSinceNow] > 0)
        Spin(0.01);
    return done();
}

//every element under `root`, depth first
static void Walk(AXUIElementRef root, void (^visit)(AXUIElementRef), int depth) {
    visit(root);
    if (depth > 8)
        return;
    CFTypeRef children = NULL;
    if (AXUIElementCopyAttributeValue(root, kAXChildrenAttribute, &children) == kAXErrorSuccess && children != NULL) {
        for (id child in (__bridge NSArray*)children)
            Walk((__bridge AXUIElementRef)child, visit, depth + 1);
        CFRelease(children);
    }
}

#pragma mark - Accessibility

static void TestAccessibility(NSRunningApplication* helper) {
    printf("-- accessibility, against a window of another program\n");
    AXUIElementRef application = AXUIElementCreateApplication(helper.processIdentifier);
    AXUIElementSetMessagingTimeout(application, 1);
    NSMutableArray* textAreas = [NSMutableArray array];
    __block AXUIElementRef secureField = NULL, window = NULL;
    Walk(application, ^(AXUIElementRef element) {
        CFTypeRef role = NULL, subrole = NULL;
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &role);
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute, &subrole);
        if ([(__bridge NSString*)role isEqualToString:@"AXTextArea"])
            [textAreas addObject:(__bridge id)element];
        if ([(__bridge NSString*)subrole isEqualToString:@"AXSecureTextField"])
            secureField = (AXUIElementRef)CFRetain(element);
        if ([(__bridge NSString*)role isEqualToString:@"AXWindow"])
            window = (AXUIElementRef)CFRetain(element);
        if (role) CFRelease(role);
        if (subrole) CFRelease(subrole);
    }, 0);
    CHECK(textAreas.count == 2);
    CHECK(secureField != NULL);
    CHECK(window != NULL);
    if (textAreas.count != 2 || secureField == NULL)
        return;

    //the order of the views is the order they were added in
    NSString* text = nil;
    AISelectionStatus status = [AISelection statusOfElement:(__bridge AXUIElementRef)textAreas[0] text:&text];
    CHECK(status == AISelectionText && [text isEqualToString:@"chào"]);
    text = nil;
    status = [AISelection statusOfElement:(__bridge AXUIElementRef)textAreas[1] text:&text];
    CHECK(status == AISelectionNone && text == nil);            // it answered: nothing is selected, no need to copy

    //a password field is never read
    text = nil;
    status = [AISelection statusOfElement:secureField text:&text];
    CHECK(status == AISelectionSecret && text == nil);

    //an element with no selection to speak of cannot say
    text = nil;
    status = [AISelection statusOfElement:window text:&text];
    CHECK(status == AISelectionUnknown && text == nil);
    CFRelease(secureField);
    if (window) CFRelease(window);
    CFRelease(application);
}

#pragma mark - Copy

static NSPasteboard* gBoard;
static int gCopyPresses;

//a "⌘C" that puts `text` on the clipboard after a moment, like an application does. The extra type is written by name, as
//Electron does: it is not a UTI, and NSPasteboardItem refuses it.
static void CopyPuts(NSString* text, NSString* vscodeData) {
    AISelection.copyCommand = ^{
        gCopyPresses++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSMutableArray* types = [NSMutableArray arrayWithObject:NSPasteboardTypeString];
            if (vscodeData != nil)
                [types addObject:@"vscode-editor-data"];
            [gBoard declareTypes:types owner:nil];
            [gBoard setString:text forType:NSPasteboardTypeString];
            if (vscodeData != nil)
                [gBoard setData:[vscodeData dataUsingEncoding:NSUTF8StringEncoding] forType:@"vscode-editor-data"];
        });
    };
}

//what the user had copied: text, HTML, and a type of an application that is not a UTI
static void PutOriginal(void) {
    [gBoard declareTypes:@[NSPasteboardTypeString, NSPasteboardTypeHTML, @"x-custom-flavor"] owner:nil];
    [gBoard setString:@"của người dùng" forType:NSPasteboardTypeString];
    [gBoard setData:[@"<b>của người dùng</b>" dataUsingEncoding:NSUTF8StringEncoding] forType:NSPasteboardTypeHTML];
    [gBoard setData:[@"dữ liệu riêng" dataUsingEncoding:NSUTF8StringEncoding] forType:@"x-custom-flavor"];
}

static BOOL OriginalIsBack(void) {
    NSString* html = [[NSString alloc] initWithData:[gBoard dataForType:NSPasteboardTypeHTML] ?: [NSData data] encoding:NSUTF8StringEncoding];
    NSString* custom = [[NSString alloc] initWithData:[gBoard dataForType:@"x-custom-flavor"] ?: [NSData data] encoding:NSUTF8StringEncoding];
    return [[gBoard stringForType:NSPasteboardTypeString] isEqualToString:@"của người dùng"] && [html isEqualToString:@"<b>của người dùng</b>"] &&
           [custom isEqualToString:@"dữ liệu riêng"];
}

static NSString* Read(NSRunningApplication* app, BOOL allowCopy, BOOL* done) {
    __block NSString* result = nil;
    __block BOOL finished = NO;
    NSDate* start = [NSDate date];
    [AISelection readSelectionOfApplication:app allowCopy:allowCopy completion:^(NSString* text) { result = text; finished = YES; }];
    SpinUntil(^BOOL { return finished; }, 5);
    if (done != NULL)
        *done = finished;
    CHECK([[NSDate date] timeIntervalSinceDate:start] < 2);      // it never keeps the user waiting
    return result;
}

static void TestCopy(NSRunningApplication* helper) {
    printf("-- copy, when Accessibility cannot say\n");
    if (IsSecureEventInputEnabled()) {
        printf("secure input is on (a password field or the lock screen): the copy is not used then, so it is not tested now\n");
        return;
    }
    gBoard = [NSPasteboard pasteboardWithUniqueName];
    AISelection.pasteboard = gBoard;
    //an application that cannot say what is selected, like most web and Electron applications
    AISelection.accessibilityProbe = ^AISelectionStatus(pid_t pid, NSString** text) { return AISelectionUnknown; };
    BOOL done = NO;

    //an application that copies: the text comes, and the clipboard is back as it was, every type
    PutOriginal();
    gCopyPresses = 0;
    CopyPuts(@"đã chọn đây", nil);
    NSString* text = Read(helper, YES, &done);
    CHECK(done && [text isEqualToString:@"đã chọn đây"] && gCopyPresses == 1);
    CHECK(OriginalIsBack());

    //nothing selected: the application copies nothing, the clipboard was not touched
    PutOriginal();
    NSInteger count = gBoard.changeCount;
    gCopyPresses = 0;
    AISelection.copyCommand = ^{ gCopyPresses++; };
    text = Read(helper, YES, &done);
    CHECK(done && text == nil && gCopyPresses == 1);
    CHECK(gBoard.changeCount == count && OriginalIsBack());

    //an editor that copies the line when nothing is selected, and says so
    PutOriginal();
    CopyPuts(@"const line = 1;\n", @"{\"version\":1,\"isFromEmptySelection\":true,\"multicursorText\":null}");
    text = Read(helper, YES, &done);
    CHECK(done && text == nil);
    CHECK(OriginalIsBack());
    //the same editor with a real selection
    PutOriginal();
    CopyPuts(@"let selected = 2;", @"{\"version\":1,\"isFromEmptySelection\":false}");
    text = Read(helper, YES, &done);
    CHECK([text isEqualToString:@"let selected = 2;"] && OriginalIsBack());

    //only spaces are not a selection
    PutOriginal();
    CopyPuts(@"  \n ", nil);
    text = Read(helper, YES, &done);
    CHECK(text == nil && OriginalIsBack());

    //copy not allowed: the clipboard is not touched and nothing is pressed
    PutOriginal();
    gCopyPresses = 0;
    CopyPuts(@"không được lấy", nil);
    text = Read(helper, NO, &done);
    CHECK(done && text == nil && gCopyPresses == 0 && OriginalIsBack());

    //no application, or VOpenKey's own: nothing to read
    text = Read(nil, YES, &done);
    CHECK(done && text == nil && gCopyPresses == 0);
    text = Read([NSRunningApplication currentApplication], YES, &done);
    CHECK(done && text == nil && gCopyPresses == 0);

    //two reads in a row each give the clipboard back
    PutOriginal();
    CopyPuts(@"lần một", nil);
    CHECK([Read(helper, YES, &done) isEqualToString:@"lần một"]);
    CopyPuts(@"lần hai", nil);
    CHECK([Read(helper, YES, &done) isEqualToString:@"lần hai"]);
    CHECK(OriginalIsBack());

    //an application that answers "nothing is selected" or "a password" is never copied from
    PutOriginal();
    gCopyPresses = 0;
    CopyPuts(@"không được copy", nil);
    AISelection.accessibilityProbe = ^AISelectionStatus(pid_t pid, NSString** text) { return AISelectionNone; };
    CHECK(Read(helper, YES, &done) == nil && done && gCopyPresses == 0);
    AISelection.accessibilityProbe = ^AISelectionStatus(pid_t pid, NSString** text) { return AISelectionSecret; };
    CHECK(Read(helper, YES, &done) == nil && done && gCopyPresses == 0);
    //an application that answers with the text: the clipboard is not touched either
    AISelection.accessibilityProbe = ^AISelectionStatus(pid_t pid, NSString** text) { *text = @"từ Accessibility"; return AISelectionText; };
    NSInteger count2 = gBoard.changeCount;
    CHECK([Read(helper, YES, &done) isEqualToString:@"từ Accessibility"] && gCopyPresses == 0 && gBoard.changeCount == count2);

    //an application that never answers: after a moment the copy is used, and while that question is lost no other is asked
    AISelection.accessibilityProbe = ^AISelectionStatus(pid_t pid, NSString** text) { sleep(3); return AISelectionText; };
    PutOriginal();
    gCopyPresses = 0;
    CopyPuts(@"đã copy được", nil);
    NSDate* start = [NSDate date];
    text = Read(helper, YES, &done);
    NSTimeInterval took = [[NSDate date] timeIntervalSinceDate:start];
    CHECK(done && [text isEqualToString:@"đã copy được"] && gCopyPresses == 1);
    CHECK(took > 0.8 && took < 2);
    start = [NSDate date];
    text = Read(helper, YES, &done);                 // the lost question is still lost: no new one, the copy at once
    CHECK(done && [text isEqualToString:@"đã copy được"] && [[NSDate date] timeIntervalSinceDate:start] < 0.7);
    Spin(3);                                          // the lost question is answered at last, and asking works again
    AISelection.accessibilityProbe = ^AISelectionStatus(pid_t pid, NSString** text) { *text = @"lại bình thường"; return AISelectionText; };
    CHECK([Read(helper, YES, &done) isEqualToString:@"lại bình thường"]);

    AISelection.accessibilityProbe = nil;
    AISelection.pasteboard = nil;
    AISelection.copyCommand = nil;
}

//the whole way through Accessibility, no probe: the helper has its first text view focused, with "chào" selected
static void TestEndToEnd(NSRunningApplication* helper) {
    printf("-- the whole way through Accessibility\n");
    BOOL done = NO;
    NSString* text = Read(helper, NO, &done);
    CHECK(done && [text isEqualToString:@"chào"]);
}

int main(int argc, char** argv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);            // what was done so far is visible even if the program is stopped
        [NSApplication sharedApplication];
        if (!AXIsProcessTrusted()) {
            printf("this program is not allowed to use Accessibility: the tests of it are skipped\n");
            return 0;
        }
        //while the screen is locked Accessibility sees no window of another program, whatever it is asked
        NSDictionary* session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
        if ([session[@"CGSSessionScreenIsLocked"] boolValue]) {
            printf("the screen is locked: Accessibility cannot see the window of the helper, the tests are skipped\n");
            return 0;
        }
        NSTask* task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSPipe* out = [NSPipe pipe];
        NSPipe* in = [NSPipe pipe];
        task.standardOutput = out;
        task.standardInput = in;
        NSError* error = nil;
        if (![task launchAndReturnError:&error]) {
            printf("could not start the helper: %s\n", error.localizedDescription.UTF8String);
            return 2;
        }
        NSData* line = [out.fileHandleForReading readDataOfLength:6];        // "ready\n"
        if (![[[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding] hasPrefix:@"ready"]) {
            printf("the helper did not come up\n");
            [task terminate];
            return 2;
        }
        NSRunningApplication* helper = [NSRunningApplication runningApplicationWithProcessIdentifier:task.processIdentifier];

        TestAccessibility(helper);
        TestEndToEnd(helper);
        TestCopy(helper);

        [in.fileHandleForWriting closeFile];                                 // the helper quits when its input is closed
        [task waitUntilExit];
        printf(failures ? "\n%d FAILURES\n" : "ALL OK\n", failures);
    }
    return failures ? 1 : 0;
}
