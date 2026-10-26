//
//  SuggestionController.h
//  VOpenKey
//
//  The macOS side of the suggestion bar. What suggestions are and how they behave lives in the shared
//  engine (engine/Suggest*.h); this file only does what is specific to macOS: reading the dictionary
//  files, finding the text caret through Accessibility, showing the panel and saving what was learned.
//  Everything here runs on the main thread, the same one as the event tap.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, VOKSuggestionKey) {
    VOKSuggestionKeySpace,  //a plain space, passed on unchanged by the typing engine
    VOKSuggestionKeyDelete,
    VOKSuggestionKeyOther   //any other key that is not part of a word
};

//settings, saved by the Settings window
extern int vSuggestEnabled;
extern int vSuggestNextWord;
extern int vSuggestLearn;
extern int vSuggestCompounds;
extern int vMacroConfirm;      //an abbreviation is not replaced by itself: the bar offers its full text, Tab or ⌥1 types it (on by default)
extern int vSuggestTabAccepts; //Tab chooses the first suggestion (on by default); ⌥Tab is an ordinary Tab, for the fields of a form

/// The bar is in use: for words, or only for the abbreviations that wait for the user.
extern int vUseMacro;
#define VOK_SUGGESTION_ACTIVE (vSuggestEnabled || (vUseMacro && vMacroConfirm))

@interface SuggestionController : NSObject

/// The values of the settings before the user has changed them. Call at launch, before any window shows them.
+(void)registerDefaults;

/// Loads the dictionaries and starts watching the frontmost application. Call once at launch.
+(void)start;
/// Saves what was learned.
+(void)stop;

/// The settings or the frontmost application changed.
+(void)reloadSettings;

/// Editable bundle identifiers. On first use, includes popular standalone terminals.
+(NSArray<NSString*>*)excludedApps;
+(BOOL)appExclusionsEnabled;
+(void)setAppExclusionsEnabled:(BOOL)enabled;
+(void)setExcludedApps:(NSArray<NSString*>*)identifiers;
+(NSString*)defaultNameForExcludedApp:(NSString*)identifier;
+(BOOL)isAppIdentifierExcluded:(NSString*)identifier;
/// Reads the dictionary files again, after files were added or edited.
+(void)reloadDictionaries;
/// Forgets everything learned from the user's typing, in memory and on disk.
+(void)forgetLearnedWords;
/// Shows the folder where dictionary files can be added in Finder.
+(void)openDictionaryFolder;

+(BOOL)isShowing;

/// Typing was interrupted (mouse click, other application, language switch...).
+(void)reset;

/// A key was handled by the typing engine. word is the word now on screen, empty if there is none;
/// raw is the keys pressed for it, before Telex or VNI turned them into accents.
/// macro is the full text of the word when it is an abbreviation that waits for the user (vPeekMacro), nil otherwise.
+(void)keyProcessed:(VOKSuggestionKey)key word:(NSString*)word raw:(NSString*)raw macro:(NSString* _Nullable)macro;

/// Tab or ⌥1-5 was pressed. Returns YES when it chose a suggestion: swallow the key, delete `erase`
/// characters and type `text`.
+(BOOL)acceptSlot:(NSInteger)slot
      currentWord:(NSString*)word
             text:(NSString* __autoreleasing*)text
            erase:(NSUInteger*)erase;

@end
