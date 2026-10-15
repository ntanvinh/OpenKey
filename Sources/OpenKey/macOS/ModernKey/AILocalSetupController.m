//
//  AILocalSetupController.m
//  VOpenKey
//

#import "AILocalSetupController.h"
#import "AIOllama.h"
#import "VOKUI.h"

static const CGFloat kWindowWidth = 720;
static const CGFloat kInner = 640;                 //width of what is inside a card

@interface AILocalSetupController () <NSWindowDelegate, NSTextFieldDelegate>
@end

@implementation AILocalSetupController {
    AILocalSetup* _setup;
    AIHardware* _hardware;
    NSArray<AILocalModel*>* _catalog;
    NSURL* _modelsDirectory;
    NSSet<NSString*>* _installedTags;
    AILocalModel* _recommended;
    AILocalModel* _customModel;                    //the model typed by the user, with its size once looked up
    AIModelAssessment* _assessment;
    NSInteger _customLookupSerial;
    BOOL _hardwareGiven;                           //described by the caller (tests): not replaced by the real Mac when the window opens

    NSWindow* _window;
    NSTextField* _machineLabel, *_overviewLabel, *_summaryLabel, *_requirementsLabel, *_verdictLabel, *_problemsLabel, *_notesLabel, *_resultLabel, *_customStatus;
    NSPopUpButton* _modelPopUp;
    NSTextField* _customField;
    NSButton* _installButton, *_cancelButton, *_removeButton, *_refreshButton;
    NSStackView* _customRow;
    NSView* _progressSection;
    NSStackView* _stepRows[AILocalStepCount];
    NSImageView* _stepIcons[AILocalStepCount];
    NSTextField* _stepDetails[AILocalStepCount];
    NSProgressIndicator* _stepBars[AILocalStepCount];
}

+(void)show {
    static AILocalSetupController* shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[AILocalSetupController alloc] initWithSetup:[AILocalSetup standardSetup] hardware:nil catalog:[AILocalModels catalog]
                                               modelsDirectory:[AILocalSetup defaultModelsDirectory]];
    });
    [shared present];
}

-(instancetype)initWithSetup:(AILocalSetup*)setup hardware:(AIHardware*)hardware catalog:(NSArray<AILocalModel*>*)catalog
             modelsDirectory:(NSURL*)modelsDirectory {
    self = [super init];
    if (self) {
        _setup = setup;
        _hardware = hardware;
        _hardwareGiven = hardware != nil;
        _catalog = catalog;
        _modelsDirectory = modelsDirectory;
        _libraryURL = [AIOllama defaultRegistryURL];
        __weak AILocalSetupController* weakSelf = self;
        _setup.onChange = ^{ [weakSelf reloadProgress]; };
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setupFinished:) name:VOKAILocalSetupDidFinishNotification object:_setup];
    }
    return self;
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(AILocalSetup*)setup { return _setup; }
-(AIHardware*)hardware { return _hardware; }
-(void)setHardware:(AIHardware*)hardware {
    _hardware = hardware;
    _hardwareGiven = hardware != nil;
    if (_window != nil)
        [self reloadAll];
}
-(AILocalModel*)selectedModel {
    [self buildIfNeeded];
    NSInteger index = _modelPopUp.indexOfSelectedItem;
    if (index < 0)
        return nil;
    if (index < (NSInteger)_catalog.count)
        return _catalog[index];
    return _customModel;
}
-(AIModelAssessment*)assessment { return _assessment; }
-(NSWindow*)window { [self buildIfNeeded]; return _window; }
-(NSTextField*)machineLabel { [self buildIfNeeded]; return _machineLabel; }
-(NSTextField*)overviewLabel { [self buildIfNeeded]; return _overviewLabel; }
-(NSPopUpButton*)modelPopUp { [self buildIfNeeded]; return _modelPopUp; }
-(NSTextField*)customField { [self buildIfNeeded]; return _customField; }
-(NSTextField*)summaryLabel { [self buildIfNeeded]; return _summaryLabel; }
-(NSTextField*)requirementsLabel { [self buildIfNeeded]; return _requirementsLabel; }
-(NSTextField*)verdictLabel { [self buildIfNeeded]; return _verdictLabel; }
-(NSTextField*)problemsLabel { [self buildIfNeeded]; return _problemsLabel; }
-(NSTextField*)notesLabel { [self buildIfNeeded]; return _notesLabel; }
-(NSButton*)installButton { [self buildIfNeeded]; return _installButton; }
-(NSButton*)cancelButton { [self buildIfNeeded]; return _cancelButton; }
-(NSButton*)removeButton { [self buildIfNeeded]; return _removeButton; }
-(NSButton*)refreshButton { [self buildIfNeeded]; return _refreshButton; }
-(NSTextField*)resultLabel { [self buildIfNeeded]; return _resultLabel; }
-(NSView*)progressSection { [self buildIfNeeded]; return _progressSection; }

#pragma mark - Building

static NSTextField* Wrapped(NSString* text, CGFloat size, NSFontWeight weight, NSColor* color, CGFloat width) {
    NSTextField* label = VOKLabel(text, size, weight, color);
    label.preferredMaxLayoutWidth = width;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label.widthAnchor constraintEqualToConstant:width].active = YES;
    [label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    return label;
}

static NSStackView* Stack(NSArray<NSView*>* views, BOOL vertical, CGFloat spacing) {
    NSStackView* stack = [NSStackView stackViewWithViews:views];
    stack.orientation = vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = vertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

/// A card of System Settings with a title above it: `rows` inside, with the inset every card has.
static NSView* Section(NSString* title, NSArray<NSView*>* rows) {
    NSStackView* inside = Stack(rows, YES, 8);
    inside.edgeInsets = NSEdgeInsetsMake(12, 16, 12, 16);
    NSView* card = VOKCard(inside);
    NSTextField* heading = VOKLabel(title, 13, NSFontWeightSemibold, nil);
    NSStackView* section = Stack(@[heading, card], YES, 6);
    [card.widthAnchor constraintEqualToConstant:kInner + 32].active = YES;
    return section;
}

-(NSButton*)buttonWithTitle:(NSString*)title action:(SEL)action {
    NSButton* button = [NSButton buttonWithTitle:title target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

-(void)buildIfNeeded {
    if (_window != nil)
        return;
    if (_hardware == nil)
        _hardware = [AIHardware currentForDirectory:_modelsDirectory];

    _machineLabel = Wrapped(@"", 12, NSFontWeightMedium, nil, kInner);
    _overviewLabel = Wrapped(@"", 12, NSFontWeightRegular, [NSColor secondaryLabelColor], kInner);
    _refreshButton = [self buttonWithTitle:@"Kiểm tra lại" action:@selector(refreshHardware:)];
    _refreshButton.controlSize = NSControlSizeSmall;
    VOKSetButtonSymbol(_refreshButton, @"arrow.clockwise", 11);
    NSView* machine = Section(@"Máy của bạn", @[_machineLabel, _overviewLabel, _refreshButton]);

    _modelPopUp = [[NSPopUpButton alloc] init];
    _modelPopUp.translatesAutoresizingMaskIntoConstraints = NO;
    _modelPopUp.target = self;
    _modelPopUp.action = @selector(modelPopUpChanged:);
    [_modelPopUp.widthAnchor constraintEqualToConstant:kInner].active = YES;
    _customField = [[NSTextField alloc] init];
    _customField.placeholderString = @"Tên model của Ollama, ví dụ qwen3:8b hoặc llama3.2:3b";
    _customField.delegate = self;
    _customField.target = self;
    _customField.action = @selector(customModelEntered:);
    _customField.translatesAutoresizingMaskIntoConstraints = NO;
    [_customField.widthAnchor constraintEqualToConstant:kInner].active = YES;
    _customStatus = Wrapped(@"", 11, NSFontWeightRegular, [NSColor secondaryLabelColor], kInner);
    _customRow = Stack(@[_customField, _customStatus], YES, 4);
    _summaryLabel = Wrapped(@"", 12, NSFontWeightRegular, nil, kInner);
    _requirementsLabel = Wrapped(@"", 12, NSFontWeightRegular, [NSColor secondaryLabelColor], kInner);
    _verdictLabel = Wrapped(@"", 13, NSFontWeightSemibold, nil, kInner);
    _problemsLabel = Wrapped(@"", 12, NSFontWeightRegular, nil, kInner);
    NSView* choose = Section(@"Chọn model", @[_modelPopUp, _customRow, _summaryLabel, _requirementsLabel, _verdictLabel, _problemsLabel]);

    _notesLabel = Wrapped(@"", 12, NSFontWeightRegular, [NSColor secondaryLabelColor], kInner);
    NSView* notes = Section(@"Sẽ cài những gì, và chạy thế nào", @[_notesLabel]);

    NSMutableArray<NSView*>* stepViews = [NSMutableArray array];
    for (int i = 0; i < AILocalStepCount; i++) {
        _stepIcons[i] = [[NSImageView alloc] init];
        _stepIcons[i].translatesAutoresizingMaskIntoConstraints = NO;
        [_stepIcons[i].widthAnchor constraintEqualToConstant:18].active = YES;
        [_stepIcons[i].heightAnchor constraintEqualToConstant:18].active = YES;
        NSTextField* title = VOKLabel([AILocalSetup titleOfStep:(AILocalStep)i], 13, NSFontWeightMedium, nil);
        _stepDetails[i] = Wrapped(@"", 11, NSFontWeightRegular, [NSColor secondaryLabelColor], kInner - 28);
        _stepBars[i] = [[NSProgressIndicator alloc] init];
        _stepBars[i].style = NSProgressIndicatorStyleBar;
        _stepBars[i].minValue = 0;
        _stepBars[i].maxValue = 1;
        _stepBars[i].translatesAutoresizingMaskIntoConstraints = NO;
        [_stepBars[i].widthAnchor constraintEqualToConstant:kInner - 28].active = YES;
        NSStackView* header = Stack(@[_stepIcons[i], title], NO, 8);
        NSStackView* text = Stack(@[_stepDetails[i], _stepBars[i]], YES, 3);
        text.edgeInsets = NSEdgeInsetsMake(0, 26, 0, 0);
        _stepRows[i] = Stack(@[header, text], YES, 3);
        [stepViews addObject:_stepRows[i]];
    }
    _resultLabel = Wrapped(@"", 13, NSFontWeightSemibold, nil, kInner);
    [stepViews addObject:_resultLabel];
    NSView* progress = Section(@"Tiến trình", stepViews);
    _progressSection = progress;

    _installButton = [self buttonWithTitle:@"Cài đặt" action:@selector(install:)];
    _installButton.keyEquivalent = @"\r";
    _cancelButton = [self buttonWithTitle:@"Dừng" action:@selector(cancel:)];
    _removeButton = [self buttonWithTitle:@"Xóa model này khỏi máy…" action:@selector(removeModel:)];
    NSView* spacer = [[NSView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* buttons = Stack(@[_removeButton, spacer, _cancelButton, _installButton], NO, 10);
    [buttons.widthAnchor constraintEqualToConstant:kInner + 32].active = YES;

    NSTextField* title = VOKLabel(@"Cài AI chạy trên máy này", 20, NSFontWeightBold, nil);
    NSTextField* intro = Wrapped(@"AI chạy ngay trên Mac của bạn: không cần API key, không tính tiền theo lượt dùng, và chữ bạn viết không rời khỏi máy. "
                                 @"Đổi lại, máy phải đủ mạnh và đang ít việc: chạy model dùng hết sức bộ xử lý và chiếm nhiều RAM. VOpenKey AI kiểm tra máy rồi mới khuyên bạn chọn model nào.", 12, NSFontWeightRegular,
                                 [NSColor secondaryLabelColor], kInner + 32);
    NSStackView* content = Stack(@[title, intro, machine, choose, notes, progress, buttons], YES, 16);
    content.edgeInsets = NSEdgeInsetsMake(24, 24, 24, 24);
    content.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView* scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    NSView* documentView = [[NSView alloc] init];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    [documentView addSubview:content];
    scroll.documentView = documentView;
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:documentView.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor],
        [documentView.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
    ]];

    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowWidth, 760)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"Cài AI chạy trên máy";
    _window.releasedWhenClosed = NO;
    _window.tabbingMode = NSWindowTabbingModeDisallowed;
    _window.delegate = self;
    _window.contentView = scroll;
    _window.minSize = NSMakeSize(kWindowWidth, 420);
    _window.maxSize = NSMakeSize(kWindowWidth, 1400);
    [_window center];
    [self reloadAll];
}

#pragma mark - Showing

-(void)present {
    [self buildIfNeeded];
    if (!_hardwareGiven)
        [self refreshHardware:nil];                     //the Mac may have changed since the window was last open
    [NSApp activateIgnoringOtherApps:YES];
    [_window makeKeyAndOrderFront:nil];
}

-(void)close {
    [_window close];
}

-(void)refreshHardware:(id)sender {
    if (_setup.running)
        return;                                         //the Mac does not change under an installation that is going on
    if (sender != nil || !_hardwareGiven)
        _hardware = [AIHardware currentForDirectory:_modelsDirectory];
    [self reloadAll];
}

#pragma mark - What the Mac and the model say

static NSImage* Dot(NSColor* color) {
    return [NSImage imageWithSize:NSMakeSize(10, 10) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [color setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 1, 1)] fill];
        return YES;
    }];
}

static NSString* Stars(NSInteger value) {
    NSMutableString* text = [NSMutableString string];
    for (NSInteger i = 1; i <= 5; i++)
        [text appendString:i <= value ? @"★" : @"☆"];
    return text;
}

-(AIModelFit)fitOfModel:(AILocalModel*)model {
    return [AIModelAdvisor assessModel:model hardware:_hardware runtimeInstalled:_setup.runtime.isInstalled modelDownloaded:[_installedTags containsObject:model.tag]].fit;
}

-(void)reloadAll {
    _installedTags = [AILocalSetup installedTagsInModelsDirectory:_modelsDirectory];
    _recommended = [AIModelAdvisor recommendedModelAmong:_catalog hardware:_hardware];
    NSString* keep = self.selectedModel.tag;
    BOOL keepCustomChoice = _modelPopUp.numberOfItems > 0 && _modelPopUp.indexOfSelectedItem >= (NSInteger)_catalog.count;   //"other", even if nothing is typed yet

    _machineLabel.stringValue = [_hardware summary];
    _overviewLabel.stringValue = [AIModelAdvisor overviewForHardware:_hardware models:_catalog];

    [_modelPopUp removeAllItems];
    for (AILocalModel* model in _catalog) {
        AIModelAssessment* a = [AIModelAdvisor assessModel:model hardware:_hardware runtimeInstalled:_setup.runtime.isInstalled
                                           modelDownloaded:[_installedTags containsObject:model.tag]];
        NSString* title = [NSString stringWithFormat:@"%@  ·  %@  ·  %@", model.name, VOKAIFormatBytes(model.bytes), a.headline];
        if (model == _recommended)
            title = [title stringByAppendingString:@"  ★ Khuyên dùng"];
        if ([_installedTags containsObject:model.tag])
            title = [title stringByAppendingString:@"  ✓ Đã cài"];
        [_modelPopUp addItemWithTitle:title];
        _modelPopUp.lastItem.image = Dot(a.fit == AIModelFitSmooth ? [NSColor systemGreenColor] : (a.fit == AIModelFitTight ? [NSColor systemOrangeColor] : [NSColor systemRedColor]));
    }
    [_modelPopUp addItemWithTitle:@"Model khác (tự nhập tên)…"];
    NSInteger index = 0;
    for (NSUInteger i = 0; i < _catalog.count; i++) {
        if (keep != nil && [_catalog[i].tag isEqualToString:keep])
            index = (NSInteger)i;
        else if (keep == nil && _catalog[i] == _recommended)
            index = (NSInteger)i;
    }
    if (keepCustomChoice)
        index = (NSInteger)_catalog.count;
    if (_catalog.count == 0)
        index = 0;
    [_modelPopUp selectItemAtIndex:index];
    [self reloadSelection];
    [self reloadProgress];
}

-(void)modelPopUpChanged:(id)sender {
    [self reloadSelection];
    [self reloadProgress];
}

-(void)selectModelWithTag:(NSString*)tag {
    [self buildIfNeeded];
    for (NSUInteger i = 0; i < _catalog.count; i++)
        if ([_catalog[i].tag isEqualToString:tag])
            [_modelPopUp selectItemAtIndex:(NSInteger)i];
    [self modelPopUpChanged:nil];
}

/// Everything under the popup: the model, what it needs, what the Mac says about it.
-(void)reloadSelection {
    BOOL custom = _modelPopUp.indexOfSelectedItem >= (NSInteger)_catalog.count;
    _customRow.hidden = !custom;
    AILocalModel* model = self.selectedModel;
    if (custom && _customModel == nil) {
        _assessment = nil;
        _summaryLabel.stringValue = @"Nhập tên một model của thư viện Ollama (ollama.com/library). VOpenKey AI tra dung lượng của nó rồi đánh giá máy bạn có chạy nổi không.";
        _requirementsLabel.stringValue = @"";
        _verdictLabel.stringValue = @"";
        _problemsLabel.stringValue = @"";
        _notesLabel.stringValue = [self notesForModel:nil];
        [self reloadButtons];
        return;
    }
    if (model == nil) {
        _assessment = nil;
        _summaryLabel.stringValue = @"Danh sách model không đọc được. Hãy cài lại VOpenKey AI.";
        [self reloadButtons];
        return;
    }
    BOOL downloaded = [_installedTags containsObject:model.tag];
    _assessment = [AIModelAdvisor assessModel:model hardware:_hardware runtimeInstalled:_setup.runtime.isInstalled modelDownloaded:downloaded];
    AIModelAssessment* a = _assessment;

    NSMutableString* summary = [NSMutableString stringWithString:model.summary];
    if (!model.isCustom)
        [summary appendFormat:@"\nChất lượng %@   Tốc độ %@   Tiếng Việt: %@", Stars(model.quality), Stars(model.speed), model.vietnamese];
    _summaryLabel.stringValue = summary;

    NSString* ramNow = [NSString stringWithFormat:@"%.0f GB", round(_hardware.memoryBytes / 1073741824.0)];
    NSMutableString* needs = [NSMutableString string];
    if (model.bytes > 0) {
        NSString* ramNeeded = a.minimumRAMGB == a.comfortableRAMGB
            ? [NSString stringWithFormat:@"từ %ld GB", (long)a.minimumRAMGB]
            : [NSString stringWithFormat:@"từ %ld GB (thoải mái từ %ld GB)", (long)a.minimumRAMGB, (long)a.comfortableRAMGB];
        [needs appendFormat:@"Dung lượng tải: %@. Bộ nhớ khi chạy: khoảng %@. Cần RAM %@; máy bạn có %@.",
         VOKAIFormatBytes(model.bytes), VOKAIFormatBytes(a.memoryNeededBytes), ramNeeded, ramNow];
        if (a.diskNeededBytes > 0)
            [needs appendFormat:@"\nỔ đĩa cần trống: %@ (đã tính chỗ để macOS hoạt động); còn trống %@.", VOKAIFormatBytes(a.diskNeededBytes), VOKAIFormatBytes(_hardware.freeDiskBytes)];
        else
            [needs appendString:@"\nModel đã có trong máy, không cần tải thêm."];
    } else {
        [needs appendString:@"Chưa biết dung lượng model này."];
    }
    _requirementsLabel.stringValue = needs;

    _verdictLabel.stringValue = a.headline;
    _verdictLabel.textColor = a.blockers.count > 0 ? [NSColor systemRedColor] : (a.fit == AIModelFitTight || a.warnings.count > 0 ? [NSColor systemOrangeColor] : [NSColor systemGreenColor]);
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    for (NSString* blocker in a.blockers)
        [lines addObject:[@"⛔ " stringByAppendingString:blocker]];
    for (NSString* warning in a.warnings)
        [lines addObject:[@"⚠️ " stringByAppendingString:warning]];
    if (a.blockers.count == 0 && a.warnings.count == 0)
        [lines addObject:@"✓ Máy bạn đủ sức chạy model này thoải mái."];
    _problemsLabel.stringValue = [lines componentsJoinedByString:@"\n"];
    _notesLabel.stringValue = [self notesForModel:model];
    [self reloadButtons];
}

-(NSString*)notesForModel:(AILocalModel*)model {
    BOOL installed = _setup.runtime.isInstalled;
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    if (installed)
        [lines addObject:@"• Ollama (chương trình chạy model) đã có trên máy, không cài lại."];
    else
        [lines addObject:[NSString stringWithFormat:@"• Ollama, chương trình mã nguồn mở chạy model: tải bản chính thức từ GitHub (khoảng 207 MB, chiếm %@ sau khi cài), kiểm tra mã SHA-256, chữ ký và công chứng của Apple rồi cài vào thư mục ~/Applications của bạn. Không cần quyền quản trị. Cần macOS %ld trở lên.",
                          VOKAIFormatBytes([AIModelAdvisor runtimeDiskBytes] * 64 / 100), (long)[AIModelAdvisor runtimeMinimumMajorOS]]];
    if (model != nil && model.bytes > 0)
        [lines addObject:[NSString stringWithFormat:@"• Model %@: tải từ thư viện của Ollama về ~/.ollama/models (%@). Mất bao lâu tùy đường mạng của bạn; mạng chập chờn thì VOpenKey AI tự thử lại vài lần, hết lượt mà vẫn lỗi thì bấm Cài đặt lần nữa để tải tiếp, không phải tải lại từ đầu. Máy được giữ không ngủ trong lúc cài.", model.name, VOKAIFormatBytes(model.bytes)]];
    else
        [lines addObject:@"• Model: tải từ thư viện của Ollama về ~/.ollama/models."];
    [lines addObject:@"• VOpenKey AI chỉ mở máy chủ Ollama khi bạn dùng trợ lý AI và tắt nó khi thoát VOpenKey AI. Máy chủ chỉ nhận kết nối từ chính máy này (127.0.0.1), không có biểu tượng thừa trên thanh menu, không tự cập nhật. Khi không dùng một lúc (10 phút), model được giải phóng khỏi RAM. Trong Cài đặt > AI có nút Khởi động, Dừng và Giải phóng RAM để bạn tự điều khiển khi thấy máy ì."];
    [lines addObject:@"• Lần đầu dùng, Ollama mất khoảng 20 đến 40 giây để khởi động và model cần nạp vào RAM nên câu trả lời đầu chậm hơn các câu sau."];
    [lines addObject:@"• Muốn gỡ: bấm \"Xóa model này khỏi máy\" để lấy lại chỗ, và kéo ~/Applications/Ollama.app vào thùng rác nếu không cần Ollama nữa."];
    return [lines componentsJoinedByString:@"\n"];
}

-(void)reloadButtons {
    AILocalModel* model = self.selectedModel;
    BOOL running = _setup.running;
    BOOL downloaded = model != nil && [_installedTags containsObject:model.tag];
    BOOL ready = _assessment != nil && _assessment.canInstall;
    BOOL operating = running || _setup.succeeded;
    _installButton.title = downloaded ? @"Dùng model này" : @"Cài đặt";
    _installButton.enabled = ready && !running;
    _cancelButton.hidden = !running;
    _removeButton.enabled = downloaded && !running;
    _removeButton.hidden = !downloaded;
    _modelPopUp.enabled = !running;
    _customField.enabled = !running;
    _refreshButton.enabled = !running;
    (void)operating;
}

#pragma mark - Another model, typed by the user

-(void)controlTextDidEndEditing:(NSNotification*)notification {
    if (notification.object == _customField)
        [self customModelEntered:_customField];
}

-(void)customModelEntered:(id)sender {
    NSString* text = _customField.stringValue;
    if ([text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) {
        _customModel = nil;
        _customStatus.stringValue = @"";
        [self reloadSelection];
        return;
    }
    NSString* tag = [AILocalModels validTagFromText:text];
    if (tag == nil) {
        _customModel = nil;
        _customStatus.stringValue = @"Tên không hợp lệ. Chỉ dùng chữ, số, dấu . _ - và một dấu : trước phần phiên bản (ví dụ qwen3:8b).";
        _customStatus.textColor = [NSColor systemRedColor];
        [self reloadSelection];
        return;
    }
    if (_customModel != nil && [_customModel.tag isEqualToString:tag])
        return;
    NSInteger serial = ++_customLookupSerial;
    _customStatus.stringValue = @"Đang tra dung lượng model trong thư viện Ollama…";
    _customStatus.textColor = [NSColor secondaryLabelColor];
    [AIOllama librarySizeOfTag:tag registry:_libraryURL completion:^(uint64_t bytes, NSError* error) {
        if (serial != self->_customLookupSerial)
            return;                                            //another name was typed meanwhile
        if (error != nil && error.code == VOKAILocalErrorNotFound) {
            self->_customModel = nil;
            self->_customStatus.stringValue = error.localizedDescription;
            self->_customStatus.textColor = [NSColor systemRedColor];
        } else {
            self->_customModel = [AILocalModel customModelWithTag:tag bytes:bytes];
            self->_customStatus.stringValue = error != nil ? [error.localizedDescription stringByAppendingString:@" Vẫn có thể cài, nhưng VOpenKey AI không đánh giá được máy có chạy nổi không."]
                : (bytes > 0 ? [NSString stringWithFormat:@"Tìm thấy %@: %@.", tag, VOKAIFormatBytes(bytes)] : @"Model ở nguồn khác nên không tra được dung lượng.");
            self->_customStatus.textColor = [NSColor secondaryLabelColor];
        }
        [self reloadSelection];
    }];
}

#pragma mark - Actions

-(void)install:(id)sender {
    AILocalModel* model = self.selectedModel;
    if (model == nil || _setup.running || _assessment == nil || !_assessment.canInstall)
        return;
    _resultLabel.stringValue = @"";
    [_setup installModel:model];
    [self reloadButtons];
}

-(void)cancel:(id)sender {
    [_setup cancel];
}

-(void)removeModel:(id)sender {
    AILocalModel* model = self.selectedModel;
    if (model == nil || _setup.running)
        return;
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Xóa model %@ khỏi máy?", model.name];
    alert.informativeText = [NSString stringWithFormat:@"Giải phóng %@ ổ đĩa. Bạn có thể cài lại bất cứ lúc nào (phải tải lại).", VOKAIFormatBytes(model.bytes)];
    [alert addButtonWithTitle:@"Xóa"];
    [alert addButtonWithTitle:@"Hủy"];
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn)
            return;
        self->_installButton.enabled = NO;
        self->_removeButton.enabled = NO;
        self->_resultLabel.stringValue = @"Đang xóa model…";
        self->_resultLabel.textColor = [NSColor secondaryLabelColor];
        [self->_setup removeModel:model completion:^(NSError* error) {
            self->_resultLabel.stringValue = error != nil ? [@"Không xóa được: " stringByAppendingString:error.localizedDescription] : [NSString stringWithFormat:@"Đã xóa %@.", model.name];
            self->_resultLabel.textColor = error != nil ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
            [self reloadAll];
        }];
    }];
}

-(void)setupFinished:(NSNotification*)notification {
    _installedTags = [AILocalSetup installedTagsInModelsDirectory:_modelsDirectory];
    [self reloadAll];
}

#pragma mark - Progress

static NSImage* IconForState(AILocalStepState state) {
    switch (state) {
        case AILocalStepRunning: return VOKSymbol(@"arrow.triangle.2.circlepath", 14, NSFontWeightRegular);
        case AILocalStepDone:    return VOKSymbol(@"checkmark.circle.fill", 15, NSFontWeightRegular);
        case AILocalStepSkipped: return VOKSymbol(@"checkmark.circle", 15, NSFontWeightRegular);
        case AILocalStepFailed:  return VOKSymbol(@"xmark.octagon.fill", 15, NSFontWeightRegular);
        default:                 return VOKSymbol(@"circle", 14, NSFontWeightRegular);
    }
}

-(void)reloadProgress {
    if (_window == nil)
        return;
    BOOL started = _setup.running || _setup.succeeded || _setup.error != nil;
    _progressSection.hidden = !started;                 //nothing to show before the first installation
    for (int i = 0; i < AILocalStepCount; i++) {
        AILocalStepState state = [_setup stateOfStep:(AILocalStep)i];
        _stepRows[i].hidden = !started;
        _stepIcons[i].image = IconForState(state);
        _stepIcons[i].contentTintColor = state == AILocalStepDone ? [NSColor systemGreenColor] : (state == AILocalStepFailed ? [NSColor systemRedColor]
                                           : (state == AILocalStepRunning ? [NSColor controlAccentColor] : [NSColor tertiaryLabelColor]));
        NSString* detail = [_setup detailOfStep:(AILocalStep)i];
        _stepDetails[i].stringValue = detail;
        _stepDetails[i].hidden = detail.length == 0;
        _stepDetails[i].textColor = state == AILocalStepFailed ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
        double fraction = [_setup fractionOfStep:(AILocalStep)i];
        BOOL showBar = state == AILocalStepRunning;
        _stepBars[i].hidden = !showBar;
        if (showBar) {
            _stepBars[i].indeterminate = fraction < 0;
            if (fraction >= 0)
                _stepBars[i].doubleValue = fraction;
            else
                [_stepBars[i] startAnimation:nil];
        } else {
            [_stepBars[i] stopAnimation:nil];
        }
    }
    if (_setup.succeeded) {
        _resultLabel.stringValue = [NSString stringWithFormat:@"Xong. Trợ lý AI giờ dùng %@ chạy trên máy bạn: chọn đoạn văn rồi bấm phím tắt của trợ lý AI (mặc định ⌃⌥A).", _setup.model.name];
        _resultLabel.textColor = [NSColor systemGreenColor];
    } else if (_setup.error != nil) {
        _resultLabel.stringValue = _setup.wasCancelled ? _setup.error.localizedDescription : @"Chưa xong. Xem bước bị lỗi ở trên, sửa nguyên nhân rồi bấm Cài đặt để thử lại.";
        _resultLabel.textColor = _setup.wasCancelled ? [NSColor secondaryLabelColor] : [NSColor systemOrangeColor];
    } else if (!_setup.running) {
        _resultLabel.stringValue = @"";
    }
    _resultLabel.hidden = _resultLabel.stringValue.length == 0;
    [self reloadButtons];
}

@end
