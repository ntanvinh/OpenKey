//
//  SuggestionOptionsDialog.h
//  VOpenKey AI, Windows
//
//  The window of the suggestion bar's look and of the programs it stays away from: two sliders for how see-through the bar is
//  (normally, and while the pointer is on it) and the list of programs where there is no bar (terminals), which the user can
//  edit. The same options as on macOS (Settings > Suggestions). Every change takes effect and is saved as it is made.
//
#pragma once
#include "stdafx.h"

namespace SuggestionOptionsDialog {

/// Opens the window (or brings it to the front).
void show();
bool isVisible();

} // namespace SuggestionOptionsDialog
