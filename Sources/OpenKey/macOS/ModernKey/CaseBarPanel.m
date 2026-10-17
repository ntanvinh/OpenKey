//
//  CaseBarPanel.m
//  VOpenKey
//

#import "CaseBarPanel.h"
#import "SuggestionPanel.h"

//Same proportions as the suggestion bar, so that the two feel like one thing: concentric corners
static const CGFloat kItemRadius = 6;
static const CGFloat kPadding = 5;
static const CGFloat kBarRadius = kItemRadius + kPadding;
static const CGFloat kItemHeight = 26;
static const CGFloat kItemPadding = 10;
static const CGFloat kSeparatorHeight = 9;      //room for the line under a row whose offer says "separatorAfter"
static const CGFloat kHintWidth = 26;
static const CGFloat kColumnGap = 12;
static const CGFloat kPreviewWidth = 230;
static const CGFloat kScreenMargin = 6;
static const NSTimeInterval kFadeIn = 0.12;

#pragma mark - The rows

@interface CaseBarListView : NSView
@property (nonatomic, copy) NSArray<NSDictionary*>* offers;
@property (nonatomic) NSInteger highlighted;
@property (nonatomic, copy) void (^onChoose)(NSInteger index);
@property (nonatomic, copy) void (^onHighlight)(NSInteger index);
-(NSSize)contentSize;
@end

@implementation CaseBarListView {
    CGFloat _nameWidth;
}

-(BOOL)isFlipped {
    return YES;
}

-(BOOL)isOpaque {
    return NO;
}

//a click on the list is for the list, even when VOpenKey is not the application in front
-(BOOL)acceptsFirstMouse:(NSEvent*)event {
    return YES;
}

-(NSDictionary*)nameAttributes:(BOOL)lit {
    return @{NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
             NSForegroundColorAttributeName: lit ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor]};
}

-(NSDictionary*)hintAttributes:(BOOL)lit {
    return @{NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular],
             NSForegroundColorAttributeName: lit ? [[NSColor alternateSelectedControlTextColor] colorWithAlphaComponent:0.8]
                                                 : [NSColor secondaryLabelColor]};
}

-(NSDictionary*)previewAttributes:(BOOL)lit {
    NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    return @{NSFontAttributeName: [NSFont systemFontOfSize:13],
             NSParagraphStyleAttributeName: style,
             NSForegroundColorAttributeName: lit ? [[NSColor alternateSelectedControlTextColor] colorWithAlphaComponent:0.85]
                                                 : [NSColor secondaryLabelColor]};
}

//one line: the line breaks of a text of several lines are shown as ⏎
+(NSString*)previewLine:(NSString*)text {
    NSString* flat = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\n" withString:@" ⏎ "];
    return flat.length > 160 ? [flat substringToIndex:160] : flat;
}

-(void)setOffers:(NSArray<NSDictionary*>*)offers {
    _offers = [offers copy];
    _nameWidth = 0;
    for (NSDictionary* offer in _offers)
        _nameWidth = MAX(_nameWidth, ceil([offer[@"name"] sizeWithAttributes:[self nameAttributes:NO]].width));
    self.needsDisplay = YES;
}

-(void)setHighlighted:(NSInteger)highlighted {
    if (_highlighted == highlighted)
        return;
    _highlighted = highlighted;
    self.needsDisplay = YES;
}

-(NSSize)contentSize {
    CGFloat width = kPadding + kItemPadding + kHintWidth + _nameWidth + kColumnGap + kPreviewWidth + kItemPadding + kPadding;
    return NSMakeSize(width, kPadding * 2 + kItemHeight * self.offers.count + [self separatorSpaceBeforeItem:self.offers.count]);
}

//the height of the separators above row `index`
-(CGFloat)separatorSpaceBeforeItem:(NSInteger)index {
    CGFloat space = 0;
    for (NSInteger i = 0; i < index && i < (NSInteger)self.offers.count; i++) {
        if ([self.offers[i][@"separatorAfter"] boolValue])
            space += kSeparatorHeight;
    }
    return space;
}

-(NSRect)rectOfItem:(NSInteger)index {
    return NSMakeRect(kPadding, kPadding + index * kItemHeight + [self separatorSpaceBeforeItem:index], NSWidth(self.bounds) - 2 * kPadding, kItemHeight);
}

-(NSInteger)itemAtPoint:(NSPoint)point {
    for (NSInteger i = 0; i < (NSInteger)self.offers.count; i++) {
        if (NSPointInRect(point, [self rectOfItem:i]))
            return i;
    }
    return -1;
}

-(void)drawRect:(NSRect)dirtyRect {
    //hairline around the list, drawn here so that its colour follows light and dark
    NSBezierPath* outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.25, 0.25) xRadius:kBarRadius yRadius:kBarRadius];
    outline.lineWidth = 0.5;
    [[NSColor separatorColor] setStroke];
    [outline stroke];

    for (NSInteger i = 0; i < (NSInteger)self.offers.count; i++) {
        BOOL lit = i == self.highlighted;
        NSRect item = [self rectOfItem:i];
        if (lit) {
            [[NSColor controlAccentColor] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:item xRadius:kItemRadius yRadius:kItemRadius] fill];
        }
        NSDictionary* offer = self.offers[i];
        CGFloat left = NSMinX(item) + kItemPadding;
        if ([offer[@"separatorAfter"] boolValue]) {
            NSRect line = NSMakeRect(NSMinX(item) + kItemPadding, NSMaxY(item) + kSeparatorHeight / 2 - 0.25, NSWidth(item) - 2 * kItemPadding, 0.5);
            [[NSColor separatorColor] setFill];
            NSRectFill(line);
        }

        NSString* hint = [CaseBarPanel hintForIndex:i];
        NSDictionary* hintAttributes = [self hintAttributes:lit];
        NSDictionary* nameAttributes = [self nameAttributes:lit];
        NSSize nameSize = [offer[@"name"] sizeWithAttributes:nameAttributes];
        //the key hint, the name and the preview are different sizes of text on one baseline, centred as a whole on the row
        NSFont* nameFont = nameAttributes[NSFontAttributeName];
        CGFloat baseline = NSMidY(item) - nameSize.height / 2 + nameFont.ascender;
        if (hint != nil) {
            NSFont* hintFont = hintAttributes[NSFontAttributeName];
            [hint drawAtPoint:NSMakePoint(left, baseline - hintFont.ascender) withAttributes:hintAttributes];
        }
        left += kHintWidth;
        [offer[@"name"] drawAtPoint:NSMakePoint(left, baseline - nameFont.ascender) withAttributes:nameAttributes];
        left += _nameWidth + kColumnGap;

        NSDictionary* previewAttributes = [self previewAttributes:lit];
        NSFont* previewFont = previewAttributes[NSFontAttributeName];
        NSString* preview = [CaseBarListView previewLine:offer[@"text"]];
        [preview drawInRect:NSMakeRect(left, baseline - previewFont.ascender, NSMaxX(item) - kItemPadding - left, previewFont.ascender - previewFont.descender + 2)
             withAttributes:previewAttributes];
    }
}

#pragma mark Mouse

-(void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea* area in self.trackingAreas)
        [self removeTrackingArea:area];
    //always: the application of the text is the active one, not this one
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                       options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                         owner:self userInfo:nil]];
}

-(void)mouseMoved:(NSEvent*)event {
    NSInteger index = [self itemAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index != self.highlighted && self.onHighlight != nil)
        self.onHighlight(index);
}

-(void)mouseExited:(NSEvent*)event {
    if (self.onHighlight != nil)
        self.onHighlight(-1);
}

-(void)mouseDown:(NSEvent*)event {
    NSInteger index = [self itemAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index >= 0 && self.onHighlight != nil)
        self.onHighlight(index); //lights the row while the button is down, like a menu
}

-(void)mouseUp:(NSEvent*)event {
    NSInteger index = [self itemAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index >= 0 && self.onChoose != nil)
        self.onChoose(index);
}

-(void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

@end

#pragma mark - The panel

//Stretchable rounded mask: the system uses it to cut the blur and to shape the shadow
static NSImage* ListMask(void) {
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

@implementation CaseBarPanel {
    CaseBarListView* _list;
}

+(NSString*)hintForIndex:(NSUInteger)index {
    if (index > 9)
        return nil;
    return [NSString stringWithFormat:@"⌥%lu", (unsigned long)((index + 1) % 10)];
}

-(instancetype)init {
    self = [super initWithContentRect:NSMakeRect(0, 0, 400, 100)
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
        background.maskImage = ListMask();
        self.contentView = background;

        _list = [[CaseBarListView alloc] initWithFrame:background.bounds];
        _list.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _list.highlighted = -1;
        __weak CaseBarPanel* weakSelf = self;
        _list.onHighlight = ^(NSInteger index) { weakSelf.highlighted = index; };
        _list.onChoose = ^(NSInteger index) {
            if (weakSelf.onChoose != nil)
                weakSelf.onChoose(index);
        };
        [background addSubview:_list];
    }
    return self;
}

//never the window that receives the typing; a click on a row still works
-(BOOL)canBecomeKeyWindow {
    return NO;
}

-(BOOL)canBecomeMainWindow {
    return NO;
}

-(void)setOffers:(NSArray<NSDictionary*>*)offers {
    _list.offers = offers;
    _list.highlighted = -1;
    [self setContentSize:[_list contentSize]];
    _list.needsDisplay = YES;
    [self invalidateShadow];
}

-(NSInteger)highlighted {
    return _list.highlighted;
}

-(void)setHighlighted:(NSInteger)highlighted {
    _list.highlighted = highlighted;
}

-(void)moveHighlight:(NSInteger)delta {
    NSInteger count = (NSInteger)_list.offers.count;
    if (count == 0)
        return;
    NSInteger current = _list.highlighted;
    if (current < 0)
        _list.highlighted = delta > 0 ? 0 : count - 1;
    else
        _list.highlighted = (current + delta + count) % count;
}

-(NSScreen*)screenContaining:(NSPoint)point {
    for (NSScreen* screen in [NSScreen screens]) {
        if (NSPointInRect(point, screen.frame))
            return screen;
    }
    return [NSScreen mainScreen];
}

-(void)show {
    if (self.visible)
        return;
    if ([[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion]) {
        self.alphaValue = 1;
        [self orderFrontRegardless];
        return;
    }
    self.alphaValue = 0;
    [self orderFrontRegardless];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.duration = kFadeIn;
        self.animator.alphaValue = 1;
    }];
}

-(void)showBelowRect:(NSRect)line {
    NSRect visible = [self screenContaining:line.origin].visibleFrame;
    NSPoint origin = [SuggestionPanel originForBarOfSize:self.frame.size line:line visibleFrame:visible];
    //taller than the room: keep it on the screen anyway
    origin.y = MAX(origin.y, visible.origin.y + kScreenMargin);
    if (!NSEqualPoints(origin, self.frame.origin))
        [self setFrameOrigin:origin];
    [self show];
}

-(void)showNearPoint:(NSPoint)point {
    [self showBelowRect:NSMakeRect(point.x, point.y - 22, 0, 22)];
}

@end
