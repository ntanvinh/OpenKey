---
title: "Windows port scoping: what exists and what is missing"
author: Vinhnt
date: 2026-10-24
branch: master
cost: { minutes: 1, tokens: 31374 }
touches:
  - Sources/OpenKey/win32/OpenKey/OpenKey.sln
  - ".github/workflows/release-windows.yml"
---

## Decided
Windows x86/x64 already build from the original OpenKey code (Sources/OpenKey/win32/OpenKey/OpenKey.sln, .github/workflows/release-windows.yml). The work is porting the macOS-fork-only features (suggestion bar, snippets, case bar, word restore, AI assistant, local AI, auto-update, diagnostics). The portable engine (Suggest, SnippetSearch, SuggestSession) is in Sources/OpenKey/engine. Proposed phasing: phase 1 typing and popups, phase 2 AI assistant, phase 3 local AI, agent CLIs and updater. Pure Win32/C++, matching the existing dialogs.
## Tried and ruled out
Nothing written yet. No code was changed. The user was asked for scope, verification method and UI toolkit.
## Watch out
No Windows toolchain on the Mac, so only the engine tests can run locally. The Win32 UI and hooks can only be checked through the windows-latest CI, which needs the user's approval to push.
