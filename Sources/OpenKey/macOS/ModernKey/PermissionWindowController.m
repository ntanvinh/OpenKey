//
//  PermissionWindowController.m
//  VOpenKey
//

#import "PermissionWindowController.h"
#import "AppPermissions.h"
#import "OpenKeyManager.h"
#import "AppInfo.h"
#import "VOKUI.h"

static const CGFloat kContentWidth = 460;

//macOS applies a permission only to a process started after it was granted in some cases; after this many
//polls with both permissions on and the hook still refusing to start, ask the user to restart the app
static const int kMaxHookFailures = 4;

//The app icon, to be dragged into the list in System Settings. Normally the app is in the Applications folder and
//macOS lists it by itself; a copy that runs from anywhere else (a build under development) is easy to lose.
@interface AppIconDragView : NSImageView <NSDraggingSource>
@end

@implementation AppIconDragView

-(void)mouseDown:(NSEvent*)event {
    NSDraggingItem* item = [[NSDraggingItem alloc] initWithPasteboardWriter:[[NSBundle mainBundle] bundleURL]];
    [item setDraggingFrame:self.bounds contents:self.image];
    [self beginDraggingSessionWithItems:@[item] event:event source:self];
}

-(NSDragOperation)draggingSession:(NSDraggingSession*)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationCopy;
}

@end

static BOOL RunsFromApplicationsFolder(void) {
    NSString* path = [[NSBundle mainBundle] bundlePath];
    return [path hasPrefix:@"/Applications/"] || [path hasPrefix:[NSHomeDirectory() stringByAppendingPathComponent:@"Applications/"]];
}

@implementation PermissionWindowController {
    void (^_onReady)(void);
    NSTimer* _timer;
    NSSwitch* _accessibilitySwitch;
    NSSwitch* _inputMonitoringSwitch;
    NSTextField* _statusLabel;
    NSImageView* _statusIcon;
    NSProgressIndicator* _spinner;
    NSButton* _settingsButton;
    NSButton* _primaryButton;
    int _hookFailures;
    BOOL _ready;
    BOOL _needsRestart;
}

-(instancetype)initWithReadyHandler:(void (^)(void))onReady {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 560)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskFullSizeContentView
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    window.movableByWindowBackground = YES;
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        _onReady = [onReady copy];
        window.delegate = self;
        [self buildContent];
    }
    return self;
}

#pragma mark - UI

-(NSView*)rowWithSymbol:(NSString*)symbol tileColor:(NSColor*)tileColor title:(NSString*)title subtitle:(NSString*)subtitle toggle:(NSSwitch*)toggle {
    NSView* tile = [[NSView alloc] init];
    tile.wantsLayer = YES;
    tile.layer.cornerRadius = 8;
    tile.layer.backgroundColor = tileColor.CGColor;
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    NSImageView* glyph = [NSImageView imageViewWithImage:VOKSymbol(symbol, 17, NSFontWeightMedium) ?: [[NSImage alloc] init]];
    glyph.contentTintColor = [NSColor whiteColor];
    glyph.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:glyph];
    [NSLayoutConstraint activateConstraints:@[
        [tile.widthAnchor constraintEqualToConstant:36],
        [tile.heightAnchor constraintEqualToConstant:36],
        [glyph.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [glyph.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
    ]];

    //the text may wrap but never push the switch: both switches sit in the same column, at the right edge of the card
    CGFloat textWidth = kContentWidth - 2 * 14 - 36 - 3 * 12 - 42;
    NSTextField* titleLabel = VOKLabel(title, 13, NSFontWeightSemibold, nil);
    titleLabel.preferredMaxLayoutWidth = textWidth;
    NSTextField* subtitleLabel = VOKLabel(subtitle, 12, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    subtitleLabel.preferredMaxLayoutWidth = textWidth;
    NSStackView* texts = [NSStackView stackViewWithViews:@[titleLabel, subtitleLabel]];
    texts.orientation = NSUserInterfaceLayoutOrientationVertical;
    texts.alignment = NSLayoutAttributeLeading;
    texts.spacing = 2;

    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    [toggle setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSView* spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* row = [NSStackView stackViewWithViews:@[tile, texts, spacer, toggle]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 12;
    row.edgeInsets = NSEdgeInsetsMake(12, 14, 12, 14);
    row.translatesAutoresizingMaskIntoConstraints = NO;
    return row;
}

//Shown only when the app is not in an Applications folder: how to find it in System Settings.
-(NSView*)findTheAppHint {
    AppIconDragView* icon = [[AppIconDragView alloc] init];
    icon.image = NSApp.applicationIconImage;
    icon.toolTip = @"Kéo biểu tượng này thả vào danh sách trong Cài đặt hệ thống";
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:36].active = YES;
    [icon.heightAnchor constraintEqualToConstant:36].active = YES;
    
    NSTextField* text = VOKLabel(@"Không thấy VOpenKey trong danh sách? Kéo biểu tượng này thả vào danh sách, hoặc bấm nút \"+\" rồi chọn app tại vị trí hiện trong Finder.",
                                 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    NSButton* reveal = [NSButton buttonWithTitle:@"Hiện trong Finder" target:self action:@selector(revealApp:)];
    reveal.controlSize = NSControlSizeSmall;
    reveal.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    
    NSStackView* texts = [NSStackView stackViewWithViews:@[text, reveal]];
    texts.orientation = NSUserInterfaceLayoutOrientationVertical;
    texts.alignment = NSLayoutAttributeLeading;
    texts.spacing = 6;
    NSStackView* hint = [NSStackView stackViewWithViews:@[icon, texts]];
    hint.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    hint.alignment = NSLayoutAttributeTop;
    hint.spacing = 12;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [hint.widthAnchor constraintEqualToConstant:kContentWidth].active = YES;
    return hint;
}

-(void)revealApp:(id)sender {
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[[NSBundle mainBundle] bundleURL]]];
}

-(void)buildContent {
    NSImageView* icon = [NSImageView imageViewWithImage:NSApp.applicationIconImage];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon.widthAnchor constraintEqualToConstant:72].active = YES;
    [icon.heightAnchor constraintEqualToConstant:72].active = YES;

    NSTextField* title = VOKLabel([NSString stringWithFormat:@"Chào mừng đến với %@", VOK_APP_NAME], 22, NSFontWeightBold, nil);
    title.alignment = NSTextAlignmentCenter;
    NSTextField* intro = VOKLabel(@"Để gõ tiếng Việt trong mọi ứng dụng, bạn chỉ cần cấp 2 quyền dưới đây: bấm công tắc, rồi bật VOpenKey trong Cài đặt hệ thống.",
                                  13, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    intro.alignment = NSTextAlignmentCenter;
    [intro.widthAnchor constraintEqualToConstant:kContentWidth - 20].active = YES;

    _accessibilitySwitch = [[NSSwitch alloc] init];
    _accessibilitySwitch.target = self;
    _accessibilitySwitch.action = @selector(accessibilityToggled:);
    _inputMonitoringSwitch = [[NSSwitch alloc] init];
    _inputMonitoringSwitch.target = self;
    _inputMonitoringSwitch.action = @selector(inputMonitoringToggled:);

    NSView* accessibilityRow = [self rowWithSymbol:@"figure.arms.open" tileColor:[NSColor systemBlueColor]
                                             title:@"Trợ năng (Accessibility)"
                                          subtitle:@"Để thay chữ bạn gõ bằng chữ có dấu."
                                            toggle:_accessibilitySwitch];
    NSView* inputMonitoringRow = [self rowWithSymbol:@"keyboard" tileColor:[NSColor systemGrayColor]
                                               title:@"Giám sát đầu vào (Input Monitoring)"
                                            subtitle:@"Để biết bạn đang bấm phím nào mà chuyển dấu."
                                              toggle:_inputMonitoringSwitch];
    NSStackView* rows = [NSStackView stackViewWithViews:@[accessibilityRow, VOKSeparator(), inputMonitoringRow]];
    rows.orientation = NSUserInterfaceLayoutOrientationVertical;
    rows.spacing = 0;
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    VOKFillWidth(rows);
    NSView* card = VOKCard(rows);
    [card.widthAnchor constraintEqualToConstant:kContentWidth].active = YES;

    _spinner = [[NSProgressIndicator alloc] init];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.displayedWhenStopped = NO;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _statusIcon = [[NSImageView alloc] init];
    _statusIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel = VOKLabel(@"", 12, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    NSStackView* status = [NSStackView stackViewWithViews:@[_spinner, _statusIcon, _statusLabel]];
    status.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    status.alignment = NSLayoutAttributeCenterY;
    status.spacing = 6;

    NSTextField* privacy = VOKLabel(@"Phím bạn gõ chỉ được xử lý ngay trên máy của bạn, không gửi đi đâu cả.",
                                    11, NSFontWeightRegular, [NSColor tertiaryLabelColor]);
    privacy.alignment = NSTextAlignmentCenter;
    [privacy.widthAnchor constraintEqualToConstant:kContentWidth].active = YES;

    _settingsButton = [NSButton buttonWithTitle:@"Mở Cài đặt hệ thống" target:self action:@selector(openSettings:)];
    _primaryButton = [NSButton buttonWithTitle:@"Xong" target:self action:@selector(primaryAction:)];
    _primaryButton.keyEquivalent = @"\r";
    _primaryButton.enabled = NO;
    NSView* spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* buttons = [NSStackView stackViewWithViews:@[_settingsButton, spacer, _primaryButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    [buttons.widthAnchor constraintEqualToConstant:kContentWidth].active = YES;

    NSMutableArray* parts = [NSMutableArray arrayWithObjects:icon, title, intro, card, nil];
    NSView* hint = nil;
    if (!RunsFromApplicationsFolder()) {
        hint = [self findTheAppHint];
        [parts addObject:hint];
    }
    [parts addObjectsFromArray:@[status, privacy, buttons]];
    NSStackView* stack = [NSStackView stackViewWithViews:parts];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 14;
    [stack setCustomSpacing:6 afterView:icon];
    [stack setCustomSpacing:20 afterView:intro];
    if (hint != nil)
        [stack setCustomSpacing:16 afterView:card];
    [stack setCustomSpacing:18 afterView:status];
    [stack setCustomSpacing:22 afterView:privacy];
    stack.edgeInsets = NSEdgeInsetsMake(40, 30, 24, 30);
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSView* content = self.window.contentView;
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
    [content layoutSubtreeIfNeeded];
    [self.window setContentSize:NSMakeSize(kContentWidth + 60, stack.fittingSize.height)];
}

#pragma mark - Behaviour

-(void)present {
    [self refresh];
    if (_timer == nil) {
        _timer = [NSTimer timerWithTimeInterval:0.7 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
        _timer.tolerance = 0.2;
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
        //coming back from System Settings is when the answer is most likely to have changed
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
                                                     name:NSApplicationDidBecomeActiveNotification object:nil];
    }
    [self.window center];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:nil]; //no focus ring on the first switch
}

-(void)windowWillClose:(NSNotification*)notification {
    [_timer invalidate];
    _timer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)accessibilityToggled:(NSSwitch*)sender {
    if ([AppPermissions accessibilityGranted])
        [AppPermissions openAccessibilitySettings];
    else
        [AppPermissions requestAccessibility];
    [self refresh]; //the switch shows what macOS says, not what was clicked
}

-(void)inputMonitoringToggled:(NSSwitch*)sender {
    if ([AppPermissions inputMonitoringGranted])
        [AppPermissions openInputMonitoringSettings];
    else
        [AppPermissions requestInputMonitoring];
    [self refresh];
}

-(void)openSettings:(id)sender {
    if (![AppPermissions accessibilityGranted])
        [AppPermissions openAccessibilitySettings];
    else
        [AppPermissions openInputMonitoringSettings];
}

-(void)primaryAction:(id)sender {
    if (_needsRestart) {
        NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration configuration];
        configuration.createsNewApplicationInstance = YES;
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:[[NSBundle mainBundle] bundleURL] configuration:configuration completionHandler:nil];
        [NSApp terminate:nil];
    } else {
        [self.window close];
    }
}

-(void)showStatus:(NSString*)text symbol:(NSString*)symbol color:(NSColor*)color waiting:(BOOL)waiting {
    _statusLabel.stringValue = text;
    _statusLabel.textColor = color;
    _statusIcon.image = symbol != nil ? VOKSymbol(symbol, 13, NSFontWeightSemibold) : nil;
    _statusIcon.contentTintColor = color;
    _statusIcon.hidden = symbol == nil;
    if (waiting)
        [_spinner startAnimation:nil];
    else
        [_spinner stopAnimation:nil];
}

-(void)refresh {
    BOOL accessibility = [AppPermissions accessibilityGranted];
    BOOL inputMonitoring = [AppPermissions inputMonitoringGranted];
    _accessibilitySwitch.state = accessibility ? NSControlStateValueOn : NSControlStateValueOff;
    _inputMonitoringSwitch.state = inputMonitoring ? NSControlStateValueOn : NSControlStateValueOff;
    if (_ready)
        return;

    if (!accessibility || !inputMonitoring) {
        NSString* missing = !accessibility && !inputMonitoring ? @"Còn thiếu 2 quyền" : (!accessibility ? @"Còn thiếu quyền Trợ năng" : @"Còn thiếu quyền Giám sát đầu vào");
        [self showStatus:[missing stringByAppendingString:@". Đang chờ bạn bật công tắc…"] symbol:nil color:[NSColor secondaryLabelColor] waiting:YES];
        _primaryButton.enabled = NO;
        return;
    }

    if ([OpenKeyManager initEventTap]) {
        _ready = YES;
        [self showStatus:[NSString stringWithFormat:@"Đã sẵn sàng! %@ đang chạy trên thanh menu.", VOK_APP_NAME]
                  symbol:@"checkmark.circle.fill" color:[NSColor systemGreenColor] waiting:NO];
        _primaryButton.title = @"Xong";
        _primaryButton.enabled = YES;
        if (_onReady != nil)
            _onReady();
        //nothing more to do for the user, so do not make them close the window
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.window.isVisible)
                [self.window close];
        });
    } else if (++_hookFailures >= kMaxHookFailures) {
        _needsRestart = YES;
        [self showStatus:@"Quyền đã được cấp, nhưng cần khởi động lại để có hiệu lực."
                  symbol:@"arrow.clockwise.circle.fill" color:[NSColor systemOrangeColor] waiting:NO];
        _primaryButton.title = @"Khởi động lại";
        _primaryButton.enabled = YES;
    } else {
        [self showStatus:@"Đang khởi động bộ gõ…" symbol:nil color:[NSColor secondaryLabelColor] waiting:YES];
    }
}

@end
