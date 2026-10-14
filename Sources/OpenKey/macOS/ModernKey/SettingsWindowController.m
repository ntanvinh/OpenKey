//
//  SettingsWindowController.m
//  VOpenKey
//

#import "SettingsWindowController.h"
#import "AppDelegate.h"
#import "AppInfo.h"
#import "AppPermissions.h"
#import "RememberedAppsController.h"
#import "ShortcutRecorder.h"
#import "OpenKeyManager.h"
#import "SuggestionController.h"
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
extern int convertToolHotKey;

//Spacing used by every tab, so they all have the same rhythm (multiples of 4, like System Settings)
static const CGFloat kCardWidth = 520;
static const CGFloat kPageMargin = 24;      //between the window edge and the cards
static const CGFloat kSectionSpacing = 24;  //between one group and the next
static const CGFloat kHeadingSpacing = 8;   //between a group's heading and its card
static const CGFloat kRowInset = 16;        //between the card edge and the text or control of a row
static const CGFloat kRowPadding = 10;      //above and below the text of a row
static const CGFloat kRowSpacing = 12;      //between the text of a row and its control
static const CGFloat kRowMinHeight = 44;    //a row is never lower than this, with or without a line of explanation
static const CGFloat kChildIndent = 20;     //extra inset of an option that depends on the one above it
static const CGFloat kFooterSpacing = 8;    //between a card and the note under it
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

//The page of a tab. Flipped, so that when a page is taller than the window and scrolls it starts at the top.
@interface SettingsPageView : NSView
@end

@implementation SettingsPageView
-(BOOL)isFlipped {
    return YES;
}
@end

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
    ShortcutRecorder* _switchRecorder;
    ShortcutRecorder* _convertRecorder;
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
        [self addPage:@"Gõ tắt" symbol:@"text.badge.plus" sections:@[[self sectionMacro], [self sectionConvertShortcut], [self sectionQuickTyping]]];
        [self addPage:@"Gợi ý" symbol:@"text.cursor" sections:@[[self sectionSuggestion]]];
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
    stack.spacing = kSectionSpacing;
    stack.edgeInsets = NSEdgeInsetsMake(kPageMargin, kPageMargin, kPageMargin, kPageMargin);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView* section in sections)
        [section.widthAnchor constraintEqualToConstant:kCardWidth].active = YES;

    NSView* content = [[SettingsPageView alloc] init];
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

    //a page taller than the screen scrolls instead of making a window that does not fit
    CGFloat limit = MAX(480, [NSScreen mainScreen].visibleFrame.size.height - 170); //minus the title bar, the toolbar, the menu bar
    NSView* pageView = content;
    if (size.height > limit) {
        NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, size.width, limit)];
        scroll.hasVerticalScroller = YES;
        scroll.autohidesScrollers = YES;
        scroll.drawsBackground = NO;
        scroll.documentView = content; //flipped, so it starts at its top
        pageView = scroll;
        size.height = limit;
    }

    NSViewController* page = [[NSViewController alloc] init];
    page.title = title;
    page.view = pageView;
    page.preferredContentSize = size; //the window grows or shrinks to fit the tab that is selected
    [_tabs addChildViewController:page];
    _tabs.tabViewItems.lastObject.image = VOKSymbol(symbol, 18, NSFontWeightRegular);
}

#pragma mark - Rows and sections

//A card of rows under a heading, like a group in System Settings.
-(NSView*)sectionWithTitle:(NSString*)title rows:(NSArray<NSView*>*)rows {
    return [self sectionWithTitle:title rows:rows footer:nil];
}

//Same, with a note in small grey text under the card for what does not fit in a row.
-(NSView*)sectionWithTitle:(NSString*)title rows:(NSArray<NSView*>*)rows footer:(NSString*)footer {
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

    //the heading and the note start where the text of the rows starts
    NSTextField* heading = VOKLabel(title, 13, NSFontWeightSemibold, nil);
    NSStackView* headingLine = [NSStackView stackViewWithViews:@[heading]];
    headingLine.edgeInsets = NSEdgeInsetsMake(0, kRowInset, 0, kRowInset);
    NSMutableArray* views = [NSMutableArray arrayWithObjects:headingLine, card, nil];
    NSStackView* section = [NSStackView stackViewWithViews:views];
    section.orientation = NSUserInterfaceLayoutOrientationVertical;
    section.alignment = NSLayoutAttributeLeading;
    section.spacing = kHeadingSpacing;
    section.translatesAutoresizingMaskIntoConstraints = NO;
    [card.widthAnchor constraintEqualToAnchor:section.widthAnchor].active = YES;
    [headingLine.widthAnchor constraintEqualToAnchor:section.widthAnchor].active = YES;
    if (footer.length > 0) {
        NSTextField* note = VOKLabel(footer, 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
        [self fixSizeOfLabel:note width:kCardWidth - 2 * kRowInset];
        NSStackView* noteLine = [NSStackView stackViewWithViews:@[note]];
        noteLine.edgeInsets = NSEdgeInsetsMake(0, kRowInset, 0, kRowInset);
        [section addArrangedSubview:noteLine];
        [section setCustomSpacing:kFooterSpacing afterView:card];
        [noteLine.widthAnchor constraintEqualToAnchor:section.widthAnchor].active = YES;
    }
    return section;
}

//A label that wraps gets the height of its text at that width, measured here. Leaving it to Auto Layout made a row
//whose text needs two lines keep the height of one, with the text spilling over the edge of the card.
-(void)fixSizeOfLabel:(NSTextField*)label width:(CGFloat)width {
    label.preferredMaxLayoutWidth = width;
    NSSize size = [label.cell cellSizeForBounds:NSMakeRect(0, 0, width, CGFLOAT_MAX)];
    [label.heightAnchor constraintEqualToConstant:ceil(size.height)].active = YES;
    [label.widthAnchor constraintLessThanOrEqualToConstant:width].active = YES;
}

//Name (and a line of explanation under it) on the left, the control on the right.
//The padding above and below the text is made of constraints: the edge insets of a stack view are not applied
//vertically when its views are centred, which left rows with several lines of text without any padding.
-(NSView*)rowWithTitle:(NSString*)title detail:(NSString*)detail control:(NSView*)control indent:(CGFloat)indent {
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [control setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [control setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    //the text may be as wide as what the control leaves
    CGFloat textWidth = kCardWidth - 2 * kRowInset - kRowSpacing - ceil(control.fittingSize.width) - indent;
    NSTextField* name = VOKLabel(title, 13, NSFontWeightRegular, nil);
    [self fixSizeOfLabel:name width:textWidth];
    NSMutableArray* texts = [NSMutableArray arrayWithObject:name];
    if (detail.length > 0) {
        NSTextField* explanation = VOKLabel(detail, 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
        [self fixSizeOfLabel:explanation width:textWidth];
        [texts addObject:explanation];
    }
    NSStackView* textStack = [NSStackView stackViewWithViews:texts];
    textStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    textStack.alignment = NSLayoutAttributeLeading;
    textStack.spacing = 3;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;

    NSView* row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:textStack];
    [row addSubview:control];
    [NSLayoutConstraint activateConstraints:@[
        [textStack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:kRowInset + indent],
        [textStack.topAnchor constraintEqualToAnchor:row.topAnchor constant:kRowPadding],
        [textStack.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-kRowPadding],
        [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-kRowSpacing],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-kRowInset],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:kRowMinHeight],
    ]];
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
    return [self rowWithTitle:toggle.title detail:toggle.detail control:control indent:parent != nil ? kChildIndent : 0];
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

    //the shortcut that switches the language: recorded by pressing it
    _switchRecorder = [[ShortcutRecorder alloc] init];
    _switchRecorder.toolTip = @"Bấm vào ô rồi nhấn phím tắt mới. Cũng có thể chỉ giữ hai phím bổ trợ, ví dụ ⌃⇧, rồi thả ra. Xóa để bỏ phím tắt.";
    _switchRecorder.conflict = ^NSString*(int data) {
        return VOKShortcutsEqual(data, convertToolHotKey) ? @"Chuyển mã nhanh" : nil;
    };
    __weak SettingsWindowController* weakSelf = self;
    _switchRecorder.onChange = ^(int data) {
        vSwitchKeyStatus = data;
        [[NSUserDefaults standardUserDefaults] setInteger:vSwitchKeyStatus forKey:@"SwitchKeyStatus"];
        [appDelegate refreshMenu]; //the shortcut is shown on the menu
        (void)weakSelf;
    };

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
        [self rowWithTitle:@"Phím chuyển chế độ" detail:@"Bấm vào ô rồi nhấn tổ hợp phím mới."
                      control:_switchRecorder indent:0],
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

-(NSView*)sectionConvertShortcut {
    ShortcutRecorder* recorder = [[ShortcutRecorder alloc] init];
    _convertRecorder = recorder; //the Convert window records the same shortcut: reload() keeps this one up to date
    recorder.value = convertToolHotKey;
    recorder.toolTip = @"Bấm vào ô rồi nhấn phím tắt mới. Cũng có thể chỉ giữ hai phím bổ trợ, ví dụ ⌃⇧, rồi thả ra. Xóa để bỏ phím tắt.";
    recorder.conflict = ^NSString*(int data) {
        return VOKShortcutsEqual(data, vSwitchKeyStatus) ? @"Chuyển chế độ gõ" : nil;
    };
    recorder.onChange = ^(int data) {
        convertToolHotKey = data;
        [[NSUserDefaults standardUserDefaults] setInteger:convertToolHotKey forKey:@"convertToolHotKey"];
        [appDelegate setQuickConvertString];
    };
    return [self sectionWithTitle:@"Chuyển mã"
                             rows:@[[self rowWithTitle:@"Phím chuyển mã nhanh"
                                                detail:@"Chọn nội dung rồi bấm phím tắt để chuyển mã trong clipboard."
                                               control:recorder indent:0]]];
}

-(NSView*)sectionSuggestion {
    void (^changed)(BOOL) = ^(BOOL on) { [SuggestionController reloadSettings]; };
    SettingsToggle* enabled = [SettingsToggle title:@"Thanh gợi ý khi gõ"
                                             detail:@"Hiện từ gợi ý dưới chữ đang gõ. Giữ ⌥ và bấm số 1–5 để chọn."
                                                key:@"SuggestionEnabled" variable:&vSuggestEnabled];
    enabled.onChange = changed;
    SettingsToggle* compounds = [SettingsToggle title:@"Gợi ý từ ghép"
                                               detail:@"Gõ liền không dấu cũng ra từ ghép, ví dụ thietke ra thiết kế."
                                                  key:@"SuggestionCompounds" variable:&vSuggestCompounds];
    compounds.onChange = changed;
    compounds.parent = enabled;
    SettingsToggle* nextWord = [SettingsToggle title:@"Dự đoán từ kế tiếp" detail:@"Gợi ý ngay sau dấu cách, trước khi bạn gõ chữ nào."
                                                 key:@"SuggestionNextWord" variable:&vSuggestNextWord];
    nextWord.onChange = changed;
    nextWord.parent = enabled;
    SettingsToggle* tab = [SettingsToggle title:@"Dùng Tab để chọn gợi ý đầu tiên"
                                          detail:@"Khi bật, Tab không còn chuyển sang ô kế tiếp trong form lúc thanh gợi ý đang hiện."
                                             key:@"SuggestionTab" variable:&vSuggestTabAccepts];
    tab.onChange = changed;
    tab.parent = enabled;
    SettingsToggle* learn = [SettingsToggle title:@"Học từ cách gõ của bạn"
                                           detail:@"Nhớ từ và cụm từ bạn hay dùng, chỉ lưu trên máy này."
                                              key:@"SuggestionLearn" variable:&vSuggestLearn];
    learn.onChange = changed;
    learn.parent = enabled;

    NSMutableArray* rows = [NSMutableArray array];
    for (SettingsToggle* toggle in @[enabled, compounds, nextWord, tab, learn])
        [rows addObject:[self rowForToggle:toggle]];
    NSButton* folder = [NSButton buttonWithTitle:@"Mở thư mục…" target:self action:@selector(openDictionaryFolder:)];
    [rows addObject:[self buttonRowWithTitle:@"Từ điển" detail:@"Thả thêm file .txt vào thư mục để bổ sung từ và cụm từ." button:folder]];
    NSButton* reload = [NSButton buttonWithTitle:@"Tải lại" target:self action:@selector(reloadDictionaries:)];
    [rows addObject:[self buttonRowWithTitle:@"Tải lại từ điển" detail:@"Sau khi thêm hoặc sửa file từ điển." button:reload]];
    NSButton* forget = [NSButton buttonWithTitle:@"Xóa…" target:self action:@selector(forgetLearnedWords:)];
    [rows addObject:[self buttonRowWithTitle:@"Dữ liệu đã học" detail:@"Quên mọi từ và cụm từ VOpenKey đã học từ bạn." button:forget]];
    return [self sectionWithTitle:@"Gợi ý khi gõ" rows:rows
                           footer:@"Chỉ dùng được với bảng mã Unicode. Tự tắt trong Terminal và khi gõ mật khẩu."];
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
    NSMutableArray* rows = [NSMutableArray array];
    for (SettingsToggle* toggle in @[smart, remember, otherLanguage, tempOff])
        [rows addObject:[self rowForToggle:toggle]];
    NSButton* list = [NSButton buttonWithTitle:@"Xem danh sách…" target:self action:@selector(openRememberedApps:)];
    [rows addObject:[self buttonRowWithTitle:@"Ứng dụng đã ghi nhớ" detail:@"Xem và sửa chế độ gõ, bảng mã VOpenKey đã nhớ cho từng ứng dụng." button:list]];
    return [self sectionWithTitle:@"Theo từng ứng dụng" rows:rows];
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

    _switchRecorder.value = vSwitchKeyStatus;
    _convertRecorder.value = convertToolHotKey;

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

-(void)openRememberedApps:(id)sender {
    [RememberedAppsController presentFromWindow:self.window];
}

-(void)openDictionaryFolder:(id)sender {
    [SuggestionController openDictionaryFolder];
}

-(void)reloadDictionaries:(id)sender {
    [SuggestionController reloadDictionaries];
}

-(void)forgetLearnedWords:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Xóa dữ liệu đã học?";
    alert.informativeText = @"VOpenKey sẽ quên mọi từ và cụm từ đã học từ cách gõ của bạn. Từ điển có sẵn không bị ảnh hưởng.";
    //the safe choice is the default one, the destructive one is in red
    [alert addButtonWithTitle:@"Hủy"];
    [alert addButtonWithTitle:@"Xóa"].hasDestructiveAction = YES;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertSecondButtonReturn)
            [SuggestionController forgetLearnedWords];
    }];
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
    [alert addButtonWithTitle:@"Hủy"];
    [alert addButtonWithTitle:@"Khôi phục"].hasDestructiveAction = YES;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertSecondButtonReturn)
            return;
        [appDelegate loadDefaultConfig];
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"ShowUIOnStartup"];
        [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"RunOnStartup"];
        [appDelegate setRunOnStartup:YES];
        [self reload];
    }];
}

@end
