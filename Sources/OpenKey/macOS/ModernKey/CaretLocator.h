//
//  CaretLocator.h
//  VOpenKey
//
//  Finds where the text being typed is on the screen, by asking the application that has the keyboard through
//  Accessibility. The suggestion bar is put under that line.
//

#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

@interface CaretLocation : NSObject

/// The character before the caret, the last one typed (a space when no word is being typed). Cocoa screen coordinates,
/// NSZeroRect when the application does not tell.
@property (nonatomic) NSRect caret;

/// The first character of the word being typed, NSZeroRect when unknown or when the word is one character.
@property (nonatomic) NSRect wordStart;

/// The focused text field or text area, NSZeroRect when unknown.
@property (nonatomic) NSRect field;

/// The application can tell its text, so `textMatches` says something.
@property (nonatomic) BOOL canCheckText;

/// The text the application has before the caret is what was typed: the position is up to date. Applications such as
/// Chrome describe their text a moment after it was typed, and until then give the position of the line before.
@property (nonatomic) BOOL textMatches;

@end

@interface CaretLocator : NSObject

/// The element of the application that has the keyboard, retained (CFRelease it), NULL when there is none or the application does
/// not answer in time. Asks Chromium and Electron to describe their text fields, once per process. Off the main thread.
+(AXUIElementRef)copyFocusedElementInProcess:(pid_t)pid CF_RETURNS_RETAINED;

/// Asks the frontmost application. Takes up to a fraction of a second when the application is slow to catch up: call it
/// off the main thread. `word` is what has been typed of the current word, empty right after a space.
+(CaretLocation*)locateInProcess:(pid_t)pid word:(NSString*)word;

/// The same for a given text element. When the text does not match yet it asks again, up to `retries` times, 30 ms apart.
+(CaretLocation*)locateInElement:(AXUIElementRef)element word:(NSString*)word retries:(int)retries;

/// The line the bar goes under: where the text of the word starts, and the height and place of the line of the caret.
+(NSRect)lineForLocation:(CaretLocation*)location typing:(BOOL)typing;

/// Where the selected text of an application is, for a list that goes under it: the line the selection ends on, starting at the
/// x of the selection when it begins on that same line. Cocoa screen coordinates; NSZeroRect when nothing is selected or the
/// application does not tell. Like `locateInProcess:` it may take a moment: call it off the main thread.
+(NSRect)selectionLineInProcess:(pid_t)pid;

@end
