//
//  CaseBarPanel.h
//  VOpenKey
//
//  The list that offers to change the case of the selected text: one row for each style, with the key that chooses it and what the
//  text would become. Looks like a menu of macOS (same material, accent colour for the row under the pointer or the arrows) and,
//  like the suggestion bar, never takes the keyboard from the application: the selection stays selected there.
//

#import <Cocoa/Cocoa.h>

@interface CaseBarPanel : NSPanel

/// A row was chosen with the mouse. The index is the one in `setOffers:`.
@property (nonatomic, copy) void (^onChoose)(NSInteger index);

/// The rows: dictionaries with "name" and "text" (the text the selection would become), most popular style first.
-(void)setOffers:(NSArray<NSDictionary*>*)offers;

/// The row that is lit: the one under the pointer, or the one the arrows reached. -1 for none.
@property (nonatomic) NSInteger highlighted;

/// Moves the lit row by `delta` (±1), around the ends. Lights the first or last when nothing is lit.
-(void)moveHighlight:(NSInteger)delta;

/// Puts the list under a line of text (see SuggestionPanel) and shows it.
-(void)showBelowRect:(NSRect)line;
-(void)showNearPoint:(NSPoint)point;

/// The key that chooses row `index`: ⌥1 … ⌥9, ⌥0 for the tenth; nil when the row has none.
+(NSString*)hintForIndex:(NSUInteger)index;

@end
