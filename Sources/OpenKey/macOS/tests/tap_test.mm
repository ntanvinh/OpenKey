// Tests of the event tap of VOpenKey, OpenKeyCallback in OpenKey.mm, with the real typing engine behind it. Run with
// run-tap-test.sh.
//
// Key events are made here and handed to the callback, which answers like it does to the system: it lets an event through
// or swallows it, and it posts the keys it types itself (Backspace, text). OpenKey.mm is compiled with
// CGEventTapPostEvent replaced by Posted() below, which writes what is posted into a model of the text of an application.
// No key reaches the system.
//
// The expected texts hold Vietnamese letters, so this file is UTF-8 (MSVC would need /utf-8, it only builds on macOS).
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#include <string>
#import "AppDelegate.h"
#import "OpenKeyManager.h"
#import <objc/runtime.h>
#import "AIAssistant.h"
#import "CaseBar.h"
#import "CaseBarPanel.h"
#import "AISettings.h"
#import "ShortcutConflicts.h"
#import "SnippetPalette.h"
#import "SuggestionController.h"
#import "ShortcutRecorder.h"
#import "WordRestore.h"
#import "Diagnostics.h"
#include <sys/stat.h>

//what the typing engine wants the application to define (AppDelegate.m does it in the app)
int vLanguage = 1;
int vInputType = 0;
int vFreeMark = 0;
int vCodeTable = 0;
int vSwitchKeyStatus = 0;
int vCheckSpelling = 0;
int vUseModernOrthography = 0;
int vQuickTelex = 0;
int vRestoreIfWrongSpelling = 0;
int vFixRecommendBrowser = 0;
int vUseMacro = 0;
int vUseMacroInEnglishMode = 0;
int vAutoCapsMacro = 0;
int vUseSmartSwitchKey = 0;
int vUpperCaseFirstChar = 0;
int vTempOffSpelling = 0;
int vAllowConsonantZFWJ = 0;
int vQuickStartConsonant = 0;
int vQuickEndConsonant = 0;
int vRememberCode = 0;
int vOtherLanguage = 0;
int vTempOffOpenKey = 0;
int vSendKeyStepByStep = 0;
int vFixChromiumBrowser = 0;
int vPerformLayoutCompat = 0;
int vShowIconOnDock = 0;

extern int convertToolHotKey;   //defined by the engine (ConvertTool.cpp)
extern "C" {
void RequestNewSession(void);
void OpenKeyInit(void);
CGEventRef OpenKeyCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon);
void CleanEventFlags(CGEventRef down, CGEventRef up, const char* what);
}

//AppDelegate: only what the event tap calls
AppDelegate* appDelegate;
static int gLanguageSwitches = 0;
static int gQuickConverts = 0;
@implementation AppDelegate
-(void)onImputMethodChanged:(BOOL)willNotify { gLanguageSwitches++; }
-(void)onQuickConvert { gQuickConverts++; }
-(void)refreshMenu {}
-(void)onCodeTableChanged:(int)index {}
@end
@implementation OpenKeyManager
+(void)reenableEventTap {}
@end

static int gAIToggles = 0;
static int gCaseBarToggles = 0;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

#pragma mark - The application's text

static std::u16string gText;

//OpenKey.mm calls this where it would call CGEventTapPostEvent: the application receives the key
extern "C" void Posted(CGEventTapProxy proxy, CGEventRef event) {
    if (CGEventGetType(event) != kCGEventKeyDown)
        return;
    int code = (int)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    UniChar buffer[32];
    UniCharCount length = 0;
    CGEventKeyboardGetUnicodeString(event, 32, &length, buffer);
    if (code == 51) { //backspace
        if (!gText.empty())
            gText.pop_back();
    } else if (length > 0 && buffer[0] != 0) {
        gText.append((const char16_t*)buffer, length);
    }
}

static int keyCodeOf(char c) {
    switch (c) {
        case 'a': return kVK_ANSI_A; case 'b': return kVK_ANSI_B; case 'c': return kVK_ANSI_C; case 'd': return kVK_ANSI_D;
        case 'e': return kVK_ANSI_E; case 'f': return kVK_ANSI_F; case 'g': return kVK_ANSI_G; case 'h': return kVK_ANSI_H;
        case 'i': return kVK_ANSI_I; case 'j': return kVK_ANSI_J; case 'k': return kVK_ANSI_K; case 'l': return kVK_ANSI_L;
        case 'm': return kVK_ANSI_M; case 'n': return kVK_ANSI_N; case 'o': return kVK_ANSI_O; case 'p': return kVK_ANSI_P;
        case 'q': return kVK_ANSI_Q; case 'r': return kVK_ANSI_R; case 's': return kVK_ANSI_S; case 't': return kVK_ANSI_T;
        case 'u': return kVK_ANSI_U; case 'v': return kVK_ANSI_V; case 'w': return kVK_ANSI_W; case 'x': return kVK_ANSI_X;
        case 'y': return kVK_ANSI_Y; case 'z': return kVK_ANSI_Z; case ' ': return kVK_Space; case ',': return kVK_ANSI_Comma;
    }
    return -1;
}

static std::string utf8(const std::u16string& text) {
    NSString* s = [NSString stringWithCharacters:(const unichar*)text.data() length:text.size()];
    return s.UTF8String ?: "";
}

#pragma mark - Keys as the system sends them

//a modifier key going down or up: the flags are what is held afterwards
static void sendFlags(int code, CGEventFlags flags) {
    CGEventRef event = CGEventCreate(NULL);
    CGEventSetType(event, kCGEventFlagsChanged);
    CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, code);
    CGEventSetFlags(event, flags);
    OpenKeyCallback(NULL, kCGEventFlagsChanged, event, NULL);
    CFRelease(event);
}

static const struct { CGEventFlags flag; int code; } kModifiers[] = {
    {kCGEventFlagMaskControl, kVK_Control}, {kCGEventFlagMaskAlternate, kVK_Option},
    {kCGEventFlagMaskCommand, kVK_Command}, {kCGEventFlagMaskShift, kVK_Shift},
};

//Sends a key to the event tap, after the modifiers in `flags` were pressed (unless pressModifiers is NO: the test does it)
//and before they are let go. Returns whether the application gets the key itself: the tap lets it through. A key that
//the tap lets through types its own character, a swallowed one is not typed (the tap has typed what it wanted).
static bool sendKey(int code, CGEventFlags flags, char typed, bool pressModifiers = true) {
    CGEventFlags held = 0;
    if (pressModifiers) {
        for (auto& m : kModifiers) {
            if (flags & m.flag) {
                held |= m.flag;
                sendFlags(m.code, held);
            }
        }
    }
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)code, true);
    CGEventSetFlags(down, flags);
    CGEventRef answer = OpenKeyCallback(NULL, kCGEventKeyDown, down, NULL);
    bool passed = answer != NULL;
    if (passed && typed != 0 && !(flags & (kCGEventFlagMaskCommand | kCGEventFlagMaskControl)))
        gText.push_back((char16_t)((flags & kCGEventFlagMaskAlternate) && typed == ' ' ? 0xA0 : typed)); //⌥Space is a no-break space
    CFRelease(down);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)code, false);
    CGEventSetFlags(up, flags);
    OpenKeyCallback(NULL, kCGEventKeyUp, up, NULL);
    CFRelease(up);
    if (pressModifiers) {
        for (int i = 3; i >= 0; i--) {
            if (held & kModifiers[i].flag) {
                held &= ~kModifiers[i].flag;
                sendFlags(kModifiers[i].code, held);
            }
        }
    }
    return passed;
}

static void typeKeys(const char* keys) {
    for (const char* p = keys; *p; p++) {
        bool upper = *p >= 'A' && *p <= 'Z';
        char lower = upper ? (char)(*p - 'A' + 'a') : *p;
        int code = keyCodeOf(lower);
        sendKey(code, upper ? kCGEventFlagMaskShift : 0, *p);
    }
}

//what the app does when typing was interrupted
static void newWord() {
    gText.clear();
    RequestNewSession();
}

static std::string typedText(const char* keys) {
    newWord();
    typeKeys(keys);
    return utf8(gText);
}

#define EXPECT(keys, expected) do { std::string got = typedText(keys); \
    if (got != expected) { printf("FAIL line %d: \"%s\" gave \"%s\", expected \"%s\"\n", __LINE__, keys, got.c_str(), expected); failures++; } } while (0)

#pragma mark - The tests

static void runTypingTests(const char* title) {
    printf("-- %s\n", title);

    // plain typing
    vRestoreIfWrongSpelling = 0;
    EXPECT("vieetj ", "việt ");
    EXPECT("xin chaof ", "xin chào ");
    EXPECT("Vieetj Nam ", "Việt Nam ");
    EXPECT("dduowngf ", "đường ");
    EXPECT("restore ", "rétỏe ");                 // the way it always was
    EXPECT("sos sao ", "só sao ");                // the key of the snippet shortcut is just a letter

    // a word that is over and not Vietnamese gets its keys back
    vRestoreIfWrongSpelling = 1;
    EXPECT("restore ", "restore ");
    EXPECT("Restore ", "Restore ");
    EXPECT("hello restore world ", "hello restore world ");
    EXPECT("vieetj ", "việt ");
    EXPECT("dduowngf ", "đường ");

    // by hand
    newWord();
    typeKeys("restore");
    CHECK(utf8(gText) == "rétỏe");
    bool passed = sendKey(kVK_Space, kCGEventFlagMaskAlternate, ' ');
    CHECK(!passed);                                 // the shortcut is taken by VOpenKey
    CHECK(utf8(gText) == "restore");
    typeKeys("d");
    CHECK(utf8(gText) == "restored");               // typed as it comes
    typeKeys(" chaof ");
    CHECK(utf8(gText) == "restored chào ");

    // by hand, nothing to give back: the key is the application's
    newWord();
    passed = sendKey(kVK_Space, kCGEventFlagMaskAlternate, ' ');
    CHECK(passed);
    newWord();
    typeKeys("vieetj ");
    passed = sendKey(kVK_Space, kCGEventFlagMaskAlternate, ' ');
    CHECK(passed);                                  // the word is over
    newWord();
    typeKeys("abc");
    passed = sendKey(kVK_Space, kCGEventFlagMaskAlternate, ' ');
    CHECK(passed);                                  // as typed

    // by hand, only in Vietnamese mode
    vLanguage = 0;
    newWord();
    typeKeys("restore");
    passed = sendKey(kVK_Space, kCGEventFlagMaskAlternate, ' ');
    CHECK(passed);
    vLanguage = 1;

    // the shortcut can be taken away
    int saved = vRestoreHotKey;
    vRestoreHotKey = VOK_SHORTCUT_NONE;
    newWord();
    typeKeys("restore");
    passed = sendKey(kVK_Space, kCGEventFlagMaskAlternate, ' ');
    CHECK(passed);
    vRestoreHotKey = saved;

    // another shortcut
    vRestoreHotKey = 0x76000209;                    // ⌥V: key 9 with ⌥
    newWord();
    typeKeys("restore");
    passed = sendKey(kVK_ANSI_V, kCGEventFlagMaskAlternate, 'v');
    CHECK(!passed && utf8(gText) == "restore");
    vRestoreHotKey = saved;

    // a shortcut of modifiers only, restores when they are let go
    vRestoreHotKey = (int)0xFE0009FEu;              // ⌃⇧
    newWord();
    typeKeys("restore");
    sendFlags(kVK_Control, kCGEventFlagMaskControl);
    sendFlags(kVK_Shift, kCGEventFlagMaskControl | kCGEventFlagMaskShift);
    CHECK(utf8(gText) == "rétỏe");                  // not yet
    sendFlags(kVK_Shift, kCGEventFlagMaskControl);
    CHECK(utf8(gText) == "restore");
    sendFlags(kVK_Control, 0);
    vRestoreHotKey = saved;
}

static void Spin(double seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

//The AI shortcut: the tap swallows it and asks the window to open (a second later on the main queue, not inside the callback).
//+[AIAssistant toggle] is replaced by a counter, so that no window opens.
static void runAITests() {
    printf("-- AI shortcut\n");
    Method toggle = class_getClassMethod([AIAssistant class], @selector(toggle));
    IMP original = method_setImplementation(toggle, imp_implementationWithBlock(^{ gAIToggles++; }));
    int savedSwitch = vSwitchKeyStatus;
    vAIEnabled = 1;
    vAIHotKey = VOK_AI_DEFAULT_HOTKEY;                       // ⌃⌥A
    gLanguageSwitches = 0;

    gAIToggles = 0;
    newWord();
    bool passed = sendKey(kVK_ANSI_A, kCGEventFlagMaskControl | kCGEventFlagMaskAlternate, 'a');
    CHECK(!passed);                                           // the key is taken
    CHECK(gAIToggles == 0);                                   // and the window is asked for later, not in the callback
    Spin(0.1);
    CHECK(gAIToggles == 1);
    CHECK(utf8(gText).empty());                               // nothing was typed

    //the key of the shortcut is a letter like any other: Vietnamese with many a's is typed as before
    gAIToggles = 0;
    CHECK(typedText("an ") == "an ");
    CHECK(typedText("aas ") == "ấ ");
    CHECK(typedText("xin chaof cacs banj ") == "xin chào các bạn ");
    CHECK(typedText("Anh ") == "Anh ");
    Spin(0.1);
    CHECK(gAIToggles == 0);

    //⌃⇧A is another shortcut of the applications: it opens nothing, and with ⌃⇧ as the switch it must not switch either
    vSwitchKeyStatus = (int)0xFE0009FEu;
    newWord();
    sendFlags(kVK_Control, kCGEventFlagMaskControl);
    sendFlags(kVK_Shift, kCGEventFlagMaskControl | kCGEventFlagMaskShift);
    passed = sendKey(kVK_ANSI_A, kCGEventFlagMaskControl | kCGEventFlagMaskShift, 'a', false);
    CHECK(passed);
    sendFlags(kVK_Shift, kCGEventFlagMaskControl);
    sendFlags(kVK_Control, 0);
    Spin(0.1);
    CHECK(gAIToggles == 0 && gLanguageSwitches == 0);
    vSwitchKeyStatus = savedSwitch;

    //switched off: the key is the application's
    vAIEnabled = 0;
    newWord();
    passed = sendKey(kVK_ANSI_A, kCGEventFlagMaskControl | kCGEventFlagMaskAlternate, 'a');
    CHECK(passed);
    Spin(0.1);
    CHECK(gAIToggles == 0);
    vAIEnabled = 1;

    //no shortcut
    vAIHotKey = VOK_SHORTCUT_NONE;
    passed = sendKey(kVK_ANSI_A, kCGEventFlagMaskControl | kCGEventFlagMaskAlternate, 'a');
    CHECK(passed);
    Spin(0.1);
    CHECK(gAIToggles == 0);

    //a shortcut of modifiers only opens it when they are let go
    vAIHotKey = (int)0xFE000AFEu;                             // ⌥⇧
    newWord();
    sendFlags(kVK_Option, kCGEventFlagMaskAlternate);
    sendFlags(kVK_Shift, kCGEventFlagMaskAlternate | kCGEventFlagMaskShift);
    Spin(0.1);
    CHECK(gAIToggles == 0);
    sendFlags(kVK_Shift, kCGEventFlagMaskAlternate);
    sendFlags(kVK_Option, 0);
    Spin(0.1);
    CHECK(gAIToggles == 1);
    vAIHotKey = VOK_AI_DEFAULT_HOTKEY;

    //no two things on one shortcut
    CHECK([VOKShortcutConflict(VOK_AI_DEFAULT_HOTKEY, VOKShortcutOwnerRestore) isEqualToString:@"Mở trợ lý AI"]);
    CHECK([VOKShortcutConflict(VOK_AI_DEFAULT_HOTKEY, VOKShortcutOwnerSwitch) isEqualToString:@"Mở trợ lý AI"]);
    CHECK(VOKShortcutConflict(VOK_AI_DEFAULT_HOTKEY, VOKShortcutOwnerAI) == nil);          // its own is not a conflict
    CHECK([VOKShortcutConflict(VOK_RESTORE_DEFAULT_HOTKEY, VOKShortcutOwnerAI) isEqualToString:@"Khôi phục từ đang gõ"]);
    CHECK([VOKShortcutConflict(VOK_SNIPPET_DEFAULT_HOTKEY, VOKShortcutOwnerAI) isEqualToString:@"Mở snippet"]);
    vAIEnabled = 0;
    CHECK(VOKShortcutConflict(VOK_AI_DEFAULT_HOTKEY, VOKShortcutOwnerRestore) == nil);     // off: it does not hold the keys
    vAIEnabled = 1;

    method_setImplementation(toggle, original);
}

//The list that changes the case of the selection: its shortcut, the keys it takes while it is up, the mouse that puts it away.
//+[CaseBar toggle] is replaced by a counter for the shortcut; the list itself is shown with a known text, and the paste goes to a
//stand-in.
static void runCaseBarTests() {
    printf("-- case bar\n");
    Method toggle = class_getClassMethod([CaseBar class], @selector(toggle));
    IMP original = method_setImplementation(toggle, imp_implementationWithBlock(^{ gCaseBarToggles++; }));
    vCaseBarHotKey = VOK_CASEBAR_DEFAULT_HOTKEY;             // ⌃⌥C
    vCaseBarAuto = 1;

    gCaseBarToggles = 0;
    newWord();
    bool passed = sendKey(kVK_ANSI_C, kCGEventFlagMaskControl | kCGEventFlagMaskAlternate, 'c');
    CHECK(!passed);                                           // taken
    CHECK(gCaseBarToggles == 0);                              // asked for later, not in the callback
    Spin(0.1);
    CHECK(gCaseBarToggles == 1);
    CHECK(utf8(gText).empty());

    //the key of the shortcut is a letter like any other
    gCaseBarToggles = 0;
    CHECK(typedText("chaof cacs ") == "chào các ");
    Spin(0.1);
    CHECK(gCaseBarToggles == 0);

    //no shortcut / modifiers only
    vCaseBarHotKey = VOK_SHORTCUT_NONE;
    passed = sendKey(kVK_ANSI_C, kCGEventFlagMaskControl | kCGEventFlagMaskAlternate, 'c');
    CHECK(passed);
    Spin(0.1);
    CHECK(gCaseBarToggles == 0);
    vCaseBarHotKey = (int)0xFE000AFEu;                        // ⌥⇧
    newWord();
    sendFlags(kVK_Option, kCGEventFlagMaskAlternate);
    sendFlags(kVK_Shift, kCGEventFlagMaskAlternate | kCGEventFlagMaskShift);
    sendFlags(kVK_Shift, kCGEventFlagMaskAlternate);
    sendFlags(kVK_Option, 0);
    Spin(0.1);
    CHECK(gCaseBarToggles == 1);
    vCaseBarHotKey = VOK_CASEBAR_DEFAULT_HOTKEY;

    //conflicts
    CHECK([VOKShortcutConflict(VOK_CASEBAR_DEFAULT_HOTKEY, VOKShortcutOwnerAI) isEqualToString:@"Đổi chữ hoa/thường"]);
    CHECK(VOKShortcutConflict(VOK_CASEBAR_DEFAULT_HOTKEY, VOKShortcutOwnerCaseBar) == nil);
    CHECK([VOKShortcutConflict(VOK_AI_DEFAULT_HOTKEY, VOKShortcutOwnerCaseBar) isEqualToString:@"Mở trợ lý AI"]);
    method_setImplementation(toggle, original);

    //with the list up, ⌥1 chooses, and the key is not the application's (nor its key up)
    __block NSString* pasted = nil;
    [CaseBar setTextInserter:^(NSString* text, NSRunningApplication* app) { pasted = text; }];
    NSRunningApplication* other = nil;
    for (NSRunningApplication* app in [NSWorkspace sharedWorkspace].runningApplications)
        if (app.processIdentifier != getpid() && app.activationPolicy == NSApplicationActivationPolicyRegular) { other = app; break; }
    newWord();
    passed = sendKey(kVK_ANSI_1, kCGEventFlagMaskAlternate, '1');
    CHECK(passed);                                            // no list: ⌥1 is the application's
    [CaseBar presentText:@"xin chào" application:other explicit:NO anchor:NSMakeRect(100, 100, 0, 18)];
    [[CaseBar panel] setFrameOrigin:NSMakePoint(-30000, -30000)];
    CHECK([CaseBar isVisible]);
    passed = sendKey(kVK_ANSI_1, kCGEventFlagMaskAlternate, '1');
    CHECK(!passed);
    CHECK([pasted isEqualToString:@"XIN CHÀO"]);
    CHECK(![CaseBar isVisible]);
    CHECK(utf8(gText).size() == 1);                           // only the one typed above: the swallowed ⌥1 typed nothing
    //typing goes on as before
    newWord();
    CHECK(typedText("aas ") == "ấ ");

    //a plain key puts the list away and is the application's; the mouse and the wheel put it away
    auto showList = ^{
        [CaseBar presentText:@"xin chào" application:other explicit:NO anchor:NSMakeRect(100, 100, 0, 18)];
        [[CaseBar panel] setFrameOrigin:NSMakePoint(-30000, -30000)];
    };
    showList();
    newWord();
    CHECK(typedText("an ") == "an ");
    CHECK(![CaseBar isVisible]);
    showList();
    CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointMake(10, 10), kCGMouseButtonLeft);
    OpenKeyCallback(NULL, kCGEventLeftMouseDown, down, NULL);
    CFRelease(down);
    CHECK(![CaseBar isVisible]);
    showList();
    CGEventRef scroll = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, -3);
    CGEventRef passedScroll = OpenKeyCallback(NULL, kCGEventScrollWheel, scroll, NULL);
    CHECK(passedScroll != NULL);                              // the wheel is never taken
    CFRelease(scroll);
    CHECK(![CaseBar isVisible]);
    CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, CGPointMake(10, 10), kCGMouseButtonLeft);
    CGEventRef passedUp = OpenKeyCallback(NULL, kCGEventLeftMouseUp, up, NULL);
    CHECK(passedUp != NULL);                                  // nor the mouse button
    CFRelease(up);
    [CaseBar hide];
    [CaseBar setTextInserter:nil];
}

static void runShortcutTests() {
    printf("-- shortcuts\n");
    vRestoreIfWrongSpelling = 0;
    int savedSwitch = vSwitchKeyStatus;

    // the switch is ⌃⇧, the snippets ⌃⌥S: ⌃⇧S (Save As) must not switch the language when the keys are let go
    vSwitchKeyStatus = (int)0xFE0009FEu;            // ⌃⇧
    gLanguageSwitches = 0;
    newWord();
    sendFlags(kVK_Control, kCGEventFlagMaskControl);
    sendFlags(kVK_Shift, kCGEventFlagMaskControl | kCGEventFlagMaskShift);
    bool passed = sendKey(kVK_ANSI_S, kCGEventFlagMaskControl | kCGEventFlagMaskShift, 's', false);
    CHECK(passed);
    sendFlags(kVK_Shift, kCGEventFlagMaskControl);
    sendFlags(kVK_Control, 0);
    CHECK(gLanguageSwitches == 0);

    // the same keys without the S do switch
    sendFlags(kVK_Control, kCGEventFlagMaskControl);
    sendFlags(kVK_Shift, kCGEventFlagMaskControl | kCGEventFlagMaskShift);
    sendFlags(kVK_Shift, kCGEventFlagMaskControl);
    sendFlags(kVK_Control, 0);
    CHECK(gLanguageSwitches == 1);
    vLanguage = 1;                                  // the stub does not flip it back like the app does

    // a switch that is a key: ⌃Space, and ⌥Space (restore) next to it does not switch
    vSwitchKeyStatus = 0x20000131;                  // ⌃Space
    gLanguageSwitches = 0;
    newWord();
    passed = sendKey(kVK_Space, kCGEventFlagMaskControl, ' ');
    CHECK(!passed && gLanguageSwitches == 1);
    vLanguage = 1;
    gLanguageSwitches = 0;
    typeKeys("restore");
    passed = sendKey(kVK_Space, kCGEventFlagMaskAlternate, ' ');
    CHECK(!passed && gLanguageSwitches == 0 && utf8(gText) == "restore");

    // the convert shortcut still works
    gQuickConverts = 0;
    int savedConvert = convertToolHotKey;
    convertToolHotKey = 0x7A000206 | 0x200;         // ⌥Z
    passed = sendKey(kVK_ANSI_Z, kCGEventFlagMaskAlternate, 'z');
    CHECK(!passed && gQuickConverts == 1);
    convertToolHotKey = savedConvert;

    vSwitchKeyStatus = savedSwitch;
}


#pragma mark - The diagnostics log

static NSString* ReadLog(NSString* dir) {
    [VOKDiagnostics flush];
    return [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"diagnostics.log"] encoding:NSUTF8StringEncoding error:nil] ?: @"";
}

static BOOL Has(NSString* text, NSString* needle) {
    return [text containsString:needle];
}

static NSUInteger Count(NSString* text, NSString* needle) {
    return [text componentsSeparatedByString:needle].count - 1;
}

static void runDiagnosticsTests() {
    printf("-- diagnostics log\n");
    NSFileManager* fm = [NSFileManager defaultManager];
    NSString* base = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"vok-diag-test-%d", getpid()]];
    [fm removeItemAtPath:base error:nil];

    // switched off: nothing is made, nothing is written
    NSString* offDir = [base stringByAppendingPathComponent:@"off"];
    [VOKDiagnostics startWithDirectory:offDir enabled:NO maxFileBytes:1 << 20 watchdogInterval:0.2 stallThreshold:1.0];
    CHECK(![VOKDiagnostics isOn] && vDiagnostics == 0);
    VOKDiag(@"test", @"this must not be written");
    [VOKDiagnostics flush];
    CHECK(![fm fileExistsAtPath:offDir]);
    EXPECT("vieetj ", "việt ");                      // typing does not depend on it

    // switched on
    NSString* dir = [base stringByAppendingPathComponent:@"on"];
    [VOKDiagnostics startWithDirectory:dir enabled:YES maxFileBytes:1 << 20 watchdogInterval:0.2 stallThreshold:1.0];
    CHECK([VOKDiagnostics isOn] && vDiagnostics == 1);
    struct stat info;
    CHECK(stat([dir stringByAppendingPathComponent:@"diagnostics.log"].fileSystemRepresentation, &info) == 0 && (info.st_mode & 0777) == 0600);
    CHECK(stat(dir.fileSystemRepresentation, &info) == 0 && (info.st_mode & 0777) == 0700);
    Spin(0.3);

    // typing, with the invisible character of the fix for browsers: written down, but never what was typed
    vFixRecommendBrowser = 1;
    EXPECT("dduowngf ", "đường ");
    EXPECT("xin chaof ", "xin chào ");
    EXPECT("Vieetj Nam ", "Việt Nam ");
    vFixRecommendBrowser = 0;
    NSString* log = ReadLog(dir);
    CHECK(Has(log, @"[start] ---- VOpenKey AI"));
    CHECK(Has(log, @"[state] front="));
    CHECK(Has(log, @"[inject] engine code="));
    CHECK(Has(log, @"emptyChar=1"));
    for (NSString* typed in @[@"đường", @"duong", @"dduowngf", @"chào", @"chao", @"chaof", @"Việt", @"vieetj", @"Vieetj"])
        CHECK(!Has(log, typed));
    // typing as usual is not an anomaly. Three things depend on the machine this runs on and are left out: macOS' own Vietnamese
    // input source being selected (then the log must say so), a callback that took 20 ms because the window list was slow, and a
    // busy machine that kept this thread from its heartbeat for a second (the stall test below shows that one is noticed)
    BOOL macVietnameseSelected = [[VOKDiagnostics currentInputSourceID] hasPrefix:@"com.apple.inputmethod.VietnameseIM"];
    for (NSString* line in [log componentsSeparatedByString:@"\n"]) {
        if ([line containsString:@"[ANOMALY]"] && ![line containsString:@"DOUBLE CONVERSION"] && ![line containsString:@"SLOW CALLBACK"] &&
            ![line containsString:@"MAIN THREAD STALL"]) {
            printf("FAIL: an anomaly while typing normally: %s\n", line.UTF8String);
            failures++;
        }
    }
    CHECK(Has(log, @"DOUBLE CONVERSION") == macVietnameseSelected);

    // modifier flags that stuck to the events of the typing source are cleared and written down
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, 0, true), up = CGEventCreateKeyboardEvent(NULL, 0, false);
    CGEventSetFlags(down, kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate | kCGEventFlagMaskNonCoalesced);
    CGEventSetFlags(up, kCGEventFlagMaskCommand);
    CleanEventFlags(down, up, "text");
    CHECK((CGEventGetFlags(down) & (kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate)) == 0);
    CHECK((CGEventGetFlags(down) & kCGEventFlagMaskNonCoalesced) != 0);
    CHECK((CGEventGetFlags(up) & kCGEventFlagMaskCommand) == 0);
    CFRelease(down);
    CFRelease(up);
    CHECK(Has(ReadLog(dir), @"[ANOMALY] FLAGS: a text event of the typing source carried modifier flags"));

    // a main thread that does not answer is noticed, and so is its return
    usleep(1700000);
    Spin(0.6);
    log = ReadLog(dir);
    CHECK(Has(log, @"[ANOMALY] MAIN THREAD STALL"));
    CHECK(Has(log, @"[stall] main thread answering again"));

    // an event tap that macOS switched off is noticed, and so is its return
    __block NSInteger tapState = 1;
    [VOKDiagnostics setTapEnabledCheck:^NSInteger{ return tapState; }];
    Spin(0.5);
    tapState = 0;
    Spin(0.6);
    tapState = 1;
    Spin(0.6);
    log = ReadLog(dir);
    CHECK(Has(log, @"[tap] TAP enabled"));
    CHECK(Has(log, @"[ANOMALY] TAP DISABLED"));
    CHECK(Has(log, @"[tap] TAP enabled again"));

    // what was posted against what reached the end of the event chain (not while another app holds secure input: no tap sees keys then)
    if (IsSecureEventInputEnabled()) {
        printf("   (secure input is on: the delivery check is skipped)\n");
    } else {
        [VOKDiagnostics setWatchedSource:42];
        [VOKDiagnostics resetDeliveryCounters];         // what the typing above posted has no listener here to arrive at
        [VOKDiagnostics countPosted:VOKEventKindText pairs:4];
        [VOKDiagnostics countPosted:VOKEventKindBackspace pairs:3];
        [VOKDiagnostics countPosted:VOKEventKindEmptyChar pairs:2];
        for (int i = 0; i < 4; i++) [VOKDiagnostics countArrived:VOKEventKindText down:YES];
        for (int i = 0; i < 3; i++) [VOKDiagnostics countArrived:VOKEventKindText down:NO];
        for (int i = 0; i < 3; i++) { [VOKDiagnostics countArrived:VOKEventKindBackspace down:YES]; [VOKDiagnostics countArrived:VOKEventKindBackspace down:NO]; }
        for (int i = 0; i < 2; i++) [VOKDiagnostics countArrived:VOKEventKindEmptyChar down:NO];
        Spin(2.0);
        log = ReadLog(dir);
        CHECK(Has(log, @"backspace down 3/3 up 3/3; empty-char down 0/2 up 2/2; text down 4/4 up 3/4;"));
        CHECK(Has(log, @"[ANOMALY] DELIVERY"));
        CHECK(Has(log, @"text key downs 4 of 4, key ups 3 of 4"));
        CHECK(!Has(log, @"backspace key downs"));
        CHECK(!Has(log, @"empty-char key downs"));      // the invisible character is not counted as a loss
        NSUInteger anomalies = Count(log, @"[ANOMALY] DELIVERY");
        // a later burst where only the invisible character goes missing: reported, but not as an anomaly
        [VOKDiagnostics countPosted:VOKEventKindEmptyChar pairs:3];
        Spin(4.0);
        log = ReadLog(dir);
        CHECK(Has(log, @"empty-char down 0/3 up 0/3"));
        CHECK(Count(log, @"[ANOMALY] DELIVERY") == anomalies);
        [VOKDiagnostics setWatchedSource:0];
    }
    [VOKDiagnostics stop];
    CHECK(vDiagnostics == 0);

    // the file stays small: it is replaced by a new one at the limit and the one before is kept
    NSString* rotDir = [base stringByAppendingPathComponent:@"rotate"];
    [VOKDiagnostics startWithDirectory:rotDir enabled:YES maxFileBytes:3000 watchdogInterval:0.5 stallThreshold:1.0];
    for (int i = 0; i < 200; i++)
        VOKDiag(@"test", @"line %d to fill the file up to its limit, nothing else", i);
    [VOKDiagnostics flush];
    struct stat now, before;
    CHECK(stat([rotDir stringByAppendingPathComponent:@"diagnostics.log"].fileSystemRepresentation, &now) == 0 && now.st_size <= 3000);
    CHECK(stat([rotDir stringByAppendingPathComponent:@"diagnostics.1.log"].fileSystemRepresentation, &before) == 0 && before.st_size <= 3000);
    NSString* latest = ReadLog(rotDir);
    CHECK(Has(latest, @"line 199 to fill"));
    [VOKDiagnostics stop];

    [fm removeItemAtPath:base error:nil];
}

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        appDelegate = [[AppDelegate alloc] init];
        OpenKeyInit();
        //the settings of a fresh app, set after OpenKeyInit() read the saved ones
        vLanguage = 1;
        vInputType = 0;
        vCodeTable = 0;
        vCheckSpelling = 0;
        vUseMacro = 0;
        vSuggestEnabled = 0;
        vSwitchKeyStatus = 0x7A000206;
        vSnippetsEnabled = 1;
        vSnippetHotKey = VOK_SNIPPET_DEFAULT_HOTKEY;
        vRestoreHotKey = VOK_RESTORE_DEFAULT_HOTKEY;
        vAIEnabled = 1;
        vAIHotKey = VOK_AI_DEFAULT_HOTKEY;
        vCaseBarHotKey = VOK_CASEBAR_DEFAULT_HOTKEY;
        vCaseBarAuto = 1;

        vFixRecommendBrowser = 0;
        runTypingTests("typing");
        vFixRecommendBrowser = 1;                   // browsers: a no-break character is typed first and deleted
        runTypingTests("typing, with the fix for suggestions of browsers");
        vFixRecommendBrowser = 0;
        runShortcutTests();
        runAITests();
        runCaseBarTests();
        runDiagnosticsTests();

        printf(failures ? "\n%d FAILURES\n" : "ALL OK\n", failures);
    }
    return failures ? 1 : 0;
}
