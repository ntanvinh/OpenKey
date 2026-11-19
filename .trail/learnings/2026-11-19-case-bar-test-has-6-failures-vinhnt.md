---
title: "case_bar_test has 6 failures on a clean HEAD (auto-show after double click, shift+click, shift+arrows, cmd+A), 2026-11-19"
author: Vinhnt
date: 2026-11-19
branch: master
cost: { minutes: 6, tokens: 19958 }
touches:
  - Sources/OpenKey/macOS/ModernKey/CaseBarPanel.h
  - Sources/OpenKey/macOS/ModernKey/CaseBarPanel.m
  - Sources/OpenKey/macOS/ModernKey/SuggestionController.mm
  - Sources/OpenKey/macOS/tests/run-case-bar-test.sh
  - Sources/OpenKey/macOS/tests/case_bar_colors_test.m
---

## Decided
- Running run-case-bar-test.sh on a clean copy of HEAD (git archive, plus the QuartzCore link fix) gives the same 6 failures as with the colour change: case_bar_test.m lines 207, 208, 214, 225, 230, 235 ("a double click shows it", "shift+click shows it", "shown once it stopped", "and shows it again", "⌘A shows it", clipboard check). So they are not caused by the veil / opaque text change; case_transform_test and case_bar_colors_test pass.
- Cause of the 6 failures not investigated: all are the automatic show after a selection (a timed path, Spin(0.45..0.6)), none touches drawing.

## Tried and ruled out
- Blaming the colour change: ruled out by the identical result on HEAD.

## Watch out
- Suspects to check first: the machine state while the test runs (three screens, Other() picking an app, the screen locked) and the timings in the test; the cold build takes several minutes, run it in the background with a long timeout (the default 10 min kills it).
