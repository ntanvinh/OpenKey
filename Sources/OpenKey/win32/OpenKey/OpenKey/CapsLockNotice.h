//
//  CapsLockNotice.h
//  VOpenKey AI, Windows
//
//  What the person sees when Caps Lock is switched: the tray icon turns red (a copy of the usual icon is made here) and a small
//  message, "Caps Lock đang bật" or "Caps Lock đã tắt", comes up near the bottom of the screen for a moment. The message is a window
//  of its own that never takes the focus, and it follows the colours of Windows (light or dark) like the other windows of the features.
//  Detecting the change is the job of the tray window (SystemTrayHelper): it asks `isOn` from a timer.
//
#pragma once
#include "stdafx.h"

/// The setting "Thông báo khi bật/tắt Caps Lock" (Bảng điều khiển > Hệ thống), on unless it is 0. It switches the message off; the tray icon
/// is red while Caps Lock is on either way. Saved in the registry as vCapsLockToast; FeatureActions::loadSettings reads it.
extern int vCapsLockToast;

namespace CapsLockNotice {

/// Caps Lock is on now (the state the keyboard has, not a count of key presses).
bool isOn();

/// The icon of the time Caps Lock is on, at the size of `base` (an icon of the tray); NULL when it cannot be made. English: a red tile with
/// the letter of `base` in white. Vietnamese: the flag of Vietnam, a red tile with a yellow star in the middle. The caller keeps it and
/// gives it back with DestroyIcon.
HICON makeRedIcon(HICON base, bool vietnamese);

/// The message for the new state; one that is still there is changed and stays for the full time again.
void showToast(bool on);

/// Takes the message away at once (the setting was switched off while it was up).
void hideToast();

/// Takes the message away and frees the window.
void destroy();

/// "Caps Lock đang bật" / "Caps Lock đã tắt".
const wchar_t* messageFor(bool on);

} // namespace CapsLockNotice
