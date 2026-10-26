---
title: Separate default and hover transparency for suggestion bar
author: Vinhnt
date: 2026-10-26
branch: windows-port
touches:
  - CHANGELOG.md
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/ModernKey/SuggestionPanel.h
  - Sources/OpenKey/macOS/ModernKey/SuggestionPanel.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.rc
---

## Decided
- Keep independent persisted percentages for normal suggestion-bar transparency (0–80%, default 0) and hover transparency (1–95%, default 85). The hover target stays at least one percentage point more transparent than the normal target so hover always fades the bar.
- If the normal transparency is raised past the stored hover percentage, raise and persist the hover percentage to normal+1. Update the visible hover slider bounds and value with it.
- Apply settings changes immediately to visible panels, using the normal target outside hover and the hover target after the existing hover delay.
## Tried and ruled out
- A fixed hover alpha of 0.15 made the fade nearly imperceptible when the normal slider was near its 80% maximum: only five percentage points remained. Give hover its own saved setting.
- No tests or build were run in this turn. `git diff --check` passed. `trail check` still reports 20 lexical conflicts in pre-existing Windows workflow and documentation changes, outside the transparency files.
## Watch out
- Preserve the existing normal-transparency range/default and initialize hover to 85% so its opacity initially matches the earlier 0.15 alpha target.
- Keep the hover value strictly above the normal value, and update both the hover slider's minimum and its displayed value when normal transparency changes.
