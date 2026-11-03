---
title: "Secure input: yellow tray icon and holder window (who holds it)"
author: Vinhnt
date: 2026-11-03
branch: master
cost: { minutes: 27, tokens: 389759 }
touches:
  - README.md
  - Sources/OpenKey/macOS/ModernKey/SecureInputMonitor.h
  - Sources/OpenKey/macOS/ModernKey/SecureInputMonitor.m
  - Sources/OpenKey/macOS/ModernKey/StatusMenuController.m
  - Sources/OpenKey/macOS/ModernKey/VOKUI.h
  - Sources/OpenKey/macOS/ModernKey/VOKUI.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/macOS/tests/run-secure-input-suggestion-test.sh
  - Sources/OpenKey/macOS/tests/run-tap-test.sh
  - docs/vopenkey-ai/product.json
---

## Decided
- Owner request 2026-11-03: when secure input forces English the tray icon turns yellow, the menu notice "Secure Input đang bật bởi X…" is clickable and opens a window with details to track the program down. macOS only: Windows has no secure input, so nothing was ported.
- Yellow only when OpenKey is in Vietnamese mode and `isOpenKeyBlind` (auto-switched to English). Not yellow in English mode, nor while the macOS Vietnamese-IM fallback types for us.
- Icon: `VOKWarningStatusImage(StatusEng glyph)` = yellow glyph (drawn twice: the flag's grey stripes are half transparent and went mustard over the tile) on a dark rounded tile, so it reads on light and dark menu bars. No new asset; the status PNGs are one colour on alpha.
- Facts live in `SecureInputHolder` (value object: pid, role, name, bundle id, version, path, start time, parent, icon), built by `SecureInputMonitor` on every poll; `SecureInputWindow` shows them and follows `SecureInputMonitorDidChangeNotification`. Role uses the frontmost app that is not VOpenKey itself (our own window steals focus).
- Dates in the window are forced to `vi_VN`: the UI is Vietnamese-only, an English Mac showed "Today, 14:11 (1 hour ago)".

## Tried and ruled out
- Plain yellow glyph without a tile: ~1.6:1 contrast on a light menu bar.
- Lazy icon loading in SecureInputHolder: measured 0.26 ms per snapshot at 2 polls/s (about 0.05% of one core), not worth the code.
- SwiftUI: the app is AppKit/Objective-C, a SwiftUI window would not follow VOKUI.

## Watch out
- Tests: `tests/run-secure-input-holder-test.sh` and `run-secure-input-ui-test.sh [folder]` (offscreen, fake secure input + session, /bin/sleep child as holder). Snapshot the window through `window.contentView.superview`, not the content: otherwise dark mode has a white ground.
- `run-tap-test.sh` was already broken at HEAD (SensitiveField.m not in its compile list, link error since commit 44b57de); fixed by adding it. It then has ONE failure, `tap_test.mm:466` (case bar ⌥1 paste), identical on a clean HEAD copy, so unrelated to this work.
- NOT verified: the real tray click and the yellow icon in the menu bar of the running app (the status item cannot be screenshotted on this Mac), real holders with real password fields.
- `trail check` flagged 3 lexical false positives (window key, build window file, bar word suggestion) that only match file names and comments.
