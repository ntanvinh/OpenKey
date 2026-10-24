---
title: Suggestion bar fades when the pointer hovers it
author: Vinhnt
date: 2026-10-24
branch: master
cost: { minutes: 13, tokens: 47224 }
touches:
  - Sources/OpenKey/macOS/ModernKey/SuggestionPanel.m
  - scripts/dev.sh
---

## Decided
- SuggestionPanel (ignoresMouseEvents=YES) fades to alpha 0.15 (kHoverAlpha, 0.15 s ease-out, instant with Reduce Motion) while the pointer is inside its frame. It learns the pointer from a global NSEvent monitor (mouse moved/drag/scroll, no permission needed), installed in show and removed in orderOut:.
- "Temporarily off" already exists: status-menu item toggleSuggestion (SuggestionEnabled). No new switch was added.

## Tried and ruled out
- Making the panel take mouse events / tracking areas: it would steal clicks and focus from the app being typed in.
- Esc or a global hotkey to hide the bar: not done, Esc collides with apps; offered to the owner.

## Watch out
- QuartzCore must be imported in SuggestionPanel.m for CAMediaTimingFunction.
- Do not run scripts/dev.sh to check a compile (it bumps the version and installs/opens the app); use xcodebuild -derivedDataPath build/check CODE_SIGNING_ALLOWED=NO.
- Hover was only compiled, not seen in a real app.
