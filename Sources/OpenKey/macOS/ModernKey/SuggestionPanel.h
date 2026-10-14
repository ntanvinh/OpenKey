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

/// What the first word is chosen with: ⌥1, or Tab when that is allowed. The others are ⌥2, ⌥3...
@property (nonatomic) BOOL firstWordUsesTab;

/// The first word is the highlighted one, the others follow it.
-(void)setWords:(NSArray<NSString*>*)words;

/// Puts the bar under a rectangle (the word being typed), in Cocoa screen coordinates; above it when
/// there is no room below. Shows the bar.
-(void)showBelowRect:(NSRect)rect;

/// When the position of the text caret is not known: under the mouse pointer.
-(void)showNearPoint:(NSPoint)point;

@end
