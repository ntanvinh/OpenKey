//
//  AIProgress.h
//  VOpenKey
//
//  What the AI window shows while an AI is working. An answer can take a while (a program like Codex or Antigravity starts, signs in,
//  thinks; a high thinking level can take half a minute), and a window that does not move looks like an application that has hung.
//  So while it waits the window
//  - tells in words what is going on, in sentences that change as the time goes on, and that say it is normal when it gets long;
//  - moves: a light runs round the edge of the answer, the words shimmer, the sparkles breathe.
//  With "Reduce motion" on in the system settings nothing moves: the sentences and the seconds are still there.
//

#import <Cocoa/Cocoa.h>

#ifdef __cplusplus
extern "C" {
#endif
/// The user asked the system for less motion (System Settings > Accessibility > Display).
BOOL AIReduceMotion(void);
#ifdef __cplusplus
}
#endif

@interface AIProgressText : NSObject

/// The sentence for the moment after `seconds` of waiting. It changes every few seconds so that the window never looks stuck, and it
/// gets more reassuring the longer it takes: at first what is happening, then that it is going on normally, then that it can be stopped.
/// `provider` is the name of the AI, said at the very beginning.
+(NSString*)messageAfterSeconds:(NSInteger)seconds provider:(NSString*)provider;

/// The same for a picture, which takes longer than a text (half a minute is usual) and says so.
+(NSString*)messageAfterSeconds:(NSInteger)seconds provider:(NSString*)provider image:(BOOL)image;

/// "Đã chờ 12 giây", "Đã chờ 1 phút 05 giây".
+(NSString*)elapsedAfterSeconds:(NSInteger)seconds;

@end

/// A light that runs round the edge of a rounded rectangle, over what is under it (clicks go through). Put it over a card; it is clipped
/// by the card.
@interface AIGlowView : NSView
-(void)start;
-(void)stop;
/// Between -start and -stop.
@property (nonatomic, readonly) BOOL animating;
@end

/// Text with a wave of light that runs over it, for as long as `shimmering` is on.
@interface AIShimmerLabel : NSTextField
@property (nonatomic) BOOL shimmering;
/// Shows another text, fading from the old one.
-(void)fadeToMessage:(NSString*)message;
@end

/// Makes a view breathe (its opacity goes down and up), or stops it.
void AIPulseView(NSView* view, BOOL on);
