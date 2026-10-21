---
title: Settings window follows macOS Settings conventions
author: Vinhnt
date: 2026-10-21
branch: master
cost: { minutes: 1, tokens: 45469 }
touches:
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - marketing/features/ai-image-generation.json
  - marketing/features/ai-writing-assistant.json
  - marketing/features/contextual-word-suggestions.json
  - marketing/features/local-ai-setup.json
  - marketing/features/prompt-snippet-library.json
  - marketing/features/restore-accidental-typing.json
  - marketing/features/signed-in-ai-agents.json
  - marketing/features/smooth-vietnamese-typing.json
  - marketing/screenshots/desktop/01-ai-writing-assistant.png
---

## Decided
Settings window (SettingsWindowController.m) already matched System Settings: toolbar tabs, cards, 44pt rows, 4-multiple spacing, fixed size, scroll when taller than screen. Only close button (no miniaturize), and a SettingsWindow subclass handles ⌘W because the app has no main menu.

## Tried and ruled out
Checked for a main menu/⌘W/Esc handlers: none in AppDelegate.m, so key equivalents must live in the window itself.

## Watch out
Not run in the real app, only `clang -fsyntax-only`. The first switch shows a focus ring on open (initial first responder); left as is, owner not yet asked.
