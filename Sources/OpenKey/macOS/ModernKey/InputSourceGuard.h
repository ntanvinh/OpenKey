//
//  InputSourceGuard.h
//  VOpenKey
//
//  VOpenKey types Vietnamese by itself. If macOS' own Vietnamese input source (Telex, VNI) is selected at the same time,
//  every letter is converted twice and what comes out is wrong. While VOpenKey is set to Vietnamese this keeps the input
//  source of macOS on ABC: when it is a Vietnamese one it is switched to ABC, now and whenever it is changed back.
//
//  Left alone on purpose:
//  - other languages (Japanese, Chinese...): they are not "two Vietnamese input methods", and the setting that turns
//    VOpenKey off when macOS types another language already handles them;
//  - the secure input fallback (SecureInputMonitor), which switches to macOS' Vietnamese source on purpose while a
//    background app holds secure input;
//  - plain keyboard layouts such as ABC, US, Dvorak, macOS' "Vietnamese" layout of keys and Unicode Hex Input: they
//    convert nothing.
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

/// Setting "Keep macOS on ABC while typing Vietnamese", on by default.
extern int vForceABC;

@interface InputSourceGuard : NSObject

/// The value of the setting before the user has changed it. Call at launch, before any window shows the setting.
+(void)registerDefaults;

/// Loads the setting and starts watching the input source of macOS. Call once at launch.
+(void)start;

/// Looks now: if VOpenKey is set to Vietnamese and macOS' source is a Vietnamese one, switches macOS to ABC.
/// Call it when VOpenKey's language or the setting changes. Returns YES if it switched.
+(BOOL)enforce;

/// Whether an input source is one of macOS' (or another) Vietnamese input methods.
+(BOOL)isVietnameseSource:(TISInputSourceRef)source;

@end
