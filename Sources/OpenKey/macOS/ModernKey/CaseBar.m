//
//  CaseBar.m
//  VOpenKey
//

#import "CaseBar.h"
#import "CaseBarPanel.h"
#import "CaseTransform.h"
#import "AISelection.h"
#import "CaretLocator.h"
#import "SnippetInserter.h"
#import "ShortcutRecorder.h"
#import <Carbon/Carbon.h>

int vCaseBarAuto = 1;
int vCaseBarHotKey = VOK_CASEBAR_DEFAULT_HOTKEY;

static NSString* const kAutoKey = @"CaseBarAuto";
static NSString* const kHotKeyKey = @"CaseBarHotKey";

static const NSUInteger kMaxLength = 100000;          //a longer text is not a thing to change the case of from a list
static const NSUInteger kPreviewLength = 2000;        //the previews and the choice of rows look at the start of the text only
static const NSTimeInterval kMouseWait = 0.15;        //the application updates its selection a moment after the button comes up
static const NSTimeInterval kKeyWait = 0.35;          //Shift+arrow repeats: wait until the selection stopped moving
static const NSTimeInterval kLocateWait = 0.5;        //an application that does not say where its selection is gets the list under the pointer
static const NSTimeInterval kAutoLifetime = 20;       //a list nobody used goes away by itself
static const CGFloat kDragDistance = 5;               //less than this is a click

static CaseBarPanel* sPanel;
static NSString* sText;                               //the whole selection
static NSArray<NSDictionary*>* sOffers;
static NSRunningApplication* sApplication;
static BOOL sExplicit;
static NSUInteger sGeneration;                        //every input and every new list: what was asked before is stale
static NSPoint sMouseDown;
static void (^sBoundary)(void);
static BOOL (^sBlocked)(void);
static BOOL sStarted;

static void (^sReader)(NSRunningApplication*, BOOL, void (^)(NSString*));
static NSRect (^sLocator)(pid_t);
static void (^sInserter)(NSString*, NSRunningApplication*);
static NSRunningApplication* (^sFront)(void);

//keys 1 2 3 4 5 6 7 8 9 0 of a US layout in this order: the rows ⌥1 … ⌥9, ⌥0
static const CGKeyCode kDigitKeys[10] = {18, 19, 20, 21, 23, 22, 26, 28, 25, 29};

@implementation CaseBar

#pragma mark - Settings

+(void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{kAutoKey: @1, kHotKeyKey: @(VOK_CASEBAR_DEFAULT_HOTKEY)}];
}

+(void)start {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    vCaseBarAuto = [defaults integerForKey:kAutoKey] != 0;
    vCaseBarHotKey = (int)[defaults integerForKey:kHotKeyKey];
    //0 would be "the A key alone": every A typed would open the list
    if (vCaseBarHotKey == 0)
        vCaseBarHotKey = VOK_SHORTCUT_NONE;
    if (!vCaseBarAuto)
        [self hide];
    if (!sStarted) {
        sStarted = YES;
        //the list belongs to the application whose text it is about; another one in front makes it wrong
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:nil
                                                                    usingBlock:^(NSNotification* note) {
            NSRunningApplication* now = note.userInfo[NSWorkspaceApplicationKey];
            if (now.processIdentifier != sApplication.processIdentifier)
                [CaseBar hide];
        }];
    }
}

#pragma mark - Things a test replaces

+(void (^)(NSRunningApplication*, BOOL, void (^)(NSString*)))selectionReader {
    return sReader ?: ^(NSRunningApplication* application, BOOL allowCopy, void (^completion)(NSString*)) {
        [AISelection readSelectionOfApplication:application allowCopy:allowCopy completion:completion];
    };
}

+(void)setSelectionReader:(void (^)(NSRunningApplication*, BOOL, void (^)(NSString*)))reader {
    sReader = [reader copy];
}

+(NSRect (^)(pid_t))selectionLocator {
    return sLocator ?: ^NSRect(pid_t pid) { return [CaretLocator selectionLineInProcess:pid]; };
}

+(void)setSelectionLocator:(NSRect (^)(pid_t))locator {
    sLocator = [locator copy];
}

+(void (^)(NSString*, NSRunningApplication*))textInserter {
    return sInserter ?: ^(NSString* text, NSRunningApplication* application) {
        [[SnippetInserter shared] insertText:text application:application];
    };
}

+(void)setTextInserter:(void (^)(NSString*, NSRunningApplication*))inserter {
    sInserter = [inserter copy];
}

+(NSRunningApplication* (^)(void))frontApplication {
    return sFront ?: ^NSRunningApplication*(void) { return [NSWorkspace sharedWorkspace].frontmostApplication; };
}

+(void)setFrontApplication:(NSRunningApplication* (^)(void))front {
    sFront = [front copy];
}

+(void)setTypingBoundaryHandler:(void (^)(void))handler {
    sBoundary = [handler copy];
}

+(void)setBlockedCheck:(BOOL (^)(void))check {
    sBlocked = [check copy];
}

+(CaseBarPanel*)panel {
    return sPanel;
}

#pragma mark - Showing

+(BOOL)isVisible {
    return sPanel != nil && sPanel.visible;
}

+(void)toggle {
    if (![self isVisible]) {
        [self show];
    } else if (sExplicit) {
        [self hide];
    } else {
        //the list came up by itself: the shortcut hands it the keys (arrows, ↩, Esc)
        sExplicit = YES;
        sPanel.highlighted = 0;
    }
}

+(void)hide {
    sGeneration++;
    if (![self isVisible])
        return;
    [sPanel orderOut:nil];
    sText = nil;
    sOffers = nil;
    sApplication = nil;
    if (sBoundary != nil)
        sBoundary();
}

+(BOOL)blocked {
    return sBlocked != nil && sBlocked();
}

//the application in front, unless it is this one
+(NSRunningApplication*)targetApplication {
    NSRunningApplication* application = [self frontApplication]();
    if (application == nil || application.processIdentifier == [NSProcessInfo processInfo].processIdentifier)
        return nil;
    return application;
}

+(void)show {
    [self findSelectionExplicit:YES];
}

//Asks the application in front for its selection and, when there is text, shows the list. `isExplicit`: the user asked (shortcut,
//menu), then the clipboard may be used to find the text and a selection that cannot be changed is answered with a beep.
+(void)findSelectionExplicit:(BOOL)isExplicit {
    NSRunningApplication* application = [self targetApplication];
    if (application == nil || [self blocked]) {
        if (isExplicit)
            NSBeep();
        return;
    }
    //macOS does not let any other application see the keys while a password field has the keyboard: the list could not be put away
    if (!isExplicit && IsSecureEventInputEnabled())
        return;
    NSUInteger generation = ++sGeneration;
    [self selectionReader](application, isExplicit, ^(NSString* text) {
        if (generation != sGeneration)
            return; //the user did something else meanwhile
        if (text.length == 0 || text.length > kMaxLength || [self blocked]) {
            if (isExplicit)
                NSBeep();
            return;
        }
        if ([CaseTransform offersForText:[self headOfText:text]].count == 0) {
            if (isExplicit)
                NSBeep();
            return;
        }
        [self locateSelectionOf:application then:^(NSRect line) {
            if (generation != sGeneration)
                return;
            [self presentText:text application:application explicit:isExplicit anchor:line];
        }];
    });
}

//Where the selection is. The question goes to the application off the main thread and is not waited for for long.
+(void)locateSelectionOf:(NSRunningApplication*)application then:(void (^)(NSRect line))then {
    __block BOOL answered = NO;
    void (^answer)(NSRect) = ^(NSRect line) {
        if (answered)
            return;
        answered = YES;
        then(line);
    };
    pid_t pid = application.processIdentifier;
    NSRect (^locator)(pid_t) = [self selectionLocator];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSRect line = locator(pid);
        dispatch_async(dispatch_get_main_queue(), ^{ answer(line); });
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLocateWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        answer(NSZeroRect);
    });
}

+(NSString*)headOfText:(NSString*)text {
    if (text.length <= kPreviewLength)
        return text;
    NSRange head = [text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, kPreviewLength)];
    return [text substringWithRange:head];
}

+(void)presentText:(NSString*)text application:(NSRunningApplication*)application explicit:(BOOL)isExplicit anchor:(NSRect)line {
    NSArray<NSDictionary*>* offers = [CaseTransform offersForText:[self headOfText:text]];
    if (offers.count == 0)
        return;
    if (sPanel == nil) {
        sPanel = [[CaseBarPanel alloc] init];
        sPanel.onChoose = ^(NSInteger index) { [CaseBar chooseIndex:index]; };
    }
    BOOL wasVisible = [self isVisible];
    sText = [text copy];
    sOffers = offers;
    sApplication = application;
    sExplicit = isExplicit;
    NSUInteger generation = ++sGeneration;
    [sPanel setOffers:offers];
    sPanel.highlighted = isExplicit ? 0 : -1;
    if (line.size.height <= 0) //the application does not say where: under the pointer
        [sPanel showNearPoint:[NSEvent mouseLocation]];
    else
        [sPanel showBelowRect:line];
    if (!wasVisible && sBoundary != nil)
        sBoundary();
    if (!isExplicit) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAutoLifetime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation == sGeneration)
                [CaseBar hide];
        });
    }
}

#pragma mark - Choosing

+(void)chooseIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)sOffers.count || sText == nil)
        return;
    VOKCaseStyle style = (VOKCaseStyle)[sOffers[index][@"style"] integerValue];
    NSString* result = [CaseTransform apply:style toText:sText];
    NSRunningApplication* application = sApplication;
    [self hide];
    if (result.length > 0)
        [self textInserter](result, application);
}

#pragma mark - Events of the tap

static BOOL IsSelectionKey(CGKeyCode code, CGEventFlags modifiers) {
    //Shift with an arrow, Home, End, Page Up/Down extends the selection; ⌘A selects all
    BOOL extends = (modifiers & kCGEventFlagMaskShift) && (code == 123 || code == 124 || code == 125 || code == 126 ||
                                                           code == 115 || code == 119 || code == 116 || code == 121);
    BOOL selectAll = code == 0 && (modifiers & kCGEventFlagMaskCommand) && !(modifiers & ~kCGEventFlagMaskCommand);
    return extends || selectAll;
}

+(void)scheduleLookIn:(NSTimeInterval)delay {
    NSUInteger generation = ++sGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation == sGeneration && vCaseBarAuto)
            [CaseBar findSelectionExplicit:NO];
    });
}

+(BOOL)keyDown:(CGKeyCode)keyCode flags:(CGEventFlags)flags {
    CGEventFlags modifiers = flags & (kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate | kCGEventFlagMaskControl | kCGEventFlagMaskShift);
    BOOL selects = vCaseBarAuto && IsSelectionKey(keyCode, modifiers);
    if (![self isVisible]) {
        if (selects)
            [self scheduleLookIn:kKeyWait];
        else
            sGeneration++; //a look that was waiting for the selection to settle is off: the user went on
        return NO;
    }

    if (modifiers == kCGEventFlagMaskAlternate) {
        for (NSInteger i = 0; i < 10; i++) {
            if (kDigitKeys[i] == keyCode && i < (NSInteger)sOffers.count) {
                [self chooseIndex:i];
                return YES;
            }
        }
    }
    if (sExplicit && modifiers == 0) {
        switch (keyCode) {
            case 126: [sPanel moveHighlight:-1]; return YES;
            case 125: [sPanel moveHighlight:1]; return YES;
            case 36: case 76: [self chooseIndex:sPanel.highlighted]; return YES;
            case 53: [self hide]; return YES;
            default: break;
        }
    }
    //any other key is for the application, and the list has had its time (a letter typed replaces the selection)
    [self hide];
    if (selects)
        [self scheduleLookIn:kKeyWait];
    return NO;
}

+(BOOL)pointerIsOnList {
    return [self isVisible] && NSPointInRect([NSEvent mouseLocation], sPanel.frame);
}

+(void)mouseDown {
    sMouseDown = [NSEvent mouseLocation];
    if ([self pointerIsOnList])
        return; //a click on a row is for the row
    [self hide];
}

+(void)mouseUpWithClickCount:(int64_t)clickCount flags:(CGEventFlags)flags {
    if (!vCaseBarAuto || [self pointerIsOnList])
        return;
    NSPoint up = [NSEvent mouseLocation];
    BOOL dragged = hypot(up.x - sMouseDown.x, up.y - sMouseDown.y) >= kDragDistance;
    BOOL extended = (flags & kCGEventFlagMaskShift) != 0; //Shift+click extends the selection
    if (dragged || clickCount >= 2 || extended)
        [self scheduleLookIn:kMouseWait];
}

+(void)scrolled {
    if ([self isVisible])
        [self hide];
}

@end
