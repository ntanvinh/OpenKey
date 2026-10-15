//
//  AISelection.h
//  VOpenKey
//
//  Finds the text the user has selected in the application that has the keyboard, so that it can be put in the AI window.
//
//  1. Accessibility first: the application is asked what is selected in the field that has the keyboard. It touches nothing, so
//     the clipboard is not used. A password field is never read.
//  2. If the application cannot say (most web and Electron applications), ⌘C is pressed, the clipboard is read and then put
//     back as it was. Editors that copy the whole line when nothing is selected (VS Code and its forks) are recognised, and
//     what they copy is not taken for a selection.
//

#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

typedef NS_ENUM(NSInteger, AISelectionStatus) {
    AISelectionText,        //something is selected, here it is
    AISelectionNone,        //the field answered: nothing is selected
    AISelectionUnknown,     //the field cannot say
    AISelectionSecret       //a password field: never read
};

@interface AISelection : NSObject

/// The selected text of the application, `nil` when nothing is selected or it cannot be found. `completion` is called on the main
/// thread, shortly (Accessibility may take a fraction of a second, ⌘C a few tenths at most). With `allowCopy` NO the clipboard is
/// never touched.
+(void)readSelectionOfApplication:(NSRunningApplication*)application
                        allowCopy:(BOOL)allowCopy
                       completion:(void (^)(NSString* text))completion;

/// What Accessibility says about one text element. The text is trimmed of nothing: it is what the user selected.
+(AISelectionStatus)statusOfElement:(AXUIElementRef)element text:(NSString**)text;

/// What asks an application about its selection. Accessibility, unless a test replaces it. Called on a background queue.
@property (class, nonatomic, copy) AISelectionStatus (^accessibilityProbe)(pid_t pid, NSString** text);

/// The clipboard that ⌘C is read from. The general one, unless a test says otherwise.
@property (class, nonatomic, strong) NSPasteboard* pasteboard;

/// What presses ⌘C. A test replaces it.
@property (class, nonatomic, copy) void (^copyCommand)(void);

@end
