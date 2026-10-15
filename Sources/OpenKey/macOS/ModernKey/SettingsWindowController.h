//
//  SettingsWindowController.h
//  VOpenKey
//
//  The settings window, built like the settings window of a macOS app: tabs in the toolbar, groups of rows in
//  rounded cards, a switch at the right of every option.
//

#import <Cocoa/Cocoa.h>

@interface SettingsWindowController : NSWindowController <NSWindowDelegate>

// Brings the window to the front, for the menu item and for a click on the Dock icon.
-(void)show;

// Brings the window to the front on the tab with this title ("AI"), for the button of the AI window that opens its settings.
-(void)showTabTitled:(NSString*)title;

// Re-reads the saved settings into the controls, for when something else changed them.
-(void)reload;

@end
