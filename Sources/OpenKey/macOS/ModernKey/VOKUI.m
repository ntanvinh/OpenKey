//
//  VOKUI.m
//  VOpenKey
//

#import "VOKUI.h"

NSImage* VOKSymbol(NSString* name, CGFloat pointSize, NSFontWeight weight) {
    NSImage* image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    if (image == nil)
        return nil;
    return [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight]];
}

NSButton* VOKFindButton(NSView* root, SEL action) {
    if ([root isKindOfClass:[NSButton class]] && ((NSButton*)root).action == action)
        return (NSButton*)root;
    for (NSView* child in root.subviews) {
        NSButton* found = VOKFindButton(child, action);
        if (found != nil)
            return found;
    }
    return nil;
}

void VOKSetButtonSymbol(NSButton* button, NSString* symbol, CGFloat pointSize) {
    NSImage* image = VOKSymbol(symbol, pointSize, NSFontWeightRegular);
    if (image == nil || button == nil)
        return;
    button.image = image;
    button.imagePosition = button.title.length > 0 ? NSImageLeading : NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.imageHugsTitle = YES;
}

static NSBezierPath* StarPath(NSPoint center, CGFloat radius) {
    NSBezierPath* star = [NSBezierPath bezierPath];
    for (int i = 0; i < 10; i++) {
        CGFloat angle = (-90 + i * 36) * M_PI / 180;
        CGFloat r = i % 2 == 0 ? radius : radius * 0.381966;
        NSPoint point = NSMakePoint(center.x + r * cos(angle), center.y - r * sin(angle)); //y up: the star points up
        if (i == 0) [star moveToPoint:point]; else [star lineToPoint:point];
    }
    [star closePath];
    return star;
}

NSImage* VOKFlagImage(NSString* region) {
    BOOL vietnam = [region isEqualToString:@"vn"];
    NSImage* image = [NSImage imageWithSize:NSMakeSize(17, 12) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSRect flag = NSInsetRect(rect, 0.5, 0.5);
        NSBezierPath* outline = [NSBezierPath bezierPathWithRoundedRect:flag xRadius:1.7 yRadius:1.7];
        [NSGraphicsContext saveGraphicsState];
        [outline addClip];
        if (vietnam) {
            [[NSColor colorWithSRGBRed:0.855 green:0.145 blue:0.114 alpha:1] setFill];
            NSRectFill(flag);
            [[NSColor colorWithSRGBRed:1 green:0.95 blue:0 alpha:1] setFill];
            [StarPath(NSMakePoint(NSMidX(flag), NSMidY(flag) - 0.2), NSHeight(flag) * 0.34) fill];
        } else {
            CGFloat stripe = NSHeight(flag) / 13;
            for (int i = 0; i < 13; i++) {
                //the top stripe is red, then they alternate
                [(i % 2 == 0 ? [NSColor colorWithSRGBRed:0.70 green:0.13 blue:0.20 alpha:1] : [NSColor whiteColor]) setFill];
                NSRectFill(NSMakeRect(NSMinX(flag), NSMaxY(flag) - (i + 1) * stripe, NSWidth(flag), stripe + 0.01));
            }
            NSRect canton = NSMakeRect(NSMinX(flag), NSMaxY(flag) - 7 * stripe, NSWidth(flag) * 0.42, 7 * stripe);
            [[NSColor colorWithSRGBRed:0.24 green:0.23 blue:0.43 alpha:1] setFill];
            NSRectFill(canton);
            [[NSColor whiteColor] setFill];
            for (int row = 0; row < 3; row++)
                for (int column = 0; column < 3; column++)
                    NSRectFill(NSMakeRect(NSMinX(canton) + NSWidth(canton) * (0.2 + 0.3 * column) - 0.4,
                                          NSMinY(canton) + NSHeight(canton) * (0.2 + 0.3 * row) - 0.4, 0.8, 0.8));
        }
        [NSGraphicsContext restoreGraphicsState];
        [[NSColor colorWithWhite:0 alpha:0.28] setStroke];
        outline.lineWidth = 0.5;
        [outline stroke];
        return YES;
    }];
    image.template = NO;
    return image;
}

NSTextField* VOKLabel(NSString* text, CGFloat size, NSFontWeight weight, NSColor* color) {
    NSTextField* label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color != nil ? color : [NSColor labelColor];
    label.selectable = NO;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

//Not an NSBox: a box sizes itself badly around Auto Layout content, and its colors do not follow the appearance
//of the window the way these do.
@interface VOKCardView : NSView
@end

@implementation VOKCardView

-(instancetype)init {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 10;
        self.layer.borderWidth = 1;
        self.layer.masksToBounds = YES;
    }
    return self;
}

-(BOOL)wantsUpdateLayer {
    return YES;
}

-(void)updateLayer {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
        self.layer.borderColor = [NSColor separatorColor].CGColor;
    }];
}

@end

NSView* VOKCard(NSView* content) {
    VOKCardView* card = [[VOKCardView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:card.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
    ]];
    return card;
}

NSView* VOKSeparator(void) {
    NSBox* line = [[NSBox alloc] init];
    line.boxType = NSBoxSeparator;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    return line;
}

NSView* VOKInsetSeparator(CGFloat leading) {
    NSView* container = [[NSView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    NSView* line = VOKSeparator();
    [container addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [line.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:leading],
        [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [line.topAnchor constraintEqualToAnchor:container.topAnchor],
        [line.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    return container;
}

void VOKFillWidth(NSStackView* stack) {
    for (NSView* view in stack.arrangedSubviews) {
        [view.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [view.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
    }
}
