//
//  SuggestionPanel.m
//  VOpenKey
//

#import "SuggestionPanel.h"

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

-(void)showBelowRect:(NSRect)rect {
    NSSize size = self.frame.size;
    NSRect visible = [self screenContaining:rect.origin].visibleFrame;
    //the first word starts where the typed word starts
    CGFloat x = rect.origin.x - kPadding - kItemPadding;
    x = MAX(visible.origin.x + kScreenMargin, MIN(x, NSMaxX(visible) - size.width - kScreenMargin));
    CGFloat y = rect.origin.y - size.height - kDistanceFromText;
    if (y < visible.origin.y + kScreenMargin) //no room below: above the text
        y = NSMaxY(rect) + kDistanceFromText;
    [self setFrameOrigin:NSMakePoint(x, y)];
    [self show];
}

-(void)showNearPoint:(NSPoint)point {
    [self showBelowRect:NSMakeRect(point.x, point.y - 22, 0, 22)];
}

@end
