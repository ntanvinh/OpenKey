---
title: "Windows parity pass 2026-11-04: transparency, program list, closing mark, update flow"
author: Vinhnt
date: 2026-11-04
branch: master
cost: { minutes: 20, tokens: 304684 }
touches:
  - Sources/OpenKey/engine/SuggestSession.h
  - Sources/OpenKey/engine/tests/suggest_test.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AIAssistant.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AboutDialog.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AppDelegate.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AppDelegate.h
  - Sources/OpenKey/win32/OpenKey/OpenKey/FeaturesDialog.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/MainControlDialog.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.rc
---

## Decided
- 2026-11-04, owner: bring Windows up to the recent macOS changes it can support (secure input has no Windows equivalent: skipped). Done: suggestion bar transparency (engine/SuggestAppearance, 0-80 normal and 1-95 hover, hover always above normal), editable program list plus master switch (engine/AppExclusions + SuggestionOptionsDialog, default list = the old terminals, a never-edited registry value means defaults, an empty value means an emptied list), closing mark replaces the accepted space (engine Session::spaceAdjustment already existed; Windows glue in the keyboard hook, ToUnicodeEx only while the new Session::spaceAdjustmentPending() is true), AI window Sao chep va dong (closes only after the clipboard took the text), LSSoft lines in About, README and checklist.
- Windows update flow: before this the check was OFF by default (vCheckNewVersion 0) and ran synchronously on the UI thread before the message loop. Now default ON, a worker thread (15 s after start, every 6 h, 10 min after a failed try) posts AppDelegate::kMessageUpdateFound to the tray window. OpenKeyManager::launchUpdater starts OpenKeyUpdate.exe from the exe own folder: a program started by schtasks or the Run key has System32 as current folder, the old code used GetCurrentDirectory, lost the update and still closed the app. OpenKeyUpdate checks the zip SHA-256 against the .sha256 asset (real v3.7.19 file checked: first word equals shasum of the zip) and relaunches.
- Mac updater re-verified on the REAL release v3.7.20 with the production AppUpdater (see the other 2026-11-04 note and memory auto-update).

## Tried and ruled out
- Editing OpenKey.rc to add the LSSoft lines to About: it is rewritten by Visual Studio, so the two lines are created in code (MapDialogRect + SysLink) in the free space under the version. Only one label of OpenKey.rc was renamed (Tu dong kiem tra ban moi).
- Another button row in the Features window: it is already as high as 1366x768 allows, so the new button sits on the macro-presets row and the window is wider.
- Running anything on Windows: not possible here. Everything is mingw syntax check x86+x64, a mingw link, portable tests and mutation checks of the two new engine modules. The first real build is the Windows build workflow on GitHub.

## Watch out
- OpenKeyUpdate.exe is never replaced by an update (it is running), so its SHA-256 check and relaunch only reach people who install from a new zip. The main program part (launchUpdater with the program folder) reaches everybody who updates.
- Release v3.7.20 has no Windows zip and version.json still says 3.7.19: no GitHub workflow was started on 2026-11-03 for the push or the release (cause not proven), release.sh stopped before the announce step. By design Windows users are not offered a version without a zip.
- Windows version compare (OpenKeyManager::checkUpdate shiftVersion) puts the minor number above the major: a major bump (4.0.0) would compare lower than 3.7.x. Not touched.
- The Windows UI test already sets vCheckNewVersion = 0, so the update prompt cannot steal focus in CI.
