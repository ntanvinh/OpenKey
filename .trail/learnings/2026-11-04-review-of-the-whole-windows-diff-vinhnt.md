---
title: Review of the whole Windows diff (2026-11-04)
author: Vinhnt
date: 2026-11-04
branch: master
cost: { minutes: 15, tokens: 138992 }
touches:
  - Sources/OpenKey/engine/AIProtocol.cpp
  - Sources/OpenKey/engine/AIProtocol.h
  - Sources/OpenKey/engine/SuggestSession.h
  - Sources/OpenKey/engine/tests/ai_protocol_test.cpp
  - Sources/OpenKey/engine/tests/suggest_test.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AIAssistant.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AIClient.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AIClient.h
  - Sources/OpenKey/win32/OpenKey/OpenKey/AISettings.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AISettings.h
---

## Decided
- 2026-11-04 review of the whole Windows diff (owner asked for it after the picture port). Read: AIAgentRunner, CaseBar, the hook glue in OpenKey.cpp, the update flow (AppDelegate, OpenKeyManager, OpenKeyUpdate), SuggestionController/Bar/OptionsDialog, FeaturesDialog, AIAssistant, AISettingsDialog, PictureFile, TextInserter. Fixed what was found: (1) AIAgentRunner searched relative PATH entries ("." or "tools") where the program happens to run, a planted codex.exe would have been taken: only absolute folders now (PathIsRelativeW). (2) CaseBar g_looking could stay true for ever if the UI Automation worker never answered (busy or hung program): a start time and an 8 s watchdog now let a new look start. (3) The window of the case list is made before the hooks (CaseBar::prepare) instead of inside the first keyboard hook call. (4) The update thread joins COM (MTA) because urlmon is COM; AppDelegate.cpp needed objbase.h, and only link-windows.sh sees it because check-windows.sh skips AppDelegate.cpp, BaseDialog.cpp and OpenKeyHelper.cpp on purpose. (5) OpenKeyUpdate says so when only the .sha256 could not be fetched, instead of "does not match". (6) SuggestionOptionsDialog no longer sets the trackbar that is being dragged. (7) windows-ui-test.ps1 switches vCaseBarAuto off so CI does not depend on it; PictureFile caps decoded pictures at 36 million pixels.

## Tried and ruled out
- Nothing from the review was ruled out; no logic error was found in the keyboard hook closing-mark glue, the controller exclusion list, the picture flow of the assistant, or the process/pipe/job handling of the runner beyond the points above.

## Watch out
- Run link-windows.sh, not only check-windows.sh, after touching AppDelegate.cpp, BaseDialog.cpp or OpenKeyHelper.cpp.
- Alt+1..5 is taken by both the suggestion bar and the auto case list (the list is read first by the hook); a selection by keys while the bar is up can meet both. Rare, same on macOS with the option key.
- Still nothing ran on Windows.
