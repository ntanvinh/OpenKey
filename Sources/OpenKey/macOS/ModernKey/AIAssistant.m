//
//  AIAssistant.m
//  VOpenKey
//

#import "AIAssistant.h"
#import "AIKeychain.h"
#import "AIOllamaRuntime.h"
#import "AISelection.h"
#import "AISettings.h"
#import "VOKUI.h"

static const CGFloat kWidth = 620;
static const CGFloat kInset = 16;
static const CGFloat kCornerRadius = 14;
static const NSUInteger kMaxSelection = 30000;     //a whole document is not something to send by accident

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
    NSTextField* _contextLabel;
    NSTextView* _input;
    NSTextField* _inputPlaceholder;
    NSView* _inputScroll;
    NSTextField* _infoLabel;
    NSButton* _actionButton;
    NSTextView* _output;
    NSTextField* _outputPlaceholder;
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
-(NSButton*)settingsButton { [self buildIfNeeded]; return _settingsButton; }
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
    NSView* spacer1 = [[NSView alloc] init];
    [spacer1 setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* header = [NSStackView stackViewWithViews:@[_icon, title, spacer1, _providerPopUp]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.spacing = 6;
    header.alignment = NSLayoutAttributeCenterY;

    //what was selected
    _contextLabel = [self labelWithSize:11 color:[NSColor secondaryLabelColor]];
    _contextLabel.hidden = YES;

    //the request
    _inputPlaceholder = VOKLabel(@"Bạn muốn viết gì? Ví dụ: “Viết email xin nghỉ phép ngày mai”, hoặc chọn một đoạn văn rồi bấm phím tắt để nhờ dịch, sửa, tóm tắt.",
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

    _infoLabel = [self labelWithSize:11 color:[NSColor secondaryLabelColor]];
    _actionButton = [self buttonWithTitle:@"Tạo" action:@selector(actionPressed:)];
    NSView* spacer2 = [[NSView alloc] init];
    [spacer2 setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* askRow = [NSStackView stackViewWithViews:@[_infoLabel, spacer2, _actionButton]];
    askRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    askRow.alignment = NSLayoutAttributeCenterY;
    askRow.spacing = 8;

    //the answer
    _outputPlaceholder = VOKLabel(@"Câu trả lời của AI sẽ hiện ở đây.", 13, NSFontWeightRegular, [NSColor placeholderTextColor]);
    _outputPlaceholder.preferredMaxLayoutWidth = kWidth - 2 * kInset - 22;
    NSTextView* outputView = nil;
    _outputScroll = TextArea(190, _outputPlaceholder, &outputView);
    _output = outputView;
    _output.editable = NO;
    _output.selectable = YES;
    [_output setAccessibilityLabel:@"Kết quả"];

    _statusLabel = [self labelWithSize:11 color:[NSColor secondaryLabelColor]];
    _settingsButton = [self buttonWithTitle:@"Mở Cài đặt AI…" action:@selector(openSettings:)];
    _settingsButton.controlSize = NSControlSizeSmall;
    _settingsButton.hidden = YES;
    NSView* spacer3 = [[NSView alloc] init];
    [spacer3 setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* statusRow = [NSStackView stackViewWithViews:@[_statusLabel, spacer3, _settingsButton]];
    statusRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    statusRow.alignment = NSLayoutAttributeCenterY;
    statusRow.spacing = 8;
    //the text may take what the button leaves
    [_statusLabel setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];

    //what to do with it
    _hintLabel = [self labelWithSize:10 color:[NSColor tertiaryLabelColor]];
    _hintLabel.stringValue = @"⌘↩ Tạo   ⇧⌘↩ Chèn   ⇧⌘C Sao chép   esc Đóng";
    _copyButton = [self buttonWithTitle:@"Sao chép" action:@selector(copyPressed:)];
    _insertButton = [self buttonWithTitle:@"Chèn" action:@selector(insertPressed:)];
    NSView* spacer4 = [[NSView alloc] init];
    [spacer4 setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* bottom = [NSStackView stackViewWithViews:@[_hintLabel, spacer4, _copyButton, _insertButton]];
    bottom.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bottom.alignment = NSLayoutAttributeCenterY;
    bottom.spacing = 8;

    _stack = [NSStackView stackViewWithViews:@[header, _contextLabel, _inputScroll, askRow, _outputScroll, statusRow, bottom]];
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
        _contextLabel.stringValue = [NSString stringWithFormat:@"Đã lấy %lu ký tự đang chọn%@%@. Gõ yêu cầu ở dòng đầu; kết quả sẽ thay thế vùng chọn.",
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
    [self resizeToFit];

    NSRect visible = [self screenOfMouse].visibleFrame;
    NSSize size = _panel.frame.size;
    NSPoint origin = NSMakePoint(NSMidX(visible) - size.width / 2, NSMaxY(visible) - visible.size.height * 0.16 - size.height);
    origin.y = MAX(origin.y, visible.origin.y + 20);
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
    _state = AIAssistantStateIdle;
    [self updatePlaceholders];
    BOOL wasVisible = _panel.visible;
    [_panel orderOut:nil];
    sHasKeyboard = NO;
    if (wasVisible && sBoundary != nil)
        sBoundary();
}

-(void)forgetText {
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
    [self updateInfoLabel];
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
        [self updateInfoLabel];
    }
}

//who gets what is typed here: said every time, on the window itself
-(void)updateInfoLabel {
    if (_provider == nil) {
        _infoLabel.stringValue = @"";
        return;
    }
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
        [self showMessage:@"Hãy nhập yêu cầu trước." error:NO];
        return;
    }
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
    _state = AIAssistantStateGenerating;
    //a model that runs on this Mac is heavy: when the Mac is already busy it will be slow, and that is said at once
    NSString* working = @"Đang tạo…";
    if (provider.isLocal && [(self.hardwareProvider ? self.hardwareProvider() : [AIHardware current]) isBusy])
        working = @"Đang tạo… Máy đang bận nên AI chạy trên máy sẽ chậm. Nếu cần nhanh, chọn dịch vụ trực tuyến trong Cài đặt > AI.";
    [self showMessage:working error:NO];
    [self updateInterface];

    if ([self needsLocalServerFor:configuration]) {
        NSUInteger serial = _askSerial;
        __block BOOL answered = NO;
        __weak AIAssistant* weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            AIAssistant* strong = weakSelf;
            if (strong != nil && !answered && serial == strong->_askSerial)         //only when it really takes time
                [strong showMessage:@"Đang khởi động AI trên máy (lần đầu 20 đến 40 giây)…" error:NO];
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
        if (error != nil) {
            [strong showFailure:error];
        } else {
            strong->_state = AIAssistantStateDone;
            [strong showMessage:@"Xong. ⇧⌘↩ để dùng kết quả." error:NO];
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

-(void)showMessage:(NSString*)message error:(BOOL)error {
    _statusLabel.stringValue = message;
    _statusLabel.textColor = error ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
    _settingsButton.hidden = YES;
    [self resizeToFit];
}

-(void)showFailure:(NSError*)error {
    if (error.code == VOKAIErrorCancelled)
        return;
    _state = AIAssistantStateFailed;
    [self showMessage:error.localizedDescription error:YES];
    //what to do about it is in the settings
    BOOL settingsCanHelp = error.code == VOKAIErrorNoKey || error.code == VOKAIErrorAuthentication || error.code == VOKAIErrorBadAddress ||
                           error.code == VOKAIErrorModel || error.code == VOKAIErrorBadKey;
    _settingsButton.hidden = !settingsCanHelp;
    [self resizeToFit];
    [self updateInterface];
}

#pragma mark Using the answer

-(NSString*)answerToUse {
    return [_result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

-(void)insertResult {
    NSString* text = [self answerToUse];
    if (text.length == 0 || _state == AIAssistantStateGenerating)
        return;
    NSRunningApplication* target = _target;
    [self hideAssistant];
    [_inserter insertText:text application:target];
}

-(void)copyResult {
    NSString* text = [self answerToUse];
    if (text.length == 0)
        return;
    NSPasteboard* board = _inserter.pasteboard;
    [board clearContents];
    [board setString:text forType:NSPasteboardTypeString];
    [self showMessage:@"Đã sao chép." error:NO];
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
    _outputPlaceholder.hidden = _output.string.length > 0;
}

-(void)textDidChange:(NSNotification*)notification {
    [self updatePlaceholders];
}

-(void)updateInterface {
    [self updatePlaceholders];
    BOOL generating = _state == AIAssistantStateGenerating;
    BOOL hasResult = _result.length > 0;
    _actionButton.title = generating ? @"Dừng" : (hasResult ? @"Tạo lại" : @"Tạo");
    //⌘↩ asks; while an answer is on its way the same place is ⌘. as everywhere in macOS
    if (generating)
        [self setKeyEquivalent:@"." mask:NSEventModifierFlagCommand forButton:_actionButton];
    else
        [self setKeyEquivalent:@"\r" mask:NSEventModifierFlagCommand forButton:_actionButton];
    _copyButton.enabled = hasResult;
    _insertButton.title = _hadSelection ? @"Thay thế vùng chọn" : @"Chèn";
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
