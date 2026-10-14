//
//  SuggestionKeys.h
//  VOpenKey
//
//  Which keys choose a suggestion of the bar. Pure functions, so that they can be tested without the event tap.
//
//      Tab                 the first suggestion (when the user allows it, which is the default)
//      ⌥1 to ⌥5            suggestion 1 to 5
//      ⌥Tab                an ordinary Tab, for going on to the next field of a form while the bar is up: the key
//                          is turned into a plain Tab on its way, nothing more
//      anything else       goes to the application as always
//

#ifndef SuggestionKeys_h
#define SuggestionKeys_h

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

//key codes of macOS (the typing engine calls them KEY_TAB, KEY_1...)
enum {
    kSuggestionKeyTab = 48,
    kSuggestionKey1 = 18,
    kSuggestionKey2 = 19,
    kSuggestionKey3 = 20,
    kSuggestionKey4 = 21,
    kSuggestionKey5 = 23
};

/// ⌥Tab with nothing else held down.
static inline bool SuggestionIsOptionTab(CGKeyCode keycode, CGEventFlags flags) {
    const CGEventFlags others = kCGEventFlagMaskCommand | kCGEventFlagMaskControl | kCGEventFlagMaskShift;
    return keycode == kSuggestionKeyTab && (flags & kCGEventFlagMaskAlternate) && !(flags & others);
}

/// Takes the Option off a key event, so that ⌥Tab goes on as an ordinary Tab (the key code and the other flags stay).
/// Returns the flags the event has now.
static inline CGEventFlags SuggestionTakeOptionOff(CGEventRef event) {
    CGEventFlags flags = CGEventGetFlags(event) & ~kCGEventFlagMaskAlternate;
    CGEventSetFlags(event, flags);
    return flags;
}

/// The suggestion a key chooses: 0 for the first one, 4 for the fifth, -1 when the key chooses none.
static inline int SuggestionSlotForKey(CGKeyCode keycode, CGEventFlags flags, bool tabChoosesFirst) {
    if (flags & (kCGEventFlagMaskCommand | kCGEventFlagMaskControl | kCGEventFlagMaskShift))
        return -1; //⇧Tab goes back to the previous field, shortcuts are not ours
    bool option = flags & kCGEventFlagMaskAlternate;
    if (keycode == kSuggestionKeyTab)
        return (!option && tabChoosesFirst) ? 0 : -1;
    if (!option)
        return -1;
    switch (keycode) {
        case kSuggestionKey1: return 0;
        case kSuggestionKey2: return 1;
        case kSuggestionKey3: return 2;
        case kSuggestionKey4: return 3;
        case kSuggestionKey5: return 4;
    }
    return -1;
}

#endif /* SuggestionKeys_h */
