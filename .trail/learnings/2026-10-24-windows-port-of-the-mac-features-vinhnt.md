---
title: "Windows port of the Mac features: design, checks, what is not verified"
author: Vinhnt
date: 2026-10-24
branch: master
cost: { minutes: 83, tokens: 800750 }
touches:
  - Sources/OpenKey/win32/OpenKey/OpenKey/AppDelegate.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.vcxproj
  - Sources/OpenKey/win32/OpenKey/OpenKey/SystemTrayHelper.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKeyUpdate/OpenKeyUpdate.cpp
  - Sources/OpenKey/win32/README.md
  - ".github/workflows/windows-build.yml"
  - Sources/OpenKey/engine/AIProtocol.cpp
  - Sources/OpenKey/engine/AIProtocol.h
  - Sources/OpenKey/engine/CaseTransform.cpp
---

## Decided
- Pure Win32/C++ (no new toolkit), same style as the old code. New features live in Sources/OpenKey/win32/OpenKey/OpenKey (SuggestionBar/Controller, SnippetPalette/Editor/Service, CaseBar, AIAssistant/AISettingsDialog/AIClient, FeaturesDialog, FeatureActions, ShortcutField, TextInserter) and everything portable moved to engine/ with tests: MiniJson, SnippetStore, CaseTransform (Unicode data comes from a `Unicode` object: CoreFoundation in the test, LCMapStringEx/NormalizeString on Windows), AIProtocol (codes and details only, the Vietnamese sentences are made in win32/AIText.cpp), MacroPresets.
- Shortcuts and actions never run inside the keyboard hook: the hook posts to FeatureActions' own message-only window. Text goes in by Ctrl+V with the user's clipboard restored (TextInserter). A shortcut's modifiers are released/restored around typing from the hook (releaseHeldModifiers) and Ctrl+C/Ctrl+V are sent only after the keys are up (runWhenKeysReleased), or Alt+2 becomes Alt+Backspace and Ctrl+Alt+C becomes Ctrl+Alt+C.
- Keys: Tab / Alt+1-5 accept, Esc hides the bar (Alt+Tab is Windows'). API keys: DPAPI blob in HKCU\SOFTWARE\TuyenMai\OpenKey (AIKeyStore). Feature settings use the variable name as the registry name (APP_SET_DATA convention). Defaults Ctrl+Alt+S/C/R/A.
- Ported: suggestions, macro confirm, snippets, case list (shortcut only), word restore shortcut, AI assistant (OpenAI/Gemini/Anthropic protocols), macro presets, x86 fix of OpenKeyUpdate. Windows already had auto update (version.json + OpenKeyUpdate.exe).

## Tried and ruled out
- Not ported: agent CLIs (codex/claude/agy), local AI installer (Ollama), picture generation, auto case list on selection, diagnostics log, Dictionary fallback spell checker. WinUI/WPF: needs a new toolchain and drops old Windows.
- Editing OpenKey.rc (UTF-16, rewritten by Visual Studio): a second Features.rc (ASCII) holds the dictionaries, default snippets and macro presets as RCDATA.

## Watch out
- Nothing was run on Windows. Mac checks: scripts/test-portable.sh, scripts/check-windows.sh (mingw syntax, x86+x64), scripts/link-windows.sh (full link). mingw needs _WIN32_WINNT=0x0A00 or Vista+ APIs are hidden; MSVC does not. Delete old .o files before linking or a failed compile still "links". The CI workflow windows-build.yml is the first real Visual Studio build.
- New win32 files with Vietnamese text need a UTF-8 BOM and wide literals: no /utf-8 flag, narrow literals are read in the machine's code page. engine/ files stay ASCII.
- docs/windows-port-checklist.md lists what must be tried by hand. Old Windows strings still say "OpenKey" (owner decides, CLAUDE.md).
