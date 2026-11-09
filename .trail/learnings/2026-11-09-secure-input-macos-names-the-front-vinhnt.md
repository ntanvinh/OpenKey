---
title: "Secure Input: macOS names the FRONT app, not the holder (corrects the note of the same day)"
author: Vinhnt
date: 2026-11-09
branch: master
cost: { minutes: 16, tokens: 145522 }
touches:
  - README.md
  - Sources/OpenKey/macOS/ModernKey/SecureInputHolder.h
  - Sources/OpenKey/macOS/ModernKey/SecureInputHolder.m
  - Sources/OpenKey/macOS/ModernKey/SecureInputMonitor.h
  - Sources/OpenKey/macOS/ModernKey/SecureInputMonitor.m
  - Sources/OpenKey/macOS/ModernKey/SecureInputWindow.m
  - Sources/OpenKey/macOS/ModernKey/StatusMenuController.m
  - Sources/OpenKey/macOS/tests/secure_input_holder_test.m
  - Sources/OpenKey/macOS/tests/secure_input_ui_test.m
  - build/sip-probe/siphold.m
---

## Decided
- CORRECTS the learning "Secure Input: wrong holder name (macOS names one process), checked and annotated" of the same day, whose "Decided" part (doubt only when macOS names VOpenKey AI itself) and "Tried and ruled out" part (real secure input could not be made) are outdated. Measured outside the sandbox on macOS 15.7: `kCGSSessionSecureInputPID` is the process number of the application IN FRONT, not of the holder.
  - Experiment: two command line processes, then one accessory NSApplication (no window, never frontmost), held `EnableSecureEventInput` for ~3 s each. macOS named the front app (Electron), named Chrome the moment the owner switched to Chrome, Electron again on the way back; the real holder was never named. `IsSecureEventInputEnabled` stayed on until the last holder released.
  - Same in the owner's diagnostics logs: all 14 non-system `[secure] ON` lines named the front app.
- So the name is a fact only when something confirms it. `SecureInputMonitor +checked:` leaves `doubt` empty for: the lock screen and macOS system prompts (role System/LockedSession), a terminal whose Secure Keyboard Entry preference is on (`SecureInputSuspect +secureKeyboardEntryIsOnForPID:`), this very process while one of its `NSSecureTextField` is being edited, nobody named (pid 0). Every other named app gets `doubt` ("macOS chỉ báo ứng dụng đang ở phía trước…"), the heading/menu item/tooltip say "macOS báo … (có thể không đúng)".
- `earlierReports` are the applications the person typed in while secure input stayed on; the window turns them into "Secure Input vẫn bật liên tục trong khi app bạn gõ đổi giữa: A, B … nhiều khả năng một ứng dụng chạy nền đang giữ" (an app with a password field normally releases it when you leave). Suspects (remote desktop, VM, password manager, terminal with the switch on) stay as the lead.

## Tried and ruled out
- Asking Accessibility whether the front app has a focused secure field (`SensitiveField verdictForFocusedFieldInProcess:`) on every 0.5 s poll: it talks to another app, must run off the main thread, and a stalled main thread already cost the owner their tap once (see memory openkey-fork-testing). Not added; possible follow-up per front-app change, asynchronously.
- Changing the macOS-Vietnamese-IM fallback: left alone, it is the owner's decision (below).

## Watch out
- The fallback "an ordinary app in the background holds secure input -> switch to macOS' Vietnamese input method" (`HolderIsTheAppBeingTypedIn`) compares the named pid with the front pid. Since the named pid IS the front pid, it never fires for a real background holder; it fires for ~0.4 s at a switch of the front app, while the named pid lags (log: "Secure input is on, using …VietnameseSimpleTelex" 14:53:23.001 and 14:56:23.031, "Back to …ABC" 0.45 s and 0.36 s later; `/usr/bin/log show --predicate 'process == "VOpenKey AI"'`). Real consequence: the input source is flipped to Apple's IM for a moment at app switches. Not changed.
- To reproduce: `build/sip-probe` style probes (`siphold`: EnableSecureEventInput for N s; `sipwatch`: print every change of secure flag, named pid, front app). Each run blinds the owner's tap for its duration: a few seconds, say so.
- With the sandbox off the 9 failures of `run-secure-input-ui-test.sh` ("Sao chép thông tin") disappear: they were the sandbox blocking the pasteboard service. `run-secure-input-ui-test.sh` failed once on `tipTexts` of the "gone" holder (line 212) and then passed 11 runs in a row; cause not found.
- Mutation check (backup, restore in a trap, `cmp` afterwards) of the rule in `+checked:`: never doubting an ordinary app (3 failures), doubting a terminal with Secure Keyboard Entry on (2), doubting the lock screen/system prompts (1): all caught. The app target builds (`xcodebuild … PRODUCT_BUNDLE_IDENTIFIER=vn.io.lssoft.vopenkey.uitest`, no warning in the changed files).
