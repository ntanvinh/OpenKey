//
//  AILocalSetupController.h
//  VOpenKey
//
//  The window "Cài AI chạy trên máy" (Settings > AI): looks at the Mac, advises, lets the user choose a model, says what will be
//  installed and what it needs, then installs it (AILocalSetup) and shows each step.
//
//  The advice comes before anything is downloaded: what this Mac has (memory, chip, disk, macOS, battery), which models it can
//  run comfortably, which only just, which not at all, and why. A model that cannot be installed (too big, no room, macOS too
//  old) cannot be started; one that is "tight" can, with a warning.
//

#import <Cocoa/Cocoa.h>
#import "AILocalSetup.h"
#import "AIModelAdvisor.h"

@interface AILocalSetupController : NSObject

/// Opens the window of the application (made on first use).
+(void)show;

/// With what the caller gives (tests): the Mac is described by `hardware`, `setup` does the work, `modelsDirectory` is where the
/// models already on the Mac are read from.
-(instancetype)initWithSetup:(AILocalSetup*)setup hardware:(AIHardware*)hardware catalog:(NSArray<AILocalModel*>*)catalog
             modelsDirectory:(NSURL*)modelsDirectory;

-(void)present;
-(void)close;

@property (nonatomic, readonly) NSWindow* window;
@property (nonatomic, readonly) AILocalSetup* setup;
@property (nonatomic, strong) AIHardware* hardware;
/// Where the size of a model typed by the user is looked up: the public library of Ollama, unless a test says otherwise.
@property (nonatomic, strong) NSURL* libraryURL;
@property (nonatomic, readonly) AILocalModel* selectedModel;
@property (nonatomic, readonly) AIModelAssessment* assessment;

@property (nonatomic, readonly) NSTextField* machineLabel;
/// What the Mac can run, in a sentence: the tooltip of the line that describes the Mac.
@property (nonatomic, readonly) NSString* overviewText;
@property (nonatomic, readonly) NSPopUpButton* modelPopUp;
@property (nonatomic, readonly) NSTextField* customField;
@property (nonatomic, readonly) NSTextField* summaryLabel;
@property (nonatomic, readonly) NSTextField* requirementsLabel;
@property (nonatomic, readonly) NSTextField* verdictLabel;
@property (nonatomic, readonly) NSTextField* problemsLabel;
@property (nonatomic, readonly) NSTextField* notesLabel;
@property (nonatomic, readonly) NSButton* installButton;
@property (nonatomic, readonly) NSButton* cancelButton;
@property (nonatomic, readonly) NSButton* removeButton;
@property (nonatomic, readonly) NSButton* refreshButton;
@property (nonatomic, readonly) NSTextField* resultLabel;
/// The list of steps, shown once an installation was started.
@property (nonatomic, readonly) NSView* progressSection;

/// Chooses a model of the list by its tag (what the popup does when the user clicks).
-(void)selectModelWithTag:(NSString*)tag;
/// What the user does with the buttons.
-(void)install:(id)sender;
-(void)cancel:(id)sender;
-(void)refreshHardware:(id)sender;
/// The text of the "other model" field was entered.
-(void)customModelEntered:(id)sender;

@end
