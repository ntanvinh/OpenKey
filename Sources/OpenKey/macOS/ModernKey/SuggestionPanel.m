//
//  SuggestionPanel.m
//  VOpenKey
//

#import "SuggestionPanel.h"

static const CGFloat kPadding = 4;
static const CGFloat kItemHeight = 24;
static const CGFloat kItemPadding = 9;
static const CGFloat kItemGap = 2;
static const CGFloat kLabelGap = 5;
static const CGFloat kCornerRadius = 8;
static const CGFloat kScreenMargin = 4;
static const CGFloat kDistanceFromText = 3;

#pragma mark - The words

@interface SuggestionItemsView : NSView
@property (nonatomic, copy) NSArray<NSString*>* words;
-(NSSize)contentSize;
@end

@implementation SuggestionItemsView

-(BOOL)isFlipped {
    return YES;
}

-(NSString*)labelAtIndex:(NSUInteger)index {
    return index == 0 ? @"⇥" : [NSString stringWithFormat:@"⌥%lu", (unsigned long)index + 1];
}

-(NSDictionary*)wordAttributes:(BOOL)selected {
    return @{NSFontAttributeName: [NSFont systemFontOfSize:15],
             NSForegroundColorAttributeName: selected ? [NSColor whiteColor] : [NSColor labelColor]};
}

-(NSDictionary*)labelAttributes:(BOOL)selected {
    return @{NSFontAttributeName: [NSFont systemFontOfSize:11],
             NSForegroundColorAttributeName: selected ? [[NSColor whiteColor] colorWithAlphaComponent:0.75]
                                                      : [NSColor tertiaryLabelColor]};
}

-(CGFloat)widthOfItem:(NSUInteger)index {
    BOOL selected = index == 0;
    CGFloat label = [[self labelAtIndex:index] sizeWithAttributes:[self labelAttributes:selected]].width;
    CGFloat word = [self.words[index] sizeWithAttributes:[self wordAttributes:selected]].width;
    return kItemPadding + label + kLabelGap + word + kItemPadding;
}

-(NSSize)contentSize {
    CGFloat width = kPadding;
    for (NSUInteger i = 0; i < self.words.count; i++)
        width += [self widthOfItem:i] + (i > 0 ? kItemGap : 0);
    return NSMakeSize(ceil(width + kPadding), kItemHeight + 2 * kPadding);
}

-(void)drawRect:(NSRect)dirtyRect {
    CGFloat x = kPadding;
    for (NSUInteger i = 0; i < self.words.count; i++) {
        BOOL selected = i == 0;
        CGFloat width = [self widthOfItem:i];
        NSRect item = NSMakeRect(x, kPadding, width, kItemHeight);
        if (selected) {
            [[NSColor controlAccentColor] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:item xRadius:5 yRadius:5] fill];
        }
        NSString* label = [self labelAtIndex:i];
        NSDictionary* labelAttributes = [self labelAttributes:selected];
        NSDictionary* wordAttributes = [self wordAttributes:selected];
        NSSize labelSize = [label sizeWithAttributes:labelAttributes];
        NSSize wordSize = [self.words[i] sizeWithAttributes:wordAttributes];
        CGFloat left = x + kItemPadding;
        [label drawAtPoint:NSMakePoint(left, item.origin.y + (kItemHeight - labelSize.height) / 2)
            withAttributes:labelAttributes];
        [self.words[i] drawAtPoint:NSMakePoint(left + labelSize.width + kLabelGap,
                                               item.origin.y + (kItemHeight - wordSize.height) / 2)
                    withAttributes:wordAttributes];
        x += width + kItemGap;
    }
}

@end

#pragma mark - The panel

@implementation SuggestionPanel {
    SuggestionItemsView* _items;
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
        self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                  NSWindowCollectionBehaviorStationary |
                                  NSWindowCollectionBehaviorFullScreenAuxiliary |
                                  NSWindowCollectionBehaviorIgnoresCycle;

        NSVisualEffectView* background = [[NSVisualEffectView alloc] initWithFrame:self.contentView.bounds];
        background.material = NSVisualEffectMaterialMenu;
        background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        background.state = NSVisualEffectStateActive;
        background.wantsLayer = YES;
        background.layer.cornerRadius = kCornerRadius;
        background.layer.masksToBounds = YES;
        background.layer.borderWidth = 0.5;
        background.layer.borderColor = [[NSColor separatorColor] CGColor];
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

-(void)setWords:(NSArray<NSString*>*)words {
    _items.words = words;
    [self setContentSize:[_items contentSize]];
    _items.needsDisplay = YES;
}

-(NSScreen*)screenContaining:(NSPoint)point {
    for (NSScreen* screen in [NSScreen screens]) {
        if (NSPointInRect(point, screen.frame))
            return screen;
    }
    return [NSScreen mainScreen];
}

-(void)showBelowRect:(NSRect)rect {
    NSSize size = self.frame.size;
    NSRect visible = [self screenContaining:rect.origin].visibleFrame;
    CGFloat x = rect.origin.x - kPadding;
    x = MAX(visible.origin.x + kScreenMargin, MIN(x, NSMaxX(visible) - size.width - kScreenMargin));
    CGFloat y = rect.origin.y - size.height - kDistanceFromText;
    if (y < visible.origin.y + kScreenMargin) //no room below: above the text
        y = NSMaxY(rect) + kDistanceFromText;
    [self setFrameOrigin:NSMakePoint(x, y)];
    [self orderFrontRegardless];
}

-(void)showNearPoint:(NSPoint)point {
    [self showBelowRect:NSMakeRect(point.x, point.y - 22, 0, 22)];
}

@end
