//
//  ShortcutField.h
//  VOpenKey AI, Windows
//
//  A read-only text box that records a shortcut: the user focuses it and presses the keys. Used by the settings windows of the
//  features. The shortcut is the number of OpenKey (see FeatureActions.h) and is saved in the registry as soon as it is set.
//
#pragma once
#include "stdafx.h"

namespace ShortcutField {

/// Makes `field` (an EDIT control) record the shortcut `variable`, saved under `registryName`. `message` receives what to tell
/// the user ("Phím này đang dùng để ...", "" to clear it).
void attach(HWND field, int* variable, const wchar_t* registryName, void (*message)(const std::wstring& text));

/// Shows the shortcut of every attached field again (after a reset).
void refresh();

/// True while one of the fields has the keyboard: the keyboard hook then leaves every key alone, so that the user can press a
/// shortcut that the program itself uses (Ctrl+Alt+S) to set it.
bool isRecording();

} // namespace ShortcutField
