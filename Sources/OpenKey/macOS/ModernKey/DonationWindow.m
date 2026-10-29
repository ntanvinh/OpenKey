//
//  DonationWindow.m
//  VOpenKey
//

#import "DonationWindow.h"
#import "AppInfo.h"
#import "Donation.h"
#import "VOKUI.h"

static const CGFloat kWidth = 420;
static const CGFloat kMargin = 28;          //between the window edge and what is in it
static const CGFloat kRowInset = 16;        //between the card edge and the text of a row
static const CGFloat kRowPadding = 10;      //above and below the text of a row
static const CGFloat kRowMinHeight = 44;
static const CGFloat kQRSide = 208;

//Esc closes it, like the About window
@interface DonationNSWindow : NSWindow
@end

@implementation DonationNSWindow
-(void)cancelOperation:(id)sender {
    [self performClose:sender];
}
@end

//The view inside the scroll view: its top is where the scrolling starts, so that a window shorter than its content shows the heading first
@interface DonationDocumentView : NSView
@end

@implementation DonationDocumentView
-(BOOL)isFlipped { return YES; }
@end

//Text that wraps at `width`, with the height that text needs there. Leaving the height to Auto Layout let a label of two lines keep
//the height of one (see SettingsWindowController).
static NSTextField* FixedLabelWithFont(NSString* text, NSFont* font, NSColor* color, CGFloat width, NSTextAlignment alignment) {
    NSTextField* label = VOKLabel(text, font.pointSize, NSFontWeightRegular, color);
    label.font = font;
    label.alignment = alignment;
    label.preferredMaxLayoutWidth = width;
    NSSize fit = [label.cell cellSizeForBounds:NSMakeRect(0, 0, width, CGFLOAT_MAX)];
    [label.heightAnchor constraintEqualToConstant:ceil(fit.height)].active = YES;
    [label.widthAnchor constraintEqualToConstant:width].active = YES;
    return label;
}

static NSTextField* FixedLabel(NSString* text, CGFloat size, NSFontWeight weight, NSColor* color, CGFloat width, NSTextAlignment alignment) {
    return FixedLabelWithFont(text, [NSFont systemFontOfSize:size weight:weight], color, width, alignment);
}

@interface DonationWindow () <NSWindowDelegate>
@end

@implementation DonationWindow {
    NSWindow* _window;
    DonationChannel _channel;
    BOOL _thanks;
    NSSegmentedControl* _channelControl;
    NSStackView* _pageHolder;
    NSImageView* _qrView;
    NSTextField* _noticeLabel;
    NSButton* _confirmButton;
    NSButton* _undoButton;
    NSButton* _payPalButton;
    NSMutableArray<NSButton*>* _copyButtons;
    NSMutableArray<NSString*>* _copyValues;     //what each "Sao chép" copies, and under what name it says so
    NSMutableArray<NSString*>* _copyNames;
    NSView* _document;                          //what the window shows, inside its scroll view
}

+(DonationWindow*)shared {
    static DonationWindow* shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[DonationWindow alloc] init]; });
    return shared;
}

+(void)show {
    [[self shared] showWindow];
}

-(instancetype)init {
    self = [super init];
    if (self) {
        _pasteboard = [NSPasteboard generalPasteboard];
        _copyButtons = [NSMutableArray array];
        _copyValues = [NSMutableArray array];
        _copyNames = [NSMutableArray array];
    }
    return self;
}

-(NSWindow*)window {
    if (_window == nil) {
        _window = [[DonationNSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWidth, 600)
                                                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                        backing:NSBackingStoreBuffered defer:YES];
        _window.title = [NSString stringWithFormat:@"Ủng hộ %@", VOK_APP_NAME];
        _window.releasedWhenClosed = NO;
        _window.delegate = self;
        [_window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
        [_window standardWindowButton:NSWindowZoomButton].hidden = YES;
        [self rebuild];
        [_window center];
    }
    return _window;
}

-(void)showWindow {
    NSWindow* window = self.window;
    if (!window.visible) {
        //a window that was closed is opened again as the situation is now: the thanks when they already donated, the form when not
        _channel = [self defaultChannel];
        [self rebuild];
    }
    //a menu bar application is not active when its menu item is clicked, and the window would open behind other windows
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
}

//Vietnam for a Mac whose first language is Vietnamese (the donate screen of VMonitor AI chooses the same way), abroad otherwise
-(DonationChannel)defaultChannel {
    NSString* language = [NSLocale preferredLanguages].firstObject.lowercaseString;
    return [language hasPrefix:@"vi"] ? DonationChannelVietnam : DonationChannelInternational;
}

#pragma mark Reading

-(DonationChannel)channel { return _channel; }
-(NSView*)documentView { [self window]; return _document; }
-(BOOL)showingThanks { return _thanks; }
-(NSSegmentedControl*)channelControl { [self window]; return _channelControl; }
-(NSImageView*)qrView { [self window]; return _qrView; }
-(NSTextField*)noticeLabel { [self window]; return _noticeLabel; }
-(NSButton*)confirmButton { [self window]; return _confirmButton; }
-(NSButton*)undoButton { [self window]; return _undoButton; }
-(NSButton*)payPalButton { [self window]; return _payPalButton; }
-(NSArray<NSButton*>*)copyButtons { [self window]; return [_copyButtons copy]; }

#pragma mark Building

-(NSButton*)buttonWithTitle:(NSString*)title action:(SEL)action {
    NSButton* button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

//Name over value on the left, "Sao chép" on the right when the value is something to copy
-(NSView*)rowWithName:(NSString*)name value:(NSString*)value font:(NSFont*)font copy:(BOOL)copy cardWidth:(CGFloat)cardWidth {
    NSView* row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    NSButton* button = nil;
    CGFloat buttonSpace = 0;
    if (copy) {
        button = [self buttonWithTitle:@"Sao chép" action:@selector(copyPressed:)];
        button.controlSize = NSControlSizeSmall;
        button.tag = (NSInteger)_copyValues.count;
        [button setAccessibilityLabel:[NSString stringWithFormat:@"Sao chép %@", name.lowercaseString]];
        [_copyButtons addObject:button];
        [_copyValues addObject:value];
        [_copyNames addObject:name];
        buttonSpace = ceil(button.fittingSize.width) + 12;
    }
    CGFloat textWidth = cardWidth - 2 * kRowInset - buttonSpace;
    NSTextField* nameLabel = FixedLabel(name, 11, NSFontWeightRegular, [NSColor secondaryLabelColor], textWidth, NSTextAlignmentLeft);
    NSTextField* valueLabel = FixedLabelWithFont(value, font, [NSColor labelColor], textWidth, NSTextAlignmentLeft);
    valueLabel.selectable = YES;
    [row addSubview:nameLabel];
    [row addSubview:valueLabel];
    [NSLayoutConstraint activateConstraints:@[
        [nameLabel.topAnchor constraintEqualToAnchor:row.topAnchor constant:kRowPadding],
        [nameLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:kRowInset],
        [valueLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:2],
        [valueLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [row.bottomAnchor constraintEqualToAnchor:valueLabel.bottomAnchor constant:kRowPadding],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:kRowMinHeight],
    ]];
    if (button != nil) {
        [row addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-kRowInset],
            [button.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];
    }
    return row;
}

-(NSView*)cardWithRows:(NSArray<NSView*>*)rows width:(CGFloat)width {
    NSMutableArray* parts = [NSMutableArray array];
    for (NSUInteger i = 0; i < rows.count; i++) {
        if (i > 0)
            [parts addObject:VOKInsetSeparator(kRowInset)];
        [parts addObject:rows[i]];
    }
    NSStackView* list = [NSStackView stackViewWithViews:parts];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.spacing = 0;
    VOKFillWidth(list);
    NSView* card = VOKCard(list);
    [card.widthAnchor constraintEqualToConstant:width].active = YES;
    return card;
}

-(void)addPageViews:(NSArray<NSView*>*)views {
    for (NSView* view in views)
        [_pageHolder addArrangedSubview:view];
}

//The page under the two tabs: the account of a Vietnamese bank with its QR code, or PayPal
-(void)fillPage {
    for (NSView* view in [_pageHolder.arrangedSubviews copy]) {
        [_pageHolder removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    [_copyButtons removeAllObjects];
    [_copyValues removeAllObjects];
    [_copyNames removeAllObjects];
    _qrView = nil;
    _payPalButton = nil;
    CGFloat width = kWidth - 2 * kMargin;

    if (_channel == DonationChannelVietnam) {
        NSString* payload = [Donation qrPayload];
        NSImage* qr = payload != nil ? [Donation qrImageForPayload:payload side:kQRSide] : nil;
        NSView* picture;
        if (qr != nil) {
            _qrView = [NSImageView imageViewWithImage:qr];
            _qrView.imageScaling = NSImageScaleProportionallyUpOrDown;
            _qrView.wantsLayer = YES;
            _qrView.layer.cornerRadius = 8;
            _qrView.layer.masksToBounds = YES;
            _qrView.translatesAutoresizingMaskIntoConstraints = NO;
            [_qrView.widthAnchor constraintEqualToConstant:qr.size.width].active = YES;
            [_qrView.heightAnchor constraintEqualToConstant:qr.size.height].active = YES;
            [_qrView setAccessibilityLabel:[NSString stringWithFormat:@"Mã VietQR chuyển khoản ủng hộ %@: %@ %@, người nhận %@",
                                            VOK_APP_NAME, VOK_DONATE_BANK_NAME, VOK_DONATE_ACCOUNT_NO, VOK_DONATE_ACCOUNT_NAME]];
            picture = _qrView;
        } else {
            picture = FixedLabel(@"Không tạo được mã QR. Bạn vẫn có thể chuyển khoản theo thông tin bên dưới.", 12, NSFontWeightRegular,
                                 [NSColor systemRedColor], width, NSTextAlignmentCenter);
        }
        NSTextField* caption = FixedLabel(@"Quét bằng app ngân hàng và nhập số tiền bạn muốn ủng hộ.", 11, NSFontWeightRegular,
                                          [NSColor secondaryLabelColor], width, NSTextAlignmentCenter);
        NSView* card = [self cardWithRows:@[
            [self rowWithName:@"Ngân hàng" value:VOK_DONATE_BANK_NAME font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] copy:NO cardWidth:width],
            [self rowWithName:@"Số tài khoản" value:VOK_DONATE_ACCOUNT_NO font:[NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightMedium] copy:YES cardWidth:width],
            [self rowWithName:@"Người nhận" value:VOK_DONATE_ACCOUNT_NAME font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] copy:NO cardWidth:width],
            [self rowWithName:@"Nội dung chuyển khoản" value:VOK_DONATE_NOTE font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] copy:YES cardWidth:width],
        ] width:width];
        [self addPageViews:@[picture, caption, card]];
        [_pageHolder setCustomSpacing:6 afterView:picture];
        [_pageHolder setCustomSpacing:14 afterView:caption];
    } else {
        NSView* card = [self cardWithRows:@[
            [self rowWithName:@"Người nhận (PayPal)" value:VOK_DONATE_PAYPAL_NAME font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] copy:NO cardWidth:width],
            [self rowWithName:@"Liên kết thanh toán" value:VOK_DONATE_PAYPAL_URL font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] copy:YES cardWidth:width],
        ] width:width];
        _payPalButton = [self buttonWithTitle:@"Mở PayPal" action:@selector(payPalPressed:)];
        NSTextField* hint = FixedLabel(@"Chọn số tiền tùy ý trên PayPal. Liên kết mở trong trình duyệt và cần có internet.", 11, NSFontWeightRegular,
                                       [NSColor secondaryLabelColor], width, NSTextAlignmentCenter);
        [self addPageViews:@[card, _payPalButton, hint]];
        [_pageHolder setCustomSpacing:14 afterView:card];
        [_pageHolder setCustomSpacing:6 afterView:_payPalButton];
    }
}

-(NSView*)formContent {
    CGFloat width = kWidth - 2 * kMargin;
    NSImageView* heart = [NSImageView imageViewWithImage:VOKSymbol(@"heart.fill", 30, NSFontWeightRegular)];
    heart.contentTintColor = [NSColor systemPinkColor];
    [heart setAccessibilityElement:NO];
    NSTextField* heading = FixedLabel(@"Một chút ủng hộ, thêm nhiều động lực.", 18, NSFontWeightSemibold, nil, width, NSTextAlignmentCenter);
    NSTextField* intro = FixedLabel([NSString stringWithFormat:@"Nếu %@ giúp bạn gõ và viết thuận tiện hơn, bạn có thể góp sức để app tiếp tục phát triển.", VOK_APP_NAME],
                                    12, NSFontWeightRegular, [NSColor secondaryLabelColor], width, NSTextAlignmentCenter);

    _channelControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Việt Nam", @"Quốc tế"]
                                                        trackingMode:NSSegmentSwitchTrackingSelectOne
                                                              target:self action:@selector(channelChanged:)];
    _channelControl.segmentStyle = NSSegmentStyleRounded;
    _channelControl.selectedSegment = _channel == DonationChannelVietnam ? 0 : 1;
    _channelControl.segmentDistribution = NSSegmentDistributionFillEqually;
    _channelControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_channelControl.widthAnchor constraintEqualToConstant:width].active = YES;
    [_channelControl setAccessibilityLabel:@"Cách ủng hộ"];

    _pageHolder = [[NSStackView alloc] init];
    _pageHolder.orientation = NSUserInterfaceLayoutOrientationVertical;
    _pageHolder.alignment = NSLayoutAttributeCenterX;
    _pageHolder.spacing = 10;
    _pageHolder.translatesAutoresizingMaskIntoConstraints = NO;
    [self fillPage];

    //a line is kept free for "Đã sao chép", so that the window does not jump when it appears
    _noticeLabel = FixedLabel(@" ", 11, NSFontWeightRegular, [NSColor secondaryLabelColor], width, NSTextAlignmentCenter);
    NSTextField* trust = FixedLabel(@"Sau khi ủng hộ, hãy xác nhận để ẩn mục Ủng hộ khỏi menu. App tin vào xác nhận của bạn và không đối soát giao dịch.",
                                    11, NSFontWeightRegular, [NSColor secondaryLabelColor], width, NSTextAlignmentLeft);

    NSButton* close = [self buttonWithTitle:@"Đóng" action:@selector(closePressed:)];
    _confirmButton = [self buttonWithTitle:@"Tôi đã ủng hộ" action:@selector(confirmPressed:)];
    _confirmButton.keyEquivalent = @"\r";
    NSView* spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* buttons = [NSStackView stackViewWithViews:@[spacer, close, _confirmButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 8;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    [buttons.widthAnchor constraintEqualToConstant:width].active = YES;

    NSView* line = VOKSeparator();
    NSStackView* stack = [NSStackView stackViewWithViews:@[heart, heading, intro, _channelControl, _pageHolder, _noticeLabel, line, trust, buttons]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 12;
    [stack setCustomSpacing:6 afterView:heart];
    [stack setCustomSpacing:6 afterView:heading];
    [stack setCustomSpacing:18 afterView:intro];
    [stack setCustomSpacing:2 afterView:_pageHolder];
    [stack setCustomSpacing:6 afterView:_noticeLabel];
    [line.widthAnchor constraintEqualToConstant:width].active = YES;
    return stack;
}

-(NSView*)thanksContent {
    CGFloat width = kWidth - 2 * kMargin;
    NSImageView* heart = [NSImageView imageViewWithImage:VOKSymbol(@"heart.fill", 48, NSFontWeightRegular)];
    heart.contentTintColor = [NSColor systemPinkColor];
    [heart setAccessibilityElement:NO];
    NSTextField* heading = FixedLabel(@"Cảm ơn bạn đã ủng hộ!", 22, NSFontWeightSemibold, nil, width, NSTextAlignmentCenter);
    NSTextField* body = FixedLabel([NSString stringWithFormat:@"Sự ủng hộ của bạn giúp %@ tiếp tục phát triển. Mục Ủng hộ đã được ẩn khỏi menu trên thanh trạng thái; bạn vẫn mở lại được ở Cài đặt > Hệ thống.", VOK_APP_NAME],
                                   12, NSFontWeightRegular, [NSColor secondaryLabelColor], width, NSTextAlignmentCenter);
    _undoButton = [self buttonWithTitle:@"Bấm nhầm? Hoàn tác" action:@selector(undoPressed:)];
    NSButton* done = [self buttonWithTitle:@"Xong" action:@selector(closePressed:)];
    done.keyEquivalent = @"\r";
    NSView* spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* buttons = [NSStackView stackViewWithViews:@[_undoButton, spacer, done]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 8;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    [buttons.widthAnchor constraintEqualToConstant:width].active = YES;
    NSStackView* stack = [NSStackView stackViewWithViews:@[heart, heading, body, buttons]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 12;
    [stack setCustomSpacing:10 afterView:heart];
    [stack setCustomSpacing:22 afterView:body];
    return stack;
}

//Builds what the window shows for the situation now, and gives the window the height of it (its top stays where it is)
-(void)rebuild {
    _thanks = Donation.acknowledged;
    _channelControl = nil;
    _pageHolder = nil;
    _noticeLabel = nil;
    _confirmButton = nil;
    _undoButton = nil;
    _qrView = nil;
    _payPalButton = nil;
    [_copyButtons removeAllObjects];
    NSView* stack = _thanks ? [self thanksContent] : [self formContent];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    NSView* content = [[DonationDocumentView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:kMargin - 6],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
        [stack.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
    ]];
    //The window is as high as its content, unless the screen is lower than that (a small MacBook): then the content scrolls, and
    //nothing is cut off. The width never changes.
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, 400)];
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.documentView = content;
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [content.widthAnchor constraintEqualToConstant:kWidth],
    ]];
    _document = content;
    _window.contentView = scroll;
    [self resizeToFit];
}

-(void)resizeToFit {
    [_document layoutSubtreeIfNeeded];
    NSSize size = _document.fittingSize;
    NSScreen* screen = _window.screen ?: [NSScreen mainScreen];
    //what the screen leaves for the window, less a margin; the title bar is part of the window but not of its content
    CGFloat room = (self.maximumHeightForTesting > 0 ? self.maximumHeightForTesting : screen.visibleFrame.size.height - 40) -
                   (_window.frame.size.height - _window.contentLayoutRect.size.height);
    CGFloat height = MAX(200, MIN(size.height, room));
    NSRect frame = _window.frame;
    CGFloat top = NSMaxY(frame);
    NSRect target = [_window frameRectForContentRect:NSMakeRect(0, 0, kWidth, height)];
    frame.size = target.size;
    frame.origin.y = top - frame.size.height;
    [_window setFrame:frame display:_window.visible];
    [_document scrollPoint:NSZeroPoint];
}

#pragma mark Actions

-(void)selectChannel:(DonationChannel)channel {
    [self window];
    if (_thanks)
        return;
    _channel = channel;
    _channelControl.selectedSegment = channel == DonationChannelVietnam ? 0 : 1;
    _noticeLabel.stringValue = @" ";
    [self fillPage];
    [self resizeToFit];
}

-(void)channelChanged:(NSSegmentedControl*)sender {
    [self selectChannel:sender.selectedSegment == 0 ? DonationChannelVietnam : DonationChannelInternational];
}

-(void)say:(NSString*)message error:(BOOL)error {
    _noticeLabel.stringValue = message;
    _noticeLabel.textColor = error ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
    //VoiceOver does not read a label that changes by itself
    NSAccessibilityPostNotificationWithUserInfo(_noticeLabel, NSAccessibilityAnnouncementRequestedNotification,
                                                @{NSAccessibilityAnnouncementKey: message});
}

-(void)copyPressed:(NSButton*)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)_copyValues.count)
        return;
    [_pasteboard clearContents];
    if ([_pasteboard setString:_copyValues[index] forType:NSPasteboardTypeString])
        [self say:[NSString stringWithFormat:@"Đã sao chép: %@.", _copyNames[index].lowercaseString] error:NO];
    else
        [self say:@"Không sao chép được. Hãy chọn và sao chép thông tin ở trên." error:YES];
}

-(void)payPalPressed:(id)sender { [self openPayPal]; }

-(void)openPayPal {
    NSURL* url = [NSURL URLWithString:VOK_DONATE_PAYPAL_URL];
    if (self.openURL != nil) {
        self.openURL(url);
        return;
    }
    if (![[NSWorkspace sharedWorkspace] openURL:url])
        [self say:@"Không mở được PayPal. Hãy thử lại hoặc sao chép liên kết thanh toán." error:YES];
}

-(void)confirmPressed:(id)sender { [self confirmDonation]; }
-(void)undoPressed:(id)sender { [self undoDonation]; }
-(void)closePressed:(id)sender { [_window performClose:nil]; }

-(void)confirmDonation {
    [self window];
    Donation.acknowledged = YES;
    [self rebuild];
    [_window makeFirstResponder:nil];
}

-(void)undoDonation {
    [self window];
    Donation.acknowledged = NO;
    _channel = [self defaultChannel];
    [self rebuild];
}

@end
