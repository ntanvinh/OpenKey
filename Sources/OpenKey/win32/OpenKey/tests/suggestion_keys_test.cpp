// Runs on any platform: clang++ -std=c++11 -I../OpenKey suggestion_keys_test.cpp && ./a.out
#include <cstdio>
#include "SuggestionKeys.h"

using namespace vsuggestkeys;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main() {
    Modifiers none = {false, false, false, false};
    Modifiers alt = {false, false, true, false};
    Modifiers shift = {true, false, false, false};
    Modifiers ctrl = {false, true, false, false};
    Modifiers altShift = {true, false, true, false};
    Modifiers win = {false, false, false, true};

    CHECK(slotForKey(kTab, none, true) == 0);
    CHECK(slotForKey(kTab, none, false) == -1);      //Tab turned off by the user
    CHECK(slotForKey(kTab, shift, true) == -1);      //Shift+Tab: previous field
    CHECK(slotForKey(kTab, alt, true) == -1);        //Alt+Tab is Windows' own
    CHECK(slotForKey(kTab, ctrl, true) == -1);       //Ctrl+Tab: next tab of the application
    for (unsigned i = 0; i < 5; i++) {
        CHECK(slotForKey(kDigit1 + i, alt, true) == (int)i);
        CHECK(slotForKey(kDigit1 + i, alt, false) == (int)i);
        CHECK(slotForKey(kDigit1 + i, none, true) == -1);   //a plain digit is a digit
        CHECK(slotForKey(kDigit1 + i, altShift, true) == -1);
        CHECK(slotForKey(kDigit1 + i, win, true) == -1);
    }
    CHECK(slotForKey(kDigit5 + 1, alt, true) == -1);  //Alt+6
    CHECK(slotForKey(0x30, alt, true) == -1);         //Alt+0
    CHECK(slotForKey(kEscape, none, true) == -1);

    if (failures == 0)
        printf("suggestion_keys_test: all passed\n");
    return failures == 0 ? 0 : 1;
}
