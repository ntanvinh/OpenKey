---
title: "Auto-update: what is now verified on the real Mac (hdiutil, Xcode build, real signature, real swap)"
author: Vinhnt
date: 2026-10-20
branch: master
cost: { minutes: 1, tokens: 7187 }
touches:
  - CLAUDE.md
  - README.md
  - RELEASING.md
  - Sources/OpenKey/macOS/ModernKey/AppDelegate.m
  - Sources/OpenKey/macOS/ModernKey/AppInfo.h
  - Sources/OpenKey/macOS/ModernKey/OpenKeyManager.h
  - Sources/OpenKey/macOS/ModernKey/OpenKeyManager.m
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/ModernKey/StatusMenuController.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
---

## Decided
- Verified outside the sandbox: run-app-update-test.sh with VOK_TEST_REAL_DMG=1 passes (real hdiutil attach/detach, no volume left mounted); a full signed Release xcodebuild of the project succeeds with AppUpdater.m registered; the production AppUpdateVerifier.standard accepts the real Developer ID build (Team 39SH232CQ4) and refuses a wrong version, another Team, another identifier; runningApplicationSatisfiesRequirement is NO for an unsigned process and YES for one signed with that identity and identifier vn.io.lssoft.vopenkey.
- End to end on the real build in a scratch folder (real dmg, production verifier, real helper): 3.7.4 replaced by 3.7.5, the installed copy still passes codesign --verify --deep --strict and the production requirement, has no quarantine attribute, nothing is left beside the app, helper note "ok 3.7.5".

## Tried and ruled out
- Nothing in the design was ruled out by this pass.

## Watch out
- Still NOT verified: the alerts, the status menu item and the Settings button in the running app; the real /usr/bin/open relaunch of the real app (the e2e used a recording tool so that no second keyboard hook started); macOS 15 App Management/TCC on a real replacement; Accessibility permission surviving; an unnotarized release; a real release on the repository.
- In the agent's shell the permission policy denied the gh CLI, ps and rm -rf with variables (plain rm -r works), so the list of releases already on the repository was never read.
- tap_test (run-tap-test.sh) fails one case-bar check, "XIN CHÀO" pasted (line 466), on an untouched export of HEAD too: not caused by the updater.
