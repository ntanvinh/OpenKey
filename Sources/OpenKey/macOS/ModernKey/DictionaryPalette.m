//
//  DictionaryPalette.m
//  VOpenKey
//

#import "DictionaryPalette.h"
#import "AISelection.h"
#import "VOKUI.h"
#import "WordSpeaker.h"
#import <Carbon/Carbon.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const CGFloat kPanelWidth = 760;
static const CGFloat kPanelHeight = 500;
static const CGFloat kLeftColWidth = 258;
static const CGFloat kCornerRadius = 14;    //the same as the snippet palette and the AI assistant, the other two large floating panels
static const CGFloat kHairline = 0.5;       //the edge of a panel is one device pixel on a Retina screen, as in the case bar and the suggestion bar

static DictionaryPalette* sSharedPalette = nil;
static dispatch_block_t sTypingBoundary = nil;

static NSImage* WindowMaskImage(CGFloat radius) {
    CGFloat edge = radius * 2 + 2;
    NSImage* mask = [NSImage imageWithSize:NSMakeSize(edge, edge) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [[NSColor blackColor] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:r xRadius:radius yRadius:radius] fill];
        return YES;
    }];
    mask.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    mask.resizingMode = NSImageResizingModeStretch;
    return mask;
}

static NSColor* PrimaryTextColor(void) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor*(NSAppearance* app) {
        BOOL dark = [app bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua;
        return dark ? [NSColor colorWithCalibratedWhite:0.95 alpha:1.0]
                    : [NSColor colorWithCalibratedWhite:0.10 alpha:1.0];
    }];
}

static NSColor* SecondaryTextColor(void) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor*(NSAppearance* app) {
        BOOL dark = [app bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua;
        return dark ? [NSColor colorWithCalibratedWhite:0.74 alpha:1.0]
                    : [NSColor colorWithCalibratedWhite:0.32 alpha:1.0];
    }];
}

static NSColor* VeilColor(void) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor*(NSAppearance* app) {
        BOOL dark = [app bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua;
        return dark ? [NSColor colorWithCalibratedWhite:0.13 alpha:0.96]
                    : [NSColor colorWithCalibratedWhite:0.985 alpha:0.97];
    }];
}

static NSTextField* DictLabel(NSString* text, CGFloat size, NSFontWeight weight, NSColor* color) {
    NSTextField* label = VOKLabel(text, size, weight, color);
    label.translatesAutoresizingMaskIntoConstraints = YES;
    return label;
}

@interface VOKDictVeilView : NSView
@end

@implementation VOKDictVeilView
-(BOOL)allowsVibrancy { return NO; }
-(BOOL)wantsUpdateLayer { return YES; }
-(void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = VeilColor().CGColor;
        self.layer.cornerRadius = kCornerRadius;
        self.layer.borderWidth = kHairline;
        //the system separator as it is: -colorWithAlphaComponent: does not multiply, it REPLACES the alpha (0.12 in dark), so the
        //0.55 that was here drew a white line of 55% (black in light): 4 to 5 times heavier than every other edge of the app
        self.layer.borderColor = NSColor.separatorColor.CGColor;
    }];
}
-(void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
@end

static NSColor* BadgeBackgroundColor(BOOL accent) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor*(NSAppearance* app) {
        BOOL dark = [app bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua;
        if (accent)
            return dark ? [NSColor.systemBlueColor colorWithAlphaComponent:0.25]
                        : [NSColor.systemBlueColor colorWithAlphaComponent:0.13];
        return dark ? [NSColor colorWithCalibratedWhite:1.0 alpha:0.10]
                    : [NSColor colorWithCalibratedWhite:0.0 alpha:0.065];
    }];
}

//A macOS tag: a capsule (radius = half the height) with a tinted fill, the text centred on both axes. The old badge was a
//wrapping label with a layer fill: such a label draws its text from the top, so it sat high in the pill, and the layer colour was
//frozen at the appearance it was created in.
@interface VOKDictBadgeView : NSView
@property(nonatomic, strong) NSColor* fill;
@end

@implementation VOKDictBadgeView
-(BOOL)allowsVibrancy { return NO; }
-(BOOL)wantsUpdateLayer { return YES; }
-(void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = self.fill.CGColor;
        self.layer.cornerRadius = NSHeight(self.bounds) / 2.0;
    }];
}
-(void)setFrame:(NSRect)frame { [super setFrame:frame]; self.needsDisplay = YES; }
-(void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
@end

static CGFloat const kBadgeHeight = 18;

static NSView* DictBadge(NSString* text, NSColor* textColor, NSColor* fill, CGFloat minW, CGFloat maxW, CGFloat x, CGFloat y) {
    NSFont* font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold];
    NSTextField* label = [NSTextField labelWithString:text ?: @""];
    label.font = font;
    label.textColor = textColor;
    label.alignment = NSTextAlignmentCenter;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label sizeToFit];
    CGFloat w = MIN(maxW, MAX(minW, ceil(NSWidth(label.frame)) + 14));
    VOKDictBadgeView* box = [[VOKDictBadgeView alloc] initWithFrame:NSMakeRect(x, y, w, kBadgeHeight)];
    box.wantsLayer = YES;
    box.fill = fill;
    CGFloat lh = ceil(NSHeight(label.frame));
    label.frame = NSMakeRect(5, floor((kBadgeHeight - lh) / 2.0), w - 10, lh);
    [box addSubview:label];
    return box;
}

static NSColor* BadgeTintColor(NSColor* base) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor*(NSAppearance* app) {
        BOOL dark = [app bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua;
        return [base colorWithAlphaComponent:dark ? 0.22 : 0.14];
    }];
}

static NSString* SafeDisplayText(NSString* s) {
    return s ?: @"";
}

#pragma mark - Custom Table Row & Panel

@interface VOKDictRowView : NSTableRowView
@end

@implementation VOKDictRowView
-(void)drawSelectionInRect:(NSRect)dirtyRect {
    if (self.selectionHighlightStyle == NSTableViewSelectionHighlightStyleNone)
        return;
    NSRect rect = NSInsetRect(self.bounds, 8, 2);
    NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:7 yRadius:7];
    if (self.emphasized)
        [[NSColor.controlAccentColor colorWithAlphaComponent:0.92] setFill];
    else
        [[NSColor.controlAccentColor colorWithAlphaComponent:0.22] setFill];
    [path fill];
}
@end

@interface VOKDictPanel : NSPanel
@property (nonatomic, copy) void (^onCancelKey)(void);
@property (nonatomic, copy) void (^onSpeakKey)(void);
@end

@implementation VOKDictPanel
-(BOOL)canBecomeKeyWindow { return YES; }
-(BOOL)canBecomeMainWindow { return NO; }
-(void)cancelOperation:(id)sender {
    if (self.onCancelKey) self.onCancelKey();
}
//⌘P reads the word aloud, also while the search field has the keyboard (the field would not use it: there is nothing to print here)
-(BOOL)performKeyEquivalent:(NSEvent*)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask &
                                 (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl);
    if (flags == NSEventModifierFlagCommand && [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"p"]) {
        if (self.onSpeakKey) self.onSpeakKey();
        return YES;
    }
    return [super performKeyEquivalent:event];
}
@end

#pragma mark - DictionaryPalette

@interface DictionaryPalette () <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@end

@implementation DictionaryPalette {
    DictionaryService* _service;
    VOKDictPanel* _panel;
    NSVisualEffectView* _effectView;
    NSView* _veilView;

    // Header
    NSView* _headerBar;
    NSImageView* _searchIcon;
    NSTextField* _searchField;
    NSButton* _clearButton;
    NSButton* _managerToggleButton;
    NSButton* _closeButton;
    NSTextField* _managerTitleLabel;

    // Filter Strip (Lookup mode)
    NSScrollView* _filterScroll;
    NSStackView* _filterStack;
    NSView* _filterSep;

    // Lookup Split View Container
    NSView* _lookupContainer;
    NSScrollView* _resultsScroll;
    NSTableView* _resultsTable;
    NSView* _columnSep;
    NSView* _rightPane;
    NSView* _defActionBar;
    NSTextField* _defSummaryLabel;
    NSButton* _speakButton;
    NSButton* _copyDefButton;
    NSScrollView* _defScroll;
    NSTextView* _definitionView;

    // Lookup Empty State Overlay
    NSView* _emptyOverlay;
    NSImageView* _emptyIcon;
    NSTextField* _emptyTitle;
    NSTextField* _emptyHint;
    NSButton* _emptyActionButton;

    // Manager Mode Container
    NSView* _managerContainer;
    NSView* _managerToolbar;
    NSTextField* _managerBanner;
    NSButton* _downloadSelectedButton;
    NSButton* _importButton;
    NSButton* _backToLookupButton;
    NSScrollView* _catalogScroll;
    NSTableView* _catalogTable;

    // Footer
    NSView* _footerSep;
    NSView* _footerBar;
    NSTextField* _footerLeftLabel;
    NSTextField* _footerRightLabel;

    // State
    BOOL _showingManager;
    BOOL _openingFileDialog;
    NSString* _selectedFilterDictId;
    NSString* _speakText;           //what the speaker button reads for the word on show; nil when it is not an English word
    NSArray<VOKDictionaryCatalogItem*>* _catalogItems;
    NSMutableSet<NSString*>* _checkedIDs;
    NSArray<VOKDictionarySearchHit*>* _hits;
    NSArray<VOKDictionaryDefinition*>* _currentDefinitions;
    NSInteger _selectedRow;
    NSUInteger _searchGeneration;
    BOOL _closing;
}

+(instancetype)shared {
    if (sSharedPalette == nil)
        sSharedPalette = [[DictionaryPalette alloc] initWithService:[DictionaryService shared]];
    return sSharedPalette;
}

+(BOOL)isVisible {
    return sSharedPalette != nil && sSharedPalette.panel.visible;
}

+(void)showPalette {
    [[self shared] show];
}

+(void)showWithQuery:(nullable NSString*)query {
    [[self shared] showWithQuery:query captureSelection:(query.length == 0)];
}

+(void)hidePalette {
    [sSharedPalette hide];
}

+(void)setTypingBoundaryHandler:(dispatch_block_t)handler {
    sTypingBoundary = [handler copy];
}

-(instancetype)initWithService:(DictionaryService*)service {
    if ((self = [super init])) {
        _service = service ?: [DictionaryService shared];
        _hits = @[];
        _currentDefinitions = @[];
        _catalogItems = [_service allDictionaries];
        _checkedIDs = [NSMutableSet set];
        _selectedRow = -1;
        [self seedDefaultChecks];
        [self buildPanel];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(serviceDidUpdate:)
                                                     name:VOKDictionaryDidChangeNotification
                                                   object:_service];
    }
    return self;
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)seedDefaultChecks {
    for (VOKDictionaryCatalogItem* item in _catalogItems) {
        if (!item.installed && item.recommended)
            [_checkedIDs addObject:item.dictId];
    }
}

-(NSPanel*)panel { return _panel; }
-(NSTextField*)searchField { return _searchField; }
-(NSTableView*)resultsTable { return _resultsTable; }
-(NSTextView*)definitionView { return _definitionView; }
-(NSButton*)speakButton { return _speakButton; }
-(NSString*)speakText { return _speakText; }
-(NSButton*)copyButton { return _copyDefButton; }
-(BOOL)showingManager { return _showingManager; }
-(NSString*)selectedFilterDictId { return _selectedFilterDictId; }
-(NSArray<VOKDictionarySearchHit*>*)currentHits { return _hits; }

#pragma mark - UI Construction

-(void)buildPanel {
    NSRect frame = NSMakeRect(0, 0, kPanelWidth, kPanelHeight);
    _panel = [[VOKDictPanel alloc] initWithContentRect:frame
                                             styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    _panel.level = NSFloatingWindowLevel;
    _panel.opaque = NO;
    _panel.backgroundColor = [NSColor clearColor];
    _panel.hasShadow = YES;
    _panel.movableByWindowBackground = YES;
    _panel.hidesOnDeactivate = NO;
    _panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace |
                                NSWindowCollectionBehaviorTransient |
                                NSWindowCollectionBehaviorFullScreenAuxiliary;
    _panel.delegate = self;
    __weak DictionaryPalette* weakSelf = self;
    _panel.onCancelKey = ^{ [weakSelf handleEscape]; };
    _panel.onSpeakKey = ^{ [weakSelf speakCurrentWord]; };
    [_panel setAccessibilityLabel:@"Từ điển VOpenKey AI"];

    _effectView = [[NSVisualEffectView alloc] initWithFrame:frame];
    _effectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _effectView.material = NSVisualEffectMaterialPopover;
    _effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _effectView.state = NSVisualEffectStateActive;
    _effectView.maskImage = WindowMaskImage(kCornerRadius);
    _panel.contentView = _effectView;

    _veilView = [[VOKDictVeilView alloc] initWithFrame:frame];
    _veilView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _veilView.wantsLayer = YES;
    _veilView.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
    [_effectView addSubview:_veilView];

    [self buildHeader];
    [self buildFilterStrip];
    [self buildLookupArea];
    [self buildManagerArea];
    [self buildFooter];
    [self layoutViews];
    [self syncModeUI];
}

-(void)buildHeader {
    _headerBar = [[NSView alloc] initWithFrame:NSZeroRect];
    [_veilView addSubview:_headerBar];

    _searchIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _searchIcon.image = VOKSymbol(@"magnifyingglass", 16, NSFontWeightMedium);
    _searchIcon.contentTintColor = SecondaryTextColor();
    [_headerBar addSubview:_searchIcon];

    _searchField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _searchField.bordered = NO;
    _searchField.drawsBackground = NO;
    _searchField.focusRingType = NSFocusRingTypeNone;
    _searchField.font = [NSFont systemFontOfSize:16 weight:NSFontWeightRegular];
    _searchField.textColor = PrimaryTextColor();
    _searchField.placeholderString = @"Tra từ Anh, Việt hoặc gõ không dấu…";
    _searchField.delegate = self;
    _searchField.target = self;
    _searchField.action = @selector(searchReturnPressed:);
    [_searchField setAccessibilityLabel:@"Ô nhập từ cần tra"];
    [_headerBar addSubview:_searchField];

    _clearButton = [NSButton buttonWithTitle:@"" target:self action:@selector(clearSearchPressed:)];
    _clearButton.bordered = NO;
    _clearButton.image = VOKSymbol(@"xmark.circle.fill", 14, NSFontWeightRegular);
    _clearButton.contentTintColor = SecondaryTextColor();
    _clearButton.toolTip = VOKTooltip(@"Xóa nội dung tìm kiếm");
    [_clearButton setAccessibilityLabel:@"Xóa từ đang tra"];
    _clearButton.hidden = YES;
    [_headerBar addSubview:_clearButton];

    _managerTitleLabel = DictLabel(@"Quản lý bộ từ điển", 15, NSFontWeightSemibold, PrimaryTextColor());
    _managerTitleLabel.hidden = YES;
    [_headerBar addSubview:_managerTitleLabel];

    _managerToggleButton = [NSButton buttonWithTitle:@"Bộ từ điển" target:self action:@selector(toggleManagerPressed:)];
    _managerToggleButton.bezelStyle = NSBezelStyleRounded;
    _managerToggleButton.controlSize = NSControlSizeRegular;
    VOKSetButtonSymbol(_managerToggleButton, @"books.vertical", 12);
    _managerToggleButton.toolTip = VOKTooltip(@"Tải thêm từ điển mã nguồn mở hoặc nhập file StarDict");
    [_managerToggleButton setAccessibilityLabel:@"Quản lý bộ từ điển"];
    [_headerBar addSubview:_managerToggleButton];

    _closeButton = [NSButton buttonWithTitle:@"" target:self action:@selector(closePressed:)];
    _closeButton.bordered = NO;
    _closeButton.image = VOKSymbol(@"xmark", 13, NSFontWeightSemibold);
    _closeButton.contentTintColor = SecondaryTextColor();
    _closeButton.toolTip = VOKTooltip(@"Đóng (Esc)");
    [_closeButton setAccessibilityLabel:@"Đóng cửa sổ từ điển"];
    [_headerBar addSubview:_closeButton];

    _filterSep = VOKSeparator();
    [_veilView addSubview:_filterSep];
}

-(void)buildFilterStrip {
    _filterScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _filterScroll.hasHorizontalScroller = NO;
    _filterScroll.hasVerticalScroller = NO;
    _filterScroll.drawsBackground = NO;
    _filterScroll.borderType = NSNoBorder;

    _filterStack = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, 28)];
    _filterStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _filterStack.alignment = NSLayoutAttributeCenterY;
    _filterStack.spacing = 6;
    _filterStack.edgeInsets = NSEdgeInsetsMake(2, 12, 2, 12);
    _filterScroll.documentView = _filterStack;
    [_veilView addSubview:_filterScroll];
}

-(void)buildLookupArea {
    _lookupContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    [_veilView addSubview:_lookupContainer];

    // Left results table
    _resultsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _resultsScroll.hasVerticalScroller = YES;
    _resultsScroll.autohidesScrollers = YES;
    _resultsScroll.drawsBackground = NO;
    _resultsScroll.borderType = NSNoBorder;

    _resultsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _resultsTable.style = NSTableViewStylePlain;
    _resultsTable.headerView = nil;
    _resultsTable.backgroundColor = [NSColor clearColor];
    _resultsTable.intercellSpacing = NSMakeSize(0, 0);
    _resultsTable.rowHeight = 46;
    _resultsTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _resultsTable.dataSource = self;
    _resultsTable.delegate = self;
    _resultsTable.identifier = @"LookupResultsTable";
    [_resultsTable setAccessibilityLabel:@"Danh sách từ khớp"];
    NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier:@"word"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    col.width = kLeftColWidth;
    [_resultsTable addTableColumn:col];
    [_resultsTable sizeLastColumnToFit];
    _resultsScroll.documentView = _resultsTable;
    [_lookupContainer addSubview:_resultsScroll];

    _columnSep = [[NSView alloc] initWithFrame:NSZeroRect];
    _columnSep.wantsLayer = YES;
    _columnSep.layer.backgroundColor = [NSColor separatorColor].CGColor;
    [_lookupContainer addSubview:_columnSep];

    // Right definition pane
    _rightPane = [[NSView alloc] initWithFrame:NSZeroRect];
    [_lookupContainer addSubview:_rightPane];

    _defActionBar = [[NSView alloc] initWithFrame:NSZeroRect];
    [_rightPane addSubview:_defActionBar];

    _defSummaryLabel = DictLabel(@"", 11.5, NSFontWeightMedium, SecondaryTextColor());
    [_defActionBar addSubview:_defSummaryLabel];

    //the speaker: shown only for an English word (see displayHitAtRow:), next to the copy button as in the Dictionary app of the Mac
    _speakButton = [NSButton buttonWithTitle:@"" target:self action:@selector(speakPressed:)];
    _speakButton.bezelStyle = NSBezelStyleRounded;
    _speakButton.controlSize = NSControlSizeSmall;
    VOKSetButtonSymbol(_speakButton, @"speaker.wave.2", 12);
    _speakButton.toolTip = VOKTooltip(@"Nghe phát âm tiếng Anh (⌘P)");
    [_speakButton setAccessibilityLabel:@"Nghe phát âm từ tiếng Anh"];
    _speakButton.hidden = YES;
    [_defActionBar addSubview:_speakButton];

    _copyDefButton = [NSButton buttonWithTitle:@"Sao chép nghĩa" target:self action:@selector(copyDefinitionPressed:)];
    _copyDefButton.bezelStyle = NSBezelStyleRounded;
    _copyDefButton.controlSize = NSControlSizeSmall;
    VOKSetButtonSymbol(_copyDefButton, @"doc.on.doc", 11);
    [_copyDefButton setAccessibilityLabel:@"Sao chép toàn bộ nghĩa của từ"];
    [_defActionBar addSubview:_copyDefButton];

    _defScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _defScroll.hasVerticalScroller = YES;
    _defScroll.autohidesScrollers = YES;
    _defScroll.drawsBackground = NO;
    _defScroll.borderType = NSNoBorder;

    _definitionView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 460, 340)];
    _definitionView.editable = NO;
    _definitionView.selectable = YES;
    _definitionView.drawsBackground = NO;
    _definitionView.richText = YES;
    _definitionView.textContainerInset = NSMakeSize(18, 12);
    _definitionView.autoresizingMask = NSViewWidthSizable;
    _definitionView.textContainer.widthTracksTextView = YES;
    [_definitionView setAccessibilityLabel:@"Nội dung giải nghĩa từ điển"];
    _defScroll.documentView = _definitionView;
    [_rightPane addSubview:_defScroll];

    // Empty state overlay inside right pane
    _emptyOverlay = [[NSView alloc] initWithFrame:NSZeroRect];
    _emptyIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _emptyIcon.image = VOKSymbol(@"character.book.closed", 34, NSFontWeightLight);
    _emptyIcon.contentTintColor = SecondaryTextColor();
    [_emptyOverlay addSubview:_emptyIcon];

    _emptyTitle = DictLabel(@"", 15, NSFontWeightSemibold, PrimaryTextColor());
    _emptyTitle.alignment = NSTextAlignmentCenter;
    [_emptyOverlay addSubview:_emptyTitle];

    _emptyHint = DictLabel(@"", 12.5, NSFontWeightRegular, SecondaryTextColor());
    _emptyHint.alignment = NSTextAlignmentCenter;
    [_emptyOverlay addSubview:_emptyHint];

    _emptyActionButton = [NSButton buttonWithTitle:@"Mở Bộ từ điển" target:self action:@selector(openManagerFromEmpty:)];
    _emptyActionButton.bezelStyle = NSBezelStyleRounded;
    [_emptyOverlay addSubview:_emptyActionButton];
    [_rightPane addSubview:_emptyOverlay];
}

-(void)buildManagerArea {
    _managerContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _managerContainer.hidden = YES;
    [_veilView addSubview:_managerContainer];

    _managerToolbar = [[NSView alloc] initWithFrame:NSZeroRect];
    [_managerContainer addSubview:_managerToolbar];

    _managerBanner = DictLabel(@"Chọn bộ từ điển mã nguồn mở để tải (Anh–Việt, Việt–Anh ở đầu) hoặc nhập StarDict.",
                               12, NSFontWeightRegular, SecondaryTextColor());
    _managerBanner.maximumNumberOfLines = 2;
    [_managerToolbar addSubview:_managerBanner];

    _backToLookupButton = [NSButton buttonWithTitle:@"Quay lại tra cứu" target:self action:@selector(toggleManagerPressed:)];
    _backToLookupButton.bezelStyle = NSBezelStyleRounded;
    VOKSetButtonSymbol(_backToLookupButton, @"chevron.left", 11);
    [_managerToolbar addSubview:_backToLookupButton];

    _importButton = [NSButton buttonWithTitle:@"Thêm từ máy…" target:self action:@selector(importLocalPressed:)];
    _importButton.bezelStyle = NSBezelStyleRounded;
    VOKSetButtonSymbol(_importButton, @"folder.badge.plus", 12);
    [_importButton setAccessibilityLabel:@"Nhập file hoặc thư mục từ điển StarDict từ máy"];
    [_managerToolbar addSubview:_importButton];

    _downloadSelectedButton = [NSButton buttonWithTitle:@"Tải mục đã chọn" target:self action:@selector(downloadSelectedPressed:)];
    _downloadSelectedButton.bezelStyle = NSBezelStyleRounded;
    _downloadSelectedButton.bezelColor = [NSColor controlAccentColor];
    VOKSetButtonSymbol(_downloadSelectedButton, @"arrow.down.circle.fill", 12);
    [_downloadSelectedButton setAccessibilityLabel:@"Tải xuống các từ điển đã chọn"];
    [_managerToolbar addSubview:_downloadSelectedButton];

    _catalogScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _catalogScroll.hasVerticalScroller = YES;
    _catalogScroll.autohidesScrollers = YES;
    _catalogScroll.drawsBackground = NO;
    _catalogScroll.borderType = NSNoBorder;

    _catalogTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _catalogTable.style = NSTableViewStylePlain;
    _catalogTable.headerView = nil;
    _catalogTable.backgroundColor = [NSColor clearColor];
    _catalogTable.intercellSpacing = NSMakeSize(0, 0);
    _catalogTable.rowHeight = 76;
    _catalogTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    _catalogTable.dataSource = self;
    _catalogTable.delegate = self;
    _catalogTable.identifier = @"CatalogTable";
    [_catalogTable setAccessibilityLabel:@"Danh sách bộ từ điển mã nguồn mở"];
    NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier:@"catalog"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    col.width = kPanelWidth;
    [_catalogTable addTableColumn:col];
    [_catalogTable sizeLastColumnToFit];
    _catalogScroll.documentView = _catalogTable;
    [_managerContainer addSubview:_catalogScroll];
}

-(void)buildFooter {
    _footerSep = VOKSeparator();
    [_veilView addSubview:_footerSep];

    _footerBar = [[NSView alloc] initWithFrame:NSZeroRect];
    [_veilView addSubview:_footerBar];

    _footerLeftLabel = DictLabel(@"", 11.5, NSFontWeightRegular, SecondaryTextColor());
    [_footerBar addSubview:_footerLeftLabel];

    _footerRightLabel = DictLabel(@"↑↓ Chọn từ · ⌘1–9 Chọn nhanh · Esc Đóng", 11.5, NSFontWeightRegular, SecondaryTextColor());
    _footerRightLabel.alignment = NSTextAlignmentRight;
    [_footerBar addSubview:_footerRightLabel];
}

-(void)layoutViews {
    CGFloat w = kPanelWidth;
    CGFloat h = kPanelHeight;
    CGFloat headerH = 52;
    CGFloat filterH = _showingManager ? 0 : 34;
    CGFloat footerH = 30;
    CGFloat bodyY = footerH + 1;
    CGFloat bodyH = h - headerH - filterH - bodyY - 1;

    _headerBar.frame = NSMakeRect(0, h - headerH, w, headerH);
    _searchIcon.frame = NSMakeRect(16, (headerH - 18) / 2, 18, 18);
    CGFloat rightEdge = w - 14;
    _closeButton.frame = NSMakeRect(rightEdge - 24, (headerH - 24) / 2, 24, 24);
    rightEdge -= 32;
    _managerToggleButton.frame = NSMakeRect(rightEdge - 118, (headerH - 28) / 2, 118, 28);
    rightEdge -= 126;
    _clearButton.frame = NSMakeRect(rightEdge - 20, (headerH - 20) / 2, 20, 20);
    _searchField.frame = NSMakeRect(42, (headerH - 24) / 2 - 1, rightEdge - 66, 24);
    _managerTitleLabel.frame = NSMakeRect(16, (headerH - 22) / 2, 320, 22);

    _filterScroll.hidden = _showingManager;
    _filterScroll.frame = NSMakeRect(0, h - headerH - filterH, w, filterH);
    _filterSep.frame = NSMakeRect(0, h - headerH - filterH - 1, w, 1);

    _lookupContainer.frame = NSMakeRect(0, bodyY, w, bodyH);
    _resultsScroll.frame = NSMakeRect(0, 0, kLeftColWidth, bodyH);
    _columnSep.frame = NSMakeRect(kLeftColWidth, 0, 1, bodyH);
    CGFloat rw = w - kLeftColWidth - 1;
    _rightPane.frame = NSMakeRect(kLeftColWidth + 1, 0, rw, bodyH);
    _defActionBar.frame = NSMakeRect(0, bodyH - 34, rw, 34);
    _defSummaryLabel.frame = NSMakeRect(18, 8, rw - 150 - 38, 18);
    _copyDefButton.frame = NSMakeRect(rw - 128, 6, 114, 22);
    _speakButton.frame = NSMakeRect(rw - 128 - 6 - 32, 6, 32, 22);
    _defScroll.frame = NSMakeRect(0, 0, rw, bodyH - 34);
    _definitionView.frame = NSMakeRect(0, 0, rw, MAX(bodyH - 34, _definitionView.frame.size.height));

    _emptyOverlay.frame = NSMakeRect(0, 0, rw, bodyH);
    CGFloat cy = bodyH / 2;
    _emptyIcon.frame = NSMakeRect((rw - 40) / 2, cy + 28, 40, 40);
    _emptyTitle.frame = NSMakeRect(24, cy - 4, rw - 48, 24);
    _emptyHint.frame = NSMakeRect(36, cy - 44, rw - 72, 36);
    _emptyActionButton.frame = NSMakeRect((rw - 140) / 2, cy - 82, 140, 28);

    CGFloat mgrBodyY = footerH + 1;
    CGFloat mgrBodyH = h - headerH - mgrBodyY - 1;
    _managerContainer.frame = NSMakeRect(0, mgrBodyY, w, mgrBodyH);
    CGFloat tbH = 56;
    _managerToolbar.frame = NSMakeRect(0, mgrBodyH - tbH, w, tbH);
    CGFloat dlW = 148, impW = 134, backW = 122, gap = 8;
    CGFloat right = w - 14;
    _downloadSelectedButton.frame = NSMakeRect(right - dlW, 14, dlW, 28);
    right -= dlW + gap;
    _importButton.frame = NSMakeRect(right - impW, 14, impW, 28);
    right -= impW + gap;
    _backToLookupButton.frame = NSMakeRect(right - backW, 14, backW, 28);
    CGFloat bannerRight = _backToLookupButton.hidden ? right : (right - backW - gap);
    _managerBanner.frame = NSMakeRect(16, 10, MAX(180, bannerRight - 22), 36);
    _catalogScroll.frame = NSMakeRect(0, 0, w, mgrBodyH - tbH);

    _footerSep.frame = NSMakeRect(0, footerH, w, 1);
    _footerBar.frame = NSMakeRect(0, 0, w, footerH);
    _footerLeftLabel.frame = NSMakeRect(16, 6, 390, 18);
    _footerRightLabel.frame = NSMakeRect(w - 340, 6, 324, 18);
}

#pragma mark - Presentation & Mode Switching

-(void)show {
    [self showWithQuery:nil captureSelection:YES];
}

-(void)showWithQuery:(nullable NSString*)query captureSelection:(BOOL)captureSelection {
    if (sTypingBoundary) sTypingBoundary();

    // Update dark/light backing layer color cleanly when opening
    _veilView.layer.backgroundColor = VeilColor().CGColor;
    _catalogItems = [_service allDictionaries];

    BOOL hasDicts = [_service hasInstalledDictionary];
    [self setShowingManager:!hasDicts];
    [self rebuildFilterPills];

    if (query.length > 0) {
        _searchField.stringValue = query;
        _clearButton.hidden = NO;
        [self setShowingManager:NO];
        [self reloadResultsAndSelectFirst:YES];
        [self presentPanel];
    } else if (captureSelection && hasDicts) {
        NSRunningApplication* front = [NSWorkspace sharedWorkspace].frontmostApplication;
        NSString* prefill = [self normalizedWordFromText:_searchField.stringValue];
        _searchField.stringValue = prefill;
        _clearButton.hidden = (prefill.length == 0);
        [self reloadResultsAndSelectFirst:YES];
        [self presentPanel];
        __weak DictionaryPalette* weakSelf = self;
        [AISelection readSelectionOfApplication:front allowCopy:NO completion:^(NSString* selected) {
            DictionaryPalette* strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.panel.visible) return;
            NSString* word = [strongSelf normalizedWordFromText:selected];
            if (word.length > 0 && ![word isEqualToString:strongSelf->_searchField.stringValue]) {
                strongSelf->_searchField.stringValue = word;
                strongSelf->_clearButton.hidden = NO;
                [strongSelf reloadResultsAndSelectFirst:YES];
            }
        }];
    } else {
        [self reloadResultsAndSelectFirst:YES];
        [self presentPanel];
    }
}

-(NSString*)normalizedWordFromText:(NSString*)text {
    if (text.length == 0) return @"";
    NSString* t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // Take only the first line if a multi-line selection was captured
    NSRange nl = [t rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
    if (nl.location != NSNotFound)
        t = [[t substringToIndex:nl.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length > 80)
        t = [t substringToIndex:80];
    return t;
}

-(void)presentPanel {
    NSPoint mouse = [NSEvent mouseLocation];
    NSScreen* screen = [NSScreen mainScreen];
    for (NSScreen* s in [NSScreen screens]) {
        if (NSPointInRect(mouse, s.frame)) { screen = s; break; }
    }
    NSRect vf = screen ? screen.visibleFrame : NSMakeRect(0, 0, 1280, 800);
    CGFloat x = vf.origin.x + round((vf.size.width - kPanelWidth) / 2);
    CGFloat y = vf.origin.y + round(vf.size.height * 0.58 - kPanelHeight / 2);
    if (y + kPanelHeight > NSMaxY(vf) - 16) y = NSMaxY(vf) - kPanelHeight - 16;
    if (y < vf.origin.y + 16) y = vf.origin.y + 16;
    [_panel setFrame:NSMakeRect(x, y, kPanelWidth, kPanelHeight) display:YES];

    BOOL reduceMotion = [NSWorkspace sharedWorkspace].accessibilityDisplayShouldReduceMotion;
    if (!reduceMotion && !_panel.visible) {
        _panel.alphaValue = 0.0;
        [_panel makeKeyAndOrderFront:nil];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
            ctx.duration = 0.12;
            _panel.animator.alphaValue = 1.0;
        } completionHandler:nil];
    } else {
        _panel.alphaValue = 1.0;
        [_panel makeKeyAndOrderFront:nil];
    }

    if (!_showingManager) {
        [_panel makeFirstResponder:_searchField];
        if (_searchField.stringValue.length > 0)
            [_searchField selectText:nil];
    }
}

-(void)hide {
    if (_closing || !_panel.visible) return;
    _closing = YES;
    [[WordSpeaker shared] stop];
    [_panel orderOut:nil];
    _closing = NO;
}

-(void)windowDidResignKey:(NSNotification*)notification {
    if (_openingFileDialog || _closing)
        return;
    [self hide];
}

-(void)setShowingManager:(BOOL)showingManager {
    _showingManager = showingManager;
    [self syncModeUI];
    [self layoutViews];
    if (!showingManager && _panel.visible)
        [_panel makeFirstResponder:_searchField];
}

-(void)syncModeUI {
    _searchIcon.hidden = _showingManager;
    _searchField.hidden = _showingManager;
    _clearButton.hidden = _showingManager || (_searchField.stringValue.length == 0);
    _managerTitleLabel.hidden = !_showingManager;
    _lookupContainer.hidden = _showingManager;
    _managerContainer.hidden = !_showingManager;

    BOOL hasDicts = [_service hasInstalledDictionary];
    _backToLookupButton.hidden = !hasDicts;
    [_managerToggleButton setTitle:_showingManager ? @"Tra cứu" : @"Bộ từ điển"];
    VOKSetButtonSymbol(_managerToggleButton, _showingManager ? @"magnifyingglass" : @"books.vertical", 12);

    if (_showingManager) {
        [_catalogTable reloadData];
        [self updateDownloadSelectedButton];
        _footerRightLabel.stringValue = @"Esc Đóng · Hỗ trợ StarDict .zip / .ifo";
    } else {
        _footerRightLabel.stringValue = @"↑↓ Chọn từ · ⌘P Phát âm · ⏎ Chép nghĩa · Esc Đóng";
    }
    [self updateFooterStatus];
}

-(void)updateFooterStatus {
    NSArray<VOKDictionaryCatalogItem*>* installed = [_service installedDictionaries];
    NSUInteger activeCount = 0;
    uint64_t totalEntries = 0;
    for (VOKDictionaryCatalogItem* item in installed) {
        if (item.enabled) {
            activeCount++;
            totalEntries += item.headwordCount;
        }
    }
    VOKDictionaryCatalogItem* downloadingItem = nil;
    for (VOKDictionaryCatalogItem* item in _catalogItems) {
        if (item.downloading) { downloadingItem = item; break; }
    }
    if (downloadingItem != nil) {
        _footerLeftLabel.stringValue = [NSString stringWithFormat:@"%@: %@", downloadingItem.shortName, downloadingItem.statusText];
    } else if (activeCount == 0) {
        _footerLeftLabel.stringValue = @"Chưa bật bộ từ điển nào — hãy tải hoặc bật ít nhất 1 bộ.";
    } else {
        NSNumberFormatter* fmt = [[NSNumberFormatter alloc] init];
        fmt.numberStyle = NSNumberFormatterDecimalStyle;
        NSString* numStr = [fmt stringFromNumber:@(totalEntries)];
        _footerLeftLabel.stringValue = [NSString stringWithFormat:@"%lu bộ từ điển đang bật · %@ mục từ",
                                        (unsigned long)activeCount, numStr ?: @"0"];
    }
}

-(void)rebuildFilterPills {
    for (NSView* sub in [_filterStack.arrangedSubviews copy]) {
        [_filterStack removeArrangedSubview:sub];
        [sub removeFromSuperview];
    }
    NSArray<VOKDictionaryCatalogItem*>* installed = [_service installedDictionaries];
    BOOL allSelected = (_selectedFilterDictId == nil);
    [_filterStack addArrangedSubview:[self makePillWithTitle:@"Tất cả" dictId:nil active:allSelected]];

    BOOL foundSelected = NO;
    for (VOKDictionaryCatalogItem* item in installed) {
        if (!item.enabled) continue;
        BOOL active = [_selectedFilterDictId isEqualToString:item.dictId];
        if (active) foundSelected = YES;
        [_filterStack addArrangedSubview:[self makePillWithTitle:item.shortName dictId:item.dictId active:active]];
    }
    if (_selectedFilterDictId != nil && !foundSelected) {
        _selectedFilterDictId = nil;
        [self rebuildFilterPills];
    }
}

-(NSButton*)makePillWithTitle:(NSString*)title dictId:(nullable NSString*)dictId active:(BOOL)active {
    NSButton* btn = [NSButton buttonWithTitle:title target:self action:@selector(filterPillPressed:)];
    btn.bezelStyle = NSBezelStyleRecessed;
    btn.buttonType = NSButtonTypePushOnPushOff;
    btn.state = active ? NSControlStateValueOn : NSControlStateValueOff;
    btn.font = [NSFont systemFontOfSize:11.5 weight:active ? NSFontWeightSemibold : NSFontWeightRegular];
    btn.identifier = dictId ?: @"";
    [btn setAccessibilityLabel:[NSString stringWithFormat:@"Lọc theo %@", title]];
    return btn;
}

-(void)selectFilterDictId:(nullable NSString*)dictId {
    _selectedFilterDictId = dictId.length > 0 ? [dictId copy] : nil;
    [self rebuildFilterPills];
    [self reloadResultsAndSelectFirst:YES];
}

#pragma mark - Search & Definition Rendering

-(void)reloadResultsAndSelectFirst:(BOOL)selectFirst {
    NSString* query = _searchField.stringValue ?: @"";
    _searchGeneration++;
    NSUInteger gen = _searchGeneration;

    if (![_service hasInstalledDictionary]) {
        _hits = @[];
        [_resultsTable reloadData];
        [self showEmptyStateWithTitle:@"Chưa có bộ từ điển nào"
                                 hint:@"Chọn nút Bộ từ điển để tải từ điển Anh–Việt, Việt–Anh miễn phí hoặc nhập file StarDict."
                           showButton:YES];
        return;
    }

    // Immediate lookup on service (sub-ms mmap search); async guard keeps UI smooth on fast typing
    NSArray<VOKDictionarySearchHit*>* hits = [_service search:query filterDictId:_selectedFilterDictId maxResults:80];
    if (gen != _searchGeneration) return;
    _hits = hits;
    [_resultsTable reloadData];

    if (hits.count > 0) {
        NSInteger target = selectFirst ? 0 : MIN(_selectedRow, (NSInteger)hits.count - 1);
        if (target < 0) target = 0;
        _selectedRow = target;
        [_resultsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)target] byExtendingSelection:NO];
        [_resultsTable scrollRowToVisible:(NSUInteger)target];
        [self displayHitAtRow:target];
    } else {
        _selectedRow = -1;
        _currentDefinitions = @[];
        _definitionView.string = @"";
        if (query.length > 0) {
            [self showEmptyStateWithTitle:[NSString stringWithFormat:@"Không tìm thấy “%@”", query]
                                     hint:@"Kiểm tra chính tả, thử gõ không dấu hoặc tải thêm bộ từ điển ngôn ngữ khác."
                               showButton:YES];
        } else {
            [self showEmptyStateWithTitle:@"Sẵn sàng tra từ điển"
                                     hint:@"Nhập từ cần tra vào ô phía trên để xem giải nghĩa ngay lập tức."
                               showButton:NO];
        }
    }
}

//The speaker is for the headword when a dictionary that has it is English (or has no language): "hello" from an English-Vietnamese
//dictionary, not "ba" from a Vietnamese-English one. What was being read belongs to the word that is no longer shown.
-(void)updateSpeakerForHit:(VOKDictionarySearchHit*)hit definitions:(NSArray<VOKDictionaryDefinition*>*)defs {
    [[WordSpeaker shared] stop];
    NSMutableArray<NSString*>* langs = [NSMutableArray array];
    for (VOKDictionaryDefinition* def in defs) {
        NSString* lang = @"";
        for (VOKDictionaryCatalogItem* item in _catalogItems) {
            if ([item.dictId isEqualToString:def.dictId]) {
                lang = item.sourceLang ?: @"";
                break;
            }
        }
        [langs addObject:lang];
    }
    _speakText = [WordSpeaker textToSpeakForHeadword:hit.headword sourceLangs:langs];
    _speakButton.hidden = (_speakText.length == 0);
}

-(void)showEmptyStateWithTitle:(NSString*)title hint:(NSString*)hint showButton:(BOOL)showButton {
    [[WordSpeaker shared] stop];
    _speakText = nil;
    _speakButton.hidden = YES;
    _defActionBar.hidden = YES;
    _defScroll.hidden = YES;
    _emptyOverlay.hidden = NO;
    _emptyTitle.stringValue = title ?: @"";
    _emptyHint.stringValue = hint ?: @"";
    _emptyActionButton.hidden = !showButton;
}

-(void)displayHitAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_hits.count) {
        [self showEmptyStateWithTitle:@"Chọn từ bên trái" hint:@"Nhấp hoặc dùng phím ↑ ↓ để xem giải nghĩa." showButton:NO];
        return;
    }
    _selectedRow = row;
    VOKDictionarySearchHit* hit = _hits[(NSUInteger)row];
    NSArray<VOKDictionaryDefinition*>* defs = [_service definitionsForHit:hit filterDictId:_selectedFilterDictId];
    _currentDefinitions = defs;

    if (defs.count == 0) {
        [self showEmptyStateWithTitle:hit.headword hint:@"Không đọc được mục từ từ bộ từ điển này." showButton:NO];
        return;
    }

    _emptyOverlay.hidden = YES;
    _defActionBar.hidden = NO;
    _defScroll.hidden = NO;
    _defSummaryLabel.stringValue = defs.count == 1
        ? defs[0].dictName
        : [NSString stringWithFormat:@"Khớp ở %lu bộ từ điển", (unsigned long)defs.count];
    [_copyDefButton setTitle:@"Sao chép nghĩa"];
    [self updateSpeakerForHit:hit definitions:defs];

    [_definitionView.textStorage setAttributedString:[self renderedDefinitions:defs forHit:hit]];
    [_definitionView scrollToBeginningOfDocument:nil];
}

#pragma mark - Rendering an entry

//An entry as the Dictionary app of the Mac sets it: the headword large, the phonetic under it, the part of speech in bold italic, the senses
//numbered with a hanging indent (the text lines up after the number, not under it), examples in italic, idioms after a ▸, the field a group
//of senses belongs to as a small heading. The system font, the colours of the system: light and dark follow by themselves.
static const CGFloat kNumberColumn = 24;

static NSFont* ItalicFont(NSFont* font) {
    return [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSItalicFontMask] ?: font;
}

static NSParagraphStyle* HangingStyle(CGFloat first, CGFloat head, CGFloat before, CGFloat after, BOOL withTab) {
    NSMutableParagraphStyle* p = [[NSMutableParagraphStyle alloc] init];
    p.firstLineHeadIndent = first;
    p.headIndent = head;
    p.paragraphSpacingBefore = before;
    p.paragraphSpacing = after;
    p.lineSpacing = 2.5;
    if (withTab)
        p.tabStops = @[[[NSTextTab alloc] initWithType:NSLeftTabStopType location:head]];
    p.defaultTabInterval = head > 0 ? head : 28;
    return p;
}

-(NSAttributedString*)renderedDefinitions:(NSArray<VOKDictionaryDefinition*>*)defs forHit:(VOKDictionarySearchHit*)hit {
    NSMutableAttributedString* out = [[NSMutableAttributedString alloc] init];
    NSColor* primary = PrimaryTextColor();
    NSColor* secondary = SecondaryTextColor();

    void (^add)(NSString*, NSFont*, NSColor*, NSParagraphStyle*) = ^(NSString* text, NSFont* font, NSColor* color, NSParagraphStyle* style) {
        if (text.length == 0) return;
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{
            NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style}]];
    };
    NSFont* body = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];

    // headword banner
    add([SafeDisplayText(hit.headword) stringByAppendingString:@"\n"], [NSFont systemFontOfSize:26 weight:NSFontWeightBold], primary,
        HangingStyle(0, 0, 0, 2, NO));
    if (hit.subtitle.length > 0) {
        NSString* cleanSub = [hit.subtitle stringByReplacingOccurrencesOfString:@"<- " withString:@"Từ gốc cho dạng: "];
        add([cleanSub stringByAppendingString:@"\n"], [NSFont systemFontOfSize:12 weight:NSFontWeightMedium], secondary, HangingStyle(0, 0, 0, 6, NO));
    }

    for (NSUInteger i = 0; i < defs.count; ++i) {
        VOKDictionaryDefinition* sec = defs[i];

        // the dictionary this part comes from: its kind of translation in the accent colour, its name quiet
        CGFloat before = (i == 0) ? 10 : 22;
        if (sec.badge.length > 0)
            add([sec.badge stringByAppendingString:@"  "], [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold], NSColor.controlAccentColor,
                HangingStyle(0, 0, before, 6, NO));
        NSString* name = sec.dictName;
        if (sec.matchedVia.length > 0)
            name = [name stringByAppendingFormat:@"  (qua “%@”)", sec.matchedVia];
        add([name stringByAppendingString:@"\n"], [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold], secondary,
            HangingStyle(0, 0, sec.badge.length > 0 ? 0 : before, 6, NO));

        CGFloat indent = 0;     // where the text of the sense that is being written starts: examples and notes go under it
        BOOL first = YES;
        for (VOKDictionaryFormattedLine* line in sec.lines) {
            switch (line.kind) {
                case VOKDictionaryBlockKindHeadword:
                    indent = 0;
                    add([line.text stringByAppendingString:@"\n"], [NSFont systemFontOfSize:first ? 20 : 17 weight:NSFontWeightSemibold], primary,
                        HangingStyle(0, 0, first ? 0 : 14, 2, NO));
                    break;
                case VOKDictionaryBlockKindPhonetic:
                    add([line.text stringByAppendingString:@"\n"], [NSFont systemFontOfSize:14 weight:NSFontWeightRegular], secondary,
                        HangingStyle(0, 0, 0, 4, NO));
                    break;
                case VOKDictionaryBlockKindPartOfSpeech: {
                    indent = 0;
                    NSFont* pos = ItalicFont([NSFont systemFontOfSize:13.5 weight:NSFontWeightBold]);
                    NSParagraphStyle* style = HangingStyle(0, 0, 12, 4, NO);
                    add(line.text, pos, primary, style);
                    if (line.secondary.length > 0)
                        add([@"  " stringByAppendingString:line.secondary], [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular], secondary, style);
                    add(@"\n", pos, primary, style);
                    break;
                }
                case VOKDictionaryBlockKindSection:
                    indent = 0;
                    add([line.text.uppercaseString stringByAppendingString:@"\n"], [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold], secondary,
                        HangingStyle(0, 0, 14, 3, NO));
                    break;
                case VOKDictionaryBlockKindSense: {
                    BOOL numbered = line.marker.length > 0;
                    indent = numbered ? kNumberColumn : 0;
                    NSParagraphStyle* style = HangingStyle(0, indent, 6, 2, numbered);
                    if (numbered)
                        add([line.marker stringByAppendingString:@"\t"], [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold], secondary, style);
                    add([line.text stringByAppendingString:@"\n"], body, primary, style);
                    break;
                }
                case VOKDictionaryBlockKindSubSense: {
                    BOOL numbered = line.marker.length > 0;
                    CGFloat head = indent + kNumberColumn - 4;
                    NSParagraphStyle* style = HangingStyle(indent, numbered ? head : indent, 3, 2, numbered);
                    if (numbered)
                        add([line.marker stringByAppendingString:@"\t"], [NSFont monospacedDigitSystemFontOfSize:12.5 weight:NSFontWeightMedium], secondary, style);
                    add([line.text stringByAppendingString:@"\n"], [NSFont systemFontOfSize:13.5 weight:NSFontWeightRegular], primary, style);
                    break;
                }
                case VOKDictionaryBlockKindExample: {
                    NSParagraphStyle* style = HangingStyle(indent, indent, 2, 2, NO);
                    NSFont* base = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
                    add([NSString stringWithFormat:@"“%@”", line.text], ItalicFont(base), secondary, style);
                    if (line.secondary.length > 0)
                        add([@"  " stringByAppendingString:line.secondary], base, primary, style);
                    add(@"\n", base, primary, style);
                    break;
                }
                case VOKDictionaryBlockKindIdiom: {
                    NSParagraphStyle* style = HangingStyle(0, 14, 10, 2, NO);
                    add(@"▸ ", [NSFont systemFontOfSize:12 weight:NSFontWeightRegular], secondary, style);
                    add(line.text, [NSFont systemFontOfSize:13.5 weight:NSFontWeightSemibold], primary, style);
                    if (line.secondary.length > 0)
                        add([@"  " stringByAppendingString:line.secondary], [NSFont systemFontOfSize:13.5 weight:NSFontWeightRegular], primary, style);
                    add(@"\n", body, primary, style);
                    indent = 14;
                    break;
                }
                case VOKDictionaryBlockKindNote:
                    add([line.text stringByAppendingString:@"\n"], [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular], secondary,
                        HangingStyle(indent, indent, 3, 2, NO));
                    break;
                case VOKDictionaryBlockKindPlain:
                    add([line.text stringByAppendingString:@"\n"], [NSFont systemFontOfSize:13.5 weight:NSFontWeightRegular], primary,
                        HangingStyle(0, 0, 4, 2, NO));
                    break;
            }
            first = NO;
        }
    }
    return out;
}

#pragma mark - Notifications & Actions

-(void)serviceDidUpdate:(NSNotification*)note {
    _catalogItems = [_service allDictionaries];
    [self rebuildFilterPills];
    [self updateFooterStatus];
    if (_showingManager) {
        [_catalogTable reloadData];
        [self updateDownloadSelectedButton];
        _backToLookupButton.hidden = ![_service hasInstalledDictionary];
    } else {
        [self reloadResultsAndSelectFirst:(_selectedRow < 0)];
    }
}

-(void)handleEscape {
    if (!_showingManager && _searchField.stringValue.length > 0) {
        _searchField.stringValue = @"";
        _clearButton.hidden = YES;
        [self reloadResultsAndSelectFirst:YES];
        [_panel makeFirstResponder:_searchField];
        return;
    }
    if (_showingManager && [_service hasInstalledDictionary]) {
        [self setShowingManager:NO];
        return;
    }
    [self hide];
}

-(void)closePressed:(id)sender { [self hide]; }

-(void)clearSearchPressed:(id)sender {
    _searchField.stringValue = @"";
    _clearButton.hidden = YES;
    [self reloadResultsAndSelectFirst:YES];
    [_panel makeFirstResponder:_searchField];
}

-(void)searchReturnPressed:(id)sender {
    [self copyDefinitionPressed:nil];
}

-(void)toggleManagerPressed:(id)sender {
    [self setShowingManager:!_showingManager];
}

-(void)openManagerFromEmpty:(id)sender {
    [self setShowingManager:YES];
}

-(void)filterPillPressed:(NSButton*)sender {
    [self selectFilterDictId:sender.identifier.length > 0 ? sender.identifier : nil];
}

-(void)speakPressed:(id)sender {
    [self speakCurrentWord];
}

//Reads the headword that is shown, when it is an English word. A Mac without an English voice says so in the footer.
-(void)speakCurrentWord {
    if (_speakText.length == 0 || _showingManager)
        return;
    if (![[WordSpeaker shared] speak:_speakText])
        _footerLeftLabel.stringValue = @"Chưa có giọng đọc tiếng Anh · Cài ở Cài đặt › Trợ năng";
}

-(void)copyDefinitionPressed:(id)sender {
    NSString* text = _definitionView.string;
    if (text.length == 0) return;
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
    [_copyDefButton setTitle:@"Đã chép"];
}

-(void)downloadSelectedPressed:(id)sender {
    NSMutableArray<NSString*>* ids = [NSMutableArray array];
    for (VOKDictionaryCatalogItem* item in _catalogItems) {
        if (!item.installed && !item.downloading && [_checkedIDs containsObject:item.dictId])
            [ids addObject:item.dictId];
    }
    if (ids.count > 0)
        [_service downloadDictionariesWithIDs:ids];
}

-(void)updateDownloadSelectedButton {
    NSUInteger count = 0;
    for (VOKDictionaryCatalogItem* item in _catalogItems) {
        if (!item.installed && !item.downloading && [_checkedIDs containsObject:item.dictId])
            count++;
    }
    _downloadSelectedButton.enabled = (count > 0);
    _downloadSelectedButton.title = count > 0
        ? [NSString stringWithFormat:@"Tải %lu bộ đã chọn", (unsigned long)count]
        : @"Chọn bộ để tải";
}

-(void)importLocalPressed:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.title = @"Chọn bộ từ điển StarDict (.zip, .ifo hoặc thư mục)";
    panel.message = @"Hỗ trợ tệp nén .stardict.zip, tệp .ifo (cùng thư mục chứa .idx/.dict.dz) hoặc văn bản FVDP .txt.";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;

    _openingFileDialog = YES;
    NSModalResponse response = [panel runModal];
    _openingFileDialog = NO;
    [_panel makeKeyAndOrderFront:nil];
    if (response != NSModalResponseOK || panel.URL == nil)
        return;

    _footerLeftLabel.stringValue = @"Đang nhập & lập chỉ mục từ điển từ máy…";
    [_service importLocalURL:panel.URL completion:^(VOKDictionaryCatalogItem* item, NSError* error) {
        if (error != nil) {
            NSAlert* alert = [[NSAlert alloc] init];
            alert.messageText = @"Không nhập được từ điển";
            alert.informativeText = error.localizedDescription ?: @"Tệp không đúng định dạng StarDict.";
            [alert runModal];
            [self updateFooterStatus];
        } else if (item != nil) {
            _footerLeftLabel.stringValue = [NSString stringWithFormat:@"Đã nhập “%@” (%llu mục từ)",
                                            item.name, item.headwordCount];
        }
    }];
}

#pragma mark - TextField Delegate & Keyboard Navigation

-(void)controlTextDidChange:(NSNotification*)obj {
    if (obj.object != _searchField) return;
    _clearButton.hidden = (_searchField.stringValue.length == 0);
    [self reloadResultsAndSelectFirst:YES];
}

-(BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
    if (control != _searchField) return NO;
    if (commandSelector == @selector(moveDown:)) {
        if (_hits.count > 0) {
            NSInteger next = MIN((NSInteger)_hits.count - 1, _selectedRow + 1);
            [_resultsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)next] byExtendingSelection:NO];
            [_resultsTable scrollRowToVisible:(NSUInteger)next];
            [self displayHitAtRow:next];
        }
        return YES;
    }
    if (commandSelector == @selector(moveUp:)) {
        if (_hits.count > 0) {
            NSInteger prev = MAX(0, _selectedRow - 1);
            [_resultsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)prev] byExtendingSelection:NO];
            [_resultsTable scrollRowToVisible:(NSUInteger)prev];
            [self displayHitAtRow:prev];
        }
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self handleEscape];
        return YES;
    }
    return NO;
}

#pragma mark - TableView DataSource & Delegate

-(NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    if (tableView == _resultsTable) return (NSInteger)_hits.count;
    if (tableView == _catalogTable) return (NSInteger)_catalogItems.count;
    return 0;
}

-(NSTableRowView*)tableView:(NSTableView*)tableView rowViewForRow:(NSInteger)row {
    if (tableView == _resultsTable)
        return [[VOKDictRowView alloc] initWithFrame:NSZeroRect];
    return [[NSTableRowView alloc] initWithFrame:NSZeroRect];
}

-(void)tableViewSelectionDidChange:(NSNotification*)notification {
    if (notification.object == _resultsTable) {
        NSInteger row = _resultsTable.selectedRow;
        if (row >= 0)
            [self displayHitAtRow:row];
    }
}

-(NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    if (tableView == _resultsTable)
        return [self resultCellViewForRow:row];
    return [self catalogCellViewForRow:row];
}

-(NSView*)resultCellViewForRow:(NSInteger)row {
    VOKDictionarySearchHit* hit = _hits[(NSUInteger)row];
    NSView* cell = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kLeftColWidth, 46)];

    NSTextField* title = DictLabel(hit.headword, 13.5, hit.isExact ? NSFontWeightSemibold : NSFontWeightMedium, PrimaryTextColor());
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    title.maximumNumberOfLines = 1;

    NSView* badge = DictBadge(hit.badgesSummary, hit.isExact ? [NSColor systemBlueColor] : SecondaryTextColor(),
                              BadgeBackgroundColor(hit.isExact), 42, 92, 0, hit.subtitle.length > 0 ? 22 : 14);
    CGFloat badgeW = NSWidth(badge.frame);
    badge.frame = NSMakeRect(kLeftColWidth - 14 - badgeW, NSMinY(badge.frame), badgeW, kBadgeHeight);
    title.frame = NSMakeRect(16, hit.subtitle.length > 0 ? 22 : 13, kLeftColWidth - 38 - badgeW, 20);
    [cell addSubview:title];
    if (hit.badgesSummary.length > 0)
        [cell addSubview:badge];

    if (hit.subtitle.length > 0) {
        NSTextField* sub = DictLabel(hit.subtitle, 10.5, NSFontWeightRegular, SecondaryTextColor());
        sub.lineBreakMode = NSLineBreakByTruncatingTail;
        sub.maximumNumberOfLines = 1;
        sub.frame = NSMakeRect(16, 5, kLeftColWidth - 30, 15);
        [cell addSubview:sub];
    }
    return cell;
}

-(NSView*)catalogCellViewForRow:(NSInteger)row {
    VOKDictionaryCatalogItem* item = _catalogItems[(NSUInteger)row];
    CGFloat cw = kPanelWidth;
    NSView* cell = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, cw, 76)];

    // Checkbox (if not installed) or Enable NSSwitch (if installed)
    if (item.installed) {
        NSSwitch* sw = [[NSSwitch alloc] initWithFrame:NSMakeRect(14, 26, 38, 22)];
        sw.state = item.enabled ? NSControlStateValueOn : NSControlStateValueOff;
        sw.identifier = item.dictId;
        sw.target = self;
        sw.action = @selector(toggleDictEnabledPressed:);
        [sw setAccessibilityLabel:[NSString stringWithFormat:@"Bật hoặc tắt %@", item.name]];
        [cell addSubview:sw];
    } else {
        NSButton* cb = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxPressed:)];
        cb.frame = NSMakeRect(18, 28, 22, 22);
        cb.state = [_checkedIDs containsObject:item.dictId] ? NSControlStateValueOn : NSControlStateValueOff;
        cb.enabled = !item.downloading;
        cb.identifier = item.dictId;
        [cb setAccessibilityLabel:[NSString stringWithFormat:@"Chọn tải %@", item.name]];
        [cell addSubview:cb];
    }

    // Badge
    BOOL accent = item.priority <= 30;
    NSView* badge = DictBadge(item.badge.length > 0 ? item.badge : @"DICT", accent ? [NSColor systemBlueColor] : SecondaryTextColor(),
                              BadgeBackgroundColor(accent), 54, 54, 60, 44);
    [cell addSubview:badge];

    // Title + meta line
    NSTextField* title = DictLabel(item.name, 13.5, NSFontWeightSemibold, PrimaryTextColor());
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    title.maximumNumberOfLines = 1;
    CGFloat maxTitleW = cw - 280;
    CGFloat titleW = MIN(maxTitleW, ceil([item.name sizeWithAttributes:@{NSFontAttributeName: title.font}].width) + 4);
    title.frame = NSMakeRect(122, 43, titleW, 20);
    [cell addSubview:title];

    if (item.recommended) {
        NSView* rec = DictBadge(@"Khuyên dùng", [NSColor systemGreenColor], BadgeTintColor([NSColor systemGreenColor]), 0, 110,
                                122 + titleW + 8, 44);
        if (NSMaxX(rec.frame) < cw - 140)
            [cell addSubview:rec];
    }

    // Right action button (Tải / Hủy / Xóa)
    NSButton* actBtn = [NSButton buttonWithTitle:@"" target:self action:@selector(catalogRowActionPressed:)];
    actBtn.bezelStyle = NSBezelStyleRounded;
    actBtn.controlSize = NSControlSizeSmall;
    actBtn.identifier = item.dictId;
    if (item.downloading) {
        actBtn.title = @"Hủy";
    } else if (item.installed) {
        actBtn.title = @"Xóa";
        VOKSetButtonSymbol(actBtn, @"trash", 11);
    } else {
        actBtn.title = item.errorText.length > 0 ? @"Thử lại" : [NSString stringWithFormat:@"Tải (%@)", item.downloadSizeText];
    }
    CGFloat btnW = item.downloading ? 68 : (item.installed ? 72 : 114);
    actBtn.frame = NSMakeRect(cw - btnW - 14, 24, btnW, 24);
    [cell addSubview:actBtn];

    // Second line: progress bar or description + license/size
    if (item.downloading) {
        NSProgressIndicator* bar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(60, 18, cw - 200, 12)];
        bar.indeterminate = (item.downloadProgress <= 0.0);
        bar.minValue = 0;
        bar.maxValue = 1;
        bar.doubleValue = item.downloadProgress;
        if (bar.indeterminate) [bar startAnimation:nil];
        [cell addSubview:bar];

        NSTextField* status = DictLabel(item.statusText, 11, NSFontWeightRegular, SecondaryTextColor());
        status.frame = NSMakeRect(60, 2, cw - 200, 15);
        [cell addSubview:status];
    } else {
        NSString* info = item.errorText.length > 0
            ? item.errorText
            : [NSString stringWithFormat:@"%@ · %@ · %@", item.downloadSizeText, item.license, item.descriptionText];
        NSColor* infoColor = item.errorText.length > 0 ? [NSColor systemRedColor] : SecondaryTextColor();
        NSTextField* desc = DictLabel(info, 11.5, NSFontWeightRegular, infoColor);
        desc.lineBreakMode = NSLineBreakByTruncatingTail;
        desc.maximumNumberOfLines = 1;
        desc.frame = NSMakeRect(60, 14, cw - 196, 18);
        [cell addSubview:desc];
    }

    NSView* sep = VOKInsetSeparator(14);
    sep.frame = NSMakeRect(14, 0, cw - 28, 1);
    [cell addSubview:sep];
    return cell;
}

-(void)checkboxPressed:(NSButton*)sender {
    if (sender.state == NSControlStateValueOn)
        [_checkedIDs addObject:sender.identifier];
    else
        [_checkedIDs removeObject:sender.identifier];
    [self updateDownloadSelectedButton];
}

-(void)toggleDictEnabledPressed:(NSSwitch*)sender {
    [_service setDictionaryID:sender.identifier enabled:(sender.state == NSControlStateValueOn)];
}

-(void)catalogRowActionPressed:(NSButton*)sender {
    NSString* did = sender.identifier;
    for (VOKDictionaryCatalogItem* item in _catalogItems) {
        if (![item.dictId isEqualToString:did]) continue;
        if (item.downloading)
            [_service cancelDownloadForID:did];
        else if (item.installed)
            [_service removeDictionaryID:did];
        else
            [_service downloadDictionariesWithIDs:@[did]];
        break;
    }
}

@end
