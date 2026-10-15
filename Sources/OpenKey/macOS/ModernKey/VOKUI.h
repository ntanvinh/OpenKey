//
//  VOKUI.h
//  VOpenKey
//
//  Small building blocks shared by the windows and menus, so they all look like parts of macOS.
//

#import <Cocoa/Cocoa.h>

#ifdef __cplusplus
extern "C" {
#endif

// SF Symbol, nil if this macOS does not know the name.
NSImage* VOKSymbol(NSString* name, CGFloat pointSize, NSFontWeight weight);

// The button in a view hierarchy that sends `action`, nil if there is none. For buttons that have no outlet.
NSButton* VOKFindButton(NSView* root, SEL action);

// Puts an SF Symbol before the title of a button. Symbols are templates: they take the colour of the button text, so
// they stay visible in light and dark mode and when the button is the default one.
void VOKSetButtonSymbol(NSButton* button, NSString* symbol, CGFloat pointSize);

// Small flag for a menu item, like the ones macOS shows for input sources: @"vn" or @"us". Drawn, not loaded, so it is
// sharp at any resolution.
NSImage* VOKFlagImage(NSString* region);

// Non-editable text that wraps at the width it is given.
NSTextField* VOKLabel(NSString* text, CGFloat size, NSFontWeight weight, NSColor* color);

// A tooltip that is read in a column: macOS stretches a long one into a single line as wide as the screen, so it is broken
// into lines of about 60 characters (at spaces; lines the text already has are kept).
NSString* VOKTooltip(NSString* text);

// Rounded container with a hairline border, the "grouped" look of System Settings.
NSView* VOKCard(NSView* content);

// Thin horizontal line between the rows of a card.
NSView* VOKSeparator(void);

// The same line, starting `leading` points from the left edge: the rows of System Settings are separated by lines
// that begin where their text begins.
NSView* VOKInsetSeparator(CGFloat leading);

// Makes every arranged subview of a vertical stack as wide as the stack.
void VOKFillWidth(NSStackView* stack);

#ifdef __cplusplus
}
#endif
