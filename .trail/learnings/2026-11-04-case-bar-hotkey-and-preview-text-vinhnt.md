---
title: "Case bar: hotkey and preview text invisible until hover (macOS), cause not confirmed"
author: Vinhnt
date: 2026-11-04
branch: master
cost: { minutes: 7, tokens: 170573 }
touches:
  - build/cbrepro/repro.m
  - build/cbrepro/repro2.m
---

## Decided
- Bug report (2026-11-04): sometimes the case bar shows with the hotkey column and the preview column not visible; hovering a row makes them appear. Only the name is readable.
- macOS only. Windows CaseBar.cpp draws an opaque background with fixed colours (FeatureTheme.h secondaryText 96 light / 176 dark), so it does not have this problem.
- In CaseBarPanel.m an unlit row draws the name with labelColor and the hotkey and preview with secondaryLabelColor (about 50% alpha); a lit row draws all three in white on the accent colour. The colour is the only difference between the text that is seen and the text that is not, so secondaryLabelColor is the main suspect. The panel background is NSVisualEffectMaterialMenu (translucent) and the list view does not allow vibrancy, so legibility depends on what is behind the panel, which would fit "sometimes". SuggestionPanel uses the same material and the same colour for its hint.
- No code was changed: the cause was not confirmed. Two competing hypotheses: (1) low contrast of secondaryLabelColor on the translucent material; (2) the first draw is broken and the hover redraw (needsDisplay on the whole list) fixes it. A screenshot taken while the bug shows tells them apart (text absent vs text faint).

## Tried and ruled out
- Capturing the real panel from a process started in the Claude sandbox: NSScreen.screens.count is 0, so no window is drawn (drawRect: never called, windowNumber -1, alpha stays 0) and CGWindowListCreateImage returns NULL. Nothing about WindowServer, blur or vibrancy can be checked there.
- CGWindowListCreateImage is marked obsolete in the macOS 15 SDK (compile error); it has to be called through dlsym.
- scripts run-case-bar-test.sh fails in the sandbox: mktemp -d lands in /var/folders (not allowed); a TMPDIR override needs approval.
- Earlier note that the panel flashed at origin 6,6 on the owner's screen was wrong: with no screens, visibleFrame is empty and showBelowRect clamps to 0 plus the 6 px margin.

## Watch out
- showBelowRect clamps the panel into the visible frame, so setFrameOrigin(-30000) before it is not enough to keep a panel off screen; park it after showing (as case_bar_test.m Park() does).
- Do not fix this with two changes at once (contrast and forced redraw): confirm which hypothesis is true first, on the owner's Mac.
- If a fix is made, apply the same reasoning to the suggestion bar hint (SuggestionPanel.m, secondaryLabelColor).
