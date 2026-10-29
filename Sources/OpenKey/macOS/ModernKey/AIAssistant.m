//
//  AIAssistant.m
//  VOpenKey
//

#import "AIAssistant.h"
#import "AIAgentCLI.h"
#import "AIKeychain.h"
#import "AIPresets.h"
#import "AILightbox.h"
#import "AIProgress.h"
#import "AIOllamaRuntime.h"
#import "AISelection.h"
#import "AISettings.h"
#import "VOKUI.h"

static const CGFloat kWidth = 620;
static const CGFloat kInset = 16;
static const CGFloat kCornerRadius = 14;
static const NSUInteger kMaxSelection = 30000;     //a whole document is not something to send by accident
static NSString* const kOutputPlaceholder = @"Câu trả lời của AI sẽ hiện ở đây.";

static void (^sBoundary)(void);
static void (^sOpenSettings)(void);
static BOOL sHasKeyboard;   //the window is the one that gets the keys: read for every key by the event tap, it must be cheap

#pragma mark - Views

//Takes the keyboard without making the application active; ⎋ goes to the assistant
@interface AIPanel : NSPanel
@property (nonatomic, copy) void (^onCancel)(void);
@end

@implementation AIPanel
-(BOOL)canBecomeKeyWindow { return YES; }
-(BOOL)canBecomeMainWindow { return NO; }
-(void)cancelOperation:(id)sender {
    if (self.onCancel != nil)
        self.onCancel();
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

//A text area: the ready-made text view in a scroll view (it wraps lines at the width of the view and follows its size), in the
//rounded card of the settings, whose colours follow light and dark. `placeholder` is written over it while it is empty.
static NSView* TextArea(CGFloat height, NSTextField* placeholder, NSTextView** textView) {
    NSScrollView* scroll = [NSTextView scrollableTextView];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    NSTextView* view = scroll.documentView;
    view.textContainerInset = NSMakeSize(6, 8);
    view.drawsBackground = NO;
    view.font = [NSFont systemFontOfSize:13];
    view.textColor = [NSColor labelColor];
    NSView* card = VOKCard(scroll);
    [card.heightAnchor constraintEqualToConstant:height].active = YES;

    placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:placeholder];
    [NSLayoutConstraint activateConstraints:@[
        [placeholder.topAnchor constraintEqualToAnchor:view.topAnchor constant:8],
        [placeholder.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:11],
        [placeholder.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-11],
    ]];
    *textView = view;
    return card;
}

#pragma mark - The assistant

@interface AIAssistant () <NSTextViewDelegate, NSWindowDelegate>
@end

@implementation AIAssistant {
    SnippetInserter* _inserter;
    AIPanel* _panel;
    NSVisualEffectView* _background;
    NSStackView* _stack;

    NSImageView* _icon;
    NSPopUpButton* _providerPopUp;
    NSPopUpButton* _modelPopUp;
    NSPopUpButton* _effortPopUp;
    NSTextField* _contextLabel;
    NSTextView* _input;
    NSTextField* _inputPlaceholder;
    NSView* _inputScroll;
    NSTextField* _infoLabel;
    NSButton* _actionButton;
    NSTextView* _output;
    AIShimmerLabel* _outputPlaceholder;
    AIGlowView* _glow;
    NSButton* _gearButton;
    NSButton* _speedButton;
    NSStackView* _presetStrip;              //the ready-made conversions under the box: a caption, then one button per preset
    NSArray<NSButton*>* _presetButtons;
    AIPreset* _activePreset;                //the one the next "Tạo" applies; cleared when the text is edited and when the window opens
    BOOL _inputHintShown;                   //the status line asks for a text: it goes as soon as one is typed
    NSButton* _imageButton;
    NSButton* _revealButton;
    NSButton* _saveImageButton;
    NSUInteger _copyFeedback;
    BOOL _copyConfirmed;
    NSImageView* _imageView;
    NSURL* _resultImageURL;                 //the picture that was made (a file in the folder of Codex), and its data as a PNG for the clipboard
    NSData* _resultImagePNG;
    BOOL _imageRequest;                     //the request that is going on, or the last one, was for a picture
    BOOL _canMakeImages;                    //the AI in use makes pictures (cached: it is asked at every piece of an answer)
    NSString* _progressNote;                //a message that stays while waiting (the Mac is busy, the local server starts)
    NSString* _slowLevelName;               //the thinking level of this request when it is above the lowest, nil otherwise
    NSView* _outputScroll;
    NSTextField* _statusLabel;
    NSButton* _settingsButton;
    NSTextField* _hintLabel;
    NSButton* _copyButton;
    NSButton* _insertButton;

    NSRunningApplication* _target;      //the application that had the keyboard, where the answer goes
    BOOL _hadSelection;
    BOOL _opening;                      //the selection is being read: a second press of the shortcut does nothing
    AIClient* _client;
    NSUInteger _askSerial;                  //changes whenever a request is cancelled, so that a start of the local server that ends later does nothing
    NSTimer* _progressTimer;                //for a program on this Mac, which can take a while before the first word: the seconds are shown
    NSDate* _askStarted;
    NSMutableSet<NSString*>* _modelsRequested;   //the programs whose list of models was asked this time the application runs (once is enough)
    AIAssistantState _state;
    NSMutableString* _result;
    AIProvider* _provider;
}

#pragma mark Entry points

+(AIAssistant*)shared {
    static AIAssistant* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AIAssistant alloc] initWithInserter:[SnippetInserter shared]]; });
    return instance;
}

+(BOOL)isVisible {
    return sHasKeyboard;
}

+(void)toggle {
    AIAssistant* assistant = [self shared];
    if (assistant->_panel.visible && assistant->_panel.keyWindow)
        [assistant hideAssistant];
    else if (assistant->_panel.visible)
        [assistant->_panel makeKeyAndOrderFront:nil]; //still open but the keyboard is elsewhere: bring it back
    else
        [self show];
}

+(void)show {
    [[self shared] showForFrontmostApplication];
}

+(void)hide {
    [[self shared] hideAssistant];
}

+(void)setTypingBoundaryHandler:(void (^)(void))handler {
    sBoundary = [handler copy];
}

+(void)setSettingsHandler:(void (^)(void))handler {
    sOpenSettings = [handler copy];
}

-(instancetype)initWithInserter:(SnippetInserter*)inserter {
    self = [super init];
    if (self) {
        _inserter = inserter;
        _result = [NSMutableString string];
        _modelsRequested = [NSMutableSet set];
        _slowHintDelay = 8;
    }
    return self;
}

-(NSPanel*)panel { [self buildIfNeeded]; return _panel; }
-(NSTextView*)inputView { [self buildIfNeeded]; return _input; }
-(NSTextView*)outputView { [self buildIfNeeded]; return _output; }
-(NSButton*)actionButton { [self buildIfNeeded]; return _actionButton; }
-(NSButton*)copyButton { [self buildIfNeeded]; return _copyButton; }
-(NSButton*)insertButton { [self buildIfNeeded]; return _insertButton; }
-(NSTextField*)statusLabel { [self buildIfNeeded]; return _statusLabel; }
-(NSTextField*)contextLabel { [self buildIfNeeded]; return _contextLabel; }
-(NSTextField*)infoLabel { [self buildIfNeeded]; return _infoLabel; }
-(NSPopUpButton*)providerPopUp { [self buildIfNeeded]; return _providerPopUp; }
-(NSPopUpButton*)modelPopUp { [self buildIfNeeded]; return _modelPopUp; }
-(NSPopUpButton*)effortPopUp { [self buildIfNeeded]; return _effortPopUp; }
-(NSButton*)settingsButton { [self buildIfNeeded]; return _settingsButton; }
-(NSButton*)openSettingsButton { [self buildIfNeeded]; return _gearButton; }
-(NSTextField*)progressLabel { [self buildIfNeeded]; return _outputPlaceholder; }
-(BOOL)glowing { return _glow.animating; }
-(NSButton*)speedButton { [self buildIfNeeded]; return _speedButton; }
-(NSButton*)imageButton { [self buildIfNeeded]; return _imageButton; }
-(NSButton*)revealButton { [self buildIfNeeded]; return _revealButton; }
-(NSButton*)saveImageButton { [self buildIfNeeded]; return _saveImageButton; }
-(BOOL)copyConfirmed { return _copyConfirmed; }
-(NSImageView*)imageView { [self buildIfNeeded]; return _imageView; }
-(NSURL*)resultImageURL { return _resultImageURL; }
-(AIAssistantState)state { return _state; }
-(NSString*)resultText { return [_result copy]; }

#pragma mark Building the window

-(NSTextField*)labelWithSize:(CGFloat)size color:(NSColor*)color {
    NSTextField* label = VOKLabel(@"", size, NSFontWeightRegular, color);
    label.selectable = NO;
    return label;
}

-(NSButton*)buttonWithTitle:(NSString*)title action:(SEL)action {
    NSButton* button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

-(void)buildIfNeeded {
    if (_panel != nil)
        return;
    _panel = [[AIPanel alloc] initWithContentRect:NSMakeRect(0, 0, kWidth, 500)
                                        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                          backing:NSBackingStoreBuffered defer:YES];
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
    _panel.title = @"Trợ lý AI";
    _panel.delegate = self;
    _panel.movableByWindowBackground = YES;
    __weak AIAssistant* weakSelf = self;
    _panel.onCancel = ^{ [weakSelf escape]; };

    _background = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, 500)];
    _background.material = NSVisualEffectMaterialPopover;
    _background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _background.state = NSVisualEffectStateActive;
    _background.maskImage = WindowMask();
    _panel.contentView = _background;

    //header: what it is, and which AI answers
    _icon = [NSImageView imageViewWithImage:VOKSymbol(@"sparkles", 15, NSFontWeightSemibold)];
    _icon.contentTintColor = [NSColor controlAccentColor];
    NSTextField* title = VOKLabel(@"Trợ lý AI", 13, NSFontWeightSemibold, nil);
    title.selectable = NO;
    _providerPopUp = [[NSPopUpButton alloc] init];
    _providerPopUp.controlSize = NSControlSizeSmall;
    _providerPopUp.font = [NSFont systemFontOfSize:11];
    _providerPopUp.target = self;
    _providerPopUp.action = @selector(providerChosen:);
    _providerPopUp.translatesAutoresizingMaskIntoConstraints = NO;
    [_providerPopUp setAccessibilityLabel:@"Nhà cung cấp AI"];
    //for a program on this Mac: which model, and how long it thinks; hidden for the services that have an address
    _modelPopUp = [[NSPopUpButton alloc] init];
    _modelPopUp.controlSize = NSControlSizeSmall;
    _modelPopUp.font = [NSFont systemFontOfSize:11];
    _modelPopUp.target = self;
    _modelPopUp.action = @selector(modelChosen:);
    _modelPopUp.translatesAutoresizingMaskIntoConstraints = NO;
    _modelPopUp.hidden = YES;
    [_modelPopUp setAccessibilityLabel:@"Model"];
    _effortPopUp = [[NSPopUpButton alloc] init];
    _effortPopUp.controlSize = NSControlSizeSmall;
    _effortPopUp.font = [NSFont systemFontOfSize:11];
    _effortPopUp.target = self;
    _effortPopUp.action = @selector(effortChosen:);
    _effortPopUp.translatesAutoresizingMaskIntoConstraints = NO;
    _effortPopUp.hidden = YES;
    [_effortPopUp setAccessibilityLabel:@"Mức suy nghĩ"];
    NSView* spacer1 = [[NSView alloc] init];
    [spacer1 setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    _gearButton = [NSButton buttonWithImage:VOKSymbol(@"gearshape", 13, NSFontWeightRegular) target:self action:@selector(openSettings:)];
    _gearButton.bordered = NO;
    _gearButton.contentTintColor = [NSColor secondaryLabelColor];
    _gearButton.toolTip = @"Mở Cài đặt AI";
    _gearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_gearButton setAccessibilityLabel:@"Mở Cài đặt AI"];
    NSStackView* header = [NSStackView stackViewWithViews:@[_icon, title, spacer1, _providerPopUp, _modelPopUp, _effortPopUp, _gearButton]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.spacing = 6;
    header.alignment = NSLayoutAttributeCenterY;

    //what was selected
    _contextLabel = [self labelWithSize:11 color:[NSColor secondaryLabelColor]];
    _contextLabel.hidden = YES;

    //the request
    _inputPlaceholder = VOKLabel(@"Bạn muốn viết gì? Ví dụ: “Viết email xin nghỉ phép ngày mai”. Hoặc dán một đoạn văn (hay chọn nó rồi bấm phím tắt) và bấm một kiểu chuyển đổi bên dưới: sửa lỗi, đổi giọng, dịch, làm thơ…",
                                 13, NSFontWeightRegular, [NSColor placeholderTextColor]);
    _inputPlaceholder.preferredMaxLayoutWidth = kWidth - 2 * kInset - 22;
    NSTextView* inputView = nil;
    _inputScroll = TextArea(130, _inputPlaceholder, &inputView);
    _input = inputView;
    _input.delegate = self;
    _input.allowsUndo = YES;
    _input.richText = NO;
    //typed back into other applications as it is: nothing may be "corrected"
    _input.automaticQuoteSubstitutionEnabled = NO;
    _input.automaticDashSubstitutionEnabled = NO;
    _input.automaticTextReplacementEnabled = NO;
    _input.automaticSpellingCorrectionEnabled = NO;
    _input.automaticLinkDetectionEnabled = NO;
    [_input setAccessibilityLabel:@"Yêu cầu"];

    _presetStrip = [self buildPresetStripWithWidth:kWidth - 2 * kInset];

    _infoLabel = [self labelWithSize:11 color:[NSColor secondaryLabelColor]];
    _infoLabel.lineBreakMode = NSLineBreakByTruncatingTail;       //a long line (the name of a program, its model, its level) is cut, the button stays
    _infoLabel.maximumNumberOfLines = 1;
    [_infoLabel setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
    _actionButton = [self buttonWithTitle:@"Tạo" action:@selector(actionPressed:)];
    NSView* spacer2 = [[NSView alloc] init];
    [spacer2 setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    _imageButton = [self buttonWithTitle:@"Tạo ảnh" action:@selector(imagePressed:)];
    VOKSetButtonSymbol(_imageButton, @"photo.badge.plus", 12);
    _imageButton.enabled = NO;
    [self setKeyEquivalent:@"\r" mask:NSEventModifierFlagCommand | NSEventModifierFlagOption forButton:_imageButton];
    NSStackView* askRow = [NSStackView stackViewWithViews:@[_infoLabel, spacer2, _imageButton, _actionButton]];
    askRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    askRow.alignment = NSLayoutAttributeCenterY;
    askRow.spacing = 8;

    //the answer
    _outputPlaceholder = [AIShimmerLabel wrappingLabelWithString:kOutputPlaceholder];
    _outputPlaceholder.font = [NSFont systemFontOfSize:13];
    _outputPlaceholder.textColor = [NSColor placeholderTextColor];
    _outputPlaceholder.selectable = NO;
    _outputPlaceholder.translatesAutoresizingMaskIntoConstraints = NO;
    _outputPlaceholder.preferredMaxLayoutWidth = kWidth - 2 * kInset - 22;
    NSTextView* outputView = nil;
    _outputScroll = TextArea(190, _outputPlaceholder, &outputView);
    //the picture, when a picture was asked for: it takes the place of the answer
    _imageView = [[NSImageView alloc] init];
    _imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _imageView.imageAlignment = NSImageAlignCenter;
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.hidden = YES;
    _imageView.toolTip = @"Bấm để xem ảnh lớn";
    [_imageView setAccessibilityLabel:@"Ảnh đã tạo"];
    [_imageView addGestureRecognizer:[[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(imageClicked:)]];
    [_outputScroll addSubview:_imageView];
    [NSLayoutConstraint activateConstraints:@[
        [_imageView.topAnchor constraintEqualToAnchor:_outputScroll.topAnchor constant:8],
        [_imageView.leadingAnchor constraintEqualToAnchor:_outputScroll.leadingAnchor constant:8],
        [_imageView.trailingAnchor constraintEqualToAnchor:_outputScroll.trailingAnchor constant:-8],
        [_imageView.bottomAnchor constraintEqualToAnchor:_outputScroll.bottomAnchor constant:-8],
    ]];
    //a light runs round the edge of the answer while it is awaited
    _glow = [[AIGlowView alloc] init];
    _glow.translatesAutoresizingMaskIntoConstraints = NO;
    [_outputScroll addSubview:_glow];
    [NSLayoutConstraint activateConstraints:@[
        [_glow.topAnchor constraintEqualToAnchor:_outputScroll.topAnchor],
        [_glow.leadingAnchor constraintEqualToAnchor:_outputScroll.leadingAnchor],
        [_glow.trailingAnchor constraintEqualToAnchor:_outputScroll.trailingAnchor],
        [_glow.bottomAnchor constraintEqualToAnchor:_outputScroll.bottomAnchor],
    ]];
    _output = outputView;
    _output.editable = NO;
    _output.selectable = YES;
    [_output setAccessibilityLabel:@"Kết quả"];

    _statusLabel = [self labelWithSize:11 color:[NSColor secondaryLabelColor]];
    _settingsButton = [self buttonWithTitle:@"Mở Cài đặt AI…" action:@selector(openSettings:)];
    _settingsButton.controlSize = NSControlSizeSmall;
    _settingsButton.hidden = YES;
    _speedButton = [self buttonWithTitle:@"Hỏi lại ở mức Thấp" action:@selector(askAgainFaster:)];
    _speedButton.controlSize = NSControlSizeSmall;
    _speedButton.toolTip = @"Dừng câu hỏi này và hỏi lại ở mức suy nghĩ thấp nhất của model, thường nhanh hơn nhiều.";
    _speedButton.hidden = YES;
    NSView* spacer3 = [[NSView alloc] init];
    [spacer3 setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    _revealButton = [self buttonWithTitle:@"Hiện ảnh" action:@selector(revealImage:)];
    _revealButton.controlSize = NSControlSizeSmall;
    _revealButton.toolTip = @"Hiện file ảnh trong Finder";
    _revealButton.hidden = YES;
    _saveImageButton = [self buttonWithTitle:@"Lưu" action:@selector(saveImagePressed:)];
    _saveImageButton.controlSize = NSControlSizeSmall;
    VOKSetButtonSymbol(_saveImageButton, @"square.and.arrow.down", 11);
    _saveImageButton.toolTip = @"Lưu ảnh vào thư mục Downloads";
    _saveImageButton.hidden = YES;
    NSStackView* statusRow = [NSStackView stackViewWithViews:@[_statusLabel, spacer3, _speedButton, _saveImageButton, _revealButton, _settingsButton]];
    statusRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    statusRow.alignment = NSLayoutAttributeCenterY;
    statusRow.spacing = 8;
    //the text may take what the button leaves
    [_statusLabel setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];

    //what to do with it
    _hintLabel = [self labelWithSize:10 color:[NSColor tertiaryLabelColor]];
    _hintLabel.stringValue = @"⌘↩ Tạo   ⌥⌘↩ Tạo ảnh   ⇧⌘↩ Chèn   ⇧⌘C Sao chép   esc Đóng";
    _copyButton = [self buttonWithTitle:@"Sao chép" action:@selector(copyPressed:)];
    _insertButton = [self buttonWithTitle:@"Chèn" action:@selector(insertPressed:)];
    NSView* spacer4 = [[NSView alloc] init];
    [spacer4 setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* bottom = [NSStackView stackViewWithViews:@[_hintLabel, spacer4, _copyButton, _insertButton]];
    bottom.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bottom.alignment = NSLayoutAttributeCenterY;
    bottom.spacing = 8;

    _stack = [NSStackView stackViewWithViews:@[header, _contextLabel, _inputScroll, _presetStrip, askRow, _outputScroll, statusRow, bottom]];
    _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stack.alignment = NSLayoutAttributeLeading;
    _stack.spacing = 10;
    _stack.edgeInsets = NSEdgeInsetsMake(kInset, kInset, kInset, kInset);
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_stack setCustomSpacing:6 afterView:header];
    for (NSView* view in _stack.arrangedSubviews)
        [view.widthAnchor constraintEqualToConstant:kWidth - 2 * kInset].active = YES;
    //labels that wrap need the width they wrap at, or their height is that of one line
    _contextLabel.preferredMaxLayoutWidth = kWidth - 2 * kInset;
    _statusLabel.preferredMaxLayoutWidth = kWidth - 2 * kInset - 150;
    [_background addSubview:_stack];
    [NSLayoutConstraint activateConstraints:@[
        [_stack.topAnchor constraintEqualToAnchor:_background.topAnchor],
        [_stack.leadingAnchor constraintEqualToAnchor:_background.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:_background.trailingAnchor],
        [_stack.widthAnchor constraintEqualToConstant:kWidth],
    ]];
    [self reloadProviders];
    [self updateInterface];
    [_stack layoutSubtreeIfNeeded];
    NSSize size = NSMakeSize(kWidth, _stack.fittingSize.height);
    [_panel setContentSize:size];
}

//The ready-made conversions: small buttons in rows that break where the width of the window ends (a stack view does not wrap by
//itself, and the width of the window never changes, so the rows are cut once, here). The one that was chosen is filled with the accent
//colour. A caption says what they are.
-(NSStackView*)buildPresetStripWithWidth:(CGFloat)width {
    const CGFloat gap = 6;
    //one line, not a wrapping label: a wrapping label has no width of its own and was laid out as narrow as one word
    NSTextField* caption = [NSTextField labelWithString:@"Chuyển đổi nhanh:"];
    caption.font = [NSFont systemFontOfSize:11];
    caption.textColor = [NSColor secondaryLabelColor];
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    NSMutableArray<NSButton*>* buttons = [NSMutableArray array];
    for (AIPreset* preset in [AIPresets all]) {
        NSButton* button = [NSButton buttonWithTitle:preset.title target:self action:@selector(presetPressed:)];
        button.bezelStyle = NSBezelStyleRounded;
        button.controlSize = NSControlSizeSmall;
        button.font = [NSFont systemFontOfSize:11];
        [button setButtonType:NSButtonTypePushOnPushOff];
        button.identifier = preset.identifier;
        button.toolTip = VOKTooltip(preset.summary);
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button setAccessibilityLabel:[@"Chuyển đổi: " stringByAppendingString:preset.title]];
        [button setAccessibilityHelp:preset.summary];
        [buttons addObject:button];
    }
    _presetButtons = buttons;

    //The width a view takes in a row is its intrinsic one (that of its alignment rect: the bezel and the shadow of a rounded button stand
    //outside it, and a stack view does not count them)
    CGFloat (^widthInRow)(NSView*) = ^CGFloat(NSView* view) { return ceil(view.intrinsicContentSize.width); };
    NSMutableArray<NSStackView*>* rows = [NSMutableArray array];
    NSMutableArray<NSView*>* line = [NSMutableArray arrayWithObject:caption];
    CGFloat used = widthInRow(caption);
    for (NSButton* button in buttons) {
        CGFloat need = widthInRow(button);
        if (line.count > 0 && used + gap + need > width) {
            [rows addObject:[NSStackView stackViewWithViews:line]];
            line = [NSMutableArray array];
            used = -gap;
        }
        [line addObject:button];
        used += gap + need;
    }
    if (line.count > 0)
        [rows addObject:[NSStackView stackViewWithViews:line]];
    for (NSStackView* row in rows) {
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeCenterY;
        row.spacing = gap;
    }
    NSStackView* strip = [NSStackView stackViewWithViews:rows];
    strip.orientation = NSUserInterfaceLayoutOrientationVertical;
    strip.alignment = NSLayoutAttributeLeading;
    strip.spacing = 4;
    return strip;
}

//A message that wraps changes the height of the window: it grows or shrinks downwards, the top stays where it is
-(void)resizeToFit {
    [_stack layoutSubtreeIfNeeded];
    CGFloat height = _stack.fittingSize.height;
    NSRect frame = _panel.frame;
    if (fabs(frame.size.height - height) < 1)
        return;
    CGFloat top = NSMaxY(frame);
    frame.size.height = height;
    frame.origin.y = top - height;
    [_panel setFrame:frame display:YES];
}

#pragma mark Opening and closing

-(NSScreen*)screenOfMouse {
    NSPoint mouse = [NSEvent mouseLocation];
    for (NSScreen* screen in [NSScreen screens])
        if (NSPointInRect(mouse, screen.frame))
            return screen;
    return [NSScreen mainScreen];
}

-(void)showForFrontmostApplication {
    if (_opening || _panel.visible)
        return;
    NSRunningApplication* front = [NSWorkspace sharedWorkspace].frontmostApplication;
    if (front.processIdentifier == [NSProcessInfo processInfo].processIdentifier)
        front = nil;
    _opening = YES;
    //the selection is read before the window opens: afterwards the keyboard is no longer in the application
    [AISelection readSelectionOfApplication:front allowCopy:vAICopySelection != 0 completion:^(NSString* text) {
        self->_opening = NO;
        [self presentWithSelection:text application:front];
    }];
}

-(void)presentWithSelection:(NSString*)selection application:(NSRunningApplication*)application {
    [self buildIfNeeded];
    if (_panel.visible)
        return;
    _target = application;
    if (sBoundary != nil)
        sBoundary();
    [self cancelRequest];
    [_result setString:@""];
    [self forgetText];
    _activePreset = nil;
    _statusLabel.stringValue = @"";
    _state = AIAssistantStateIdle;

    NSString* chosen = selection.length > 0 ? selection : nil;
    _hadSelection = chosen != nil;
    if (chosen != nil) {
        BOOL cut = chosen.length > kMaxSelection;
        if (cut)
            chosen = [chosen substringToIndex:kMaxSelection];
        _input.string = [@"\n\n" stringByAppendingString:chosen]; //the cursor stays in front: the instruction goes there
        _input.selectedRange = NSMakeRange(0, 0);
        [_input.undoManager removeAllActions];                    //typing starts from the text that was put in, not from nothing
        NSString* where = application.localizedName.length > 0 ? [NSString stringWithFormat:@" trong %@", application.localizedName] : @"";
        _contextLabel.stringValue = [NSString stringWithFormat:@"Đã lấy %lu ký tự đang chọn%@%@. Gõ yêu cầu ở dòng đầu hoặc bấm một kiểu chuyển đổi; kết quả sẽ thay thế vùng chọn.",
                                     (unsigned long)chosen.length, where, cut ? @" (đã cắt bớt, quá dài)" : @""];
        _contextLabel.hidden = NO;
    } else {
        _input.string = @"";
        _contextLabel.hidden = YES;
    }
    [self reloadProviders];
    [self updateInterface];
    if (_provider == nil)
        [self showSetupNeeded];
    else
        [self showStorageNote];
    [self resizeToFit];

    NSRect visible = [self screenOfMouse].visibleFrame;
    NSSize size = _panel.frame.size;
    NSPoint origin = NSMakePoint(NSMidX(visible) - size.width / 2, NSMaxY(visible) - visible.size.height * 0.16 - size.height);
    origin.y = MAX(origin.y, visible.origin.y + 20);
    if (self.offscreenForTesting) {
        //a test must not show a window to, nor take the keyboard from, whoever is working on this Mac
        [_panel setFrameOrigin:NSMakePoint(-30000, -30000)];
        [_panel orderFront:nil];
        [_panel makeFirstResponder:_input];
        sHasKeyboard = NO;
        return;
    }
    [_panel setFrameOrigin:origin];

    [_panel makeKeyAndOrderFront:nil];
    //Hidden switch for a Mac or an application where the window does not get the keys without VOpenKey being the active
    //application, the same as for the window of the snippets: defaults write <bundle id> SnippetsActivateApp -bool YES
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"SnippetsActivateApp"] || !_panel.keyWindow) {
        [NSApp activateIgnoringOtherApps:YES];
        [_panel makeKeyAndOrderFront:nil];
    }
    [_panel makeFirstResponder:_input];
    sHasKeyboard = _panel.keyWindow;
}

-(void)hideAssistant {
    [self cancelRequest];
    //what was typed and what came back is not kept: not even in the undo history, where ⌘Z would bring it back
    [self forgetText];
    [_result setString:@""];
    _activePreset = nil;
    _state = AIAssistantStateIdle;
    [self updatePlaceholders];
    [self updatePresetButtons];
    BOOL wasVisible = _panel.visible;
    [_panel orderOut:nil];
    sHasKeyboard = NO;
    if (wasVisible && sBoundary != nil)
        sBoundary();
}

-(void)forgetText {
    [self resetCopyButton];
    [self forgetImage];
    _input.string = @"";
    _output.string = @"";
    [_input.undoManager removeAllActions];
    [_output.undoManager removeAllActions];
}

-(void)windowDidBecomeKey:(NSNotification*)notification {
    sHasKeyboard = YES;
}

-(void)windowDidResignKey:(NSNotification*)notification {
    sHasKeyboard = NO;
    if (sBoundary != nil)
        sBoundary();
    //Nothing to lose: the window goes away when the user clicks elsewhere. With something written or an answer on the way it
    //stays, so that the answer can be read and copied from another application.
    BOOL somethingToKeep = _state != AIAssistantStateIdle || [_input.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0;
    if (!somethingToKeep && _panel.visible && !_opening)
        [self hideAssistant];
}

//⎋: stops what is going on, otherwise closes
-(void)escape {
    if (_state == AIAssistantStateGenerating)
        [self stop];
    else
        [self hideAssistant];
}

#pragma mark Providers

-(void)reloadProviders {
    [_providerPopUp removeAllItems];
    NSString* wanted = AISettings.providerIdentifier;
    AIProvider* chosen = nil;
    NSMutableArray<AIProvider*>* ready = [NSMutableArray array];
    for (AIProvider* provider in [AIProvider allProviders])
        if ([AISettings isProviderReady:provider])
            [ready addObject:provider];
    for (AIProvider* provider in ready) {
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:provider.name action:nil keyEquivalent:@""];
        item.representedObject = provider.identifier;
        [_providerPopUp.menu addItem:item];
        if ([provider.identifier isEqualToString:wanted])
            chosen = provider;
    }
    if (chosen == nil)
        chosen = ready.firstObject;
    if (ready.count > 0)
        [_providerPopUp.menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* settings = [[NSMenuItem alloc] initWithTitle:@"Cài đặt AI…" action:nil keyEquivalent:@""];
    settings.representedObject = @"";
    [_providerPopUp.menu addItem:settings];
    if (chosen != nil) {
        [_providerPopUp selectItemAtIndex:[_providerPopUp indexOfItemWithRepresentedObject:chosen.identifier]];
    } else {
        NSMenuItem* none = [[NSMenuItem alloc] initWithTitle:@"Chưa kết nối AI" action:nil keyEquivalent:@""];
        none.enabled = NO;
        [_providerPopUp.menu insertItem:none atIndex:0];
        [_providerPopUp selectItemAtIndex:0];
    }
    _provider = chosen;
    [_providerPopUp sizeToFit];
    [self reloadAgentControls];
    [self updateInfoLabel];
    [self updateInterface];
}

-(void)providerChosen:(NSPopUpButton*)sender {
    NSString* identifier = sender.selectedItem.representedObject;
    if ([identifier isEqualToString:@""]) {
        [self reloadProviders];                      //"Cài đặt AI…" is not a provider: back to the one in use
        [self openSettings:nil];
        return;
    }
    if (identifier != nil) {
        AISettings.providerIdentifier = identifier;
        _provider = [AIProvider providerWithIdentifier:identifier];
        [self reloadAgentControls];
        [self updateInfoLabel];
        [self updateInterface];
        if (_state == AIAssistantStateIdle) {
            _statusLabel.stringValue = @"";
            [self showStorageNote];
        }
        [self resizeToFit];
    }
}

#pragma mark A program on this Mac

//what Antigravity keeps of every request, said where it can be read before asking
-(void)showStorageNote {
    NSString* note = [AIAgentCLI forProvider:_provider].storageNote;
    if (note.length == 0 || _state != AIAssistantStateIdle)
        return;
    _statusLabel.stringValue = note;
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _settingsButton.hidden = YES;
}

//the model and the thinking level of a program: the menus follow what is chosen in the settings and are the same choice
-(void)reloadAgentControls {
    AIAgentCLI* cli = [AIAgentCLI forProvider:_provider];
    _modelPopUp.hidden = cli == nil;
    _effortPopUp.hidden = cli == nil;
    if (cli == nil)
        return;
    NSArray<AIAgentModel*>* models = [cli knownModels];
    NSString* saved = [AISettings modelForProvider:_provider];
    NSString* effortSaved = [AISettings effortForProvider:_provider];

    [_modelPopUp removeAllItems];
    if (cli.kind != AIAgentKindClaude) {                    //Claude Code always has a model to start with: Haiku
        NSMenuItem* automatic = [[NSMenuItem alloc] initWithTitle:@"Tự chọn (model nhẹ)" action:nil keyEquivalent:@""];
        automatic.representedObject = @"";
        automatic.toolTip = @"Một model nhanh và rẻ, đủ để viết, dịch, sửa chữ. Chọn model khác nếu cần.";
        [_modelPopUp.menu addItem:automatic];
    }
    BOOL found = saved.length == 0;
    for (AIAgentModel* model in models) {
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:model.name action:nil keyEquivalent:@""];
        item.representedObject = model.identifier;
        item.toolTip = model.summary;
        [_modelPopUp.menu addItem:item];
        found |= [model.identifier isEqualToString:saved];
    }
    if (!found) {                                           //a name typed in the settings that the program did not list
        NSMenuItem* typed = [[NSMenuItem alloc] initWithTitle:saved action:nil keyEquivalent:@""];
        typed.representedObject = saved;
        [_modelPopUp.menu addItem:typed];
    }
    NSInteger index = saved.length > 0 ? [_modelPopUp indexOfItemWithRepresentedObject:saved] : 0;
    [_modelPopUp selectItemAtIndex:MAX(index, 0)];
    [_modelPopUp sizeToFit];

    //the levels of the model that will be used
    NSString* used = [cli modelToPassForSaved:saved models:models];
    AIAgentModel* known = used.length > 0 ? [AIAgentCLI modelWithIdentifier:used among:models] : nil;
    NSArray<NSString*>* levels = known.efforts ?: [AIAgentCLI commonEfforts];
    [_effortPopUp removeAllItems];
    NSMenuItem* fast = [[NSMenuItem alloc] initWithTitle:@"Tự động (nhanh)" action:nil keyEquivalent:@""];
    fast.representedObject = @"";
    fast.toolTip = @"Mức thấp nhất mà model nhận: trả lời nhanh, đủ cho viết, dịch, sửa chữ.";
    [_effortPopUp.menu addItem:fast];
    for (NSString* level in levels) {
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:[AIAgentCLI nameOfEffort:level] action:nil keyEquivalent:@""];
        item.representedObject = level;
        item.toolTip = [AIAgentCLI speedNoteForEffort:level];            //what the level costs in time
        [_effortPopUp.menu addItem:item];
    }
    NSMenuItem* own = [[NSMenuItem alloc] initWithTitle:@"Mặc định của CLI" action:nil keyEquivalent:@""];
    own.representedObject = AIAgentEffortProgramDefault;
    own.toolTip = [AIAgentCLI speedNoteForEffort:nil];
    [_effortPopUp.menu addItem:own];
    NSInteger levelIndex = effortSaved.length > 0 ? [_effortPopUp indexOfItemWithRepresentedObject:effortSaved] : 0;
    [_effortPopUp selectItemAtIndex:MAX(levelIndex, 0)];
    [_effortPopUp sizeToFit];

    //the list of models of Codex and Antigravity comes from the program: asked once, then the menus are filled
    BOOL needsList = models.count == 0 && cli.kind != AIAgentKindClaude && ![_modelsRequested containsObject:_provider.identifier];
    NSString* executable = needsList ? [AISettings executablePathForProvider:_provider] : nil;
    if (executable != nil) {
        [_modelsRequested addObject:_provider.identifier];
        AIProvider* asked = _provider;
        __weak AIAssistant* weakSelf = self;
        [cli loadModelsFromExecutable:executable completion:^(NSArray<AIAgentModel*>* loaded, NSError* error) {
            AIAssistant* strong = weakSelf;
            if (strong != nil && strong->_provider == asked && loaded.count > 0) {
                [strong reloadAgentControls];
                [strong updateInfoLabel];
            }
        }];
    }
}

-(void)modelChosen:(NSPopUpButton*)sender {
    NSString* identifier = sender.selectedItem.representedObject;
    if (identifier == nil || _provider == nil)
        return;
    [AISettings setModel:identifier forProvider:_provider];
    [self reloadAgentControls];                              //another model has other levels
    [self updateInfoLabel];
}

-(void)effortChosen:(NSPopUpButton*)sender {
    NSString* level = sender.selectedItem.representedObject;
    if (level == nil || _provider == nil)
        return;
    [AISettings setEffort:level forProvider:_provider];
    [self updateInfoLabel];
}

#pragma mark Waiting

//The wait starts: the light runs, the sparkles breathe, the words shimmer and say what is going on, and every second the seconds count.
-(void)beginProgress {
    [self endProgress];
    _askStarted = [NSDate date];
    AIAgentCLI* cli = [AIAgentCLI forProvider:_provider];
    _slowLevelName = nil;
    if (cli != nil && !_imageRequest) {           //how long a picture takes does not depend on the level
        NSString* level = [cli effectiveEffortForSavedModel:[AISettings modelForProvider:_provider] effort:[AISettings effortForProvider:_provider] models:[cli knownModels]];
        if (![AIAgentCLI isFastEffort:level])
            _slowLevelName = [AIAgentCLI nameOfEffort:level];
    }
    [_glow start];
    AIPulseView(_icon, YES);
    _outputPlaceholder.textColor = [NSColor secondaryLabelColor];
    _outputPlaceholder.shimmering = YES;
    [_outputPlaceholder fadeToMessage:[AIProgressText messageAfterSeconds:0 provider:_provider.name image:_imageRequest]];
    __weak AIAssistant* weakSelf = self;
    _progressTimer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer* timer) {
        AIAssistant* strong = weakSelf;
        if (strong == nil || strong->_state != AIAssistantStateGenerating) {
            [timer invalidate];
            return;
        }
        [strong updateProgress];
    }];
    [[NSRunLoop currentRunLoop] addTimer:_progressTimer forMode:NSRunLoopCommonModes];     //it goes on while a menu of the window is open
}

-(void)updateProgress {
    NSInteger seconds = (NSInteger)(-[_askStarted timeIntervalSinceNow]);
    if (_result.length == 0)
        [_outputPlaceholder fadeToMessage:[AIProgressText messageAfterSeconds:seconds provider:_provider.name image:_imageRequest]];
    BOOL slow = _slowLevelName != nil && seconds >= (NSInteger)self.slowHintDelay;
    //the first seconds keep what the request said ("Đang tạo…"); then the seconds, and the cause of the wait when it is known
    if (seconds >= 2 || slow) {
        NSString* elapsed = [AIProgressText elapsedAfterSeconds:seconds];
        NSString* text = _progressNote != nil ? [NSString stringWithFormat:@"%@ (%@)", _progressNote, elapsed]
                                              : (_result.length > 0 ? [NSString stringWithFormat:@"Đang viết · %@", elapsed] : elapsed);
        if (slow && _progressNote == nil)
            text = [text stringByAppendingFormat:@" · Mức “%@” suy nghĩ kỹ nên chậm hơn; mức Thấp thường nhanh hơn nhiều.", _slowLevelName];
        _statusLabel.stringValue = text;
        _statusLabel.textColor = [NSColor secondaryLabelColor];
    }
    _speedButton.hidden = !slow;
    [self resizeToFit];
}

//The wait is over (answer, error, stop, closing): everything that moved is still, and the place of the answer is itself again.
-(void)endProgress {
    [_progressTimer invalidate];
    _progressTimer = nil;
    _progressNote = nil;
    _slowLevelName = nil;
    [_glow stop];
    AIPulseView(_icon, NO);
    _outputPlaceholder.shimmering = NO;
    _outputPlaceholder.textColor = [NSColor placeholderTextColor];
    if (![_outputPlaceholder.stringValue isEqualToString:kOutputPlaceholder])
        _outputPlaceholder.stringValue = kOutputPlaceholder;
    _speedButton.hidden = YES;
}

-(void)askAgainFaster:(id)sender {
    if (_provider == nil)
        return;
    [AISettings setEffort:nil forProvider:_provider];          //"automatic" is the lowest level the model accepts
    [self cancelRequest];
    _state = _result.length > 0 ? AIAssistantStateDone : AIAssistantStateIdle;
    [self reloadAgentControls];
    [self updateInfoLabel];
    if (_imageRequest)
        [self askForImage];
    else
        [self ask];
}

//who gets what is typed here: said every time, on the window itself
-(void)updateInfoLabel {
    if (_provider == nil) {
        _infoLabel.stringValue = @"";
        return;
    }
    AIAgentCLI* cli = [AIAgentCLI forProvider:_provider];
    if (cli != nil) {
        NSString* summary = [cli summaryForSavedModel:[AISettings modelForProvider:_provider] effort:[AISettings effortForProvider:_provider] models:[cli knownModels]];
        _infoLabel.stringValue = [NSString stringWithFormat:@"Nội dung gửi tới %@ · %@", _provider.name, summary];
        _infoLabel.toolTip = [NSString stringWithFormat:@"Nội dung gửi tới %@ qua tài khoản đã đăng nhập sẵn trong chương trình này · %@", _provider.name, summary];
        return;
    }
    _infoLabel.toolTip = nil;
    NSString* model = [AISettings modelForProvider:_provider];
    _infoLabel.stringValue = _provider.isLocal
        ? [NSString stringWithFormat:@"Chạy trên máy này hoặc trong mạng nội bộ · %@", model]
        : [NSString stringWithFormat:@"Nội dung gửi tới %@ · %@", _provider.name, model];
}

-(void)showSetupNeeded {
    _statusLabel.stringValue = @"Chưa kết nối AI. Chọn nhà cung cấp và nhập API key (hoặc chọn AI chạy trên máy) trong Cài đặt > AI.";
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _settingsButton.hidden = NO;
    [self resizeToFit];
}

#pragma mark Asking

-(void)cancelRequest {
    _askSerial++;
    [_client cancel];
    _client = nil;
    [self endProgress];
}

/// The AI on this Mac that VOpenKey installed (or that was installed by hand) is not running until something needs it: its server is
/// started now, which the first time takes about 20 seconds. Only for the address where Ollama listens by default.
-(BOOL)needsLocalServerFor:(AIConfiguration*)configuration {
    if (![configuration.provider.identifier isEqualToString:@"ollama"] || ![AIOllamaRuntime shared].isInstalled)
        return NO;
    NSURL* url = [NSURL URLWithString:configuration.baseURL];
    NSURL* standard = [AIOllamaRuntime shared].baseURL;
    NSString* host = url.host.lowercaseString;
    return ([host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"localhost"]) && [url.port ?: @80 isEqualToNumber:standard.port ?: @11434];
}

-(void)ask {
    NSString* prompt = [_input.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (prompt.length == 0) {
        [self showInputHint:_activePreset != nil ? @"Hãy nhập hoặc chọn đoạn văn cần chuyển đổi trước." : @"Hãy nhập yêu cầu trước."];
        return;
    }
    //a conversion that was chosen goes in front of the text; it is not written in the box, the button that is lit says which one it is
    if (_activePreset != nil)
        prompt = [AIPresets promptForPreset:_activePreset draft:prompt];
    AIProvider* provider = _provider ?: AISettings.provider;
    NSError* problem = nil;
    AIConfiguration* configuration = [AISettings configurationForProvider:provider error:&problem];
    if (configuration == nil) {
        [self showFailure:problem];
        return;
    }
    [self cancelRequest];
    [_result setString:@""];
    _output.string = @"";
    [self forgetImage];
    [self resetCopyButton];
    _imageRequest = NO;
    _state = AIAssistantStateGenerating;
    [self beginProgress];
    //a model that runs on this Mac is heavy: when the Mac is already busy it will be slow, and that is said at once
    NSString* working = @"Đang tạo…";
    if (provider.isLocal && [(self.hardwareProvider ? self.hardwareProvider() : [AIHardware current]) isBusy]) {
        working = @"Đang tạo… Máy đang bận nên AI chạy trên máy sẽ chậm. Nếu cần nhanh, chọn dịch vụ trực tuyến trong Cài đặt > AI.";
        _progressNote = working;
    }
    [self showMessage:working error:NO];
    [self updateInterface];

    if ([self needsLocalServerFor:configuration]) {
        NSUInteger serial = _askSerial;
        __block BOOL answered = NO;
        __weak AIAssistant* weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            AIAssistant* strong = weakSelf;
            if (strong != nil && !answered && serial == strong->_askSerial) {       //only when it really takes time
                strong->_progressNote = @"Đang khởi động AI trên máy (lần đầu 20 đến 40 giây)…";
                [strong showMessage:strong->_progressNote error:NO];
            }
        });
        [[AIOllamaRuntime shared] ensureRunning:^(NSError* error) {
            answered = YES;
            AIAssistant* strong = weakSelf;
            if (strong == nil || serial != strong->_askSerial)
                return;                                                             //stopped or closed meanwhile
            if (error != nil) {
                [strong showFailure:error];
                [strong updateInterface];
                return;
            }
            [strong sendPrompt:prompt configuration:configuration];
        }];
        return;
    }
    [self sendPrompt:prompt configuration:configuration];
}

#pragma mark A picture

-(void)forgetImage {
    if ([AILightbox shared].visible)
        [[AILightbox shared] close];
    _saveImageButton.hidden = YES;
    _resultImageURL = nil;
    _resultImagePNG = nil;
    _imageView.image = nil;
    _imageView.hidden = YES;
    _revealButton.hidden = YES;
}

-(void)imagePressed:(id)sender {
    [self askForImage];
}

//Codex makes it with its imagegen skill, which has to be named in the request or the picture is a poor one; the file is kept by Codex.
-(void)askForImage {
    _activePreset = nil;       //a picture is made from the description in the box, not from a conversion
    [self updatePresetButtons];
    NSString* request = [_input.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (request.length == 0) {
        [self showMessage:@"Hãy mô tả bức ảnh bạn muốn trước." error:NO];
        return;
    }
    AIProvider* provider = _provider ?: AISettings.provider;
    if (![AISettings canMakeImagesWithProvider:provider]) {
        [self showMessage:@"Chỉ tạo được ảnh khi dùng Codex CLI. Chọn Codex CLI ở góc trên của cửa sổ." error:YES];
        return;
    }
    NSError* problem = nil;
    AIConfiguration* configuration = [AISettings configurationForProvider:provider error:&problem];
    if (configuration == nil) {
        [self showFailure:problem];
        return;
    }
    [self cancelRequest];
    [_result setString:@""];
    _output.string = @"";
    [self forgetImage];
    [self resetCopyButton];
    _imageRequest = YES;
    _state = AIAssistantStateGenerating;
    [self beginProgress];
    [self showMessage:@"Đang tạo ảnh…" error:NO];
    [self updateInterface];

    AIClient* client = [[AIClient alloc] initWithConfiguration:configuration];
    _client = client;
    __weak AIAssistant* weakSelf = self;
    [client generateImageWithPrompt:[AIAgentCLI imagePromptForRequest:request template:AISettings.imagePrompt]
                             onNote:^(NSString* note) {}                //what the agent says on the way is not shown: the words of the wait are
                         completion:^(NSURL* image, NSError* error) {
        AIAssistant* strong = weakSelf;
        if (strong == nil || strong->_client != client)
            return;
        strong->_client = nil;
        [strong endProgress];
        if (error != nil) {
            [strong showFailure:error];
        } else {
            [strong showImageAtURL:image];
        }
        [strong updateInterface];
    }];
}

-(void)showImageAtURL:(NSURL*)url {
    NSData* data = [NSData dataWithContentsOfURL:url];
    NSImage* image = data.length > 0 ? [[NSImage alloc] initWithData:data] : nil;
    if (image == nil) {
        [self showFailure:[NSError errorWithDomain:VOKAIErrorDomain code:VOKAIErrorEmpty userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Không đọc được ảnh mà Codex đã tạo (%@).", url.lastPathComponent]}]];
        return;
    }
    //the clipboard takes a PNG: whatever Codex wrote (it could be a JPEG or a WebP) is turned into one
    NSData* png = data;
    if (![[url.pathExtension lowercaseString] isEqualToString:@"png"]) {
        NSBitmapImageRep* rep = [NSBitmapImageRep imageRepWithData:data];
        png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] ?: data;
    }
    _resultImageURL = url;
    _resultImagePNG = png;
    _imageView.image = image;
    _imageView.hidden = NO;
    _state = AIAssistantStateDone;
    NSString* shown = [url.path stringByAbbreviatingWithTildeInPath];
    [self showMessage:[NSString stringWithFormat:@"Xong. ⇧⌘↩ để chèn ảnh. Codex lưu ảnh ở %@", shown] error:NO];
    _revealButton.hidden = NO;
    _saveImageButton.hidden = NO;
    [self updatePlaceholders];
}

-(void)imageClicked:(id)sender { [self openImage]; }

-(void)openImage {
    if (_resultImagePNG == nil || _imageView.image == nil)
        return;
    AILightbox* box = [AILightbox shared];
    box.offscreenForTesting = self.offscreenForTesting;
    box.pasteboard = _inserter.pasteboard;
    [box showImage:_imageView.image png:_resultImagePNG name:_resultImageURL.lastPathComponent over:_panel];
}

-(void)saveImagePressed:(id)sender { [self saveImage]; }

//Downloads, with a name of its own, without asking
-(void)saveImage {
    if (_resultImagePNG == nil)
        return;
    NSError* error = nil;
    NSURL* url = [AILightbox savePNG:_resultImagePNG toFolder:[AILightbox downloadsFolder] error:&error];
    if (url == nil) {
        [self showMessage:[NSString stringWithFormat:@"Không lưu được ảnh: %@", error.localizedDescription] error:YES];
        return;
    }
    [self showMessage:[NSString stringWithFormat:@"Đã lưu vào Downloads: %@", url.lastPathComponent] error:NO];
    _statusLabel.textColor = [NSColor systemGreenColor];
}

//the green check on the copy button, for a moment
-(void)flashCopyButton {
    NSUInteger mine = ++_copyFeedback;
    _copyConfirmed = YES;
    NSImage* check = VOKSymbol(@"checkmark.circle.fill", 12, NSFontWeightSemibold);
    _copyButton.image = check;
    _copyButton.imagePosition = NSImageLeading;
    _copyButton.contentTintColor = [NSColor systemGreenColor];
    _copyButton.title = @"Đã sao chép";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (mine != self->_copyFeedback)
            return;
        [self resetCopyButton];
    });
}

-(void)resetCopyButton {
    _copyFeedback++;
    _copyConfirmed = NO;
    _copyButton.image = nil;
    _copyButton.contentTintColor = nil;
    _copyButton.title = @"Sao chép";
}

-(void)revealImage:(id)sender {
    if (_resultImageURL != nil)
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[_resultImageURL]];
}

-(void)sendPrompt:(NSString*)prompt configuration:(AIConfiguration*)configuration {
    AIClient* client = [[AIClient alloc] initWithConfiguration:configuration];
    _client = client;
    __weak AIAssistant* weakSelf = self;
    [client generateWithPrompt:prompt onText:^(NSString* piece) {
        AIAssistant* strong = weakSelf;
        if (strong == nil || strong->_client != client)
            return;
        [strong->_result appendString:piece];
        [strong->_output.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:piece attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:13], NSForegroundColorAttributeName: [NSColor labelColor]}]];
        [strong->_output scrollRangeToVisible:NSMakeRange(strong->_output.string.length, 0)];
        strong->_output.needsDisplay = YES;
        [strong updateInterface];
    } completion:^(NSError* error) {
        AIAssistant* strong = weakSelf;
        if (strong == nil || strong->_client != client)
            return;
        strong->_client = nil;
        [strong endProgress];
        if (error != nil) {
            [strong showFailure:error];
        } else {
            strong->_state = AIAssistantStateDone;
            //the rhyme and the number of syllables of a poem are the AI's word: the window does not count them
            [strong showMessage:strong->_activePreset.isPoem ? @"Xong. Số tiếng và vần của thơ chưa được kiểm tra, hãy đọc lại. ⇧⌘↩ để dùng kết quả."
                                                             : @"Xong. ⇧⌘↩ để dùng kết quả." error:NO];
        }
        [strong updateInterface];
    }];
}

-(void)stop {
    if (_state != AIAssistantStateGenerating)
        return;
    [self cancelRequest];
    _state = _result.length > 0 ? AIAssistantStateDone : AIAssistantStateIdle;
    [self showMessage:@"Đã dừng." error:NO];
    [self updateInterface];
}

//The window asks for a text. The line is taken back when the user types one, so that it does not stay under a box that is no longer empty.
-(void)showInputHint:(NSString*)hint {
    [self showMessage:hint error:NO];
    _inputHintShown = YES;
}

-(void)showMessage:(NSString*)message error:(BOOL)error {
    _inputHintShown = NO;
    _statusLabel.stringValue = message;
    _statusLabel.textColor = error ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
    _settingsButton.hidden = YES;
    if (_progressTimer == nil)
        _speedButton.hidden = YES;                      //while waiting, the clock decides when it is there
    _revealButton.hidden = _resultImageURL == nil || _state == AIAssistantStateGenerating;
    _saveImageButton.hidden = _revealButton.hidden;
    [self resizeToFit];
}

-(void)showFailure:(NSError*)error {
    if (error.code == VOKAIErrorCancelled)
        return;
    _state = AIAssistantStateFailed;
    [self endProgress];
    [self showMessage:error.localizedDescription error:YES];
    //what to do about it is in the settings
    BOOL settingsCanHelp = error.code == VOKAIErrorNoKey || error.code == VOKAIErrorAuthentication || error.code == VOKAIErrorBadAddress ||
                           error.code == VOKAIErrorModel || error.code == VOKAIErrorBadKey || error.code == VOKAIErrorNoProgram;
    _settingsButton.hidden = !settingsCanHelp;
    [self resizeToFit];
    [self updateInterface];
}

#pragma mark Conversions

-(NSArray<NSButton*>*)presetButtons { [self buildIfNeeded]; return _presetButtons; }
-(AIPreset*)activePreset { return _activePreset; }

//a button of a conversion is lit while it is the one that applies, and works when there is a text to convert and no answer on its way
-(void)updatePresetButtons {
    BOOL hasText = [_input.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0;
    BOOL generating = _state == AIAssistantStateGenerating;
    NSArray<AIPreset*>* all = [AIPresets all];
    for (NSUInteger i = 0; i < _presetButtons.count && i < all.count; i++) {
        NSButton* button = _presetButtons[i];
        BOOL chosen = _activePreset != nil && [_activePreset.identifier isEqualToString:all[i].identifier];
        button.state = chosen ? NSControlStateValueOn : NSControlStateValueOff;
        button.bezelColor = chosen ? [NSColor controlAccentColor] : nil;
        button.enabled = hasText && !generating;
    }
}

-(void)presetPressed:(NSButton*)sender {
    [self applyPresetWithIdentifier:sender.identifier];
}

-(void)applyPresetWithIdentifier:(NSString*)identifier {
    AIPreset* preset = [AIPresets presetWithIdentifier:identifier];
    BOOL hasText = [_input.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0;
    if (preset == nil || _state == AIAssistantStateGenerating)
        return;
    if (!hasText) {
        [self showInputHint:@"Hãy nhập hoặc chọn đoạn văn cần chuyển đổi trước."];
        return;
    }
    _activePreset = preset;
    [self updatePresetButtons];
    [self ask];
}

#pragma mark Using the answer

-(NSString*)answerToUse {
    return [_result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

-(void)insertResult {
    if (_state == AIAssistantStateGenerating)
        return;
    if (_resultImagePNG != nil) {
        NSData* png = _resultImagePNG;
        NSRunningApplication* target = _target;
        [self hideAssistant];
        [_inserter insertImageData:png application:target];
        return;
    }
    NSString* text = [self answerToUse];
    if (text.length == 0)
        return;
    NSRunningApplication* target = _target;
    [self hideAssistant];
    [_inserter insertText:text application:target];
}

-(void)copyResult {
    NSPasteboard* board = _inserter.pasteboard;
    if (_resultImagePNG != nil) {
        [board clearContents];
        NSPasteboardItem* item = [[NSPasteboardItem alloc] init];
        [item setData:_resultImagePNG forType:NSPasteboardTypePNG];
        NSData* tiff = [[[NSImage alloc] initWithData:_resultImagePNG] TIFFRepresentation];
        if (tiff != nil)
            [item setData:tiff forType:NSPasteboardTypeTIFF];
        [board writeObjects:@[item]];
        [self showMessage:@"Đã sao chép ảnh." error:NO];
        _statusLabel.textColor = [NSColor systemGreenColor];
        _revealButton.hidden = NO;
        [self flashCopyButton];
        return;
    }
    NSString* text = [self answerToUse];
    if (text.length == 0)
        return;
    [board clearContents];
    [board setString:text forType:NSPasteboardTypeString];
    [self showMessage:@"Đã sao chép." error:NO];
    _statusLabel.textColor = [NSColor systemGreenColor];
    [self flashCopyButton];
}

-(void)openSettings:(id)sender {
    [self hideAssistant];
    if (sOpenSettings != nil)
        sOpenSettings();
}

#pragma mark Controls

-(void)actionPressed:(id)sender {
    if (_state == AIAssistantStateGenerating)
        [self stop];
    else
        [self ask];
}

-(void)copyPressed:(id)sender { [self copyResult]; }
-(void)insertPressed:(id)sender { [self insertResult]; }

-(void)setKeyEquivalent:(NSString*)key mask:(NSEventModifierFlags)mask forButton:(NSButton*)button {
    button.keyEquivalent = key;
    button.keyEquivalentModifierMask = mask;
}

-(void)updatePlaceholders {
    _inputPlaceholder.hidden = _input.string.length > 0;
    _outputPlaceholder.hidden = _output.string.length > 0 || !_imageView.hidden;
}

-(void)textDidChange:(NSNotification*)notification {
    [self updatePlaceholders];
    //the text is no longer the one the conversion was chosen for: what is typed now is a request of its own
    _activePreset = nil;
    [self updatePresetButtons];
    if (_inputHintShown && _state == AIAssistantStateIdle)
        [self showMessage:@"" error:NO];
}

-(void)updateInterface {
    [self updatePlaceholders];
    BOOL generating = _state == AIAssistantStateGenerating;
    BOOL hasText = _result.length > 0;
    BOOL hasResult = hasText || _resultImagePNG != nil;
    _canMakeImages = _provider != nil && [AISettings canMakeImagesWithProvider:_provider];
    _actionButton.title = generating ? @"Dừng" : (hasText ? @"Tạo lại" : @"Tạo");
    //pictures are for Codex only: for the other AIs the button is there, off, and says why
    _imageButton.enabled = _canMakeImages && !generating;
    _imageButton.toolTip = _canMakeImages ? @"Tạo ảnh bằng Codex (kỹ năng imagegen) từ mô tả ở ô trên. ⌥⌘↩"
                                          : @"Chỉ dùng được khi chọn Codex CLI ở góc trên của cửa sổ.";
    //⌘↩ asks; while an answer is on its way the same place is ⌘. as everywhere in macOS
    if (generating)
        [self setKeyEquivalent:@"." mask:NSEventModifierFlagCommand forButton:_actionButton];
    else
        [self setKeyEquivalent:@"\r" mask:NSEventModifierFlagCommand forButton:_actionButton];
    _copyButton.enabled = hasResult;
    [self updatePresetButtons];
    _insertButton.title = _resultImagePNG != nil ? @"Chèn ảnh" : (_hadSelection ? @"Thay thế vùng chọn" : @"Chèn");
    _insertButton.enabled = hasResult && !generating;
    [self setKeyEquivalent:@"\r" mask:NSEventModifierFlagCommand | NSEventModifierFlagShift forButton:_insertButton];
    [self setKeyEquivalent:@"c" mask:NSEventModifierFlagCommand | NSEventModifierFlagShift forButton:_copyButton];
}

#pragma mark Text view

//Tab goes to the next control like in a form, it is not a character of the request
-(BOOL)textView:(NSTextView*)textView doCommandBySelector:(SEL)command {
    if (command == @selector(insertTab:)) {
        [_panel selectNextKeyView:nil];
        return YES;
    }
    if (command == @selector(insertBacktab:)) {
        [_panel selectPreviousKeyView:nil];
        return YES;
    }
    return NO;
}

@end
