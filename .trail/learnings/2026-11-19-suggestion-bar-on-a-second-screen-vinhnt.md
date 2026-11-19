---
title: "Suggestion bar on a second screen: cause not confirmed, placement diagnostics added (2026-11-19)"
author: Vinhnt
date: 2026-11-19
branch: master
cost: { minutes: 5, tokens: 139342 }
touches:
  - Sources/OpenKey/macOS/ModernKey/SuggestionController.mm
  - scripts/dev.sh
---

## Decided
- Bug report (2026-11-19, owner): typing on another screen, the suggestion bar still shows only on the main screen; it must always be under the place being typed.
- No fix yet: the cause is not confirmed and it cannot be reproduced in the Claude sandbox (NSScreen.screens.count is 0 there). Added only a diagnostics line in SuggestionController.mm (logPlacement:line:location:, Debug builds only, coordinates only, written when the source or one of the two screen indexes changes): source (caret/field/mouse), the line, the bar frame, the screen index of each, what the window itself says, the raw caret and field rects, and every NSScreen frame. Compiled with clang -fsyntax-only (exit 0); NOT run.
- The owner's displays (~/Library/Preferences/ByHost/com.apple.windowserver.displays.*.plist): built-in 1800x1169 at (0,0) is the primary; saved layouts have an external 1920x1080 at (0,-1080) (above), a 2560x1080 at (1920,-1080) (above and to the right) and a 1366x1024 at (1800,0) (right). So Accessibility gives negative y on a screen above the main one.

## Tried and ruled out
- By hand (not by a run), with those layouts: CaretLocator CocoaRect (primary height minus y minus h), SuggestionPanel screenContaining: (NSPointInRect on screen.frame) and originForBarOfSize:line:visibleFrame: put a bar for a caret on the screen above onto that screen, also near its bottom edge (it flips above the line). The geometry looks right, so the suspects are runtime ones.
- Remaining suspects, in the order the log will tell apart: (1) the source is "field" or "mouse" (the application gives no caret rect; the mouse pointer can be on the other screen); (2) the line is on no screen (screenContaining: falls back to [NSScreen mainScreen], which clamps the bar into that screen); (3) the frame is on the right screen but macOS shows the window on the main one (collectionBehavior CanJoinAllSpaces|Stationary|FullScreenAuxiliary, level NSPopUpMenuWindowLevel).

## Watch out
- SuggestionPanel.m is compiled alone by run-suggestion-panel-test.sh, without Diagnostics.m: do not put VOKDiag in it (link error); log from the controller.
- CaseBarPanel.m has the same screenContaining: code, so the case bar will have the same bug. Fix both, and Windows (SuggestionController.cpp, classicCaret and its siblings) per the every-fix-on-all-platforms rule once the cause is known.
- Read the log with: grep "bar placed by" ~/Library/Logs/VOpenKey/diagnostics.log (needs a Debug build from scripts/dev.sh; the sandbox cannot install it into ~/Applications).
