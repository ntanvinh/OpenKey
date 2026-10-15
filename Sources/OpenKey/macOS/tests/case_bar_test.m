//
//  case_bar_test.m
//  Tests of the case bar: when it shows, which keys it takes, what it pastes. The application, Accessibility and the paste are
//  replaced by stand-ins; what is looked at is the logic of CaseBar and the real panel (moved off screen at once).
//
//  Usage: case_bar_test [directory for the pictures of the panel]
//
#import <Cocoa/Cocoa.h>
#import "CaseBar.h"
#import "CaseBarPanel.h"

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static NSString* sPasted;
static NSString* sPastedNew;
static NSString* sSelection;         //what the stand-in application says is selected
static NSTimeInterval sReaderDelay;
static NSRect sLine;                 //where the stand-in says the selection is
static BOOL sReaderAllowCopy;
static int sReads;

static void Spin(NSTimeInterval seconds) {
    NSDate* until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static void Park(void) { //the real panel exists; it must not show on the screen of whoever runs this
    [[CaseBar panel] setFrameOrigin:NSMakePoint(-30000, -30000)];
}

static NSRunningApplication* Other(void) {
    for (NSRunningApplication* app in [NSWorkspace sharedWorkspace].runningApplications)
        if (app.processIdentifier != getpid() && app.activationPolicy == NSApplicationActivationPolicyRegular)
            return app;
    return nil;
}

static BOOL Key(CGKeyCode code, CGEventFlags flags) {
    return [CaseBar keyDown:code flags:flags];
}

static void Present(NSString* text, BOOL isExplicit) {
    [CaseBar presentText:text application:Other() explicit:isExplicit anchor:NSMakeRect(300, 400, 0, 18)];
    Park();
}

static NSImage* Snapshot(CaseBarPanel* panel, NSAppearanceName name) {
    panel.appearance = [NSAppearance appearanceNamed:name];
    NSView* root = panel.contentView.superview;
    NSRect bounds = root.bounds;
    NSBitmapImageRep* rep = [root bitmapImageRepForCachingDisplayInRect:bounds];
    [root cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSInteger margin = 24;
    NSImage* image = [[NSImage alloc] initWithSize:NSMakeSize(bounds.size.width + 2 * margin, bounds.size.height + 2 * margin)];
    [image lockFocus];
    //the blur does not render without a screen behind it: a flat ground like a window of text
    [([name isEqualToString:NSAppearanceNameDarkAqua] ? [NSColor colorWithWhite:0.17 alpha:1] : [NSColor colorWithWhite:0.97 alpha:1]) setFill];
    NSRectFill(NSMakeRect(0, 0, image.size.width, image.size.height));
    [[NSColor colorWithWhite:[name isEqualToString:NSAppearanceNameDarkAqua] ? 0.24 : 1 alpha:1] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(margin, margin, bounds.size.width, bounds.size.height) xRadius:11 yRadius:11] fill];
    [rep drawInRect:NSMakeRect(margin, margin, bounds.size.width, bounds.size.height)];
    [image unlockFocus];
    return image;
}

static void Save(NSImage* image, NSString* path) {
    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSRunningApplication* other = Other();
        CHECK(other != nil, "no other application to stand for the target");

        [CaseBar setFrontApplication:^NSRunningApplication*{ return other; }];
        [CaseBar setSelectionReader:^(NSRunningApplication* app, BOOL allowCopy, void (^completion)(NSString*)) {
            sReads++;
            sReaderAllowCopy = allowCopy;
            NSString* text = sSelection;
            if (sReaderDelay > 0)
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sReaderDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ completion(text); });
            else
                completion(text);
        }];
        [CaseBar setSelectionLocator:^NSRect(pid_t pid) { return sLine; }];
        [CaseBar setTextInserter:^(NSString* text, NSRunningApplication* app) { sPastedNew = text; sPasted = text; }];
        __block int boundaries = 0;
        [CaseBar setTypingBoundaryHandler:^{ boundaries++; }];
        [CaseBar registerDefaults];
        [CaseBar start];
        CHECK(vCaseBarAuto == 1, "auto default");
        CHECK(vCaseBarHotKey == VOK_CASEBAR_DEFAULT_HOTKEY, "hotkey default %x", vCaseBarHotKey);
        sLine = NSMakeRect(300, 400, 0, 18);

        const CGEventFlags opt = kCGEventFlagMaskAlternate;

        //nothing showing: no key is taken
        CHECK(![CaseBar isVisible], "starts hidden");
        CHECK(![CaseBar keyDown:18 flags:opt], "⌥1 with no list is the application's");
        CHECK(![CaseBar keyDown:126 flags:0], "arrow with no list");

        //the list opened by the shortcut: ⌥digits
        Present(@"xin chào thế giới", YES);
        CHECK([CaseBar isVisible], "visible after present");
        CHECK(boundaries == 1, "boundary on open: %d", boundaries);
        CHECK(Key(18, opt), "⌥1 taken");
        CHECK(![CaseBar isVisible], "hidden after a choice");
        CHECK([sPasted isEqualToString:@"XIN CHÀO THẾ GIỚI"], "⌥1 pastes upper: %s", sPasted.UTF8String);
        CHECK(boundaries == 2, "boundary on close: %d", boundaries);

        Present(@"xin chào thế giới", YES);
        //rows: CHỮ HOA, Viết Hoa Từng Từ, Viết hoa đầu câu (chữ thường is the text itself: no row), camelCase...
        CHECK(Key(19, opt), "⌥2 taken");
        CHECK([sPasted isEqualToString:@"Xin Chào Thế Giới"], "⌥2 pastes title: %s", sPasted.UTF8String);
        Present(@"xin chào thế giới", YES);
        CHECK(Key(20, opt), "⌥3 taken");
        CHECK([sPasted isEqualToString:@"Xin chào thế giới"], "⌥3 pastes sentence case: %s", sPasted.UTF8String);

        //↑ ↓ ↩ Esc in the list opened by the shortcut
        sPasted = nil;
        Present(@"xin chào thế giới", YES);
        CHECK(Key(125, 0), "down taken");   //row 0 is lit at the start: now row 1
        CHECK(Key(125, 0), "down taken 2"); //row 2
        CHECK(Key(36, 0), "return taken");
        CHECK(sPasted != nil, "return pastes the lit row: %s", sPasted.UTF8String);
        NSString* thirdRow = sPasted;
        Present(@"xin chào thế giới", YES);
        CHECK(Key(126, 0), "up taken");     //wraps to the last row
        CHECK(Key(76, 0), "enter (keypad) taken");
        CHECK(sPasted != nil && ![sPasted isEqualToString:thirdRow], "up wraps to the last row: %s", sPasted.UTF8String);
        sPasted = nil;
        Present(@"xin chào thế giới", YES);
        CHECK(Key(53, 0), "Esc taken when opened by the shortcut");
        CHECK(![CaseBar isVisible] && sPasted == nil, "Esc puts it away without pasting");
        Present(@"xin chào thế giới", YES);
        CHECK(!Key(0, 0), "a letter is the application's");
        CHECK(![CaseBar isVisible], "a letter puts it away");
        Present(@"xin chào thế giới", YES);
        CHECK(!Key(18, kCGEventFlagMaskCommand), "⌘1 is not ⌥1");
        CHECK(![CaseBar isVisible], "⌘1 puts it away");

        //the list that came up by itself leaves the arrows and Return alone
        Present(@"xin chào thế giới", NO);
        CHECK(!Key(125, 0), "down is the application's when the list came by itself");
        CHECK(![CaseBar isVisible], "and it is put away");
        Present(@"xin chào thế giới", NO);
        CHECK(!Key(36, 0), "Return is the application's");
        Present(@"xin chào thế giới", NO);
        CHECK(!Key(53, 0), "Esc is the application's, the list goes");
        CHECK(![CaseBar isVisible], "Esc puts it away");
        Present(@"xin chào thế giới", NO);
        CHECK(Key(19, opt), "⌥2 works on the list that came by itself");
        CHECK([sPasted isEqualToString:@"xin chào thế giới"] == NO, "something was pasted: %s", sPasted.UTF8String);
        //the shortcut turns it into one that takes the arrows
        Present(@"xin chào thế giới", NO);
        [CaseBar toggle];
        CHECK([CaseBar isVisible], "toggle on a list that came by itself keeps it");
        CHECK(Key(125, 0), "now the arrows are taken");
        [CaseBar toggle];
        CHECK(![CaseBar isVisible], "and the shortcut again closes it");

        //a digit with no row
        Present(@"Xin", YES); //two rows only
        CHECK(!Key(26, opt) && ![CaseBar isVisible], "⌥7 with two rows is the application's, and puts the list away");

        //nothing to offer
        sSelection = @"12345";
        sReads = 0;
        [CaseBar show];
        Spin(0.2);
        CHECK(![CaseBar isVisible], "digits only: nothing to change");

        //finding the selection: the shortcut
        sSelection = @"hello world";
        sReaderAllowCopy = NO;
        [CaseBar show];
        Spin(0.1);
        CHECK([CaseBar isVisible], "show() found the selection");
        CHECK(sReaderAllowCopy, "the shortcut may use ⌘C");
        Park();
        CHECK(Key(18, opt) && [sPasted isEqualToString:@"HELLO WORLD"], "pasted %s", sPasted.UTF8String);

        //by itself: after a drag
        sSelection = @"xin chào";
        [CaseBar mouseDown];
        [CaseBar mouseUpWithClickCount:1 flags:0];            //no drag, one click: nothing
        Spin(0.4);
        CHECK(![CaseBar isVisible], "a plain click does not show it");
        [CaseBar mouseDown];
        [CaseBar mouseUpWithClickCount:2 flags:0];            //double click
        CHECK(![CaseBar isVisible], "not before the application has updated its selection");
        Spin(0.45);
        CHECK([CaseBar isVisible], "a double click shows it");
        CHECK(!sReaderAllowCopy, "by itself the clipboard is never used");
        Park();
        [CaseBar mouseDown];
        CHECK(![CaseBar isVisible], "a click puts it away");
        [CaseBar mouseUpWithClickCount:1 flags:kCGEventFlagMaskShift]; //shift-click extends a selection
        Spin(0.45);
        CHECK([CaseBar isVisible], "shift+click shows it");
        Park();
        [CaseBar scrolled];
        CHECK(![CaseBar isVisible], "scrolling puts it away");

        //by itself: after the keyboard
        CHECK(!Key(123, kCGEventFlagMaskShift), "shift+left is the application's");
        Spin(0.2);
        CHECK(![CaseBar isVisible], "not while the selection is still moving");
        CHECK(!Key(123, kCGEventFlagMaskShift), "shift+left again");
        Spin(0.6);
        CHECK([CaseBar isVisible], "shown once it stopped");
        Park();
        CHECK(!Key(124, kCGEventFlagMaskShift), "shift+right while shown is the application's");
        CHECK(![CaseBar isVisible], "and puts it away");
        Spin(0.6);
        CHECK([CaseBar isVisible], "and shows it again for the new selection");
        Park();
        [CaseBar hide];
        CHECK(!Key(0, kCGEventFlagMaskCommand), "⌘A is the application's");
        Spin(0.6);
        CHECK([CaseBar isVisible], "⌘A shows it");
        Park();
        [CaseBar hide];

        //typing before the answer arrives cancels it
        sReaderDelay = 0.3;
        [CaseBar mouseDown];
        [CaseBar mouseUpWithClickCount:2 flags:0];
        Spin(0.25);              //the question is out
        CHECK(!Key(0, 0), "a letter");
        Spin(0.5);
        CHECK(![CaseBar isVisible], "a late answer is dropped after the user typed");
        sReaderDelay = 0;

        //typing between selection and look cancels it
        [CaseBar mouseDown];
        [CaseBar mouseUpWithClickCount:2 flags:0];
        CHECK(!Key(0, 0), "a letter");
        Spin(0.5);
        CHECK(![CaseBar isVisible], "a letter before the look cancels it");

        //switched off
        vCaseBarAuto = 0;
        [CaseBar mouseDown];
        [CaseBar mouseUpWithClickCount:2 flags:0];
        Spin(0.45);
        CHECK(![CaseBar isVisible], "off: nothing by itself");
        [CaseBar show];
        Spin(0.1);
        CHECK([CaseBar isVisible], "off: the shortcut still works");
        Park();
        [CaseBar hide];
        vCaseBarAuto = 1;

        //blocked (the snippet window has the keyboard)
        __block BOOL blocked = YES;
        [CaseBar setBlockedCheck:^BOOL{ return blocked; }];
        [CaseBar mouseDown];
        [CaseBar mouseUpWithClickCount:2 flags:0];
        Spin(0.45);
        CHECK(![CaseBar isVisible], "not while another window has the keyboard");
        blocked = NO;

        //a long text: only the start is previewed, all of it is changed
        NSMutableString* big = [NSMutableString string];
        for (int i = 0; i < 3000; i++) [big appendString:@"xin chào "];
        Present(big, YES);
        CHECK(Key(18, opt), "choose on a long text");
        CHECK(sPasted.length == big.length && [sPasted hasPrefix:@"XIN CHÀO XIN CHÀO"] && [sPasted hasSuffix:@"CHÀO "], "the whole text is changed: %lu of %lu", (unsigned long)sPasted.length, (unsigned long)big.length);
        //too long to be a thing for this list
        NSMutableString* huge = [NSMutableString stringWithString:@"a"];
        while (huge.length < 120000) [huge appendString:huge];
        sSelection = huge;
        [CaseBar show];
        Spin(0.2);
        CHECK(![CaseBar isVisible], "a text of 100000+ characters is left alone");

        //a click on a row (a real mouse-up event sent to the panel)
        sPasted = nil;
        Present(@"xin chào thế giới", YES);
        CaseBarPanel* panel = [CaseBar panel];
        CGFloat height = panel.frame.size.height;
        CGFloat rowY = height - (5 + 26 * 1 + 13); //second row, from the bottom
        NSEvent* down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(80, rowY) modifierFlags:0 timestamp:0
                                       windowNumber:panel.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
        [panel sendEvent:down];
        CHECK(panel.highlighted == 1, "pressing on a row lights it: %ld", (long)panel.highlighted);
        NSEvent* up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:NSMakePoint(80, rowY) modifierFlags:0 timestamp:0
                                     windowNumber:panel.windowNumber context:nil eventNumber:0 clickCount:1 pressure:0];
        [panel sendEvent:up];
        CHECK([sPasted isEqualToString:@"xin chào thế giới"] == NO && sPasted != nil, "a click chose a row: %s", sPasted.UTF8String);
        CHECK(![CaseBar isVisible], "and closed the list");

        //pictures
        if (argc > 1) {
            NSString* dir = [NSString stringWithUTF8String:argv[1]];
            Present(@"Xin chào thế giới. Tôi là Vinh", YES);
            [CaseBar panel].alphaValue = 1;
            Save(Snapshot([CaseBar panel], NSAppearanceNameAqua), [dir stringByAppendingPathComponent:@"case-bar-light.png"]);
            Save(Snapshot([CaseBar panel], NSAppearanceNameDarkAqua), [dir stringByAppendingPathComponent:@"case-bar-dark.png"]);
            [[CaseBar panel] moveHighlight:1];
            [[CaseBar panel] moveHighlight:1];
            Save(Snapshot([CaseBar panel], NSAppearanceNameAqua), [dir stringByAppendingPathComponent:@"case-bar-lit-light.png"]);
            Save(Snapshot([CaseBar panel], NSAppearanceNameDarkAqua), [dir stringByAppendingPathComponent:@"case-bar-lit-dark.png"]);
            [CaseBar hide];
            Present(@"dòng một của đoạn văn\nđòng hai dài hơn nhiều so với dòng một và cứ thế dài mãi không dứt", NO);
            [CaseBar panel].alphaValue = 1;
            Save(Snapshot([CaseBar panel], NSAppearanceNameAqua), [dir stringByAppendingPathComponent:@"case-bar-multiline.png"]);
            [CaseBar hide];
        }
    }
    printf(failures == 0 ? "ALL OK\n" : "%d FAILURES\n", failures);
    return failures != 0;
}
