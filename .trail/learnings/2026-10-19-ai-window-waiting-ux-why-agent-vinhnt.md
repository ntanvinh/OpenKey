---
title: "AI window: waiting UX, why agent CLIs are slow, offscreen UI tests"
author: Vinhnt
date: 2026-10-19
branch: master
cost: { minutes: 30, tokens: 158135 }
touches:
  - CHANGELOG.md
  - README.md
  - Sources/OpenKey/macOS/ModernKey/AIAgentCLI.h
  - Sources/OpenKey/macOS/ModernKey/AIAgentCLI.m
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.h
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.m
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/macOS/tests/ai_agent_test.m
  - Sources/OpenKey/macOS/tests/ai_assistant_test.m
---

## Decided
- The wait of an agent CLI is time to first text, decided by thinking level + the program's own start: agy has ~6-7 s fixed (auth, loadCodeAssist x3, fetchAvailableModels, 2 model calls), flash low 9.5 s / medium 16.5 s; claude haiku low 3.7 s but medium 40.8 s; codex 5-7 s. Defaults stay at the lowest level; the window must not hide that a higher level costs time (speed notes on menu items, "Hỏi lại ở mức Thấp" after 8 s at a level above low).
- Waiting UI lives in AIProgress (AIGlowView conic light round the answer card, AIShimmerLabel, AIPulseView, AIProgressText sentences by second). AIAssistant.beginProgress/endProgress own it; cancelRequest, showFailure, completion and hide all end it. Gear button in the header (openSettingsButton) opens the AI settings at any time.
- UI tests never show a window: AIAssistant.offscreenForTesting (origin -30000, no key, no activation); VOK_UI_VISIBLE=1 for a real on-screen check. Run them as background tasks.
## Tried and ruled out
- CAGradientLayer.locations outside 0...1 (shimmer sweep from -0.3): invalid, drew nothing, the mask hid the text. Animate startPoint/endPoint instead.
- Editing a source in place for a mutation check and running the test in the foreground: a killed run left AIAssistant.m mutated. Use a backup + trap and run in the background, then cmp.
## Watch out
- The Xcode project did not link QuartzCore: new CALayer code compiled but failed at link; standalone test scripts need -framework QuartzCore too.
- run-tap-test.sh line 466 (case bar "XIN CHÀO") fails on a clean HEAD.
