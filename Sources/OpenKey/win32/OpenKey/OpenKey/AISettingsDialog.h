//
//  AISettingsDialog.h
//  VOpenKey AI, Windows
//
//  The settings of the AI assistant: which service, its address, its model, the API key (kept encrypted for this Windows
//  account), the instruction given with every request and the shortcut. A window made in code.
//
#pragma once
#include "stdafx.h"

namespace AISettingsDialog {

void show();
bool isVisible();

/// A shortcut field of this window has the keyboard: the keyboard hook leaves every key alone (see FeaturesDialog).
bool isRecordingShortcut();

} // namespace AISettingsDialog
