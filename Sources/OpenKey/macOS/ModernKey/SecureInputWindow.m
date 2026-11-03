//
//  SecureInputWindow.m
//  VOpenKey
//
//  See SecureInputWindow.h
//

#import "SecureInputWindow.h"
#import "AppInfo.h"
#import "SecureInputMonitor.h"
#import "VOKUI.h"

static const CGFloat kWidth = 440;
static const CGFloat kMargin = 28;          //between the window edge and what is in it
static const CGFloat kRowInset = 16;        //between the card edge and the text of a row
static const CGFloat kRowPadding = 9;       //above and below the text of a row
static const CGFloat kNameWidth = 92;       //the column of names at the left of a row
static const CGFloat kColumnGap = 8;

//Esc closes it, like the About and Donate windows
@interface SecureInputNSWindow : NSWindow
@end

@implementation SecureInputNSWindow
-(void)cancelOperation:(id)sender {
    [self performClose:sender];
}
@end

//The view inside the scroll view: its top is where the scrolling starts, so that a window shorter than its content shows the heading first
@interface SecureInputDocumentView : NSView
@end

@implementation SecureInputDocumentView
-(BOOL)isFlipped { return YES; }
@end

#pragma mark - Text

//Text that wraps at `width`, with the height that text needs there. Leaving the height to Auto Layout let a label of two lines keep
//the height of one (see SettingsWindowController and DonationWindow). `breakAnywhere` is for paths and ids, which have no spaces.
static NSTextField* FixedLabel(NSAttributedString* text, CGFloat width, BOOL breakAnywhere) {
    NSTextField* label = [NSTextField wrappingLabelWithString:@""];
    label.attributedStringValue = text;
    label.selectable = NO;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    if (breakAnywhere)
        label.lineBreakMode = NSLineBreakByCharWrapping;
    label.preferredMaxLayoutWidth = width;
    NSSize fit = [label.cell cellSizeForBounds:NSMakeRect(0, 0, width, CGFLOAT_MAX)];
    [label.heightAnchor constraintEqualToConstant:ceil(fit.height)].active = YES;
    [label.widthAnchor constraintEqualToConstant:width].active = YES;
    return label;
}

static NSTextField* PlainLabel(NSString* text, NSFont* font, NSColor* color, CGFloat width, NSTextAlignment alignment, BOOL breakAnywhere) {
    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = alignment;
    paragraph.lineBreakMode = breakAnywhere ? NSLineBreakByCharWrapping : NSLineBreakByWordWrapping;
    NSAttributedString* attributed = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color != nil ? color : [NSColor labelColor],
        NSParagraphStyleAttributeName: paragraph}];
    return FixedLabel(attributed, width, breakAnywhere);
}

//"•  text", the second line under the first
static NSTextField* BulletLabel(NSString* text, CGFloat width) {
    const CGFloat indent = 12;
    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.firstLineHeadIndent = 0;
    paragraph.headIndent = indent;
    paragraph.tabStops = @[[[NSTextTab alloc] initWithType:NSLeftTabStopType location:indent]];
    paragraph.defaultTabInterval = indent;
    paragraph.lineSpacing = 1;
    NSAttributedString* attributed = [[NSAttributedString alloc] initWithString:[@"•\t" stringByAppendingString:text] attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSParagraphStyleAttributeName: paragraph}];
    return FixedLabel(attributed, width, NO);
}

//The words of the window are Vietnamese whatever the language of the Mac, so are the date and the time in it
static NSLocale* WindowLocale(void) {
    return [NSLocale localeWithLocaleIdentifier:@"vi_VN"];
}

//"Hôm nay lúc 14:05 (2 giờ trước)": when the program started
static NSString* StartText(NSDate* date) {
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    formatter.locale = WindowLocale();
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    formatter.doesRelativeDateFormatting = YES;
    NSRelativeDateTimeFormatter* relative = [[NSRelativeDateTimeFormatter alloc] init];
    relative.locale = WindowLocale();
    relative.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleFull;
    return [NSString stringWithFormat:@"%@ (%@)", [formatter stringFromDate:date],
            [relative localizedStringForDate:date relativeToDate:[NSDate date]]];
}

static NSString* TimeText(NSDate* date) {
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    formatter.locale = WindowLocale();
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    return [formatter stringFromDate:date];
}

static NSString* RoleText(SecureInputHolder* holder) {
    if (holder.pid > 0 && !holder.processExists)
        return @"Tiến trình đã thoát";
    switch (holder.role) {
        case SecureInputHolderRoleFrontApp:      return @"Ứng dụng bạn đang gõ";
        case SecureInputHolderRoleBackgroundApp: return @"Ứng dụng đang chạy nền, bạn không gõ trong đó";
        case SecureInputHolderRoleHelper:        return @"Ứng dụng trên thanh menu hoặc tiến trình nền";
        case SecureInputHolderRoleSystem:        return @"Tiến trình của macOS (đăng nhập, hộp thoại mật khẩu)";
        case SecureInputHolderRoleLockedSession: return @"Màn hình khóa hoặc phiên của người dùng khác";
        case SecureInputHolderRoleUnknown:       break;
    }
    return @"Không xác định";
}

//What to try, for the kind of holder
static NSArray<NSString*>* TipsFor(SecureInputHolder* holder) {
    if (holder.pid > 0 && !holder.processExists) {
        return @[@"macOS vẫn ghi nhận tiến trình này giữ Secure Input dù nó không còn chạy.",
                 @"Đăng xuất rồi đăng nhập lại (hoặc khởi động lại Mac) thường giải phóng nó."];
    }
    switch (holder.role) {
        case SecureInputHolderRoleFrontApp:
            return @[@"Nếu con trỏ đang ở ô nhập mật khẩu, Secure Input tắt khi bạn rời khỏi ô đó. Đây là cách bảo vệ bình thường của macOS.",
                     @"Nếu không có ô mật khẩu nào, hãy tìm tùy chọn bảo vệ bàn phím của ứng dụng, ví dụ Terminal hoặc iTerm2 > Secure Keyboard Entry, rồi tắt nó."];
        case SecureInputHolderRoleBackgroundApp:
            return @[@"Ứng dụng này chạy nền nhưng vẫn giữ Secure Input, thường vì quên nhả sau khi bạn nhập mật khẩu hoặc vì đang bật Secure Keyboard Entry.",
                     @"Mở ứng dụng, tắt tùy chọn bảo vệ bàn phím hoặc thoát hẳn (⌘Q). Biểu tượng trên thanh menu hết vàng ngay khi Secure Input tắt.",
                     @"Bấm “Hiện trong Finder” để biết đúng ứng dụng nào, hoặc mở Activity Monitor và tìm theo PID."];
        case SecureInputHolderRoleHelper:
            return @[@"Một ứng dụng trên thanh menu hoặc chạy nền (trình quản lý mật khẩu, điều khiển từ xa, VPN…) đang giữ Secure Input.",
                     @"Mở menu của nó trên thanh menu, đóng hộp thoại đăng nhập hoặc nhập mật khẩu đang mở, hoặc thoát nó. Tiến trình cha ở trên cho biết nó thuộc ứng dụng nào."];
        case SecureInputHolderRoleSystem:
            return @[@"macOS đang hiện hộp thoại mật khẩu hoặc màn hình đăng nhập. Secure Input tắt khi bạn nhập xong hoặc đóng hộp thoại đó.",
                     @"Nếu không thấy hộp thoại nào mà Secure Input vẫn bật, hãy đăng xuất rồi đăng nhập lại."];
        case SecureInputHolderRoleLockedSession:
            return @[@"Màn hình đang khóa hoặc một người dùng khác đang dùng Mac. Secure Input tắt khi bạn mở khóa."];
        case SecureInputHolderRoleUnknown:
            break;
    }
    return @[@"macOS không cho biết ứng dụng nào đang giữ Secure Input.",
             @"Thử thoát lần lượt những ứng dụng hay bật nó: Terminal hoặc iTerm2 (Secure Keyboard Entry), trình quản lý mật khẩu, ứng dụng điều khiển từ xa, VPN. Biểu tượng trên thanh menu hết vàng ngay khi bạn thoát đúng ứng dụng.",
             @"Nếu đã thoát hết mà Secure Input vẫn bật, hãy đăng xuất rồi đăng nhập lại."];
}

//What the card about the holder lists: name, value and how the value is shown
@interface SecureInputRow : NSObject
@property (nonatomic, copy) NSString* name;
@property (nonatomic, copy) NSString* value;
@property (nonatomic) BOOL monospaced;      //ids and paths
@property (nonatomic) BOOL reveal;          //the "Hiện trong Finder" button goes under it
@end

@implementation SecureInputRow
+(instancetype)rowWithName:(NSString*)name value:(NSString*)value monospaced:(BOOL)monospaced reveal:(BOOL)reveal {
    SecureInputRow* row = [[SecureInputRow alloc] init];
    row.name = name;
    row.value = value;
    row.monospaced = monospaced;
    row.reveal = reveal;
    return row;
}
@end

static NSArray<SecureInputRow*>* RowsFor(SecureInputHolder* holder) {
    NSMutableArray* rows = [NSMutableArray array];
    NSString* name = holder.name.length > 0 ? holder.name : (holder.pid > 0 ? @"Không đọc được tên" : @"macOS không cho biết");
    [rows addObject:[SecureInputRow rowWithName:@"Tên" value:name monospaced:NO reveal:NO]];
    [rows addObject:[SecureInputRow rowWithName:@"Vai trò" value:RoleText(holder) monospaced:NO reveal:NO]];
    if (holder.pid > 0)
        [rows addObject:[SecureInputRow rowWithName:@"PID" value:[NSString stringWithFormat:@"%d", holder.pid] monospaced:YES reveal:NO]];
    if (holder.bundleIdentifier.length > 0)
        [rows addObject:[SecureInputRow rowWithName:@"Bundle ID" value:holder.bundleIdentifier monospaced:YES reveal:NO]];
    if (holder.version.length > 0)
        [rows addObject:[SecureInputRow rowWithName:@"Phiên bản" value:holder.version monospaced:NO reveal:NO]];
    if (holder.path.length > 0)
        [rows addObject:[SecureInputRow rowWithName:@"Đường dẫn" value:holder.path monospaced:YES reveal:YES]];
    if (holder.startDate != nil)
        [rows addObject:[SecureInputRow rowWithName:@"Chạy từ" value:StartText(holder.startDate) monospaced:NO reveal:NO]];
    if (holder.parentPID > 0) {
        NSString* parent = holder.parentName.length > 0 ? [NSString stringWithFormat:@"%@ (PID %d)", holder.parentName, holder.parentPID]
                                                         : [NSString stringWithFormat:@"PID %d", holder.parentPID];
        [rows addObject:[SecureInputRow rowWithName:@"Mở bởi" value:parent monospaced:NO reveal:NO]];
    }
    return rows;
}

#pragma mark - The window

@interface SecureInputWindow () <NSWindowDelegate>
@end

@implementation SecureInputWindow {
    NSWindow* _window;
    NSView* _document;
    SecureInputHolder* _holder;
    SecureInputHolder* _lastHolder;
    NSDate* _releasedAt;
    SecureInputEffect _effect;

    NSTextField* _headingLabel;
    NSTextField* _explanationLabel;
    NSTextField* _noticeLabel;
    NSButton* _revealButton;
    NSButton* _copyButton;
    NSButton* _activityMonitorButton;
    NSButton* _closeButton;
    NSMutableArray<NSString*>* _rowTexts;
    NSMutableArray<NSString*>* _tipTexts;
}

+(SecureInputWindow*)shared {
    static SecureInputWindow* shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[SecureInputWindow alloc] init]; });
    return shared;
}

+(void)show {
    [[self shared] showWindow];
}

-(instancetype)init {
    self = [super init];
    if (self) {
        _pasteboard = [NSPasteboard generalPasteboard];
        _rowTexts = [NSMutableArray array];
        _tipTexts = [NSMutableArray array];
        //while the window is open it keeps up with the monitor: another holder, or secure input released
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(monitorChanged:)
                                                     name:SecureInputMonitorDidChangeNotification object:nil];
    }
    return self;
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(NSWindow*)window {
    if (_window == nil) {
        _window = [[SecureInputNSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWidth, 600)
                                                         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                           backing:NSBackingStoreBuffered defer:YES];
        _window.title = @"Secure Input";
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
    [self reloadFromMonitor];
    //a menu bar application is not active when its menu item is clicked, and the window would open behind other windows
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
}

-(void)monitorChanged:(NSNotification*)note {
    if (_window != nil && _window.visible)
        [self reloadFromMonitor];
}

-(void)reloadFromMonitor {
    SecureInputEffect effect = SecureInputEffectNone;
    if ([SecureInputMonitor isFallbackActive])
        effect = SecureInputEffectFallback;
    else if ([SecureInputMonitor isOpenKeyBlind] && [[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"] == 1)
        effect = SecureInputEffectBlocked;
    [self displayHolder:[SecureInputMonitor currentHolder] effect:effect lastHolder:[SecureInputMonitor lastHolder]
             releasedAt:[SecureInputMonitor lastReleaseDate]];
}

-(void)displayHolder:(SecureInputHolder*)holder effect:(SecureInputEffect)effect lastHolder:(SecureInputHolder*)lastHolder
          releasedAt:(NSDate*)releasedAt {
    [self window];
    _holder = holder;
    _effect = effect;
    _lastHolder = lastHolder;
    _releasedAt = releasedAt;
    [self rebuild];
}

#pragma mark Reading

-(NSView*)documentView { [self window]; return _document; }
-(NSTextField*)headingLabel { [self window]; return _headingLabel; }
-(NSTextField*)explanationLabel { [self window]; return _explanationLabel; }
-(NSTextField*)noticeLabel { [self window]; return _noticeLabel; }
-(NSButton*)revealButton { [self window]; return _revealButton; }
-(NSButton*)copyButton { [self window]; return _copyButton; }
-(NSButton*)activityMonitorButton { [self window]; return _activityMonitorButton; }
-(NSButton*)closeButton { [self window]; return _closeButton; }
-(NSArray<NSString*>*)rowTexts { [self window]; return [_rowTexts copy]; }
-(NSArray<NSString*>*)tipTexts { [self window]; return [_tipTexts copy]; }

//The holder the card is about: the current one, or the last one once secure input is off
-(SecureInputHolder*)shownHolder {
    return _holder != nil ? _holder : _lastHolder;
}

#pragma mark Texts

-(NSString*)heading {
    if (_holder == nil)
        return _lastHolder != nil ? @"Secure Input đã tắt" : @"Secure Input đang tắt";
    if (_holder.pid > 0 || _holder.name.length > 0)
        return [NSString stringWithFormat:@"Secure Input đang bật bởi %@", _holder.displayName];
    return @"Secure Input đang bật";
}

-(NSString*)explanation {
    if (_holder == nil) {
        if (_lastHolder == nil)
            return [NSString stringWithFormat:@"%@ chưa thấy ứng dụng nào giữ Secure Input. Khi có, biểu tượng trên thanh menu chuyển vàng và cửa sổ này cập nhật ngay.", VOK_APP_NAME];
        NSString* when = _releasedAt != nil ? [NSString stringWithFormat:@"Tắt lúc %@. ", TimeText(_releasedAt)] : @"";
        return [NSString stringWithFormat:@"%@%@ đọc được phím trở lại. Bên dưới là ứng dụng đã giữ nó.", when, VOK_APP_NAME];
    }
    switch (_effect) {
        case SecureInputEffectBlocked:
            return [NSString stringWithFormat:@"macOS không cho %@ đọc phím khi Secure Input bật, nên %@ tạm chuyển sang tiếng Anh. Biểu tượng trên thanh menu sẽ vàng cho tới khi Secure Input tắt.", VOK_APP_NAME, VOK_APP_NAME];
        case SecureInputEffectFallback:
            return [NSString stringWithFormat:@"Đang dùng bộ gõ Vietnamese của macOS thay cho %@ cho tới khi Secure Input tắt.", VOK_APP_NAME];
        case SecureInputEffectNone:
            break;
    }
    return [NSString stringWithFormat:@"%@ đang ở chế độ English nên bạn chưa bị ảnh hưởng. Nếu chuyển sang tiếng Việt lúc này, macOS vẫn không cho %@ đọc phím.", VOK_APP_NAME, VOK_APP_NAME];
}

-(NSString*)informationText {
    SecureInputHolder* holder = [self shownHolder];
    if (holder == nil)
        return [NSString stringWithFormat:@"%@: không thấy ứng dụng nào giữ Secure Input.", VOK_APP_NAME];
    NSMutableArray* lines = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@: %@", VOK_APP_NAME, [self heading]]];
    for (SecureInputRow* row in RowsFor(holder))
        [lines addObject:[NSString stringWithFormat:@"%@: %@", row.name, row.value]];
    return [lines componentsJoinedByString:@"\n"];
}

#pragma mark Building

-(NSButton*)buttonWithTitle:(NSString*)title action:(SEL)action {
    NSButton* button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

//Name at the left, value at the right; "Hiện trong Finder" under the value of the path
-(NSView*)viewForRow:(SecureInputRow*)row cardWidth:(CGFloat)cardWidth {
    NSView* view = [[NSView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    CGFloat valueWidth = cardWidth - 2 * kRowInset - kNameWidth - kColumnGap;
    NSTextField* name = PlainLabel(row.name, [NSFont systemFontOfSize:12], [NSColor secondaryLabelColor], kNameWidth, NSTextAlignmentLeft, NO);
    NSFont* font = row.monospaced ? [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular]
                                  : [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
    NSTextField* value = PlainLabel(row.value, font, [NSColor labelColor], valueWidth, NSTextAlignmentLeft, row.monospaced);
    value.selectable = YES;
    [view addSubview:name];
    [view addSubview:value];
    [NSLayoutConstraint activateConstraints:@[
        [name.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:kRowInset],
        [name.firstBaselineAnchor constraintEqualToAnchor:value.firstBaselineAnchor],
        [value.leadingAnchor constraintEqualToAnchor:name.trailingAnchor constant:kColumnGap],
        [value.topAnchor constraintEqualToAnchor:view.topAnchor constant:kRowPadding],
    ]];
    NSLayoutYAxisAnchor* bottom = value.bottomAnchor;
    if (row.reveal) {
        _revealButton = [self buttonWithTitle:@"Hiện trong Finder" action:@selector(revealPressed:)];
        _revealButton.controlSize = NSControlSizeSmall;
        _revealButton.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
        [_revealButton setAccessibilityLabel:[NSString stringWithFormat:@"Hiện %@ trong Finder", [self shownHolder].displayName]];
        [view addSubview:_revealButton];
        [NSLayoutConstraint activateConstraints:@[
            [_revealButton.leadingAnchor constraintEqualToAnchor:value.leadingAnchor],
            [_revealButton.topAnchor constraintEqualToAnchor:value.bottomAnchor constant:6],
        ]];
        bottom = _revealButton.bottomAnchor;
    }
    [view.bottomAnchor constraintEqualToAnchor:bottom constant:kRowPadding].active = YES;
    [view.heightAnchor constraintGreaterThanOrEqualToConstant:32].active = YES;
    [_rowTexts addObject:[NSString stringWithFormat:@"%@\n%@", row.name, row.value]];
    return view;
}

-(NSView*)cardWithViews:(NSArray<NSView*>*)views width:(CGFloat)width {
    NSMutableArray* parts = [NSMutableArray array];
    for (NSUInteger i = 0; i < views.count; i++) {
        if (i > 0)
            [parts addObject:VOKInsetSeparator(kRowInset)];
        [parts addObject:views[i]];
    }
    NSStackView* list = [NSStackView stackViewWithViews:parts];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.spacing = 0;
    VOKFillWidth(list);
    NSView* card = VOKCard(list);
    [card.widthAnchor constraintEqualToConstant:width].active = YES;
    return card;
}

-(NSView*)tipsCardWithTips:(NSArray<NSString*>*)tips width:(CGFloat)width {
    NSMutableArray* labels = [NSMutableArray array];
    CGFloat textWidth = width - 2 * kRowInset;
    for (NSString* tip in tips) {
        [labels addObject:BulletLabel(tip, textWidth)];
        [_tipTexts addObject:tip];
    }
    NSStackView* list = [NSStackView stackViewWithViews:labels];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.alignment = NSLayoutAttributeLeading;
    list.spacing = 7;
    list.edgeInsets = NSEdgeInsetsMake(12, kRowInset, 12, kRowInset);
    list.translatesAutoresizingMaskIntoConstraints = NO;
    NSView* card = VOKCard(list);
    [card.widthAnchor constraintEqualToConstant:width].active = YES;
    return card;
}

-(NSView*)headerImage {
    NSImageView* view;
    NSString* label;
    SecureInputHolder* holder = [self shownHolder];
    if (_holder == nil && _lastHolder != nil) {
        view = [NSImageView imageViewWithImage:VOKPaletteSymbol(@"checkmark.circle.fill", 40, @[[NSColor systemGreenColor]])];
        label = @"Secure Input đã tắt";
    } else if (_holder == nil) {
        view = [NSImageView imageViewWithImage:VOKPaletteSymbol(@"lock.open.fill", 40, @[[NSColor secondaryLabelColor]])];
        label = @"Secure Input đang tắt";
    } else if (holder.icon != nil) {
        view = [NSImageView imageViewWithImage:holder.icon];
        label = [NSString stringWithFormat:@"Biểu tượng của %@", holder.displayName];
    } else {
        view = [NSImageView imageViewWithImage:VOKPaletteSymbol(@"exclamationmark.triangle.fill", 40, @[[NSColor blackColor], [NSColor systemYellowColor]])];
        label = @"Cảnh báo Secure Input";
    }
    view.imageScaling = NSImageScaleProportionallyUpOrDown;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [view.widthAnchor constraintEqualToConstant:56].active = YES;
    [view.heightAnchor constraintEqualToConstant:56].active = YES;
    [view setAccessibilityLabel:label];
    return view;
}

-(NSView*)sectionTitle:(NSString*)title width:(CGFloat)width {
    NSTextField* label = PlainLabel(title, [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold], [NSColor secondaryLabelColor],
                                    width, NSTextAlignmentLeft, NO);
    label.accessibilityRole = NSAccessibilityStaticTextRole;
    return label;
}

-(NSView*)content {
    CGFloat width = kWidth - 2 * kMargin;
    SecureInputHolder* shown = [self shownHolder];

    NSView* icon = [self headerImage];
    _headingLabel = PlainLabel([self heading], [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold], nil, width, NSTextAlignmentCenter, NO);
    _headingLabel.selectable = YES;
    _explanationLabel = PlainLabel([self explanation], [NSFont systemFontOfSize:12], [NSColor secondaryLabelColor], width, NSTextAlignmentCenter, NO);

    NSMutableArray* views = [NSMutableArray arrayWithObjects:icon, _headingLabel, _explanationLabel, nil];
    NSMutableDictionary<NSNumber*, NSNumber*>* spacing = [NSMutableDictionary dictionary];   //after the view at that index
    spacing[@(0)] = @6;
    spacing[@(1)] = @6;
    spacing[@(2)] = @18;

    if (shown != nil) {
        NSMutableArray* rowViews = [NSMutableArray array];
        for (SecureInputRow* row in RowsFor(shown))
            [rowViews addObject:[self viewForRow:row cardWidth:width]];
        [views addObject:[self sectionTitle:_holder != nil ? @"Ứng dụng đang giữ Secure Input" : @"Ứng dụng đã giữ Secure Input lần gần nhất" width:width]];
        spacing[@(views.count - 1)] = @6;
        [views addObject:[self cardWithViews:rowViews width:width]];
        spacing[@(views.count - 1)] = @16;
    }
    if (_holder != nil) {
        [views addObject:[self sectionTitle:@"Cách tìm ra nguyên nhân" width:width]];
        spacing[@(views.count - 1)] = @6;
        [views addObject:[self tipsCardWithTips:TipsFor(_holder) width:width]];
        spacing[@(views.count - 1)] = @10;
    }

    //a line is kept free for "Đã sao chép", so that the window does not jump when it appears
    _noticeLabel = PlainLabel(@" ", [NSFont systemFontOfSize:11], [NSColor secondaryLabelColor], width, NSTextAlignmentCenter, NO);
    [views addObject:_noticeLabel];
    spacing[@(views.count - 1)] = @6;
    NSView* line = VOKSeparator();
    [line.widthAnchor constraintEqualToConstant:width].active = YES;
    [views addObject:line];

    _closeButton = [self buttonWithTitle:@"Đóng" action:@selector(closePressed:)];
    _closeButton.keyEquivalent = @"\r";
    NSView* spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSMutableArray* buttonViews = [NSMutableArray array];
    if (shown != nil) {
        _copyButton = [self buttonWithTitle:@"Sao chép thông tin" action:@selector(copyPressed:)];
        _activityMonitorButton = [self buttonWithTitle:@"Mở Activity Monitor" action:@selector(activityMonitorPressed:)];
        [buttonViews addObjectsFromArray:@[_copyButton, _activityMonitorButton]];
    }
    [buttonViews addObjectsFromArray:@[spacer, _closeButton]];
    NSStackView* buttons = [NSStackView stackViewWithViews:buttonViews];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 8;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    [buttons.widthAnchor constraintEqualToConstant:width].active = YES;
    [views addObject:buttons];

    NSStackView* stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 12;
    [spacing enumerateKeysAndObjectsUsingBlock:^(NSNumber* index, NSNumber* after, BOOL* stop) {
        if (index.unsignedIntegerValue < views.count)
            [stack setCustomSpacing:after.doubleValue afterView:views[index.unsignedIntegerValue]];
    }];
    return stack;
}

//Builds what the window shows for the situation now, and gives the window the height of it (its top stays where it is)
-(void)rebuild {
    _headingLabel = nil;
    _explanationLabel = nil;
    _noticeLabel = nil;
    _revealButton = nil;
    _copyButton = nil;
    _activityMonitorButton = nil;
    _closeButton = nil;
    [_rowTexts removeAllObjects];
    [_tipTexts removeAllObjects];
    NSView* stack = [self content];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    NSView* content = [[SecureInputDocumentView alloc] init];
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
    //VoiceOver does not read a heading that changes by itself
    if (_window.visible && _headingLabel != nil)
        NSAccessibilityPostNotificationWithUserInfo(_headingLabel, NSAccessibilityAnnouncementRequestedNotification,
                                                    @{NSAccessibilityAnnouncementKey: _headingLabel.stringValue});
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

-(void)say:(NSString*)message error:(BOOL)error {
    _noticeLabel.stringValue = message;
    _noticeLabel.textColor = error ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
    //VoiceOver does not read a label that changes by itself
    NSAccessibilityPostNotificationWithUserInfo(_noticeLabel, NSAccessibilityAnnouncementRequestedNotification,
                                                @{NSAccessibilityAnnouncementKey: message});
}

-(void)revealPressed:(id)sender { [self reveal]; }
-(void)copyPressed:(id)sender { [self copyInformation]; }
-(void)activityMonitorPressed:(id)sender { [self openActivityMonitorNow]; }
-(void)closePressed:(id)sender { [_window performClose:nil]; }

-(void)reveal {
    [self window];
    NSString* path = [self shownHolder].path;
    if (path.length == 0)
        return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self say:@"Không tìm thấy tệp này nữa: ứng dụng có thể đã bị xóa hoặc di chuyển." error:YES];
        return;
    }
    NSURL* url = [NSURL fileURLWithPath:path];
    if (self.revealURL != nil)
        self.revealURL(url);
    else
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[url]];
}

-(void)copyInformation {
    [self window];
    if ([self shownHolder] == nil)
        return;
    [_pasteboard clearContents];
    if ([_pasteboard setString:[self informationText] forType:NSPasteboardTypeString])
        [self say:@"Đã sao chép thông tin." error:NO];
    else
        [self say:@"Không sao chép được. Hãy chọn và sao chép thông tin ở trên." error:YES];
}

-(void)openActivityMonitorNow {
    [self window];
    if (self.openActivityMonitor != nil) {
        self.openActivityMonitor();
    } else {
        NSURL* url = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.apple.ActivityMonitor"];
        if (url == nil) {
            [self say:@"Không mở được Activity Monitor. Bạn có thể mở nó trong Ứng dụng > Tiện ích." error:YES];
            return;
        }
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:url configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
    }
    pid_t pid = [self shownHolder].pid;
    if (pid > 0)
        [self say:[NSString stringWithFormat:@"Trong Activity Monitor, tìm theo tên hoặc số PID %d.", pid] error:NO];
}

@end
