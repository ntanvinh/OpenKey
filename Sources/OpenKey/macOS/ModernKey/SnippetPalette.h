//
//  SnippetPalette.h
//  VOpenKey
//
//  The window that opens when the snippet shortcut is pressed: a search field above the list of snippets, the text of the
//  one selected at the right, like the search of Spotlight or Alfred.
//
//  - type to search (without accents is fine), ↑ ↓ to choose, ↩ to insert, ⌘1 to ⌘9 to insert one of the first nine, Esc to
//    clear the search and then to close;
//  - the window does not make VOpenKey the frontmost application (it is a non-activating panel, like the window of
//    Spotlight): the application that was being typed in stays in front and gets the snippet once the window is gone.
//    Typing Vietnamese in the search field works like anywhere else;
//  - when the window cannot take the keyboard that way VOpenKey becomes the active application for as long as the window
//    is open, and the inserter brings the other application back to the front before pasting. The hidden default
//    SnippetsActivateApp (YES) does this always.
//

#import <Cocoa/Cocoa.h>
#import "SnippetInserter.h"
#import "SnippetStore.h"

/// ⌃⌥S, in the format of ShortcutRecorder
#define VOK_SNIPPET_DEFAULT_HOTKEY 0x73000301

/// Settings, saved by the Settings window. The event tap reads them for every key, hence plain variables.
#ifdef __cplusplus
extern "C" {
#endif
extern int vSnippetsEnabled;    //the shortcut opens the window
extern int vSnippetHotKey;      //the shortcut, in the format of ShortcutRecorder
#ifdef __cplusplus
}
#endif

@interface SnippetPalette : NSObject

/// The values of the settings before the user has changed them. Call at launch, before any window shows them.
+(void)registerDefaults;

/// Reads the settings. Call once at launch, and again after they were reset.
+(void)start;

+(SnippetPalette*)shared;

/// Whether the window is on screen. The typing engine and the suggestion bar leave the keys alone meanwhile.
+(BOOL)isVisible;

/// What the shortcut does: opens the window, or closes it when it is open.
+(void)toggle;
+(void)show;
+(void)hide;

/// Called when the window opens and when it closes, with the typing engine to be told that the word being typed is over:
/// what is typed in the search field must not become part of the next word in another application.
+(void)setTypingBoundaryHandler:(void (^)(void))handler;

#pragma mark For tests

-(instancetype)initWithStore:(SnippetStore*)store inserter:(SnippetInserter*)inserter;

@property (nonatomic, readonly) NSPanel* panel;
@property (nonatomic, readonly) NSTextField* searchField;
@property (nonatomic, readonly) NSArray<VOKSnippet*>* results;
@property (nonatomic, readonly) NSInteger selectedRow;

-(void)showPalette;
-(void)hidePalette;
/// Types in the search field.
-(void)setQuery:(NSString*)query;
-(void)selectRow:(NSInteger)row;
/// Inserts the snippet selected, as ↩ does.
-(void)insertSelected;

@end
