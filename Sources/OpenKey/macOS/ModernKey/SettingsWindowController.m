//
//  SettingsWindowController.m
//  VOpenKey
//

#import "SettingsWindowController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "AppDelegate.h"
#import "AIAgentCLI.h"
#import "AIClient.h"
#import "AIKeychain.h"
#import "AILocalControl.h"
#import "AILocalSetupController.h"
#import "AIOllamaRuntime.h"
#import "AISettings.h"
#import "AppInfo.h"
#import "AppPermissions.h"
#import "AppUpdater.h"
#import "CaseBar.h"
#import "RememberedAppsController.h"
#import "ShortcutConflicts.h"
#import "ShortcutRecorder.h"
#import "InputSourceGuard.h"
#import "OpenKeyManager.h"
#import "SnippetEditorController.h"
#import "SnippetPalette.h"
#import "SnippetStore.h"
#import "SuggestionController.h"
#import "WordRestore.h"
#import "VOKUI.h"

extern AppDelegate* appDelegate;
extern void OnSpellCheckingChanged(void);

@interface SettingsWindowController () <NSTextFieldDelegate, NSComboBoxDelegate>
@end

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
@property (copy) NSString* hint;                //the longer explanation, shown when the pointer rests on the row
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

//The app has no main menu, so ⌘W would do nothing: the settings window handles it (and Esc) itself, like System Settings.
@interface SettingsWindow : NSWindow
@end

@implementation SettingsWindow
-(BOOL)performKeyEquivalent:(NSEvent*)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (flags == NSEventModifierFlagCommand && [event.charactersIgnoringModifiers isEqualToString:@"w"]) {
        [self performClose:nil];
        return YES;
    }
    return [super performKeyEquivalent:event];
}
@end

@implementation SettingsTabs
-(void)tabView:(NSTabView*)tabView didSelectTabViewItem:(NSTabViewItem*)tabViewItem {
    [super tabView:tabView didSelectTabViewItem:tabViewItem];
    [[NSUserDefaults standardUserDefaults] setInteger:[tabView indexOfTabViewItem:tabViewItem] forKey:kSelectedTabKey];
}
@end

@implementation SettingsWindowController {
    SettingsTabs* _tabs;
    NSStackView* _suggestionAppsSection;
    NSMutableArray<SettingsToggle*>* _toggles;

    NSSegmentedControl* _language;
    NSPopUpButton* _inputType;
    NSPopUpButton* _codeTable;
    ShortcutRecorder* _switchRecorder;
    ShortcutRecorder* _convertRecorder;
    ShortcutRecorder* _snippetRecorder;
    ShortcutRecorder* _restoreRecorder;

    //the AI tab
    ShortcutRecorder* _aiRecorder;
    ShortcutRecorder* _caseRecorder;
    NSPopUpButton* _aiProvider;
    NSView* _aiProgramRow, *_aiKeyRow, *_aiURLRow, *_aiEffortRow, *_aiImagePromptRow;     //the rows that are there for some services only
    NSTextField* _aiImagePrompt;
    NSTextField* _aiProgramPath;
    NSTextField* _aiProgramStatus;
    NSButton* _aiProgramChoose;
    NSButton* _aiProgramReset;
    NSPopUpButton* _aiEffort;
    NSTextField* _aiEffortStatus;
    NSMutableSet<NSString*>* _aiModelsRequested;                       //the programs whose list of models was asked since the application started
    NSSecureTextField* _aiKey;
    NSTextField* _aiKeyStatus;
    NSButton* _aiSaveKey;
    NSButton* _aiRemoveKey;
    NSButton* _aiKeyPage;
    NSTextField* _aiURL;
    NSTextField* _aiURLStatus;
    NSComboBox* _aiModel;
    NSTextField* _aiModelStatus;
    NSButton* _aiTestButton;
    NSTextField* _aiTestStatus;
    NSTextField* _aiPrompt;
    NSTextField* _aiLocalStatus;
    NSTextField* _aiLocalLoad;
    NSTextField* _aiLocalProblem;
    NSButton* _aiLocalStart;
    NSButton* _aiLocalStop;
    NSButton* _aiLocalUnload;
    NSStackView* _aiLocalButtons;
    NSTimer* _aiLocalTimer;
    NSLayoutConstraint* _aiLocalStatusHeight, *_aiLocalLoadHeight, *_aiLocalProblemHeight;     //the texts change: their height follows them
    AIClient* _aiTestClient;
    NSTextField* _accessibilityStatus;
    NSTextField* _inputMonitoringStatus;
    NSButton* _checkUpdateButton;
}

-(instancetype)init {
    NSWindow* window = [[SettingsWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 400)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable //only the close button, as in System Settings
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
        [self addPage:@"Gợi ý" symbol:@"text.cursor" sections:@[[self sectionSuggestion], [self sectionSuggestionApps], [self sectionCaseBar]]];
        [self addPage:@"Snippet" symbol:@"text.insert" sections:@[[self sectionSnippets]]];
        [self addPage:@"AI" symbol:@"sparkles" sections:@[[self sectionAI], [self sectionAILocal], [self sectionAIConnection]]];
        [self addPage:@"Ứng dụng" symbol:@"macwindow" sections:@[[self sectionPerApp], [self sectionCompatibility]]];
        [self addPage:@"Hệ thống" symbol:@"gearshape" sections:@[[self sectionStartup], [self sectionPermissions], [self sectionAbout]]];
        NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:kSelectedTabKey];
        if (saved >= 0 && saved < (NSInteger)_tabs.tabViewItems.count)
            _tabs.selectedTabViewItemIndex = saved;
        
        window.contentViewController = _tabs;
        window.delegate = self;
        [window center];
        [self reload];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(aiLocalSetupFinished:) name:VOKAILocalSetupDidFinishNotification object:nil];
    }
    return self;
}

-(void)show {
    [self reload];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

-(void)showTabTitled:(NSString*)title {
    for (NSUInteger i = 0; i < _tabs.tabViewItems.count; i++) {
        if ([_tabs.tabViewItems[i].label isEqualToString:title])
            _tabs.selectedTabViewItemIndex = (NSInteger)i;
    }
    [self show];
}

-(void)windowDidBecomeKey:(NSNotification*)notification {
    [self reload]; //permissions may have been granted while the window was in the background
    [self startAILocalTimer];
}

-(void)windowDidResignKey:(NSNotification*)notification {
    [self stopAILocalTimer];
}

-(void)windowWillClose:(NSNotification*)notification {
    [self stopAILocalTimer];
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
    CGFloat limit = [self pageHeightLimit];
    NSView* pageView = content;
    // The editable app list can grow after this page is built.
    if (size.height > limit || [title isEqualToString:@"Gợi ý"]) {
        CGFloat viewportHeight = MIN(size.height, limit);
        NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, size.width, viewportHeight)];
        scroll.hasVerticalScroller = YES;
        scroll.autohidesScrollers = YES;
        scroll.drawsBackground = NO;
        scroll.documentView = content; //flipped, so it starts at its top
        pageView = scroll;
        size.height = viewportHeight;
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
    return [self rowWithTitle:title detail:detail hint:nil control:control indent:indent];
}

//`detail` is the short line under the name that everybody reads. `hint` is for what takes more words: it is shown as a tooltip
//on the row, and a small (i) after the name tells that there is one.
-(NSView*)rowWithTitle:(NSString*)title detail:(NSString*)detail hint:(NSString*)hint control:(NSView*)control indent:(CGFloat)indent {
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [control setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [control setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    //the text may be as wide as what the control leaves
    CGFloat textWidth = kCardWidth - 2 * kRowInset - kRowSpacing - ceil(control.fittingSize.width) - indent;
    const CGFloat kHintIcon = 14, kHintGap = 5;
    NSString* tip = VOKTooltip(hint);
    NSTextField* name = VOKLabel(title, 13, NSFontWeightRegular, nil);
    [self fixSizeOfLabel:name width:tip != nil ? textWidth - kHintIcon - kHintGap : textWidth];
    NSView* nameLine = name;
    if (tip != nil) {
        NSImageView* icon = [NSImageView imageViewWithImage:VOKSymbol(@"info.circle", 12, NSFontWeightRegular)];
        icon.contentTintColor = [NSColor tertiaryLabelColor];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [icon.widthAnchor constraintEqualToConstant:kHintIcon].active = YES;
        [icon.heightAnchor constraintEqualToConstant:kHintIcon].active = YES;
        icon.toolTip = tip;
        name.toolTip = tip;
        NSStackView* line = [NSStackView stackViewWithViews:@[name, icon]];
        line.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        line.alignment = NSLayoutAttributeCenterY;
        line.spacing = kHintGap;
        line.translatesAutoresizingMaskIntoConstraints = NO;
        nameLine = line;
    }
    NSMutableArray* texts = [NSMutableArray arrayWithObject:nameLine];
    if (detail.length > 0) {
        NSTextField* explanation = VOKLabel(detail, 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
        [self fixSizeOfLabel:explanation width:textWidth];
        explanation.toolTip = tip;
        [texts addObject:explanation];
    }
    NSStackView* textStack = [NSStackView stackViewWithViews:texts];
    textStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    textStack.alignment = NSLayoutAttributeLeading;
    textStack.spacing = 3;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;

    NSView* row = [[NSView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.toolTip = tip;
    textStack.toolTip = tip;
    [row addSubview:textStack];
    [row addSubview:control];
    [NSLayoutConstraint activateConstraints:@[
        [textStack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:kRowInset + indent],
        [textStack.topAnchor constraintEqualToAnchor:row.topAnchor constant:kRowPadding],
        [textStack.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-kRowPadding],
        [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-kRowSpacing],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-kRowInset],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        //a control taller than the text (a field with a line of status under it) makes the row taller
        [control.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:kRowPadding],
        [control.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-kRowPadding],
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
    return [self rowWithTitle:toggle.title detail:toggle.detail hint:toggle.hint control:control indent:parent != nil ? kChildIndent : 0];
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
        return VOKShortcutConflict(data, VOKShortcutOwnerSwitch);
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

    SettingsToggle* forceABC = [SettingsToggle title:@"Giữ bộ gõ macOS ở ABC khi gõ tiếng Việt"
                                              detail:@"Tránh gõ hai lần khi bộ gõ Vietnamese của macOS cũng đang bật: nếu gặp nó, VOpenKey AI chuyển về ABC."
                                                 key:@"ForceABCWhenVietnamese" variable:&vForceABC];
    forceABC.onChange = ^(BOOL on) { [InputSourceGuard enforce]; };

    return [self sectionWithTitle:@"Kiểu gõ" rows:@[
        [self rowWithTitle:@"Chế độ gõ" detail:nil control:_language indent:0],
        [self rowWithTitle:@"Kiểu gõ" detail:nil control:_inputType indent:0],
        [self rowWithTitle:@"Bảng mã" detail:@"Thường là Unicode." control:_codeTable indent:0],
        [self rowWithTitle:@"Phím chuyển chế độ" detail:@"Bấm vào ô rồi nhấn tổ hợp phím mới."
                      control:_switchRecorder indent:0],
        [self rowForToggle:beep],
        [self rowForToggle:forceABC],
    ]];
}

-(NSView*)sectionSpelling {
    SettingsToggle* spelling = [SettingsToggle title:@"Kiểm tra chính tả" detail:@"Hạn chế gõ sai từ tiếng Việt."
                                                 key:@"Spelling" variable:&vCheckSpelling];
    spelling.onChange = ^(BOOL on) { OnSpellCheckingChanged(); };
    SettingsToggle* restore = [SettingsToggle title:@"Tự khôi phục từ không phải tiếng Việt"
                                             detail:@"Gõ xong từ mà không phải tiếng Việt, như rétỏe, thì trả lại đúng các phím đã gõ: restore. Không cần bật kiểm tra chính tả."
                                                key:@"RestoreIfInvalidWord" variable:&vRestoreIfWrongSpelling];
    SettingsToggle* consonants = [SettingsToggle title:@"Cho phép \"z w j f\" làm phụ âm đầu" detail:nil
                                                   key:@"vAllowConsonantZFWJ" variable:&vAllowConsonantZFWJ];
    SettingsToggle* tempOff = [SettingsToggle title:@"Tạm tắt chính tả bằng phím ⌃"
                                             detail:@"Bấm ⌃ để bỏ qua kiểm tra cho từ đang gõ, như Đắk Lắk, Krông…"
                                                key:@"vTempOffSpelling" variable:&vTempOffSpelling];
    consonants.parent = spelling;
    tempOff.parent = spelling;
    SettingsToggle* modern = [SettingsToggle title:@"Đặt dấu oà, uý (thay vì òa, úy)" detail:nil
                                               key:@"ModernOrthography" variable:&vUseModernOrthography];
    SettingsToggle* capitalize = [SettingsToggle title:@"Viết hoa chữ cái đầu câu" detail:@"Tự viết hoa sau dấu chấm và khi xuống dòng."
                                                   key:@"UpperCaseFirstChar" variable:&vUpperCaseFirstChar];

    //the shortcut that gives the keys of the word being typed back, for what the automatic restore does not catch
    _restoreRecorder = [[ShortcutRecorder alloc] init];
    _restoreRecorder.value = vRestoreHotKey;
    _restoreRecorder.toolTip = @"Bấm vào ô rồi nhấn phím tắt mới. Cũng có thể chỉ giữ hai phím bổ trợ, ví dụ ⌃⇧, rồi thả ra. Xóa để bỏ phím tắt.";
    _restoreRecorder.conflict = ^NSString*(int data) {
        return VOKShortcutConflict(data, VOKShortcutOwnerRestore);
    };
    _restoreRecorder.onChange = ^(int data) {
        vRestoreHotKey = data;
        [[NSUserDefaults standardUserDefaults] setInteger:vRestoreHotKey forKey:@"RestoreHotKey"];
    };

    NSMutableArray* rows = [NSMutableArray array];
    for (SettingsToggle* toggle in @[spelling, restore])
        [rows addObject:[self rowForToggle:toggle]];
    [rows addObject:[self rowWithTitle:@"Phím khôi phục từ đang gõ"
                                detail:@"Từ đang gõ bị biến thành sai (rétỏe, ví dụ)? Bấm phím này để trả lại đúng các phím đã gõ."
                               control:_restoreRecorder indent:0]];
    for (SettingsToggle* toggle in @[consonants, tempOff, modern, capitalize])
        [rows addObject:[self rowForToggle:toggle]];
    return [self sectionWithTitle:@"Chính tả và dấu" rows:rows];
}

#pragma mark - Tab "Gõ tắt"

-(NSView*)sectionMacro {
    SettingsToggle* macro = [SettingsToggle title:@"Cho phép gõ tắt" detail:@"Gõ ngắn, ra cả cụm từ để tiết kiệm thời gian."
                                              key:@"UseMacro" variable:&vUseMacro];
    macro.onChange = ^(BOOL on) { [SuggestionController reloadSettings]; };
    SettingsToggle* confirm = [SettingsToggle title:@"Hỏi trước khi thay chữ viết tắt"
                                             detail:@"Chữ viết tắt không tự đổi: bản đầy đủ hiện trên thanh gợi ý, bấm Tab (hoặc ⌥1) để thay. Gõ tiếp thì giữ nguyên, ví dụ vn ở cuối tên miền .com.vn. Không áp dụng khi tắt gõ tiếng Việt."
                                                key:@"MacroConfirm" variable:&vMacroConfirm];
    confirm.onChange = ^(BOOL on) { [SuggestionController reloadSettings]; };
    confirm.parent = macro;
    SettingsToggle* inEnglish = [SettingsToggle title:@"Gõ tắt cả khi tắt gõ tiếng Việt" detail:nil
                                                  key:@"UseMacroInEnglishMode" variable:&vUseMacroInEnglishMode];
    SettingsToggle* capitalize = [SettingsToggle title:@"Tự động viết hoa theo phím tắt" detail:nil
                                                   key:@"vAutoCapsMacro" variable:&vAutoCapsMacro];
    NSButton* edit = [NSButton buttonWithTitle:@"Bảng gõ tắt…" target:self action:@selector(openMacroTable:)];

    NSMutableArray* rows = [NSMutableArray array];
    for (SettingsToggle* toggle in @[macro, confirm, inEnglish, capitalize])
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
        return VOKShortcutConflict(data, VOKShortcutOwnerConvert);
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
                                             detail:@"Hiện từ gợi ý dưới chữ đang gõ. Tab chọn từ đầu, ⌥1–⌥5 chọn từ khác."
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
                                          detail:@"Muốn chuyển sang ô kế tiếp trong form khi thanh gợi ý đang hiện, bấm ⌥Tab: nó là Tab thường. Tắt thì Tab luôn là Tab thường."
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
    [rows addObject:[self buttonRowWithTitle:@"Dữ liệu đã học" detail:@"Quên mọi từ và cụm từ VOpenKey AI đã học từ bạn." button:forget]];
    return [self sectionWithTitle:@"Gợi ý khi gõ" rows:rows
                           footer:@"Chỉ dùng được với bảng mã Unicode. Không hiện khi gõ mật khẩu."];
}

-(NSView*)sectionSuggestionApps {
    _suggestionAppsSection = [NSStackView stackViewWithViews:@[]];
    _suggestionAppsSection.orientation = NSUserInterfaceLayoutOrientationVertical;
    _suggestionAppsSection.spacing = 0;
    VOKFillWidth(_suggestionAppsSection);
    [self reloadSuggestionApps];
    return _suggestionAppsSection;
}

-(void)reloadSuggestionApps {
    for (NSView* view in _suggestionAppsSection.arrangedSubviews.copy)
        [view removeFromSuperview];
    NSMutableArray<NSView*>* rows = [NSMutableArray array];
    NSArray<NSString*>* apps = [SuggestionController excludedApps];
    NSSwitch* enabled = [[NSSwitch alloc] init];
    enabled.state = [SuggestionController appExclusionsEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    enabled.target = self;
    enabled.action = @selector(toggleSuggestionAppExclusions:);
    [enabled setAccessibilityLabel:@"Tự tắt gợi ý theo ứng dụng"];
    [rows addObject:[self rowWithTitle:@"Tự tắt gợi ý theo ứng dụng"
                               detail:@"Tắt thanh gợi ý khi chuyển sang các ứng dụng trong danh sách."
                              control:enabled indent:0]];
    BOOL expanded = [NSUserDefaults.standardUserDefaults boolForKey:@"SuggestionAppsExpanded"];
    NSButton* disclosure = [NSButton buttonWithTitle:expanded ? @"Thu gọn" : @"Hiện danh sách"
                                            target:self action:@selector(toggleSuggestionAppsExpanded:)];
    VOKSetButtonSymbol(disclosure, expanded ? @"chevron.down" : @"chevron.right", 11);
    [disclosure setAccessibilityLabel:expanded ? @"Thu gọn danh sách ứng dụng" : @"Mở danh sách ứng dụng"];
    [rows addObject:[self buttonRowWithTitle:@"Danh sách ứng dụng"
                                    detail:[NSString stringWithFormat:@"%lu ứng dụng", (unsigned long)apps.count]
                                    button:disclosure]];
    if (expanded) {
        for (NSString* identifier in apps) {
            NSURL* url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:identifier];
            NSString* name = url ? [NSFileManager.defaultManager displayNameAtPath:url.path] : [SuggestionController defaultNameForExcludedApp:identifier];
            if ([name hasSuffix:@".app"])
                name = name.stringByDeletingPathExtension;
            NSButton* remove = [NSButton buttonWithTitle:@"Bỏ khỏi danh sách" target:self action:@selector(removeSuggestionApp:)];
            remove.identifier = identifier;
            [remove setAccessibilityLabel:[NSString stringWithFormat:@"Bỏ %@ khỏi danh sách tự tắt gợi ý", name]];
            [rows addObject:[self buttonRowWithTitle:name detail:identifier button:remove]];
        }
        NSButton* add = [NSButton buttonWithTitle:@"Thêm ứng dụng…" target:self action:@selector(addSuggestionApp:)];
        [rows addObject:[self buttonRowWithTitle:apps.count ? @"Thêm ứng dụng" : @"Chưa có ứng dụng nào"
                                        detail:apps.count ? @"Chọn ứng dụng cần tự tắt thanh gợi ý." : @"Thêm ứng dụng để tự tắt gợi ý khi chuyển sang ứng dụng đó."
                                        button:add]];
    }
    NSView* section = [self sectionWithTitle:@"Tự tắt gợi ý trong ứng dụng" rows:rows
                                     footer:expanded ? @"Mặc định có các terminal phổ biến. Tắt công tắc vẫn giữ danh sách. Bạn có thể chỉnh danh sách cả khi đang tắt." : nil];
    [_suggestionAppsSection addArrangedSubview:section];
    [section.widthAnchor constraintEqualToAnchor:_suggestionAppsSection.widthAnchor].active = YES;
    NSScrollView* scroll = _suggestionAppsSection.enclosingScrollView;
    if (scroll != nil) {
        NSView* content = scroll.documentView;
        NSView* stack = content.subviews.firstObject;
        NSSize size = stack.fittingSize;
        [content setFrameSize:NSMakeSize(content.frame.size.width, MAX(size.height, scroll.contentSize.height))];
        [content layoutSubtreeIfNeeded];
        [scroll reflectScrolledClipView:scroll.contentView];
    }
}

-(void)toggleSuggestionAppExclusions:(NSSwitch*)sender {
    [SuggestionController setAppExclusionsEnabled:sender.state == NSControlStateValueOn];
}

-(void)toggleSuggestionAppsExpanded:(id)sender {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:![defaults boolForKey:@"SuggestionAppsExpanded"] forKey:@"SuggestionAppsExpanded"];
    [self reloadSuggestionApps];
    // Rebuilding the rows replaces the disclosure button; keep keyboard navigation there.
    NSButton* disclosure = VOKFindButton(_suggestionAppsSection, @selector(toggleSuggestionAppsExpanded:));
    [self.window makeFirstResponder:disclosure];
}

-(void)removeSuggestionApp:(NSButton*)sender {
    NSMutableArray* apps = [[SuggestionController excludedApps] mutableCopy];
    [apps removeObject:sender.identifier];
    [SuggestionController setExcludedApps:apps];
    [self reloadSuggestionApps];
}

-(void)addSuggestionApp:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypeApplicationBundle];
    panel.directoryURL = [NSURL fileURLWithPath:@"/Applications" isDirectory:YES];
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.prompt = @"Thêm ứng dụng";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK)
            return;
        NSMutableArray* apps = [[SuggestionController excludedApps] mutableCopy];
        NSMutableArray* invalid = [NSMutableArray array];
        for (NSURL* url in panel.URLs) {
            NSString* identifier = [NSBundle bundleWithURL:url].bundleIdentifier;
            if (identifier.length > 0)
                [apps addObject:identifier];
            else
                [invalid addObject:url.lastPathComponent];
        }
        [SuggestionController setExcludedApps:apps];
        [self reloadSuggestionApps];
        if (invalid.count > 0) {
            NSAlert* alert = [[NSAlert alloc] init];
            alert.messageText = @"Không thể thêm ứng dụng";
            alert.informativeText = [NSString stringWithFormat:@"Ứng dụng không có mã định danh: %@. Hãy chọn lại một ứng dụng .app hợp lệ.", [invalid componentsJoinedByString:@", "]];
            [alert addButtonWithTitle:@"Đóng"];
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
        }
    }];
}

-(NSView*)sectionCaseBar {
    SettingsToggle* automatic = [SettingsToggle title:@"Hiện thanh đổi chữ khi chọn văn bản"
                                               detail:@"Chọn chữ bằng chuột hoặc Shift+mũi tên, thanh hiện ra ngay dưới vùng chọn."
                                                  key:@"CaseBarAuto" variable:&vCaseBarAuto];
    automatic.hint = @"Chọn kiểu chữ bằng ⌥1…⌥9 hoặc bấm chuột. Bấm phím khác, bấm chuột hay cuộn là thanh biến mất. Chỉ hoạt động ở ứng dụng cho đọc vùng chọn; không đụng tới clipboard cho tới khi bạn chọn một kiểu.";
    automatic.onChange = ^(BOOL on) { [CaseBar start]; };

    _caseRecorder = [[ShortcutRecorder alloc] init];
    _caseRecorder.value = vCaseBarHotKey;
    _caseRecorder.toolTip = VOKTooltip(@"Bấm vào ô rồi nhấn phím tắt mới. Cũng có thể chỉ giữ hai phím bổ trợ, ví dụ ⌃⇧, rồi thả ra. Xóa để bỏ phím tắt.");
    _caseRecorder.conflict = ^NSString*(int data) {
        return VOKShortcutConflict(data, VOKShortcutOwnerCaseBar);
    };
    _caseRecorder.onChange = ^(int data) {
        vCaseBarHotKey = data;
        [[NSUserDefaults standardUserDefaults] setInteger:vCaseBarHotKey forKey:@"CaseBarHotKey"];
        [appDelegate refreshMenu]; //the shortcut is shown on the menu
    };
    return [self sectionWithTitle:@"Đổi chữ hoa/thường" rows:@[
        [self rowForToggle:automatic],
        [self rowWithTitle:@"Phím tắt" detail:@"Chọn văn bản rồi bấm để mở thanh, dùng được cả ở ứng dụng không cho đọc vùng chọn." control:_caseRecorder indent:0],
    ] footer:@"Chữ hoa, chữ thường, Viết Hoa Từng Từ, viết hoa đầu câu, camelCase, snake_case… và bỏ dấu tiếng Việt. "
             @"Mỗi dòng hiện trước kết quả. Dùng ⌥1…⌥9 hoặc bấm chuột; khi mở bằng phím tắt còn dùng được ↑ ↓ ↩ và Esc."];
}

#pragma mark - Tab "Snippet"

-(NSView*)sectionSnippets {
    SettingsToggle* enabled = [SettingsToggle title:@"Chèn snippet bằng phím tắt"
                                             detail:@"Bấm phím tắt ở bất kỳ ứng dụng nào để tìm snippet và chèn vào chỗ đang gõ."
                                                key:@"SnippetsEnabled" variable:&vSnippetsEnabled];
    enabled.onChange = ^(BOOL on) { [appDelegate refreshMenu]; };

    ShortcutRecorder* recorder = [[ShortcutRecorder alloc] init];
    _snippetRecorder = recorder;
    recorder.value = vSnippetHotKey;
    recorder.toolTip = @"Bấm vào ô rồi nhấn phím tắt mới. Cũng có thể chỉ giữ hai phím bổ trợ, ví dụ ⌃⇧, rồi thả ra. Xóa để bỏ phím tắt.";
    recorder.conflict = ^NSString*(int data) {
        return VOKShortcutConflict(data, VOKShortcutOwnerSnippet);
    };
    recorder.onChange = ^(int data) {
        vSnippetHotKey = data;
        [[NSUserDefaults standardUserDefaults] setInteger:vSnippetHotKey forKey:@"SnippetHotKey"];
        [appDelegate refreshMenu]; //the shortcut is shown on the menu
    };

    NSButton* manage = [NSButton buttonWithTitle:@"Quản lý…" target:self action:@selector(openSnippetEditor:)];
    NSButton* restore = [NSButton buttonWithTitle:@"Khôi phục…" target:self action:@selector(restoreSnippets:)];
    return [self sectionWithTitle:@"Snippet" rows:@[
        [self rowForToggle:enabled],
        [self rowWithTitle:@"Phím tắt mở snippet" detail:@"Bấm vào ô rồi nhấn tổ hợp phím mới." control:recorder indent:0],
        [self buttonRowWithTitle:@"Danh sách snippet" detail:@"Thêm, sửa hoặc xóa snippet. Có sẵn các prompt mẫu cho trợ lý AI." button:manage],
        [self buttonRowWithTitle:@"Snippet mẫu" detail:@"Lấy lại các snippet mẫu đã xóa và đưa các bản đã sửa về như ban đầu." button:restore],
    ] footer:@"Trong nội dung snippet, {clipboard} được thay bằng chữ đang sao chép, {date} bằng ngày hôm nay (14/10/2026) "
             @"và {time} bằng giờ hiện tại (09:05). Snippet được dán bằng ⌘V, sau đó clipboard của bạn được trả lại như cũ."];
}

#pragma mark - Tab "AI"

-(NSTextField*)aiStatusLabelWithWidth:(CGFloat)width {
    NSTextField* label = VOKLabel(@"", 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    label.preferredMaxLayoutWidth = width;
    [label.widthAnchor constraintEqualToConstant:width].active = YES;
    return label;
}

-(NSTextField*)aiFieldWithWidth:(CGFloat)width placeholder:(NSString*)placeholder secure:(BOOL)secure {
    NSTextField* field = secure ? [[NSSecureTextField alloc] init] : [[NSTextField alloc] init];
    field.placeholderString = placeholder;
    field.delegate = self;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.widthAnchor constraintEqualToConstant:width].active = YES;
    return field;
}

-(NSStackView*)aiStack:(NSArray<NSView*>*)views vertical:(BOOL)vertical spacing:(CGFloat)spacing {
    NSStackView* stack = [NSStackView stackViewWithViews:views];
    stack.orientation = vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = vertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

//what the shortcut does, and how the selected text is found
-(NSView*)sectionAI {
    SettingsToggle* enabled = [SettingsToggle title:@"Mở trợ lý AI bằng phím tắt" detail:nil key:@"AIEnabled" variable:&vAIEnabled];
    enabled.hint = @"Chọn một đoạn văn rồi bấm phím tắt để nhờ AI dịch, sửa, tóm tắt. Không chọn gì thì nhờ viết nội dung mới.";
    enabled.onChange = ^(BOOL on) { [appDelegate refreshMenu]; };

    _aiRecorder = [[ShortcutRecorder alloc] init];
    _aiRecorder.value = vAIHotKey;
    _aiRecorder.toolTip = VOKTooltip(@"Bấm vào ô rồi nhấn phím tắt mới. Cũng có thể chỉ giữ hai phím bổ trợ, ví dụ ⌃⇧, rồi thả ra. Xóa để bỏ phím tắt.");
    _aiRecorder.conflict = ^NSString*(int data) {
        return VOKShortcutConflict(data, VOKShortcutOwnerAI);
    };
    _aiRecorder.onChange = ^(int data) {
        vAIHotKey = data;
        [[NSUserDefaults standardUserDefaults] setInteger:vAIHotKey forKey:@"AIHotKey"];
        [appDelegate refreshMenu]; //the shortcut is shown on the menu
    };

    SettingsToggle* copy = [SettingsToggle title:@"Lấy chữ đang chọn bằng ⌘C khi cần" detail:nil key:@"AICopySelection" variable:&vAICopySelection];
    copy.hint = @"Trình duyệt, Trae, VS Code… không cho đọc vùng chọn trực tiếp. VOpenKey AI bấm ⌘C rồi trả clipboard về như cũ.";
    return [self sectionWithTitle:@"Trợ lý AI" rows:@[
        [self rowForToggle:enabled],
        [self rowWithTitle:@"Phím tắt" detail:nil control:_aiRecorder indent:0],
        [self rowForToggle:copy],
    ]];
}

//an AI that runs on this Mac: installed from a window of its own, that checks the Mac first; once there is one it can be started
//and stopped from here, because a model that runs is heavy and only suits a Mac that has little else to do
-(NSView*)sectionAILocal {
    const CGFloat width = 300;
    NSButton* install = [NSButton buttonWithTitle:@"Cài AI chạy trên máy…" target:self action:@selector(aiOpenLocalSetup:)];
    install.bezelStyle = NSBezelStyleRounded;
    VOKSetButtonSymbol(install, @"arrow.down.circle", 13);

    _aiLocalStart = [NSButton buttonWithTitle:@"Khởi động" target:self action:@selector(aiLocalStart:)];
    _aiLocalStop = [NSButton buttonWithTitle:@"Dừng" target:self action:@selector(aiLocalStop:)];
    _aiLocalUnload = [NSButton buttonWithTitle:@"Giải phóng RAM" target:self action:@selector(aiLocalUnload:)];
    VOKSetButtonSymbol(_aiLocalStart, @"play.fill", 11);
    VOKSetButtonSymbol(_aiLocalStop, @"stop.fill", 11);
    VOKSetButtonSymbol(_aiLocalUnload, @"memorychip", 11);
    _aiLocalStop.toolTip = VOKTooltip(@"Tắt hẳn Ollama do VOpenKey AI mở. Ollama do ứng dụng khác mở thì phải tắt ở ứng dụng đó.");
    _aiLocalStart.toolTip = VOKTooltip(@"Mở Ollama ngay, để lần hỏi đầu tiên không phải chờ khởi động.");
    _aiLocalUnload.toolTip = VOKTooltip(@"Đưa model ra khỏi RAM ngay mà không tắt Ollama. Lần hỏi sau model sẽ nạp lại nên câu trả lời đầu chậm hơn.");
    for (NSButton* button in @[_aiLocalStart, _aiLocalStop, _aiLocalUnload])
        button.bezelStyle = NSBezelStyleRounded;
    _aiLocalButtons = [self aiStack:@[_aiLocalStart, _aiLocalStop, _aiLocalUnload] vertical:NO spacing:6];
    _aiLocalStatus = [self aiStatusLabelWithWidth:width];
    _aiLocalLoad = [self aiStatusLabelWithWidth:width];
    _aiLocalProblem = [self aiStatusLabelWithWidth:width];
    _aiLocalProblem.textColor = [NSColor systemRedColor];
    NSStackView* control = [self aiStack:@[install, _aiLocalStatus, _aiLocalButtons, _aiLocalLoad, _aiLocalProblem] vertical:YES spacing:6];
    install.toolTip = VOKTooltip(@"Kiểm tra máy, khuyên một model phù hợp rồi tự cài Ollama và model đó.");
    NSView* section = [self sectionWithTitle:@"AI chạy trên máy" rows:@[
        [self rowWithTitle:@"Không cần internet" detail:@"Không cần API key, chữ không rời khỏi máy."
                      hint:@"Không cần API key, không tính tiền theo lượt dùng, chữ của bạn không rời khỏi máy.\n"
                           @"Chạy model là việc rất nặng: nó dùng hết sức của bộ xử lý và chiếm nhiều RAM, nên chỉ hợp khi máy đang ít việc. "
                           @"Cần macOS 14 trở lên, chip Apple Silicon (M1 trở lên) và RAM từ 8 GB; Mac chip Intel chạy được nhưng chậm.\n"
                           @"Ollama do VOpenKey AI mở chỉ chạy khi cần và tắt khi thoát VOpenKey AI; bấm Dừng để tắt ngay."
                   control:control indent:0],
    ]];
    AILocalControl* local = [AILocalControl shared];
    __weak SettingsWindowController* weakSelf = self;
    local.onChange = ^{ [weakSelf reloadAILocalStatus]; };
    [self reloadAILocalStatus];
    [local refresh];
    return section;
}

-(void)aiOpenLocalSetup:(id)sender {
    [AILocalSetupController show];
}

-(void)aiLocalSetupFinished:(NSNotification*)notification {
    [self reloadAI];                    //the assistant now uses the model that was installed
    [[AILocalControl shared] refresh];
}

-(void)aiLocalStart:(id)sender { [[AILocalControl shared] start]; }
-(void)aiLocalStop:(id)sender { [[AILocalControl shared] stop]; }
-(void)aiLocalUnload:(id)sender { [[AILocalControl shared] unload]; }

//what is on this Mac: shown from what AILocalControl last read; it reads again while this window is in front
-(void)reloadAILocalStatus {
    if (_aiLocalStatus == nil)
        return;
    AILocalControl* local = [AILocalControl shared];
    AIProvider* provider = AISettings.provider;
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    if ([provider.identifier isEqualToString:@"ollama"])
        [lines addObject:[NSString stringWithFormat:@"Trợ lý đang dùng model %@.", [AISettings modelForProvider:provider]]];
    [lines addObject:local.briefStatusText];
    [self aiSetText:[lines componentsJoinedByString:@"\n"] label:_aiLocalStatus height:&_aiLocalStatusHeight];
    _aiLocalStatus.toolTip = VOKTooltip(local.statusText);
    _aiLocalButtons.hidden = !local.detected;                       //nothing to start or stop until there is an Ollama
    _aiLocalStart.enabled = local.canStart;
    _aiLocalStop.enabled = local.canStop;
    _aiLocalUnload.enabled = local.canUnload;
    [self aiSetText:local.detected ? local.briefLoadText : @"" label:_aiLocalLoad height:&_aiLocalLoadHeight];
    _aiLocalLoad.toolTip = VOKTooltip(local.loadText);
    _aiLocalLoad.hidden = !local.detected;
    _aiLocalLoad.textColor = local.macIsBusy ? [NSColor systemOrangeColor] : [NSColor secondaryLabelColor];
    [self aiSetText:local.problemText ?: @"" label:_aiLocalProblem height:&_aiLocalProblemHeight];
    _aiLocalProblem.hidden = local.problemText.length == 0;
    [self refitPageOf:_aiLocalStatus];
}

//A page is measured once, when it is built, and its frame is fixed to that size. A text that changes (a status of two lines instead
//of one) or a control that appears or hides makes the content taller or shorter than the frame, and the rows are then squeezed over
//each other. After such a change the page is measured again.
-(void)refitPageOf:(NSView*)view {
    //not while the tab view controller is still putting the page in its window: that resizes the window too, and changing the page
    //under it left the window at the size of an empty page (a clipped page when the AI tab was the one open at launch)
    __weak SettingsWindowController* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refitNowPageOf:view]; });
}

-(void)refitNowPageOf:(NSView*)view {
    NSView* content = view;
    while (content != nil && ![content isKindOfClass:[SettingsPageView class]])
        content = content.superview;
    NSStackView* stack = content.subviews.firstObject;
    if (![stack isKindOfClass:[NSStackView class]])
        return;                                                                     //not in a page yet: it is measured when the page is built
    [stack layoutSubtreeIfNeeded];
    NSSize size = stack.fittingSize;
    if (fabs(size.height - content.frame.size.height) < 0.5 && fabs(size.width - content.frame.size.width) < 0.5)
        return;
    content.frame = NSMakeRect(0, 0, size.width, size.height);
    [content layoutSubtreeIfNeeded];
    //the window follows the page: its size is what the tab view controller asks the page for
    for (NSViewController* page in _tabs.childViewControllers) {
        NSView* shown = page.view;
        if ([shown isKindOfClass:[NSScrollView class]])
            shown = ((NSScrollView*)shown).documentView;
        if (shown == content)
            page.preferredContentSize = NSMakeSize(size.width, MIN(size.height, [self pageHeightLimit]));
    }
}

//a page taller than the screen scrolls instead of making a window that does not fit
-(CGFloat)pageHeightLimit {
    return MAX(480, [NSScreen mainScreen].visibleFrame.size.height - 170);          //minus the title bar, the toolbar, the menu bar
}

//a text of several lines in a column of fixed width, whose height has to follow the text when it changes
-(void)aiSetText:(NSString*)text label:(NSTextField*)label height:(NSLayoutConstraint* __strong *)height {
    label.stringValue = text;
    NSSize size = [label.cell cellSizeForBounds:NSMakeRect(0, 0, label.preferredMaxLayoutWidth, CGFLOAT_MAX)];
    if (*height == nil) {
        *height = [label.heightAnchor constraintEqualToConstant:ceil(size.height)];
        (*height).active = YES;
    } else {
        (*height).constant = ceil(size.height);
    }
}

-(void)startAILocalTimer {
    [self stopAILocalTimer];
    [[AILocalControl shared] refresh];
    __weak SettingsWindowController* weakSelf = self;
    _aiLocalTimer = [NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer* timer) {
        if (weakSelf == nil) { [timer invalidate]; return; }
        [[AILocalControl shared] refresh];
    }];
}

-(void)stopAILocalTimer {
    [_aiLocalTimer invalidate];
    _aiLocalTimer = nil;
}

//which AI, with what key
-(NSView*)sectionAIConnection {
    const CGFloat width = 300;

    //the services with an address first, then the programs that are signed in by themselves
    _aiProvider = [[NSPopUpButton alloc] init];
    _aiProvider.autoenablesItems = NO;
    BOOL programsStarted = NO;
    for (AIProvider* provider in [AIProvider allProviders]) {
        if (provider.isAgentCLI && !programsStarted) {
            programsStarted = YES;
            [_aiProvider.menu addItem:[NSMenuItem separatorItem]];
            NSMenuItem* heading = [[NSMenuItem alloc] initWithTitle:@"Chương trình đã đăng nhập sẵn trên máy" action:nil keyEquivalent:@""];
            heading.enabled = NO;
            [_aiProvider.menu addItem:heading];
        }
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:provider.name action:nil keyEquivalent:@""];
        item.representedObject = provider.identifier;
        [_aiProvider.menu addItem:item];
    }
    _aiProvider.target = self;
    _aiProvider.action = @selector(aiProviderChanged:);
    _aiProvider.translatesAutoresizingMaskIntoConstraints = NO;
    [_aiProvider.widthAnchor constraintEqualToConstant:width].active = YES;
    _aiKeyPage = [NSButton buttonWithTitle:@"Lấy key…" target:self action:@selector(aiOpenKeyPage:)];
    _aiKeyPage.bezelStyle = NSBezelStyleInline;
    _aiKeyPage.controlSize = NSControlSizeSmall;
    NSStackView* providerControl = [self aiStack:@[_aiProvider, _aiKeyPage] vertical:YES spacing:4];

    //a program (Codex, Claude Code, Antigravity): where it is, and the thinking level
    _aiProgramPath = [self aiStatusLabelWithWidth:width];
    _aiProgramPath.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _aiProgramPath.maximumNumberOfLines = 1;
    _aiProgramPath.textColor = [NSColor labelColor];
    _aiProgramPath.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _aiProgramChoose = [NSButton buttonWithTitle:@"Chọn…" target:self action:@selector(aiChooseProgram:)];
    _aiProgramReset = [NSButton buttonWithTitle:@"Tìm lại" target:self action:@selector(aiResetProgram:)];
    for (NSButton* button in @[_aiProgramChoose, _aiProgramReset])
        button.bezelStyle = NSBezelStyleRounded;
    _aiProgramReset.toolTip = VOKTooltip(@"Bỏ đường dẫn đã chọn, để VOpenKey AI tự tìm chương trình ở những nơi thường cài.");
    _aiProgramStatus = [self aiStatusLabelWithWidth:width];
    NSStackView* programControl = [self aiStack:@[_aiProgramPath, [self aiStack:@[_aiProgramChoose, _aiProgramReset] vertical:NO spacing:6], _aiProgramStatus]
                                       vertical:YES spacing:4];
    _aiEffort = [[NSPopUpButton alloc] init];
    _aiEffort.target = self;
    _aiEffort.action = @selector(aiEffortChanged:);
    _aiEffort.translatesAutoresizingMaskIntoConstraints = NO;
    [_aiEffort.widthAnchor constraintEqualToConstant:width].active = YES;
    _aiEffortStatus = [self aiStatusLabelWithWidth:width];
    NSStackView* effortControl = [self aiStack:@[_aiEffort, _aiEffortStatus] vertical:YES spacing:4];

    //the key: typed once, then it only lives in the keychain
    _aiKey = (NSSecureTextField*)[self aiFieldWithWidth:width - 150 placeholder:@"Dán API key vào đây" secure:YES];
    _aiSaveKey = [NSButton buttonWithTitle:@"Lưu" target:self action:@selector(aiSaveKey:)];
    _aiRemoveKey = [NSButton buttonWithTitle:@"Xóa key" target:self action:@selector(aiRemoveKey:)];
    for (NSButton* button in @[_aiSaveKey, _aiRemoveKey])
        button.bezelStyle = NSBezelStyleRounded;
    _aiKeyStatus = [self aiStatusLabelWithWidth:width];
    NSStackView* keyControl = [self aiStack:@[[self aiStack:@[_aiKey, _aiSaveKey, _aiRemoveKey] vertical:NO spacing:6], _aiKeyStatus] vertical:YES spacing:4];

    _aiURL = [self aiFieldWithWidth:width placeholder:@"https://máy-chủ/v1" secure:NO];
    _aiURLStatus = [self aiStatusLabelWithWidth:width];
    NSStackView* urlControl = [self aiStack:@[_aiURL, _aiURLStatus] vertical:YES spacing:4];

    _aiModel = [[NSComboBox alloc] init];
    _aiModel.delegate = self;
    _aiModel.completes = NO;
    _aiModel.numberOfVisibleItems = 12;
    _aiModel.placeholderString = @"Tên model";
    _aiModel.translatesAutoresizingMaskIntoConstraints = NO;
    [_aiModel.widthAnchor constraintEqualToConstant:width - 120].active = YES;
    NSButton* list = [NSButton buttonWithTitle:@"Tải danh sách" target:self action:@selector(aiListModels:)];
    list.bezelStyle = NSBezelStyleRounded;
    _aiModelStatus = [self aiStatusLabelWithWidth:width];
    NSStackView* modelControl = [self aiStack:@[[self aiStack:@[_aiModel, list] vertical:NO spacing:6], _aiModelStatus] vertical:YES spacing:4];

    _aiTestButton = [NSButton buttonWithTitle:@"Kiểm tra kết nối" target:self action:@selector(aiTest:)];
    _aiTestButton.bezelStyle = NSBezelStyleRounded;
    _aiTestStatus = [self aiStatusLabelWithWidth:width];
    NSStackView* testControl = [self aiStack:@[_aiTestButton, _aiTestStatus] vertical:YES spacing:4];

    _aiPrompt = [self aiFieldWithWidth:width placeholder:[AISettings defaultSystemPrompt] secure:NO];
    _aiPrompt.usesSingleLineMode = NO;
    _aiPrompt.lineBreakMode = NSLineBreakByWordWrapping;
    _aiPrompt.cell.wraps = YES;
    _aiPrompt.cell.scrollable = NO;
    _aiPrompt.maximumNumberOfLines = 6;
    [_aiPrompt.heightAnchor constraintEqualToConstant:92].active = YES;
    _aiPrompt.stringValue = AISettings.systemPrompt;
    NSButton* resetPrompt = [NSButton buttonWithTitle:@"Dùng lời nhắc mặc định" target:self action:@selector(aiResetPrompt:)];
    resetPrompt.bezelStyle = NSBezelStyleInline;
    resetPrompt.controlSize = NSControlSizeSmall;
    NSStackView* promptControl = [self aiStack:@[_aiPrompt, resetPrompt] vertical:YES spacing:4];

    //what is said to Codex to make a picture
    _aiImagePrompt = [self aiFieldWithWidth:width placeholder:[AISettings defaultImagePrompt] secure:NO];
    _aiImagePrompt.usesSingleLineMode = NO;
    _aiImagePrompt.lineBreakMode = NSLineBreakByWordWrapping;
    _aiImagePrompt.cell.wraps = YES;
    _aiImagePrompt.cell.scrollable = NO;
    _aiImagePrompt.maximumNumberOfLines = 4;
    [_aiImagePrompt.heightAnchor constraintEqualToConstant:60].active = YES;
    _aiImagePrompt.stringValue = AISettings.imagePrompt;
    NSButton* resetImagePrompt = [NSButton buttonWithTitle:@"Dùng lệnh mặc định" target:self action:@selector(aiResetImagePrompt:)];
    resetImagePrompt.bezelStyle = NSBezelStyleInline;
    resetImagePrompt.controlSize = NSControlSizeSmall;
    NSStackView* imagePromptControl = [self aiStack:@[_aiImagePrompt, resetImagePrompt] vertical:YES spacing:4];

    _aiImagePromptRow = [self rowWithTitle:@"Lệnh tạo ảnh" detail:nil
                                      hint:@"Gửi cho Codex khi bấm “Tạo ảnh” trong hộp thoại trợ lý; {prompt} là mô tả của bạn. Phải nhắc tên kỹ năng $imagegen thì Codex mới tạo ảnh đẹp. "
                                           @"“our design system” chỉ là lời nhắc: Codex chạy trong một thư mục trống nên không thấy hệ thống thiết kế nào, hãy thay bằng mô tả phong cách của bạn hoặc bỏ đi. "
                                           @"Tạo ảnh dùng model và mức suy nghĩ đang chọn, thường mất 20 đến 40 giây."
                                   control:imagePromptControl indent:0];
    _aiProgramRow = [self rowWithTitle:@"Chương trình" detail:nil
                                  hint:@"Dùng chương trình AI đã cài và đăng nhập sẵn trên máy này, không cần API key. VOpenKey AI không đọc tài khoản hay token của chương trình: "
                                       @"mỗi yêu cầu chỉ chạy nó một lần, trong một thư mục tạm trống, không cho nó dùng công cụ, chạy lệnh hay đọc, sửa tệp của bạn."
                               control:programControl indent:0];
    _aiKeyRow = [self rowWithTitle:@"API key" detail:nil
                              hint:@"Chỉ lưu trong Keychain của tài khoản macOS đang dùng, không ghi ra file, không đồng bộ iCloud. Tài khoản macOS khác trên máy này phải nhập key riêng."
                           control:keyControl indent:0];
    _aiURLRow = [self rowWithTitle:@"Địa chỉ máy chủ" detail:nil control:urlControl indent:0];
    _aiEffortRow = [self rowWithTitle:@"Mức suy nghĩ" detail:nil
                                 hint:@"Mức càng cao thì AI càng suy nghĩ lâu: chậm hơn và tốn hạn mức hơn, hiếm khi cần cho viết, dịch hay sửa chữ. Đo thực tế: mức Thấp thường vài giây, mức Vừa có thể 15 đến 40 giây, mức Cao có thể cả phút. “Tự động” dùng mức thấp nhất mà model nhận."
                              control:effortControl indent:0];
    NSView* section = [self sectionWithTitle:@"Dịch vụ AI" rows:@[
        [self rowWithTitle:@"Dịch vụ" detail:nil
                      hint:@"Nội dung bạn nhập và chữ đang chọn được gửi tới dịch vụ bạn chọn; AI chạy trên máy (Ollama, LM Studio) thì không rời khỏi máy."
                   control:providerControl indent:0],
        _aiProgramRow,
        _aiKeyRow,
        _aiURLRow,
        [self rowWithTitle:@"Model" detail:nil control:modelControl indent:0],
        _aiEffortRow,
        _aiImagePromptRow,
        [self rowWithTitle:@"Kết nối" detail:nil control:testControl indent:0],
        [self rowWithTitle:@"Lời nhắc hệ thống" detail:nil
                      hint:@"Dặn AI cách trả lời, gửi kèm mọi yêu cầu."
                   control:promptControl indent:0],
    ]];

    _aiModelsRequested = [NSMutableSet set];
    [self reloadAI];
    return section;
}

-(AIProvider*)aiProviderInUse {
    return AISettings.provider;
}

//puts what is saved for the provider in use into the controls
-(void)reloadAI {
    if (_aiProvider == nil)
        return;
    AIProvider* provider = [self aiProviderInUse];
    AIAgentCLI* cli = [AIAgentCLI forProvider:provider];
    [_aiProvider selectItemAtIndex:[_aiProvider indexOfItemWithRepresentedObject:provider.identifier]];
    _aiProvider.toolTip = VOKTooltip(provider.note);     //what is special about this service: a tooltip, not a paragraph
    _aiKeyPage.hidden = provider.keyPageURL.length == 0;

    //a program has no key and no address; a service has no program and no thinking level
    [self aiSetRow:_aiProgramRow hidden:cli == nil];
    [self aiSetRow:_aiEffortRow hidden:cli == nil];
    [self aiSetRow:_aiImagePromptRow hidden:!cli.canMakeImages];
    [self aiSetRow:_aiKeyRow hidden:cli != nil];
    [self aiSetRow:_aiURLRow hidden:cli != nil];

    BOOL hasKey = [AIKeychain hasKeyForProvider:provider.identifier];
    _aiKey.stringValue = @"";
    _aiKey.placeholderString = hasKey ? @"•••••••••••• (đã lưu)" : (provider.needsKey ? @"Dán API key vào đây" : @"Không bắt buộc");
    [self aiShow:hasKey ? @"Đã lưu." : (provider.needsKey ? @"Chưa có key." : @"Dịch vụ này không cần key.") in:_aiKeyStatus error:NO];
    _aiSaveKey.enabled = NO;
    _aiRemoveKey.enabled = hasKey;

    _aiURL.stringValue = [AISettings baseURLForProvider:provider];
    _aiURL.placeholderString = provider.defaultBaseURL.length > 0 ? provider.defaultBaseURL : @"https://máy-chủ/v1";
    [self aiShow:@"" in:_aiURLStatus error:NO];
    _aiModel.stringValue = [AISettings modelForProvider:provider];
    [_aiModel removeAllItems];
    _aiModel.placeholderString = cli == nil ? @"Tên model" : (cli.kind == AIAgentKindClaude ? @"haiku" : @"Tự chọn model nhẹ");
    [self aiShow:@"" in:_aiModelStatus error:NO];
    [self aiShow:@"" in:_aiTestStatus error:NO];
    _aiPrompt.stringValue = AISettings.systemPrompt;
    _aiImagePrompt.stringValue = AISettings.imagePrompt;
    if (cli != nil)
        [self reloadAIProgram];
    [self reloadAILocalStatus];
    [self refitPageOf:_aiProvider];                         //the note and the link to the keys appear and hide with the service
}

//hides or shows a row of the card together with the line above it
-(void)aiSetRow:(NSView*)row hidden:(BOOL)hidden {
    NSStackView* list = [row.superview isKindOfClass:[NSStackView class]] ? (NSStackView*)row.superview : nil;
    NSUInteger index = [list.arrangedSubviews indexOfObject:row];
    row.hidden = hidden;
    if (index != NSNotFound && index > 0)
        list.arrangedSubviews[index - 1].hidden = hidden;
}

#pragma mark A program on this Mac

//where the program is, what the user chose, and the models and levels it offers
-(void)reloadAIProgram {
    AIProvider* provider = [self aiProviderInUse];
    AIAgentCLI* cli = [AIAgentCLI forProvider:provider];
    if (cli == nil)
        return;
    NSString* found = [AISettings executablePathForProvider:provider];
    NSString* chosen = [AISettings programForProvider:provider];
    _aiProgramReset.hidden = chosen == nil;
    _aiProgramPath.stringValue = found ?: [NSString stringWithFormat:@"Không tìm thấy `%@`", cli.command];
    _aiProgramPath.toolTip = found;
    _aiProgramPath.textColor = found != nil ? [NSColor labelColor] : [NSColor systemRedColor];
    if (found != nil) {
        NSMutableArray<NSString*>* lines = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@. Chưa đăng nhập? Mở Terminal và chạy: %@",
                                                                            chosen != nil && [chosen isEqualToString:found] ? @"Đường dẫn do bạn chọn" : @"Tự tìm thấy", cli.loginHint]];
        if (cli.storageNote.length > 0)
            [lines addObject:cli.storageNote];
        [self aiShow:[lines componentsJoinedByString:@"\n"] in:_aiProgramStatus error:NO];
    } else {
        NSString* install = cli.installHint.length > 0 ? [NSString stringWithFormat:@" Cài bằng: %@, rồi bấm “Tìm lại”.", cli.installHint] : @" Cài nó rồi bấm “Tìm lại”.";
        [self aiShow:[NSString stringWithFormat:@"Chưa có `%@` trong những nơi thường cài.%@ Hoặc bấm “Chọn…” để chỉ đường dẫn.", cli.command, install] in:_aiProgramStatus error:YES];
    }
    [self aiReloadModelList];
    [self aiReloadEfforts];
    //the models of Codex and Antigravity come from the program itself: asked once
    if (found != nil && [cli knownModels].count == 0 && cli.kind != AIAgentKindClaude && ![_aiModelsRequested containsObject:provider.identifier]) {
        [_aiModelsRequested addObject:provider.identifier];
        [cli loadModelsFromExecutable:found completion:^(NSArray<AIAgentModel*>* models, NSError* error) {
            if (models.count > 0 && provider == [self aiProviderInUse]) {
                [self aiReloadModelList];
                [self aiReloadEfforts];
            }
        }];
    }
}

//the names in the box of models are those the program has
-(void)aiReloadModelList {
    AIAgentCLI* cli = [AIAgentCLI forProvider:[self aiProviderInUse]];
    if (cli == nil)
        return;
    NSString* typed = _aiModel.stringValue;
    [_aiModel removeAllItems];
    NSMutableArray<NSString*>* names = [NSMutableArray array];
    for (AIAgentModel* model in [cli knownModels])
        [names addObject:model.identifier];
    [_aiModel addItemsWithObjectValues:names];
    _aiModel.stringValue = typed;
    [self aiShow:names.count > 0 ? [NSString stringWithFormat:@"%lu model. Để trống để VOpenKey AI tự chọn model nhẹ.", (unsigned long)names.count]
                                 : @"Bấm “Tải danh sách” để xem model của chương trình."
              in:_aiModelStatus error:NO];
}

//the levels of the model that will be used, with "automatic" and "what the program does by itself" around them
-(void)aiReloadEfforts {
    AIProvider* provider = [self aiProviderInUse];
    AIAgentCLI* cli = [AIAgentCLI forProvider:provider];
    if (cli == nil)
        return;
    NSArray<AIAgentModel*>* models = [cli knownModels];
    NSString* used = [cli modelToPassForSaved:[AISettings modelForProvider:provider] models:models];
    AIAgentModel* known = used.length > 0 ? [AIAgentCLI modelWithIdentifier:used among:models] : nil;
    NSArray<NSString*>* levels = known.efforts ?: [AIAgentCLI commonEfforts];
    [_aiEffort removeAllItems];
    NSMenuItem* automatic = [[NSMenuItem alloc] initWithTitle:@"Tự động (khuyên dùng: nhanh nhất)" action:nil keyEquivalent:@""];
    automatic.representedObject = @"";
    [_aiEffort.menu addItem:automatic];
    for (NSString* level in levels) {
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:[AIAgentCLI nameOfEffort:level] action:nil keyEquivalent:@""];
        item.representedObject = level;
        item.toolTip = [AIAgentCLI speedNoteForEffort:level];
        [_aiEffort.menu addItem:item];
    }
    NSMenuItem* own = [[NSMenuItem alloc] initWithTitle:@"Mặc định của CLI" action:nil keyEquivalent:@""];
    own.representedObject = AIAgentEffortProgramDefault;
    own.toolTip = [AIAgentCLI speedNoteForEffort:nil];
    [_aiEffort.menu addItem:own];
    NSString* saved = [AISettings effortForProvider:provider];
    NSInteger index = saved.length > 0 ? [_aiEffort indexOfItemWithRepresentedObject:saved] : 0;
    [_aiEffort selectItemAtIndex:MAX(index, 0)];
    NSString* summary = [cli summaryForSavedModel:[AISettings modelForProvider:provider] effort:saved models:models];
    NSString* effective = [cli effectiveEffortForSavedModel:[AISettings modelForProvider:provider] effort:saved models:models];
    [self aiShow:[NSString stringWithFormat:@"Sẽ dùng: %@. %@.", summary, [AIAgentCLI speedNoteForEffort:effective]] in:_aiEffortStatus error:NO];
}

-(void)aiEffortChanged:(NSPopUpButton*)sender {
    NSString* level = sender.selectedItem.representedObject;
    if (level != nil)
        [AISettings setEffort:level forProvider:[self aiProviderInUse]];
    [self aiReloadEfforts];
}

-(void)aiChooseProgram:(id)sender {
    AIProvider* provider = [self aiProviderInUse];
    AIAgentCLI* cli = [AIAgentCLI forProvider:provider];
    if (cli == nil)
        return;
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.message = [NSString stringWithFormat:@"Chọn chương trình `%@`", cli.command];
    panel.prompt = @"Chọn";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.showsHiddenFiles = YES;                           //~/.local, ~/.nvm: where these programs usually are
    NSString* current = [AISettings executablePathForProvider:provider];
    panel.directoryURL = [NSURL fileURLWithPath:current.length > 0 ? [current stringByDeletingLastPathComponent] : NSHomeDirectory()];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil)
            return;
        NSString* path = panel.URL.path;
        if (![AIAgentCLI isRunnableFile:path]) {
            [self aiShow:@"Tệp này không chạy được (không có quyền thực thi). Hãy chọn chính chương trình." in:self->_aiProgramStatus error:YES];
            return;
        }
        [AISettings setProgram:path forProvider:provider];
        [self reloadAI];
    }];
}

-(void)aiResetProgram:(id)sender {
    [AISettings setProgram:nil forProvider:[self aiProviderInUse]];
    [self reloadAI];
}

-(void)aiShow:(NSString*)message in:(NSTextField*)label error:(BOOL)error {
    label.stringValue = message ?: @"";
    label.textColor = error ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
    label.hidden = label.stringValue.length == 0;   //an empty line would still take room under the field
}

-(void)aiProviderChanged:(NSPopUpButton*)sender {
    NSString* identifier = sender.selectedItem.representedObject;
    if (identifier.length > 0)
        AISettings.providerIdentifier = identifier;
    [self reloadAI];
}

-(void)aiOpenKeyPage:(id)sender {
    NSString* page = [self aiProviderInUse].keyPageURL;
    if (page.length > 0)
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:page]];
}

//What is typed in the fields. The key field enables its button as soon as something is in it; the others are saved when the
//user is done with them.
-(void)controlTextDidChange:(NSNotification*)notification {
    if (notification.object == _aiKey)
        _aiSaveKey.enabled = _aiKey.stringValue.length > 0;
}

-(void)controlTextDidEndEditing:(NSNotification*)notification {
    id field = notification.object;
    if (field == _aiURL)
        [self aiCommitURL];
    else if (field == _aiModel)
        [self aiCommitModel];
    else if (field == _aiPrompt)
        AISettings.systemPrompt = _aiPrompt.stringValue;
    else if (field == _aiImagePrompt)
        AISettings.imagePrompt = _aiImagePrompt.stringValue;
    else if (field == _aiKey && _aiKey.stringValue.length > 0 && [notification.userInfo[@"NSTextMovement"] integerValue] == NSReturnTextMovement)
        [self aiSaveKey:nil];
}

-(void)comboBoxSelectionDidChange:(NSNotification*)notification {
    //the text of the box is not updated yet when this is called
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger index = self->_aiModel.indexOfSelectedItem;
        if (index >= 0)
            self->_aiModel.stringValue = [self->_aiModel itemObjectValueAtIndex:index];
        [self aiCommitModel];
    });
}

-(BOOL)aiCommitURL {
    AIProvider* provider = [self aiProviderInUse];
    NSString* typed = _aiURL.stringValue;
    if (typed.length == 0 && provider.defaultBaseURL.length == 0) {
        [AISettings setBaseURL:@"" forProvider:provider];
        [self aiShow:@"Chưa nhập địa chỉ máy chủ." in:_aiURLStatus error:YES];
        return NO;
    }
    if (typed.length == 0) {
        [AISettings setBaseURL:@"" forProvider:provider];       //back to the address of the service
        _aiURL.stringValue = provider.defaultBaseURL;
        [self aiShow:@"" in:_aiURLStatus error:NO];
        return YES;
    }
    NSString* reason = nil;
    NSString* clean = VOKAICleanBaseURL(typed, &reason);
    if (clean == nil) {
        [self aiShow:reason in:_aiURLStatus error:YES];          //not saved: the one that works stays
        return NO;
    }
    [AISettings setBaseURL:clean forProvider:provider];
    _aiURL.stringValue = clean;
    [self aiShow:@"" in:_aiURLStatus error:NO];
    return YES;
}

-(void)aiCommitModel {
    [AISettings setModel:_aiModel.stringValue forProvider:[self aiProviderInUse]];
    if ([AIAgentCLI forProvider:[self aiProviderInUse]] != nil)
        [self aiReloadEfforts];                             //another model has other levels
}

-(void)aiSaveKey:(id)sender {
    AIProvider* provider = [self aiProviderInUse];
    NSString* reason = nil;
    NSString* key = VOKAICleanKey(_aiKey.stringValue, &reason);
    if (key == nil) {
        [self aiShow:reason in:_aiKeyStatus error:YES];
        return;
    }
    NSError* error = nil;
    if (![AIKeychain setKey:key forProvider:provider.identifier error:&error]) {
        [self aiShow:error.localizedDescription in:_aiKeyStatus error:YES];
        return;
    }
    [self reloadAI];                                              //the field is emptied: the key is not shown again
    [self aiShow:@"Đã lưu vào Keychain của tài khoản macOS này." in:_aiKeyStatus error:NO];
}

-(void)aiRemoveKey:(id)sender {
    AIProvider* provider = [self aiProviderInUse];
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Xóa API key của %@?", provider.name];
    alert.informativeText = @"Key bị xóa khỏi Keychain. Bạn cần nhập lại nếu muốn dùng dịch vụ này.";
    [alert addButtonWithTitle:@"Hủy"];
    [alert addButtonWithTitle:@"Xóa"].hasDestructiveAction = YES;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse code) {
        if (code != NSAlertSecondButtonReturn)
            return;
        [AIKeychain removeKeyForProvider:provider.identifier];
        [self reloadAI];
        [self aiShow:@"Đã xóa key." in:self->_aiKeyStatus error:NO];
    }];
}

-(void)aiResetImagePrompt:(id)sender {
    AISettings.imagePrompt = nil;
    _aiImagePrompt.stringValue = AISettings.imagePrompt;
}

-(void)aiResetPrompt:(id)sender {
    AISettings.systemPrompt = nil;
    _aiPrompt.stringValue = AISettings.systemPrompt;
}

-(void)aiListModels:(id)sender {
    AIProvider* provider = [self aiProviderInUse];
    if (!provider.isAgentCLI && ![self aiCommitURL])
        return;
    NSError* error = nil;
    AIConfiguration* configuration = [AISettings configurationForListingModelsOfProvider:provider error:&error];
    if (configuration == nil) {
        [self aiShow:error.localizedDescription in:_aiModelStatus error:YES];
        return;
    }
    [self aiShow:@"Đang tải danh sách…" in:_aiModelStatus error:NO];
    [AIClient listModelsForConfiguration:configuration completion:^(NSArray<NSString*>* models, NSError* failure) {
        if (provider != [self aiProviderInUse])
            return;                                               //the user went to another service meanwhile
        if (failure != nil) {
            [self aiShow:failure.localizedDescription in:self->_aiModelStatus error:YES];
            return;
        }
        [self->_aiModel removeAllItems];
        [self->_aiModel addItemsWithObjectValues:models];
        [self aiShow:[NSString stringWithFormat:@"Tìm thấy %lu model. Bấm vào mũi tên ở ô model để chọn.", (unsigned long)models.count] in:self->_aiModelStatus error:NO];
        if (provider.isAgentCLI)
            [self aiReloadEfforts];                         //the levels come with the models
    }];
}

//a real request, the smallest one: it tells at once whether the address, the key and the model work together
-(void)aiTest:(id)sender {
    AIProvider* provider = [self aiProviderInUse];
    if (!provider.isAgentCLI && ![self aiCommitURL])
        return;
    [self aiCommitModel];
    NSError* error = nil;
    AIConfiguration* configuration = [AISettings configurationForProvider:provider error:&error];
    if (configuration == nil) {
        [self aiShow:error.localizedDescription in:_aiTestStatus error:YES];
        return;
    }
    configuration.systemPrompt = @"Reply with the single word OK.";
    _aiTestButton.enabled = NO;
    [self aiShow:@"Đang kiểm tra…" in:_aiTestStatus error:NO];
    AIClient* client = [[AIClient alloc] initWithConfiguration:configuration];
    _aiTestClient = client;
    __block NSMutableString* answer = [NSMutableString string];
    [client generateWithPrompt:@"Say OK" onText:^(NSString* piece) { [answer appendString:piece]; }
                    completion:^(NSError* failure) {
        self->_aiTestClient = nil;
        self->_aiTestButton.enabled = YES;
        if (failure != nil) {
            [self aiShow:failure.localizedDescription in:self->_aiTestStatus error:YES];
            return;
        }
        NSString* shown = answer.length > 40 ? [[answer substringToIndex:40] stringByAppendingString:@"…"] : answer;
        [self aiShow:[NSString stringWithFormat:@"Kết nối tốt. %@ trả lời: “%@”.", provider.name, [shown stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]
                  in:self->_aiTestStatus error:NO];
    }];
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
    SettingsToggle* tempOff = [SettingsToggle title:@"Tạm tắt VOpenKey AI bằng phím ⌘" detail:@"Bấm ⌘ để tạm ngừng cho tới khi bạn gõ một từ mới."
                                                key:@"vTempOffOpenKey" variable:&vTempOffOpenKey];
    NSMutableArray* rows = [NSMutableArray array];
    for (SettingsToggle* toggle in @[smart, remember, otherLanguage, tempOff])
        [rows addObject:[self rowForToggle:toggle]];
    NSButton* list = [NSButton buttonWithTitle:@"Xem danh sách…" target:self action:@selector(openRememberedApps:)];
    [rows addObject:[self buttonRowWithTitle:@"Ứng dụng đã ghi nhớ" detail:@"Xem và sửa chế độ gõ, bảng mã VOpenKey AI đã nhớ cho từng ứng dụng." button:list]];
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
    SettingsToggle* showSettings = [SettingsToggle title:@"Mở cài đặt khi khởi động" detail:@"Hiện cửa sổ này mỗi khi chạy VOpenKey AI."
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
    SettingsToggle* checkOnStart = [SettingsToggle title:@"Tự động kiểm tra bản mới" detail:@"Khi khởi động, rồi vài giờ một lần."
                                                     key:@"DontCheckUpdate" variable:NULL];
    checkOnStart.inverted = YES;
    SettingsToggle* autoInstall = [SettingsToggle title:@"Tự động tải và cài bản mới" detail:@"Bản mới tải ngầm; cài khi bạn khởi động lại."
                                                    key:@"AutoInstallUpdates" variable:NULL];
    autoInstall.parent = checkOnStart;
    NSMutableArray* rows = [NSMutableArray arrayWithObjects:[self rowForToggle:checkOnStart], [self rowForToggle:autoInstall], nil];

    NSString* version = [NSString stringWithFormat:@"Phiên bản %@ (%@)",
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
    _checkUpdateButton = [NSButton buttonWithTitle:@"Kiểm tra bản mới…" target:self action:@selector(checkForUpdate:)];
    [rows addObject:[self buttonRowWithTitle:VOK_APP_NAME detail:version button:_checkUpdateButton]];
    //the button follows the update: checking, downloading, ready (a check can be made by the app itself)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateCheckButton) name:AppUpdaterDidChangeNotification object:nil];
    [self updateCheckButton];
    [rows addObject:[self buttonRowWithTitle:@"Giới thiệu" detail:[NSString stringWithFormat:@"Phát triển bởi %@, fork từ OpenKey.", VOK_COMPANY]
                                      button:[NSButton buttonWithTitle:[NSString stringWithFormat:@"Giới thiệu %@", VOK_APP_NAME] target:self action:@selector(openAbout:)]]];
    [rows addObject:[self buttonRowWithTitle:@"Khôi phục mặc định" detail:@"Đưa mọi tùy chọn về như lúc mới cài."
                                      button:[NSButton buttonWithTitle:@"Khôi phục…" target:self action:@selector(resetToDefaults:)]]];
    return [self sectionWithTitle:@"Về VOpenKey AI" rows:rows];
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
    _snippetRecorder.value = vSnippetHotKey;
    _restoreRecorder.value = vRestoreHotKey;
    _aiRecorder.value = vAIHotKey;
    _caseRecorder.value = vCaseBarHotKey;
    [self reloadAI];

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
    alert.informativeText = @"VOpenKey AI sẽ quên mọi từ và cụm từ đã học từ cách gõ của bạn. Từ điển có sẵn không bị ảnh hưởng.";
    //the safe choice is the default one, the destructive one is in red
    [alert addButtonWithTitle:@"Hủy"];
    [alert addButtonWithTitle:@"Xóa"].hasDestructiveAction = YES;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertSecondButtonReturn)
            [SuggestionController forgetLearnedWords];
    }];
}

-(void)openSnippetEditor:(id)sender {
    [SnippetEditorController show];
}

-(void)restoreSnippets:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Khôi phục snippet mẫu?";
    alert.informativeText = @"Các snippet mẫu đã xóa sẽ quay lại và các snippet mẫu bạn đã sửa sẽ trở về nội dung gốc. Snippet do bạn tạo không bị ảnh hưởng.";
    [alert addButtonWithTitle:@"Hủy"];
    [alert addButtonWithTitle:@"Khôi phục"].hasDestructiveAction = YES;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertSecondButtonReturn)
            [[SnippetStore shared] restoreDefaults];
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

-(void)updateCheckButton {
    AppUpdater* updater = [AppUpdater shared];
    BOOL enabled = YES;
    NSString* title = @"Kiểm tra bản mới…";
    switch (updater.state) {
        case AppUpdaterStateChecking:
            title = @"Đang kiểm tra…";
            enabled = NO;
            break;
        case AppUpdaterStateAvailable:
            title = [NSString stringWithFormat:@"Cập nhật lên %@…", updater.availableRelease.version];
            break;
        case AppUpdaterStateDownloading:
            title = updater.progress >= 0 ? [NSString stringWithFormat:@"Đang tải %d%%…", (int)(updater.progress * 100)] : @"Đang tải…";
            enabled = NO;
            break;
        case AppUpdaterStateReady:
            title = @"Khởi động lại để cập nhật";
            break;
        default:
            break;
    }
    _checkUpdateButton.title = title;
    _checkUpdateButton.enabled = enabled;
}

-(void)checkForUpdate:(id)sender {
    switch ([AppUpdater shared].state) {
        case AppUpdaterStateReady:
            [OpenKeyManager restartToUpdate:self.window];
            break;
        case AppUpdaterStateAvailable:
            [OpenKeyManager showUpdateDialog:self.window];
            break;
        default:
            [OpenKeyManager checkNewVersion:self.window];
            break;
    }
}

-(void)openAbout:(id)sender {
    [appDelegate onAboutSelected];
}

-(void)resetToDefaults:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Khôi phục cấu hình mặc định?";
    alert.informativeText = @"Mọi tùy chọn sẽ trở về như lúc mới cài. Danh sách gõ tắt, snippet và API key của bạn không bị xóa.";
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
