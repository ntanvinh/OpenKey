---
title: macOS suggestion bar transparency slider preserves hover fade
author: Vinhnt
date: 2026-10-26
branch: windows-port
touches:
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/ModernKey/SuggestionPanel.h
  - Sources/OpenKey/macOS/ModernKey/SuggestionPanel.m
  - Sources/OpenKey/macOS/tests/suggestion_apps_test.mm
  - Sources/OpenKey/macOS/tests/suggestion_panel_test.m
  - scripts/dev.sh
---

## Decided
- Settings > Gợi ý has a native continuous transparency slider from 0 to 80 percent, default 0, with a visible percentage and an accessibility label. It uses the existing settings row/card design.
- SuggestionPanel persists SuggestionTransparencyPercent and notifies existing panels immediately. Show and pointer exit restore the selected alpha; hovering still fades to 0.15 and preserves the existing grace period and click-through behavior.
## Tried and ruled out
- Do not launch scripts/dev.sh for compile verification: the isolated AppKit tests render the real settings section and instantiate the real panel without starting the input tap or changing production preferences.
- trail check reports 20 lexical conflicts in earlier branch changes to Windows workflow, CHANGELOG, CLAUDE and README; none are in the five files changed for this slider. No commit or PR is made here.
## Watch out
- Objective-C implementation symbols are absent from trail 0.23's graph; use exact source spans after the graph lookup.
- run-suggestion-panel-test.sh is not executable; invoke it with zsh. Both it and run-suggestion-apps-test.sh passed; settings snapshots at 0, 50 and 80 percent cover light and dark appearances.
- When replacing a settings section in an NSStackView test, remove the previous section once before the theme/value loop.
