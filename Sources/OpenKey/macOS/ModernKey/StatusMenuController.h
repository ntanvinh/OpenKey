//
//  StatusMenuController.h
//  VOpenKey
//
//  The menu bar icon and its menu, laid out the way macOS lays out its own: check marks for what is selected,
//  SF Symbols for actions, the shortcuts of the app shown on the right, and notices that appear only when there
//  is something to tell (missing permissions, secure input).
//

#import <Cocoa/Cocoa.h>

@interface StatusMenuController : NSObject <NSMenuDelegate>

// Re-reads the settings and brings the icon, check marks and notices up to date.
-(void)refresh;

@end
