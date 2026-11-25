---
title: "AI settings: account row (login status + copy-paste login guide)"
author: Vinhnt
date: 2026-11-25
branch: master
cost: { minutes: 20, tokens: 106675 }
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
- 2026-11-25 owner: show login state and account by itself, with a login guide that is only copy and paste, per OS. Row "Tài khoản" under the program row (Mac SettingsWindowController aiReloadLogin, Windows AISettingsDialog showLogin/requestLogin).
- Only the program's own status command is run: `codex login status` (words on STDERR, "Logged in using ChatGPT", no email), `claude auth status` (JSON with email), agy has no command -> Unknown. Parsers: engine/AIAgent.cpp loginStatusFromOutput (Windows, tested in engine/tests) and AIAgentCLI.m loginFromOutput (Mac, tested in ai_agent_test.m).
- Never open ~/.codex/auth.json or other token files to get the Codex email: the privacy promise is "no tokens, no login files". Unknown/not understood is never shown as "signed out".
- Guide when not signed in: Mac "Sao chép lệnh" + "Mở Terminal" (Cmd+V); Windows "Sao chép lệnh" + "Mở PowerShell" (Ctrl+V). Re-checked on every return to the window while not signed in; 30 s throttle when signed in.
## Watch out
- Not seen on screen, Windows never run. agy test line 598 fails on clean HEAD too.
