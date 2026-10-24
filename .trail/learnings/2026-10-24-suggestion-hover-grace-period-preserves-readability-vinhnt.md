---
title: Suggestion hover grace period preserves readability
author: Vinhnt
date: 2026-10-24
branch: master
touches:
  - Sources/OpenKey/macOS/ModernKey/SuggestionPanel.m
  - Sources/OpenKey/macOS/tests/run-suggestion-panel-test.sh
  - Sources/OpenKey/macOS/tests/suggestion_panel_test.m
  - scripts/dev.sh
---

## Decided
- SuggestionPanel keeps full opacity for 1.2 seconds of pointer overlap before fading to 0.15 over 0.25 seconds. Repeated show calls and pointer movement inside the bar preserve the pending deadline. Exiting or hiding cancels the timer; reopening starts fresh.
- A weak timer callback rechecks visibility and the current pointer position. Reduce Motion preserves the reading delay but applies opacity changes without animation.
## Tried and ruled out
- Restarting the timer on each suggestion update would keep the bar opaque indefinitely during continuous typing.
- trail check incorrectly flags the hover-delay branch as bringing back panel mouse events. ignoresMouseEvents remains YES, and only the existing global NSEvent monitor observes movement; there are no tracking areas or event handlers on the panel.
## Watch out
- Objective-C implementations are not indexed by the current trail graph. The standalone suggestion_panel_test uses a real offscreen panel and simulated mouseLocation; it does not prove the appearance of the installed app.
- Use xcodebuild with CODE_SIGNING_ALLOWED=NO for compile checks, not scripts/dev.sh which installs and opens the app.
