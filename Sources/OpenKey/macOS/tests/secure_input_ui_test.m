//
//  Tests of what the person sees of secure input: the window behind "Secure Input đang bật bởi …" in the menu (SecureInputWindow:
//  every kind of holder, every effect, released, long texts, a low screen, the buttons, following the monitor while it is open) and
//  the yellow menu bar icon (VOKWarningStatusImage). Run with run-secure-input-ui-test.sh.
//
//  Nothing is shown on the screen and the keyboard and the clipboard of the user are never touched: windows are built and drawn
//  offscreen (a window that has to count as open sits at (-30000, -30000) and is never made key), "Sao chép thông tin" writes to a
//  pasteboard of its own, "Hiện trong Finder" and "Mở Activity Monitor" to blocks.
//
//   secure_input_ui_test [folder for pictures]
//
#import <Cocoa/Cocoa.h>
#import "AppInfo.h"
#import "SecureInputMonitor.h"
#import "SecureInputWindow.h"
#import "SuggestionController.h"
#import "Diagnostics.h"
#import "VOKUI.h"

//the monitor, with a session that a test decides about
static BOOL fakeSecure;
static pid_t fakeHolderPID;
Boolean FakeSecure(void) { return fakeSecure; }
CFDictionaryRef FakeSession(void) {
    return (CFDictionaryRef)CFBridgingRetain(@{@"kCGSSessionSecureInputPID": @(fakeHolderPID)});
}
int vLanguage = 1;
int vInputType = 0;
int vDiagnostics = 0;
int vUseMacro = 0;
void RequestNewSession(void) {}
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation SuggestionController
+(void)reset {}
@end
@implementation VOKDiagnostics
+(void)log:(NSString*)category message:(NSString*)message {}
@end

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static NSString* snapshotFolder;
static const CGFloat kContentWidth = 440;

#pragma mark - Helpers

static SecureInputHolder* Holder(pid_t pid, SecureInputHolderRole role, BOOL exists, NSString* name, NSString* bundle, NSString* version,
                                 NSString* path, pid_t parentPID, NSString* parentName, BOOL icon) {
    return [[SecureInputHolder alloc] initWithPID:pid role:role processExists:exists name:name bundleIdentifier:bundle version:version path:path
                                        startDate:[NSDate dateWithTimeIntervalSinceNow:-5400] parentPID:parentPID parentName:parentName
                                             icon:icon ? [NSImage imageNamed:NSImageNameApplicationIcon] : nil];
}

static SecureInputHolder* Terminal(SecureInputHolderRole role) {
    return Holder(4242, role, YES, @"Terminal", @"com.apple.Terminal", @"2.14 (455)", @"/System/Applications/Utilities/Terminal.app", 0, nil, YES);
}

static BOOL Has(NSArray<NSString*>* list, NSString* part) {
    for (NSString* item in list) {
        if ([item containsString:part])
            return YES;
    }
    return NO;
}

//the text of a label needs no more room than the label has (a wrapping label that kept the height of one line shows as cut off)
static void CheckLabels(NSView* view, int* clipped) {
    if ([view isKindOfClass:[NSTextField class]] && !view.hidden) {
        NSTextField* label = (NSTextField*)view;
        if (label.stringValue.length > 1 && !label.isEditable) {
            NSSize needed = [label.cell cellSizeForBounds:NSMakeRect(0, 0, label.frame.size.width, CGFLOAT_MAX)];
            if (needed.height > label.frame.size.height + 1) {
                printf("   clipped label: %s (needs %.0f, has %.0f)\n", label.stringValue.UTF8String, needed.height, label.frame.size.height);
                (*clipped)++;
            }
        }
    }
    for (NSView* child in view.subviews)
        CheckLabels(child, clipped);
}

//nothing sticks out at the sides of the window, and no button is squeezed below the room its title needs
static void CheckBounds(NSView* root, NSView* view, int* outside) {
    NSRect box = [view convertRect:view.bounds toView:root];
    if (!view.hidden && (NSMinX(box) < -0.5 || NSMaxX(box) > kContentWidth + 0.5)) {
        printf("   sticks out: %s (%.0f to %.0f)\n", NSStringFromClass([view class]).UTF8String, NSMinX(box), NSMaxX(box));
        (*outside)++;
    }
    if ([view isKindOfClass:[NSButton class]] && !view.hidden && view.frame.size.width + 1 < view.fittingSize.width) {
        printf("   squeezed button: %s (%.0f of %.0f)\n", ((NSButton*)view).title.UTF8String, view.frame.size.width, view.fittingSize.width);
        (*outside)++;
    }
    for (NSView* child in view.subviews)
        CheckBounds(root, child, outside);
}

static void Snapshot(NSWindow* window, NSString* name, BOOL dark) {
    if (snapshotFolder == nil)
        return;
    window.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    //the frame of the window holds its background: drawing that one, not the content alone, gives the colours of a window
    NSView* frame = window.contentView.superview;
    [frame layoutSubtreeIfNeeded];
    NSRect rect = [frame convertRect:window.contentView.frame fromView:window.contentView];
    NSBitmapImageRep* cached = [frame bitmapImageRepForCachingDisplayInRect:rect];
    [frame.effectiveAppearance performAsCurrentDrawingAppearance:^{ [frame cacheDisplayInRect:rect toBitmapImageRep:cached]; }];
    NSData* png = [cached representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:[snapshotFolder stringByAppendingPathComponent:[name stringByAppendingString:dark ? @"-dark.png" : @"-light.png"]] atomically:YES];
}

//Shows a state, checks it is laid out cleanly in both appearances and writes the pictures. The window is rebuilt for each state.
static SecureInputWindow* Show(NSString* name, SecureInputHolder* holder, SecureInputEffect effect, SecureInputHolder* last, NSDate* releasedAt) {
    SecureInputWindow* window = [[SecureInputWindow alloc] init];
    window.pasteboard = [NSPasteboard pasteboardWithUniqueName];
    window.maximumHeightForTesting = 5000;                           //as high as the content, as on a tall screen
    [window displayHolder:holder effect:effect lastHolder:last releasedAt:releasedAt];
    for (int dark = 0; dark < 2; dark++) {
        window.window.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
        [window.documentView layoutSubtreeIfNeeded];
        int clipped = 0, outside = 0;
        CheckLabels(window.documentView, &clipped);
        CheckBounds(window.documentView, window.documentView, &outside);
        if (clipped != 0 || outside != 0)
            printf("   in state '%s' (%s)\n", name.UTF8String, dark ? "dark" : "light");
        CHECK(clipped == 0);
        CHECK(outside == 0);
        Snapshot(window.window, name, dark);
    }
    CHECK(fabs(window.window.contentLayoutRect.size.width - kContentWidth) < 0.5);
    return window;
}

#pragma mark - Window states

static void TestHolders(void) {
    printf("-- holders\n");

    //an app in the background, typing Vietnamese is off: the usual case
    SecureInputWindow* w = Show(@"blocked-background", Terminal(SecureInputHolderRoleBackgroundApp), SecureInputEffectBlocked, nil, nil);
    CHECK([w.headingLabel.stringValue isEqualToString:@"Secure Input đang bật bởi Terminal"]);
    CHECK([w.explanationLabel.stringValue containsString:@"tạm chuyển sang tiếng Anh"]);
    CHECK([w.explanationLabel.stringValue containsString:@"vàng"]);
    CHECK([w.explanationLabel.stringValue containsString:VOK_APP_NAME]);
    NSArray* rows = w.rowTexts;
    CHECK([rows containsObject:@"Tên\nTerminal"]);
    CHECK(Has(rows, @"Vai trò\nỨng dụng đang chạy nền"));
    CHECK([rows containsObject:@"PID\n4242"]);
    CHECK([rows containsObject:@"Bundle ID\ncom.apple.Terminal"]);
    CHECK([rows containsObject:@"Phiên bản\n2.14 (455)"]);
    CHECK([rows containsObject:@"Đường dẫn\n/System/Applications/Utilities/Terminal.app"]);
    CHECK(Has(rows, @"Chạy từ\n"));
    CHECK(!Has(rows, @"Mở bởi"));                                   //started by launchd: nothing to say
    CHECK(w.tipTexts.count == 3);
    CHECK(Has(w.tipTexts, @"quên nhả"));
    CHECK(w.revealButton != nil && w.copyButton != nil && w.activityMonitorButton != nil && w.closeButton != nil);
    CHECK([w.closeButton.keyEquivalent isEqualToString:@"\r"]);     //Return closes it: nothing here is dangerous
    CHECK(w.copyButton.keyEquivalent.length == 0 && w.revealButton.keyEquivalent.length == 0);
    CHECK([w.noticeLabel.stringValue isEqualToString:@" "]);        //a line is kept for what the buttons say
    CHECK([w.window.title isEqualToString:@"Secure Input"]);
    CHECK(w.window.contentView != nil);

    //macOS' own Vietnamese source typing for us, and VOpenKey AI in English mode: three ways to say what it costs
    w = Show(@"fallback", Terminal(SecureInputHolderRoleBackgroundApp), SecureInputEffectFallback, nil, nil);
    CHECK([w.explanationLabel.stringValue containsString:@"bộ gõ Vietnamese của macOS"]);
    CHECK(![w.explanationLabel.stringValue containsString:@"vàng"]);
    w = Show(@"english-mode", Terminal(SecureInputHolderRoleBackgroundApp), SecureInputEffectNone, nil, nil);
    CHECK([w.explanationLabel.stringValue containsString:@"chế độ English"]);

    //the app being typed in
    w = Show(@"front-app", Terminal(SecureInputHolderRoleFrontApp), SecureInputEffectBlocked, nil, nil);
    CHECK(Has(w.rowTexts, @"Vai trò\nỨng dụng bạn đang gõ"));
    CHECK(Has(w.tipTexts, @"ô nhập mật khẩu") && Has(w.tipTexts, @"Secure Keyboard Entry"));

    //a helper started by an app: the parent says whose it is
    SecureInputHolder* helper = Holder(5151, SecureInputHolderRoleHelper, YES, @"Google Chrome Helper", @"com.google.Chrome.helper", @"130.0.1",
                                       @"/Applications/Google Chrome.app/Contents/Frameworks/Helper.app", 5100, @"Google Chrome", NO);
    w = Show(@"helper", helper, SecureInputEffectBlocked, nil, nil);
    CHECK(Has(w.rowTexts, @"Vai trò\nỨng dụng trên thanh menu hoặc tiến trình nền"));
    CHECK([w.rowTexts containsObject:@"Mở bởi\nGoogle Chrome (PID 5100)"]);
    CHECK(Has(w.tipTexts, @"thanh menu"));

    //part of macOS
    SecureInputHolder* system = Holder(88, SecureInputHolderRoleSystem, YES, @"SecurityAgent", @"com.apple.SecurityAgent", nil,
                                       @"/System/Library/Frameworks/Security.framework/Versions/A/MachServices/SecurityAgent.bundle", 0, nil, NO);
    w = Show(@"system", system, SecureInputEffectBlocked, nil, nil);
    CHECK(Has(w.rowTexts, @"Vai trò\nTiến trình của macOS"));
    CHECK(Has(w.tipTexts, @"hộp thoại mật khẩu"));
    CHECK(![w.rowTexts containsObject:@"Phiên bản\n"] && !Has(w.rowTexts, @"Phiên bản"));

    //the lock screen
    w = Show(@"locked", Holder(90, SecureInputHolderRoleLockedSession, YES, @"loginwindow", @"com.apple.loginwindow", nil,
                               @"/System/Library/CoreServices/loginwindow.app", 0, nil, NO), SecureInputEffectBlocked, nil, nil);
    CHECK(Has(w.rowTexts, @"Vai trò\nMàn hình khóa"));
    CHECK(Has(w.tipTexts, @"mở khóa"));

    //macOS names nobody: no PID, no path, no "Hiện trong Finder", and the advice is what to try
    w = Show(@"unknown", Holder(0, SecureInputHolderRoleUnknown, NO, nil, nil, nil, nil, 0, nil, NO), SecureInputEffectBlocked, nil, nil);
    CHECK([w.headingLabel.stringValue isEqualToString:@"Secure Input đang bật"]);
    CHECK([w.rowTexts containsObject:@"Tên\nmacOS không cho biết"]);
    CHECK(!Has(w.rowTexts, @"PID") && !Has(w.rowTexts, @"Đường dẫn") && !Has(w.rowTexts, @"Bundle ID"));
    CHECK(w.revealButton == nil);
    CHECK(w.copyButton != nil && w.activityMonitorButton != nil);
    CHECK(Has(w.tipTexts, @"macOS không cho biết ứng dụng nào") && Has(w.tipTexts, @"iTerm2"));

    //a process number that no longer runs
    w = Show(@"gone", Holder(777, SecureInputHolderRoleUnknown, NO, nil, nil, nil, nil, 0, nil, NO), SecureInputEffectBlocked, nil, nil);
    CHECK([w.headingLabel.stringValue isEqualToString:@"Secure Input đang bật bởi tiến trình 777"]);
    CHECK([w.rowTexts containsObject:@"Vai trò\nTiến trình đã thoát"]);
    CHECK([w.rowTexts containsObject:@"Tên\nKhông đọc được tên"]);
    CHECK([w.rowTexts containsObject:@"PID\n777"]);
    CHECK(Has(w.tipTexts, @"Đăng xuất"));
}

static void TestReleased(void) {
    printf("-- released\n");
    SecureInputHolder* last = Terminal(SecureInputHolderRoleBackgroundApp);
    SecureInputWindow* w = Show(@"released", nil, SecureInputEffectNone, last, [NSDate date]);
    CHECK([w.headingLabel.stringValue isEqualToString:@"Secure Input đã tắt"]);
    CHECK([w.explanationLabel.stringValue containsString:@"Tắt lúc"]);
    CHECK([w.explanationLabel.stringValue containsString:@"đọc được phím trở lại"]);
    CHECK(![w.explanationLabel.stringValue containsString:@"tiếng Việt"]);           //true only in Vietnamese mode: not said here
    CHECK(w.tipTexts.count == 0);                                   //nothing to track down any more
    CHECK([w.rowTexts containsObject:@"Tên\nTerminal"]);            //but who it was stays in view
    CHECK(w.copyButton != nil && w.closeButton != nil);

    //never was on: nothing to list, nothing to copy
    w = Show(@"never", nil, SecureInputEffectNone, nil, nil);
    CHECK([w.headingLabel.stringValue isEqualToString:@"Secure Input đang tắt"]);
    CHECK(w.rowTexts.count == 0 && w.tipTexts.count == 0);
    CHECK(w.copyButton == nil && w.activityMonitorButton == nil && w.revealButton == nil && w.closeButton != nil);
    [w copyInformation];                                            //does nothing, and does not fail
    CHECK([w.noticeLabel.stringValue isEqualToString:@" "]);
}

static void TestLongTexts(void) {
    printf("-- long texts and a low screen\n");
    NSString* longName = @"Một Ứng Dụng Có Cái Tên Rất Dài Để Thử Xem Dòng Chữ Có Bị Cắt Hay Không Khi Tên Dài Hơn Cả Cửa Sổ";
    NSString* longPath = @"/Users/someone-with-a-very-long-account-name/Library/Application Support/Some Vendor/Some Product Name/Versions/2026.11.03-build-123456/Contents/MacOS/helper-tool-with-long-name";
    NSString* longBundle = @"com.some-vendor-with-a-long-name.product.name.helper.agent.background.service.for.keyboards";
    SecureInputHolder* holder = Holder(31337, SecureInputHolderRoleBackgroundApp, YES, longName, longBundle, @"2026.11.03.123456-beta.7 (1234567890)",
                                       longPath, 31000, @"Một Trình Quản Lý Tiến Trình Có Tên Cũng Rất Dài Như Vậy", YES);
    SecureInputWindow* w = Show(@"long", holder, SecureInputEffectBlocked, nil, nil);
    CHECK([w.headingLabel.stringValue containsString:longName]);
    CHECK([w.rowTexts containsObject:[@"Đường dẫn\n" stringByAppendingString:longPath]]);
    CHECK([w informationText].length > longPath.length + longBundle.length);

    //a screen too low for the window: it keeps its width, is cut to the room, and the content scrolls
    SecureInputWindow* low = [[SecureInputWindow alloc] init];
    low.maximumHeightForTesting = 320;
    [low displayHolder:Terminal(SecureInputHolderRoleBackgroundApp) effect:SecureInputEffectBlocked lastHolder:nil releasedAt:nil];
    CHECK(low.window.frame.size.height <= 321);
    CHECK(low.documentView.fittingSize.height > 400);
    CHECK([low.window.contentView isKindOfClass:[NSScrollView class]] && ((NSScrollView*)low.window.contentView).hasVerticalScroller);
    CHECK(fabs(low.window.contentLayoutRect.size.width - kContentWidth) < 0.5);
    //a state that is shorter again is not left with the old height
    low.maximumHeightForTesting = 0;
    [low displayHolder:nil effect:SecureInputEffectNone lastHolder:nil releasedAt:nil];
    CHECK(low.window.frame.size.height < 450);
}

#pragma mark - Actions

static void TestActions(void) {
    printf("-- actions\n");
    NSString* finder = @"/System/Library/CoreServices/Finder.app";
    SecureInputHolder* holder = Holder(4242, SecureInputHolderRoleBackgroundApp, YES, @"Finder", @"com.apple.finder", @"15.0", finder, 0, nil, NO);
    SecureInputWindow* w = [[SecureInputWindow alloc] init];
    NSPasteboard* board = [NSPasteboard pasteboardWithUniqueName];
    NSInteger userBoardChanges = [NSPasteboard generalPasteboard].changeCount;
    w.pasteboard = board;
    __block NSURL* revealed = nil;
    __block int activityMonitorOpened = 0;
    w.revealURL = ^(NSURL* url) { revealed = url; };
    w.openActivityMonitor = ^{ activityMonitorOpened++; };
    [w displayHolder:holder effect:SecureInputEffectBlocked lastHolder:nil releasedAt:nil];

    //"Hiện trong Finder" shows exactly the file named in the path row
    [w.revealButton performClick:nil];
    CHECK(revealed != nil && [revealed.path isEqualToString:finder]);
    CHECK([w.revealButton.accessibilityLabel containsString:@"Finder"]);

    //the file is gone: the person is told, Finder is not asked
    revealed = nil;
    [w displayHolder:Holder(4242, SecureInputHolderRoleBackgroundApp, YES, @"Gone", nil, nil, @"/Applications/Nothing Here 12345.app", 0, nil, NO)
              effect:SecureInputEffectBlocked lastHolder:nil releasedAt:nil];
    [w.revealButton performClick:nil];
    CHECK(revealed == nil);
    CHECK([w.noticeLabel.stringValue containsString:@"Không tìm thấy"]);
    CHECK(w.noticeLabel.textColor != nil && ![w.noticeLabel.textColor isEqual:[NSColor secondaryLabelColor]]);   //an error does not look like a hint

    //"Mở Activity Monitor" opens it and says what to search for
    [w displayHolder:holder effect:SecureInputEffectBlocked lastHolder:nil releasedAt:nil];
    [w.activityMonitorButton performClick:nil];
    CHECK(activityMonitorOpened == 1);
    CHECK([w.noticeLabel.stringValue containsString:@"PID 4242"]);

    //"Sao chép thông tin": every fact, one per line, on the pasteboard of the test
    [w.copyButton performClick:nil];
    NSString* copied = [board stringForType:NSPasteboardTypeString];
    CHECK(copied != nil);
    CHECK([copied containsString:@"Secure Input đang bật bởi Finder"]);
    CHECK([copied containsString:@"Tên: Finder"]);
    CHECK([copied containsString:@"PID: 4242"]);
    CHECK([copied containsString:@"Bundle ID: com.apple.finder"]);
    CHECK([copied containsString:[@"Đường dẫn: " stringByAppendingString:finder]]);
    CHECK([copied containsString:@"Vai trò: Ứng dụng đang chạy nền"]);
    CHECK([copied isEqualToString:[w informationText]]);
    CHECK([w.noticeLabel.stringValue isEqualToString:@"Đã sao chép thông tin."]);
    CHECK([NSPasteboard generalPasteboard].changeCount == userBoardChanges);       //the clipboard of the user is untouched

    //the notice goes away when the window shows something else, and the window stays the same width
    [w displayHolder:nil effect:SecureInputEffectNone lastHolder:holder releasedAt:[NSDate date]];
    CHECK([w.noticeLabel.stringValue isEqualToString:@" "]);

    //the buttons are really wired: Đóng closes a window that is open
    w.window.title = @"Secure Input";
    [w.window setFrameOrigin:NSMakePoint(-30000, -30000)];
    [w.window orderFrontRegardless];
    CHECK(w.window.visible);
    [w.closeButton performClick:nil];
    CHECK(!w.window.visible);
}

#pragma mark - Following the monitor

static void TestFollowsMonitor(void) {
    printf("-- follows the monitor\n");
    //the window asks the monitor and the saved language: VOpenKey AI is set to Vietnamese here
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"InputMethod": @1}];
    fakeSecure = NO;
    fakeHolderPID = 0;
    [SecureInputMonitor start];
    [SecureInputMonitor performSelector:NSSelectorFromString(@"evaluate")];

    SecureInputWindow* w = [[SecureInputWindow alloc] init];
    w.pasteboard = [NSPasteboard pasteboardWithUniqueName];
    [w displayHolder:nil effect:SecureInputEffectNone lastHolder:nil releasedAt:nil];
    [w.window setFrameOrigin:NSMakePoint(-30000, -30000)];
    [w.window orderFrontRegardless];                               //open, but nowhere a person can see it, and never key
    CHECK([w.headingLabel.stringValue isEqualToString:@"Secure Input đang tắt"]);

    //a program takes secure input: the open window shows it without being asked
    NSTask* sleeper = [NSTask launchedTaskWithLaunchPath:@"/bin/sleep" arguments:@[@"120"]];
    fakeHolderPID = sleeper.processIdentifier;
    fakeSecure = YES;
    [SecureInputMonitor performSelector:NSSelectorFromString(@"evaluate")];
    CHECK([w.headingLabel.stringValue isEqualToString:@"Secure Input đang bật bởi sleep"]);
    CHECK([w.explanationLabel.stringValue containsString:@"tạm chuyển sang tiếng Anh"]);
    CHECK([w.rowTexts containsObject:[NSString stringWithFormat:@"PID\n%d", sleeper.processIdentifier]]);
    CHECK([w.rowTexts containsObject:@"Đường dẫn\n/bin/sleep"]);
    CHECK([w.rowTexts containsObject:[NSString stringWithFormat:@"Mở bởi\n%@ (PID %d)", [NSProcessInfo processInfo].processName, getpid()]]);

    //released: it says so and keeps who it was
    fakeSecure = NO;
    [SecureInputMonitor performSelector:NSSelectorFromString(@"evaluate")];
    CHECK([w.headingLabel.stringValue isEqualToString:@"Secure Input đã tắt"]);
    CHECK([w.rowTexts containsObject:@"Tên\nsleep"]);
    CHECK(w.tipTexts.count == 0);

    //a window that is closed is left alone
    [w.window orderOut:nil];
    NSTextField* before = w.headingLabel;
    fakeSecure = YES;
    [SecureInputMonitor performSelector:NSSelectorFromString(@"evaluate")];
    CHECK(w.headingLabel == before);

    [SecureInputMonitor stop];
    [sleeper terminate];
    [sleeper waitUntilExit];
}

#pragma mark - The icon

//the colour of the pixel at a point of an image drawn at 44 x 44 (the 2x size of the menu bar), top left origin
typedef struct { CGFloat r, g, b, a; } Pixel;

static NSBitmapImageRep* Render(NSImage* image, BOOL dark) {
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

static void TestIcon(void) {
    printf("-- icon\n");
    //the icon of the menu bar, a flag in one colour on transparent, as the real file is
    NSString* resources = [[NSProcessInfo processInfo].environment[@"VOK_RESOURCES"] copy];
    NSImage* glyph = [[NSImage alloc] initWithContentsOfFile:[resources stringByAppendingPathComponent:@"StatusEng.png"]];
    CHECK(glyph != nil);
    CHECK(VOKWarningStatusImage(nil) == nil);

    NSImage* warning = VOKWarningStatusImage(glyph);
    CHECK(warning != nil);
    CHECK(!warning.isTemplate);                                       //a template would be tinted like the other icons: no yellow
    CHECK(fabs(warning.size.width - glyph.size.width) < 0.01 && fabs(warning.size.height - glyph.size.height) < 0.01);

    for (int dark = 0; dark < 2; dark++) {
        NSBitmapImageRep* rep = Render(warning, dark);
        //yellow and darker pixels, whatever the appearance: it is seen on a light menu bar and on a dark one
        int yellow = 0, shaded = 0, clear = 0, total = 0, solidInTile = 0;
        for (NSInteger y = 0; y < 44; y++) {
            for (NSInteger x = 0; x < 44; x++) {
                Pixel p = At(rep, x, y);
                total++;
                if (p.a < 0.05) clear++;
                if (p.a > 0.8 && p.r > 0.85 && p.g > 0.65 && p.g < 0.9 && p.b < 0.25) yellow++;
                else if (p.a > 0.8 && p.r < 0.7) shaded++;                 //the tile showing between the yellow stripes
                if (x >= 3 && x < 41 && y >= 8 && y < 36 && p.a > 0.85) solidInTile++;
            }
        }
        printf("   %s: %d yellow, %d shaded, %d clear, %d solid in the tile, of %d\n", dark ? "dark" : "light", yellow, shaded, clear, solidInTile, total);
        CHECK(yellow > 300);                                          //the flag, clearly yellow
        CHECK(shaded > 20);                                           //the tile behind it shows between the stripes
        CHECK(solidInTile > 38 * 28 * 0.95);                          //the tile is solid: no hole where the menu bar would show through
        CHECK(clear > 200);                                           //the corners and the space around the tile stay transparent
        CHECK(At(rep, 0, 0).a < 0.05);
        CHECK(At(rep, 22, 22).a > 0.8);
    }

    //the same glyph in its usual colour has no yellow at all: the yellow is the warning's own
    NSBitmapImageRep* plain = Render(glyph, NO);
    int plainYellow = 0;
    for (NSInteger y = 0; y < 44; y++) {
        for (NSInteger x = 0; x < 44; x++) {
            Pixel p = At(plain, x, y);
            if (p.a > 0.5 && p.r > 0.85 && p.g > 0.65 && p.b < 0.25)
                plainYellow++;
        }
    }
    CHECK(plainYellow == 0);

    if (snapshotFolder != nil) {
        //the icon at 8x, on a light and a dark menu bar, next to the English and the Vietnamese ones
        NSImage* vietnamese = [[NSImage alloc] initWithContentsOfFile:[resources stringByAppendingPathComponent:@"Status.png"]];
        CGFloat scale = 8;
        NSSize canvas = NSMakeSize(2 * 100, 34);
        NSBitmapImageRep* out = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:canvas.width * scale pixelsHigh:canvas.height * scale
                                                                    bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                   colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        out.size = canvas;
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:out]];
        for (int dark = 0; dark < 2; dark++) {
            NSRect bar = NSMakeRect(dark * 100, 0, 100, 34);
            [(dark ? [NSColor colorWithWhite:0.18 alpha:1] : [NSColor colorWithWhite:0.93 alpha:1]) setFill];
            NSRectFill(bar);
            [[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua] performAsCurrentDrawingAppearance:^{
                NSColor* tint = dark ? [NSColor whiteColor] : [NSColor colorWithWhite:0.15 alpha:1];
                NSArray* images = @[vietnamese, glyph, warning];
                for (int i = 0; i < 3; i++) {
                    NSImage* image = images[i];
                    NSRect where = NSMakeRect(bar.origin.x + 10 + i * 28, 6, 22, 22);
                    if (i < 2) {
                        //how the menu bar draws a template image
                        NSImage* tinted = [NSImage imageWithSize:image.size flipped:NO drawingHandler:^BOOL(NSRect r) {
                            [image drawInRect:r];
                            [tint set];
                            NSRectFillUsingOperation(r, NSCompositingOperationSourceAtop);
                            return YES;
                        }];
                        [tinted drawInRect:where];
                    } else {
                        [image drawInRect:where];
                    }
                }
            }];
        }
        [NSGraphicsContext restoreGraphicsState];
        [[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[snapshotFolder stringByAppendingPathComponent:@"icon.png"] atomically:YES];
    }

    //the symbol of the menu item: a triangle with its two layers coloured
    NSImage* symbol = VOKPaletteSymbol(@"exclamationmark.triangle.fill", 13, @[[NSColor blackColor], [NSColor systemYellowColor]]);
    CHECK(symbol != nil);
    CHECK(!symbol.isTemplate);
    CHECK(VOKPaletteSymbol(@"no.such.symbol.name", 13, @[[NSColor redColor]]) == nil);
}

int main(int argc, char** argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];   //no Dock icon, no focus
        snapshotFolder = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : nil;
        if (snapshotFolder != nil)
            [[NSFileManager defaultManager] createDirectoryAtPath:snapshotFolder withIntermediateDirectories:YES attributes:nil error:nil];
        TestHolders();
        TestReleased();
        TestLongTexts();
        TestActions();
        TestFollowsMonitor();
        TestIcon();
        printf(failures == 0 ? "secure_input_ui_test: ALL OK\n" : "secure_input_ui_test: %d FAILED\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
