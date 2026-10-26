//
//  SuggestionPanel.h
//  VOpenKey
//
//  The suggestion bar: a small strip of words next to the text being typed, laid out like the candidate
//  bar of a Chinese input method. It never takes the keyboard focus and ignores the mouse, so the text
//  field stays active.
//

#import <Cocoa/Cocoa.h>

@interface SuggestionPanel : NSPanel

/// Saved transparency, 0–80 percent (default 0). Changes apply to visible bars immediately.
+(NSInteger)transparencyPercent;
+(void)setTransparencyPercent:(NSInteger)percent;

/// Saved transparency while the pointer is over the bar, 1–95 percent (default 85).
/// Always remains at least one point more transparent than the normal appearance.
+(NSInteger)hoverTransparencyPercent;
+(void)setHoverTransparencyPercent:(NSInteger)percent;

/// What the first word is chosen with: Tab (the default), or ⌥1 when the user turned Tab off. The others are ⌥2, ⌥3...
@property (nonatomic) BOOL firstWordUsesTab;

/// The first word is the highlighted one, the others follow it.
-(void)setWords:(NSArray<NSString*>*)words;

/// Puts the bar under a line of text, in Cocoa screen coordinates: `line` is where the text of the word starts (its x) and
/// the place and height of the line of the caret. Above the line when there is no room below. Shows the bar.
-(void)showBelowRect:(NSRect)line;

/// Where the bar of that size goes for that line on a screen whose usable area is `visible`.
+(NSPoint)originForBarOfSize:(NSSize)size line:(NSRect)line visibleFrame:(NSRect)visible;

/// When the position of the text caret is not known: under the mouse pointer.
-(void)showNearPoint:(NSPoint)point;

@end
