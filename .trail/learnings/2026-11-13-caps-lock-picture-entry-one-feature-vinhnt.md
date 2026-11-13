---
title: "Caps Lock picture entry: one feature file, picture description in captures.json"
author: Vinhnt
date: 2026-11-13
branch: master
cost: { minutes: 3, tokens: 163934 }
touches:
  - marketing/screenshots/desktop/captures.json
  - marketing/releases/notes/3.7.28.md
  - marketing/features/caps-lock-warning.json
  - scripts/check-product-docs.py
  - docs/vopenkey-ai/product.json
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - marketing/product.json
  - CLAUDE.md
---

## Decided
- "See Caps Lock Before You Type" already exists as marketing/features/caps-lock-warning.json. Keep that one entry; never add a second file with the same title. Its screens (Menu bar, Caps Lock notice, System settings) already match the picture spec, so the file was left unchanged.
- The picture description goes in marketing/screenshots/desktop/captures.json under the feature id, with "inUse": false. inUse is true only when the feature file links the PNG through `image`.
- The picture needs a person on a real Mac with Caps Lock on (cmd+shift+4 over the menu bar icon and the notice). The AI cannot capture the real menu bar icon.

## Tried and ruled out
- A second feature file with the same title: it would list the feature twice on the website.
- Setting `image` in the feature JSON before the PNG exists: scripts/check-product-docs.py then requires exactly one matching entry in docs/vopenkey-ai/product.json, so the check fails until that entry exists.

## Watch out
- Check UI labels in source before quoting them. The Settings toggle label is in Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m; the toast texts are in CapsLockToast.m.
- The feature-file screen names follow the app's own settings tabs ("Input settings", "System settings" = the Hệ thống tab), not macOS System Settings.
- The app configuration in a brief may list macOS only. The repo's marketing/product.json and CLAUDE.md require both macOS and Windows; positioning follows the repo.
