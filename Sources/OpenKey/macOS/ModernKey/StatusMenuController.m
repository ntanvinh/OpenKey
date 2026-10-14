//
//  StatusMenuController.m
//  VOpenKey
//

#import "StatusMenuController.h"
#import "AppDelegate.h"
#import "AppInfo.h"
#import "OpenKeyManager.h"
#import "SecureInputMonitor.h"
#import "VOKUI.h"

extern AppDelegate* appDelegate;
extern int convertToolHotKey;

//"Telex" and the like, in the order of the InputType setting
static NSArray<NSString*>* InputTypeNames(void) {
    return @[@"Telex", @"VNI", @"Simple Telex 1", @"Simple Telex 2"];
}

//the order of the CodeTable setting
static NSArray<NSString*>* CodeTableNames(void) {
    return @[@"Unicode dựng sẵn", @"TCVN3 (ABC)", @"VNI Windows", @"Unicode tổ hợp", @"Vietnamese Locale CP 1258"];
}

//Shows a global shortcut (modifier bits 0x100 ⌃, 0x200 ⌥, 0x400 ⌘, 0x800 ⇧ and the character in the top byte)
//on the right of a menu item the way macOS shows shortcuts.
static void ApplyShortcut(NSMenuItem* item, int data) {
    NSEventModifierFlags modifiers = 0;
    if (data & 0x100) modifiers |= NSEventModifierFlagControl;
    if (data & 0x200) modifiers |= NSEventModifierFlagOption;
    if (data & 0x400) modifiers |= NSEventModifierFlagCommand;
    if (data & 0x800) modifiers |= NSEventModifierFlagShift;
    unsigned key = ((unsigned)data >> 24) & 0xFF;
    //0xFE: no key, the shortcut is made of modifiers only, which a menu cannot show
    if (key == 0xFE || key == 0 || modifiers == 0) {
        item.keyEquivalent = @"";
        item.keyEquivalentModifierMask = 0;
        return;
    }
    item.keyEquivalent = [[NSString stringWithFormat:@"%c", key] lowercaseString];
    item.keyEquivalentModifierMask = modifiers;
}

//The checkmark of the selected language sits at the trailing edge of the menu, in the column where the other rows have
//their arrows and shortcuts, while the rows keep the native size and spacing of AppKit.
//A menu is as wide as its widest row. Putting the right tab stop wider than every other row makes these two the
//widest ones, so the stop is the trailing edge of the menu whatever the other rows hold or the system font is
//(a smaller number leaves the checkmark floating in the middle of a wider menu). The text starts after the flag.
static const CGFloat kLanguageRowTextWidth = 262;

static NSAttributedString* LanguageMenuTitle(NSString* title, BOOL selected) {
    NSString* value = [title stringByAppendingFormat:@"\t%@", selected ? @"✓" : @""];
    NSMutableParagraphStyle* paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentLeft;
    paragraphStyle.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentRight
                                                                 location:kLanguageRowTextWidth
                                                                  options:@{}]];
    return [[NSAttributedString alloc] initWithString:value attributes:@{
        NSParagraphStyleAttributeName: paragraphStyle
    }];
}

//A small gray heading over a group of items, like the ones macOS uses (14 and later have a real one)
static NSMenuItem* MakeHeader(NSString* title) {
    if (@available(macOS 14.0, *))
        return [NSMenuItem sectionHeaderWithTitle:title];
    NSMenuItem* header = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    header.enabled = NO;
    header.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}];
    return header;
}

static NSMenuItem* MakeItem(NSString* title, NSString* symbol, id target, SEL action) {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = target;
    if (symbol != nil)
        item.image = VOKSymbol(symbol, 13, NSFontWeightRegular);
    return item;
}

@implementation StatusMenuController {
    NSStatusItem* _statusItem;
    NSMenu* _menu;

    NSMenuItem* _permissionItem;
    NSMenuItem* _secureItem;
    NSMenuItem* _noticeSeparator;

    NSMenuItem* _vietnameseItem;
    NSMenuItem* _englishItem;
    NSMenuItem* _inputTypeParent;
    NSMenuItem* _codeTableParent;
    NSArray<NSMenuItem*>* _inputTypeItems;
    NSArray<NSMenuItem*>* _codeTableItems;
    NSMenuItem* _quickConvertItem;
}

-(instancetype)init {
    self = [super init];
    if (self) {
        _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
        [self buildMenu];
        _statusItem.menu = _menu;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
                                                     name:SecureInputMonitorDidChangeNotification object:nil];
        [self refresh];
    }
    return self;
}

-(NSMenu*)submenuWithNames:(NSArray<NSString*>*)names action:(SEL)action items:(NSArray<NSMenuItem*>**)items {
    NSMenu* submenu = [[NSMenu alloc] initWithTitle:@""];
    submenu.autoenablesItems = NO;
    NSMutableArray* created = [NSMutableArray array];
    for (NSUInteger i = 0; i < names.count; i++) {
        NSMenuItem* item = MakeItem(names[i], nil, self, action);
        item.tag = i;
        [submenu addItem:item];
        [created addObject:item];
    }
    *items = created;
    return submenu;
}

-(void)buildMenu {
    _menu = [[NSMenu alloc] initWithTitle:VOK_APP_NAME];
    _menu.autoenablesItems = NO;
    _menu.delegate = self;

    //notices, only there when there is something to tell
    _permissionItem = MakeItem(@"Cấp quyền để VOpenKey hoạt động…", @"exclamationmark.shield", self, @selector(askPermissions:));
    _secureItem = MakeItem(@"Secure Input đang bật", @"exclamationmark.triangle", nil, nil);
    _secureItem.enabled = NO;
    _noticeSeparator = [NSMenuItem separatorItem];
    [_menu addItem:_permissionItem];
    [_menu addItem:_secureItem];
    [_menu addItem:_noticeSeparator];

    //Typing language, with the flag at the leading edge and the selected checkmark trailing.
    _vietnameseItem = MakeItem(@"Tiếng Việt", nil, self, @selector(selectVietnamese:));
    _vietnameseItem.image = VOKFlagImage(@"vn");
    _englishItem = MakeItem(@"English", nil, self, @selector(selectEnglish:));
    _englishItem.image = VOKFlagImage(@"us");
    [_menu addItem:MakeHeader(@"Chế độ gõ")];
    [_menu addItem:_vietnameseItem];
    [_menu addItem:_englishItem];
    [_menu addItem:[NSMenuItem separatorItem]];

    _inputTypeParent = MakeItem(@"Kiểu gõ", @"keyboard", nil, nil);
    NSArray<NSMenuItem*>* items = nil;
    [_menu addItem:_inputTypeParent];
    [_menu setSubmenu:[self submenuWithNames:InputTypeNames() action:@selector(selectInputType:) items:&items] forItem:_inputTypeParent];
    _inputTypeItems = items;

    _codeTableParent = MakeItem(@"Bảng mã", @"textformat", nil, nil);
    [_menu addItem:_codeTableParent];
    [_menu setSubmenu:[self submenuWithNames:CodeTableNames() action:@selector(selectCodeTable:) items:&items] forItem:_codeTableParent];
    _codeTableItems = items;
    [_menu addItem:[NSMenuItem separatorItem]];

    [_menu addItem:MakeItem(@"Công cụ chuyển mã…", @"arrow.left.arrow.right", self, @selector(openConvertTool:))];
    _quickConvertItem = MakeItem(@"Chuyển mã nhanh", @"doc.on.clipboard", self, @selector(quickConvert:));
    [_menu addItem:_quickConvertItem];
    [_menu addItem:MakeItem(@"Gõ tắt…", @"text.badge.plus", self, @selector(openMacro:))];
    [_menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* settings = MakeItem(@"Cài đặt…", @"gearshape", self, @selector(openSettings:));
    settings.keyEquivalent = @",";
    [_menu addItem:settings];
    [_menu addItem:MakeItem([NSString stringWithFormat:@"Giới thiệu %@", VOK_APP_NAME], @"info.circle", self, @selector(openAbout:))];
    [_menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* quit = MakeItem([NSString stringWithFormat:@"Thoát %@", VOK_APP_NAME], @"power", NSApp, @selector(terminate:));
    quit.keyEquivalent = @"q";
    [_menu addItem:quit];
}

#pragma mark - State

//While secure input is on macOS hides every key from the app, so the icon shows English until it is released
//(unless macOS' own Vietnamese input source is typing in the app's place). Only the icon changes, not the saved
//language: that would also teach Smart Switch Key that the app holding secure input is an English app.
-(void)refresh {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSInteger language = [defaults integerForKey:@"InputMethod"];
    NSInteger inputType = [defaults integerForKey:@"InputType"];
    NSInteger codeTable = [defaults integerForKey:@"CodeTable"];
    BOOL grayIcon = [defaults integerForKey:@"GrayIcon"] != 0;

    BOOL vietnamese = language == 1 && ![SecureInputMonitor isOpenKeyBlind];
    NSImage* image = [NSImage imageNamed:vietnamese ? @"Status" : @"StatusEng"];
    [image setTemplate:grayIcon];
    _statusItem.button.image = image;
    _statusItem.button.alternateImage = [NSImage imageNamed:vietnamese ? @"StatusHighlighted" : @"StatusHighlightedEng"];
    _statusItem.button.toolTip = [SecureInputMonitor statusDescription];

    //Language switching is available through the app-wide shortcut, but the
    //menu uses its trailing checkmark to show the current selection.
    _vietnameseItem.attributedTitle = LanguageMenuTitle(@"Tiếng Việt", language == 1);
    _englishItem.attributedTitle = LanguageMenuTitle(@"English", language != 1);

    for (NSMenuItem* item in _inputTypeItems)
        item.state = item.tag == inputType ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSMenuItem* item in _codeTableItems)
        item.state = item.tag == codeTable ? NSControlStateValueOn : NSControlStateValueOff;
    if (@available(macOS 14.4, *)) {
        //what is selected, written under the name of the submenu
        _inputTypeParent.subtitle = inputType >= 0 && inputType < (NSInteger)InputTypeNames().count ? InputTypeNames()[inputType] : nil;
        _codeTableParent.subtitle = codeTable >= 0 && codeTable < (NSInteger)CodeTableNames().count ? CodeTableNames()[codeTable] : nil;
    }

    ApplyShortcut(_quickConvertItem, convertToolHotKey);

    BOOL needsPermission = ![OpenKeyManager isInited];
    NSString* secureDescription = [SecureInputMonitor statusDescription];
    _permissionItem.hidden = !needsPermission;
    _secureItem.hidden = secureDescription == nil;
    _noticeSeparator.hidden = !needsPermission && secureDescription == nil;
    if (secureDescription != nil) {
        NSString* holder = [SecureInputMonitor holderName];
        _secureItem.title = holder != nil ? [NSString stringWithFormat:@"Secure Input đang bật bởi %@", holder] : @"Secure Input đang bật";
        _secureItem.toolTip = secureDescription;
        if (@available(macOS 14.4, *)) {
            _secureItem.subtitle = [SecureInputMonitor isFallbackActive] ? @"Đang dùng bộ gõ Vietnamese của macOS" : @"Tạm chuyển sang tiếng Anh";
        }
    }
}

-(void)menuNeedsUpdate:(NSMenu*)menu {
    [self refresh];
}

#pragma mark - Actions

-(void)selectLanguage:(NSInteger)language {
    //the app toggles the language, so only call it when the choice is a change
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"] != language)
        [appDelegate onInputMethodSelected];
}

-(void)selectVietnamese:(id)sender {
    [self selectLanguage:1];
}

-(void)selectEnglish:(id)sender {
    [self selectLanguage:0];
}

-(void)selectInputType:(NSMenuItem*)sender {
    [appDelegate onInputTypeSelectedIndex:(int)sender.tag];
}

-(void)selectCodeTable:(NSMenuItem*)sender {
    [appDelegate onCodeTableChanged:(int)sender.tag];
}

-(void)openConvertTool:(id)sender {
    [appDelegate onConvertTool];
}

-(void)quickConvert:(id)sender {
    [appDelegate onQuickConvert];
}

-(void)openMacro:(id)sender {
    [appDelegate onMacroSelected];
}

-(void)openSettings:(id)sender {
    [appDelegate onControlPanelSelected];
}

-(void)openAbout:(id)sender {
    [appDelegate onAboutSelected];
}

-(void)askPermissions:(id)sender {
    [appDelegate showPermissionWindow];
}

@end
