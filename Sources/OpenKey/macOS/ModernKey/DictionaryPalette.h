//
//  DictionaryPalette.h
//  VOpenKey
//
//  Floating 2-column Spotlight-style dictionary lookup and open-source catalog manager panel.
//

#import <Cocoa/Cocoa.h>
#import "DictionaryService.h"

NS_ASSUME_NONNULL_BEGIN

@interface DictionaryPalette : NSObject

+(instancetype)shared;
+(BOOL)isVisible;
+(void)showPalette;
+(void)showWithQuery:(nullable NSString*)query;
+(void)hidePalette;
+(void)setTypingBoundaryHandler:(nullable dispatch_block_t)handler;

/// Designated initializer for tests using an isolated DictionaryService.
-(instancetype)initWithService:(DictionaryService*)service;

-(void)show;
-(void)showWithQuery:(nullable NSString*)query captureSelection:(BOOL)captureSelection;
-(void)hide;

@property (nonatomic, readonly) NSPanel* panel;
@property (nonatomic, readonly) NSTextField* searchField;
@property (nonatomic, readonly) NSTableView* resultsTable;
@property (nonatomic, readonly) NSTextView* definitionView;
@property (nonatomic, readonly) NSButton* speakButton;
@property (nonatomic, readonly) NSButton* copyButton;
/// What the speaker button reads for the word that is shown (⌘P does the same); nil when it is not an English word.
@property (nonatomic, copy, readonly, nullable) NSString* speakText;
@property (nonatomic, readonly) BOOL showingManager;
@property (nonatomic, copy, readonly, nullable) NSString* selectedFilterDictId;
@property (nonatomic, copy, readonly) NSArray<VOKDictionarySearchHit*>* currentHits;
@property (nonatomic, strong, nullable) id testWindow;

/// Reads the English word that is shown, aloud (the speaker button and ⌘P).
-(void)speakCurrentWord;
-(void)setShowingManager:(BOOL)showingManager;
-(void)selectFilterDictId:(nullable NSString*)dictId;
-(void)reloadResultsAndSelectFirst:(BOOL)selectFirst;

@end

NS_ASSUME_NONNULL_END
