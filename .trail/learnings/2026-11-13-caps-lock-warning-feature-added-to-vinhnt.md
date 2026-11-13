---
title: Caps Lock Warning feature added to the marketing feature list
author: Vinhnt
date: 2026-11-13
branch: master
cost: { minutes: 2, tokens: 117696 }
touches:
  - CHANGELOG.md
  - README.md
  - Sources/OpenKey/macOS/ModernKey/AppDelegate.m
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/ModernKey/StatusMenuController.m
  - Sources/OpenKey/macOS/ModernKey/VOKUI.h
  - Sources/OpenKey/macOS/ModernKey/VOKUI.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/win32/OpenKey/OpenKey/AppDelegate.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/FeatureActions.cpp
---

## Decided
- Added marketing/features/caps-lock-warning.json (id caps-lock-warning): tier value, rank 100 (between custom-text-macros 90 and remember-input-settings-by-app 110), mode desktop, orientation landscape, screens Menu bar, Caps Lock notice, System settings.
- No `featured` and no `image` on the new file. Featured 1 to 11 are taken by the existing features and the run-only rule forbids renumbering them. `image` is set only after the screenshot exists (marketing/screenshots/desktop/scenarios.md).
- Copy is macOS-only because marketing/product.json lists platforms ["macOS"]. The Windows tray behaviour is left out of the copy.
- Copy rules applied (copywriting skill): 1 to 3 sentences, no em dashes, no contrast reveals, no trailing pile-on clauses.

## Tried and ruled out
- Validating the JSON with python3 -I (inline and heredoc) and with plutil -lint: both blocked by the approval policy in this session. Fallback: read the file back and check `git status`, which showed the new file as the only change under marketing/features.
- Writing a check script under /tmp: write permission was denied.

## Watch out
- The Caps Lock copy describes intended behaviour. A real key press on macOS, the icon in the real menu bar, and Windows were never run.
- positioning.md and the 11 existing feature files already exist. The run-only instruction says not to rewrite them, so the full catalog was not redone.
- When the Caps Lock screenshot is captured, set image to ../screenshots/desktop/NN-caps-lock-warning.png. Setting featured needs a free number, which means renumbering existing features, so confirm with the owner first.
