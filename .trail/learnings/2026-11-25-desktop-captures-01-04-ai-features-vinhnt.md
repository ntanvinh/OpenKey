---
title: "Desktop captures 01-04 (AI features) via a ModernKey-linked harness, 2026-11-25"
author: Vinhnt
date: 2026-11-25
branch: master
cost: { minutes: 19, tokens: 148109 }
touches:
  - README.md
  - Sources/OpenKey/engine/AIAgent.cpp
  - Sources/OpenKey/engine/AIAgent.h
  - Sources/OpenKey/engine/tests/ai_agent_test.cpp
  - Sources/OpenKey/macOS/ModernKey/AIAgentCLI.h
  - Sources/OpenKey/macOS/ModernKey/AIAgentCLI.m
  - Sources/OpenKey/macOS/ModernKey/AIClient.m
  - Sources/OpenKey/macOS/ModernKey/AIProvider.m
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/tests/ai_agent_test.m
---

## Decided
- Rebuilt a harness outside the repo: Debug build with bundle id vn.io.lssoft.vopenkey.uitest into build/capture, harness.m (plain ObjC, NOT .mm: AIAgentCLI.h uses a property named `template`) linked with every .o except main.o, wrapped in a minimal .app (own bundle id, LSUIElement, Resources copied from the built app, ad-hoc codesigned), windows at (-30000,-30000), rendered with bitmapImageRepForCachingDisplayInRect on contentView.superview.
- AI scenes use AIAssistant shared with offscreenForTesting=YES, AISettings.setProgram pointing at a neutral symlink to the real codex/claude (the VApp Manager ai-gate wrapper in PATH refuses `codex exec` without -m), then presentWithSelection + ask / askForImage. Real answers and a real Codex image (one quota use).
- Document window + panel composed side by side on a transparent canvas; the document is clipped to rounded corners because the frame view renders square.
- The app UI is Vietnamese only, so captures.json says language vi although typed text is US English.

## Tried and ruled out
- Running the harness in the foreground tool call: exit 137 once; run with nohup and poll.
- Waiting for the local-setup "machine busy" warning to go away: the host stayed at 100-170% CPU, kept the honest state.

## Watch out
- AILocalSetupController advisor reads real CPU load; capture when the Mac is idle.
- Delete the defaults domain vn.io.lssoft.vopenkey.capture afterwards; harness lives in /tmp and is gone.
