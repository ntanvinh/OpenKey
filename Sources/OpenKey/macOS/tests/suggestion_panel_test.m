#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "SuggestionPanel.h"

@interface SuggestionPanel (HoverTesting)
-(void)updateFadeForPointer;
-(void)show;
@end

static NSPoint pointer;
static NSUserDefaults* isolated;
static id TestDefaults(id self, SEL cmd) { return isolated; }
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
        NSString* suite = [@"vopenkey.test.suggestion-panel." stringByAppendingString:NSUUID.UUID.UUIDString];
        isolated = [[NSUserDefaults alloc] initWithSuiteName:suite];
        Method defaults = class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults));
        IMP originalDefaults = method_setImplementation(defaults, (IMP)TestDefaults);
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        Method mouseLocation = class_getClassMethod([NSEvent class], @selector(mouseLocation));
        IMP original = method_setImplementation(mouseLocation, (IMP)TestMouseLocation);
        SuggestionPanel* panel = [[SuggestionPanel alloc] init];
        CHECK(SuggestionPanel.transparencyPercent == 0, "default preserves full visibility");
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
        pointer = NSMakePoint(30000, 30000);
        [SuggestionPanel setTransparencyPercent:50];
        [panel show];
        Spin(0.35);
        CHECK(fabs(panel.alphaValue - 0.5) < 0.01, "show uses saved transparency");
        NSUserDefaults* reloaded = [[NSUserDefaults alloc] initWithSuiteName:suite];
        CHECK([reloaded integerForKey:@"SuggestionTransparencyPercent"] == 50, "transparency persists");
        [SuggestionPanel setTransparencyPercent:80];
        CHECK(fabs(panel.alphaValue - 0.2) < 0.01, "visible bar changes immediately");
        pointer = NSMakePoint(NSMidX(panel.frame), NSMidY(panel.frame));
        [panel updateFadeForPointer];
        Spin(1.6);
        CHECK(fabs(panel.alphaValue - 0.15) < 0.01, "hover still fades with custom transparency");
        [SuggestionPanel setTransparencyPercent:40];
        CHECK(fabs(panel.alphaValue - 0.15) < 0.01, "setting change preserves hover fade");
        pointer = NSMakePoint(30000, 30000);
        [panel updateFadeForPointer];
        Spin(0.35);
        CHECK(fabs(panel.alphaValue - 0.6) < 0.01, "pointer exit restores chosen visibility");
        [SuggestionPanel setTransparencyPercent:100];
        CHECK(SuggestionPanel.transparencyPercent == 80, "upper limit keeps bar visible");
        [SuggestionPanel setTransparencyPercent:-10];
        CHECK(SuggestionPanel.transparencyPercent == 0, "negative transparency clamps to zero");
        [panel orderOut:nil];
        [isolated removePersistentDomainForName:suite];
        method_setImplementation(defaults, originalDefaults);
        method_setImplementation(mouseLocation, original);
        NSLog(@"%@", failures ? @"FAILURES" : @"ALL OK: suggestion hover timing in light and dark appearances");
        return failures ? 1 : 0;
    }
}
