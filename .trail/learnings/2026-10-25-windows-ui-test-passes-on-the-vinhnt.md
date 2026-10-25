---
title: Windows UI test passes on the CI runner (x86 and x64)
author: Vinhnt
date: 2026-10-25
branch: windows-port
cost: { minutes: 34, tokens: 717251 }
touches:
  - docs/windows-port-checklist.md
  - docs/windows-testing.md
  - scripts/windows-ui-test.ps1
  - Sources/OpenKey/win32/OpenKey/OpenKey/AIAssistant.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.cpp
  - ".github/workflows/windows-build.yml"
  - Sources/OpenKey/engine/AIProtocol.cpp
  - Sources/OpenKey/engine/ConvertTool.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/SnippetEditor.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/SnippetPalette.cpp
---

## Decided
- windows-latest (Server 2025) has an interactive desktop: scripts/windows-ui-test.ps1 types with SendInput into a WinForms box and screenshots; 9/9 steps pass for x86 and x64 (run 40193303430 of ntanvinh/OpenKey, branch windows-port). Use `gh ... -R ntanvinh/OpenKey` (the default repo of gh here is the upstream tuyenvm/OpenKey).
## Tried and ruled out
- Test window inside powershell.exe: terminals are excluded from the suggestion bar, so the bar never showed; the script re-runs itself from a renamed copy of powershell.exe.
## Watch out
- PowerShell is case-insensitive ($vk hid $VK); a $null for a string parameter becomes ""; a mouse pointer over the case list chooses its row; dictionaries are loaded before the hooks are installed (the hook thread was blocked otherwise); the first CI build also found std::min/max vs windows.h macros and an unspecified evaluation order (gcc vs clang).
