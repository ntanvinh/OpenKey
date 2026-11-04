---
title: "Windows: auto case list and Codex/Claude Code/Antigravity as the AI (2026-11-04)"
author: Vinhnt
date: 2026-11-04
branch: master
cost: { minutes: 28, tokens: 438477 }
touches:
  - Sources/OpenKey/engine/AIProtocol.cpp
  - Sources/OpenKey/engine/AIProtocol.h
  - Sources/OpenKey/engine/SuggestSession.h
  - Sources/OpenKey/engine/tests/ai_protocol_test.cpp
  - Sources/OpenKey/engine/tests/suggest_test.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AIAssistant.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AIClient.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AIClient.h
  - Sources/OpenKey/win32/OpenKey/OpenKey/AISettings.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AISettings.h
---

## Decided
- 2026-11-04, owner chose: ship 3.7.21 with Windows included (the owner releases, nothing was published here), then port two more macOS features to Windows: the case list that comes up by itself and Codex / Claude Code / Antigravity as the AI.
- Auto case list (CaseBar.cpp): selection read with UI Automation TextPattern on a worker thread, never Ctrl+C. Triggers: drag, double click, Shift+click (mouse hook: CaseBar::mouseDown(point, left), mouseUp, scrolled) and Shift+arrows/Home/End/PageUp/PageDown, Ctrl+A (keyboard hook now calls CaseBar::keyDown for every key while vCaseBarAuto, default ON like macOS). Debounce 150 ms after mouse, 350 ms after keys, auto list lifetime 20 s, takes Alt+digits only until the shortcut is pressed (toggle upgrades it to explicit). Skipped in terminals (SuggestionController::defaultExcludedApps, not the editable list), password fields (UIA IsPassword + engine namesASecret), our own windows.
- Agent CLIs: portable engine/AIAgent.{h,cpp} mirrors AIAgentCLI.m (models from codex debug models / agy models / fixed Claude list, resolve() model+level, flags, stream-json and codex json parsers, error mapping to vai::ErrorCode Login/NoProgram/Effort/OldProgram/Timeout/TooMuch plus the old ones, Windows command line quoting with a reference parser in the test). Protocol::Agent and three providers in AIProtocol (providers().size() is now 12, ai_protocol_test updated). Windows AIAgentRunner: CreateProcess suspended, job object with KILL_ON_JOB_CLOSE, handle-list attribute so only the three pipes are inherited, writer thread for stdin, two reader threads, 10 min and 2 MB limits, empty private temp folder, drain deadline then job kill. AIClient forwards generate/listModels/cancel for Protocol::Agent and shares request ids (AIClient::newRequestId), so AIAssistant is unchanged except a label. AISettingsDialog got layout() because a program has a file and a level, a server has an address and a key.
- A .cmd script runs through cmd.exe /d /s /c only when safeForCommandShell (no & | < > ^ % ! or line break). Codex args are safe; Claude --system-prompt is two paragraphs and Antigravity carries the prompt in argv, so those need .exe.

## Tried and ruled out
- Putting the prompt through cmd.exe unescaped for scripts: cmd ends a command at a line break and expands % and ^, a user text in argv would be an injection.
- Reading the selection with Ctrl+C for the auto list: it would send Ctrl+C (interrupt in a terminal) after every selection; macOS never does that either.
- Running anything on Windows: not possible here. Mac checks: test-portable (ai_agent_test, 10 mutations of AIAgent.cpp caught), check-windows (mingw x86+x64), link-windows (x64 18107749 bytes, x86 15254746 bytes).

## Watch out
- Never run on Windows: the install folders and file names of these programs on Windows are guesses from macOS (npm shim codex.cmd, claude.exe in .local\bin, agy.exe or .cmd). The flags are the macOS verified ones; the Windows builds may differ.
- near is a macro of windows.h (a variable named near does not compile, MSVC too).
- The app often runs elevated: the agent programs inherit that, so they look at the profile of that account.
- Picture generation (Codex imagegen) and the Ollama installer are still macOS only.
- The UI Automation TextPattern of Chrome needs its accessibility mode (a UIA client switches it on, with a cost); untested.
