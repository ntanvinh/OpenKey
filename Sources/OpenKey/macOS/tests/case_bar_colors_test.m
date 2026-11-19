//
//  case_bar_colors_test.m
//  VOpenKey
//
//  Can the case bar be read on any backdrop? The panel is a blur of what is behind it. Black and white bound every other backdrop
//  (the colour of each channel of the result grows with the backdrop's), so the text is checked against those two, under the veil, in
//  light and in dark: 4.5:1 at least (WCAG AA for normal text) for the name, the key and the preview of a row that is not lit.
//  The colours are the ones the list draws with (+[CaseBarPanel nameAttributes:] ...), not copies.
//
//  No window is shown: the panel is made and drawn into a bitmap, never ordered in. With a directory as argument it also writes
//  pictures of the list over black, white, red, yellow, blue and a mid grey (the blur itself does not render without a screen, so the
//  veil and the text are what the pictures show: the worst case for the text).
//

#import <Cocoa/Cocoa.h>
#import "CaseBarPanel.h"

static int failures;
#define CHECK(condition, ...) do { if (!(condition)) { NSLog(@"FAIL: " __VA_ARGS__); failures++; } } while (0)

typedef struct { CGFloat r, g, b, a; } RGBA;

static RGBA Resolve(NSColor* color, NSAppearance* appearance) {
    __block RGBA result = {0, 0, 0, 1};
    [appearance performAsCurrentDrawingAppearance:^{
        NSColor* rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        result = (RGBA){rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent};
    }];
    return result;
}

static RGBA Over(RGBA top, RGBA below) { //top drawn over below (below opaque)
    return (RGBA){top.r * top.a + below.r * (1 - top.a), top.g * top.a + below.g * (1 - top.a), top.b * top.a + below.b * (1 - top.a), 1};
}

static CGFloat Channel(CGFloat c) { return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
static CGFloat Luminance(RGBA c) { return 0.2126 * Channel(c.r) + 0.7152 * Channel(c.g) + 0.0722 * Channel(c.b); }
static CGFloat Contrast(RGBA a, RGBA b) {
    CGFloat la = Luminance(a), lb = Luminance(b);
    return (MAX(la, lb) + 0.05) / (MIN(la, lb) + 0.05);
}

static NSColor* ColorOf(NSDictionary* attributes) { return attributes[NSForegroundColorAttributeName]; }

static NSArray<NSDictionary*>* Offers(void) {
    return @[@{@"name": @"CHỮ HOA", @"text": @"XIN CHÀO THẾ GIỚI"},
             @{@"name": @"chữ thường", @"text": @"xin chào thế giới"},
             @{@"name": @"Viết Hoa Đầu Từ", @"text": @"Xin Chào Thế Giới", @"separatorAfter": @YES},
             @{@"name": @"camelCase", @"text": @"xinChaoTheGioi"},
             @{@"name": @"snake_case", @"text": @"xin_chao_the_gioi"}];
}

static NSImage* ListPicture(NSAppearanceName name, NSColor* backdrop, NSInteger lit) {
    CaseBarPanel* panel = [[CaseBarPanel alloc] init]; //never ordered in
    panel.appearance = [NSAppearance appearanceNamed:name];
    [panel setOffers:Offers()];
    panel.highlighted = lit;
    NSView* root = panel.contentView.superview;
    NSRect bounds = root.bounds;
    NSBitmapImageRep* rep = [root bitmapImageRepForCachingDisplayInRect:bounds];
    [root cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSInteger margin = 18;
    NSImage* image = [[NSImage alloc] initWithSize:NSMakeSize(bounds.size.width + 2 * margin, bounds.size.height + 2 * margin)];
    [image lockFocus];
    [backdrop setFill];
    NSRectFill(NSMakeRect(0, 0, image.size.width, image.size.height));
    [rep drawInRect:NSMakeRect(margin, margin, bounds.size.width, bounds.size.height)];
    [image unlockFocus];
    return image;
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        const RGBA black = {0, 0, 0, 1}, white = {1, 1, 1, 1};
        CGFloat worst = 99;
        for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            NSAppearance* appearance = [NSAppearance appearanceNamed:name];
            RGBA veil = Resolve([CaseBarPanel veilColor], appearance);
            CHECK(veil.a > 0.5 && veil.a < 1, "%s: the veil must cover most of the blur but let some through (alpha %.2f)", name.UTF8String, veil.a);
            struct { const char* what; NSDictionary* attributes; } texts[] = {
                {"name", [CaseBarPanel nameAttributes:NO]},
                {"hotkey", [CaseBarPanel hintAttributes:NO]},
                {"preview", [CaseBarPanel previewAttributes:NO]},
            };
            for (int t = 0; t < 3; t++) {
                RGBA text = Resolve(ColorOf(texts[t].attributes), appearance);
                if (t > 0)
                    CHECK(text.a == 1, "%s %s must be opaque (alpha %.2f): a translucent colour reads as the backdrop allows", name.UTF8String, texts[t].what, text.a);
                for (int b = 0; b < 2; b++) {
                    RGBA ground = Over(veil, b ? white : black);
                    CGFloat ratio = Contrast(Over(text, ground), ground);
                    worst = MIN(worst, ratio);
                    printf("%-22s %-8s over %s: %.2f:1\n", name.UTF8String, texts[t].what, b ? "white" : "black", ratio);
                    CHECK(ratio >= 4.5, "%s %s over a %s backdrop is %.2f:1, 4.5:1 is the least", name.UTF8String, texts[t].what, b ? "white" : "black", ratio);
                }
            }
            //the lit row sits on an opaque accent colour: nothing of the backdrop reaches it, so nothing may be translucent there
            CHECK(Resolve(ColorOf([CaseBarPanel hintAttributes:YES]), appearance).a == 1, "%s lit hotkey must be opaque", name.UTF8String);
            CHECK(Resolve(ColorOf([CaseBarPanel previewAttributes:YES]), appearance).a == 1, "%s lit preview must be opaque", name.UTF8String);
        }
        printf("worst contrast: %.2f:1\n", worst);

        if (argc > 1 && strlen(argv[1]) > 0) {
            NSString* directory = [NSString stringWithUTF8String:argv[1]];
            [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
            struct { const char* name; NSColor* color; } grounds[] = {
                {"black", [NSColor blackColor]}, {"white", [NSColor whiteColor]}, {"red", [NSColor colorWithSRGBRed:0.85 green:0.1 blue:0.1 alpha:1]},
                {"yellow", [NSColor colorWithSRGBRed:1 green:0.9 blue:0.2 alpha:1]}, {"blue", [NSColor colorWithSRGBRed:0.1 green:0.3 blue:0.9 alpha:1]},
                {"grey", [NSColor colorWithWhite:0.5 alpha:1]},
            };
            for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                for (int g = 0; g < 6; g++) {
                    NSImage* image = ListPicture(name, grounds[g].color, 1);
                    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
                    NSString* file = [NSString stringWithFormat:@"%@/case-bar-%@-%s.png", directory,
                                      [name isEqualToString:NSAppearanceNameDarkAqua] ? @"dark" : @"light", grounds[g].name];
                    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:file atomically:YES];
                }
            }
            printf("pictures in %s\n", directory.UTF8String);
        }
        printf(failures ? "FAILURES: %d\n" : "ALL OK\n", failures);
    }
    return failures ? 1 : 0;
}
