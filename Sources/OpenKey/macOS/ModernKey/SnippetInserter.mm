//
//  SnippetInserter.mm
//  VOpenKey
//

#import "SnippetInserter.h"
#import <Carbon/Carbon.h>
#include "SnippetSearch.h"

static NSString* const kTransientType = @"org.nspasteboard.TransientType";
static const NSTimeInterval kPasteDelay = 0.05;          //let the snippet window close and the application take the keyboard back
static const NSTimeInterval kActivationDelay = 0.2;      //when the application first has to be brought to the front

static CGEventSourceRef sEventSource = NULL;

//The key that types a letter on the keyboard layout in use. ⌘V is the key labelled V, which is not the same physical
//key on Dvorak or Colemak; 9 is the one of the usual layout.
static CGKeyCode KeyCodeForLetter(UniChar letter, CGKeyCode fallback) {
    TISInputSourceRef source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
    if (source == NULL)
        return fallback;
    CGKeyCode result = fallback;
    CFDataRef layoutData = (CFDataRef)TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
    if (layoutData != NULL) {
        const UCKeyboardLayout* layout = (const UCKeyboardLayout*)CFDataGetBytePtr(layoutData);
        for (CGKeyCode code = 0; code < 128; code++) {
            UInt32 deadKeys = 0;
            UniChar characters[4];
            UniCharCount length = 0;
            OSStatus status = UCKeyTranslate(layout, code, kUCKeyActionDown, 0, LMGetKbdType(),
                                             kUCKeyTranslateNoDeadKeysBit, &deadKeys, 4, &length, characters);
            if (status == noErr && length == 1 && characters[0] == letter) {
                result = code;
                break;
            }
        }
    }
    CFRelease(source);
    return result;
}

static void PostCommand(unichar letter) {
    CGEventSourceRef source = sEventSource;
    BOOL ownSource = NO;
    if (source == NULL) {
        source = CGEventSourceCreate(kCGEventSourceStatePrivate);
        ownSource = YES;
    }
    CGKeyCode key = KeyCodeForLetter(letter, letter == 'c' ? 8 : 9);
    CGEventRef down = CGEventCreateKeyboardEvent(source, key, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, key, false);
    CGEventSetFlags(down, kCGEventFlagMaskCommand);
    CGEventSetFlags(up, kCGEventFlagMaskCommand);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    if (ownSource)
        CFRelease(source);
}

@implementation VOKPasteboardSnapshot {
    //one item, the usual case: the types of the clipboard by name. This way types that are not UTIs ("vscode-editor-data" of the
    //VS Code family, written by Electron) survive, which NSPasteboardItem refuses.
    NSDictionary<NSString*, NSData*>* _single;
    NSArray<NSString*>* _singleOrder;
    //several items (files copied in the Finder): item by item
    NSArray<NSDictionary<NSString*, NSData*>*>* _items;
}

+(instancetype)snapshotOfPasteboard:(NSPasteboard*)pasteboard {
    VOKPasteboardSnapshot* snapshot = [[VOKPasteboardSnapshot alloc] init];
    if (pasteboard.pasteboardItems.count <= 1) {
        NSMutableDictionary* contents = [NSMutableDictionary dictionary];
        NSMutableArray* order = [NSMutableArray array];
        for (NSPasteboardType type in pasteboard.types) {
            if ([type hasPrefix:@"dyn."]) //made up by macOS for the types it cannot name: it makes them again
                continue;
            NSData* data = [pasteboard dataForType:type];
            if (data != nil) {
                contents[type] = data;
                [order addObject:type];
            }
        }
        snapshot->_single = contents;
        snapshot->_singleOrder = order;
        return snapshot;
    }
    NSMutableArray* items = [NSMutableArray array];
    for (NSPasteboardItem* item in pasteboard.pasteboardItems) {
        NSMutableDictionary* contents = [NSMutableDictionary dictionary];
        for (NSPasteboardType type in item.types) {
            if ([type hasPrefix:@"dyn."])
                continue;
            NSData* data = [item dataForType:type];
            if (data != nil)
                contents[type] = data;
        }
        if (contents.count > 0)
            [items addObject:contents];
    }
    snapshot->_items = items;
    return snapshot;
}

-(void)restoreToPasteboard:(NSPasteboard*)pasteboard {
    if (_single != nil) {
        if (_singleOrder.count == 0) {
            [pasteboard clearContents];
            return;
        }
        [pasteboard declareTypes:_singleOrder owner:nil];
        for (NSString* type in _singleOrder)
            [pasteboard setData:_single[type] forType:type];
        return;
    }
    [pasteboard clearContents];
    NSMutableArray* items = [NSMutableArray array];
    for (NSDictionary<NSString*, NSData*>* contents in _items) {
        NSPasteboardItem* item = [[NSPasteboardItem alloc] init];
        for (NSPasteboardType type in contents)
            [item setData:contents[type] forType:type];
        [items addObject:item];
    }
    if (items.count > 0)
        [pasteboard writeObjects:items];
}

@end

@implementation SnippetInserter {
    //what the clipboard held before a snippet was put on it, waiting to be put back
    VOKPasteboardSnapshot* _saved;
    NSInteger _changeCountAfterWrite;
    NSUInteger _generation;     //a restore that was scheduled for an earlier insertion must not act on a later one
}

+(SnippetInserter*)shared {
    static SnippetInserter* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[SnippetInserter alloc] init]; });
    return instance;
}

+(void)useEventSource:(CGEventSourceRef)source {
    sEventSource = source;
}

+(void)postCommandKey:(unichar)letter {
    PostCommand(letter);
}

-(instancetype)init {
    self = [super init];
    if (self) {
        _pasteboard = [NSPasteboard generalPasteboard];
        _restoreDelay = 0.8;
        _pasteCommand = ^{ PostCommand('v'); };
    }
    return self;
}

#pragma mark - Placeholders

-(NSString*)expandedText:(NSString*)text {
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSDate* now = [NSDate date];
    formatter.dateFormat = @"dd/MM/yyyy";
    NSString* date = [formatter stringFromDate:now];
    formatter.dateFormat = @"HH:mm";
    NSString* time = [formatter stringFromDate:now];

    vsnippet::Values values;
    values.clipboard = [_pasteboard stringForType:NSPasteboardTypeString].UTF8String ?: "";
    values.date = date.UTF8String;
    values.time = time.UTF8String;
    std::string expanded = vsnippet::expand(text.UTF8String ?: "", values);
    return [NSString stringWithUTF8String:expanded.c_str()] ?: @"";
}

#pragma mark - The clipboard

//Puts the clipboard back now if a snippet is still on it
-(void)restoreIfUntouched {
    VOKPasteboardSnapshot* saved = _saved;
    _saved = nil;
    if (saved != nil && _pasteboard.changeCount == _changeCountAfterWrite)
        [saved restoreToPasteboard:_pasteboard];
    //else: the user or an application copied something since, which is worth more than what was there before
}

#pragma mark - Inserting

-(void)insertSnippetContent:(NSString*)content application:(NSRunningApplication*)application {
    //an earlier snippet is perhaps still waiting to give the clipboard back: that comes first, or {clipboard} would be
    //the text of that snippet
    [self restoreIfUntouched];

    [self pasteText:[self expandedText:content] application:application];
}

-(void)insertText:(NSString*)text application:(NSRunningApplication*)application {
    [self restoreIfUntouched];
    [self pasteText:text application:application];
}

//Puts the text on the clipboard, presses ⌘V in the application and gives the clipboard back
-(void)pasteText:(NSString*)text application:(NSRunningApplication*)application {
    if (text.length == 0)
        return;

    _saved = [VOKPasteboardSnapshot snapshotOfPasteboard:_pasteboard];
    [_pasteboard clearContents];
    NSPasteboardItem* item = [[NSPasteboardItem alloc] init];
    [item setString:text forType:NSPasteboardTypeString];
    [item setData:[NSData data] forType:kTransientType];
    [_pasteboard writeObjects:@[item]];
    _changeCountAfterWrite = _pasteboard.changeCount;
    NSUInteger generation = ++_generation;

    //the window of the snippets does not make VOpenKey the frontmost application, so normally the target still is
    BOOL frontmostIsTarget = application == nil ||
        [NSWorkspace sharedWorkspace].frontmostApplication.processIdentifier == application.processIdentifier;
    if (!frontmostIsTarget)
        [application activateWithOptions:0];
    NSTimeInterval pasteAfter = frontmostIsTarget ? kPasteDelay : kActivationDelay;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pasteAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.pasteCommand();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((pasteAfter + self.restoreDelay) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation == self->_generation)
            [self restoreIfUntouched];
    });
}

@end
