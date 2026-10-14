//
//  SnippetEditorController.h
//  VOpenKey
//
//  The window where snippets are made, edited and deleted: the list at the left, the title, keywords and text of the one
//  selected at the right. Changes are kept as they are made, there is nothing to save.
//

#import <Cocoa/Cocoa.h>
#import "SnippetStore.h"

@interface SnippetEditorController : NSWindowController

/// Opens the window of the app (one only), in front of the other windows.
+(void)show;

/// For tests: an editor on another store, not shown.
-(instancetype)initWithStore:(SnippetStore*)store;

@property (nonatomic, readonly) NSTableView* table;
@property (nonatomic, readonly) NSTextField* titleField;
@property (nonatomic, readonly) NSTextField* keywordsField;
@property (nonatomic, readonly) NSTextView* contentView;
@property (nonatomic, readonly) NSSearchField* filterField;

/// Adds a snippet and selects it, as the + button does.
-(void)addSnippet;

/// Deletes the snippet selected without asking, as the − button does after the question.
-(void)removeSelectedSnippet;

@end
