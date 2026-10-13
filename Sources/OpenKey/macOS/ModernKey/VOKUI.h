//
//  VOKUI.h
//  VOpenKey
//
//  Small building blocks shared by the windows and menus, so they all look like parts of macOS.
//

#import <Cocoa/Cocoa.h>

// SF Symbol, nil if this macOS does not know the name.
NSImage* VOKSymbol(NSString* name, CGFloat pointSize, NSFontWeight weight);

// Small flag for a menu item, like the ones macOS shows for input sources: @"vn" or @"us". Drawn, not loaded, so it is
// sharp at any resolution.
NSImage* VOKFlagImage(NSString* region);

// Non-editable text that wraps at the width it is given.
NSTextField* VOKLabel(NSString* text, CGFloat size, NSFontWeight weight, NSColor* color);

// Rounded container with a hairline border, the "grouped" look of System Settings.
NSView* VOKCard(NSView* content);

// Thin horizontal line between the rows of a card.
NSView* VOKSeparator(void);

// Makes every arranged subview of a vertical stack as wide as the stack.
void VOKFillWidth(NSStackView* stack);
