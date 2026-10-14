//
//  RememberedAppsController.h
//  VOpenKey
//
//  The list of what VOpenKey has remembered for each application (typing language and code table): remembered by itself,
//  shown here, and open to changes by hand.
//

#import <Cocoa/Cocoa.h>

@interface RememberedAppsController : NSObject

/// Shows the list as a sheet of `parent`.
+(void)presentFromWindow:(NSWindow*)parent;

@end
