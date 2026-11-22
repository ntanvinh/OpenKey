---
title: "case_bar_test: why 6 'shows by itself' checks failed (locked screen) and how the test owns the machine state (2026-11-22)"
author: Vinhnt
date: 2026-11-22
branch: master
cost: { minutes: 13, tokens: 480726 }
touches:
  - CHANGELOG.md
  - Sources/OpenKey/macOS/ModernKey/DictionaryPalette.h
  - Sources/OpenKey/macOS/ModernKey/DictionaryPalette.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/macOS/tests/case_bar_test.m
  - Sources/OpenKey/macOS/tests/run-case-bar-test.sh
  - Sources/OpenKey/macOS/tests/run-dictionary-test.sh
  - Sources/OpenKey/macOS/tests/run-tap-test.sh
  - Sources/OpenKey/win32/OpenKey/OpenKey/DictionaryPalette.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.rc
---

## Decided
- Root cause of the 6 failures at HEAD (case_bar_test.m: double click, shift+click, shown once it stopped, shows again, select-all, plus the clipboard check): CaseBar.m's automatic path returns when `IsSecureEventInputEnabled()` (a password field cannot be put away), and the test read the REAL state of the Mac. Measured: with the screen locked (CGSession locked=1) loginwindow (pid 665) holds secure input, so the real answer is 1; a gate log in an instrumented copy showed `findSelection explicit=0 app=yes blocked=0 secure=1` and the reader was never called. Unlocked: 0 failures at HEAD logic. The shortcut path (`[CaseBar show]`, explicit) is not gated, which is why only the auto checks failed.
- Fix: run-case-bar-test.sh compiles CaseBar.m alone with `-DIsSecureEventInputEnabled=FakeSecureInput -DNSWorkspaceDidActivateApplicationNotification=kTestActivation`; case_bar_test.m defines both (`sFakeSecure`, `kTestActivation`, `Activate()`), and has new checks that never existed: with secure input a double click does not show the list and does not even read the selection (shortcut still works); the text's own application coming to the front keeps the list, any other one puts it away. Mutation-checked: removing the gate -> 2 failures (lines 242/243), removing the activation hide -> 1 failure (line 265); final runs ALL OK twice, also while the screen was still locked.

## Tried and ruled out
- "Secure input is off" from a one-off probe run just before: a standalone tool said 0 while the screen was unlocked, the test (and later the probe) said 1 once it locked. The state flips when the owner leaves or comes back; always print it next to a failing run (build/dict-border/secure.m style: CGSessionCopyCurrentDictionary kCGSSessionSecureInputPID + CGSSessionScreenIsLocked).
- Treating the transient failure at lines 208/211 (explicit show, `show() found the selection`) as a bug of the case bar: it appeared once, right when the Mac went from locked to unlocked, with the same code that passed before and after. Cause NOT observed; the likely one is a real app activation (unlock, the owner's click) reaching the observer in CaseBar.start, which hides the list; hence the test now owns that notification.

## Watch out
- Any test of CaseBar that touches the real workspace or the real session (secure input, front application, activation) is a test of whoever uses the Mac while it runs. Same family as the lock-screen note in openkey-fork-testing.md.
- Other runners that compile CaseBar.m or the suggestion code (run-tap-test.sh already fakes what it needs) were not audited for the same dependence.
