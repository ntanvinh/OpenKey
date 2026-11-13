---
title: "Caps Lock toast: Settings toggle on macOS and Windows"
author: Vinhnt
date: 2026-11-13
branch: master
cost: { minutes: 7, tokens: 358055 }
touches:
  - README.md
  - Sources/OpenKey/macOS/ModernKey/AppDelegate.m
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/ModernKey/StatusMenuController.m
  - Sources/OpenKey/macOS/ModernKey/VOKUI.h
  - Sources/OpenKey/macOS/ModernKey/VOKUI.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/win32/OpenKey/OpenKey/AppDelegate.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/FeatureActions.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/MainControlDialog.cpp
---

## Decided
- Owner chose 2026-11-13 to add a switch for the Caps Lock toast on both platforms (it replaces "no toggle" in the earlier Caps Lock learning). It switches off the message only; the tray icon stays red while Caps Lock is on.
- macOS: `SettingsToggle` in `sectionStartup` of SettingsWindowController.m, key `CapsLockToast` (0/1, registered default 1 by `CapsLockMonitor +registerDefaults`, which AppDelegate now also calls at launch so the Settings window reads 1, not 0). Switching it off hides a toast that is up. `CapsLockMonitor noteState:` treats a missing key as on.
- Windows: `vCapsLockToast` (defined in CapsLockNotice.cpp, registry name = variable name, loaded in `FeatureActions::loadSettings`, reset to 1 in `AppDelegate::onDefaultConfig`). The check box is created IN CODE on the "He thong" tab of MainControlDialog (`addCapsLockToastCheck`, 7,108 dialog units, id 2103), as the earlier learning says for OpenKey.rc.

## Tried and ruled out
- Adding the control to OpenKey.rc / resource.h: Visual Studio rewrites the .rc.
- A Settings toggle that also hides the red icon: the owner asked for the red icon as the main signal, the toggle is for the message only.

## Watch out
- NOT seen: the check box position on a real Windows tab (108 units may overlap the page frame on some DPI/theme), the real macOS Settings page. Checked only by compile (mingw x86/x64, link ok) and `run-capslock-test.sh` (checks the default 1 and the saved 0).
- `trail check` shows lexical false positives on MainControlDialog.cpp:329: the comment "OpenKey.rc is left alone" matches the learning it follows.
