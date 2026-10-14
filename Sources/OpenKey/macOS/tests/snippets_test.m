// Tests of the snippets on macOS: the store (file, ready-made snippets, search), the inserter (clipboard, paste), the
// search window and the editor. Run with run-snippets-test.sh.
//
// No key is sent to the system: key events go straight into the windows of this process with -sendEvent:. A window of
// the snippets is shown for a moment, without taking the keyboard from the application in front.
#import <Cocoa/Cocoa.h>
#import "SnippetStore.h"
#import "SnippetInserter.h"
#import "SnippetPalette.h"
#import "SnippetEditorController.h"

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

static void Spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static NSString* gDefaults;

static NSURL* FreshFile(NSString* name) {
    NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"snipmac-" stringByAppendingString:[NSUUID UUID].UUIDString]];
    return [[NSURL fileURLWithPath:dir isDirectory:YES] URLByAppendingPathComponent:name];
}

static NSDictionary* ReadJSON(NSURL* file) {
    NSData* data = [NSData dataWithContentsOfURL:file];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

#pragma mark - Store

static void TestStore(void) {
    printf("-- store\n");
    NSURL* defaults = [NSURL fileURLWithPath:gDefaults];
    NSURL* file = FreshFile(@"snippets.json");
    SnippetStore* store = [[SnippetStore alloc] initWithFileURL:file defaultsURL:defaults];
    NSUInteger builtin = store.snippets.count;
    printf("builtin snippets: %lu\n", (unsigned long)builtin);
    CHECK(builtin >= 20);
    CHECK([store snippetWithIdentifier:@"builtin.summarize"] != nil);
    [store flush];
    CHECK([[NSFileManager defaultManager] fileExistsAtPath:file.path]);
    NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:file.path error:nil];
    CHECK([attributes[NSFilePosixPermissions] intValue] == 0600);
    NSDictionary* json = ReadJSON(file);
    CHECK([json[@"snippets"] count] == builtin);
    CHECK([json[@"seeded"] count] == builtin);

    //search
    NSArray* found = [store search:@"tom tat"];
    CHECK(found.count >= 1 && [[found[0] identifier] isEqualToString:@"builtin.summarize"]);
    CHECK([store search:@""].count == builtin);
    CHECK([store search:@"zzzzqq"].count == 0);

    //a user snippet, an edit, a use
    VOKSnippet* mine = [store addSnippetWithTitle:@"Chữ ký" keywords:@"signature chu ky" content:@"Trân trọng,\nVinh"];
    CHECK([mine.identifier hasPrefix:@"user."]);
    CHECK(!mine.isBuiltIn);
    CHECK([[[store search:@"chu ky"] firstObject] isEqual:mine]);
    mine.content = @"Trân trọng,\nVinh Nguyễn";
    [store snippetDidChange:mine];
    VOKSnippet* summarize = [store snippetWithIdentifier:@"builtin.summarize"];
    NSString* originalTitle = summarize.title;
    summarize.title = @"Tóm tắt (của tôi)";
    [store snippetDidChange:summarize];
    [store recordUse:mine];
    CHECK(mine.useCount == 1 && mine.lastUsed > 0);
    CHECK([[[store search:@""] firstObject] isEqual:mine]);     //used last comes first

    //a notification for edits, none for a use
    __block int notified = 0;
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:VOKSnippetsDidChangeNotification object:store queue:nil
                                                             usingBlock:^(NSNotification* n) { notified++; }];
    [store recordUse:mine];
    CHECK(notified == 0);
    [store snippetDidChange:mine];
    CHECK(notified == 1);
    [[NSNotificationCenter defaultCenter] removeObserver:token];

    //delete a ready-made one, keep going: it stays deleted
    VOKSnippet* translate = [store snippetWithIdentifier:@"builtin.translate-en"];
    [store removeSnippet:translate];
    CHECK([store snippetWithIdentifier:@"builtin.translate-en"] == nil);
    CHECK(store.snippets.count == builtin);                      //-1 +1 (mine)
    [store flush];

    SnippetStore* again = [[SnippetStore alloc] initWithFileURL:file defaultsURL:defaults];
    CHECK(again.snippets.count == builtin);
    CHECK([again snippetWithIdentifier:@"builtin.translate-en"] == nil);          //deleted stays deleted
    CHECK([[again snippetWithIdentifier:mine.identifier].content isEqualToString:@"Trân trọng,\nVinh Nguyễn"]);
    CHECK([again snippetWithIdentifier:mine.identifier].useCount == 2);
    CHECK([[again snippetWithIdentifier:@"builtin.summarize"].title isEqualToString:@"Tóm tắt (của tôi)"]);

    //restore: the deleted one is back, the edited one as it was, mine untouched
    [again restoreDefaults];
    CHECK([again snippetWithIdentifier:@"builtin.translate-en"] != nil);
    CHECK([[again snippetWithIdentifier:@"builtin.summarize"].title isEqualToString:originalTitle]);
    CHECK([again snippetWithIdentifier:mine.identifier] != nil);
    CHECK(again.snippets.count == builtin + 1);
    [again flush];

    //a newer version brings one more ready-made snippet: only that one is added
    NSMutableDictionary* newer = [ReadJSON(defaults) mutableCopy];
    NSMutableArray* list = [newer[@"snippets"] mutableCopy];
    [list addObject:@{@"id": @"builtin.new-in-4", @"title": @"Mới", @"keywords": @"moi new tinh nang", @"content": @"Một snippet mẫu mới trong bản sau, đủ dài để được tính."}];
    newer[@"snippets"] = list;
    NSURL* newerFile = FreshFile(@"newer.json");
    [[NSFileManager defaultManager] createDirectoryAtURL:[newerFile URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSJSONSerialization dataWithJSONObject:newer options:0 error:nil] writeToURL:newerFile atomically:YES];
    [store removeSnippet:[store snippetWithIdentifier:@"builtin.plan"]];
    [store flush];
    SnippetStore* updated = [[SnippetStore alloc] initWithFileURL:file defaultsURL:newerFile];
    CHECK([updated snippetWithIdentifier:@"builtin.new-in-4"] != nil);
    CHECK([updated snippetWithIdentifier:@"builtin.plan"] == nil);                 //deleted earlier: still gone

    //a file nobody can read is kept aside and the list starts again
    NSURL* broken = FreshFile(@"snippets.json");
    [[NSFileManager defaultManager] createDirectoryAtURL:[broken URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    [@"{ this is not json" writeToURL:broken atomically:YES encoding:NSUTF8StringEncoding error:nil];
    SnippetStore* recovered = [[SnippetStore alloc] initWithFileURL:broken defaultsURL:defaults];
    CHECK(recovered.snippets.count == builtin);
    NSArray* siblings = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[broken URLByDeletingLastPathComponent].path error:nil];
    BOOL keptAside = NO;
    for (NSString* name in siblings) if ([name hasPrefix:@"snippets-unreadable-"]) keptAside = YES;
    CHECK(keptAside);

    //no ready-made file at all (a damaged bundle): an empty list that works
    SnippetStore* empty = [[SnippetStore alloc] initWithFileURL:FreshFile(@"snippets.json") defaultsURL:nil];
    CHECK(empty.snippets.count == 0);
    CHECK([empty search:@"a"].count == 0);
    VOKSnippet* first = [empty addSnippetWithTitle:@"A" keywords:nil content:nil];
    CHECK([empty search:@""].count == 1 && first.keywords.length == 0);
}

#pragma mark - Inserter

static void TestInserter(void) {
    printf("-- inserter\n");
    NSPasteboard* board = [NSPasteboard pasteboardWithUniqueName];
    SnippetInserter* inserter = [[SnippetInserter alloc] init];
    inserter.pasteboard = board;
    inserter.restoreDelay = 0.15;
    __block NSString* pasted = nil;
    __block BOOL transient = NO;
    __block int pastes = 0;
    inserter.pasteCommand = ^{
        pastes++;
        pasted = [board stringForType:NSPasteboardTypeString];
        transient = [board.types containsObject:@"org.nspasteboard.TransientType"];
    };

    //expansion
    [board clearContents];
    [board setString:@"đã copy {date}" forType:NSPasteboardTypeString];
    NSString* expanded = [inserter expandedText:@"[{clipboard}] {date} {time} {x}"];
    NSDateFormatter* f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"dd/MM/yyyy";
    NSString* today = [f stringFromDate:[NSDate date]];
    CHECK(([expanded hasPrefix:[NSString stringWithFormat:@"[đã copy {date}] %@ ", today]]));
    CHECK([expanded hasSuffix:@" {x}"]);
    CHECK([[expanded substringFromIndex:expanded.length - 9] length] == 9);
    [board clearContents];
    CHECK([[inserter expandedText:@"a{clipboard}b"] isEqualToString:@"ab"]);   //empty clipboard

    //an insertion: the snippet is on the clipboard at the time of the paste, the user's clipboard comes back afterwards
    [board clearContents];
    NSPasteboardItem* item = [[NSPasteboardItem alloc] init];
    [item setString:@"gốc" forType:NSPasteboardTypeString];
    [item setData:[@"<b>gốc</b>" dataUsingEncoding:NSUTF8StringEncoding] forType:NSPasteboardTypeHTML];
    [board writeObjects:@[item]];
    [inserter insertSnippetContent:@"Dịch:\n{clipboard}" application:nil];
    Spin(0.1);
    CHECK(pastes == 1);
    CHECK([pasted isEqualToString:@"Dịch:\ngốc"]);
    CHECK(transient);
    Spin(0.3);
    CHECK([[board stringForType:NSPasteboardTypeString] isEqualToString:@"gốc"]);
    NSString* html = [[NSString alloc] initWithData:[board dataForType:NSPasteboardTypeHTML] encoding:NSUTF8StringEncoding];
    CHECK([html isEqualToString:@"<b>gốc</b>"]);                                  //the other types too
    CHECK(![board.types containsObject:@"org.nspasteboard.TransientType"]);

    //something copied during the paste is worth more than what was there: no restore
    [inserter insertSnippetContent:@"snippet" application:nil];
    Spin(0.1);
    CHECK([pasted isEqualToString:@"snippet"]);
    [board clearContents];
    [board setString:@"mới copy" forType:NSPasteboardTypeString];
    Spin(0.3);
    CHECK([[board stringForType:NSPasteboardTypeString] isEqualToString:@"mới copy"]);

    //empty text: nothing happens
    int before = pastes;
    [inserter insertSnippetContent:@"{clipboard}" application:nil];                  //clipboard is "mới copy", not empty
    Spin(0.1);
    CHECK(pastes == before + 1);
    [board clearContents];
    [inserter insertSnippetContent:@"{clipboard}" application:nil];                  //empty clipboard: nothing to paste
    Spin(0.1);
    CHECK(pastes == before + 1);

    //two in a row: the second one's {clipboard} is the user's text, not the first snippet
    [board clearContents];
    [board setString:@"của người dùng" forType:NSPasteboardTypeString];
    [inserter insertSnippetContent:@"một" application:nil];
    [inserter insertSnippetContent:@"hai {clipboard}" application:nil];
    Spin(0.1);
    CHECK([pasted isEqualToString:@"hai của người dùng"]);
    Spin(0.4);
    CHECK([[board stringForType:NSPasteboardTypeString] isEqualToString:@"của người dùng"]);
}

#pragma mark - Palette

static NSEvent* KeyEvent(NSWindow* window, NSString* characters, unsigned short code, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                        windowNumber:window.windowNumber context:nil characters:characters
         charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
}

static void TestPalette(void) {
    printf("-- palette\n");
    NSURL* defaults = [NSURL fileURLWithPath:gDefaults];
    SnippetStore* store = [[SnippetStore alloc] initWithFileURL:FreshFile(@"snippets.json") defaultsURL:defaults];
    NSPasteboard* board = [NSPasteboard pasteboardWithUniqueName];
    SnippetInserter* inserter = [[SnippetInserter alloc] init];
    inserter.pasteboard = board;
    inserter.restoreDelay = 0.05;
    __block NSString* pasted = nil;
    __block int pastes = 0;
    inserter.pasteCommand = ^{ pastes++; pasted = [board stringForType:NSPasteboardTypeString]; };
    [board clearContents];
    [board setString:@"VĂN BẢN" forType:NSPasteboardTypeString];

    __block int boundaries = 0;
    [SnippetPalette setTypingBoundaryHandler:^{ boundaries++; }];

    SnippetPalette* palette = [[SnippetPalette alloc] initWithStore:store inserter:inserter];
    CHECK(![SnippetPalette isVisible]);
    printf("app active before showing: %d\n", NSApp.active);
    [palette showPalette];
    Spin(0.3);
    printf("panel visible=%d key=%d, app active=%d (a nonactivating panel should be key without activating the app)\n",
           palette.panel.visible, palette.panel.keyWindow, NSApp.active);
    CHECK(palette.panel.visible);
    //macOS gives the keyboard to no window while the screen is locked, whatever the window asks for
    NSDictionary* session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    if ([session[@"CGSSessionScreenIsLocked"] boolValue])
        printf("screen is locked: the check that the window takes the keyboard is skipped\n");
    else
        CHECK(palette.panel.keyWindow);
    CHECK([SnippetPalette isVisible]);
    CHECK(boundaries == 1);
    CHECK(palette.searchField.currentEditor != nil);                                 //the field has the keyboard
    CHECK(palette.results.count == store.snippets.count);
    CHECK(palette.selectedRow == 0);

    //typing: the key events of the panel reach the field
    NSWindow* w = palette.panel;
    for (NSString* c in @[@"d", @"i", @"c", @"h"])
        [w sendEvent:KeyEvent(w, c, 0, 0)];
    Spin(0.05);
    printf("typed -> field '%s', %lu results\n", palette.searchField.stringValue.UTF8String, (unsigned long)palette.results.count);
    CHECK([palette.searchField.stringValue isEqualToString:@"dich"]);
    CHECK(palette.results.count >= 2 && [[palette.results[0] identifier] hasPrefix:@"builtin.translate"]);

    //arrows
    [w sendEvent:KeyEvent(w, [NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey], 125, NSEventModifierFlagFunction)];
    CHECK(palette.selectedRow == 1);
    [w sendEvent:KeyEvent(w, [NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey], 126, NSEventModifierFlagFunction)];
    CHECK(palette.selectedRow == 0);
    [w sendEvent:KeyEvent(w, [NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey], 126, NSEventModifierFlagFunction)];
    CHECK(palette.selectedRow == 0);                                                  //not past the top

    //Esc clears the search first
    [w sendEvent:KeyEvent(w, @"\x1b", 53, 0)];
    CHECK(palette.searchField.stringValue.length == 0);
    CHECK(palette.panel.visible);
    CHECK(palette.results.count == store.snippets.count);

    //accent-free search finds accented titles, and Return inserts the first result
    palette.searchField.stringValue = @"";
    [palette setQuery:@"tom tat"];
    CHECK([[palette.results[0] identifier] isEqualToString:@"builtin.summarize"]);
    [w sendEvent:KeyEvent(w, @"\r", 36, 0)];
    Spin(0.2);
    CHECK(!palette.panel.visible);
    CHECK(![SnippetPalette isVisible]);
    CHECK(boundaries == 2);
    CHECK(pastes == 1);
    CHECK([pasted containsString:@"VĂN BẢN"] && [pasted hasPrefix:@"Hãy tóm tắt văn bản"]);
    CHECK([store snippetWithIdentifier:@"builtin.summarize"].useCount == 1);

    //next time the one used comes first for an empty search
    [palette showPalette];
    Spin(0.1);
    CHECK([[palette.results[0] identifier] isEqualToString:@"builtin.summarize"]);

    //⌘2 inserts the second row
    BOOL handled = [w performKeyEquivalent:KeyEvent(w, @"2", 19, NSEventModifierFlagCommand)];
    Spin(0.2);
    CHECK(handled);
    CHECK(!palette.panel.visible);
    CHECK(pastes == 2);
    CHECK([pasted rangeOfString:@"{clipboard}"].location == NSNotFound);

    //⌘9 with fewer rows: handled and nothing inserted
    [palette showPalette];
    [palette setQuery:@"commit"];
    CHECK(palette.results.count == 1);
    handled = [w performKeyEquivalent:KeyEvent(w, @"9", 25, NSEventModifierFlagCommand)];
    CHECK(handled && palette.panel.visible && pastes == 2);
    //plain keys are not key equivalents
    CHECK(![w performKeyEquivalent:KeyEvent(w, @"2", 19, 0)]);

    //no match: nothing selected, Return does nothing
    [palette setQuery:@"zzzzqqq"];
    CHECK(palette.results.count == 0);
    [w sendEvent:KeyEvent(w, @"\r", 36, 0)];
    CHECK(palette.panel.visible && pastes == 2);

    //a change in the store while open (edited in the editor): the list follows
    [palette setQuery:@""];
    NSUInteger count = palette.results.count;
    [store addSnippetWithTitle:@"Thêm khi đang mở" keywords:@"" content:@"nội dung"];
    CHECK(palette.results.count == count + 1);

    //losing the keyboard closes it
    [palette hidePalette];
    CHECK(!palette.panel.visible);
    [palette showPalette];
    Spin(0.1);
    [palette.panel resignKeyWindow];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidResignKeyNotification object:palette.panel];
    CHECK(!palette.panel.visible);
}

#pragma mark - Editor

static void TestEditor(void) {
    printf("-- editor\n");
    NSURL* defaults = [NSURL fileURLWithPath:gDefaults];
    NSURL* file = FreshFile(@"snippets.json");
    SnippetStore* store = [[SnippetStore alloc] initWithFileURL:file defaultsURL:defaults];
    NSUInteger count = store.snippets.count;
    SnippetEditorController* editor = [[SnippetEditorController alloc] initWithStore:store];
    [editor.window layoutIfNeeded];
    CHECK(editor.table.numberOfRows == (NSInteger)count);
    CHECK(editor.table.selectedRow == 0);
    VOKSnippet* first = store.snippets[0];
    CHECK([editor.titleField.stringValue isEqualToString:first.title]);
    CHECK([editor.contentView.string isEqualToString:first.content]);
    CHECK(editor.titleField.enabled && editor.contentView.editable);

    //editing writes through to the store
    editor.titleField.stringValue = @"Đổi tên";
    [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:editor.titleField];
    CHECK([first.title isEqualToString:@"Đổi tên"]);
    editor.contentView.string = @"nội dung mới {clipboard}";
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTextDidChangeNotification object:editor.contentView];
    CHECK([first.content isEqualToString:@"nội dung mới {clipboard}"]);
    CHECK([editor.table.selectedRowIndexes count] == 1);                           //the list kept the selection

    //selecting another one shows it without writing anything into the first
    [editor.table selectRowIndexes:[NSIndexSet indexSetWithIndex:3] byExtendingSelection:NO];
    CHECK([editor.titleField.stringValue isEqualToString:store.snippets[3].title]);
    CHECK([first.title isEqualToString:@"Đổi tên"]);

    //add
    [editor addSnippet];
    CHECK(store.snippets.count == count + 1);
    CHECK(editor.table.numberOfRows == (NSInteger)count + 1);
    CHECK([editor.titleField.stringValue isEqualToString:@"Snippet mới"]);
    CHECK(editor.table.selectedRow == (NSInteger)count);
    editor.keywordsField.stringValue = @"qzxchuky";
    [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:editor.keywordsField];
    CHECK([store.snippets.lastObject.keywords isEqualToString:@"qzxchuky"]);

    //filter
    editor.filterField.stringValue = @"qzxchuky";
    [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:editor.filterField];
    CHECK(editor.table.numberOfRows == 1);
    editor.filterField.stringValue = @"";
    [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:editor.filterField];
    CHECK(editor.table.numberOfRows == (NSInteger)count + 1);

    //remove
    [editor.table selectRowIndexes:[NSIndexSet indexSetWithIndex:count] byExtendingSelection:NO];
    [editor removeSelectedSnippet];
    CHECK(store.snippets.count == count);
    CHECK(editor.table.selectedRow >= 0);

    //an empty store: the form is disabled, and adding works again
    for (VOKSnippet* s in store.snippets)
        [store removeSnippet:s];
    CHECK(editor.table.numberOfRows == 0);
    CHECK(!editor.titleField.enabled);
    [editor addSnippet];
    CHECK(editor.titleField.enabled && editor.table.numberOfRows == 1);
    [editor close];
    [store flush];
    CHECK([ReadJSON(file)[@"snippets"] count] == 1);
}

int main(int argc, char** argv) { @autoreleasepool {
    NSApplication* app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    gDefaults = [NSString stringWithUTF8String:argv[1]];
    TestStore();
    TestInserter();
    TestPalette();
    TestEditor();
    printf(failures ? "\n%d FAILURES\n" : "ALL OK\n", failures);
    return failures ? 1 : 0;
}}
