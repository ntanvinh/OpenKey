//
//  SnippetInserter.h
//  VOpenKey
//
//  Puts the text of a snippet into the application that has the keyboard.
//
//  The text is pasted (⌘V), not typed: typed, every line break of a prompt would be a Return, and in a chat box that
//  sends the message half way. Pasting needs the clipboard, so what the user had copied is put back afterwards, unless
//  something else was copied in the meantime. The snippet is marked as temporary on the clipboard
//  (org.nspasteboard.TransientType) so that clipboard managers do not keep it in their history.
//
//  {clipboard}, {date} and {time} in the text are replaced first (see engine/SnippetSearch.h): {clipboard} with what the
//  user had copied before, {date} as 14/10/2026 and {time} as 09:05.
//

#import <Cocoa/Cocoa.h>

@interface SnippetInserter : NSObject

+(SnippetInserter*)shared;

/// The event source that VOpenKey's own event tap recognises and leaves alone. Set it once the tap exists, so that the ⌘V
/// that pastes the snippet is not treated as typing. Without it a private source of this class is used.
+(void)useEventSource:(CGEventSourceRef)source;

/// The clipboard that is used. The general one, unless a test says otherwise.
@property (nonatomic, strong) NSPasteboard* pasteboard;

/// How long after the paste the clipboard of the user is put back. The application reads it a moment after ⌘V.
@property (nonatomic) NSTimeInterval restoreDelay;

/// What presses ⌘V. A test replaces it.
@property (nonatomic, copy) void (^pasteCommand)(void);

/// `text` with {clipboard}, {date} and {time} replaced by the current clipboard text and time.
-(NSString*)expandedText:(NSString*)text;

/// Inserts a snippet (its text, placeholders not replaced yet) into `application`, the one that had the keyboard before
/// the snippet window opened. When the application is not in front it is brought there first.
-(void)insertSnippetContent:(NSString*)content application:(NSRunningApplication*)application;

@end
