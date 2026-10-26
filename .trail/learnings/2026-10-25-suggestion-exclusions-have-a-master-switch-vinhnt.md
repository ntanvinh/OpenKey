---
title: Suggestion exclusions have a master switch and a collapsed list
author: Vinhnt
date: 2026-10-25
branch: windows-port
touches:
  - CHANGELOG.md
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/ModernKey/SuggestionController.h
  - Sources/OpenKey/macOS/ModernKey/SuggestionController.mm
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.rc
  - Sources/OpenKey/macOS/tests/run-suggestion-apps-test.sh
  - Sources/OpenKey/macOS/tests/suggestion_apps_test.mm
---

## Decided
- User requested an on/off switch (default on) and a collapsible app exclusion list.
- SuggestionAppExclusionsEnabled gates isAppIdentifierExcluded, so disabling the policy affects runtime behavior without deleting the editable list.
- SuggestionAppsExpanded defaults false and persists the user's disclosure choice separately from the master switch.
- Keep list editing available while the policy is off. Use native NSSwitch and existing settings rows, with count and explicit disclosure label.
- Rebuilding rows restores focus to the new disclosure button for keyboard navigation.
## Tried and ruled out
- Hiding the app rows alone does not disable runtime exclusion. Keep collapse and enable state independent.
- Do not remove defaults or reset the list when switching the policy off.
## Watch out
- Tests use isolated preferences and link real app objects without starting the event tap or touching learned dictionaries.
- trail check 0.23 reports lexical conflicts on this implementation against the earlier immutable-default learning. Those are false positives: migration defaults are only seeded once; runtime uses the editable list and the master switch.
