---
title: "Suggestion bar: closing mark replaces the space left by an accepted suggestion"
author: Vinhnt
date: 2026-10-27
branch: windows-port
cost: { minutes: 1, tokens: 51966 }
touches:
  - Sources/OpenKey/engine/SuggestSession.cpp
  - Sources/OpenKey/engine/SuggestSession.h
  - Sources/OpenKey/engine/tests/suggest_test.cpp
  - Sources/OpenKey/macOS/ModernKey/OpenKey.mm
  - Sources/OpenKey/macOS/ModernKey/SuggestionController.h
  - Sources/OpenKey/macOS/ModernKey/SuggestionController.mm
---

## Decided
- Rule lives in the portable engine: Session::accept sets spacePending_, any keyProcessed/reset clears it; Session::dropsAcceptedSpace(ch) lists . , ; : ! ? ) ] } >. macOS glue (OpenKey.mm, before "handle keyboard") sends one Backspace when the key's character (CGEventKeyboardGetUnicodeString) is in that list and acceptedSpacePending() is true.
- Keys with Cmd/Ctrl/Option held are never touched.

## Tried and ruled out
- Nothing alternative tried; the glue was only syntax-checked (clang -fsyntax-only), not run in a real app.

## Watch out
- OTHER_CONTROL_KEY in OpenKey.mm is a macro without outer parentheses: always write !(OTHER_CONTROL_KEY).
- macOS sed -i needs '' (use python for edits).
- Not verified: real Tab/⌥1 accept followed by . or ) in a live app.
