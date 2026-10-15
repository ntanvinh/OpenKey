//
//  AIAssistant.h
//  VOpenKey
//
//  The window that opens when the AI shortcut is pressed: the user says what text they want, an AI service writes it, and the
//  text is put where the user was typing.
//
//  - If something was selected in the application, it is already in the box when the window opens, with the cursor in front of
//    it to write the instruction ("Dịch sang tiếng Anh"). The answer then replaces the selection.
//  - Type the request, ⌘↩ to ask. The answer is written in the window as the service produces it; ⎋ stops it.
//  - ⇧⌘↩ puts the answer into the application (it replaces the selection, or goes where the cursor was), ⇧⌘C copies it.
//  - Like the window of the snippets it does not make VOpenKey the frontmost application, and typing Vietnamese in it works like
//    anywhere else. Nothing typed or received is kept: the text is gone when the window closes.
//

#import <Cocoa/Cocoa.h>
#import "AIClient.h"
#import "AIHardware.h"
#import "SnippetInserter.h"

typedef NS_ENUM(NSInteger, AIAssistantState) {
    AIAssistantStateIdle,           //nothing asked yet, or the window was just opened
    AIAssistantStateGenerating,
    AIAssistantStateDone,
    AIAssistantStateFailed
};

@interface AIAssistant : NSObject

+(AIAssistant*)shared;

/// Whether the window is on screen. The typing engine and the suggestion bar leave the keys alone meanwhile.
+(BOOL)isVisible;

/// What the shortcut does: opens the window, or closes it when it is open.
+(void)toggle;
/// Looks for the selection of the application in front, then opens the window.
+(void)show;
+(void)hide;

/// Called when the window opens and when it closes, with the typing engine to be told that the word being typed is over.
+(void)setTypingBoundaryHandler:(void (^)(void))handler;

/// Called to open the AI page of the settings (the window has a button for it when nothing is connected yet).
+(void)setSettingsHandler:(void (^)(void))handler;

#pragma mark For tests

-(instancetype)initWithInserter:(SnippetInserter*)inserter;

/// How the Mac is described when a request goes to an AI that runs on it (to say that the Mac is busy). A test gives its own.
@property (nonatomic, copy) AIHardware* (^hardwareProvider)(void);

@property (nonatomic, readonly) NSPanel* panel;
@property (nonatomic, readonly) NSTextView* inputView;
@property (nonatomic, readonly) NSTextView* outputView;
@property (nonatomic, readonly) NSButton* actionButton;     //"Tạo" while idle, "Dừng" while generating
@property (nonatomic, readonly) NSButton* copyButton;
@property (nonatomic, readonly) NSButton* insertButton;
@property (nonatomic, readonly) NSTextField* statusLabel;
@property (nonatomic, readonly) NSTextField* contextLabel;
@property (nonatomic, readonly) NSTextField* infoLabel;
@property (nonatomic, readonly) NSPopUpButton* providerPopUp;
@property (nonatomic, readonly) NSButton* settingsButton;
@property (nonatomic, readonly) AIAssistantState state;
/// What the service has written so far.
@property (nonatomic, readonly) NSString* resultText;

/// Opens the window for an application whose selection is already known (nil when nothing is selected).
-(void)presentWithSelection:(NSString*)selection application:(NSRunningApplication*)application;
-(void)hideAssistant;

-(void)ask;             //the button "Tạo", ⌘↩
-(void)stop;            //the button "Dừng", ⎋ while generating
-(void)insertResult;    //⇧⌘↩
-(void)copyResult;      //⇧⌘C

@end
