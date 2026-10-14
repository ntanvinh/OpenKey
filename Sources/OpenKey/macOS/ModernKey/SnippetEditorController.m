//
//  SnippetEditorController.m
//  VOpenKey
//

#import "SnippetEditorController.h"
#import "VOKUI.h"

static const CGFloat kListWidth = 240;
static const CGFloat kMargin = 20;
static const CGFloat kRowHeight = 44;

@interface SnippetEditorController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate,
                                       NSSearchFieldDelegate, NSWindowDelegate>
@end

@implementation SnippetEditorController {
    SnippetStore* _store;

    NSSearchField* _filter;
    NSTableView* _table;
    NSButton* _addButton;
    NSButton* _removeButton;

    NSTextField* _titleField;
    NSTextField* _keywordsField;
    NSTextView* _contentView;
    NSTextField* _hint;
    NSTextField* _emptyLabel;
    NSView* _form;

    NSArray<VOKSnippet*>* _shown;       //what the list shows: all of them, or what the filter found
    BOOL _loadingForm;                  //the fields are being filled in: that is not an edit
    BOOL _changingStore;                //the store tells us about our own changes
}

+(void)show {
    static SnippetEditorController* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[SnippetEditorController alloc] initWithStore:[SnippetStore shared]]; });
    [NSApp activateIgnoringOtherApps:YES];
    [instance.window makeKeyAndOrderFront:nil];
}

-(instancetype)initWithStore:(SnippetStore*)store {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 780, 500)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Snippet";
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(640, 380);
    self = [super initWithWindow:window];
    if (self) {
        _store = store;
        window.delegate = self;
        [self buildContent];
        [window center];
        [self reloadList];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storeDidChange:)
                                                     name:VOKSnippetsDidChangeNotification object:store];
    }
    return self;
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(NSTableView*)table { return _table; }
-(NSTextField*)titleField { return _titleField; }
-(NSTextField*)keywordsField { return _keywordsField; }
-(NSTextView*)contentView { return _contentView; }
-(NSSearchField*)filterField { return _filter; }

#pragma mark - Building the window

-(NSTextField*)captionWithText:(NSString*)text {
    NSTextField* caption = [NSTextField labelWithString:text];
    caption.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    caption.textColor = [NSColor secondaryLabelColor];
    return caption;
}

-(void)buildContent {
    NSView* content = self.window.contentView;

    //the list, with the buttons that add and remove under it
    _filter = [[NSSearchField alloc] init];
    _filter.placeholderString = @"Lọc";
    _filter.delegate = self;
    _filter.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView* listScroll = [[NSScrollView alloc] init];
    listScroll.hasVerticalScroller = YES;
    listScroll.autohidesScrollers = YES;
    listScroll.borderType = NSBezelBorder;
    listScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _table = [[NSTableView alloc] init];
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"snippet"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:column];
    _table.headerView = nil;
    _table.rowHeight = kRowHeight;
    _table.allowsEmptySelection = YES;
    _table.dataSource = self;
    _table.delegate = self;
    listScroll.documentView = _table;

    _addButton = [NSButton buttonWithImage:VOKSymbol(@"plus", 12, NSFontWeightRegular) target:self action:@selector(add:)];
    _removeButton = [NSButton buttonWithImage:VOKSymbol(@"minus", 12, NSFontWeightRegular) target:self action:@selector(remove:)];
    for (NSButton* button in @[_addButton, _removeButton]) {
        button.bezelStyle = NSBezelStyleRounded;
        button.translatesAutoresizingMaskIntoConstraints = NO;
    }
    [_addButton setAccessibilityLabel:@"Thêm snippet"];
    [_removeButton setAccessibilityLabel:@"Xóa snippet"];

    //the form
    _titleField = [NSTextField textFieldWithString:@""];
    _titleField.placeholderString = @"Ví dụ: Dịch sang tiếng Anh";
    _titleField.delegate = self;
    _keywordsField = [NSTextField textFieldWithString:@""];
    _keywordsField.placeholderString = @"Ví dụ: dich english translate";
    _keywordsField.delegate = self;
    for (NSTextField* field in @[_titleField, _keywordsField])
        field.translatesAutoresizingMaskIntoConstraints = NO;

    //the ready-made text view in a scroll view: it wraps lines at the width of the view and follows its size
    NSScrollView* contentScroll = [NSTextView scrollableTextView];
    contentScroll.hasVerticalScroller = YES;
    contentScroll.autohidesScrollers = YES;
    contentScroll.borderType = NSBezelBorder;
    contentScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _contentView = contentScroll.documentView;
    _contentView.delegate = self;
    _contentView.textContainerInset = NSMakeSize(6, 8);
    _contentView.font = [NSFont systemFontOfSize:13];
    _contentView.richText = NO;
    _contentView.allowsUndo = YES;
    //the text is typed into other applications as it is, code and prompts included: nothing may be "corrected"
    _contentView.automaticQuoteSubstitutionEnabled = NO;
    _contentView.automaticDashSubstitutionEnabled = NO;
    _contentView.automaticTextReplacementEnabled = NO;
    _contentView.automaticSpellingCorrectionEnabled = NO;
    _contentView.continuousSpellCheckingEnabled = NO;
    _contentView.grammarCheckingEnabled = NO;
    _contentView.automaticLinkDetectionEnabled = NO;
    _contentView.automaticDataDetectionEnabled = NO;

    _hint = VOKLabel(@"Trong nội dung: {clipboard} là chữ đang được sao chép, {date} là ngày hôm nay, {time} là giờ hiện tại. "
                     @"Các chữ khác trong ngoặc nhọn được giữ nguyên.", 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);

    NSTextField* titleCaption = [self captionWithText:@"Tiêu đề"];
    NSTextField* keywordsCaption = [self captionWithText:@"Từ khóa"];
    NSTextField* contentCaption = [self captionWithText:@"Nội dung"];
    _form = [[NSView alloc] init];
    _form.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView* view in @[titleCaption, _titleField, keywordsCaption, _keywordsField, contentCaption, contentScroll, _hint]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [_form addSubview:view];
    }

    _emptyLabel = [NSTextField wrappingLabelWithString:@"Chưa có snippet nào.\nBấm + để thêm snippet đầu tiên."];
    _emptyLabel.alignment = NSTextAlignmentCenter;
    _emptyLabel.textColor = [NSColor secondaryLabelColor];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;

    for (NSView* view in @[_filter, listScroll, _addButton, _removeButton, _form, _emptyLabel])
        [content addSubview:view];

    [NSLayoutConstraint activateConstraints:@[
        [_filter.topAnchor constraintEqualToAnchor:content.topAnchor constant:kMargin],
        [_filter.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:kMargin],
        [_filter.widthAnchor constraintEqualToConstant:kListWidth],

        [listScroll.topAnchor constraintEqualToAnchor:_filter.bottomAnchor constant:10],
        [listScroll.leadingAnchor constraintEqualToAnchor:_filter.leadingAnchor],
        [listScroll.widthAnchor constraintEqualToConstant:kListWidth],
        [listScroll.bottomAnchor constraintEqualToAnchor:_addButton.topAnchor constant:-10],

        [_addButton.leadingAnchor constraintEqualToAnchor:_filter.leadingAnchor],
        [_addButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-kMargin],
        [_addButton.widthAnchor constraintEqualToConstant:36],
        [_removeButton.leadingAnchor constraintEqualToAnchor:_addButton.trailingAnchor constant:6],
        [_removeButton.centerYAnchor constraintEqualToAnchor:_addButton.centerYAnchor],
        [_removeButton.widthAnchor constraintEqualToConstant:36],

        [_form.topAnchor constraintEqualToAnchor:content.topAnchor constant:kMargin],
        [_form.leadingAnchor constraintEqualToAnchor:listScroll.trailingAnchor constant:kMargin],
        [_form.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-kMargin],
        [_form.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-kMargin],

        [titleCaption.topAnchor constraintEqualToAnchor:_form.topAnchor],
        [titleCaption.leadingAnchor constraintEqualToAnchor:_form.leadingAnchor],
        [_titleField.topAnchor constraintEqualToAnchor:titleCaption.bottomAnchor constant:4],
        [_titleField.leadingAnchor constraintEqualToAnchor:_form.leadingAnchor],
        [_titleField.trailingAnchor constraintEqualToAnchor:_form.trailingAnchor],
        [keywordsCaption.topAnchor constraintEqualToAnchor:_titleField.bottomAnchor constant:14],
        [keywordsCaption.leadingAnchor constraintEqualToAnchor:_form.leadingAnchor],
        [_keywordsField.topAnchor constraintEqualToAnchor:keywordsCaption.bottomAnchor constant:4],
        [_keywordsField.leadingAnchor constraintEqualToAnchor:_form.leadingAnchor],
        [_keywordsField.trailingAnchor constraintEqualToAnchor:_form.trailingAnchor],
        [contentCaption.topAnchor constraintEqualToAnchor:_keywordsField.bottomAnchor constant:14],
        [contentCaption.leadingAnchor constraintEqualToAnchor:_form.leadingAnchor],
        [contentScroll.topAnchor constraintEqualToAnchor:contentCaption.bottomAnchor constant:4],
        [contentScroll.leadingAnchor constraintEqualToAnchor:_form.leadingAnchor],
        [contentScroll.trailingAnchor constraintEqualToAnchor:_form.trailingAnchor],
        [_hint.topAnchor constraintEqualToAnchor:contentScroll.bottomAnchor constant:10],
        [_hint.leadingAnchor constraintEqualToAnchor:_form.leadingAnchor],
        [_hint.trailingAnchor constraintEqualToAnchor:_form.trailingAnchor],
        [_hint.bottomAnchor constraintEqualToAnchor:_form.bottomAnchor],

        [_emptyLabel.centerXAnchor constraintEqualToAnchor:_form.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:_form.centerYAnchor],
        [_emptyLabel.widthAnchor constraintLessThanOrEqualToAnchor:_form.widthAnchor],
    ]];
}

#pragma mark - The list and the form

-(VOKSnippet*)selectedSnippet {
    NSInteger row = _table.selectedRow;
    return row >= 0 && row < (NSInteger)_shown.count ? _shown[row] : nil;
}

-(void)reloadList {
    VOKSnippet* selected = [self selectedSnippet];
    NSString* filter = _filter.stringValue;
    _shown = filter.length > 0 ? [_store search:filter] : _store.snippets;
    [_table reloadData];
    NSUInteger row = selected != nil ? [_shown indexOfObject:selected] : NSNotFound;
    if (row == NSNotFound && _shown.count > 0)
        row = 0;
    if (row != NSNotFound)
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self loadForm];
}

-(void)loadForm {
    VOKSnippet* snippet = [self selectedSnippet];
    _loadingForm = YES;
    _titleField.stringValue = snippet.title ?: @"";
    _keywordsField.stringValue = snippet.keywords ?: @"";
    //replacing the text through the text storage keeps the undo history of the field from going back into another snippet
    [_contentView.undoManager removeAllActions];
    _contentView.string = snippet.content ?: @"";
    _loadingForm = NO;

    BOOL has = snippet != nil;
    _titleField.enabled = has;
    _keywordsField.enabled = has;
    _contentView.editable = has;
    _removeButton.enabled = has;
    BOOL listIsEmpty = _store.snippets.count == 0;
    _form.hidden = !has && listIsEmpty;
    _emptyLabel.hidden = !listIsEmpty;
}

-(void)storeDidChange:(NSNotification*)notification {
    if (!_changingStore)
        [self reloadList];
}

#pragma mark Editing

//Writes what is in the fields into the snippet
-(void)fieldsDidChange {
    VOKSnippet* snippet = [self selectedSnippet];
    if (snippet == nil || _loadingForm)
        return;
    snippet.title = _titleField.stringValue;
    snippet.keywords = _keywordsField.stringValue;
    snippet.content = _contentView.string;
    _changingStore = YES;
    [_store snippetDidChange:snippet];
    _changingStore = NO;
    NSInteger row = _table.selectedRow;
    if (row >= 0)
        [_table reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
}

-(void)controlTextDidChange:(NSNotification*)notification {
    if (notification.object == _filter) {
        [self reloadList];
        return;
    }
    [self fieldsDidChange];
}

-(void)textDidChange:(NSNotification*)notification {
    [self fieldsDidChange];
}

-(void)windowWillClose:(NSNotification*)notification {
    [_store flush];
}

#pragma mark Buttons

-(void)addSnippet {
    _filter.stringValue = @"";
    VOKSnippet* snippet = [_store addSnippetWithTitle:@"Snippet mới" keywords:@"" content:@""];
    [self reloadList];
    NSUInteger row = [_shown indexOfObject:snippet];
    if (row != NSNotFound) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [_table scrollRowToVisible:row];
    }
    [self loadForm];
    [self.window makeFirstResponder:_titleField];
    [_titleField selectText:nil];
}

-(void)add:(id)sender {
    [self addSnippet];
}

-(void)removeSelectedSnippet {
    VOKSnippet* snippet = [self selectedSnippet];
    if (snippet == nil)
        return;
    NSInteger row = _table.selectedRow;
    [_store removeSnippet:snippet];
    [self reloadList];
    if (_shown.count > 0) {
        NSInteger next = MIN(row, (NSInteger)_shown.count - 1);
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:next] byExtendingSelection:NO];
        [self loadForm];
    }
}

-(void)remove:(id)sender {
    VOKSnippet* snippet = [self selectedSnippet];
    if (snippet == nil)
        return;
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Xóa snippet “%@”?", snippet.title.length > 0 ? snippet.title : @"chưa đặt tên"];
    alert.informativeText = snippet.isBuiltIn
        ? @"Đây là snippet mẫu. Bạn có thể lấy lại nó bằng “Khôi phục snippet mẫu” trong Cài đặt."
        : @"Không thể hoàn tác việc này.";
    //the safe choice is the default one, the destructive one is in red
    [alert addButtonWithTitle:@"Hủy"];
    [alert addButtonWithTitle:@"Xóa"].hasDestructiveAction = YES;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse code) {
        if (code == NSAlertSecondButtonReturn)
            [self removeSelectedSnippet];
    }];
}

#pragma mark Table

-(NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    return (NSInteger)_shown.count;
}

-(NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    NSTableCellView* cell = [tableView makeViewWithIdentifier:@"cell" owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, kListWidth, kRowHeight)];
        cell.identifier = @"cell";
        NSTextField* title = [NSTextField labelWithString:@""];
        title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        NSTextField* detail = [NSTextField labelWithString:@""];
        detail.font = [NSFont systemFontOfSize:11];
        detail.textColor = [NSColor secondaryLabelColor];
        detail.lineBreakMode = NSLineBreakByTruncatingTail;
        NSStackView* stack = [NSStackView stackViewWithViews:@[title, detail]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 2;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6],
            [stack.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-6],
            [stack.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
        cell.textField = title;
    }
    VOKSnippet* snippet = _shown[row];
    cell.textField.stringValue = snippet.title.length > 0 ? snippet.title : @"(Chưa đặt tên)";
    NSTextField* detail = ((NSStackView*)cell.subviews.firstObject).arrangedSubviews.lastObject;
    detail.stringValue = [self firstLineOf:snippet.content];
    return cell;
}

-(NSString*)firstLineOf:(NSString*)text {
    for (NSString* line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString* trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0)
            return trimmed;
    }
    return @"";
}

-(void)tableViewSelectionDidChange:(NSNotification*)notification {
    [self loadForm];
}

@end
