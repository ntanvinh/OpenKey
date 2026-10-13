//
//  AppPermissions.h
//  VOpenKey
//
//  The two privacy permissions VOpenKey needs to see the keys being typed and replace them.
//

#import <Cocoa/Cocoa.h>

@interface AppPermissions : NSObject

// Accessibility: lets the app post the corrected characters.
+(BOOL)accessibilityGranted;
// Input Monitoring: lets the app know which keys are pressed.
+(BOOL)inputMonitoringGranted;
+(BOOL)allGranted;

// Adds the app to the list in System Settings (macOS shows its own prompt) and opens the pane, where
// all that is left for the user is to turn the switch on.
+(void)requestAccessibility;
+(void)requestInputMonitoring;

+(void)openAccessibilitySettings;
+(void)openInputMonitoringSettings;

@end
