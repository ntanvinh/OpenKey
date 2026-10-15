//
//  AboutPanel.m
//  VOpenKey
//

#import "AboutPanel.h"
#import "AppInfo.h"
#import "VOKUI.h"

static const CGFloat kWindowWidth = 360;
static const CGFloat kSideMargin = 32;
static const CGFloat kIconSize = 96;
static const CGFloat kLogoWidth = 104;
static const CGFloat kBrandPadding = 20;   //between the edge of the brand card and what is in it

#pragma mark - The logo

//Where the drawing is inside an image: the box of the pixels that are not transparent. The file has wide empty margins.
static CGRect OpaqueBounds(CGImageRef image) {
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    CGRect whole = CGRectMake(0, 0, width, height);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (context == NULL)
        return whole;
    CGContextDrawImage(context, whole, image);
    const uint8_t* pixels = CGBitmapContextGetData(context);
    size_t minX = width, minY = height, maxX = 0, maxY = 0;
    BOOL found = NO;
    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            if (pixels[(y * width + x) * 4 + 3] > 8) {
                found = YES;
                minX = MIN(minX, x); maxX = MAX(maxX, x);
                minY = MIN(minY, y); maxY = MAX(maxY, y);
            }
        }
    }
    CGContextRelease(context);
    //row 0 of the buffer is the top of the image, the same as for CGImageCreateWithImageInRect
    return found ? CGRectMake(minX, minY, maxX - minX + 1, maxY - minY + 1) : whole;
}

//The logo of LSSoft cut to its drawing, as a template image: the file is one light grey that would all but disappear on a
//light window, so it is tinted when it is shown. nil when the file is missing.
static NSImage* LogoImage(void) {
    NSImage* file = [NSImage imageNamed:@"lss-logo"];
    CGImageRef full = [file CGImageForProposedRect:NULL context:nil hints:nil];
    if (full == NULL)
        return nil;
    CGRect box = OpaqueBounds(full);
    CGImageRef cropped = CGImageCreateWithImageInRect(full, box);
    if (cropped == NULL)
        return nil;
    NSImage* logo = [[NSImage alloc] initWithCGImage:cropped size:NSMakeSize(kLogoWidth, round(kLogoWidth * box.size.height / box.size.width))];
    CGImageRelease(cropped);
    logo.template = YES;
    return logo;
}

//The grey of the file on a dark window, a darker one on a light window where the original would not show
static NSColor* LogoTint(void) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor*(NSAppearance* appearance) {
        BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]]
                     isEqualToString:NSAppearanceNameDarkAqua];
        return dark ? [NSColor colorWithSRGBRed:0xD1 / 255.0 green:0xD2 / 255.0 blue:0xD4 / 255.0 alpha:1]
                    : [NSColor colorWithSRGBRed:0x86 / 255.0 green:0x8A / 255.0 blue:0x90 / 255.0 alpha:1];
    }];
}

#pragma mark - The window

//Esc closes it, like the About windows of other apps
@interface AboutWindow : NSWindow
@end

@implementation AboutWindow
-(void)cancelOperation:(id)sender {
    [self performClose:sender];
}
@end

@implementation AboutPanel

//Three short paragraphs, centred. A line break inside a paragraph is U+2028, so that the lines of one paragraph stay close
//together and only the paragraphs are apart.
+(NSAttributedString*)credits {
    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    paragraph.paragraphSpacing = 10;
    paragraph.lineSpacing = 1;
    NSDictionary* plain = @{NSFontAttributeName: [NSFont systemFontOfSize:11],
                            NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
                            NSParagraphStyleAttributeName: paragraph};
    NSMutableAttributedString* credits = [[NSMutableAttributedString alloc] init];
    void (^addText)(NSString*) = ^(NSString* text) {
        [credits appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:plain]];
    };
    void (^addLink)(NSString*, NSString*) = ^(NSString* text, NSString* url) {
        NSMutableDictionary* attributes = [plain mutableCopy];
        attributes[NSLinkAttributeName] = [NSURL URLWithString:url];
        [credits appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
    };
    addText([NSString stringWithFormat:@"Fork từ OpenKey của %@,\u2028phát hành theo giấy phép GPL-3.0.\n", VOK_UPSTREAM_AUTHOR]);
    addLink(@"Mã nguồn VOpenKey AI", VOK_REPO_URL);
    addText(@"  ·  ");
    addLink(@"OpenKey gốc", VOK_UPSTREAM_URL);
    addText(@"\nTừ điển gợi ý dùng các mục từ của\u2028");
    addLink(@"Wiktionary tiếng Việt", @"https://vi.wiktionary.org");
    addText(@" (CC BY-SA 4.0)");
    return credits;
}

//"Copyright © 2026 LSSoft": the first sentence of the copyright text of Info.plist, which goes on to the fork and the licence
+(NSString*)copyrightLine {
    NSString* full = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSHumanReadableCopyright"];
    if (full.length == 0)
        return nil;
    NSRange end = [full rangeOfString:@". "];
    return end.location != NSNotFound ? [full substringToIndex:end.location] : full;
}

//The block that says who made the app: the logo of the company with its name under it, in a card like the groups of Settings
+(NSView*)brandCard {
    NSMutableArray* parts = [NSMutableArray array];
    NSImage* logo = LogoImage();
    if (logo != nil) {
        NSImageView* mark = [NSImageView imageViewWithImage:logo];
        mark.contentTintColor = LogoTint();
        mark.imageScaling = NSImageScaleProportionallyUpOrDown;
        mark.translatesAutoresizingMaskIntoConstraints = NO;
        [mark setAccessibilityLabel:VOK_COMPANY];
        [mark.widthAnchor constraintEqualToConstant:logo.size.width].active = YES;
        [mark.heightAnchor constraintEqualToConstant:logo.size.height].active = YES;
        [parts addObject:mark];
    }

    NSMutableAttributedString* name = [[NSMutableAttributedString alloc] init];
    [name appendAttributedString:[[NSAttributedString alloc] initWithString:@"Phát triển bởi " attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}]];
    [name appendAttributedString:[[NSAttributedString alloc] initWithString:VOK_COMPANY attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor labelColor]}]];
    NSTextField* credit = [NSTextField labelWithAttributedString:name];
    credit.translatesAutoresizingMaskIntoConstraints = NO;
    [parts addObject:credit];

    NSStackView* stack = [NSStackView stackViewWithViews:parts];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    //the padding is made of constraints: a stack view ignores its vertical edge insets when its views are centred
    NSView* inner = [[NSView alloc] init];
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    [inner addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:inner.topAnchor constant:kBrandPadding],
        [stack.bottomAnchor constraintEqualToAnchor:inner.bottomAnchor constant:-kBrandPadding],
        [stack.centerXAnchor constraintEqualToAnchor:inner.centerXAnchor],
    ]];
    return VOKCard(inner);
}

//Text with links that wraps at a given width. A text view, because a label does not open links reliably.
+(NSTextView*)textViewWithAttributedString:(NSAttributedString*)text width:(CGFloat)width {
    NSTextView* view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, width, 10)];
    view.editable = NO;
    view.selectable = YES;
    view.drawsBackground = NO;
    view.textContainerInset = NSZeroSize;
    view.textContainer.lineFragmentPadding = 0;
    view.textContainer.widthTracksTextView = NO;
    view.textContainer.containerSize = NSMakeSize(width, CGFLOAT_MAX);
    [view.textStorage setAttributedString:text];
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    CGFloat height = ceil([view.layoutManager usedRectForTextContainer:view.textContainer].size.height);
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [view.widthAnchor constraintEqualToConstant:width].active = YES;
    [view.heightAnchor constraintEqualToConstant:height].active = YES;
    return view;
}

+(NSView*)content {
    NSImageView* icon = [NSImageView imageViewWithImage:[NSApp applicationIconImage]];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:kIconSize].active = YES;
    [icon.heightAnchor constraintEqualToConstant:kIconSize].active = YES;

    NSTextField* name = [NSTextField labelWithString:VOK_APP_NAME];
    name.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
    NSString* version = [NSString stringWithFormat:@"Phiên bản %@ (%@)",
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
    NSTextField* versionLabel = [NSTextField labelWithString:version];
    versionLabel.font = [NSFont systemFontOfSize:12];
    versionLabel.textColor = [NSColor secondaryLabelColor];
    NSTextField* tagline = [NSTextField labelWithString:@"Bộ gõ tiếng Việt cho macOS"];
    tagline.font = [NSFont systemFontOfSize:13];

    CGFloat contentWidth = kWindowWidth - 2 * kSideMargin;
    NSView* brand = [self brandCard];
    NSTextView* credits = [self textViewWithAttributedString:[self credits] width:contentWidth];

    NSMutableArray* views = [NSMutableArray arrayWithObjects:icon, name, versionLabel, tagline, brand, credits, nil];
    NSString* copyright = [self copyrightLine];
    NSTextField* copyrightLabel = nil;
    if (copyright.length > 0) {
        copyrightLabel = [NSTextField labelWithString:copyright];
        copyrightLabel.font = [NSFont systemFontOfSize:10];
        copyrightLabel.textColor = [NSColor tertiaryLabelColor];
        [views addObject:copyrightLabel];
    }

    NSStackView* stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:12 afterView:icon];
    [stack setCustomSpacing:2 afterView:name];
    [stack setCustomSpacing:6 afterView:versionLabel];
    [stack setCustomSpacing:24 afterView:tagline];
    [stack setCustomSpacing:18 afterView:brand];
    if (copyrightLabel != nil)
        [stack setCustomSpacing:14 afterView:credits];
    [brand.widthAnchor constraintEqualToConstant:contentWidth].active = YES;

    NSView* content = [[NSView alloc] init];
    [content addSubview:stack];
    //under the transparent title bar: more room above than below
    [NSLayoutConstraint activateConstraints:@[
        [content.widthAnchor constraintEqualToConstant:kWindowWidth],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:44],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
        [stack.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
    ]];
    return content;
}

+(NSWindow*)window {
    static NSWindow* window;
    if (window != nil)
        return window;
    NSView* content = [self content];
    [content layoutSubtreeIfNeeded];
    NSSize size = content.fittingSize;
    window = [[AboutWindow alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskFullSizeContentView
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    window.title = [NSString stringWithFormat:@"Giới thiệu %@", VOK_APP_NAME];
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    window.movableByWindowBackground = YES;
    window.releasedWhenClosed = NO;
    [window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
    [window standardWindowButton:NSWindowZoomButton].hidden = YES;
    window.contentView = content;
    [window setContentSize:size];
    [window center];
    return window;
}

+(void)show {
    //a menu bar app is not active when its menu item is clicked, and the window would open behind other windows
    [NSApp activateIgnoringOtherApps:YES];
    [[self window] makeKeyAndOrderFront:nil];
}

@end
