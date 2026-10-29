---
title: "Secret-field detection on Windows: UIA + ES_PASSWORD, shared engine/SensitiveField"
author: Vinhnt
date: 2026-10-29
branch: windows-port
cost: { minutes: 4, tokens: 298188 }
touches:
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.vcxproj
  - Sources/OpenKey/win32/OpenKey/OpenKey/SuggestionBar.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/SuggestionBar.h
  - Sources/OpenKey/win32/OpenKey/OpenKey/SuggestionController.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/SuggestionController.h
  - scripts/link-windows.sh
  - scripts/test-portable.sh
  - Sources/OpenKey/engine/SensitiveField.cpp
  - Sources/OpenKey/engine/SensitiveField.h
  - Sources/OpenKey/engine/tests/sensitive_field_test.cpp
---

## Decided
- Owner rule (2026-10-29): every fix ships on macOS and Windows together.
- Windows has no secure input, the keyboard hook sees password keys, so the field is asked: ES_PASSWORD style of the focused Edit/RichEdit (sync, in the hook) and UI Automation (worker thread: IsPassword, then Name/HelpText/AutomationId through engine/SensitiveField.cpp). Same word list and cases as macOS SensitiveField.m (test: engine/tests/sensitive_field_test.cpp).
- Windows has no serial queue like macOS, so the bar of a word stays hidden (g_fieldPending) until the answer is in. isActive() stays true while the field is secret, otherwise the hook stops calling keyProcessed and the next ordinary field is never noticed.

## Watch out
- Windows code only compiled (check-windows.sh, link-windows.sh x64), never run. UIA GetFocusedElement makes Chromium turn on its accessibility tree.
