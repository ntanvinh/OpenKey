#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "SuggestionPanel.h"

@interface SuggestionPanel (HoverTesting)
-(void)updateFadeForPointer;
-(void)show;
@end

static NSPoint pointer;
static NSPoint TestMouseLocation(id self, SEL cmd) { return pointer; }
static int failures;
#define CHECK(condition, message) do { if (!(condition)) { NSLog(@"FAIL: %s", message); failures++; } } while (0)

static void Spin(NSTimeInterval seconds) {
    NSDate* until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (until.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        Method mouseLocation = class_getClassMethod([NSEvent class], @selector(mouseLocation));
        IMP original = method_setImplementation(mouseLocation, (IMP)TestMouseLocation);
        SuggestionPanel* panel = [[SuggestionPanel alloc] init];
        [panel setWords:@[@"gợi ý", @"suggestion"]];
        //A real AppKit window, off screen; the pointer is simulated without moving the user's mouse.
        for (NSAppearanceName appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            panel.appearance = [NSAppearance appearanceNamed:appearance];
            [panel setFrameOrigin:NSMakePoint(-30000, -30000)];
            pointer = NSMakePoint(NSMidX(panel.frame), NSMidY(panel.frame));
            [panel show];
            Spin(0.7);
            CHECK(panel.alphaValue > 0.99, "bar must stay readable during grace period");
            [panel setWords:@[@"gợi ý mới", @"updated suggestion"]];
            [panel show]; //typing updates must not postpone fading
            [panel updateFadeForPointer];
            Spin(0.9);
            CHECK(fabs(panel.alphaValue - 0.15) < 0.01, "stationary pointer must fade after grace period");
            pointer = NSMakePoint(30000, 30000);
            [panel updateFadeForPointer];
            Spin(0.35);
            CHECK(panel.alphaValue > 0.99, "pointer exit must restore full visibility");

            pointer = NSMakePoint(NSMidX(panel.frame), NSMidY(panel.frame));
            [panel updateFadeForPointer];
            Spin(0.4);
            pointer = NSMakePoint(30000, 30000);
            [panel updateFadeForPointer];
            Spin(1.2);
            CHECK(panel.alphaValue > 0.99, "leaving before deadline must cancel fade");

            pointer = NSMakePoint(NSMidX(panel.frame), NSMidY(panel.frame));
            [panel updateFadeForPointer];
            Spin(0.6);
            [panel orderOut:nil];
            [panel setFrameOrigin:NSMakePoint(-30000, -30000)];
            pointer = NSMakePoint(NSMidX(panel.frame), NSMidY(panel.frame));
            [panel show];
            Spin(0.8);
            CHECK(panel.alphaValue > 0.99, "reopening must get a new grace period");
            Spin(1.2);
            CHECK(fabs(panel.alphaValue - 0.15) < 0.01, "reopened bar must eventually fade");
            CHECK(panel.ignoresMouseEvents && !panel.canBecomeKeyWindow, "bar must preserve click through and typing focus");
            [panel orderOut:nil];
        }
        method_setImplementation(mouseLocation, original);
        NSLog(@"%@", failures ? @"FAILURES" : @"ALL OK: suggestion hover timing in light and dark appearances");
        return failures ? 1 : 0;
    }
}
