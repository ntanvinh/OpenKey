//
//  CapsLockToast.m
//  VOpenKey
//

#import "CapsLockToast.h"
#import <QuartzCore/QuartzCore.h>
#import "VOKUI.h"

static const CGFloat kHeight = 48;
static const CGFloat kRadius = 14;
static const CGFloat kPaddingLeading = 16;
static const CGFloat kPaddingTrailing = 20;
static const CGFloat kIconSize = 22;
static const CGFloat kGap = 10;
static const CGFloat kBottomOffset = 88;            //above the Dock, where the volume and brightness indicators of macOS are
static const NSTimeInterval kStay = 1.4;
static const NSTimeInterval kFadeIn = 0.12;         //it has to be there as the key goes down: short
static const NSTimeInterval kFadeOut = 0.2;

static BOOL sOffscreen;
static CapsLockToast* sPanel;

static NSImage* ToastMask(void) {
    CGFloat side = kRadius * 2 + 1;
    NSImage* mask = [NSImage imageWithSize:NSMakeSize(side, side) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor blackColor] set];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:kRadius yRadius:kRadius] fill];
        return YES;
    }];
    mask.capInsets = NSEdgeInsetsMake(kRadius, kRadius, kRadius, kRadius);
    mask.resizingMode = NSImageResizingModeStretch;
    return mask;
}

@implementation CapsLockToast {
    NSImageView* _icon;
    NSTextField* _label;
    NSInteger _generation;          //a fade that was started before the toast was shown again must not take it away
    NSString* _message;
}

+(NSString*)messageForState:(BOOL)on {
    return on ? @"Caps Lock đang bật" : @"Caps Lock đã tắt";
}

+(CapsLockToast*)panel {
    return sPanel;
}

+(void)setOffscreenForTesting:(BOOL)offscreen {
    sOffscreen = offscreen;
}

+(void)showForState:(BOOL)on {
    if (sPanel == nil)
        sPanel = [[CapsLockToast alloc] init];
    [sPanel presentForState:on];
}

+(void)hide {
    [sPanel dismissNow];
}

-(instancetype)init {
    self = [super initWithContentRect:NSMakeRect(0, 0, 200, kHeight)
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
        self.ignoresMouseEvents = YES;      //a click goes to what is under it
        self.animationBehavior = NSWindowAnimationBehaviorNone;
        self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                  NSWindowCollectionBehaviorStationary |
                                  NSWindowCollectionBehaviorFullScreenAuxiliary |
                                  NSWindowCollectionBehaviorIgnoresCycle;

        NSVisualEffectView* background = [[NSVisualEffectView alloc] initWithFrame:self.contentView.bounds];
        background.material = NSVisualEffectMaterialMenu;
        background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        background.state = NSVisualEffectStateActive;
        background.maskImage = ToastMask();
        self.contentView = background;

        _icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _icon.imageScaling = NSImageScaleProportionallyDown;
        [_icon setAccessibilityElement:NO];     //the label says it
        [background addSubview:_icon];

        _label = [NSTextField labelWithString:@""];
        _label.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
        _label.textColor = [NSColor labelColor];
        _label.lineBreakMode = NSLineBreakByClipping;
        [background addSubview:_label];
    }
    return self;
}

//never the window that gets the typing
-(BOOL)canBecomeKeyWindow {
    return NO;
}

-(BOOL)canBecomeMainWindow {
    return NO;
}

-(NSString*)message {
    return _message ?: @"";
}

-(NSScreen*)screenOfPointer {
    NSPoint pointer = [NSEvent mouseLocation];
    for (NSScreen* screen in [NSScreen screens]) {
        if (NSPointInRect(pointer, screen.frame))
            return screen;
    }
    return [NSScreen mainScreen];
}

//On: the red of the icon in the menu bar, so the two say the same thing. Off: the plain colour, nothing to warn about.
-(void)fillForState:(BOOL)on {
    _message = [[CapsLockToast messageForState:on] copy];
    _label.stringValue = _message;
    [_label sizeToFit];

    NSImage* symbol = VOKSymbol(on ? @"capslock.fill" : @"capslock", kIconSize, NSFontWeightSemibold);
    if (symbol != nil) {
        NSColor* colour = on ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
        if (@available(macOS 12.0, *))
            symbol = [symbol imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:colour]] ?: symbol;
        _icon.image = symbol;
        _icon.contentTintColor = colour;
    }

    CGFloat labelWidth = ceil(NSWidth(_label.frame));
    CGFloat width = kPaddingLeading + kIconSize + kGap + labelWidth + kPaddingTrailing;
    NSRect frame = self.frame;
    frame.size = NSMakeSize(width, kHeight);
    [self setFrame:frame display:NO];

    _icon.frame = NSMakeRect(kPaddingLeading, (kHeight - kIconSize) / 2, kIconSize, kIconSize);
    CGFloat labelHeight = ceil(NSHeight(_label.frame));
    _label.frame = NSMakeRect(kPaddingLeading + kIconSize + kGap, (kHeight - labelHeight) / 2, labelWidth, labelHeight);
    [self invalidateShadow];
}

-(void)placeOnScreen {
    if (sOffscreen) {
        [self setFrameOrigin:NSMakePoint(-30000, -30000)];
        return;
    }
    NSRect area = [self screenOfPointer].visibleFrame;
    [self setFrameOrigin:NSMakePoint(round(NSMidX(area) - NSWidth(self.frame) / 2), round(NSMinY(area) + kBottomOffset))];
}

-(void)presentForState:(BOOL)on {
    BOOL alreadyThere = self.visible && self.alphaValue > 0.01;
    _generation++;
    NSInteger generation = _generation;

    [self fillForState:on];
    [self placeOnScreen];

    //VoiceOver does not see a window that never takes the focus: it is told
    NSAccessibilityPostNotificationWithUserInfo(NSApp ?: (id)self, NSAccessibilityAnnouncementRequestedNotification,
        @{NSAccessibilityAnnouncementKey: _message, NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium)});

    //no fade for the person who asked for less motion, nor where nothing is drawn (the tests keep it outside the screens)
    BOOL calm = [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion] || sOffscreen;
    if (alreadyThere || calm) {
        self.alphaValue = 1;
        [self orderFrontRegardless];
    } else {
        self.alphaValue = 0;
        [self orderFrontRegardless];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
            context.duration = kFadeIn;
            context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.23 :1 :0.32 :1];
            self.animator.alphaValue = 1;
        }];
    }

    __weak CapsLockToast* weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kStay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf fadeOutIfStill:generation];
    });
}

-(void)fadeOutIfStill:(NSInteger)generation {
    if (generation != _generation || !self.visible)
        return;
    if ([[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion] || sOffscreen) {
        [self orderOut:nil];
        return;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.duration = kFadeOut;
        context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.23 :1 :0.32 :1];
        self.animator.alphaValue = 0;
    }];
    //taken away by the clock, not by the end of the animation: a window that is not drawn never finishes one. Shown again meanwhile: leave it.
    __weak CapsLockToast* weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kFadeOut + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CapsLockToast* strongSelf = weakSelf;
        if (strongSelf != nil && generation == strongSelf->_generation)
            [strongSelf orderOut:nil];
    });
}

-(void)dismissNow {
    _generation++;
    [self orderOut:nil];
    self.alphaValue = 1;
}

@end
