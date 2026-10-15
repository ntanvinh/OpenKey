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
#import "AISettings.h"
#import "ShortcutConflicts.h"
#import "SnippetPalette.h"
#import "SuggestionController.h"
#import "ShortcutRecorder.h"
#import "WordRestore.h"

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

        vFixRecommendBrowser = 0;
        runTypingTests("typing");
        vFixRecommendBrowser = 1;                   // browsers: a no-break character is typed first and deleted
        runTypingTests("typing, with the fix for suggestions of browsers");
        vFixRecommendBrowser = 0;
        runShortcutTests();
        runAITests();

        printf(failures ? "\n%d FAILURES\n" : "ALL OK\n", failures);
    }
    return failures ? 1 : 0;
}
