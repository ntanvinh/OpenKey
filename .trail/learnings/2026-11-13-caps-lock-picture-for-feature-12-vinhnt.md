---
title: "Caps Lock picture for feature 12: composed offscreen from the test build"
author: Vinhnt
date: 2026-11-13
branch: master
cost: { minutes: 7, tokens: 179596 }
touches:
  - docs/vopenkey-ai/product.json
  - marketing/features/caps-lock-warning.json
  - marketing/screenshots/desktop/captures.json
  - docs/vopenkey-ai/screenshots/12-caps-lock-warning.png
  - marketing/screenshots/desktop/12-caps-lock-warning.png
  - marketing/releases/notes/3.7.28.md
  - marketing/screenshots/features.json
---

## Decided
- The caps-lock-warning picture (feature 12) is composed from offscreen renders of the real code, not a screen capture: the Settings Hệ thống section (SettingsWindowController sectionStartup), the menu bar icon (VOKCapsLockStatusImage, Vietnamese = red flag) and the toast (CapsLockToast). A harness outside the repo places them on a plain desktop at 2x (2560x1600).
- The test build compiles from the repo project into /tmp (derived data outside the repo, uitest bundle id). The harness links the build objects except main.o, as suggestion_apps_test does.
- Linked files: marketing/screenshots/desktop/12-caps-lock-warning.png and docs/vopenkey-ai/screenshots/12-caps-lock-warning.png, the feature image and featured 12, one docs/vopenkey-ai/product.json entry with copied text, captures.json inUse true.

## Tried and ruled out
- The capslock_test pictures: they are separate pieces (icon strip, toast on a white plate), not one Settings picture.
- Expecting the toggle state from the defaults key alone: SettingsToggle reads its saved state only on reload.
- Allocating SettingsWindowController without init: _toggles stays nil, so reload finds nothing. Set _toggles with setValue:forKey: first, then call reload on each toggle.
- Overriding NSWindow isKeyWindow/isMainWindow and NSApplication isActive: the switch track still draws grey. Accepted and disclosed in captures.json.

## Watch out
- ~/Library/Application Support/VOpenKey/learned.txt changed at 22:08:41 during a render run. Nothing in the Caps Lock code or harness writes there, but the running app does; check before assuming.
- marketing/screenshots/features.json is an approved VApp Manager list and has no caps-lock-warning entry; it was left as is.
- The composed picture is not a real screen capture. Replace it with a hand capture if the owner wants a real screen.
