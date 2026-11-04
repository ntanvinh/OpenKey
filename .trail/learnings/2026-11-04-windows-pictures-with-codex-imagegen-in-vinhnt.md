---
title: "Windows: pictures with Codex (imagegen) in the AI assistant (2026-11-04)"
author: Vinhnt
date: 2026-11-04
branch: master
cost: { minutes: 13, tokens: 933515 }
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
- 2026-11-04, owner chose to port Codex picture generation ("Tao anh") to Windows, after the agent CLIs. The engine (engine/AIAgent) holds the rules, tested by ai_agent_test (9 mutations caught): the sentence said to Codex (default "Use $imagegen skill to create picture {prompt}, follow our design system.", {prompt} replaced in one pass, no {prompt} = request after it, empty = default), imageArguments (the text arguments with --json at index 1), imageStandardInput (the request as it is, no rule about texts in front), codexHomeFolder, isSafeThreadId (1..80 of letters digits - _), isPictureFileName, choosePicture(threadId, entries, since, hasSince): newest picture in the thread folder, else newest written since the run started with NO leeway, else none. The directory listing is the platform (AIAgentRunner listPictures with FindFirstFile, links never followed).
- Windows: Codex only (Agent.canMakeImages). AIAgentRunner image mode (Run.image, Pump.silent keeps what Codex says in `spoken` for the "no picture" sentence), AIClient::generateImage / kMessageImage (ImageDone) so the assistant window has one more message, two new error codes NoPicture and BadPicture. The assistant window: button "Tao anh (Ctrl+Alt+Enter)" (WM_SYSKEYDOWN, Alt makes it a system key message), a child window class VOpenKeyAIPicture takes the place of the answer box, buttons Luu vao Downloads and Hien file anh on the label row, insert/copy handle the picture (TextInserter::insertPicture with the same snapshot/restore and history exclusion as for text; CF_DIB plus the registered PNG format). PictureFile decodes with WIC (any format Codex writes), lays transparency on white for the DIB, draws with StretchDIBits (never blown up). Settings > AI shows "Lenh tao anh" (AI.imagePrompt in the registry, the default is not kept) only for Codex.

## Tried and ruled out
- A portable directory finder in engine/: C++11 has no portable directory listing, so only the choice is shared and tested; the platform lists.
- AlphaBlend / msimg32 for transparency: the DIB is laid on white once, the window and the clipboard have no alpha to show it with.
- Encoding a non-PNG picture to PNG for the clipboard: only a PNG file is put on the clipboard as PNG, the others only as a bitmap.

## Watch out
- Never run on Windows: the folder generated_images\<thread id> of the Windows build of Codex and its CODEX_HOME are taken from macOS.
- Settings window height: it is as tall as a 1366x768 screen allows; the note of a program is sized from its text length and the image prompt box is 50 px, so do not add rows without removing height elsewhere.
- link-windows.sh now needs -lwindowscodecs; the vcxproj gets it from a pragma.
