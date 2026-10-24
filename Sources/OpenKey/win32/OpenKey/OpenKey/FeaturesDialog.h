//
//  FeaturesDialog.h
//  VOpenKey AI, Windows
//
//  The settings of what VOpenKey AI added to OpenKey: suggestions while typing, snippets, the shortcuts of the case list and
//  of the word restore. It is made in code (not from a dialog resource), a window that is as tall as its content.
//
#pragma once
#include "stdafx.h"

namespace FeaturesDialog {

/// Opens the window, or brings it to the front.
void show();
bool isVisible();

/// True while a shortcut field has the keyboard: the keyboard hook then leaves every key alone, so that the user can press a
/// shortcut that the program itself uses (Ctrl+Alt+S) to set it.
bool isRecordingShortcut();

} // namespace FeaturesDialog
