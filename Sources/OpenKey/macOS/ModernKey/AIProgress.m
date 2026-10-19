//
//  AIProgress.m
//  VOpenKey
//

#import "AIProgress.h"
#import <QuartzCore/QuartzCore.h>

BOOL AIReduceMotion(void) {
    return [NSWorkspace sharedWorkspace].accessibilityDisplayShouldReduceMotion;
}

#pragma mark - Sentences

@implementation AIProgressText

//The stages of a wait: from which second, how often the sentence changes, and the sentences. "%@" is the name of the AI.
+(NSArray<NSDictionary*>*)stages {
    static NSArray* stages;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stages = @[
            @{@"from": @0, @"every": @3, @"texts": @[@"Đang gửi yêu cầu tới %@…"]},
            @{@"from": @3, @"every": @3, @"texts": @[@"AI đang suy nghĩ…", @"Đang đọc kỹ yêu cầu của bạn…", @"Đang soạn câu trả lời…"]},
            @{@"from": @9, @"every": @4, @"texts": @[@"Vẫn đang xử lý, vui lòng kiên nhẫn một chút…", @"Câu trả lời cần thêm chút thời gian…",
                                                     @"AI đang cân nhắc cách diễn đạt hay nhất…"]},
            @{@"from": @18, @"every": @4, @"texts": @[@"Sắp có kết quả rồi, cảm ơn bạn đã chờ…", @"Mọi thứ vẫn đang chạy bình thường…",
                                                      @"AI đang hoàn thiện câu trả lời…"]},
            @{@"from": @32, @"every": @5, @"texts": @[@"Hơi lâu hơn bình thường, nhưng AI vẫn đang làm việc. Vui lòng đợi thêm…",
                                                      @"VOpenKey AI không bị treo, đang chờ %@ trả lời…",
                                                      @"Mạng hoặc dịch vụ có thể đang chậm, bạn đợi thêm chút nhé…"]},
            @{@"from": @60, @"every": @6, @"texts": @[@"Vẫn đang chờ. Bạn có thể bấm Dừng nếu không muốn đợi nữa.",
                                                      @"Mức suy nghĩ cao có thể mất vài phút. Bấm Dừng để thử lại ở mức thấp hơn."]},
        ];
    });
    return stages;
}

//the stages of a wait for a picture: it is slower than a text, and the words say that it is normal
+(NSArray<NSDictionary*>*)imageStages {
    static NSArray* stages;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stages = @[
            @{@"from": @0, @"every": @3, @"texts": @[@"Đang gửi yêu cầu tới %@…"]},
            @{@"from": @3, @"every": @4, @"texts": @[@"Đang phác thảo ý tưởng cho bức ảnh…", @"Đang chọn bố cục và màu sắc…",
                                                     @"Đang vẽ ảnh, việc này thường mất 20 đến 40 giây…"]},
            @{@"from": @15, @"every": @5, @"texts": @[@"Ảnh cần nhiều thời gian hơn văn bản, vui lòng kiên nhẫn…", @"Đang hoàn thiện từng chi tiết…",
                                                      @"Mọi thứ vẫn đang chạy bình thường…"]},
            @{@"from": @35, @"every": @5, @"texts": @[@"Sắp xong rồi, ảnh đang được lưu lại…", @"Hơi lâu hơn thường lệ, nhưng AI vẫn đang vẽ…",
                                                      @"VOpenKey AI không bị treo, đang chờ %@ vẽ xong…"]},
            @{@"from": @70, @"every": @6, @"texts": @[@"Vẫn đang chờ. Bạn có thể bấm Dừng nếu không muốn đợi nữa.",
                                                      @"Dịch vụ có thể đang đông người dùng, bạn đợi thêm chút nhé…"]},
        ];
    });
    return stages;
}

+(NSString*)messageAfterSeconds:(NSInteger)seconds provider:(NSString*)provider {
    return [self messageAfterSeconds:seconds provider:provider image:NO];
}

+(NSString*)messageAfterSeconds:(NSInteger)seconds provider:(NSString*)provider image:(BOOL)image {
    seconds = MAX(seconds, 0);
    NSArray<NSDictionary*>* all = image ? [self imageStages] : [self stages];
    NSDictionary* stage = all.firstObject;
    for (NSDictionary* candidate in all)
        if (seconds >= [candidate[@"from"] integerValue])
            stage = candidate;
    NSArray<NSString*>* texts = stage[@"texts"];
    NSInteger step = (seconds - [stage[@"from"] integerValue]) / MAX([stage[@"every"] integerValue], 1);
    NSString* text = texts[(NSUInteger)step % texts.count];
    return [text containsString:@"%@"] ? [NSString stringWithFormat:text, provider.length > 0 ? provider : @"AI"] : text;
}

+(NSString*)elapsedAfterSeconds:(NSInteger)seconds {
    seconds = MAX(seconds, 0);
    if (seconds < 60)
        return [NSString stringWithFormat:@"Đã chờ %ld giây", (long)seconds];
    return [NSString stringWithFormat:@"Đã chờ %ld phút %02ld giây", (long)(seconds / 60), (long)(seconds % 60)];
}

@end

#pragma mark - The light round the edge

//One light, a bright stretch of the edge with a tail that fades, that runs round the card at an even speed. It is a dashed line (a stretch
//drawn, the rest of the way not) whose dash is moved along the path: moving it is the only thing that animates, and it goes the same
//speed on the long sides and on the short ones. Under it a very thin ring shows the way, and a wider, fainter copy makes it glow.
static const CGFloat kLineWidth = 1.5;
static const CGFloat kHaloWidth = 4;
static const CGFloat kTrackWidth = 1;
static const CFTimeInterval kLapTime = 2.6;

//the stretches the light is made of, all ending at its head: how much of the way, and how strong. Laid over each other they give a tail.
static const struct { CGFloat share, alpha; } kStretches[3] = {{0.34, 0.22}, {0.18, 0.40}, {0.07, 0.75}};

//a ring: colours that show only where the line is drawn
@interface AIGlowRing : NSObject
@property (nonatomic, strong) CALayer* layer;
@property (nonatomic, strong) CAGradientLayer* colors;
@property (nonatomic, strong) NSArray<CAShapeLayer*>* strokes;
@property (nonatomic) CGFloat width;
@property (nonatomic) CGFloat perimeter;
@end

@implementation AIGlowRing
@end

@implementation AIGlowView {
    AIGlowRing* _track;
    AIGlowRing* _line;
    AIGlowRing* _halo;
    BOOL _animating;
}

-(instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.opacity = 0;
        _track = [self ringWithWidth:kTrackWidth strokes:1 opacity:0.28];
        _halo = [self ringWithWidth:kHaloWidth strokes:3 opacity:0.30];
        _line = [self ringWithWidth:kLineWidth strokes:3 opacity:1];
        for (AIGlowRing* ring in @[_track, _halo, _line])
            [self.layer addSublayer:ring.layer];
        self.hidden = YES;
    }
    return self;
}

-(AIGlowRing*)ringWithWidth:(CGFloat)width strokes:(NSUInteger)count opacity:(float)opacity {
    AIGlowRing* ring = [[AIGlowRing alloc] init];
    ring.width = width;
    ring.layer = [CALayer layer];
    ring.layer.opacity = opacity;
    ring.colors = [CAGradientLayer layer];
    ring.colors.type = kCAGradientLayerConic;
    ring.colors.startPoint = CGPointMake(0.5, 0.5);
    ring.colors.endPoint = CGPointMake(0.5, 0);
    [ring.layer addSublayer:ring.colors];
    //the strokes are only the shape that lets the colours through
    CALayer* mask = [CALayer layer];
    NSMutableArray* strokes = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) {
        CAShapeLayer* stroke = [CAShapeLayer layer];
        stroke.fillColor = NULL;
        stroke.lineWidth = width;
        stroke.lineCap = kCALineCapRound;
        stroke.strokeColor = [NSColor colorWithWhite:0 alpha:count == 1 ? 1 : kStretches[i].alpha].CGColor;
        [mask addSublayer:stroke];
        [strokes addObject:stroke];
    }
    ring.strokes = strokes;
    ring.layer.mask = mask;
    return ring;
}

-(NSView*)hitTest:(NSPoint)point {
    return nil;                                     //it is only to look at: the answer under it can be selected
}

-(BOOL)animating {
    return _animating;
}

-(void)updateColors {
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSArray* colors = @[(id)[NSColor systemBlueColor].CGColor, (id)[NSColor systemPurpleColor].CGColor, (id)[NSColor systemPinkColor].CGColor,
                            (id)[NSColor systemOrangeColor].CGColor, (id)[NSColor systemBlueColor].CGColor];
        for (AIGlowRing* ring in @[self->_track, self->_halo, self->_line])
            ring.colors.colors = colors;
    }];
}

-(void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateColors];
}

-(void)layout {
    [super layout];
    CGRect bounds = self.bounds;
    CGFloat diagonal = hypot(bounds.size.width, bounds.size.height);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (AIGlowRing* ring in @[_track, _halo, _line]) {
        ring.layer.frame = bounds;
        ring.layer.mask.frame = bounds;
        ring.colors.frame = CGRectMake(CGRectGetMidX(bounds) - diagonal / 2, CGRectGetMidY(bounds) - diagonal / 2, diagonal, diagonal);   //turns without leaving a corner empty
        //the line follows the edge of the card, which has round corners of 10 points
        CGFloat inset = ring.width / 2, radius = 10 - inset;
        CGRect box = CGRectInset(bounds, inset, inset);
        CGPathRef path = CGPathCreateWithRoundedRect(box, radius, radius, NULL);
        ring.perimeter = 2 * (box.size.width + box.size.height) - 8 * radius + 2 * M_PI * radius;
        for (NSUInteger i = 0; i < ring.strokes.count; i++) {
            CAShapeLayer* stroke = ring.strokes[i];
            stroke.frame = bounds;
            stroke.path = path;
            if (ring.strokes.count > 1) {
                CGFloat length = kStretches[i].share * ring.perimeter;
                stroke.lineDashPattern = @[@(length), @(ring.perimeter - length)];
                stroke.lineDashPhase = length;                  //the head at the start of the path: the picture of a light that stands still
            }
        }
        CGPathRelease(path);
    }
    [CATransaction commit];
    if (_animating)
        [self runLight];
}

//the light starts running, and the colours drift slowly under it
-(void)runLight {
    for (AIGlowRing* ring in @[_halo, _line]) {
        for (NSUInteger i = 0; i < ring.strokes.count; i++) {
            CGFloat length = kStretches[i].share * ring.perimeter;
            CABasicAnimation* run = [CABasicAnimation animationWithKeyPath:@"lineDashPhase"];
            run.fromValue = @(length);                          //the head moves one lap: the dash goes the whole length of the path
            run.toValue = @(length - ring.perimeter);
            run.duration = kLapTime;
            run.repeatCount = HUGE_VALF;
            run.removedOnCompletion = NO;
            [ring.strokes[i] addAnimation:run forKey:@"run"];
        }
    }
    for (AIGlowRing* ring in @[_track, _halo, _line]) {
        CABasicAnimation* drift = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        drift.fromValue = @0;
        drift.toValue = @(-2 * M_PI);
        drift.duration = 9;
        drift.repeatCount = HUGE_VALF;
        drift.removedOnCompletion = NO;
        [ring.colors addAnimation:drift forKey:@"drift"];
    }
}

-(void)start {
    if (_animating)
        return;
    _animating = YES;
    self.hidden = NO;
    [self updateColors];
    BOOL still = AIReduceMotion();
    _halo.layer.hidden = still;                     //with less motion only the ring is there, and nothing runs on it
    _line.layer.hidden = still;
    _track.layer.opacity = still ? 0.6 : 0.28;
    [self layoutSubtreeIfNeeded];
    [self layout];                                  //also starts the animations
    if (still) {
        for (AIGlowRing* ring in @[_halo, _line])
            for (CAShapeLayer* stroke in ring.strokes)
                [stroke removeAllAnimations];
        for (AIGlowRing* ring in @[_track, _halo, _line])
            [ring.colors removeAllAnimations];
    }
    CABasicAnimation* appear = [CABasicAnimation animationWithKeyPath:@"opacity"];
    appear.fromValue = @0;
    appear.toValue = @1;
    appear.duration = 0.45;
    self.layer.opacity = 1;
    [self.layer addAnimation:appear forKey:@"appear"];
}

-(void)stop {
    if (!_animating)
        return;
    _animating = NO;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        if (!self->_animating) {                    //not started again meanwhile
            self.hidden = YES;
            for (AIGlowRing* ring in @[self->_track, self->_halo, self->_line]) {
                [ring.colors removeAllAnimations];
                for (CAShapeLayer* stroke in ring.strokes)
                    [stroke removeAllAnimations];
            }
        }
    }];
    CABasicAnimation* fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @(self.layer.presentationLayer.opacity);
    fade.toValue = @0;
    fade.duration = 0.3;
    self.layer.opacity = 0;
    [self.layer addAnimation:fade forKey:@"appear"];
    [CATransaction commit];
}

@end

#pragma mark - Words with a wave of light

@implementation AIShimmerLabel {
    CAGradientLayer* _wave;
    BOOL _shimmering;
}

-(BOOL)shimmering {
    return _shimmering;
}

-(void)layout {
    [super layout];
    _wave.frame = self.bounds;
}

-(void)setShimmering:(BOOL)shimmering {
    if (shimmering == _shimmering)
        return;
    _shimmering = shimmering;
    if (!shimmering) {
        [_wave removeAllAnimations];
        self.layer.mask = nil;
        _wave = nil;
        return;
    }
    if (AIReduceMotion())
        return;
    self.wantsLayer = YES;
    //a band of light that runs over the text: the text is dimmer than that where the band is not. The gradient line moves along the text
    //(its places stay between 0 and 1, outside the line the colour of its end goes on, which is the dim one)
    _wave = [CAGradientLayer layer];
    _wave.frame = self.bounds;
    _wave.colors = @[(id)[NSColor colorWithWhite:1 alpha:0.55].CGColor, (id)[NSColor colorWithWhite:1 alpha:1].CGColor, (id)[NSColor colorWithWhite:1 alpha:0.55].CGColor];
    _wave.locations = @[@0, @0.5, @1];
    _wave.startPoint = CGPointMake(-1, 0.5);
    _wave.endPoint = CGPointMake(0, 0.5);
    self.layer.mask = _wave;
    CABasicAnimation* start = [CABasicAnimation animationWithKeyPath:@"startPoint"];
    start.fromValue = [NSValue valueWithPoint:NSMakePoint(-1, 0.5)];
    start.toValue = [NSValue valueWithPoint:NSMakePoint(1, 0.5)];
    CABasicAnimation* end = [CABasicAnimation animationWithKeyPath:@"endPoint"];
    end.fromValue = [NSValue valueWithPoint:NSMakePoint(0, 0.5)];
    end.toValue = [NSValue valueWithPoint:NSMakePoint(2, 0.5)];
    CAAnimationGroup* run = [CAAnimationGroup animation];
    run.animations = @[start, end];
    run.duration = 1.9;
    run.repeatCount = HUGE_VALF;
    run.removedOnCompletion = NO;
    [_wave addAnimation:run forKey:@"run"];
}

-(void)fadeToMessage:(NSString*)message {
    if ([self.stringValue isEqualToString:message])
        return;
    if (self.layer != nil && !AIReduceMotion()) {
        CATransition* fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = 0.35;
        [self.layer addAnimation:fade forKey:@"message"];
    }
    self.stringValue = message;
}

@end

void AIPulseView(NSView* view, BOOL on) {
    static NSString* const key = @"breathe";
    if (!on || AIReduceMotion()) {
        [view.layer removeAnimationForKey:key];
        return;
    }
    view.wantsLayer = YES;
    if ([view.layer animationForKey:key] != nil)
        return;
    CABasicAnimation* breathe = [CABasicAnimation animationWithKeyPath:@"opacity"];
    breathe.fromValue = @1;
    breathe.toValue = @0.3;
    breathe.duration = 0.9;
    breathe.autoreverses = YES;
    breathe.repeatCount = HUGE_VALF;
    breathe.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [view.layer addAnimation:breathe forKey:key];
}
