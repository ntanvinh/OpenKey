//
//  SnippetStore.h
//  VOpenKey
//
//  The snippets of the user: text kept under a title, inserted into any application with a shortcut. They are saved in
//  ~/Library/Application Support/VOpenKey/Snippets/snippets.json, a file that can also be read and edited by hand.
//
//  A new installation starts with the ready-made snippets of engine/snippets/default-snippets.json (prompts for AI
//  assistants). They are copied into the list, so they are edited and deleted like the user's own. A later version of the
//  app that brings new ready-made snippets adds only those, and one that the user deleted stays deleted.
//
//  What matching is and how results are ranked lives in the shared engine (engine/SnippetSearch.h). Everything here runs on
//  the main thread.
//

#import <Foundation/Foundation.h>

/// Posted when the list changes: a snippet was added, edited or removed, or the ready-made ones were restored.
/// Not posted when a snippet is only used.
extern NSString* const VOKSnippetsDidChangeNotification;

@interface VOKSnippet : NSObject

/// "builtin.summarize" for a ready-made snippet, "user.<uuid>" for the others. Never changes.
@property (nonatomic, copy, readonly) NSString* identifier;
@property (nonatomic, copy) NSString* title;
/// Words to find it by, besides the title and the text.
@property (nonatomic, copy) NSString* keywords;
/// What is inserted. {clipboard}, {date} and {time} are replaced when it is inserted.
@property (nonatomic, copy) NSString* content;
@property (nonatomic) int useCount;
/// Seconds since 1970, 0 when never used.
@property (nonatomic) double lastUsed;

@property (nonatomic, readonly) BOOL isBuiltIn;

@end

@interface SnippetStore : NSObject

/// The store of the app: the file in Application Support, ready-made snippets from the app bundle.
+(SnippetStore*)shared;

/// Writes the list of the app now if a change is waiting to be saved. For when the app quits. Does nothing when the store
/// was never used.
+(void)flushShared;

/// A store that keeps its list in `file` and takes its ready-made snippets from `defaults` (may be nil). For tests.
-(instancetype)initWithFileURL:(NSURL*)file defaultsURL:(NSURL*)defaults;

/// All the snippets, in the order of the list.
@property (nonatomic, readonly) NSArray<VOKSnippet*>* snippets;

/// The snippets that match, best first. An empty query gives all of them, the ones used last first.
-(NSArray<VOKSnippet*>*)search:(NSString*)query;

-(VOKSnippet*)snippetWithIdentifier:(NSString*)identifier;

/// Adds a snippet of the user at the end of the list.
-(VOKSnippet*)addSnippetWithTitle:(NSString*)title keywords:(NSString*)keywords content:(NSString*)content;

/// Call after changing the title, keywords or content of a snippet.
-(void)snippetDidChange:(VOKSnippet*)snippet;

-(void)removeSnippet:(VOKSnippet*)snippet;

/// Counts a use: the snippets used most and last come first when searching.
-(void)recordUse:(VOKSnippet*)snippet;

/// Puts the ready-made snippets back: the ones that were deleted come back, the ones that were edited are as they were.
/// The snippets of the user are not touched.
-(void)restoreDefaults;

/// Writes the list now, when something is waiting to be saved. Saving otherwise happens a moment after a change.
-(void)flush;

/// Where the list is saved.
@property (nonatomic, readonly) NSURL* fileURL;

@end
