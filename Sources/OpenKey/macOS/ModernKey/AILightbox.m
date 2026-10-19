//
//  AILightbox.m
//  VOpenKey
//

#import "AILightbox.h"
#import "VOKUI.h"

static const CGFloat kMinZoom = 0.05, kMaxZoom = 8;
static NSURL* sDownloadsForTesting;

//keeps a picture smaller than the window in the middle of it
@interface AICenteringClipView : NSClipView
@end

@implementation AICenteringClipView
-(NSRect)constrainBoundsRect:(NSRect)proposed {
    NSRect rect = [super constrainBoundsRect:proposed];
    NSView* document = self.documentView;
    if (document != nil) {
        if (document.frame.size.width < proposed.size.width)
            rect.origin.x = (document.frame.size.width - proposed.size.width) / 2;
        if (document.frame.size.height < proposed.size.height)
            rect.origin.y = (document.frame.size.height - proposed.size.height) / 2;
    }
    return rect;
}
@end

@interface AILightboxPanel : NSPanel
@property (nonatomic, weak) AILightbox* lightbox;
@end

@implementation AILightboxPanel
-(BOOL)canBecomeKeyWindow { return YES; }
-(void)cancelOperation:(id)sender { [self.lightbox close]; }
-(void)keyDown:(NSEvent*)event {
    NSString* key = event.charactersIgnoringModifiers;
    if ([key isEqualToString:@"+"] || [key isEqualToString:@"="])
        [self.lightbox zoomIn];
    else if ([key isEqualToString:@"-"])
        [self.lightbox zoomOut];
    else if ([key isEqualToString:@"0"])
        [self.lightbox zoomToFit];
    else if ([key isEqualToString:@"1"])
        [self.lightbox zoomToActualSize];
    else
        [super keyDown:event];
}
@end

@interface AILightbox () <NSWindowDelegate>
@end

@implementation AILightbox {
    AILightboxPanel* _panel;
    NSScrollView* _scroll;
    NSImageView* _imageView;
    NSTextField* _zoomLabel;
    NSTextField* _status;
    NSButton* _copyButton;
    NSButton* _saveButton;
    NSButton* _revealButton;
    NSData* _png;
    NSImage* _image;
    NSString* _name;
    NSUInteger _feedback;           //a green check that was shown for an earlier action must not hide the one of a later action
    BOOL _showsCopied, _showsSaved;
    NSURL* _savedURL;
}

+(AILightbox*)shared {
    static AILightbox* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AILightbox alloc] init]; });
    return instance;
}

-(instancetype)init {
    self = [super init];
    if (self)
        _pasteboard = [NSPasteboard generalPasteboard];
    return self;
}

-(NSPanel*)panel { return _panel; }
-(BOOL)visible { return _panel.visible; }
-(BOOL)showsCopied { return _showsCopied; }
-(BOOL)showsSaved { return _showsSaved; }
-(NSURL*)savedURL { return _savedURL; }
-(NSTextField*)statusLabel { return _status; }

#pragma mark Building

-(NSButton*)toolButton:(NSString*)symbol tip:(NSString*)tip action:(SEL)action {
    NSButton* button = [NSButton buttonWithImage:VOKSymbol(symbol, 14, NSFontWeightRegular) target:self action:action];
    button.bordered = NO;
    button.contentTintColor = [NSColor labelColor];
    button.toolTip = tip;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setAccessibilityLabel:tip];
    [button.widthAnchor constraintEqualToConstant:30].active = YES;
    [button.heightAnchor constraintEqualToConstant:26].active = YES;
    return button;
}

-(void)buildIfNeeded {
    if (_panel != nil)
        return;
    _panel = [[AILightboxPanel alloc] initWithContentRect:NSMakeRect(0, 0, 820, 640)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered defer:YES];
    _panel.lightbox = self;
    _panel.floatingPanel = YES;
    _panel.level = NSStatusWindowLevel + 1;                //over the window of the assistant, which is at the status level
    _panel.hidesOnDeactivate = NO;
    _panel.releasedWhenClosed = NO;
    _panel.minSize = NSMakeSize(460, 340);
    _panel.delegate = self;
    _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSButton* zoomOut = [self toolButton:@"minus.magnifyingglass" tip:@"Thu nhỏ (-)" action:@selector(zoomOutPressed:)];
    NSButton* zoomIn = [self toolButton:@"plus.magnifyingglass" tip:@"Phóng to (+)" action:@selector(zoomInPressed:)];
    NSButton* fit = [self toolButton:@"arrow.up.left.and.arrow.down.right" tip:@"Vừa khung (0)" action:@selector(fitPressed:)];
    NSButton* actual = [self toolButton:@"1.magnifyingglass" tip:@"Kích thước thật (1)" action:@selector(actualPressed:)];
    _zoomLabel = VOKLabel(@"100%", 11, NSFontWeightMedium, [NSColor secondaryLabelColor]);
    _zoomLabel.alignment = NSTextAlignmentCenter;
    [_zoomLabel.widthAnchor constraintEqualToConstant:46].active = YES;
    _copyButton = [self toolButton:@"doc.on.doc" tip:@"Sao chép ảnh (⌘C)" action:@selector(copyPressed:)];
    _saveButton = [self toolButton:@"square.and.arrow.down" tip:@"Lưu vào thư mục Downloads (⌘S)" action:@selector(savePressed:)];
    _revealButton = [self toolButton:@"folder" tip:@"Hiện file đã lưu trong Finder" action:@selector(revealPressed:)];
    _revealButton.hidden = YES;
    NSView* spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    _status = VOKLabel(@"", 11, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    _status.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_status setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* bar = [NSStackView stackViewWithViews:@[zoomOut, _zoomLabel, zoomIn, fit, actual, spacer, _status, _copyButton, _saveButton, _revealButton]];
    bar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bar.alignment = NSLayoutAttributeCenterY;
    bar.spacing = 4;
    bar.edgeInsets = NSEdgeInsetsMake(6, 10, 6, 10);
    bar.translatesAutoresizingMaskIntoConstraints = NO;

    _scroll = [[NSScrollView alloc] init];
    _scroll.contentView = [[AICenteringClipView alloc] init];
    _scroll.hasVerticalScroller = YES;
    _scroll.hasHorizontalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _scroll.allowsMagnification = YES;
    _scroll.minMagnification = kMinZoom;
    _scroll.maxMagnification = kMaxZoom;
    _scroll.drawsBackground = YES;
    _scroll.backgroundColor = [NSColor colorWithWhite:0.12 alpha:1];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView = [[NSImageView alloc] init];
    _imageView.imageScaling = NSImageScaleNone;
    _scroll.documentView = _imageView;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(magnified:) name:NSScrollViewDidEndLiveMagnifyNotification object:_scroll];

    NSView* content = [[NSView alloc] init];
    [content addSubview:bar];
    [content addSubview:_scroll];
    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:content.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_scroll.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
    _panel.contentView = content;
}

#pragma mark Showing

-(void)showImage:(NSImage*)image png:(NSData*)png name:(NSString*)name over:(NSWindow*)window {
    [self buildIfNeeded];
    _image = image;
    _png = png;
    _name = name;
    _savedURL = nil;
    _showsCopied = _showsSaved = NO;
    _feedback++;
    [self setStatus:@"" green:NO];
    [self updateButtons];
    _panel.title = name.length > 0 ? name : @"Ảnh";
    _imageView.image = image;
    NSSize size = image.size;
    _imageView.frame = NSMakeRect(0, 0, size.width, size.height);

    //about the size of the window of the assistant's screen, never bigger than 90% of it, and not smaller than what fits the picture at its size
    NSScreen* screen = window.screen ?: [NSScreen mainScreen];
    NSRect visible = screen.visibleFrame;
    NSSize wanted = NSMakeSize(MIN(MAX(size.width + 40, 640), visible.size.width * 0.9), MIN(MAX(size.height + 110, 520), visible.size.height * 0.9));
    [_panel setContentSize:wanted];
    if (self.offscreenForTesting) {
        [_panel setFrameOrigin:NSMakePoint(-30000, -30000)];
        [_panel orderFront:nil];
    } else {
        [_panel setFrameOrigin:NSMakePoint(NSMidX(visible) - _panel.frame.size.width / 2, NSMidY(visible) - _panel.frame.size.height / 2)];
        [_panel makeKeyAndOrderFront:nil];
    }
    [_panel.contentView layoutSubtreeIfNeeded];
    [self zoomToFit];
}

-(void)close {
    [_panel orderOut:nil];
    _imageView.image = nil;
    _image = nil;
    _png = nil;
}

-(void)windowWillClose:(NSNotification*)notification {
    _imageView.image = nil;
    _image = nil;
    _png = nil;
}

#pragma mark Zoom

-(CGFloat)zoom {
    return _scroll.magnification;
}

-(void)setZoom:(CGFloat)zoom {
    zoom = MIN(MAX(zoom, kMinZoom), kMaxZoom);
    NSRect visible = _scroll.contentView.bounds;
    [_scroll setMagnification:zoom centeredAtPoint:NSMakePoint(NSMidX(visible), NSMidY(visible))];
    _zoomLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", _scroll.magnification * 100];
}

-(void)magnified:(NSNotification*)notification {
    _zoomLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", _scroll.magnification * 100];
}

//steps that feel the same at any size: a quarter more or less each time
-(void)zoomIn { self.zoom = self.zoom * 1.25; }
-(void)zoomOut { self.zoom = self.zoom / 1.25; }
-(void)zoomToActualSize { self.zoom = 1; }

-(void)zoomToFit {
    if (_image == nil)
        return;
    NSSize area = _scroll.contentSize;
    NSSize size = _image.size;
    if (size.width <= 0 || size.height <= 0)
        return;
    //smaller than the window: shown as it is; bigger: made to fit
    self.zoom = MIN(1, MIN(area.width / size.width, area.height / size.height));
}

-(void)zoomInPressed:(id)sender { [self zoomIn]; }
-(void)zoomOutPressed:(id)sender { [self zoomOut]; }
-(void)fitPressed:(id)sender { [self zoomToFit]; }
-(void)actualPressed:(id)sender { [self zoomToActualSize]; }

#pragma mark Copy and save

-(void)updateButtons {
    _copyButton.enabled = _png != nil;
    _saveButton.enabled = _png != nil;
    _revealButton.hidden = _savedURL == nil;
    NSColor* green = [NSColor systemGreenColor];
    _copyButton.image = VOKSymbol(_showsCopied ? @"checkmark.circle.fill" : @"doc.on.doc", 14, NSFontWeightRegular);
    _copyButton.contentTintColor = _showsCopied ? green : [NSColor labelColor];
    _saveButton.image = VOKSymbol(_showsSaved ? @"checkmark.circle.fill" : @"square.and.arrow.down", 14, NSFontWeightRegular);
    _saveButton.contentTintColor = _showsSaved ? green : [NSColor labelColor];
}

-(void)setStatus:(NSString*)text green:(BOOL)green {
    _status.stringValue = text;
    _status.textColor = green ? [NSColor systemGreenColor] : [NSColor secondaryLabelColor];
}

//the check stays for a moment and goes; a later action keeps its own
-(void)flash:(BOOL)copied text:(NSString*)text {
    NSUInteger mine = ++_feedback;
    _showsCopied = copied;
    _showsSaved = !copied;
    [self setStatus:text green:YES];
    [self updateButtons];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (mine != self->_feedback)
            return;
        self->_showsCopied = self->_showsSaved = NO;
        [self setStatus:@"" green:NO];
        [self updateButtons];
    });
}

-(void)copyImage {
    if (_png == nil)
        return;
    [_pasteboard clearContents];
    NSPasteboardItem* item = [[NSPasteboardItem alloc] init];
    [item setData:_png forType:NSPasteboardTypePNG];
    NSData* tiff = _image.TIFFRepresentation;
    if (tiff != nil)
        [item setData:tiff forType:NSPasteboardTypeTIFF];
    [_pasteboard writeObjects:@[item]];
    [self flash:YES text:@"Đã sao chép ảnh"];
}

-(NSURL*)saveImage:(NSError**)error {
    if (_png == nil)
        return nil;
    NSURL* url = [AILightbox savePNG:_png toFolder:[AILightbox downloadsFolder] error:error];
    if (url == nil) {
        [self setStatus:(error != NULL && *error != nil) ? (*error).localizedDescription : @"Không lưu được ảnh." green:NO];
        _status.textColor = [NSColor systemRedColor];
        return nil;
    }
    _savedURL = url;
    [self flash:NO text:[NSString stringWithFormat:@"Đã lưu vào Downloads: %@", url.lastPathComponent]];
    return url;
}

-(void)copyPressed:(id)sender { [self copyImage]; }
-(void)savePressed:(id)sender { [self saveImage:nil]; }
-(void)revealPressed:(id)sender {
    if (_savedURL != nil)
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[_savedURL]];
}

+(NSURL*)downloadsFolder {
    if (sDownloadsForTesting != nil)
        return sDownloadsForTesting;
    return [[NSFileManager defaultManager] URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject
        ?: [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"]];
}

+(void)setDownloadsFolderForTesting:(NSURL*)folder {
    sDownloadsForTesting = folder;
}

+(NSURL*)savePNG:(NSData*)png toFolder:(NSURL*)folder error:(NSError**)error {
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd HH.mm.ss";
    NSString* base = [NSString stringWithFormat:@"Ảnh AI %@", [formatter stringFromDate:[NSDate date]]];
    NSFileManager* manager = [NSFileManager defaultManager];
    [manager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    for (int number = 1; number < 1000; number++) {
        NSString* name = number == 1 ? [base stringByAppendingString:@".png"] : [NSString stringWithFormat:@"%@ %d.png", base, number];
        NSURL* url = [folder URLByAppendingPathComponent:name];
        if ([manager fileExistsAtPath:url.path])
            continue;                                       //never over a file that is there
        if ([png writeToURL:url options:NSDataWritingWithoutOverwriting error:error])
            return url;
        return nil;
    }
    if (error != NULL)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError userInfo:@{NSLocalizedDescriptionKey: @"Không đặt được tên cho file ảnh."}];
    return nil;
}

@end
