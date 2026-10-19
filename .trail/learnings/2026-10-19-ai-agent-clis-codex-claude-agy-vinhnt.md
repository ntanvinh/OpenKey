---
title: "AI agent CLIs (codex, claude, agy) as the AI of the assistant"
author: Vinhnt
date: 2026-10-19
branch: master
cost: { minutes: 54, tokens: 838351 }
touches:
  - README.md
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.h
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.m
  - Sources/OpenKey/macOS/ModernKey/AIClient.m
  - Sources/OpenKey/macOS/ModernKey/AIProvider.h
  - Sources/OpenKey/macOS/ModernKey/AIProvider.m
  - Sources/OpenKey/macOS/ModernKey/AISettings.h
  - Sources/OpenKey/macOS/ModernKey/AISettings.m
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
---

## Decided
- Provider kind `AIProtocolAgentCLI` (codex-cli, claude-cli, agy-cli): no key, no address; code in AIAgentCLI (what each program is, flags, parsing, errors), AIAgentProcess (posix_spawn), AIAgentRunner (one request), branch inside AIClient so AIAssistant/Settings keep one call path.
- Programs are started with posix_spawn, NOT NSTask: NSTask turns every argv entry into NFD (decomposed Vietnamese, 25 bytes become 30). agy takes the prompt as an argument, Claude takes --system-prompt as one, so NSTask would hand them decomposed text. Tests compare with NSLiteralSearch because containsString: treats NFC and NFD as equal.
- Text-only lock per program: codex exec --ignore-user-config --ignore-rules -s read-only --disable shell_tool --ephemeral -C <empty private dir>; claude -p --safe-mode --tools "" --no-session-persistence --output-format stream-json --include-partial-messages --verbose; agy --output-format text -p <prompt>. Request text on stdin for codex/claude. Verified against the real programs (tests/run-ai-agent-e2e.sh, VOK_E2E=1).
- Models come from the programs: `codex debug models` (offline, ~80 ms, JSON with supported_reasoning_levels), `agy models` (stdout `id<TAB>name`, status line is on stderr), Claude has no list (aliases haiku/sonnet/opus/fable). Default = light model + lowest level: codex from catalog description words (token match, "mini" must not match "gemini"), claude haiku, agy the "flash" family. agy lists levels as separate models (gemini-3.8-flash-low/-medium/-high): grouped into one model with levels and resolved back to the variant id.
- GUI apps lack the shell PATH: programs are searched in ~/.local/bin, nvm, fnm, Homebrew... and the child PATH starts with the program's own folder (codex is `#!/usr/bin/env node`, node sits next to it in nvm).
## Tried and ruled out
- NSTask (NFD arguments, no process group). readDataToEndOfFile (a child that keeps the pipe open hangs forever): dispatch read sources + a 0.5 s drain deadline after exit.
- Deleting agy's conversation files after a request: its store is internal (db + brain/ + summaries), partial deletion is unsafe. agy has no flag to not save: `agy -p` keeps every request in ~/.gemini/antigravity-cli, so the dialog and Settings say so. `agy models` does not create a conversation.
## Watch out
- Tests: sandboxed shells cannot run the programs; `mktemp -d` ignores TMPDIR on macOS (the new runner passes a template). A stale .o after editing a .m made a test look broken: always rebuild through the run-*.sh script.
- run-tap-test.sh fails at line 466 (case bar, "XIN CHÀO") on a clean HEAD too: not caused by this feature.
- AIAgentCLI +setSearchDirectoriesForTesting: hides the real codex/claude/agy in assistant tests; without it "no AI connected" tests break on a Mac that has them.
