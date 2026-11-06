---
title: "Desktop captures 01-03: macros bar, remembered apps, writing settings via harness"
author: Vinhnt
date: 2026-11-06
branch: master
cost: { minutes: 11, tokens: 162528 }
touches:
  - docs/vopenkey-ai/product.json
  - marketing/features/ai-image-generation.json
  - marketing/features/ai-writing-assistant.json
  - marketing/features/contextual-word-suggestions.json
  - marketing/features/convert-vietnamese-encodings.json
  - marketing/features/custom-text-macros.json
  - marketing/features/flexible-vietnamese-input.json
  - marketing/features/keyboard-shortcuts.json
  - marketing/features/local-ai-setup.json
  - marketing/features/macos-menu-controls.json
---

## Decided
- Captured custom-text-macros (01), remember-input-settings-by-app (02), writing-controls (03) with an out-of-repo harness (/tmp/vok-capture/harness.mm) linked to the Xcode Debug objects (build with CODE_SIGNING_ALLOWED=NO into build/capture, all .o except main.o), isolated standardUserDefaults, windows parked at -30000, rendered via bitmapImageRepForCachingDisplayInRect.
- 01: type "ace" through vKeyHandleEvent (Telex) with addMacro("ace","anh chị em"), vMacroNeedsConfirm=1; vPeekMacro gives the text, real SuggestionPanel renders it, composited under the word in a sample document image.
- 02: real RememberedAppsController sheet (SetRememberedApp into isolated defaults) next to a sample Terminal window; English mode = OpenKey.mm skips the engine when vLanguage==0, so the harness must too.
- 03: SettingsWindowController reads toggles from defaults (Spelling, RestoreIfInvalidWord, ModernOrthography, UpperCaseFirstChar, InputMethod), not from globals: set them in the isolated suite before init. Output is portrait 1136 px (fixed 568 pt width), orientation set to portrait.

## Tried and ruled out
- Setting globals (vCheckSpelling...) to turn toggles on: Settings showed them off.
- Engine alone for English mode: vKeyHandleEvent still converts Telex; the language check lives in the tap.
- std::apply name clash: do not name a helper apply() in .mm files that include Engine.h.

## Watch out
- Harness is in /tmp, not the repo; rebuild it from this note if needed.
- Terminal window in 02 is a sample drawn by the harness, not Terminal.app.
