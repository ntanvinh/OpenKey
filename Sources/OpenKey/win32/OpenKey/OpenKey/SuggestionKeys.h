//
//  SuggestionKeys.h
//  VOpenKey AI, Windows
//
//  Which keys choose a suggestion of the bar. Pure functions on plain numbers (no Windows headers), so that they can be
//  tested without the keyboard hook.
//
//      Tab        the first suggestion (when the user allows it, which is the default)
//      Alt+1..5   suggestion 1 to 5
//      Esc        hides the bar and goes to the application: the way to type a real Tab (Alt+Tab belongs to Windows)
//      anything else goes to the application as always
//

#pragma once

namespace vsuggestkeys {

//virtual key codes of Windows
enum {
    kTab = 0x09,
    kEscape = 0x1B,
    kDigit1 = 0x31,
    kDigit5 = 0x35
};

struct Modifiers {
    bool shift;
    bool control;
    bool alt;
    bool win;
};

/// The suggestion a key chooses: 0 for the first one, 4 for the fifth, -1 when the key chooses none.
inline int slotForKey(unsigned virtualKey, const Modifiers& m, bool tabChoosesFirst) {
    if (m.control || m.shift || m.win)
        return -1; //Shift+Tab goes back to the previous field, shortcuts are not ours
    if (virtualKey == kTab)
        return (!m.alt && tabChoosesFirst) ? 0 : -1;
    if (!m.alt)
        return -1;
    if (virtualKey >= kDigit1 && virtualKey <= kDigit5)
        return (int)(virtualKey - kDigit1);
    return -1;
}

} // namespace vsuggestkeys
