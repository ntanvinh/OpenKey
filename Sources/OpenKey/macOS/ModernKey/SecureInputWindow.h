//
//  SecureInputWindow.h
//  VOpenKey
//
//  The window behind "Secure Input đang bật bởi …" in the menu of the menu bar icon: which program holds macOS' secure
//  event input (the reason the icon is yellow and typing Vietnamese stopped), with what can be found out about it so that
//  a person can track it down: name, role (the app being typed in, an app in the background, a helper, the system), bundle
//  id, process number, version, where it lives, since when it runs, which process started it. It says what to try, offers
//  "Hiện trong Finder" and "Mở Activity Monitor", and copies the facts as text.
//
//  It follows SecureInputMonitor while it is open: when the holder changes it shows the new one, when secure input is
//  released it says so and keeps the last holder in view. Esc closes it.
//

#import <Cocoa/Cocoa.h>
#import "SecureInputHolder.h"

// What secure input costs the person right now.
typedef NS_ENUM(NSInteger, SecureInputEffect) {
    SecureInputEffectBlocked,    // typing Vietnamese is off: the icon shows English (yellow)
    SecureInputEffectFallback,   // macOS' own Vietnamese input source types in VOpenKey AI's place
    SecureInputEffectNone        // VOpenKey AI is in English mode: nothing is lost yet
};

@interface SecureInputWindow : NSObject

/// Opens the window with what SecureInputMonitor knows now (and makes the application active: a menu bar application is not,
/// and the window would open behind the others).
+(void)show;
+(SecureInputWindow*)shared;

@property (nonatomic, readonly) NSWindow* window;

/// Shows `holder` (nil: secure input is off, `lastHolder` and `releasedAt` say who it was and since when it is off).
-(void)displayHolder:(SecureInputHolder*)holder effect:(SecureInputEffect)effect lastHolder:(SecureInputHolder*)lastHolder
          releasedAt:(NSDate*)releasedAt;

#pragma mark For tests

/// Where "Sao chép thông tin" puts the text; the general pasteboard unless a test says otherwise (it must not touch the clipboard of the user).
@property (nonatomic, strong) NSPasteboard* pasteboard;
/// What "Hiện trong Finder" does with the path; it shows the item in Finder unless a test says otherwise.
@property (nonatomic, copy) void (^revealURL)(NSURL* url);
/// What "Mở Activity Monitor" does; it opens the program unless a test says otherwise.
@property (nonatomic, copy) void (^openActivityMonitor)(void);
/// The most the window may be high, in points, as a low screen would allow (0: what the screen leaves). A test makes it small to see the content scroll.
@property (nonatomic) CGFloat maximumHeightForTesting;

/// What the window shows, inside its scroll view.
@property (nonatomic, readonly) NSView* documentView;
@property (nonatomic, readonly) NSTextField* headingLabel;
@property (nonatomic, readonly) NSTextField* explanationLabel;
@property (nonatomic, readonly) NSTextField* noticeLabel;
/// nil when there is no path to show.
@property (nonatomic, readonly) NSButton* revealButton;
/// nil while there is nothing to copy.
@property (nonatomic, readonly) NSButton* copyButton;
@property (nonatomic, readonly) NSButton* activityMonitorButton;
@property (nonatomic, readonly) NSButton* closeButton;
/// The rows of the card about the holder, as "name\nvalue", in the order they are shown.
@property (nonatomic, readonly) NSArray<NSString*>* rowTexts;
/// The advice that is shown, one string per line.
@property (nonatomic, readonly) NSArray<NSString*>* tipTexts;

-(void)reveal;
-(void)copyInformation;
-(void)openActivityMonitorNow;

/// The facts as plain text, what "Sao chép thông tin" copies.
-(NSString*)informationText;

@end
