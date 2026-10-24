//
//  FeatureWindows.h
//  VOpenKey AI, Windows
//
//  The windows of the features that are made in code (not from a dialog resource) take part in the message loop here, so
//  that Tab moves between their controls and Enter and Esc press the default and the cancel button, like in a dialog.
//
#pragma once
#include "stdafx.h"

namespace FeatureWindows {

/// A window whose messages go through IsDialogMessage while it is visible. Call once when the window is made.
void registerDialog(HWND window);
void unregisterDialog(HWND window);

/// For the message loop: true when the message was taken by one of them.
bool handleDialogMessage(MSG& msg);

} // namespace FeatureWindows
