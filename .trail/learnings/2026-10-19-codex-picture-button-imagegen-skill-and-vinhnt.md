---
title: Codex picture button (imagegen skill) and the running light round the answer
author: Vinhnt
date: 2026-10-19
branch: master
cost: { minutes: 29, tokens: 214604 }
touches:
  - CHANGELOG.md
  - README.md
  - Sources/OpenKey/macOS/ModernKey/AIAgentCLI.h
  - Sources/OpenKey/macOS/ModernKey/AIAgentCLI.m
  - Sources/OpenKey/macOS/ModernKey/AIAgentRunner.h
  - Sources/OpenKey/macOS/ModernKey/AIAgentRunner.m
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.h
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.m
  - Sources/OpenKey/macOS/ModernKey/AIClient.h
  - Sources/OpenKey/macOS/ModernKey/AIClient.m
---

## Decided
- "Tạo ảnh" (AIAssistant imageButton, ⌥⌘↩) is enabled only for codex-cli (AIAgentCLI canMakeImages). The request is `Use $imagegen skill to create picture {prompt}, follow our design system.` (AISettings imagePrompt, editable in Settings > AI "Lệnh tạo ảnh"): without the skill named Codex makes poor pictures; model and level are the ones of the window.
- Verified for real (one run, gpt-6-luna low): `codex exec --json` with all our lock-down flags still makes the picture. PNG in $CODEX_HOME/generated_images/<thread_id>/exec-<uuid>.png, ~25 s, ~110k input tokens. The JSONL has only thread.started{thread_id}, agent_message items, turn.completed: no image event, no path in the final message. So the path is built from the sanitized thread_id; fallback is the newest picture modified since the run started.
- The picture is shown in the answer card (imageView), copied as PNG+TIFF, inserted with SnippetInserter insertImageData: (⌘V, clipboard restored). The file stays in Codex's folder and the window says where.
- The light round the answer is a dashed stroke whose lineDashPhase is animated (even speed on long and short sides, measured: one lap 2.6 s), a thin track ring under it, 1.5 pt line + 4 pt halo. Not a rotating conic gradient (that lit the whole ring and looked thick).
## Tried and ruled out
- A 2 s leeway in the "newest picture since start" fallback: it returned the picture of the previous run when the new one failed. No leeway.
- Showing the agent's narration while the picture is made: ignored, the canned words of the wait are shown instead.
## Watch out
- In an empty cwd with --ignore-user-config Codex cannot see any design system ("follow our design system" is only a hint).
- zsh does not word-split $VAR: link frameworks with the flags written out.
