---
title: "Caps Lock: red tray icon and toast on macOS and Windows"
author: Vinhnt
date: 2026-11-13
branch: master
cost: { minutes: 14, tokens: 429850 }
touches:
  - README.md
  - Sources/OpenKey/macOS/ModernKey/AppDelegate.m
  - Sources/OpenKey/macOS/ModernKey/StatusMenuController.m
  - Sources/OpenKey/macOS/ModernKey/VOKUI.h
  - Sources/OpenKey/macOS/ModernKey/VOKUI.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.vcxproj
  - Sources/OpenKey/win32/OpenKey/OpenKey/SystemTrayHelper.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/SystemTrayHelper.h
  - scripts/link-windows.sh
---

## Decided
- Owner request 2026-11-13: pressing Caps Lock turns the tray/menu bar icon red and shows a toast "Caps Lock đang bật" / "Caps Lock đã tắt". Done on macOS and Windows together (owner rule: every feature on all platforms).
- macOS: `CapsLockMonitor` reads `+[NSEvent modifierFlags]` from global and local flagsChanged monitors plus a 0.3 s timer; `OpenKey.mm` (the event tap) is NOT touched, so `run-tap-test.sh` needs no change. `CapsLockToast` is a nonactivating panel; it is hidden by a clock (dispatch_after), not by the end of the animation, because a window that is not drawn (offscreen in tests) never finishes one. Red icon = `VOKCapsLockStatusImage`, same tile code as the yellow warning (`VOKWarningStatusImage` now shares `TintedStatusImage`).
- Secure-input yellow wins over caps red in `StatusMenuController refresh`; the tooltip and VoiceOver label get the caps line in both cases.
- Windows: polled from a WM_TIMER (150 ms) of the tray window with `GetKeyState(VK_CAPITAL)`, not from the low-level keyboard hook (it must answer fast, and the toggle bit is not updated yet while the key goes down). The icon is red tile + white letter built at run time (`engine/CapsLockIcon` does the pixels, portable and tested), because the Vietnamese icon is already a light red.
- Toast can be switched off only on macOS, with the hidden `CapsLockToast` default; no Settings toggle on either platform.

## Tried and ruled out
- Hooking the tap callback in `OpenKey.mm` for flagsChanged: would force `tap_test` to link the monitor, and the tap is blind under secure input anyway; monitors plus polling cover both.
- A plain red tint of the Windows icon: invisible for the Vietnamese one.
- A balloon/toast through `NIF_INFO` on Windows: lands in the Action Center on every toggle.

## Watch out
- NOT verified: a real Caps Lock press on either OS, the icon in the real menu bar, `NSEvent modifierFlags` while secure input is held, anything on Windows (never run).
- `trail check` reports 3 lexical false positives (README mention of secure input, `StatusMenuController.m:222` which was already there, the word "window" in the `SystemTrayHelper.h` comment).
- New Windows sources must be UTF-8 with BOM (Vietnamese literals) and registered by hand in `OpenKey.vcxproj`; new macOS files by hand in `project.pbxproj` (ids `5EC0DE10CA95...`).
