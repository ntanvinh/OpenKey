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

void VOKFillWidth(NSStackView* stack) {
    for (NSView* view in stack.arrangedSubviews) {
        [view.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [view.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
    }
}
