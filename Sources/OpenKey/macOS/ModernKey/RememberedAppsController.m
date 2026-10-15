//
//  RememberedAppsController.m
//  VOpenKey
//

#import "RememberedAppsController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "OpenKeyManager.h"
#import "VOKUI.h"

//the engine's copy of what is selected now
extern int vLanguage;
extern int vCodeTable;

//what the engine remembers, see OpenKey.mm
extern NSArray<NSDictionary*>* RememberedApps(void);
extern void SetRememberedApp(NSString* bundleId, int value);
extern void ForgetRememberedApp(NSString* bundleId);

static const CGFloat kSheetWidth = 580;
static const CGFloat kMargin = 24;
static const CGFloat kRowHeight = 36;
static const CGFloat kTableHeight = 280;

static NSString* const kAppColumn = @"app";
static NSString* const kLanguageColumn = @"language";
static NSString* const kCodeColumn = @"code";

//A row of the list: the application, and the two things remembered for it
@interface RememberedApp : NSObject
@property (copy) NSString* identifier;
@property (copy) NSString* name;
@property (strong) NSImage* icon;
@property BOOL installed;
@property int value; //language | (code table << 1)
@end

@implementation RememberedApp
-(int)language { return self.value & 1; }
-(int)codeTable { return self.value >> 1; }
@end

@interface RememberedAppsController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation RememberedAppsController {
    NSWindow* _sheet;
    NSWindow* _parent;
    NSTableView* _table;
    NSTextField* _empty;
    NSSearchField* _searchField;
    NSPopUpButton* _languageFilter;
    NSSegmentedControl* _plusMinus;
    NSMutableArray<RememberedApp*>* _apps;
    NSArray<RememberedApp*>* _visibleApps;
}

static RememberedAppsController* current; //alive while the sheet is up

+(void)presentFromWindow:(NSWindow*)parent {
    current = [[RememberedAppsController alloc] init];
    [current presentFromWindow:parent];
}

#pragma mark - Data

-(RememberedApp*)appForIdentifier:(NSString*)identifier value:(int)value {
    RememberedApp* app = [[RememberedApp alloc] init];
    app.identifier = identifier;
    app.value = value;
    NSWorkspace* workspace = [NSWorkspace sharedWorkspace];
    NSURL* url = [workspace URLForApplicationWithBundleIdentifier:identifier];
    if (url != nil) {
        app.installed = YES;
        NSString* name = [[NSFileManager defaultManager] displayNameAtPath:url.path];
        app.name = [name hasSuffix:@".app"] ? [name substringToIndex:name.length - 4] : name;
        app.icon = [workspace iconForFile:url.path];
    } else { //removed from this Mac, or not an application (the engine keeps names that are not bundle identifiers)
        app.name = identifier;
        app.icon = [workspace iconForFileType:UTTypeApplicationBundle.identifier];
    }
    app.icon.size = NSMakeSize(22, 22);
    return app;
}

-(void)loadApps {
    NSMutableArray* apps = [NSMutableArray array];
    for (NSDictionary* item in RememberedApps())
        [apps addObject:[self appForIdentifier:item[@"id"] value:[item[@"value"] intValue]]];
    [apps sortUsingComparator:^NSComparisonResult(RememberedApp* a, RememberedApp* b) {
        if (a.installed != b.installed) //applications that are gone go last
            return a.installed ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    _apps = apps;
    [self applyFilter];
}

-(void)applyFilter {
    NSString* query = [_searchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSInteger languageFilter = _languageFilter.indexOfSelectedItem;
    NSMutableArray<RememberedApp*>* visible = [NSMutableArray array];
    for (RememberedApp* app in _apps) {
        BOOL matchesQuery = query.length == 0 ||
            [app.name localizedCaseInsensitiveContainsString:query] ||
            [app.identifier localizedCaseInsensitiveContainsString:query];
        BOOL matchesLanguage = languageFilter == 0 || app.language == languageFilter - 1;
        if (matchesQuery && matchesLanguage)
            [visible addObject:app];
    }
    _visibleApps = visible;
    [_table reloadData];
    [self refreshState];
}

-(void)refreshState {
    _empty.hidden = _visibleApps.count > 0;
    if (_apps.count == 0) {
        _empty.stringValue = @"Chưa có ứng dụng nào.\nVOpenKey AI sẽ ghi nhớ khi bạn đổi chế độ gõ hoặc bảng mã trong một ứng dụng.";
    } else {
        _empty.stringValue = @"Không tìm thấy ứng dụng phù hợp.";
    }
    [_plusMinus setEnabled:_table.selectedRowIndexes.count > 0 forSegment:1];
}

#pragma mark - The sheet

-(void)presentFromWindow:(NSWindow*)parent {
    _parent = parent;
    _sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kSheetWidth, 100)
                                         styleMask:NSWindowStyleMaskTitled
                                           backing:NSBackingStoreBuffered
                                             defer:NO];

    NSTextField* title = VOKLabel(@"Ứng dụng đã ghi nhớ", 15, NSFontWeightSemibold, nil);
    NSTextField* explanation = VOKLabel(@"VOpenKey AI tự ghi nhớ chế độ gõ và bảng mã khi bạn đổi chúng trong một ứng dụng, rồi dùng lại khi bạn quay về ứng dụng đó. Bạn cũng có thể sửa ở đây. Thay đổi được lưu ngay.",
                                        11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    explanation.preferredMaxLayoutWidth = kSheetWidth - 2 * kMargin;

    _table = [[NSTableView alloc] init];
    _table.style = NSTableViewStyleInset;
    _table.rowHeight = kRowHeight;
    _table.allowsMultipleSelection = YES;
    _table.usesAutomaticRowHeights = NO;
    _table.dataSource = self;
    _table.delegate = self;
    //the columns must add up to less than the card: what does not fit is cut off at the edge, and cannot be scrolled to
    _table.intercellSpacing = NSMakeSize(8, 0);
    [self addColumn:kAppColumn title:@"Ứng dụng" width:150 minWidth:110 resizable:YES];
    [self addColumn:kLanguageColumn title:@"Chế độ gõ" width:124 minWidth:110 resizable:NO];
    [self addColumn:kCodeColumn title:@"Bảng mã" width:176 minWidth:150 resizable:NO];
    _table.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;

    NSScrollView* scroll = [[NSScrollView alloc] init];
    scroll.documentView = _table;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    NSView* card = VOKCard(scroll);
    [card.heightAnchor constraintEqualToConstant:kTableHeight].active = YES;

    _searchField = [[NSSearchField alloc] init];
    _searchField.placeholderString = @"Tìm ứng dụng";
    _searchField.sendsSearchStringImmediately = YES;
    _searchField.target = self;
    _searchField.action = @selector(filterChanged:);
    [_searchField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    _languageFilter = [[NSPopUpButton alloc] init];
    _languageFilter.controlSize = NSControlSizeSmall;
    [_languageFilter addItemsWithTitles:@[@"Tất cả chế độ", @"English", @"Tiếng Việt"]];
    [_languageFilter selectItemAtIndex:0];
    _languageFilter.target = self;
    _languageFilter.action = @selector(filterChanged:);
    [_languageFilter setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_languageFilter setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView* filters = [NSStackView stackViewWithViews:@[_searchField, _languageFilter]];
    filters.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    filters.alignment = NSLayoutAttributeCenterY;
    filters.spacing = 12;
    filters.translatesAutoresizingMaskIntoConstraints = NO;
    [_languageFilter.widthAnchor constraintEqualToConstant:150].active = YES;

    _empty = VOKLabel(@"Chưa có ứng dụng nào.\nVOpenKey AI sẽ ghi nhớ khi bạn đổi chế độ gõ hoặc bảng mã trong một ứng dụng.",
                      12, NSFontWeightRegular, [NSColor tertiaryLabelColor]);
    _empty.alignment = NSTextAlignmentCenter;
    _empty.preferredMaxLayoutWidth = 320;
    [card addSubview:_empty];
    [NSLayoutConstraint activateConstraints:@[
        [_empty.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [_empty.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [_empty.widthAnchor constraintLessThanOrEqualToConstant:320],
    ]];

    _plusMinus = [NSSegmentedControl segmentedControlWithImages:@[VOKSymbol(@"plus", 12, NSFontWeightRegular),
                                                                  VOKSymbol(@"minus", 12, NSFontWeightRegular)]
                                                   trackingMode:NSSegmentSwitchTrackingMomentary
                                                         target:self action:@selector(addOrRemove:)];
    [_plusMinus setWidth:32 forSegment:0];
    [_plusMinus setWidth:32 forSegment:1];
    [_plusMinus setToolTip:@"Thêm ứng dụng" forSegment:0];
    [_plusMinus setToolTip:@"Bỏ ứng dụng đang chọn: VOpenKey AI sẽ ghi nhớ lại từ đầu khi bạn dùng nó" forSegment:1];

    NSButton* done = [NSButton buttonWithTitle:@"Xong" target:self action:@selector(done:)];
    done.keyEquivalent = @"\r";
    NSView* spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* bar = [NSStackView stackViewWithViews:@[_plusMinus, spacer, done]];
    bar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bar.alignment = NSLayoutAttributeCenterY;

    NSStackView* stack = [NSStackView stackViewWithViews:@[title, explanation, filters, card, bar]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    [stack setCustomSpacing:4 afterView:title];
    [stack setCustomSpacing:12 afterView:explanation];
    [stack setCustomSpacing:8 afterView:filters];
    [stack setCustomSpacing:16 afterView:card];
    stack.edgeInsets = NSEdgeInsetsMake(kMargin, kMargin, kMargin, kMargin);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card.widthAnchor constraintEqualToConstant:kSheetWidth - 2 * kMargin].active = YES;
    [filters.widthAnchor constraintEqualToConstant:kSheetWidth - 2 * kMargin].active = YES;
    [bar.widthAnchor constraintEqualToConstant:kSheetWidth - 2 * kMargin].active = YES;

    NSView* content = _sheet.contentView;
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
    [_sheet setContentSize:stack.fittingSize];
    [self loadApps];
    [_parent beginSheet:_sheet completionHandler:^(NSModalResponse response) {
        current = nil;
    }];
}

-(void)addColumn:(NSString*)identifier title:(NSString*)title width:(CGFloat)width minWidth:(CGFloat)minWidth resizable:(BOOL)resizable {
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:identifier];
    column.title = title;
    column.width = width;
    column.minWidth = minWidth;
    column.resizingMask = resizable ? NSTableColumnAutoresizingMask : NSTableColumnNoResizing;
    [_table addTableColumn:column];
}

-(void)done:(id)sender {
    [_parent endSheet:_sheet];
}

-(void)cancelOperation:(id)sender {
    [self done:sender];
}

#pragma mark - Table

-(NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    return (NSInteger)_visibleApps.count;
}

-(void)tableViewSelectionDidChange:(NSNotification*)notification {
    [self refreshState];
}

-(void)filterChanged:(id)sender {
    [self applyFilter];
}

-(NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    RememberedApp* app = _visibleApps[row];
    if ([column.identifier isEqualToString:kAppColumn]) {
        NSTableCellView* cell = [[NSTableCellView alloc] init];
        NSImageView* icon = [NSImageView imageViewWithImage:app.icon];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        NSTextField* name = [NSTextField labelWithString:app.name];
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        name.textColor = app.installed ? [NSColor labelColor] : [NSColor secondaryLabelColor];
        name.toolTip = app.identifier;
        name.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:icon];
        [cell addSubview:name];
        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
            [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:22],
            [icon.heightAnchor constraintEqualToConstant:22],
            [name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
            [name.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [name.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
        return cell;
    }

    NSPopUpButton* popup = [[NSPopUpButton alloc] init];
    popup.controlSize = NSControlSizeSmall;
    popup.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
    popup.tag = row;
    popup.target = self;
    if ([column.identifier isEqualToString:kLanguageColumn]) {
        [popup addItemsWithTitles:@[@"English", @"Tiếng Việt"]]; //the index is the language
        [popup selectItemAtIndex:app.language];
        popup.action = @selector(languageChanged:);
        popup.accessibilityLabel = [NSString stringWithFormat:@"Chế độ gõ của %@", app.name];
    } else {
        [popup addItemsWithTitles:[OpenKeyManager getTableCodes]];
        [popup selectItemAtIndex:MIN(app.codeTable, (int)popup.numberOfItems - 1)];
        popup.action = @selector(codeChanged:);
        popup.accessibilityLabel = [NSString stringWithFormat:@"Bảng mã của %@", app.name];
    }
    NSTableCellView* cell = [[NSTableCellView alloc] init];
    popup.translatesAutoresizingMaskIntoConstraints = NO;
    //as wide as its longest item, but never wider than the column: a long name is cut, not pushed out of the table
    [popup setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [cell addSubview:popup];
    [NSLayoutConstraint activateConstraints:@[
        [popup.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
        [popup.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor constant:-2],
        [popup.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    return cell;
}

-(void)languageChanged:(NSPopUpButton*)sender {
    RememberedApp* app = _visibleApps[sender.tag];
    app.value = (app.value & ~1) | (int)sender.indexOfSelectedItem;
    SetRememberedApp(app.identifier, app.value);
    [self applyFilter];
}

-(void)codeChanged:(NSPopUpButton*)sender {
    RememberedApp* app = _visibleApps[sender.tag];
    app.value = (app.value & 1) | ((int)sender.indexOfSelectedItem << 1);
    SetRememberedApp(app.identifier, app.value);
}

#pragma mark - Add and remove

-(void)addOrRemove:(NSSegmentedControl*)sender {
    if (sender.selectedSegment == 0)
        [self addApp];
    else
        [self removeSelected];
}

-(void)addApp {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.message = @"Chọn ứng dụng cần ghi nhớ";
    panel.prompt = @"Thêm";
    panel.allowedContentTypes = @[UTTypeApplicationBundle];
    panel.directoryURL = [NSURL fileURLWithPath:@"/Applications"];
    panel.allowsMultipleSelection = YES;
    [panel beginSheetModalForWindow:_sheet completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK)
            return;
        NSMutableArray<NSString*>* chosen = [NSMutableArray array];
        for (NSURL* url in panel.URLs) {
            NSString* identifier = [NSBundle bundleWithURL:url].bundleIdentifier;
            if (identifier.length == 0)
                continue;
            [chosen addObject:identifier];
            BOOL known = NO;
            for (NSDictionary* item in RememberedApps())
                known = known || [item[@"id"] isEqualToString:identifier];
            //new: what is selected now, which is what the application would have been given the first time
            if (!known)
                SetRememberedApp(identifier, (vLanguage & 1) | (vCodeTable << 1));
        }
        self->_searchField.stringValue = @"";
        [self->_languageFilter selectItemAtIndex:0];
        [self loadApps];
        NSMutableIndexSet* rows = [NSMutableIndexSet indexSet];
        for (NSUInteger i = 0; i < self->_visibleApps.count; i++) {
            if ([chosen containsObject:self->_visibleApps[i].identifier])
                [rows addIndex:i];
        }
        [self->_table selectRowIndexes:rows byExtendingSelection:NO];
        if (rows.firstIndex != NSNotFound)
            [self->_table scrollRowToVisible:(NSInteger)rows.firstIndex];
    }];
}

-(void)removeSelected {
    NSIndexSet* rows = _table.selectedRowIndexes;
    if (rows.count == 0)
        return;
    [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL* stop) {
        ForgetRememberedApp(self->_visibleApps[row].identifier);
    }];
    [self loadApps];
}

@end
