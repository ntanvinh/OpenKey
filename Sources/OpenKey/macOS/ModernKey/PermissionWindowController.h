//
//  PermissionWindowController.h
//  VOpenKey
//
//  The window shown when the app opens without the permissions it needs: one row per permission with a switch
//  that mirrors the state in System Settings. It watches for the user turning the switches on, then starts the
//  keyboard hook by itself, so nothing is left to do but toggle.
//

#import <Cocoa/Cocoa.h>

@interface PermissionWindowController : NSWindowController <NSWindowDelegate>

// onReady runs once every permission is granted and the keyboard hook is running.
-(instancetype)initWithReadyHandler:(void (^)(void))onReady;

-(void)present;

@end
