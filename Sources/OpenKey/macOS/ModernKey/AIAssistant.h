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
//  - ⇧⌘↩ puts the answer into the application (it replaces the selection, or goes where the cursor was), ⇧⌘C copies it and closes the window.
//  - When the AI is a program on this Mac that is signed in by itself (Codex, Claude Code, Antigravity), the model and the thinking
//    level can be chosen here too, in the header. They start as a light model at the fast level, which is enough to write.
//  - While the AI works the window moves and talks (AIProgress): a light runs round the place of the answer and sentences change as the
//    time goes on, so that a long wait does not look like a hang. After a while at a high thinking level it offers to ask again at the
//    lowest one, which is what makes the answer fast.
//  - Under the box are ready-made conversions (AIPresets): Sửa lỗi, Lịch sự, Thân mật, Hài hước, Trang trọng, Lãng mạn, four kinds of
//    poem, Ngắn gọn, Đầy đủ hơn, Dịch sang Anh/Việt. One click applies it to the text of the box and asks at once; the button stays lit,
//    so that "Tạo lại" asks the same again, and goes out when the text is edited (what is typed then is a request of its own).
//  - The gear in the header opens the settings of the AI at any time.
//  - "Tạo ảnh" (Codex CLI only) asks Codex for a picture of what is in the box, with its imagegen skill named in the request, as it makes
//    poor pictures otherwise. The picture is shown in the place of the answer; it can be copied, put into the application, or shown in the
//    Finder. Codex keeps the file in its own folder (~/.codex/generated_images), which the window says.
//  - Like the window of the snippets it does not make VOpenKey the frontmost application, and typing Vietnamese in it works like
//    anywhere else. Nothing typed or received is kept: the text is gone when the window closes.
//

#import <Cocoa/Cocoa.h>
#import "AIClient.h"
#import "AIHardware.h"
#import "AIPresets.h"
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

/// The window opens far outside the screen and never takes the keyboard (the keyboard checks are skipped). Tests turn it on so that they
/// can run while somebody works on the same Mac.
@property (nonatomic) BOOL offscreenForTesting;

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
/// Model and thinking level, for an AI that is a program on this Mac (Codex, Claude Code, Antigravity); hidden for the others.
@property (nonatomic, readonly) NSPopUpButton* modelPopUp;
@property (nonatomic, readonly) NSPopUpButton* effortPopUp;
@property (nonatomic, readonly) NSButton* settingsButton;
/// The gear in the header: always there, opens the settings of the AI.
@property (nonatomic, readonly) NSButton* openSettingsButton;
/// What is shown in the place of the answer while it is awaited, and the light that runs round that place.
@property (nonatomic, readonly) NSTextField* progressLabel;
@property (nonatomic, readonly) BOOL glowing;
/// "Tạo ảnh": asks Codex for a picture of what is described in the box. Enabled only when the AI in use is Codex CLI.
@property (nonatomic, readonly) NSButton* imageButton;
/// The picture that was made, shown in the place of the answer; "Hiện ảnh" shows its file in the Finder.
@property (nonatomic, readonly) NSImageView* imageView;
@property (nonatomic, readonly) NSButton* revealButton;
@property (nonatomic, readonly) NSURL* resultImageURL;
/// "Lưu": saves the picture in the Downloads folder.
@property (nonatomic, readonly) NSButton* saveImageButton;
/// The buttons of the ready-made conversions, in the order of +[AIPresets all], and the one that is chosen (nil when none is).
@property (nonatomic, readonly) NSArray<NSButton*>* presetButtons;
@property (nonatomic, readonly) AIPreset* activePreset;
/// What a click on a conversion does: chooses it and asks at once. Does nothing while an answer is on its way; with nothing in the box it only says so.
-(void)applyPresetWithIdentifier:(NSString*)identifier;
/// "Hỏi lại ở mức Thấp": appears when the wait gets long at a thinking level above the lowest.
@property (nonatomic, readonly) NSButton* speedButton;
/// After how many seconds of waiting the window suggests a lower thinking level. 8 unless a test says otherwise.
@property (nonatomic) NSTimeInterval slowHintDelay;
@property (nonatomic, readonly) AIAssistantState state;
/// What the service has written so far.
@property (nonatomic, readonly) NSString* resultText;

/// Opens the window for an application whose selection is already known (nil when nothing is selected).
-(void)presentWithSelection:(NSString*)selection application:(NSRunningApplication*)application;
-(void)hideAssistant;

-(void)ask;             //the button "Tạo", ⌘↩
-(void)openImage;       //clicking the picture: it is shown large in the lightbox of the application (AILightbox)
-(void)saveImage;       //the button "Lưu"
-(void)askForImage;     //the button "Tạo ảnh", ⌥⌘↩
-(void)stop;            //the button "Dừng", ⎋ while generating
-(void)insertResult;    //⇧⌘↩
-(void)copyResult;      //⇧⌘C: copy to the clipboard and close on success

@end
