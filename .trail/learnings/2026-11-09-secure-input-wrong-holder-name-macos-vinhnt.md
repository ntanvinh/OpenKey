---
title: "Secure Input: wrong holder name (macOS names one process), checked and annotated"
author: Vinhnt
date: 2026-11-09
branch: master
cost: { minutes: 1, tokens: 445 }
touches:
  - README.md
  - Sources/OpenKey/macOS/ModernKey/SecureInputHolder.h
  - Sources/OpenKey/macOS/ModernKey/SecureInputHolder.m
  - Sources/OpenKey/macOS/ModernKey/SecureInputMonitor.m
  - Sources/OpenKey/macOS/ModernKey/SecureInputWindow.m
  - Sources/OpenKey/macOS/ModernKey/StatusMenuController.m
  - Sources/OpenKey/macOS/tests/secure_input_holder_test.m
  - Sources/OpenKey/macOS/tests/secure_input_ui_test.m
---

## Decided
- Owner report 2026-11-09: the "Secure Input đang bật bởi X" name is sometimes wrong. On their Mac Remote Desktop Manager (bundle id `com.devolutions.remotedesktopmanager`) usually blocks typing, but the window named another app; the screenshot named VOpenKey AI itself (own PID), while the diagnostics log said the same stretch had started with "Electron".
- macOS (`kCGSSessionSecureInputPID`) names ONE process at a time, so the name is shown as a claim that is checked, not as a fact:
  - `SecureInputMonitor +checked:` keeps every process macOS named during one stretch of secure input (`_period`, reset when secure goes off to on) and gives the current holder `earlierReports`, `doubt`, `suspects` (`SecureInputHolder holderWithDoubt:earlierReports:suspects:`).
  - `doubt` is set when macOS names this very process and no `NSSecureTextField` field editor of ours is first responder (only the API key field of Settings can hold it). Heading, menu item and tooltip then say "macOS báo … (có thể không đúng)".
  - `SecureInputSuspect` (in SecureInputHolder.h/.m): running apps known to take secure input (remote desktop, VM, password manager by bundle prefix or name; Terminal/iTerm2 only while their Secure Keyboard Entry preference is on). Not listed for system/lock-screen holders. Cost 0.88 ms per look with 129 apps, only while secure input is on.
  - The window adds bullets in this order: doubt, advice for the kind of holder (dropped when doubtful), "macOS đã nêu lần lượt: A, B", "Cũng đang chạy và hay giữ Secure Input: …". "Sao chép thông tin" carries the same lines.
  - Diagnostics line `[secure] macOS names X (pid N) as the holder; in front: <bundle>; named before…; also running…` on every new PID in a stretch: the evidence for the next report.

## Tried and ruled out
- Real secure input from a sandboxed shell: `EnableSecureEventInput` returns noErr but `IsSecureEventInputEnabled` stays 0, because the sandbox blocks `com.apple.hiservices-xpcservice` ("Connection Invalid"). `log`, `ps` and `xcodebuild` are blocked too. So how WindowServer picks the PID with several holders was NOT measured.
- Reading the macOS unified log for who enabled secure input: `log show` cannot run sandboxed.
- Fixing the cause inside VOpenKey (ending the API key field editing on `windowDidResignKey`): no proof that the field was the holder, so only the detection and the message were added.

## Watch out
- Every `[secure] ON` line of the log (14 non-system ones, 2026-11-08/09) had holder == the app in front at that moment. So macOS may simply report the front app when the real holder is in the background; unproven. The first thing to check on the next report is the new log line (front app vs named process vs suspects).
- A test that makes a background app hold secure input while `vLanguage == 1` makes the monitor call `TISSelectInputSource` on the REAL Mac (it did once). `secure_input_holder_test.m` sets `vLanguage = 0` in TestAnnotations for that reason; keep it.
- `run-secure-input-*.sh` need `mktemp -d "$TMPDIR/…"` in a sandboxed shell, and `run-secure-input-ui-test.sh` has 9 failures there ("Sao chép thông tin" block, `NSPasteboard pasteboardWithUniqueName` needs the pasteboard service) that also fail on the untouched code.
- NOT verified: the app target was not built (`xcodebuild` needs approval); StatusMenuController.m only passed `clang -fsyntax-only`. Real RDM holding secure input, the real tray menu and the window with real data were not seen.
