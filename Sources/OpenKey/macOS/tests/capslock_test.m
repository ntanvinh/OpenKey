//
//  capslock_test.m
//  Tests of what the person sees when Caps Lock is switched: the state CapsLockMonitor keeps and the notification it posts, the toast
//  (CapsLockToast: the line, how long it stays, a second press while it is there, it never takes the keyboard or the mouse) and the red
//  menu bar icon (VOKCapsLockStatusImage). Run with run-capslock-test.sh.
//
//  Nothing is shown on the screen and neither the keyboard nor the clipboard of the user is touched: the keyboard is a stand-in and
//  the toast is put far outside every screen.
//
//   capslock_test [folder for pictures]
//
#import <Cocoa/Cocoa.h>
#import "CapsLockMonitor.h"
#import "CapsLockToast.h"
#import "VOKUI.h"

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL line %d: %s\n", __LINE__, #cond); } } while (0)

//the keyboard, which a test decides about (CapsLockMonitor is built with -DVOKReadCapsLock=FakeCaps)
static BOOL fakeCaps;
BOOL FakeCaps(void) { return fakeCaps; }

static int notifications;

static void Spin(NSTimeInterval seconds) {
    NSDate* until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

typedef struct { CGFloat r, g, b, a; } Pixel;

static NSBitmapImageRep* RenderIcon(NSImage* image, BOOL dark) {
    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:44 pixelsHigh:44 bitsPerSample:8 samplesPerPixel:4
                                                                      hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    rep.size = NSMakeSize(22, 22);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua] performAsCurrentDrawingAppearance:^{
        [image drawInRect:NSMakeRect(0, 0, 22, 22) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    }];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

static Pixel At(NSBitmapImageRep* rep, NSInteger x, NSInteger y) {
    NSColor* c = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    return (Pixel){c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent};
}

static void Save(NSImage* image, NSString* path) {
    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static NSImage* Snapshot(CapsLockToast* panel, BOOL dark) {
    panel.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    NSView* root = panel.contentView.superview;
    NSRect bounds = root.bounds;
    NSBitmapImageRep* rep = [root bitmapImageRepForCachingDisplayInRect:bounds];
    [root cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSInteger margin = 24;
    NSImage* image = [[NSImage alloc] initWithSize:NSMakeSize(bounds.size.width + 2 * margin, bounds.size.height + 2 * margin)];
    [image lockFocus];
    //the blur does not render without a screen behind it: a flat ground like a window of text, and a plate where the material is
    [(dark ? [NSColor colorWithWhite:0.12 alpha:1] : [NSColor colorWithWhite:0.96 alpha:1]) setFill];
    NSRectFill(NSMakeRect(0, 0, image.size.width, image.size.height));
    [(dark ? [NSColor colorWithWhite:0.26 alpha:1] : [NSColor colorWithWhite:1 alpha:1]) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(margin, margin, bounds.size.width, bounds.size.height) xRadius:14 yRadius:14] fill];
    [rep drawInRect:NSMakeRect(margin, margin, bounds.size.width, bounds.size.height)];
    [image unlockFocus];
    return image;
}

//menu bar strips: [normal | secure input yellow | caps lock red] for each glyph, on a light and a dark bar
static NSImage* IconStrip(NSString* resources, BOOL dark) {
    NSMutableArray<NSImage*>* icons = [NSMutableArray array];
    for (NSString* name in @[@"Status", @"StatusEng"]) {
        NSImage* glyph = [[NSImage alloc] initWithContentsOfFile:[resources stringByAppendingPathComponent:[name stringByAppendingString:@".png"]]];
        [icons addObject:glyph];
        [icons addObject:VOKWarningStatusImage(glyph)];
        [icons addObject:VOKCapsLockStatusImage(glyph, [name isEqualToString:@"Status"])];
    }
    CGFloat cell = 22, scale = 4, gap = 10;
    NSSize size = NSMakeSize((icons.count * (cell + gap) + gap) * scale, (cell + 2 * gap) * scale);
    NSImage* strip = [[NSImage alloc] initWithSize:size];
    [strip lockFocus];
    [(dark ? [NSColor colorWithWhite:0.15 alpha:1] : [NSColor colorWithWhite:0.93 alpha:1]) setFill];
    NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    for (NSUInteger i = 0; i < icons.count; i++) {
        NSImage* icon = icons[i];
        if (icon.isTemplate) {
            //the plain icon of the menu bar is one colour: the bar's text colour
            NSImage* tinted = [icon copy];
            [tinted lockFocus];
            [(dark ? [NSColor whiteColor] : [NSColor blackColor]) set];
            NSRectFillUsingOperation(NSMakeRect(0, 0, tinted.size.width, tinted.size.height), NSCompositingOperationSourceAtop);
            [tinted unlockFocus];
            icon = tinted;
        }
        [icon drawInRect:NSMakeRect((gap + i * (cell + gap)) * scale, gap * scale, cell * scale, cell * scale)
                fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    }
    [strip unlockFocus];
    return strip;
}

static void TestMonitor(void) {
    printf("-- monitor\n");
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:CapsLockToastDefaultsKey];
    //the toggle of Settings reads the saved number: the message is on until it is switched off
    CHECK([defaults integerForKey:CapsLockToastDefaultsKey] == 0);       //nothing registered yet
    [CapsLockMonitor registerDefaults];
    CHECK([defaults integerForKey:CapsLockToastDefaultsKey] == 1);
    [CapsLockToast setOffscreenForTesting:YES];

    [[NSNotificationCenter defaultCenter] addObserverForName:CapsLockMonitorDidChangeNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification* note) { notifications++; }];

    //starting with Caps Lock already on: the icon has to know, nobody needs a message about what was there before
    fakeCaps = YES;
    [CapsLockMonitor start];
    CHECK([CapsLockMonitor isOn]);
    CHECK(notifications == 1);
    CHECK([CapsLockToast panel] == nil || ![CapsLockToast panel].visible);
    Spin(0.7);                                      //the poll runs; nothing changed
    CHECK(notifications == 1);
    CHECK([CapsLockToast panel] == nil || ![CapsLockToast panel].visible);

    //switched off: found by the poll (a change the events of the keyboard did not announce), with the message
    fakeCaps = NO;
    Spin(0.7);
    CHECK(![CapsLockMonitor isOn]);
    CHECK(notifications == 2);
    CapsLockToast* toast = [CapsLockToast panel];
    CHECK(toast != nil && toast.visible);
    CHECK([toast.message isEqualToString:@"Caps Lock đã tắt"]);

    //the same state again says nothing more
    [CapsLockMonitor noteState:NO];
    CHECK(notifications == 2);

    //on, from the keyboard events: the toast changes in place
    fakeCaps = YES;
    [CapsLockMonitor check];
    CHECK([CapsLockMonitor isOn]);
    CHECK(notifications == 3);
    CHECK([CapsLockToast panel] == toast);          //one panel for good
    CHECK([toast.message isEqualToString:@"Caps Lock đang bật"]);
    CHECK([toast.message isEqualToString:[CapsLockToast messageForState:YES]]);
    CHECK(![[CapsLockToast messageForState:NO] isEqualToString:[CapsLockToast messageForState:YES]]);

    //it is never where the person types or clicks
    CHECK(!toast.canBecomeKeyWindow && !toast.canBecomeMainWindow);
    CHECK(toast.ignoresMouseEvents);
    CHECK(toast.isFloatingPanel);
    CHECK((toast.styleMask & NSWindowStyleMaskNonactivatingPanel) != 0);
    CHECK(toast.frame.origin.x < -20000);           //offscreen: not on the screen of whoever runs the test
    CHECK(toast.frame.size.width > 120 && toast.frame.size.width < 400);
    CHECK(fabs(toast.frame.size.height - 48) < 0.5);

    //the setting that switches the message off: the state and the icon still change
    [defaults setInteger:0 forKey:CapsLockToastDefaultsKey];       //what the toggle of Settings saves
    [CapsLockToast hide];
    CHECK(!toast.visible);
    [CapsLockMonitor noteState:NO];
    CHECK(notifications == 4 && ![CapsLockMonitor isOn]);
    CHECK(!toast.visible);
    [defaults removeObjectForKey:CapsLockToastDefaultsKey];

    [CapsLockMonitor stop];
    fakeCaps = YES;
    Spin(0.7);                                      //stopped: the poll is gone
    CHECK(notifications == 4);

    //the real keyboard (not the stand-in): a plain yes or no, whatever it is now
    BOOL real = ([NSEvent modifierFlags] & NSEventModifierFlagCapsLock) != 0;
    printf("   info: Caps Lock of this Mac right now: %s\n", real ? "on" : "off");
}

static void TestToastTiming(void) {
    printf("-- toast timing\n");
    [CapsLockToast hide];
    [CapsLockToast showForState:YES];
    CapsLockToast* toast = [CapsLockToast panel];
    CHECK(toast.visible);
    Spin(1.0);
    CHECK(toast.visible);                           //still there at 1 s
    //pressed again: the message changes, and it stays for the full time from now
    [CapsLockToast showForState:NO];
    CHECK([toast.message isEqualToString:@"Caps Lock đã tắt"]);
    Spin(0.9);                                      //1.9 s after the first, 0.9 after the second
    CHECK(toast.visible);
    CHECK(toast.alphaValue > 0.99);                 //not fading out for the first one's time
    Spin(1.6);                                      //1.7 s after the second: gone
    CHECK(!toast.visible);

    //gone, and shown again: it comes back whole
    [CapsLockToast showForState:YES];
    CHECK(toast.visible);
    [CapsLockToast hide];
    CHECK(!toast.visible);
    Spin(1.8);                                      //the old timer fires on a hidden toast: nothing happens
    CHECK(!toast.visible);
}

static void TestIcons(NSString* pictures) {
    printf("-- icon\n");
    NSString* resources = [[NSProcessInfo processInfo].environment[@"VOK_RESOURCES"] copy];
    NSImage* glyph = [[NSImage alloc] initWithContentsOfFile:[resources stringByAppendingPathComponent:@"Status.png"]];
    CHECK(glyph != nil);
    CHECK(VOKCapsLockStatusImage(nil, YES) == nil && VOKCapsLockStatusImage(nil, NO) == nil);
    //Vietnamese: the flag, a red tile with the star in yellow in the middle
    NSImage* red = VOKCapsLockStatusImage(glyph, YES);
    CHECK(red != nil);
    CHECK(!red.isTemplate);                          //a template takes the colour of the menu bar: no red
    CHECK(fabs(red.size.width - glyph.size.width) < 0.01);

    for (int dark = 0; dark < 2; dark++) {
        NSBitmapImageRep* rep = RenderIcon(red, dark);
        int redPixels = 0, starPixels = 0, solidInTile = 0, clear = 0;
        for (NSInteger y = 0; y < 44; y++) {
            for (NSInteger x = 0; x < 44; x++) {
                Pixel p = At(rep, x, y);
                if (p.a > 0.8 && p.r > 0.75 && p.g < 0.35 && p.b < 0.35) redPixels++;
                if (p.a > 0.8 && p.r > 0.9 && p.g > 0.8 && p.b < 0.3) starPixels++;
                if (x >= 3 && x < 41 && y >= 8 && y < 36 && p.a > 0.85) solidInTile++;
                if (p.a < 0.05) clear++;
            }
        }
        printf("   %s: %d red, %d star, %d solid in the tile, %d clear\n", dark ? "dark" : "light", redPixels, starPixels, solidInTile, clear);
        CHECK(redPixels > 400);                      //the flag is red
        CHECK(starPixels > 40 && starPixels < 400);                      //with a yellow star
        CHECK(solidInTile > 38 * 28 * 0.95);
        CHECK(clear > 200);
        Pixel centre = At(rep, 22, 22);              //the star is in the middle
        CHECK(centre.r > 0.9 && centre.g > 0.75 && centre.b < 0.35);
    }

    //English: the glyph in red on the dark tile, no yellow
    NSImage* english = [[NSImage alloc] initWithContentsOfFile:[resources stringByAppendingPathComponent:@"StatusEng.png"]];
    NSBitmapImageRep* en = RenderIcon(VOKCapsLockStatusImage(english, NO), NO);
    int enRed = 0, enYellow = 0;
    for (NSInteger y = 0; y < 44; y++)
        for (NSInteger x = 0; x < 44; x++) {
            Pixel p = At(en, x, y);
            if (p.a > 0.8 && p.r > 0.85 && p.g < 0.4 && p.b < 0.4) enRed++;
            if (p.a > 0.8 && p.r > 0.85 && p.g > 0.65 && p.b < 0.25) enYellow++;
        }
    CHECK(enRed > 100 && enYellow == 0);

    //the warning is yellow, this one red: two different things must look different
    NSBitmapImageRep* warning = RenderIcon(VOKWarningStatusImage(glyph), NO);
    int yellowInWarning = 0, redInWarning = 0;
    for (NSInteger y = 0; y < 44; y++) {
        for (NSInteger x = 0; x < 44; x++) {
            Pixel p = At(warning, x, y);
            if (p.a > 0.8 && p.r > 0.85 && p.g > 0.65 && p.b < 0.25) yellowInWarning++;
            if (p.a > 0.8 && p.r > 0.85 && p.g < 0.4 && p.b < 0.4) redInWarning++;
        }
    }
    CHECK(yellowInWarning > 300);
    CHECK(redInWarning == 0);

    if (pictures.length > 0) {
        [[NSFileManager defaultManager] createDirectoryAtPath:pictures withIntermediateDirectories:YES attributes:nil error:nil];
        for (int dark = 0; dark < 2; dark++) {
            Save(IconStrip(resources, dark), [pictures stringByAppendingPathComponent:dark ? @"capslock-icons-dark.png" : @"capslock-icons-light.png"]);
            for (int on = 0; on < 2; on++) {
                [CapsLockToast hide];
                [CapsLockToast showForState:on];
                Save(Snapshot([CapsLockToast panel], dark), [pictures stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"capslock-toast-%@-%@.png", on ? @"on" : @"off", dark ? @"dark" : @"light"]]);
            }
        }
        [CapsLockToast hide];
        printf("   pictures in %s\n", pictures.UTF8String);
    }
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSString* pictures = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
        TestMonitor();
        TestToastTiming();
        TestIcons(pictures);
        printf(failures == 0 ? "ALL OK\n" : "FAILED: %d\n", failures);
        return failures == 0 ? 0 : 1;
    }
}
