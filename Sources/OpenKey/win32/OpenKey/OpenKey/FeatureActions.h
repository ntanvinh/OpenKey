//
//  FeatureActions.h
//  VOpenKey AI, Windows
//
//  What the shortcuts, the tray menu and the settings of the VOpenKey AI features can do, and the shortcuts themselves.
//  The keyboard hook (OpenKey.cpp) asks here which shortcut was pressed; the work is done from the message loop, never
//  inside the hook, which must answer fast.
//
//  A shortcut is a number as in OpenKey: the key code in the low byte, 0x100 Ctrl, 0x200 Alt, 0x400 Windows, 0x800 Shift;
//  key 0xFE means "no key" (only modifiers), 0xFE0000FE is "no shortcut".
//
#pragma once
#include "stdafx.h"

extern int vRestoreHotKey;       //give back the keys of the word being typed
extern int vAIHotKey;            //open the AI assistant
extern int vAIEnabled;

#define VOK_SHORTCUT_NONE 0xFE0000FE

namespace FeatureActions {

enum Action {
    None = 0,
    OpenSnippets = 1,
    ToggleCaseBar = 2,
    RestoreWord = 3,
    OpenAIAssistant = 4,
    OpenSnippetEditor = 5,
    OpenFeatureSettings = 6,
    OpenAISettings = 7
};

struct HotKey {
    int* shortcut;      //the number above
    const int* enabled; //NULL: always on
    Action action;
    const wchar_t* name; //what it is called in a message about a conflict
};

/// The shortcuts of the features, for the hook to look at on every key.
const std::vector<HotKey>& hotKeys();

/// The window that receives the actions: made at the start of the program, independent of the other features.
bool start(HINSTANCE instance);
void stop();

/// Asks for the action to be done in the message loop (safe to call from the hook). False when it cannot be asked: then the
/// shortcut must not be taken from the program.
bool post(Action action);

/// The same a moment later: for the tray menu, which gives the keyboard back to the program only when it is gone.
bool postDelayed(Action action, unsigned milliseconds);

/// Does it now. Call from the message loop only.
void run(Action action);

/// The restore of the word being typed needs the keyboard hook's own state, so the hook gives it here. It returns false when
/// there is nothing to restore (then the key goes on to the program).
void setRestoreHandler(bool (*handler)());
bool restoreWord();

/// Reads and saves the settings of the features (registry, same place as the other settings of OpenKey).
void loadSettings();
void saveHotKey(int* variable, const wchar_t* registryName, int value);

/// "Ctrl + Alt + S" for a shortcut, "Chưa đặt" for none.
std::wstring describeShortcut(int shortcut);

/// What already uses `shortcut` (the name of it), empty when it is free. `ownVariable` is the shortcut being set: it does not
/// conflict with itself.
std::wstring conflictOf(int shortcut, const int* ownVariable);

} // namespace FeatureActions
