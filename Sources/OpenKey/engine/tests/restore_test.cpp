// Tests of restoring words that are not Vietnamese ("restore" typed in Telex is "rétỏe"), by themselves when the word is
// over and by hand with vRestoreWord(). Drives the real typing engine key by key and applies what it answers to a model
// of the text on screen, the way the apps do.
//
//   clang++ -std=c++11 -I.. restore_test.cpp ../Engine.cpp ../Vietnamese.cpp ../Macro.cpp ../SmartSwitchKey.cpp \
//       ../ConvertTool.cpp -o /tmp/restore_test && /tmp/restore_test
//
// The expected texts hold Vietnamese letters, so this file is UTF-8 (MSVC needs /utf-8).
#include "Engine.h"
#include <cstdio>
#include <string>
#include <vector>

//what the engine wants the application to define
int vLanguage = 1;
int vInputType = 0;       //Telex
int vFreeMark = 0;
int vCodeTable = 0;       //Unicode
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

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

static vKeyHookState* hook;
static std::u16string screen;

static int keyCodeOf(char c) {
    switch (c) {
        case 'a': return KEY_A; case 'b': return KEY_B; case 'c': return KEY_C; case 'd': return KEY_D; case 'e': return KEY_E;
        case 'f': return KEY_F; case 'g': return KEY_G; case 'h': return KEY_H; case 'i': return KEY_I; case 'j': return KEY_J;
        case 'k': return KEY_K; case 'l': return KEY_L; case 'm': return KEY_M; case 'n': return KEY_N; case 'o': return KEY_O;
        case 'p': return KEY_P; case 'q': return KEY_Q; case 'r': return KEY_R; case 's': return KEY_S; case 't': return KEY_T;
        case 'u': return KEY_U; case 'v': return KEY_V; case 'w': return KEY_W; case 'x': return KEY_X; case 'y': return KEY_Y;
        case 'z': return KEY_Z; case ' ': return KEY_SPACE; case ',': return KEY_COMMA; case '.': return KEY_DOT;
    }
    return -1;
}

static char16_t characterOf(Uint32 data) {
    Uint32 code = getCharacterCode(data);
    if ((code & PURE_CHARACTER_MASK) || (code & CHAR_CODE_MASK))
        return (char16_t)code;
    return (char16_t)keyCodeToCharacter(code);
}

//applies the answer of the engine to the screen, like OpenKey.mm does
static void apply(const vKeyHookState& answer, char typed) {
    switch (answer.code) {
        case vDoNothing:
            screen += (char16_t)typed;
            break;
        case vWillProcess:
        case vRestore:
        case vRestoreAndStartNewSession: {
            size_t erase = answer.backspaceCount;
            screen.erase(screen.size() >= erase ? screen.size() - erase : 0);
            for (int i = answer.newCharCount - 1; i >= 0; i--)
                screen += characterOf(answer.charData[i]);
            if (answer.code != vWillProcess)
                screen += (char16_t)typed; //the key that ended the word is typed again after it
            break;
        }
        default:
            break;
    }
}

static void press(char c) {
    bool upper = c >= 'A' && c <= 'Z';
    char lower = upper ? (char)(c - 'A' + 'a') : c;
    int code = keyCodeOf(lower);
    if (code < 0) {
        printf("no key for '%c'\n", c);
        failures++;
        return;
    }
    vKeyHandleEvent(vKeyEvent::Keyboard, vKeyEventState::KeyDown, (Uint16)code, upper ? 1 : 0, false);
    apply(*hook, c);
}

//what the app does when typing was interrupted (RequestNewSession): the word is over, whatever it was
static void newWord() {
    screen.clear();
    vKeyHandleEvent(vKeyEvent::Mouse, vKeyEventState::MouseDown, 0);
}

static void type(const char* keys) {
    for (const char* p = keys; *p; p++)
        press(*p);
}

//what the user sees after typing `keys`, as UTF-8
static std::string utf8(const std::u16string& text) {
    std::string out;
    for (char16_t c : text) {
        if (c < 0x80) {
            out += (char)c;
        } else if (c < 0x800) {
            out += (char)(0xC0 | (c >> 6));
            out += (char)(0x80 | (c & 0x3F));
        } else {
            out += (char)(0xE0 | (c >> 12));
            out += (char)(0x80 | ((c >> 6) & 0x3F));
            out += (char)(0x80 | (c & 0x3F));
        }
    }
    return out;
}

static std::string typed(const char* keys, int restore, int spelling) {
    vRestoreIfWrongSpelling = restore;
    vCheckSpelling = spelling;
    vSetCheckSpelling();
    newWord();
    type(keys);
    return utf8(screen);
}

#define EXPECT(keys, restore, spelling, expected) do { \
    std::string got = typed(keys, restore, spelling); \
    if (got != expected) { printf("FAIL line %d: \"%s\" (restore %d, spelling %d) gave \"%s\", expected \"%s\"\n", __LINE__, keys, restore, spelling, got.c_str(), expected); failures++; } \
} while (0)

int main() {
    hook = (vKeyHookState*)vKeyInit();

    // 1. as it always was: nothing is restored when the option is off
    EXPECT("restore ", 0, 0, "rétỏe ");

    // 2. a word that is over and not Vietnamese gets its keys back, with spell checking off as well as on
    EXPECT("restore ", 1, 0, "restore ");
    EXPECT("restore ", 1, 1, "restore ");
    EXPECT("Restore ", 1, 0, "Restore ");
    EXPECT("restore,", 1, 0, "restore,");               // any end of word, not only a space
    EXPECT("text ", 1, 0, "text ");                      // x is a tilde: "tẽt" is not a word
    EXPECT("hello restore world ", 1, 0, "hello restore world ");

    // 3. Vietnamese is left alone
    EXPECT("vieetj ", 1, 0, "việt ");
    EXPECT("tieengs ", 1, 0, "tiếng ");
    EXPECT("xin chaof ", 1, 0, "xin chào ");
    EXPECT("dduowngf ", 1, 0, "đường ");
    EXPECT("nguwowif ", 1, 0, "người ");
    EXPECT("Vieetj Nam ", 1, 0, "Việt Nam ");
    EXPECT("toois ", 1, 0, "tối ");
    EXPECT("hoaf ", 1, 0, "hòa ");                       // the old way of placing the accent: hòa, not hoà
    EXPECT("ddi ", 1, 0, "đi ");                  // only a stroke: it is Vietnamese
    EXPECT("test ", 1, 0, "tét ");                  // a real Vietnamese word, it cannot be told apart

    // 4. a word without any accent has nothing to give back
    EXPECT("hello ", 1, 0, "hello ");

    // 5. by hand: the word being typed
    vRestoreIfWrongSpelling = 0;
    vCheckSpelling = 0;
    newWord();
    type("restore");
    CHECK(utf8(screen) == "rétỏe");
    CHECK(vRestoreWord());
    apply(*hook, 0);
    CHECK(utf8(screen) == "restore");
    CHECK(!vRestoreWord());                                // nothing more to give back
    type("d");                                             // the rest of the word is typed as it comes
    CHECK(utf8(screen) == "restored");
    type("s");                                             // not a sac accent on a Vietnamese word
    CHECK(utf8(screen) == "restoreds");
    type(" ");
    CHECK(utf8(screen) == "restoreds ");
    type("chaof ");                                        // the next word is Vietnamese again
    CHECK(utf8(screen) == "restoreds chào ");

    // 6. by hand, capital letters are kept
    newWord();
    type("Vieetj");
    CHECK(utf8(screen) == "Việt");
    CHECK(vRestoreWord());
    apply(*hook, 0);
    CHECK(utf8(screen) == "Vieetj");

    // 7. by hand, only for a word that is being typed
    newWord();
    CHECK(!vRestoreWord());                                // nothing typed
    type("vieetj ");
    CHECK(!vRestoreWord());                                // the word is over
    type("abc");
    CHECK(!vRestoreWord());                                // as typed
    type(",");
    CHECK(!vRestoreWord());

    // 8. by hand, a stroke and a modifier of a vowel are given back too
    newWord();
    type("dd");
    CHECK(utf8(screen) == "đ");
    CHECK(vRestoreWord());
    apply(*hook, 0);
    CHECK(utf8(screen) == "dd");
    newWord();
    type("w");                                             // "w" alone is a u with a horn in Telex
    CHECK(utf8(screen) == "ư");
    CHECK(vRestoreWord());
    apply(*hook, 0);
    CHECK(utf8(screen) == "w");

    // 9. by hand and then automatically: the same word is not restored twice
    vRestoreIfWrongSpelling = 1;
    newWord();
    type("restore");
    CHECK(vRestoreWord());
    apply(*hook, 0);
    type(" ");
    CHECK(utf8(screen) == "restore ");

    printf(failures ? "\n%d FAILURES\n" : "ALL OK\n", failures);
    return failures ? 1 : 0;
}
