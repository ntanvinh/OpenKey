---
title: Macros wait for the user on the suggestion bar (MacroConfirm)
author: Vinhnt
date: 2026-10-20
branch: master
cost: { minutes: 7, tokens: 172166 }
touches:
  - README.md
  - Sources/OpenKey/engine/Engine.cpp
  - Sources/OpenKey/engine/Engine.h
  - Sources/OpenKey/engine/SuggestSession.cpp
  - Sources/OpenKey/engine/SuggestSession.h
  - Sources/OpenKey/engine/tests/restore_test.cpp
  - Sources/OpenKey/engine/tests/suggest_test.cpp
  - Sources/OpenKey/macOS/ModernKey/AppDelegate.m
  - Sources/OpenKey/macOS/ModernKey/OpenKey.mm
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
---

## Decided
- Setting `MacroConfirm` (`vMacroConfirm`, default ON, Settings > Gõ tắt, child of UseMacro). While on, the typing engine does not replace a macro on space/break key (`vMacroNeedsConfirm` in Engine.cpp, set by SuggestionController.applySettings; only Unicode table; off in excluded apps).
- `vPeekMacro()` returns the full text; `Session::keyProcessed(..., macroText)` makes it candidate 0 (Tab / ⌥1 types it plus a space, nothing learned). `Settings.words=false` gives a macro-only bar, so macros work even with word suggestions off.
- English mode (UseMacroInEnglishMode) still replaces at once: no bar there.
- Bar shows macro text on one line, cut at 36 chars (BarText in SuggestionController.mm).

## Tried and ruled out
- Making the engine itself ask: platform-specific, so the engine only exposes the flag and the peek.
- Leaving the bar tied to the word-suggestion switch: with it off by default, macros would never expand.

## Watch out
- tap_test (run-tap-test.sh) fails 89 checks inside the Claude sandbox, same count on untouched HEAD (needs ~/Library/Logs; mktemp -d ignores TMPDIR, copy the script with WORK under /private/tmp/claude).
- A Bash command that is rejected by the sandbox ("variable can't be checked") runs NOTHING, including python edits chained in it: one test edit was silently lost this way, re-check with grep.
- Not verified on the real app: bar showing and Tab accepting in a real text field.
