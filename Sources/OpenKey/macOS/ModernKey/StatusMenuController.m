//
//  StatusMenuController.m
//  VOpenKey
//

#import "StatusMenuController.h"
#import "AppDelegate.h"
#import "AIAssistant.h"
#import "AISettings.h"
#import "AppInfo.h"
#import "AppUpdater.h"
#import "CaseBar.h"
#import "Donation.h"
#import "OpenKeyManager.h"
#import "SecureInputMonitor.h"
#import "ShortcutRecorder.h"
#import "SnippetPalette.h"
#import "SuggestionController.h"
#import "VOKUI.h"

extern AppDelegate* appDelegate;

//"Telex" and the like, in the order of the InputType setting
static NSArray<NSString*>* InputTypeNames(void) {
    return @[@"Telex", @"VNI", @"Simple Telex 1", @"Simple Telex 2"];
}

//the order of the CodeTable setting
static NSArray<NSString*>* CodeTableNames(void) {
    return @[@"Unicode dựng sẵn", @"TCVN3 (ABC)", @"VNI Windows", @"Unicode tổ hợp", @"Vietnamese Locale CP 1258"];
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
    NSMenuItem* _updateItem;
    NSMenuItem* _noticeSeparator;

    NSMenuItem* _vietnameseItem;
    NSMenuItem* _englishItem;
    NSMenuItem* _inputTypeParent;
    NSMenuItem* _codeTableParent;
    NSMenuItem* _suggestionItem;
    NSMenuItem* _snippetItem;
    NSMenuItem* _aiItem;
    NSMenuItem* _caseItem;
    NSMenuItem* _donateItem;
    NSArray<NSMenuItem*>* _inputTypeItems;
    NSArray<NSMenuItem*>* _codeTableItems;
}

-(instancetype)init {
    self = [super init];
    if (self) {
        _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
        [self buildMenu];
        _statusItem.menu = _menu;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
                                                     name:SecureInputMonitorDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
                                                     name:AppUpdaterDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
                                                     name:DonationDidChangeNotification object:nil];
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
    _permissionItem = MakeItem(@"Cấp quyền để VOpenKey AI hoạt động…", @"exclamationmark.shield", self, @selector(askPermissions:));
    _secureItem = MakeItem(@"Secure Input đang bật", @"exclamationmark.triangle", nil, nil);
    _secureItem.enabled = NO;
    _updateItem = MakeItem(@"", @"arrow.down.circle", self, @selector(updateAction:));
    _noticeSeparator = [NSMenuItem separatorItem];
    [_menu addItem:_permissionItem];
    [_menu addItem:_secureItem];
    [_menu addItem:_updateItem];
    [_menu addItem:_noticeSeparator];

    //Typing language, with the native checkmark in the leading state column.
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

    _suggestionItem = MakeItem(@"Thanh gợi ý khi gõ", @"text.magnifyingglass", self, @selector(toggleSuggestion:));
    [_menu addItem:_suggestionItem];
    _snippetItem = MakeItem(@"Snippet…", @"text.insert", self, @selector(openSnippets:));
    [_menu addItem:_snippetItem];
    _aiItem = MakeItem(@"Trợ lý AI…", @"sparkles", self, @selector(openAI:));
    [_menu addItem:_aiItem];
    _caseItem = MakeItem(@"Đổi chữ hoa/thường…", @"textformat.abc", self, @selector(openCaseBar:));
    [_menu addItem:_caseItem];
    [_menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* settings = MakeItem(@"Cài đặt…", @"gearshape", self, @selector(openSettings:));
    settings.keyEquivalent = @",";
    [_menu addItem:settings];
    [_menu addItem:MakeItem([NSString stringWithFormat:@"Giới thiệu %@", VOK_APP_NAME], @"info.circle", self, @selector(openAbout:))];
    //goes away once the user says they donated (it stays in Settings)
    _donateItem = MakeItem([NSString stringWithFormat:@"Ủng hộ %@", VOK_APP_NAME], @"heart", self, @selector(openDonate:));
    [_menu addItem:_donateItem];
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

    //Language switching is available through the app-wide shortcut; show the selection like other menu toggles.
    _vietnameseItem.state = language == 1 ? NSControlStateValueOn : NSControlStateValueOff;
    _englishItem.state = language != 1 ? NSControlStateValueOn : NSControlStateValueOff;

    for (NSMenuItem* item in _inputTypeItems)
        item.state = item.tag == inputType ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSMenuItem* item in _codeTableItems)
        item.state = item.tag == codeTable ? NSControlStateValueOn : NSControlStateValueOff;
    _suggestionItem.state = vSuggestEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _donateItem.hidden = Donation.acknowledged;
    //the shortcut is written at the right of the item; the event tap handles the keys, the menu only shows them
    BOOL snippetShortcut = vSnippetsEnabled && !VOKShortcutIsEmpty(vSnippetHotKey);
    _snippetItem.keyEquivalent = snippetShortcut ? VOKShortcutKeyEquivalent(vSnippetHotKey) : @"";
    _snippetItem.keyEquivalentModifierMask = snippetShortcut ? VOKShortcutModifierMask(vSnippetHotKey) : 0;
    BOOL aiShortcut = vAIEnabled && !VOKShortcutIsEmpty(vAIHotKey);
    _aiItem.keyEquivalent = aiShortcut ? VOKShortcutKeyEquivalent(vAIHotKey) : @"";
    _aiItem.keyEquivalentModifierMask = aiShortcut ? VOKShortcutModifierMask(vAIHotKey) : 0;
    BOOL caseShortcut = !VOKShortcutIsEmpty(vCaseBarHotKey);
    _caseItem.keyEquivalent = caseShortcut ? VOKShortcutKeyEquivalent(vCaseBarHotKey) : @"";
    _caseItem.keyEquivalentModifierMask = caseShortcut ? VOKShortcutModifierMask(vCaseBarHotKey) : 0;
    if (@available(macOS 14.4, *)) {
        //what is selected, written under the name of the submenu
        _inputTypeParent.subtitle = inputType >= 0 && inputType < (NSInteger)InputTypeNames().count ? InputTypeNames()[inputType] : nil;
        _codeTableParent.subtitle = codeTable >= 0 && codeTable < (NSInteger)CodeTableNames().count ? CodeTableNames()[codeTable] : nil;
    }

    BOOL needsPermission = ![OpenKeyManager isInited];
    NSString* secureDescription = [SecureInputMonitor statusDescription];
    [self refreshUpdateItem];
    _permissionItem.hidden = !needsPermission;
    _secureItem.hidden = secureDescription == nil;
    _noticeSeparator.hidden = !needsPermission && secureDescription == nil && _updateItem.hidden;
    if (secureDescription != nil) {
        NSString* holder = [SecureInputMonitor holderName];
        _secureItem.title = holder != nil ? [NSString stringWithFormat:@"Secure Input đang bật bởi %@", holder] : @"Secure Input đang bật";
        _secureItem.toolTip = secureDescription;
        if (@available(macOS 14.4, *)) {
            _secureItem.subtitle = [SecureInputMonitor isFallbackActive] ? @"Đang dùng bộ gõ Vietnamese của macOS" : @"Tạm chuyển sang tiếng Anh";
        }
    }
}

//A new version: shown while there is one to install, being downloaded, or waiting for the restart
-(void)refreshUpdateItem {
    AppUpdater* updater = [AppUpdater shared];
    NSString* version = updater.availableRelease.version;
    _updateItem.hidden = NO;
    _updateItem.enabled = YES;
    switch (updater.state) {
        case AppUpdaterStateAvailable:
            _updateItem.title = [NSString stringWithFormat:@"Cập nhật lên %@…", version];
            _updateItem.image = VOKSymbol(@"arrow.down.circle", 13, NSFontWeightRegular);
            break;
        case AppUpdaterStateDownloading:
            _updateItem.title = updater.progress >= 0 ? [NSString stringWithFormat:@"Đang tải bản %@… %d%%", version, (int)(updater.progress * 100)]
                                                      : [NSString stringWithFormat:@"Đang tải bản %@…", version];
            _updateItem.image = VOKSymbol(@"arrow.down.circle", 13, NSFontWeightRegular);
            _updateItem.enabled = NO;
            break;
        case AppUpdaterStateReady:
            _updateItem.title = [NSString stringWithFormat:@"Khởi động lại để cập nhật lên %@", version];
            _updateItem.image = VOKSymbol(@"arrow.triangle.2.circlepath", 13, NSFontWeightRegular);
            break;
        default:
            _updateItem.hidden = YES;
            break;
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

-(void)toggleSuggestion:(id)sender {
    vSuggestEnabled = !vSuggestEnabled;
    [[NSUserDefaults standardUserDefaults] setInteger:vSuggestEnabled forKey:@"SuggestionEnabled"];
    [SuggestionController reloadSettings];
    [self refresh];
}

-(void)openSnippets:(id)sender {
    [SnippetPalette show];
}

-(void)openAI:(id)sender {
    [AIAssistant show];
}

-(void)openCaseBar:(id)sender {
    [CaseBar show];
}

-(void)openSettings:(id)sender {
    [appDelegate onControlPanelSelected];
}

-(void)openDonate:(id)sender {
    [appDelegate onDonateSelected];
}

-(void)openAbout:(id)sender {
    [appDelegate onAboutSelected];
}

-(void)updateAction:(id)sender {
    if ([AppUpdater shared].state == AppUpdaterStateReady)
        [OpenKeyManager restartToUpdate:nil];
    else
        [OpenKeyManager showUpdateDialog:nil];
}

-(void)askPermissions:(id)sender {
    [appDelegate showPermissionWindow];
}

@end
