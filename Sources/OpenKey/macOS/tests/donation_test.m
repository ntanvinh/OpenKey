// Tests of the donation screen: the VietQR payload and its checksum (with the example published by VietQR), what the code is made of, the
// code read back from the picture, the payee of AppInfo.h against marketing/pricing/pricing.json, the files that the Windows program shows
// (engine/DonationInfo.h, and the picture engine/donation/donation-qr.bmp, which must say what the code of this program says), and the
// window (copying, PayPal, "Tôi đã ủng hộ" and taking it back). Run with run-donation-test.sh.
//
//   donation_test <marketing/pricing/pricing.json> <Sources/OpenKey/engine> [folder for pictures of the window]
//
// Nothing is shown on the screen and the clipboard of the user is never touched: the window is built and drawn offscreen, "Sao chép"
// writes to a pasteboard of its own and "Mở PayPal" to a block.
#import <Cocoa/Cocoa.h>
#import <CoreImage/CoreImage.h>
#import "AppInfo.h"
#import "Donation.h"
#import "DonationWindow.h"

static int failures = 0;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

//the fields of a TLV string; nil when a length does not fit
static NSDictionary<NSString*, NSString*>* Fields(NSString* payload) {
    NSMutableDictionary* fields = [NSMutableDictionary dictionary];
    NSUInteger offset = 0;
    while (offset < payload.length) {
        if (offset + 4 > payload.length)
            return nil;
        NSString* identifier = [payload substringWithRange:NSMakeRange(offset, 2)];
        NSInteger length = [[payload substringWithRange:NSMakeRange(offset + 2, 2)] integerValue];
        if (offset + 4 + length > payload.length)
            return nil;
        fields[identifier] = [payload substringWithRange:NSMakeRange(offset + 4, length)];
        offset += 4 + length;
    }
    return fields;
}

static void TestChecksum(void) {
    printf("-- checksum\n");
    //the standard check value of CRC-16/CCITT-FALSE
    CHECK([[Donation checksumOfPayload:@"123456789"] isEqualToString:@"29B1"]);
    //the example of https://www.vietqr.io/generate, the one the donate screen of VMonitor AI is tested with
    NSString* example = @"00020101021238560010A0000007270126000697041501121133666688880208QRIBFTTA53037045405790005802VN62220818Ung Ho Quy Vac Xin6304";
    CHECK([[Donation checksumOfPayload:example] isEqualToString:@"3ACF"]);
    CHECK([[Donation checksumOfPayload:@""] isEqualToString:@"FFFF"]);
}

static void TestPayload(void) {
    printf("-- payload\n");
    NSString* payload = [Donation qrPayload];
    CHECK(payload != nil);
    NSDictionary* root = Fields(payload);
    CHECK(root != nil);
    NSDictionary* merchant = Fields(root[@"38"]);
    NSDictionary* beneficiary = Fields(merchant[@"01"]);
    CHECK([merchant[@"00"] isEqualToString:@"A000000727"] && [merchant[@"02"] isEqualToString:@"QRIBFTTA"]);
    CHECK([beneficiary[@"00"] isEqualToString:VOK_DONATE_BANK_BIN] && [beneficiary[@"01"] isEqualToString:VOK_DONATE_ACCOUNT_NO]);
    CHECK([root[@"00"] isEqualToString:@"01"] && [root[@"01"] isEqualToString:@"11"]);       //static: the amount is the donor's
    CHECK([root[@"53"] isEqualToString:@"704"] && [root[@"58"] isEqualToString:@"VN"]);
    CHECK(root[@"54"] == nil);                                                                //no amount
    CHECK([Fields(root[@"62"])[@"08"] isEqualToString:VOK_DONATE_NOTE]);
    CHECK([root[@"63"] isEqualToString:[Donation checksumOfPayload:[payload substringToIndex:payload.length - 4]]]);
    CHECK([payload hasSuffix:[@"6304" stringByAppendingString:root[@"63"]]]);

    //Byte for byte what the donate screen of VMonitor AI makes (donationQrPayload in v_screen/apps/desktop/src/shared/donation.ts, run with
    //Node on the same account), for its own note and for ours: the QR code of that screen is known to be read by banking apps
    CHECK([[Donation qrPayloadForBank:@"VPBank" bin:@"970432" account:@"0988181872" note:@"VMonitor AI donate"]
           isEqualToString:@"00020101021138540010A00000072701240006970432011009881818720208QRIBFTTA53037045802VN62220818VMonitor AI donate630412F0"]);
    CHECK([payload isEqualToString:@"00020101021138540010A00000072701240006970432011009881818720208QRIBFTTA53037045802VN62220818VOpenKey AI donate6304A714"]);

    //what must not make a code: another bank, another BIN, an account that is not digits, notes that cannot be written in a QR field
    CHECK([Donation qrPayloadForBank:@"Vietcombank" bin:@"970432" account:@"0988181872" note:@"x"] == nil);
    CHECK([Donation qrPayloadForBank:@"VPBank" bin:@"970436" account:@"0988181872" note:@"x"] == nil);
    CHECK([Donation qrPayloadForBank:@"vpbank" bin:@"970432" account:@"0988181872" note:@"x"] != nil);       //the name is not case sensitive
    CHECK([Donation qrPayloadForBank:@"VPBank" bin:@"970432" account:@"09881 81872" note:@"x"] == nil);
    CHECK([Donation qrPayloadForBank:@"VPBank" bin:@"970432" account:@"" note:@"x"] == nil);
    CHECK([Donation qrPayloadForBank:@"VPBank" bin:@"970432" account:@"12345678901234567890" note:@"x"] == nil);   //20 digits
    CHECK([Donation qrPayloadForBank:@"VPBank" bin:@"970432" account:@"0988181872" note:@"Ủng hộ"] == nil);       //not ASCII
    CHECK([Donation qrPayloadForBank:@"VPBank" bin:@"970432" account:@"0988181872" note:[@"" stringByPaddingToLength:100 withString:@"a" startingAtIndex:0]] == nil);
    CHECK([Donation qrPayloadForBank:@"VPBank" bin:@"970432" account:@"0988181872" note:nil] == nil);
    CHECK([Donation qrPayloadForBank:@"VPBank" bin:@"970432" account:@"0988181872" note:[@"" stringByPaddingToLength:99 withString:@"a" startingAtIndex:0]] != nil);
}

//AppInfo.h and the marketing data are two copies of one fact: a change of the payee in one of them must not be forgotten in the other
static void TestPayeeMatchesPricing(NSString* path) {
    printf("-- payee\n");
    NSData* data = [NSData dataWithContentsOfFile:path];
    NSDictionary* pricing = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary* trusted = pricing[@"payments"][@"trusted"];
    CHECK(trusted != nil);
    NSDictionary* domestic = trusted[@"domestic"];
    CHECK([domestic[@"bankId"] isEqualToString:VOK_DONATE_BANK_NAME]);
    CHECK([domestic[@"accountNo"] isEqualToString:VOK_DONATE_ACCOUNT_NO]);
    CHECK([domestic[@"accountName"] isEqualToString:VOK_DONATE_ACCOUNT_NAME]);
    NSDictionary* international = trusted[@"international"];
    CHECK([international[@"provider"] isEqualToString:@"paypal"]);
    CHECK([international[@"url"] isEqualToString:VOK_DONATE_PAYPAL_URL]);
    CHECK([international[@"accountName"] isEqualToString:VOK_DONATE_PAYPAL_NAME]);
    //the link is one that a browser is sent to: https, and on PayPal's own domain
    NSURL* url = [NSURL URLWithString:VOK_DONATE_PAYPAL_URL];
    CHECK([url.scheme isEqualToString:@"https"] && [url.host isEqualToString:@"paypal.me"] && url.user == nil);
}

static NSString* ReadQR(NSImage* image) {
    CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (cg == NULL)
        return nil;
    CIDetector* detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
    for (CIFeature* feature in [detector featuresInImage:[CIImage imageWithCGImage:cg]])
        if ([feature isKindOfClass:[CIQRCodeFeature class]])
            return ((CIQRCodeFeature*)feature).messageString;
    return nil;
}

//The Windows program has no QR encoder: it shows a picture and the constants of engine/DonationInfo.h. Both must be what this program
//makes and says, or the two programs would send the money to different places.
static NSString* DefineValue(NSString* header, NSString* name) {
    NSString* pattern = [NSString stringWithFormat:@"#define %@\\s+\"([^\"]*)\"", name];
    NSRegularExpression* expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult* match = [expression firstMatchInString:header options:0 range:NSMakeRange(0, header.length)];
    return match != nil ? [header substringWithRange:[match rangeAtIndex:1]] : nil;
}

static void TestWindowsData(NSString* engine) {
    printf("-- the files of the Windows program\n");
    NSString* header = [NSString stringWithContentsOfFile:[engine stringByAppendingPathComponent:@"DonationInfo.h"] encoding:NSUTF8StringEncoding error:nil];
    CHECK(header.length > 0);
    CHECK([DefineValue(header, @"VOK_DONATION_BANK_NAME") isEqualToString:VOK_DONATE_BANK_NAME]);
    CHECK([DefineValue(header, @"VOK_DONATION_BANK_BIN") isEqualToString:VOK_DONATE_BANK_BIN]);
    CHECK([DefineValue(header, @"VOK_DONATION_ACCOUNT_NO") isEqualToString:VOK_DONATE_ACCOUNT_NO]);
    CHECK([DefineValue(header, @"VOK_DONATION_ACCOUNT_NAME") isEqualToString:VOK_DONATE_ACCOUNT_NAME]);
    CHECK([DefineValue(header, @"VOK_DONATION_NOTE") isEqualToString:VOK_DONATE_NOTE]);
    CHECK([DefineValue(header, @"VOK_DONATION_PAYPAL_URL") isEqualToString:VOK_DONATE_PAYPAL_URL]);
    CHECK([DefineValue(header, @"VOK_DONATION_PAYPAL_NAME") isEqualToString:VOK_DONATE_PAYPAL_NAME]);
    //the picture that the Windows window shows is read back as the text of the code of this program (scripts/make-donation-qr.sh makes it again)
    NSString* path = [[engine stringByAppendingPathComponent:@"donation"] stringByAppendingPathComponent:@"donation-qr.bmp"];
    NSImage* picture = [[NSImage alloc] initWithContentsOfFile:path];
    CHECK(picture != nil);
    CHECK([ReadQR(picture) isEqualToString:[Donation qrPayload]]);
}

static void TestQRImage(void) {
    printf("-- picture\n");
    NSString* payload = [Donation qrPayload];
    NSImage* image = [Donation qrImageForPayload:payload side:208];
    CHECK(image != nil);
    CHECK(image.size.width == image.size.height && image.size.width <= 208 && image.size.width >= 160);
    CHECK(fmod(image.size.width, 1) == 0);                                          //whole points: the edges of the squares are sharp
    //the code that was drawn is read back as the text it was made from
    CHECK([ReadQR(image) isEqualToString:payload]);
    //and a smaller one too
    NSImage* small = [Donation qrImageForPayload:payload side:120];
    CHECK(small != nil && small.size.width <= 120 && [ReadQR(small) isEqualToString:payload]);
    CHECK([Donation qrImageForPayload:payload side:10] == nil);                     //too small to hold a code
    CHECK([Donation qrImageForPayload:@"" side:208] == nil);
    CHECK([Donation qrImageForPayload:nil side:208] == nil);
}

static void TestAcknowledged(void) {
    printf("-- acknowledged\n");
    Donation.acknowledged = NO;
    __block int posts = 0;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:DonationDidChangeNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification* note) { posts++; }];
    CHECK(!Donation.acknowledged);
    Donation.acknowledged = YES;
    CHECK(Donation.acknowledged && posts == 1);
    Donation.acknowledged = YES;                                                    //nothing changed: nobody is told
    CHECK(posts == 1);
    Donation.acknowledged = NO;
    CHECK(!Donation.acknowledged && posts == 2);
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
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

static void Snapshot(NSWindow* window, NSString* folder, NSString* name, BOOL dark) {
    if (folder == nil)
        return;
    window.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    NSView* content = window.contentView;
    [content layoutSubtreeIfNeeded];
    NSBitmapImageRep* cached = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
    [content.effectiveAppearance performAsCurrentDrawingAppearance:^{ [content cacheDisplayInRect:content.bounds toBitmapImageRep:cached]; }];
    //the window is never shown: a ground of the colour of a window is drawn under its content
    NSBitmapImageRep* out = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:cached.pixelsWide pixelsHigh:cached.pixelsHigh
                                                                bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                               colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    out.size = content.bounds.size;
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:out]];
    //the colour of a window, near enough: the real one cannot be read from a window that is not on the screen
    [[NSColor colorWithSRGBRed:dark ? 0.16 : 0.925 green:dark ? 0.16 : 0.925 blue:dark ? 0.17 : 0.925 alpha:1] setFill];
    NSRectFill(NSMakeRect(0, 0, content.bounds.size.width, content.bounds.size.height));
    [cached drawInRect:NSMakeRect(0, 0, content.bounds.size.width, content.bounds.size.height)];
    [NSGraphicsContext restoreGraphicsState];
    NSData* png = [out representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:[folder stringByAppendingPathComponent:[name stringByAppendingString:dark ? @"-dark.png" : @"-light.png"]] atomically:YES];
}

static void TestWindow(NSString* snapshots) {
    printf("-- window\n");
    Donation.acknowledged = NO;
    DonationWindow* donation = [[DonationWindow alloc] init];
    NSPasteboard* board = [NSPasteboard pasteboardWithUniqueName];
    donation.pasteboard = board;
    __block NSURL* opened = nil;
    donation.openURL = ^(NSURL* url) { opened = url; };

    //the form, on the Vietnam page
    [donation selectChannel:DonationChannelVietnam];
    CHECK(!donation.window.visible);                                                //building it shows nothing
    CHECK([donation.window.title isEqualToString:@"Ủng hộ VOpenKey AI"]);
    CHECK(!donation.showingThanks && donation.channelControl != nil && donation.channel == DonationChannelVietnam);
    CHECK(donation.channelControl.segmentCount == 2 && [[donation.channelControl labelForSegment:0] isEqualToString:@"Việt Nam"]);
    CHECK(donation.channelControl.selectedSegment == 0);
    CHECK(donation.qrView != nil && donation.qrView.image != nil && donation.qrView.accessibilityLabel.length > 0);
    CHECK([ReadQR(donation.qrView.image) isEqualToString:[Donation qrPayload]]);   //what is on the window is the code that works
    CHECK(donation.copyButtons.count == 2);
    CHECK(donation.payPalButton == nil && donation.confirmButton != nil && !donation.confirmButton.hidden);
    CHECK([donation.confirmButton.title isEqualToString:@"Tôi đã ủng hộ"] && [donation.confirmButton.keyEquivalent isEqualToString:@"\r"]);
    CHECK(donation.window.frame.size.width >= 400 && donation.window.frame.size.height > 400 && donation.window.frame.size.height < 800);
    int clipped = 0;
    CheckLabels(donation.window.contentView, &clipped);
    CHECK(clipped == 0);
    Snapshot(donation.window, snapshots, @"donation-vietnam", NO);
    Snapshot(donation.window, snapshots, @"donation-vietnam", YES);

    //"Sao chép" of the account number and of the note, to the pasteboard of the test
    [donation.copyButtons[0] performClick:nil];
    CHECK([[board stringForType:NSPasteboardTypeString] isEqualToString:VOK_DONATE_ACCOUNT_NO]);
    CHECK([donation.noticeLabel.stringValue isEqualToString:@"Đã sao chép: số tài khoản."]);
    [donation.copyButtons[1] performClick:nil];
    CHECK([[board stringForType:NSPasteboardTypeString] isEqualToString:VOK_DONATE_NOTE]);
    CHECK([donation.noticeLabel.stringValue containsString:@"nội dung chuyển khoản"]);

    //the other page: PayPal; the notice of the first one is gone
    [donation selectChannel:DonationChannelInternational];
    CHECK(donation.channel == DonationChannelInternational && donation.channelControl.selectedSegment == 1);
    CHECK(donation.qrView == nil && donation.copyButtons.count == 1 && donation.payPalButton != nil);
    CHECK([[donation.noticeLabel.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0);
    clipped = 0;
    CheckLabels(donation.window.contentView, &clipped);
    CHECK(clipped == 0);
    Snapshot(donation.window, snapshots, @"donation-international", NO);
    [donation.copyButtons[0] performClick:nil];
    CHECK([[board stringForType:NSPasteboardTypeString] isEqualToString:VOK_DONATE_PAYPAL_URL]);
    [donation.payPalButton performClick:nil];
    CHECK([opened.absoluteString isEqualToString:VOK_DONATE_PAYPAL_URL]);
    [donation.channelControl setSelectedSegment:0];                                  //the segmented control itself, the way a click does
    [NSApp sendAction:donation.channelControl.action to:donation.channelControl.target from:donation.channelControl];
    CHECK(donation.channel == DonationChannelVietnam && donation.qrView != nil);

    //a screen lower than the window: the window stops where the screen does and the rest scrolls, the buttons at the end included
    donation.maximumHeightForTesting = 420;
    [donation selectChannel:DonationChannelVietnam];
    NSScrollView* scroll = (NSScrollView*)donation.window.contentView;
    CHECK([scroll isKindOfClass:[NSScrollView class]]);
    CHECK([donation.window contentRectForFrameRect:donation.window.frame].size.height <= 420);
    CHECK(donation.documentView.frame.size.height > 420 && NSMinY(scroll.contentView.bounds) == 0);       //it starts at the top
    NSRect button = [donation.documentView convertRect:donation.confirmButton.bounds fromView:donation.confirmButton];
    CHECK(!NSContainsRect(scroll.contentView.documentVisibleRect, button));                                 //not in view yet...
    [donation.documentView scrollRectToVisible:button];
    CHECK(NSContainsRect(scroll.contentView.documentVisibleRect, button));                                  //...and there after scrolling
    donation.maximumHeightForTesting = 0;
    [donation selectChannel:DonationChannelVietnam];
    CHECK(NSMinY(scroll.contentView.bounds) == 0);                                                          //the page that is made again starts at the top
    CHECK([donation.window contentRectForFrameRect:donation.window.frame].size.height >= donation.documentView.fittingSize.height - 1);

    //"Tôi đã ủng hộ": thanks, remembered, the menu is told
    __block int posts = 0;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:DonationDidChangeNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification* note) { posts++; }];
    [donation.confirmButton performClick:nil];
    CHECK(donation.showingThanks && Donation.acknowledged && posts == 1);
    CHECK(donation.channelControl == nil && donation.qrView == nil && donation.copyButtons.count == 0);
    CHECK(donation.undoButton != nil && [donation.undoButton.title isEqualToString:@"Bấm nhầm? Hoàn tác"]);
    clipped = 0;
    CheckLabels(donation.window.contentView, &clipped);
    CHECK(clipped == 0);
    Snapshot(donation.window, snapshots, @"donation-thanks", NO);
    Snapshot(donation.window, snapshots, @"donation-thanks", YES);
    [donation selectChannel:DonationChannelInternational];                           //there is no page to choose any more
    CHECK(donation.showingThanks);

    //taking it back: the form is there again
    [donation.undoButton performClick:nil];
    CHECK(!donation.showingThanks && !Donation.acknowledged && posts == 2);
    CHECK(donation.channelControl != nil && donation.confirmButton != nil && donation.undoButton == nil);
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    Donation.acknowledged = NO;
}

int main(int argc, char** argv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (argc < 3) {
            printf("usage: donation_test <pricing.json> <engine folder> [folder for pictures]\n");
            return 2;
        }
        TestChecksum();
        TestPayload();
        TestPayeeMatchesPricing(@(argv[1]));
        TestQRImage();
        TestWindowsData(@(argv[2]));
        TestAcknowledged();
        TestWindow(argc >= 4 ? @(argv[3]) : nil);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[NSProcessInfo processInfo].processName];
        printf(failures ? "\n%d FAILURES\n" : "ALL OK\n", failures);
    }
    return failures ? 1 : 0;
}
