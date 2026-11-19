---
title: "Suggestion bar on a second screen: geometry and window placement verified by runs, AX of an active app on screens 1/2 still missing (2026-11-19)"
author: Vinhnt
date: 2026-11-19
branch: master
cost: { minutes: 7, tokens: 78972 }
touches:
  - Sources/OpenKey/macOS/ModernKey/SuggestionController.mm
---

## Decided
- Follow-up to "Suggestion bar on a second screen: cause not confirmed". With the Claude sandbox off, three throw-away probes were built outside the repo (in /private/tmp, nothing shown to the owner) and RUN on the owner's Mac. Results:
  1. Real screens: 3 (built-in 1800x1169 at 0,0; two externals above it at (0,1169) 1920x1080 and (1920,1169) 2560x1080). Probe imports CaretLocator.m (for the static CocoaRect) and calls the real [SuggestionPanel screenContaining:] and originForBarOfSize:line:visibleFrame:. 75 carets (5x5 grid on every screen, AX rect made from Cocoa and converted back) -> 0 bad: the bar is always on the caret's screen, inside it, round trip exact. The coordinate conversion, the screen choice and the placement are NOT the cause.
  2. Real SuggestionPanel window (alpha 0, never key, never shown, orderFrontRegardless + setFrameOrigin): window.screen and CGWindowList bounds follow the frame on all three screens, both for a fresh show and for a move from screen 0 while up (5 of 5). macOS honouring the frame is NOT the cause (collectionBehavior 0x151, level 3).
  3. Real CaretLocator on every app with a window (read-only, rectangles and booleans, no text; run twice, the second time after a 2 s warm-up because the first question sets AXManualAccessibility): the FRONT Electron app and iTerm2 give a caret and a field on screen 0 (canCheckText=1, textMatches=1). Chrome (screen 1, not active) gives focus AXWebArea, no caret, the whole page as field (on screen 1). Electron/Brave apps that are NOT front give no focused element at all, which does not matter because they get no keys.
- What is still unknown: what CaretLocator returns for an ACTIVE app with a focused text field on screen 1 or 2 (Chrome/Electron/native). That is the one thing left that can send the bar to screen 0: no caret and no field -> showNearPoint:[NSEvent mouseLocation], and the pointer is often left on the main screen while the owner types elsewhere. The "bar placed by ..." diagnostics line (SuggestionController.mm, uncommitted at the time of this note) tells source and both screens in one run.

## Tried and ruled out
- Reading the geometry again for a bug: nothing to find, the runs agree with the hand calculation of the first note.
- Judging Electron from a first AX question: a pid that was never asked before answers "(none)" until AXManualAccessibility has taken effect; always warm up before measuring.

## Watch out
- Probes that show windows must stay invisible or offscreen (owner rule, ui-tests-background): alpha 0 + ignoresMouseEvents + never key was used; never call -[SuggestionPanel show] in a probe, it fades the bar in.
- NSScreen.mainScreen is the primary screen here for a process without a key window; it is what screenContaining: falls back to when a point is on no screen.
- A fix must also reach CaseBarPanel.m (same screenContaining:) and the Windows SuggestionController.cpp, per the every-fix-on-all-platforms rule.
