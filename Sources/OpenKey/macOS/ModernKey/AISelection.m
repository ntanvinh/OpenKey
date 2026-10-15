//
//  AISelection.m
//  VOpenKey
//

#import "AISelection.h"
#import "SnippetInserter.h"
#import <Carbon/Carbon.h>

static NSPasteboard* sPasteboard;
static void (^sCopyCommand)(void);
static AISelectionStatus (^sProbe)(pid_t, NSString**);
static BOOL sProbeRunning;                          //a question to an application has not been answered yet; main thread only

static const NSTimeInterval kModifiersWait = 0.5;   //the shortcut of the window is often still held when the text is asked for
static const NSTimeInterval kCopyWait = 0.35;       //how long an application gets to put the copy on the clipboard
static const NSTimeInterval kAccessibilityWait = 0.9; //an application that does not answer Accessibility in this time is treated as one that cannot say

#pragma mark - Copy

//the editors of the VS Code family copy the line of the caret when nothing is selected, and say so on the clipboard
static BOOL CopiedFromEmptySelection(NSPasteboard* pasteboard) {
    NSData* data = [pasteboard dataForType:@"vscode-editor-data"];
    if (data.length == 0)
        return NO;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] && [json[@"isFromEmptySelection"] boolValue];
}

static BOOL ModifiersAreHeld(void) {
    CGEventFlags flags = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
    return (flags & (kCGEventFlagMaskControl | kCGEventFlagMaskAlternate | kCGEventFlagMaskShift | kCGEventFlagMaskCommand)) != 0;
}

//One reading by ⌘C: waits until the keys of the shortcut are let go, presses ⌘C, waits for the clipboard to change, takes what
//arrived and gives the clipboard back. An object with steps, not blocks that call themselves: a block that releases the only
//variable that holds it while it runs is freed under its own feet. Main thread.
@interface AICopyRead : NSObject
-(instancetype)initWithCompletion:(void (^)(NSString* text))completion;
-(void)start;
@end

@implementation AICopyRead {
    NSPasteboard* _pasteboard;
    VOKPasteboardSnapshot* _snapshot;
    NSInteger _before;
    NSDate* _modifiersDeadline;
    NSDate* _copyDeadline;
    BOOL _pressed;
    void (^_completion)(NSString*);
}

-(instancetype)initWithCompletion:(void (^)(NSString*))completion {
    self = [super init];
    if (self)
        _completion = [completion copy];
    return self;
}

-(void)start {
    _pasteboard = [AISelection pasteboard];
    _snapshot = [VOKPasteboardSnapshot snapshotOfPasteboard:_pasteboard];
    _before = _pasteboard.changeCount;
    _modifiersDeadline = [NSDate dateWithTimeIntervalSinceNow:kModifiersWait];
    [self step];
}

-(void)stepLater {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self step]; });
}

-(void)step {
    if (!_pressed) {
        //⌘C with ⌃⌥ still held down would not be ⌘C to every application
        if (ModifiersAreHeld() && [_modifiersDeadline timeIntervalSinceNow] > 0) {
            [self stepLater];
            return;
        }
        _pressed = YES;
        _copyDeadline = [NSDate dateWithTimeIntervalSinceNow:kCopyWait];
        [AISelection copyCommand]();
    }
    if (_pasteboard.changeCount == _before && [_copyDeadline timeIntervalSinceNow] > 0) {
        [self stepLater];
        return;
    }
    NSString* text = nil;
    if (_pasteboard.changeCount != _before) {
        text = [_pasteboard stringForType:NSPasteboardTypeString];
        if (CopiedFromEmptySelection(_pasteboard))
            text = nil;
        [_snapshot restoreToPasteboard:_pasteboard];
    }
    void (^completion)(NSString*) = _completion;
    _completion = nil;
    if (completion != nil)
        completion([text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0 ? text : nil);
}

@end

@implementation AISelection

+(AISelectionStatus (^)(pid_t, NSString**))accessibilityProbe {
    return sProbe;
}

+(void)setAccessibilityProbe:(AISelectionStatus (^)(pid_t, NSString**))probe {
    sProbe = [probe copy];
}

+(NSPasteboard*)pasteboard {
    return sPasteboard ?: [NSPasteboard generalPasteboard];
}

+(void)setPasteboard:(NSPasteboard*)pasteboard {
    sPasteboard = pasteboard;
}

+(void (^)(void))copyCommand {
    return sCopyCommand ?: ^{ [SnippetInserter postCommandKey:'c']; };
}

+(void)setCopyCommand:(void (^)(void))command {
    sCopyCommand = [command copy];
}

#pragma mark - Accessibility

static NSString* StringAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    NSString* result = nil;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) == kAXErrorSuccess && value != NULL) {
        if (CFGetTypeID(value) == CFStringGetTypeID())
            result = [(__bridge NSString*)value copy];
        CFRelease(value);
    }
    return result;
}

+(AISelectionStatus)statusOfElement:(AXUIElementRef)element text:(NSString**)text {
    NSString* role = StringAttribute(element, kAXRoleAttribute);
    NSString* subrole = StringAttribute(element, kAXSubroleAttribute);
    if ([subrole isEqualToString:@"AXSecureTextField"] || [role isEqualToString:@"AXSecureTextField"])
        return AISelectionSecret;

    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute, &value) != kAXErrorSuccess || value == NULL)
        return AISelectionUnknown;
    NSString* selected = CFGetTypeID(value) == CFStringGetTypeID() ? [(__bridge NSString*)value copy] : nil;
    CFRelease(value);
    if (selected == nil)
        return AISelectionUnknown;
    if (selected.length > 0) {
        if (text != NULL)
            *text = selected;
        return AISelectionText;
    }

    //empty: either nothing is selected, or this field does not tell. The range says which.
    CFTypeRef range = NULL;
    CFRange selection = CFRangeMake(0, 0);
    BOOL haveRange = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute, &range) == kAXErrorSuccess && range != NULL &&
                     CFGetTypeID(range) == AXValueGetTypeID() && AXValueGetValue((AXValueRef)range, (AXValueType)kAXValueTypeCFRange, &selection);
    if (range != NULL)
        CFRelease(range);
    return haveRange && selection.length == 0 ? AISelectionNone : AISelectionUnknown;
}

//Chromium and Electron only describe their text fields once asked to, like in the suggestion bar
static void AskForAccessibility(AXUIElementRef application, pid_t pid) {
    static NSMutableSet<NSNumber*>* asked;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ asked = [NSMutableSet set]; });
    @synchronized (asked) {
        if ([asked containsObject:@(pid)])
            return;
        [asked addObject:@(pid)];
    }
    AXUIElementSetAttributeValue(application, CFSTR("AXManualAccessibility"), kCFBooleanTrue);
}

//on a background queue: Accessibility may wait for a slow application
+(AISelectionStatus)statusOfApplication:(pid_t)pid text:(NSString**)text {
    AXUIElementRef application = AXUIElementCreateApplication(pid);
    if (application == NULL)
        return AISelectionUnknown;
    AXUIElementSetMessagingTimeout(application, 0.3);
    AskForAccessibility(application, pid);
    AISelectionStatus status = AISelectionUnknown;
    CFTypeRef focused = NULL;
    if (AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute, &focused) == kAXErrorSuccess && focused != NULL) {
        AXUIElementSetMessagingTimeout((AXUIElementRef)focused, 0.3);
        status = [self statusOfElement:(AXUIElementRef)focused text:text];
        CFRelease(focused);
    }
    CFRelease(application);
    return status;
}

#pragma mark - Putting it together

+(void)readSelectionOfApplication:(NSRunningApplication*)application allowCopy:(BOOL)allowCopy completion:(void (^)(NSString*))completion {
    if (application == nil || application.processIdentifier == [NSProcessInfo processInfo].processIdentifier) {
        completion(nil);
        return;
    }
    pid_t pid = application.processIdentifier;

    //What to do with the answer of Accessibility. Called once, on the main thread.
    __block BOOL answered = NO;
    void (^proceed)(AISelectionStatus, NSString*) = ^(AISelectionStatus status, NSString* text) {
        if (answered)
            return;
        answered = YES;
        if (status == AISelectionText) {
            completion(text);
        } else if (status == AISelectionNone || status == AISelectionSecret || !allowCopy || IsSecureEventInputEnabled()) {
            completion(nil);
        } else {
            [[[AICopyRead alloc] initWithCompletion:completion] start];
        }
    };

    //An application can leave an Accessibility question without an answer for good, and the thread that asks is then lost. So
    //nothing waits for the answer for more than a moment, and while one question is lost no other is asked: the copy is used.
    if (sProbeRunning) {
        proceed(AISelectionUnknown, nil);
        return;
    }
    sProbeRunning = YES;
    AISelectionStatus (^probe)(pid_t, NSString**) = sProbe;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString* text = nil;
        AISelectionStatus status = probe != nil ? probe(pid, &text) : [self statusOfApplication:pid text:&text];
        dispatch_async(dispatch_get_main_queue(), ^{
            sProbeRunning = NO;
            proceed(status, text);
        });
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAccessibilityWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        proceed(AISelectionUnknown, nil);
    });
}

@end
