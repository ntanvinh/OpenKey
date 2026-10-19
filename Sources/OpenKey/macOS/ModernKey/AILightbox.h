//
//  AILightbox.h
//  VOpenKey
//
//  A picture of the AI window shown large, inside VOpenKey AI (not in another application): it can be zoomed (buttons, ⌘+ ⌘-, pinch, or
//  the scroll of the mouse with ⌥), fitted to the window, shown at its real size, copied to the clipboard, and saved. Saving puts the file in
//  the Downloads folder of the user under a name that is not taken yet; nothing is asked. ⎋ closes it.
//

#import <Cocoa/Cocoa.h>

@interface AILightbox : NSObject

+(AILightbox*)shared;

/// Shows the picture. `png` is its data (what is copied and saved), `name` is shown as the title. Placed over `window` when there is one.
-(void)showImage:(NSImage*)image png:(NSData*)png name:(NSString*)name over:(NSWindow*)window;
-(void)close;
@property (nonatomic, readonly) BOOL visible;

/// 1 is the real size of the picture.
@property (nonatomic) CGFloat zoom;
-(void)zoomIn;
-(void)zoomOut;
-(void)zoomToFit;
-(void)zoomToActualSize;

/// Puts the picture on the clipboard (PNG and TIFF); the button shows a green check for a moment.
-(void)copyImage;
/// Writes the picture to the Downloads folder as "Ảnh AI 2026-10-19 17.30.12.png" (a number is added when the name is taken). nil with the reason
/// in *error when it cannot be done.
-(NSURL*)saveImage:(NSError**)error;
/// A green check is on the copy button / the save button now.
@property (nonatomic, readonly) BOOL showsCopied;
@property (nonatomic, readonly) BOOL showsSaved;
@property (nonatomic, readonly) NSURL* savedURL;
@property (nonatomic, readonly) NSTextField* statusLabel;
@property (nonatomic, readonly) NSPanel* panel;

/// Writes `png` into `folder` with a name made from the time; returns the file. Public for the window of the assistant, which saves too.
+(NSURL*)savePNG:(NSData*)png toFolder:(NSURL*)folder error:(NSError**)error;
/// ~/Downloads, or what a test says.
+(NSURL*)downloadsFolder;
+(void)setDownloadsFolderForTesting:(NSURL*)folder;

/// For tests: the window opens far off the screen and does not take the keyboard; the clipboard is another one.
@property (nonatomic) BOOL offscreenForTesting;
@property (nonatomic, strong) NSPasteboard* pasteboard;

@end
