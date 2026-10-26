---
title: Editable macOS suggestion exclusions migrate the old extra-app list
author: Vinhnt
date: 2026-10-25
branch: windows-port
touches:
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/ModernKey/SuggestionController.h
  - Sources/OpenKey/macOS/ModernKey/SuggestionController.mm
  - Sources/OpenKey/macOS/tests/run-suggestion-apps-test.sh
  - Sources/OpenKey/macOS/tests/suggestion_apps_test.mm
---

## Decided
- Settings > Gợi ý exposes an editable exclusion list seeded with the eight existing standalone terminals. Store the complete edited list in SuggestionExcludedAppsList; an empty array is intentional.
- First access merges the old SuggestionExcludedApps extra-app list with the terminal defaults. Never union defaults into subsequent reads, otherwise removed terminals reappear.
- Applying edits rechecks the frontmost application and resets the suggestion session before applying settings. Macro expansion keeps the existing immediate behavior in excluded apps.
- The suggestion page always has a scroll view because users can grow its app list after construction. Recompute the document height after edits.
## Tried and ruled out
- Adding UI around the old immutable-default check cannot let users re-enable suggestions in a terminal.
- Launching the normal app is unnecessary for list tests. The test runner links actual app objects and isolates NSUserDefaults; it never starts dictionaries or the event tap.
## Watch out
- Trail 0.23 does not index Objective-C implementations here; exact callers may require a scoped rg fallback.
- run-suggestion-apps-test.sh builds Debug with signing disabled, tests migration/persistence/removal and renders the real section in both appearances under /tmp. It does not prove live typing in each terminal.
