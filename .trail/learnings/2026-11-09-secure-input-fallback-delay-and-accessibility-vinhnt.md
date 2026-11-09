---
title: "Secure Input: fallback delay and Accessibility confirmation done (owner decisions 2026-11-09)"
author: Vinhnt
date: 2026-11-09
branch: master
cost: { minutes: 11, tokens: 149372 }
touches:
  - README.md
  - Sources/OpenKey/macOS/ModernKey/OpenKeyManager.m
  - Sources/OpenKey/macOS/ModernKey/SecureInputHolder.h
  - Sources/OpenKey/macOS/ModernKey/SecureInputHolder.m
  - Sources/OpenKey/macOS/ModernKey/SecureInputMonitor.h
  - Sources/OpenKey/macOS/ModernKey/SecureInputMonitor.m
  - Sources/OpenKey/macOS/ModernKey/SecureInputWindow.m
  - Sources/OpenKey/macOS/ModernKey/StatusMenuController.m
  - Sources/OpenKey/macOS/tests/run-secure-input-holder-test.sh
  - Sources/OpenKey/macOS/tests/secure_input_holder_test.m
---

## Decided
- Owner answers 2026-11-09 to the open points of "Secure Input: macOS names the FRONT app, not the holder": (1) fallback "chỉ chặn chạy nhầm", (2) ask Accessibility "chạy nền, mỗi lần đổi app". Both done in `SecureInputMonitor.m`.
- Fallback: macOS' Vietnamese input source takes over only after the "ordinary app that is not in front holds it" condition held without a break for `SecureInputFallbackDelay` (1 s, `_fallbackWantedSince`, clock `Now()`), and is given back at once when the condition stops. The rule itself is unchanged and still cannot fire for a real background holder (the named pid is the front pid); the owner did NOT choose the redesign that recognises Remote Desktop Manager / MacPass.
- Confirmation by the field: `+askFieldOf:` runs `SecureInputFieldVerdictProvider` on a serial queue (not the main thread) once each time macOS names another app (`_fieldQueryPID`), answer comes back to the main thread and `evaluate` runs again; a `SensitiveFieldSensitive` verdict removes `doubt`. The provider is set in `OpenKeyManager.m` (`[SensitiveField verdictForFocusedFieldInProcess:]`), so the monitor and its test scripts need no `SensitiveField.m`. Verdicts are per time secure input is on (`_stretch`), and a stale answer is dropped.
- `run-secure-input-holder-test.sh` now fakes `TISCopyCurrentKeyboardInputSource`, `TISCreateInputSourceList`, `TISSelectInputSource`, `TISGetInputSourceProperty` (`-D…=Fake…`): the real input source of the Mac is never touched. `-setClockForTesting:` and `-setFieldVerdictProvider:` are the two hooks.

- A number that names no running process (role Unknown, `processExists == NO`) gets no `doubt` and is not asked about: it is stale, not "the application in front", and the window keeps its "Tiến trình đã thoát" advice. Found through a flaky holder test (about 1 run in 3: `NSTask waitUntilExit` spins the run loop, the 0.5 s timer of the monitor ran `evaluate` with the exited sleeper as holder and asked Accessibility about it); a deterministic check was written first, then the one-line fix; 6 runs in a row green afterwards.

## Tried and ruled out
- Mutation check (backup, trap, `cmp`): no delay (6 failures), wait not restarted (3), field asked at every poll (9), password field confirms nothing (3), look into the field on the main thread (3): all caught. Not caught and judged equivalent: dropping the `pid != _fieldQueryPID` test on a late answer (the cache is keyed by pid and cleared before each new question, so nothing observable changes).
- Testing the real Accessibility verdict: needs an active application with a focused field, i.e. taking the owner's keyboard; not done.

## Watch out
- NOT verified live: the real AX verdict of a real password field in a real app (Chrome, Terminal, MacPass), and the behaviour of the fallback with a real background holder. `SensitiveFieldSensitive` also covers fields only NAMED password/OTP/PIN (visible passwords), so it is slightly broader than "holds secure input".
- Asking sets `AXManualAccessibility` on each app asked about while secure input is on (`CaretLocator copyFocusedElementInProcess:`), which makes Chromium/Electron apps build their accessibility tree: a cost the suggestion bar already paid for apps typed in.
- The holder test picks two ordinary apps that run on the Mac and the app in front; it skips those parts when fewer exist. If the owner switches the front app in the few milliseconds the fallback part takes, it can fail once.
