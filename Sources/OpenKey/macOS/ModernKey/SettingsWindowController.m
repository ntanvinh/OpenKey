//
//  SettingsWindowController.m
//  VOpenKey
//

#import "SettingsWindowController.h"
#import "AppDelegate.h"
#import "AppInfo.h"
#import "AppPermissions.h"
#import "MyTextField.h"
#import "OpenKeyManager.h"
#import "VOKUI.h"

extern AppDelegate* appDelegate;
extern void OnSpellCheckingChanged(void);

//the engine reads these, see Engine.h for what each one does
extern int vSwitchKeyStatus;
extern int vCheckSpelling;
extern int vUseModernOrthography;
extern int vQuickTelex;
extern int vRestoreIfWrongSpelling;
extern int vFixRecommendBrowser;
extern int vUseMacro;
extern int vUseMacroInEnglishMode;
extern int vSendKeyStepByStep;
extern int vUseSmartSwitchKey;
extern int vUpperCaseFirstChar;
extern int vTempOffSpelling;
extern int vAllowConsonantZFWJ;
extern int vQuickStartConsonant;
extern int vQuickEndConsonant;
extern int vRememberCode;
extern int vOtherLanguage;
extern int vTempOffOpenKey;
extern int vShowIconOnDock;
extern int vAutoCapsMacro;
extern int vFixChromiumBrowser;
extern int vPerformLayoutCompat;

static const CGFloat kCardWidth = 520;
static const CGFloat kRowInset = 14;
static NSString* const kSelectedTabKey = @"SettingsSelectedTab";

#pragma mark - One on/off option

//An option: where it is saved, which variable the engine reads it from, and what else has to happen when it changes.
@interface SettingsToggle : NSObject
@property (copy) NSString* title;
@property (copy) NSString* detail;
@property (copy) NSString* key;                 //saved as 0/1 under this key, unless there is a getter/setter
@property int* variable;                        //the engine's copy of the value, may be NULL
@property BOOL inverted;                        //saved value is the opposite of what the switch shows
@property (copy) BOOL (^getter)(void);
@property (copy) void (^setter)(BOOL on);
@property (copy) void (^onChange)(BOOL on);
@property (weak) SettingsToggle* parent;        //switched off and greyed out while the parent is off
@property (strong) NSSwitch* control;
@end

@implementation SettingsToggle

+(instancetype)title:(NSString*)title detail:(NSString*)detail key:(NSString*)key variable:(int*)variable {
    SettingsToggle* toggle = [[SettingsToggle alloc] init];
    toggle.title = title;
    toggle.detail = detail;
    toggle.key = key;
    toggle.variable = variable;
    return toggle;
}

-(BOOL)isOn {
    if (self.getter != nil)
        return self.getter();
    BOOL saved = [[NSUserDefaults standardUserDefaults] integerForKey:self.key] != 0;
    return self.inverted ? !saved : saved;
}

-(void)reload {
    self.control.state = [self isOn] ? NSControlStateValueOn : NSControlStateValueOff;
    self.control.enabled = self.parent == nil || self.parent.control.state == NSControlStateValueOn;
}

-(void)toggled:(NSSwitch*)sender {
    BOOL on = sender.state == NSControlStateValueOn;
    if (self.setter != nil) {
        self.setter(on);
    } else {
        BOOL saved = self.inverted ? !on : on;
        [[NSUserDefaults standardUserDefaults] setInteger:saved forKey:self.key];
        if (self.variable != NULL)
            *self.variable = saved;
    }
    if (self.onChange != nil)
        self.onChange(on);
}

@end

#pragma mark - The window

//Remembers which tab was open. The tab view controller is the delegate of its own tab view, so this is
//done by overriding its method, not by setting a delegate.
@interface SettingsTabs : NSTabViewController
@end

@implementation SettingsTabs
-(void)tabView:(NSTabView*)tabView didSelectTabViewItem:(NSTabViewItem*)tabViewItem {
    [super tabView:tabView didSelectTabViewItem:tabViewItem];
    [[NSUserDefaults standardUserDefaults] setInteger:[tabView indexOfTabViewItem:tabViewItem] forKey:kSelectedTabKey];
}
@end

@implementation SettingsWindowController {
    SettingsTabs* _tabs;
    NSMutableArray<SettingsToggle*>* _toggles;

    NSSegmentedControl* _language;
    NSPopUpButton* _inputType;
    NSPopUpButton* _codeTable;
    NSArray<NSButton*>* _modifierKeys;
    MyTextField* _switchKey;
    NSTextField* _accessibilityStatus;
    NSTextField* _inputMonitoringStatus;
    NSButton* _checkUpdateButton;
}

-(instancetype)init {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 400)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.toolbarStyle = NSWindowToolbarStylePreference;
    window.releasedWhenClosed = NO;
    
    self = [super initWithWindow:window];
    if (self) {
        _toggles = [NSMutableArray array];
        
        _tabs = [[SettingsTabs alloc] init];
        _tabs.tabStyle = NSTabViewControllerTabStyleToolbar;
        [self addPage:@"Bộ gõ" symbol:@"keyboard" sections:@[[self sectionTyping], [self sectionSpelling]]];
        [self addPage:@"Gõ tắt" symbol:@"text.badge.plus" sections:@[[self sectionMacro], [self sectionQuickTyping]]];
        [self addPage:@"Ứng dụng" symbol:@"macwindow" sections:@[[self sectionPerApp], [self sectionCompatibility]]];
        [self addPage:@"Hệ thống" symbol:@"gearshape" sections:@[[self sectionStartup], [self sectionPermissions], [self sectionAbout]]];
        NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:kSelectedTabKey];
        if (saved >= 0 && saved < (NSInteger)_tabs.tabViewItems.count)
            _tabs.selectedTabViewItemIndex = saved;
        
        window.contentViewController = _tabs;
        window.delegate = self;
        [window center];
        [self reload];
    }
    return self;
}

-(void)show {
    [self reload];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

-(void)windowDidBecomeKey:(NSNotification*)notification {
    [self reload]; //permissions may have been granted while the window was in the background
}

#pragma mark - Pages

-(void)addPage:(NSString*)title symbol:(NSString*)symbol sections:(NSArray<NSView*>*)sections {
    NSStackView* stack = [NSStackView stackViewWithViews:sections];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 22;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 24, 20);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView* section in sections)
        [section.widthAnchor constraintEqualToConstant:kCardWidth].active = YES;

    NSView* content = [[NSView alloc] init];
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
    NSSize size = stack.fittingSize;
    content.frame = NSMakeRect(0, 0, size.width, size.height);
    [content layoutSubtreeIfNeeded];

    NSViewController* page = [[NSViewController alloc] init];
    page.title = title;
    page.view = content;
    page.preferredContentSize = size; //the window grows or shrinks to fit the tab that is selected
    [_tabs addChildViewController:page];
    _tabs.tabViewItems.lastObject.image = VOKSymbol(symbol, 18, NSFontWeightRegular);
}

#pragma mark - Rows and sections

//A card of rows under a heading, like a group in System Settings.
-(NSView*)sectionWithTitle:(NSString*)title rows:(NSArray<NSView*>*)rows {
    NSMutableArray* parts = [NSMutableArray array];
    for (NSUInteger i = 0; i < rows.count; i++) {
        if (i > 0)
            [parts addObject:VOKSeparator()];
        [parts addObject:rows[i]];
    }
    NSStackView* list = [NSStackView stackViewWithViews:parts];
    list.orientation = NSUserInterfaceLayoutOrientationVertical;
    list.spacing = 0;
    VOKFillWidth(list);
    NSView* card = VOKCard(list);

    NSTextField* heading = VOKLabel(title, 13, NSFontWeightSemibold, nil);
    NSStackView* section = [NSStackView stackViewWithViews:@[heading, card]];
    section.orientation = NSUserInterfaceLayoutOrientationVertical;
    section.alignment = NSLayoutAttributeLeading;
    section.spacing = 8;
    section.translatesAutoresizingMaskIntoConstraints = NO;
    [card.widthAnchor constraintEqualToAnchor:section.widthAnchor].active = YES;
    return section;
}

//Name (and a line of explanation under it) on the left, the control on the right.
-(NSView*)rowWithTitle:(NSString*)title detail:(NSString*)detail control:(NSView*)control indent:(CGFloat)indent {
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [control setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [control setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    CGFloat textWidth = kCardWidth - 2 * kRowInset - 12 - control.fittingSize.width - indent;
    NSTextField* name = VOKLabel(title, 13, NSFontWeightRegular, nil);
    name.preferredMaxLayoutWidth = textWidth;
    NSMutableArray* texts = [NSMutableArray arrayWithObject:name];
    if (detail.length > 0) {
        NSTextField* explanation = VOKLabel(detail, 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
        explanation.preferredMaxLayoutWidth = textWidth;
        [texts addObject:explanation];
    }
    NSStackView* textStack = [NSStackView stackViewWithViews:texts];
    textStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    textStack.alignment = NSLayoutAttributeLeading;
    textStack.spacing = 2;

    NSView* spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* row = [NSStackView stackViewWithViews:@[textStack, spacer, control]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 12;
    row.edgeInsets = NSEdgeInsetsMake(10, kRowInset + indent, 10, kRowInset);
    row.translatesAutoresizingMaskIntoConstraints = NO;
    return row;
}

-(NSView*)rowForToggle:(SettingsToggle*)toggle {
    NSSwitch* control = [[NSSwitch alloc] init];
    control.target = toggle;
    control.action = @selector(toggled:);
    toggle.control = control;
    __weak SettingsWindowController* weakSelf = self;
    SettingsToggle* parent = toggle.parent;
    void (^original)(BOOL) = toggle.onChange;
    toggle.onChange = ^(BOOL on) {
        if (original != nil)
            original(on);
        [weakSelf reload]; //children follow their parent
    };
    [_toggles addObject:toggle];
    return [self rowWithTitle:toggle.title detail:toggle.detail control:control indent:parent != nil ? 22 : 0];
}

-(NSView*)sectionOfToggles:(NSString*)title toggles:(NSArray<SettingsToggle*>*)toggles {
    NSMutableArray* rows = [NSMutableArray array];
    for (SettingsToggle* toggle in toggles)
        [rows addObject:[self rowForToggle:toggle]];
    return [self sectionWithTitle:title rows:rows];
}

-(NSView*)buttonRowWithTitle:(NSString*)title detail:(NSString*)detail button:(NSButton*)button {
    button.bezelStyle = NSBezelStyleRounded;
    return [self rowWithTitle:title detail:detail control:button indent:0];
}

#pragma mark - Tab "Bộ gõ"

-(NSView*)sectionTyping {
    _language = [NSSegmentedControl segmentedControlWithLabels:@[@"Tiếng Việt", @"English"]
                                                  trackingMode:NSSegmentSwitchTrackingSelectOne
                                                        target:self action:@selector(languageChanged:)];

    _inputType = [[NSPopUpButton alloc] init];
    [_inputType addItemsWithTitles:@[@"Telex", @"VNI", @"Simple Telex 1", @"Simple Telex 2"]];
    _inputType.target = self;
    _inputType.action = @selector(inputTypeChanged:);

    _codeTable = [[NSPopUpButton alloc] init];
    [_codeTable addItemsWithTitles:[OpenKeyManager getTableCodes]];
    _codeTable.target = self;
    _codeTable.action = @selector(codeTableChanged:);

    //switch shortcut: modifier keys that are on, then the key
    NSMutableArray* modifiers = [NSMutableArray array];
    NSArray* glyphs = @[@"⌃", @"⌥", @"⌘", @"⇧"];
    NSArray* bits = @[@0x100, @0x200, @0x400, @0x800];
    NSArray* names = @[@"Phím Control", @"Phím Option", @"Phím Command", @"Phím Shift"];
    for (NSUInteger i = 0; i < glyphs.count; i++) {
        NSButton* key = [NSButton buttonWithTitle:glyphs[i] target:self action:@selector(modifierChanged:)];
        key.buttonType = NSButtonTypePushOnPushOff;
        key.bezelStyle = NSBezelStyleRounded;
        key.tag = [bits[i] integerValue];
        key.toolTip = names[i];
        key.translatesAutoresizingMaskIntoConstraints = NO;
        [key.widthAnchor constraintEqualToConstant:34].active = YES;
        [modifiers addObject:key];
    }
    _modifierKeys = modifiers;
    _switchKey = [[MyTextField alloc] init];
    _switchKey.Parent = (id<MyTextFieldDelegate>)self;
    _switchKey.alignment = NSTextAlignmentCenter;
    _switchKey.bezelStyle = NSTextFieldRoundedBezel;
    _switchKey.toolTip = @"Bấm một phím vào đây (Xóa để bỏ)";
    _switchKey.translatesAutoresizingMaskIntoConstraints = NO;
    [_switchKey.widthAnchor constraintEqualToConstant:44].active = YES;
    NSStackView* shortcut = [NSStackView stackViewWithViews:[modifiers arrayByAddingObject:_switchKey]];
    shortcut.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    shortcut.spacing = 6;

    SettingsToggle* beep = [[SettingsToggle alloc] init];
    beep.title = @"Kêu beep khi chuyển chế độ";
    beep.detail = @"Không áp dụng cho chuyển chế độ thông minh.";
    beep.getter = ^BOOL { return (vSwitchKeyStatus & 0x8000) != 0; };
    beep.setter = ^(BOOL on) {
        vSwitchKeyStatus = on ? (vSwitchKeyStatus | 0x8000) : (vSwitchKeyStatus & ~0x8000);
        [[NSUserDefaults standardUserDefaults] setInteger:vSwitchKeyStatus forKey:@"SwitchKeyStatus"];
    };

    return [self sectionWithTitle:@"Kiểu gõ" rows:@[
        [self rowWithTitle:@"Chế độ gõ" detail:nil control:_language indent:0],
        [self rowWithTitle:@"Kiểu gõ" detail:nil control:_inputType indent:0],
        [self rowWithTitle:@"Bảng mã" detail:@"Thường là Unicode." control:_codeTable indent:0],
        [self rowWithTitle:@"Phím chuyển chế độ" detail:nil control:shortcut indent:0],
        [self rowForToggle:beep],
    ]];
}

-(NSView*)sectionSpelling {
    SettingsToggle* spelling = [SettingsToggle title:@"Kiểm tra chính tả" detail:@"Hạn chế gõ sai từ tiếng Việt."
                                                 key:@"Spelling" variable:&vCheckSpelling];
    spelling.onChange = ^(BOOL on) { OnSpellCheckingChanged(); };
    SettingsToggle* restore = [SettingsToggle title:@"Tự khôi phục phím với từ sai" detail:@"Từ nào sai tiếng Việt thì trả lại đúng các phím đã gõ."
                                                key:@"RestoreIfInvalidWord" variable:&vRestoreIfWrongSpelling];
    SettingsToggle* consonants = [SettingsToggle title:@"Cho phép \"z w j f\" làm phụ âm đầu" detail:nil
                                                   key:@"vAllowConsonantZFWJ" variable:&vAllowConsonantZFWJ];
    SettingsToggle* tempOff = [SettingsToggle title:@"Tạm tắt chính tả bằng phím ⌃"
                                             detail:@"Bấm ⌃ để bỏ qua kiểm tra cho từ đang gõ, như Đắk Lắk, Krông…"
                                                key:@"vTempOffSpelling" variable:&vTempOffSpelling];
    restore.parent = spelling;
    consonants.parent = spelling;
    tempOff.parent = spelling;
    SettingsToggle* modern = [SettingsToggle title:@"Đặt dấu oà, uý (thay vì òa, úy)" detail:nil
                                               key:@"ModernOrthography" variable:&vUseModernOrthography];
    SettingsToggle* capitalize = [SettingsToggle title:@"Viết hoa chữ cái đầu câu" detail:@"Tự viết hoa sau dấu chấm và khi xuống dòng."
                                                   key:@"UpperCaseFirstChar" variable:&vUpperCaseFirstChar];
    return [self sectionOfToggles:@"Chính tả và dấu" toggles:@[spelling, restore, consonants, tempOff, modern, capitalize]];
}

#pragma mark - Tab "Gõ tắt"

-(NSView*)sectionMacro {
    SettingsToggle* macro = [SettingsToggle title:@"Cho phép gõ tắt" detail:@"Gõ ngắn, ra cả cụm từ để tiết kiệm thời gian."
                                              key:@"UseMacro" variable:&vUseMacro];
    SettingsToggle* inEnglish = [SettingsToggle title:@"Gõ tắt cả khi tắt gõ tiếng Việt" detail:nil
                                                  key:@"UseMacroInEnglishMode" variable:&vUseMacroInEnglishMode];
    SettingsToggle* capitalize = [SettingsToggle title:@"Tự động viết hoa theo phím tắt" detail:nil
                                                   key:@"vAutoCapsMacro" variable:&vAutoCapsMacro];
    NSButton* edit = [NSButton buttonWithTitle:@"Bảng gõ tắt…" target:self action:@selector(openMacroTable:)];

    NSMutableArray* rows = [NSMutableArray array];
    for (SettingsToggle* toggle in @[macro, inEnglish, capitalize])
        [rows addObject:[self rowForToggle:toggle]];
    [rows addObject:[self buttonRowWithTitle:@"Danh sách gõ tắt" detail:@"Thêm, sửa, nhập và xuất các từ gõ tắt." button:edit]];
    return [self sectionWithTitle:@"Gõ tắt" rows:rows];
}

-(NSView*)sectionQuickTyping {
    SettingsToggle* quick = [SettingsToggle title:@"Gõ nhanh" detail:@"cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th"
                                              key:@"QuickTelex" variable:&vQuickTelex];
    SettingsToggle* start = [SettingsToggle title:@"Gõ tắt phụ âm đầu" detail:@"f→ph, j→gi, w→qu. Ví dụ: fải→phải, jảng→giảng, wên→quên"
                                              key:@"vQuickStartConsonant" variable:&vQuickStartConsonant];
    SettingsToggle* end = [SettingsToggle title:@"Gõ tắt phụ âm cuối" detail:@"g→ng, h→nh, k→ch. Ví dụ: trươg→trương, nhah→nhanh, bák→bách"
                                            key:@"vQuickEndConsonant" variable:&vQuickEndConsonant];
    return [self sectionOfToggles:@"Gõ nhanh" toggles:@[quick, start, end]];
}

#pragma mark - Tab "Ứng dụng"

-(NSView*)sectionPerApp {
    SettingsToggle* smart = [SettingsToggle title:@"Chuyển chế độ thông minh" detail:@"Nhớ chế độ gõ Việt hay Anh cho từng ứng dụng."
                                              key:@"UseSmartSwitchKey" variable:&vUseSmartSwitchKey];
    SettingsToggle* remember = [SettingsToggle title:@"Tự ghi nhớ bảng mã theo ứng dụng" detail:@"Hữu ích khi dùng Photoshop, CAD… với bảng mã VNI, TCVN3."
                                                 key:@"vRememberCode" variable:&vRememberCode];
    SettingsToggle* otherLanguage = [SettingsToggle title:@"Tắt tiếng Việt khi bộ gõ hệ thống khác tiếng Anh"
                                                   detail:@"Tự tắt khi bạn đang dùng một bộ gõ khác của macOS."
                                                      key:@"vOtherLanguage" variable:&vOtherLanguage];
    SettingsToggle* tempOff = [SettingsToggle title:@"Tạm tắt VOpenKey bằng phím ⌘" detail:@"Bấm ⌘ để tạm ngừng cho tới khi bạn gõ một từ mới."
                                                key:@"vTempOffOpenKey" variable:&vTempOffOpenKey];
    return [self sectionOfToggles:@"Theo từng ứng dụng" toggles:@[smart, remember, otherLanguage, tempOff]];
}

-(NSView*)sectionCompatibility {
    SettingsToggle* suggestion = [SettingsToggle title:@"Sửa lỗi gợi ý" detail:@"Sửa lỗi đúp chữ trên thanh địa chỉ trình duyệt, Excel…"
                                                   key:@"FixRecommendBrowser" variable:&vFixRecommendBrowser];
    SettingsToggle* chromium = [SettingsToggle title:@"Sửa lỗi trên Chromium (beta)" detail:@"Dành cho Chrome, Edge, Brave…"
                                                 key:@"vFixChromiumBrowser" variable:&vFixChromiumBrowser];
    chromium.parent = suggestion;
    SettingsToggle* stepByStep = [SettingsToggle title:@"Gửi từng phím" detail:@"Mặc định nên tắt. Bật nếu một ứng dụng bị lỗi khi gõ."
                                                   key:@"SendKeyStepByStep" variable:&vSendKeyStepByStep];
    SettingsToggle* layout = [SettingsToggle title:@"Tương thích Telex trên các bàn phím khác" detail:@"Dvorak, Colemak…"
                                               key:@"vPerformLayoutCompat" variable:&vPerformLayoutCompat];
    return [self sectionOfToggles:@"Tương thích" toggles:@[suggestion, chromium, stepByStep, layout]];
}

#pragma mark - Tab "Hệ thống"

-(NSView*)sectionStartup {
    SettingsToggle* startup = [SettingsToggle title:@"Khởi động cùng macOS" detail:nil key:@"RunOnStartup" variable:NULL];
    startup.onChange = ^(BOOL on) { [appDelegate setRunOnStartup:on]; };
    SettingsToggle* showSettings = [SettingsToggle title:@"Mở cài đặt khi khởi động" detail:@"Hiện cửa sổ này mỗi khi chạy VOpenKey."
                                                     key:@"ShowUIOnStartup" variable:NULL];
    __weak SettingsWindowController* weakSelf = self;
    SettingsToggle* dock = [SettingsToggle title:@"Hiện biểu tượng trên thanh Dock" detail:nil key:@"vShowIconOnDock" variable:&vShowIconOnDock];
    dock.onChange = ^(BOOL on) {
        if (!on)
            [weakSelf.window close];
        [appDelegate showIconOnDock:on];
    };
    SettingsToggle* gray = [SettingsToggle title:@"Biểu tượng đơn sắc trên thanh menu" detail:@"Hợp với giao diện sáng và tối."
                                             key:@"GrayIcon" variable:NULL];
    gray.onChange = ^(BOOL on) { [appDelegate setGrayIcon:on]; };
    return [self sectionOfToggles:@"Khởi động và hiển thị" toggles:@[startup, showSettings, dock, gray]];
}

-(NSTextField*)statusLabel {
    NSTextField* label = VOKLabel(@"", 12, NSFontWeightMedium, nil);
    label.alignment = NSTextAlignmentRight;
    return label;
}

-(NSView*)permissionRowWithTitle:(NSString*)title detail:(NSString*)detail status:(NSTextField*)status action:(SEL)action {
    NSButton* open = [NSButton buttonWithTitle:@"Mở" target:self action:action];
    open.bezelStyle = NSBezelStyleRounded;
    NSStackView* trailing = [NSStackView stackViewWithViews:@[status, open]];
    trailing.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    trailing.alignment = NSLayoutAttributeCenterY;
    trailing.spacing = 10;
    [status.widthAnchor constraintEqualToConstant:72].active = YES;
    return [self rowWithTitle:title detail:detail control:trailing indent:0];
}

-(NSView*)sectionPermissions {
    _accessibilityStatus = [self statusLabel];
    _inputMonitoringStatus = [self statusLabel];
    return [self sectionWithTitle:@"Quyền" rows:@[
        [self permissionRowWithTitle:@"Trợ năng" detail:@"Để thay chữ bạn gõ bằng chữ có dấu." status:_accessibilityStatus action:@selector(openAccessibility:)],
        [self permissionRowWithTitle:@"Giám sát đầu vào" detail:@"Để biết bạn đang bấm phím nào." status:_inputMonitoringStatus action:@selector(openInputMonitoring:)],
    ]];
}

-(NSView*)sectionAbout {
    SettingsToggle* checkOnStart = [SettingsToggle title:@"Kiểm tra bản mới khi khởi động" detail:nil key:@"DontCheckUpdate" variable:NULL];
    checkOnStart.inverted = YES;
    NSMutableArray* rows = [NSMutableArray arrayWithObject:[self rowForToggle:checkOnStart]];

    NSString* version = [NSString stringWithFormat:@"Phiên bản %@ (%@)",
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
    _checkUpdateButton = [NSButton buttonWithTitle:@"Kiểm tra bản mới…" target:self action:@selector(checkForUpdate:)];
    [rows addObject:[self buttonRowWithTitle:VOK_APP_NAME detail:version button:_checkUpdateButton]];
    [rows addObject:[self buttonRowWithTitle:@"Giới thiệu" detail:[NSString stringWithFormat:@"Phát triển bởi %@, fork từ OpenKey.", VOK_COMPANY]
                                      button:[NSButton buttonWithTitle:[NSString stringWithFormat:@"Giới thiệu %@", VOK_APP_NAME] target:self action:@selector(openAbout:)]]];
    [rows addObject:[self buttonRowWithTitle:@"Khôi phục mặc định" detail:@"Đưa mọi tùy chọn về như lúc mới cài."
                                      button:[NSButton buttonWithTitle:@"Khôi phục…" target:self action:@selector(resetToDefaults:)]]];
    return [self sectionWithTitle:@"Về VOpenKey" rows:rows];
}

#pragma mark - Reading the settings back

-(void)reload {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    //parents first: a child looks at its parent's switch
    for (SettingsToggle* toggle in _toggles)
        if (toggle.parent == nil)
            [toggle reload];
    for (SettingsToggle* toggle in _toggles)
        if (toggle.parent != nil)
            [toggle reload];

    _language.selectedSegment = [defaults integerForKey:@"InputMethod"] == 1 ? 0 : 1;
    NSInteger inputType = [defaults integerForKey:@"InputType"];
    if (inputType >= 0 && inputType < _inputType.numberOfItems)
        [_inputType selectItemAtIndex:inputType];
    NSInteger codeTable = [defaults integerForKey:@"CodeTable"];
    if (codeTable >= 0 && codeTable < _codeTable.numberOfItems)
        [_codeTable selectItemAtIndex:codeTable];

    for (NSButton* key in _modifierKeys)
        key.state = (vSwitchKeyStatus & key.tag) ? NSControlStateValueOn : NSControlStateValueOff;
    [_switchKey setTextByChar:((vSwitchKeyStatus >> 24) & 0xFF)];

    [self showStatus:[AppPermissions accessibilityGranted] in:_accessibilityStatus];
    [self showStatus:[AppPermissions inputMonitoringGranted] in:_inputMonitoringStatus];
}

-(void)showStatus:(BOOL)granted in:(NSTextField*)label {
    label.stringValue = granted ? @"Đã cấp" : @"Chưa cấp";
    label.textColor = granted ? [NSColor systemGreenColor] : [NSColor systemOrangeColor];
}

#pragma mark - Actions

-(void)languageChanged:(NSSegmentedControl*)sender {
    NSInteger wanted = sender.selectedSegment == 0 ? 1 : 0;
    //the app toggles the language, so only call it when the choice is a change
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"] != wanted)
        [appDelegate onInputMethodSelected];
}

-(void)inputTypeChanged:(NSPopUpButton*)sender {
    [appDelegate onInputTypeSelectedIndex:(int)sender.indexOfSelectedItem];
}

-(void)codeTableChanged:(NSPopUpButton*)sender {
    [appDelegate onCodeTableChanged:(int)sender.indexOfSelectedItem];
}

-(void)modifierChanged:(NSButton*)sender {
    if (sender.state == NSControlStateValueOn)
        vSwitchKeyStatus |= (int)sender.tag;
    else
        vSwitchKeyStatus &= ~(int)sender.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:vSwitchKeyStatus forKey:@"SwitchKeyStatus"];
    [appDelegate refreshMenu]; //the shortcut is shown on the menu
}

//the key that was pressed in the shortcut field (MyTextFieldDelegate)
-(void)onMyTextFieldKeyChange:(unsigned short)keyCode character:(unsigned short)character {
    vSwitchKeyStatus &= 0xFFFFFF00;
    vSwitchKeyStatus |= keyCode;
    vSwitchKeyStatus &= 0x00FFFFFF;
    vSwitchKeyStatus |= ((unsigned int)character << 24);
    [[NSUserDefaults standardUserDefaults] setInteger:vSwitchKeyStatus forKey:@"SwitchKeyStatus"];
    [appDelegate refreshMenu];
}

-(void)openMacroTable:(id)sender {
    [appDelegate onMacroSelected];
}

-(void)openAccessibility:(id)sender {
    if ([AppPermissions accessibilityGranted])
        [AppPermissions openAccessibilitySettings];
    else
        [AppPermissions requestAccessibility];
}

-(void)openInputMonitoring:(id)sender {
    if ([AppPermissions inputMonitoringGranted])
        [AppPermissions openInputMonitoringSettings];
    else
        [AppPermissions requestInputMonitoring];
}

-(void)checkForUpdate:(id)sender {
    _checkUpdateButton.title = @"Đang kiểm tra…";
    _checkUpdateButton.enabled = NO;
    [OpenKeyManager checkNewVersion:self.window callbackFunc:^{
        self->_checkUpdateButton.enabled = YES;
        self->_checkUpdateButton.title = @"Kiểm tra bản mới…";
    }];
}

-(void)openAbout:(id)sender {
    [appDelegate onAboutSelected];
}

-(void)resetToDefaults:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Khôi phục cấu hình mặc định?";
    alert.informativeText = @"Mọi tùy chọn sẽ trở về như lúc mới cài. Danh sách gõ tắt của bạn không bị xóa.";
    [alert addButtonWithTitle:@"Khôi phục"];
    [alert addButtonWithTitle:@"Hủy"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn)
            return;
        [appDelegate loadDefaultConfig];
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"ShowUIOnStartup"];
        [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"RunOnStartup"];
        [appDelegate setRunOnStartup:YES];
        [self reload];
    }];
}

@end
