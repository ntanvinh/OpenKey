// A program with a window for ai_selection_test.m to ask about through Accessibility. A process cannot ask about its own windows,
// so the test needs another one. The window holds:
//   a text view with a word selected, a text view with nothing selected, and a password field with something typed in.
// It says "ready" when the window is up, and quits when its input is closed.
#import <Cocoa/Cocoa.h>

int main(void) {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 420, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.title = @"AX helper";

        NSTextView* selected = [[NSTextView alloc] initWithFrame:NSMakeRect(10, 200, 400, 80)];
        selected.string = @"Xin chào thế giới, đây là một câu.";
        selected.selectedRange = NSMakeRange(4, 4);          // "chào"
        NSTextView* plain = [[NSTextView alloc] initWithFrame:NSMakeRect(10, 100, 400, 80)];
        plain.string = @"Một đoạn không chọn gì.";
        plain.selectedRange = NSMakeRange(0, 0);
        NSSecureTextField* secret = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(10, 40, 400, 24)];
        secret.stringValue = @"matkhau-bi-mat";
        for (NSView* view in @[selected, plain, secret])
            [window.contentView addSubview:view];
        [window orderFront:nil];
        //the first text view has the keyboard: asked what is selected where the keyboard is, the application answers "chào".
        //Not the other way round: a window with no focused field can leave an Accessibility question unanswered for good.
        [window makeFirstResponder:selected];

        //quit when the test closes the input
        [NSThread detachNewThreadWithBlock:^{
            char buffer[64];
            while (read(0, buffer, sizeof buffer) > 0) {}
            exit(0);
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            printf("ready\n");
            fflush(stdout);
        });
        [app run];
    }
    return 0;
}
