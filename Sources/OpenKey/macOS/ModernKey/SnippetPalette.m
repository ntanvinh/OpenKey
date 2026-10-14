//
//  SnippetPalette.m
//  VOpenKey
//

#import "SnippetPalette.h"
#import "SnippetEditorController.h"
#import "ShortcutRecorder.h"
#import "VOKUI.h"

int vSnippetsEnabled = 1;
int vSnippetHotKey = VOK_SNIPPET_DEFAULT_HOTKEY;

static NSString* const kEnabledKey = @"SnippetsEnabled";
static NSString* const kHotKeyKey = @"SnippetHotKey";

//Measures of the window, in points
static const CGFloat kWidth = 720;
static const CGFloat kHeight = 440;
static const CGFloat kSearchHeight = 58;
static const CGFloat kFooterHeight = 34;
static const CGFloat kListWidth = 300;
static const CGFloat kRowHeight = 46;
static const CGFloat kCornerRadius = 14;
static const CGFloat kMargin = 16;

static void (^sTypingBoundary)(void);
static BOOL sVisible;   //read for every key by the event tap: it must not build the window to answer

#pragma mark - Rows

//The selection of a row is always drawn in the accent colour: the table is never the first responder (the search field is),
//and a table that is not would draw it grey
@interface SnippetRowView : NSTableRowView
@end

@implementation SnippetRowView

-(BOOL)isEmphasized {
    return YES;
}

-(NSBackgroundStyle)interiorBackgroundStyle {
    return self.selected ? NSBackgroundStyleEmphasized : NSBackgroundStyleNormal;
}

@end

@interface SnippetCellView : NSTableCellView
@property (nonatomic, strong) NSTextField* titleLabel;
@property (nonatomic, strong) NSTextField* detailLabel;
@property (nonatomic, strong) NSTextField* hintLabel;
@end

@implementation SnippetCellView

-(instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _titleLabel = [self makeLabelOfSize:13 weight:NSFontWeightMedium];
        _detailLabel = [self makeLabelOfSize:11 weight:NSFontWeightRegular];
        _hintLabel = [self makeLabelOfSize:11 weight:NSFontWeightRegular];
        _hintLabel.alignment = NSTextAlignmentRight;
        _hintLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
        [self setBackgroundStyle:NSBackgroundStyleNormal];
    }
    return self;
}

-(NSTextField*)makeLabelOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    NSTextField* label = [NSTextField labelWithString:@""];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.usesSingleLineMode = YES;
    [self addSubview:label];
    return label;
}

-(void)layout {
    [super layout];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat hintWidth = 34;
    CGFloat left = 10;
    CGFloat textWidth = width - left - hintWidth - 10;
    CGFloat lineHeight = 17;
    CGFloat top = floor((height - 2 * lineHeight - 1) / 2);
    self.detailLabel.frame = NSMakeRect(left, top, textWidth, lineHeight);
    self.titleLabel.frame = NSMakeRect(left, top + lineHeight + 1, textWidth, lineHeight);
    self.hintLabel.frame = NSMakeRect(width - hintWidth - 10, floor((height - lineHeight) / 2), hintWidth, lineHeight);
}

-(void)setBackgroundStyle:(NSBackgroundStyle)style {
    [super setBackgroundStyle:style];
    BOOL selected = style == NSBackgroundStyleEmphasized;
    NSColor* onAccent = [NSColor alternateSelectedControlTextColor];
    self.titleLabel.textColor = selected ? onAccent : [NSColor labelColor];
    self.detailLabel.textColor = selected ? [onAccent colorWithAlphaComponent:0.78] : [NSColor secondaryLabelColor];
    self.hintLabel.textColor = selected ? [onAccent colorWithAlphaComponent:0.78] : [NSColor tertiaryLabelColor];
}

@end

#pragma mark - The panel

//Takes the keyboard without making the application active, and handles ⌘1-⌘9
@interface SnippetPanel : NSPanel
@property (nonatomic, copy) BOOL (^keyEquivalentHandler)(NSEvent* event);
@end

@implementation SnippetPanel

-(BOOL)canBecomeKeyWindow {
    return YES;
}

-(BOOL)canBecomeMainWindow {
    return NO;
}

-(BOOL)performKeyEquivalent:(NSEvent*)event {
    if (self.keyEquivalentHandler != nil && self.keyEquivalentHandler(event))
        return YES;
    return [super performKeyEquivalent:event];
}

@end

//Stretchable rounded mask: the system uses it to cut the blur and to shape the shadow
static NSImage* WindowMask(void) {
    CGFloat side = kCornerRadius * 2 + 1;
    NSImage* mask = [NSImage imageWithSize:NSMakeSize(side, side) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor blackColor] set];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:kCornerRadius yRadius:kCornerRadius] fill];
        return YES;
    }];
    mask.capInsets = NSEdgeInsetsMake(kCornerRadius, kCornerRadius, kCornerRadius, kCornerRadius);
    mask.resizingMode = NSImageResizingModeStretch;
    return mask;
}

static NSView* HorizontalLine(NSRect frame) {
    NSBox* line = [[NSBox alloc] initWithFrame:frame];
    line.boxType = NSBoxSeparator;
    return line;
}

#pragma mark - The palette

@interface SnippetPalette () <NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@end

@implementation SnippetPalette {
    SnippetStore* _store;
    SnippetInserter* _inserter;

    SnippetPanel* _panel;
    NSTextField* _field;
    NSTableView* _table;
    NSTextView* _preview;
    NSTextField* _emptyLabel;
    NSArray<VOKSnippet*>* _results;

    NSRunningApplication* _target;      //the application that had the keyboard when the window opened
    BOOL _showing;                      //the window is being opened: losing the keyboard to the window is not a reason to close
}

#pragma mark Settings and entry points

+(void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{kEnabledKey: @1, kHotKeyKey: @(VOK_SNIPPET_DEFAULT_HOTKEY)}];
}

+(void)start {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    vSnippetsEnabled = [defaults integerForKey:kEnabledKey] != 0;
    vSnippetHotKey = (int)[defaults integerForKey:kHotKeyKey];
    //0 would be "the A key alone": every A typed would open the window
    if (vSnippetHotKey == 0)
        vSnippetHotKey = VOK_SHORTCUT_NONE;
}

+(SnippetPalette*)shared {
    static SnippetPalette* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[SnippetPalette alloc] initWithStore:[SnippetStore shared] inserter:[SnippetInserter shared]];
    });
    return instance;
}

+(BOOL)isVisible {
    return sVisible;
}

+(void)toggle {
    if ([self isVisible])
        [self hide];
    else
        [self show];
}

+(void)show {
    [[self shared] showPalette];
}

+(void)hide {
    [[self shared] hidePalette];
}

+(void)setTypingBoundaryHandler:(void (^)(void))handler {
    sTypingBoundary = [handler copy];
}

-(instancetype)initWithStore:(SnippetStore*)store inserter:(SnippetInserter*)inserter {
    self = [super init];
    if (self) {
        _store = store;
        _inserter = inserter;
        _results = @[];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(snippetsDidChange:)
                                                     name:VOKSnippetsDidChangeNotification object:store];
    }
    return self;
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(NSPanel*)panel {
    [self buildIfNeeded];
    return _panel;
}

-(NSTextField*)searchField {
    [self buildIfNeeded];
    return _field;
}

-(NSArray<VOKSnippet*>*)results {
    return _results;
}

-(NSInteger)selectedRow {
    return _table.selectedRow;
}

#pragma mark Building the window

-(void)buildIfNeeded {
    if (_panel != nil)
        return;

    _panel = [[SnippetPanel alloc] initWithContentRect:NSMakeRect(0, 0, kWidth, kHeight)
                                             styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                               backing:NSBackingStoreBuffered
                                                 defer:YES];
    _panel.opaque = NO;
    _panel.backgroundColor = [NSColor clearColor];
    _panel.hasShadow = YES;
    _panel.level = NSStatusWindowLevel;
    _panel.floatingPanel = YES;
    _panel.hidesOnDeactivate = NO;
    _panel.releasedWhenClosed = NO;
    _panel.animationBehavior = NSWindowAnimationBehaviorNone;
    _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary |
                                NSWindowCollectionBehaviorIgnoresCycle;
    _panel.delegate = self;
    _panel.title = @"Snippet";
    __weak SnippetPalette* weakSelf = self;
    _panel.keyEquivalentHandler = ^BOOL(NSEvent* event) {
        return [weakSelf handleKeyEquivalent:event];
    };

    //the material of menus and popovers: it follows light and dark and "Reduce transparency" by itself
    NSVisualEffectView* background = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, kHeight)];
    background.material = NSVisualEffectMaterialPopover;
    background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    background.state = NSVisualEffectStateActive;
    background.maskImage = WindowMask();
    _panel.contentView = background;

    CGFloat mainTop = kHeight - kSearchHeight - 1;
    CGFloat mainBottom = kFooterHeight + 1;
    CGFloat mainHeight = mainTop - mainBottom;

    //search
    NSImageView* glass = [NSImageView imageViewWithImage:VOKSymbol(@"magnifyingglass", 18, NSFontWeightRegular)];
    glass.contentTintColor = [NSColor secondaryLabelColor];
    glass.frame = NSMakeRect(kMargin + 4, kHeight - kSearchHeight + (kSearchHeight - 22) / 2, 22, 22);
    [background addSubview:glass];

    _field = [[NSTextField alloc] initWithFrame:NSMakeRect(kMargin + 36, kHeight - kSearchHeight + (kSearchHeight - 32) / 2,
                                                           kWidth - 2 * kMargin - 36, 32)];
    _field.bordered = NO;
    _field.bezeled = NO;
    _field.drawsBackground = NO;
    _field.focusRingType = NSFocusRingTypeNone;
    _field.font = [NSFont systemFontOfSize:22 weight:NSFontWeightLight];
    _field.placeholderString = @"Tìm snippet…";
    _field.delegate = self;
    _field.lineBreakMode = NSLineBreakByTruncatingTail;
    _field.cell.scrollable = YES;
    [_field setAccessibilityLabel:@"Tìm snippet"];
    [background addSubview:_field];
    [background addSubview:HorizontalLine(NSMakeRect(0, mainTop, kWidth, 1))];

    //list
    NSScrollView* listScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, mainBottom, kListWidth, mainHeight)];
    listScroll.drawsBackground = NO;
    listScroll.hasVerticalScroller = YES;
    listScroll.autohidesScrollers = YES;
    listScroll.borderType = NSNoBorder;
    _table = [[NSTableView alloc] initWithFrame:listScroll.bounds];
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"snippet"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:column];
    _table.headerView = nil;
    _table.rowHeight = kRowHeight;
    _table.intercellSpacing = NSMakeSize(0, 2);
    _table.backgroundColor = [NSColor clearColor];
    _table.style = NSTableViewStyleInset;
    _table.allowsEmptySelection = NO;
    _table.allowsMultipleSelection = NO;
    _table.focusRingType = NSFocusRingTypeNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(rowDoubleClicked:);
    listScroll.documentView = _table;
    column.width = kListWidth;                      //a column keeps its first width unless it is told: titles were cut short
    [_table sizeLastColumnToFit];
    [background addSubview:listScroll];

    NSBox* divider = [[NSBox alloc] initWithFrame:NSMakeRect(kListWidth, mainBottom, 1, mainHeight)];
    divider.boxType = NSBoxSeparator;
    [background addSubview:divider];

    //preview of the text of the snippet selected
    CGFloat previewX = kListWidth + 1;
    NSScrollView* previewScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(previewX, mainBottom, kWidth - previewX, mainHeight)];
    previewScroll.drawsBackground = NO;
    previewScroll.hasVerticalScroller = YES;
    previewScroll.autohidesScrollers = YES;
    previewScroll.borderType = NSNoBorder;
    _preview = [[NSTextView alloc] initWithFrame:previewScroll.bounds];
    _preview.editable = NO;
    _preview.selectable = NO;
    _preview.drawsBackground = NO;
    _preview.textContainerInset = NSMakeSize(16, 14);
    _preview.autoresizingMask = NSViewWidthSizable;
    _preview.verticallyResizable = YES;
    _preview.textContainer.widthTracksTextView = YES;
    previewScroll.documentView = _preview;
    [background addSubview:previewScroll];

    _emptyLabel = [NSTextField wrappingLabelWithString:@""];
    _emptyLabel.font = [NSFont systemFontOfSize:13];
    _emptyLabel.textColor = [NSColor secondaryLabelColor];
    _emptyLabel.alignment = NSTextAlignmentCenter;
    _emptyLabel.frame = NSMakeRect(previewX + 40, mainBottom + mainHeight / 2 - 30, kWidth - previewX - 80, 60);
    [background addSubview:_emptyLabel];

    //footer
    [background addSubview:HorizontalLine(NSMakeRect(0, kFooterHeight, kWidth, 1))];
    NSTextField* hint = [NSTextField labelWithString:@"↩ Chèn     ↑↓ Chọn     ⌘1–9 Chèn nhanh     esc Đóng"];
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = [NSColor tertiaryLabelColor];
    hint.frame = NSMakeRect(kMargin, (kFooterHeight - 16) / 2, 400, 16);
    [background addSubview:hint];

    NSButton* manage = [NSButton buttonWithTitle:@"Quản lý snippet…" target:self action:@selector(openEditor:)];
    manage.bordered = NO;
    manage.font = [NSFont systemFontOfSize:11];
    manage.contentTintColor = [NSColor secondaryLabelColor];
    [manage sizeToFit];
    manage.frame = NSMakeRect(kWidth - kMargin - manage.frame.size.width, (kFooterHeight - 18) / 2, manage.frame.size.width, 18);
    [background addSubview:manage];
}

#pragma mark Opening and closing

-(NSScreen*)screenOfMouse {
    NSPoint mouse = [NSEvent mouseLocation];
    for (NSScreen* screen in [NSScreen screens]) {
        if (NSPointInRect(mouse, screen.frame))
            return screen;
    }
    return [NSScreen mainScreen];
}

-(void)showPalette {
    [self buildIfNeeded];
    if (_panel.visible)
        return;
    NSRunningApplication* front = [NSWorkspace sharedWorkspace].frontmostApplication;
    _target = front.processIdentifier == [NSProcessInfo processInfo].processIdentifier ? nil : front;
    if (sTypingBoundary != nil)
        sTypingBoundary();

    _showing = YES;
    _field.stringValue = @"";
    [self reloadResults];

    NSRect visible = [self screenOfMouse].visibleFrame;
    NSPoint origin = NSMakePoint(NSMidX(visible) - kWidth / 2, NSMaxY(visible) - visible.size.height * 0.2 - kHeight);
    origin.y = MAX(origin.y, visible.origin.y + 20);
    [_panel setFrameOrigin:origin];

    [_panel makeKeyAndOrderFront:nil];
    //Hidden switch for a Mac or an application where the window does not get the keys without VOpenKey being the active
    //application: defaults write <bundle id> SnippetsActivateApp -bool YES
    BOOL activate = [[NSUserDefaults standardUserDefaults] boolForKey:@"SnippetsActivateApp"];
    if (activate || !_panel.keyWindow) {
        [NSApp activateIgnoringOtherApps:YES];
        [_panel makeKeyAndOrderFront:nil];
    }
    [_panel makeFirstResponder:_field];
    sVisible = YES;
    _showing = NO;
}

-(void)hidePalette {
    if (!_panel.visible)
        return;
    [_panel orderOut:nil];
    sVisible = NO;
    if (sTypingBoundary != nil)
        sTypingBoundary();
}

-(void)windowDidResignKey:(NSNotification*)notification {
    //another window or application took the keyboard (a click outside, ⌘Tab): the search is over
    if (!_showing)
        [self hidePalette];
}

-(void)snippetsDidChange:(NSNotification*)notification {
    if (_panel.visible)
        [self reloadResults];
}

-(void)openEditor:(id)sender {
    [self hidePalette];
    [SnippetEditorController show];
}

#pragma mark Results

-(void)reloadResults {
    NSString* query = _field.stringValue;
    _results = [_store search:query];
    [_table reloadData];
    if (_results.count > 0)
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [_table scrollRowToVisible:0];
    [self updatePreview];
}

-(void)setQuery:(NSString*)query {
    [self buildIfNeeded];
    _field.stringValue = query;
    [self reloadResults];
}

-(void)selectRow:(NSInteger)row {
    if (_results.count == 0)
        return;
    row = MAX(0, MIN(row, (NSInteger)_results.count - 1));
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [_table scrollRowToVisible:row];
}

//{clipboard}, {date} and {time} stand out in the text: they are what changes when it is inserted
-(NSAttributedString*)previewForSnippet:(VOKSnippet*)snippet {
    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 3;
    NSDictionary* plain = @{NSFontAttributeName: [NSFont systemFontOfSize:13],
                            NSForegroundColorAttributeName: [NSColor labelColor],
                            NSParagraphStyleAttributeName: paragraph};
    NSMutableAttributedString* text = [[NSMutableAttributedString alloc] initWithString:snippet.content attributes:plain];
    NSRegularExpression* placeholders = [NSRegularExpression regularExpressionWithPattern:@"\\{(clipboard|date|time)\\}" options:0 error:nil];
    for (NSTextCheckingResult* match in [placeholders matchesInString:snippet.content options:0 range:NSMakeRange(0, snippet.content.length)]) {
        [text addAttributes:@{NSForegroundColorAttributeName: [NSColor controlAccentColor],
                              NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]}
                      range:match.range];
    }
    return text;
}

-(void)updatePreview {
    NSInteger row = _table.selectedRow;
    BOOL has = row >= 0 && row < (NSInteger)_results.count;
    _emptyLabel.hidden = has;
    _preview.enclosingScrollView.hidden = !has;
    if (has) {
        [_preview.textStorage setAttributedString:[self previewForSnippet:_results[row]]];
        [_preview scrollRangeToVisible:NSMakeRange(0, 0)];
        return;
    }
    if (_store.snippets.count == 0)
        _emptyLabel.stringValue = @"Chưa có snippet nào.\nBấm “Quản lý snippet…” để thêm.";
    else
        _emptyLabel.stringValue = [NSString stringWithFormat:@"Không có snippet nào khớp với “%@”.", _field.stringValue];
}

#pragma mark Inserting

-(void)insertSelected {
    NSInteger row = _table.selectedRow;
    if (row < 0 || row >= (NSInteger)_results.count)
        return;
    [self insertSnippet:_results[row]];
}

-(void)insertSnippet:(VOKSnippet*)snippet {
    NSRunningApplication* target = _target;
    [self hidePalette];
    [_store recordUse:snippet];
    //the inserter brings the application back to the front first when VOpenKey is the active one
    [_inserter insertSnippetContent:snippet.content application:target];
}

-(void)rowDoubleClicked:(id)sender {
    if (_table.clickedRow >= 0)
        [self insertSelected];
}

//⌘1 to ⌘9
-(BOOL)handleKeyEquivalent:(NSEvent*)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (flags != NSEventModifierFlagCommand)
        return NO;
    NSString* key = event.charactersIgnoringModifiers;
    if (key.length != 1 || [key characterAtIndex:0] < '1' || [key characterAtIndex:0] > '9')
        return NO;
    NSInteger row = [key characterAtIndex:0] - '1';
    if (row >= (NSInteger)_results.count)
        return YES; //nothing there, but it is not for the application behind either
    [self selectRow:row];
    [self insertSelected];
    return YES;
}

#pragma mark Search field

-(void)controlTextDidChange:(NSNotification*)notification {
    [self reloadResults];
}

-(BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)command {
    if (command == @selector(moveDown:) || command == @selector(insertTab:)) {
        [self selectRow:_table.selectedRow + 1];
        return YES;
    }
    if (command == @selector(moveUp:) || command == @selector(insertBacktab:)) {
        [self selectRow:_table.selectedRow - 1];
        return YES;
    }
    if (command == @selector(pageDown:)) {
        [self selectRow:_table.selectedRow + 5];
        return YES;
    }
    if (command == @selector(pageUp:)) {
        [self selectRow:_table.selectedRow - 5];
        return YES;
    }
    if (command == @selector(insertNewline:) || command == @selector(insertNewlineIgnoringFieldEditor:)) {
        [self insertSelected];
        return YES;
    }
    if (command == @selector(cancelOperation:)) {
        //like Spotlight: the first Esc clears what was typed, the next one closes
        if (_field.stringValue.length > 0) {
            _field.stringValue = @"";
            [self reloadResults];
        } else {
            [self hidePalette];
        }
        return YES;
    }
    return NO;
}

#pragma mark Table

-(NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    return (NSInteger)_results.count;
}

-(NSTableRowView*)tableView:(NSTableView*)tableView rowViewForRow:(NSInteger)row {
    return [[SnippetRowView alloc] init];
}

-(NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    SnippetCellView* cell = [tableView makeViewWithIdentifier:@"cell" owner:self];
    if (cell == nil) {
        cell = [[SnippetCellView alloc] initWithFrame:NSMakeRect(0, 0, kListWidth, kRowHeight)];
        cell.identifier = @"cell";
    }
    VOKSnippet* snippet = _results[row];
    cell.titleLabel.stringValue = snippet.title.length > 0 ? snippet.title : @"(Chưa đặt tên)";
    cell.detailLabel.stringValue = [SnippetPalette firstLineOf:snippet.content];
    cell.hintLabel.stringValue = row < 9 ? [NSString stringWithFormat:@"⌘%ld", (long)row + 1] : @"";
    return cell;
}

//the first line that has something in it, for the row of the list
+(NSString*)firstLineOf:(NSString*)text {
    for (NSString* line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString* trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0)
            return trimmed;
    }
    return @"";
}

-(void)tableViewSelectionDidChange:(NSNotification*)notification {
    [self updatePreview];
}

@end
