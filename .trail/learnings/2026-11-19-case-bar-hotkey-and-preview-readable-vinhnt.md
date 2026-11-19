---
title: "Case bar: hotkey and preview readable on any backdrop (veil + opaque text, 2026-11-19)"
author: Vinhnt
date: 2026-11-19
branch: master
cost: { minutes: 19, tokens: 132874 }
touches:
  - Sources/OpenKey/macOS/ModernKey/CaseBarPanel.h
  - Sources/OpenKey/macOS/ModernKey/CaseBarPanel.m
  - Sources/OpenKey/macOS/ModernKey/SuggestionController.mm
  - Sources/OpenKey/macOS/tests/run-case-bar-test.sh
  - Sources/OpenKey/macOS/tests/case_bar_colors_test.m
---

## Decided
- Owner request (2026-11-19): the hotkey and the preview of the case bar must be readable whatever is behind the menu. Cause: they used secondaryLabelColor (alpha 0.50-0.55) on a translucent NSVisualEffectMaterialMenu, so legibility depended on the backdrop (measured: 3.55:1 over black, 3.92:1 over white; the old note's hypothesis (1) of 2026-11-04 is therefore real).
- Fix (macOS, CaseBarPanel.m): a veil (windowBackgroundColor, alpha 0.8, drawn first in CaseBarListView drawRect) bounds what the backdrop can do; hotkey and preview use an opaque grey chosen against it (light 0.22, dark 0.80); the lit row's hotkey and preview are opaque too; the hotkey is Medium weight. The attribute methods moved to class methods of CaseBarPanel (+nameAttributes: +hintAttributes: +previewAttributes: +secondaryTextColor +veilColor) so the test reads the colours the list really draws.
- Test: tests/case_bar_colors_test.m (in run-case-bar-test.sh, no window shown): name, hotkey and preview over black and over white (they bound every other backdrop), light and dark, 4.5:1 least, plus "opaque". Result: worst 5.43:1. Red-green done on a copy: with secondaryLabelColor it fails 10 checks (3.55:1).
- Windows needs nothing: CaseBar.cpp draws on an opaque background (FeatureTheme.h 249 / 44) with 96 / 176 grey = 5.97:1 and 6.4:1.

## Tried and ruled out
- [[NSColor windowBackgroundColor] colorWithAlphaComponent:] for the veil: it FIXES the colour to the appearance that is current when it is made (here dark, 0.118, in light mode: dark veil under dark text). Found by the test, not by eye. A veil must be a dynamicProvider colour that resolves with performAsCurrentDrawingAppearance.
- A lower veil alpha (0.7): dark mode would need text near white (0.92) to keep 4.5:1; 0.8 balances it.

## Watch out
- run-case-bar-test.sh did not link before (SuggestionPanel.m uses CAMediaTimingFunction, QuartzCore was missing in the final link): fixed; a cold run takes ~7 minutes, run it in the background.
- Not changed, same pattern: SuggestionPanel.m hint still uses secondaryLabelColor (the bar has the owner's transparency setting); and a lit row with a light accent (yellow, orange, green) has white text on it, which is low contrast. Both are open decisions for the owner.
- A name like Picture clashes with ApplicationServices (Quickdraw); BSD sed has no \b (use perl).
