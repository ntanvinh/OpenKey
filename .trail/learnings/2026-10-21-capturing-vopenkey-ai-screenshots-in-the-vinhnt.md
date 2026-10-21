---
title: "Capturing VOpenKey AI screenshots in the background (offscreen, no lldb)"
author: Vinhnt
date: 2026-10-21
branch: master
cost: { minutes: 6, tokens: 45382 }
touches:
  - marketing/features/ai-image-generation.json
  - marketing/features/ai-writing-assistant.json
  - marketing/features/contextual-word-suggestions.json
  - marketing/features/local-ai-setup.json
  - marketing/features/prompt-snippet-library.json
  - marketing/features/restore-accidental-typing.json
  - marketing/features/signed-in-ai-agents.json
  - marketing/features/smooth-vietnamese-typing.json
  - marketing/screenshots/desktop/01-ai-writing-assistant.png
  - marketing/screenshots/desktop/02-local-ai-setup.png
---

## Decided
- Owner rule (2026-10-21): capture in the background, never show windows or take focus. Settings: launch the uitest build with `open -n -g --env DYLD_INSERT_LIBRARIES=<dylib>`; the dylib swizzles orderFront/activate, parks windows at (-30000,-30000) and every 3 s writes `contentView.superview` via bitmapImageRepForCachingDisplayInRect to PNG (retina, looks right).
- Panels (AI assistant, snippet palette, local setup): small harness linking the ModernKey .o files, wrapped in a minimal .app that copies the built app's Resources (local-models.json needs mainBundle). Real Codex answers/images, no typed results. Point the Codex program setting at a neutral symlink so the Settings row does not show /Users/<name>.
- Pictures are 1136-1440 px wide; Settings is fixed 568 pt wide (page size pinned by preferredContentSize), so Settings shots are portrait.

## Tried and ruled out
- screencapture -l on offscreen windows: "could not create image from window".
- Widening/resizing the Settings window (AX, setStyleMask, setContentSize): no effect.
- lldb expr to drive UI: fragile (c++ exception breakpoint interrupts, hangs); defaults written before launch were lost once, setting via AISettings works.
- Features 7 and 8 as typed scenes: synthetic keys cannot reach the app, so only Settings pages were captured.

## Watch out
- DYLD_* is stripped by /usr/bin/nohup and env: export it in a subshell and exec the binary directly. Re-codesign (-s - --force) a harness copied over an old one, else exit 137.
- Feature JSON `orientation` was set to landscape although 4 pictures are portrait.
- Clean up: kill pids, defaults delete the uitest domains, lsregister -u, rm /tmp work dir.
