//
//  SuggestionPanel.m
//  VOpenKey
//

#import "SuggestionPanel.h"
#import <QuartzCore/QuartzCore.h>

//Corners are concentric: the bar is as round as an item plus the space around the item
static const CGFloat kItemRadius = 6;
static const CGFloat kPadding = 4;
static const CGFloat kBarRadius = kItemRadius + kPadding;
static const CGFloat kItemHeight = 26;
static const CGFloat kItemPadding = 10;   //left and right of the text inside an item
static const CGFloat kItemGap = 2;
static const CGFloat kLabelGap = 6;       //between the key hint and the word
static const CGFloat kScreenMargin = 6;
static const CGFloat kDistanceFromText = 4;
static const NSTimeInterval kFadeIn = 0.12;
static const NSTimeInterval kHoverDelay = 1.2; //give the user time to read before the bar yields to the pointer
static const NSTimeInterval kHoverFade = 0.25;
static NSString* const kTransparencyKey = @"SuggestionTransparencyPercent";
static NSString* const kHoverTransparencyKey = @"SuggestionHoverTransparencyPercent";
static NSNotificationName const kTransparencyChanged = @"VOKSuggestionTransparencyChanged";

#pragma mark - The words

@interface SuggestionItemsView : NSView
@property (nonatomic, copy) NSArray<NSString*>* words;
@property (nonatomic) BOOL firstWordUsesTab;
-(NSSize)contentSize;
@end

@implementation SuggestionItemsView

-(BOOL)isFlipped {
    return YES;
}

-(BOOL)isOpaque {
    return NO;
}

//⌥1, ⌥2... in the way macOS writes shortcuts; Tab for the first one when it is allowed to
-(NSString*)hintAtIndex:(NSUInteger)index {
    if (index == 0 && self.firstWordUsesTab)
        return @"⇥";
    return [NSString stringWithFormat:@"⌥%lu", (unsigned long)index + 1];
}

-(NSDictionary*)wordAttributes:(BOOL)selected {
    return @{NSFontAttributeName: [NSFont systemFontOfSize:15],
             NSForegroundColorAttributeName: selected ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor]};
}

-(NSDictionary*)hintAttributes:(BOOL)selected {
    return @{NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular],
             NSForegroundColorAttributeName: selected ? [[NSColor alternateSelectedControlTextColor] colorWithAlphaComponent:0.8]
                                                      : [NSColor secondaryLabelColor]};
}

-(CGFloat)widthOfItem:(NSUInteger)index {
    BOOL selected = index == 0;
    CGFloat hint = ceil([[self hintAtIndex:index] sizeWithAttributes:[self hintAttributes:selected]].width);
    CGFloat word = ceil([self.words[index] sizeWithAttributes:[self wordAttributes:selected]].width);
    return kItemPadding + hint + kLabelGap + word + kItemPadding;
}

-(NSSize)contentSize {
    CGFloat width = kPadding;
    for (NSUInteger i = 0; i < self.words.count; i++)
        width += [self widthOfItem:i] + (i > 0 ? kItemGap : 0);
    return NSMakeSize(width + kPadding, kItemHeight + 2 * kPadding);
}

-(void)drawRect:(NSRect)dirtyRect {
    //hairline around the bar, drawn here so that its colour follows light and dark
    NSBezierPath* outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.25, 0.25)
                                                            xRadius:kBarRadius yRadius:kBarRadius];
    outline.lineWidth = 0.5;
    [[NSColor separatorColor] setStroke];
    [outline stroke];

    CGFloat x = kPadding;
    for (NSUInteger i = 0; i < self.words.count; i++) {
        BOOL selected = i == 0;
        CGFloat width = [self widthOfItem:i];
        NSRect item = NSMakeRect(x, kPadding, width, kItemHeight);
        if (selected) {
            [[NSColor controlAccentColor] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:item xRadius:kItemRadius yRadius:kItemRadius] fill];
        }
        NSString* hint = [self hintAtIndex:i];
        NSDictionary* hintAttributes = [self hintAttributes:selected];
        NSDictionary* wordAttributes = [self wordAttributes:selected];
        NSSize hintSize = [hint sizeWithAttributes:hintAttributes];
        NSSize wordSize = [self.words[i] sizeWithAttributes:wordAttributes];
        CGFloat left = x + kItemPadding;
        //the key hint and the word are smaller and larger text on one baseline, centred as a whole on the item
        NSFont* hintFont = hintAttributes[NSFontAttributeName];
        NSFont* wordFont = wordAttributes[NSFontAttributeName];
        CGFloat baseline = NSMidY(item) - wordSize.height / 2 + wordFont.ascender;
        [hint drawAtPoint:NSMakePoint(left, baseline - hintFont.ascender) withAttributes:hintAttributes];
        [self.words[i] drawAtPoint:NSMakePoint(left + ceil(hintSize.width) + kLabelGap, baseline - wordFont.ascender)
                    withAttributes:wordAttributes];
        x += width + kItemGap;
    }
}

-(void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

@end

#pragma mark - The panel

//Stretchable rounded mask: the system uses it to cut the blur and to shape the shadow
static NSImage* BarMask(void) {
    CGFloat side = kBarRadius * 2 + 1;
    NSImage* mask = [NSImage imageWithSize:NSMakeSize(side, side) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor blackColor] set];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:kBarRadius yRadius:kBarRadius] fill];
        return YES;
    }];
    mask.capInsets = NSEdgeInsetsMake(kBarRadius, kBarRadius, kBarRadius, kBarRadius);
    mask.resizingMode = NSImageResizingModeStretch;
    return mask;
}

@implementation SuggestionPanel {
    SuggestionItemsView* _items;
    BOOL _firstWordUsesTab;
    id _mouseMonitor;
    NSTimer* _hoverTimer;
    BOOL _faded;
}

+(NSInteger)transparencyPercent {
    return MAX(0, MIN(80, [NSUserDefaults.standardUserDefaults integerForKey:kTransparencyKey]));
}

+(void)setTransparencyPercent:(NSInteger)percent {
    percent = MAX(0, MIN(80, percent));
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:percent forKey:kTransparencyKey];
    id savedHoverPercent = [defaults objectForKey:kHoverTransparencyKey];
    NSInteger hoverPercent = savedHoverPercent ? [savedHoverPercent integerValue] : 85;
    if (hoverPercent <= percent)
        [defaults setInteger:percent + 1 forKey:kHoverTransparencyKey];
    [NSNotificationCenter.defaultCenter postNotificationName:kTransparencyChanged object:nil];
}

+(NSInteger)hoverTransparencyPercent {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    NSInteger saved = [defaults objectForKey:kHoverTransparencyKey] ? [defaults integerForKey:kHoverTransparencyKey] : 85;
    return MAX([self transparencyPercent] + 1, MIN(95, MAX(1, saved)));
}

+(void)setHoverTransparencyPercent:(NSInteger)percent {
    NSInteger minimum = self.transparencyPercent + 1;
    [NSUserDefaults.standardUserDefaults setInteger:MAX(minimum, MIN(95, percent)) forKey:kHoverTransparencyKey];
    [NSNotificationCenter.defaultCenter postNotificationName:kTransparencyChanged object:nil];
}

-(CGFloat)preferredAlpha {
    return 1 - SuggestionPanel.transparencyPercent / 100.0;
}

-(CGFloat)hoverAlpha {
    return 1 - SuggestionPanel.hoverTransparencyPercent / 100.0;
}

-(void)transparencyChanged:(NSNotification*)notification {
    self.alphaValue = _faded ? self.hoverAlpha : self.preferredAlpha;
}

-(instancetype)init {
    self = [super initWithContentRect:NSMakeRect(0, 0, 120, kItemHeight + 2 * kPadding)
                            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                              backing:NSBackingStoreBuffered
                                defer:YES];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = [NSColor clearColor];
        self.hasShadow = YES;
        self.level = NSPopUpMenuWindowLevel;
        self.floatingPanel = YES;
        self.hidesOnDeactivate = NO;
        self.ignoresMouseEvents = YES;
        self.releasedWhenClosed = NO;
        self.animationBehavior = NSWindowAnimationBehaviorNone;
        self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                  NSWindowCollectionBehaviorStationary |
                                  NSWindowCollectionBehaviorFullScreenAuxiliary |
                                  NSWindowCollectionBehaviorIgnoresCycle;

        //the material of menus: it follows light and dark, the accent colour and "Reduce transparency" by itself
        NSVisualEffectView* background = [[NSVisualEffectView alloc] initWithFrame:self.contentView.bounds];
        background.material = NSVisualEffectMaterialMenu;
        background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        background.state = NSVisualEffectStateActive;
        background.maskImage = BarMask();
        self.contentView = background;

        _items = [[SuggestionItemsView alloc] initWithFrame:background.bounds];
        _items.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [background addSubview:_items];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(transparencyChanged:)
                                                   name:kTransparencyChanged object:nil];
    }
    return self;
}

//never the window that receives the typing
-(BOOL)canBecomeKeyWindow {
    return NO;
}

-(BOOL)canBecomeMainWindow {
    return NO;
}

-(void)setFirstWordUsesTab:(BOOL)uses {
    _firstWordUsesTab = uses;
    _items.firstWordUsesTab = uses;
}

-(void)setWords:(NSArray<NSString*>*)words {
    _items.words = words;
    [self setContentSize:[_items contentSize]];
    _items.needsDisplay = YES;
    [self invalidateShadow];
}

-(NSScreen*)screenContaining:(NSPoint)point {
    for (NSScreen* screen in [NSScreen screens]) {
        if (NSPointInRect(point, screen.frame))
            return screen;
    }
    return [NSScreen mainScreen];
}

//The bar ignores the mouse, so it is told where the pointer is by a global monitor (no permission needed for mouse moves)
-(void)startWatchingPointer {
    if (_mouseMonitor)
        return;
    __weak SuggestionPanel* weakSelf = self;
    _mouseMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged | NSEventMaskScrollWheel
                                                           handler:^(NSEvent* event) {
        [weakSelf updateFadeForPointer];
    }];
}

-(void)stopWatchingPointer {
    if (_mouseMonitor)
        [NSEvent removeMonitor:_mouseMonitor];
    _mouseMonitor = nil;
    [_hoverTimer invalidate];
    _hoverTimer = nil;
    _faded = NO;
}

-(void)updateFadeForPointer {
    BOOL over = self.visible && NSPointInRect([NSEvent mouseLocation], self.frame);
    if (!over) {
        [_hoverTimer invalidate];
        _hoverTimer = nil;
        [self setPointerFaded:NO];
        return;
    }
    //Suggestion updates and mouse moves inside the bar must not restart the grace period.
    if (_faded || _hoverTimer)
        return;
    __weak SuggestionPanel* weakSelf = self;
    _hoverTimer = [NSTimer scheduledTimerWithTimeInterval:kHoverDelay repeats:NO block:^(NSTimer* timer) {
        SuggestionPanel* panel = weakSelf;
        if (!panel)
            return;
        panel->_hoverTimer = nil;
        [panel setPointerFaded:panel.visible && NSPointInRect([NSEvent mouseLocation], panel.frame)];
    }];
}

-(void)setPointerFaded:(BOOL)faded {
    if (faded == _faded)
        return;
    _faded = faded;
    CGFloat alpha = faded ? self.hoverAlpha : self.preferredAlpha;
    if ([[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion]) {
        self.alphaValue = alpha;
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.duration = kHoverFade;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self.animator.alphaValue = alpha;
    }];
}

-(void)orderOut:(id)sender {
    [self stopWatchingPointer];
    [super orderOut:sender];
}

-(void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self stopWatchingPointer];
}

-(void)show {
    [self startWatchingPointer];
    if (self.visible) {
        [self updateFadeForPointer]; //the bar may have moved or grown under a resting pointer
        return;
    }
    if ([[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion]) {
        self.alphaValue = self.preferredAlpha;
        [self orderFrontRegardless];
        [self updateFadeForPointer];
        return;
    }
    self.alphaValue = 0;
    [self orderFrontRegardless];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.duration = kFadeIn;
        self.animator.alphaValue = self.preferredAlpha;
    }];
    [self updateFadeForPointer];
}

+(NSPoint)originForBarOfSize:(NSSize)size line:(NSRect)line visibleFrame:(NSRect)visible {
    //the first word starts where the typed word starts
    CGFloat x = line.origin.x - kPadding - kItemPadding;
    x = MAX(visible.origin.x + kScreenMargin, MIN(x, NSMaxX(visible) - size.width - kScreenMargin));
    CGFloat y = line.origin.y - size.height - kDistanceFromText;
    if (y < visible.origin.y + kScreenMargin) //no room below: above the line
        y = MIN(NSMaxY(line) + kDistanceFromText, NSMaxY(visible) - size.height - kScreenMargin);
    return NSMakePoint(x, y);
}

-(void)showBelowRect:(NSRect)line {
    NSRect visible = [self screenContaining:line.origin].visibleFrame;
    NSPoint origin = [SuggestionPanel originForBarOfSize:self.frame.size line:line visibleFrame:visible];
    if (!NSEqualPoints(origin, self.frame.origin))
        [self setFrameOrigin:origin];
    [self show];
}

-(void)showNearPoint:(NSPoint)point {
    [self showBelowRect:NSMakeRect(point.x, point.y - 22, 0, 22)];
}

@end
