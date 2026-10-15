//
//  CaseBar.h
//  VOpenKey
//
//  The list that appears when text is selected and offers to change its case: CHỮ HOA, chữ thường, Viết Hoa Từng Từ... each with a
//  preview of the selection in that style (see CaseTransform for the styles, CaseBarPanel for how it looks).
//
//  Two ways in:
//  - by itself, a moment after the user selected text with the mouse (drag, double or triple click, Shift+click) or with the
//    keyboard (Shift+arrows, ⌘A), in an application that tells its selection through Accessibility. Nothing is ever copied for
//    this: the clipboard is not touched until a style is chosen. Any key, click or scroll puts it away, except the keys that
//    choose. Chosen by ⌥1 … ⌥9 (⌥0), or by clicking a row;
//  - by the shortcut (⌃⌥C by default) or the menu of the status icon, for any selection, also in applications that do not tell it
//    (it is then found with ⌘C, like for the AI window). Then the list also takes ↑ ↓ ↩ and Esc.
//  The chosen text is pasted over the selection (the clipboard is put back afterwards).
//
//  Everything here runs on the main thread, the one of the event tap.
//

#import <Cocoa/Cocoa.h>

@class CaseBarPanel;

/// ⌃⌥C, in the format of ShortcutRecorder
#define VOK_CASEBAR_DEFAULT_HOTKEY 0x63000308

#ifdef __cplusplus
extern "C" {
#endif
/// The list shows up by itself when text is selected. The event tap reads this for every key, hence a plain variable.
extern int vCaseBarAuto;
/// The shortcut, in the format of ShortcutRecorder; VOK_SHORTCUT_NONE when there is none.
extern int vCaseBarHotKey;
#ifdef __cplusplus
}
#endif

@interface CaseBar : NSObject

/// The values of the settings before the user has changed them. Call at launch, before any window shows them.
+(void)registerDefaults;

/// Reads the settings and starts watching the applications. Call at launch, and again after the settings were reset.
+(void)start;

+(BOOL)isVisible;

/// What the shortcut does: opens the list for the selection of the application in front, or closes it when it is open.
+(void)toggle;
+(void)show;
+(void)hide;

/// Called when the list opens and closes: the typing engine must not carry the word being typed over to the selection.
+(void)setTypingBoundaryHandler:(void (^)(void))handler;

/// Asked before the list shows up by itself or opens: YES when something else has the keyboard (the snippet window...).
+(void)setBlockedCheck:(BOOL (^)(void))check;

#pragma mark From the event tap

/// A key was pressed. YES when the list used it: the tap must not pass it on, nor its key up.
+(BOOL)keyDown:(CGKeyCode)keyCode flags:(CGEventFlags)flags;
/// A mouse button went down / the left button came up (`clickCount` 2 for a double click) / the wheel turned.
+(void)mouseDown;
+(void)mouseUpWithClickCount:(int64_t)clickCount flags:(CGEventFlags)flags;
+(void)scrolled;

#pragma mark For tests

/// What reads the selection of an application: the text, nil when there is none. AISelection, unless a test replaces it.
@property (class, nonatomic, copy) void (^selectionReader)(NSRunningApplication* application, BOOL allowCopy, void (^completion)(NSString* text));
/// What says where the selection is (Cocoa screen coordinates, NSZeroRect when unknown). Called on a background queue.
@property (class, nonatomic, copy) NSRect (^selectionLocator)(pid_t pid);
/// What puts a text over the selection of an application. SnippetInserter, unless a test replaces it.
@property (class, nonatomic, copy) void (^textInserter)(NSString* text, NSRunningApplication* application);
/// The application in front. NSWorkspace, unless a test replaces it.
@property (class, nonatomic, copy) NSRunningApplication* (^frontApplication)(void);
/// The list itself, for a test to look at.
+(CaseBarPanel*)panel;
/// Shows the list for a text that is already known, without asking any application.
+(void)presentText:(NSString*)text application:(NSRunningApplication*)application explicit:(BOOL)isExplicit anchor:(NSRect)line;

@end
