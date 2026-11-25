---
title: "AI settings: simple choices only (no prompts, no commands, model list automatic)"
author: Vinhnt
date: 2026-11-25
branch: master
cost: { minutes: 10, tokens: 183682 }
touches:
  - README.md
  - Sources/OpenKey/macOS/ModernKey/AIAgentCLI.m
  - Sources/OpenKey/macOS/ModernKey/AIClient.m
  - Sources/OpenKey/macOS/ModernKey/AIProvider.m
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/win32/OpenKey/OpenKey/AISettingsDialog.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AIText.cpp
  - Sources/OpenKey/win32/README.md
  - docs/windows-port-checklist.md
---

## Decided
- 2026-11-25 owner: Settings > AI shows no system prompt box, no image prompt box, no program path/"Tìm lại", no "Tải danh sách" button, no shell commands. Defaults apply; values saved by older builds still apply (AISettings untouched).
- Program row (Codex/Claude/agy) appears only when the program is NOT found (with "Chọn…"); found = row hidden, re-checked when the window gets key.
- Model of a program = popup "Tự động (khuyên dùng)" + what the program lists; services keep the typable combo. Lists refresh by themselves (SettingsWindowController aiShouldAskModelsOf: 30 s throttle; Windows requestModels in AISettingsDialog.cpp). Silent on failure; "Kiểm tra kết nối" tells why.
- Error texts no longer point to the removed button; the login error keeps `codex login` (tests rely on it, it is the only way to tell the user).
## Watch out
- Not seen on screen: only compiled (xcodebuild Debug, check-windows.sh) and ai tests run. run-ai-agent-test.sh has 1 failure (agy locate, line 598) on clean HEAD too. Run the zsh test scripts with zsh, not bash.
