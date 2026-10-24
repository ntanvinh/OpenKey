---
title: "Windows: one name VOpenKey AI, Esc hides the bar on all systems, automatic UI test"
author: Vinhnt
date: 2026-10-24
branch: master
cost: { minutes: 6, tokens: 647195 }
touches:
  - ".github/workflows/windows-build.yml"
  - CLAUDE.md
  - README.md
  - Sources/OpenKey/linux/README.md
  - Sources/OpenKey/macOS/ModernKey/OpenKey.mm
  - Sources/OpenKey/win32/OpenKey/OpenKey/AboutDialog.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/AppDelegate.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/ConvertToolDialog.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/MacroDialog.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/MainControlDialog.cpp
---

## Decided
- Owner (2026-10-24): "VOpenKey AI" on every desktop version, Windows included. Visible Windows strings (OpenKey.rc, tray menu, message boxes, shortcut name, About) were renamed; identifiers stay: OpenKey32/64.exe, OpenKeyUpdate.exe, registry key TuyenMai\OpenKey and its start-up entry, clipboard format, github URLs, licence headers. CLAUDE.md lists both.
- Esc hides the suggestion bar and still reaches the application, the same on Windows and macOS (macOS got it in OpenKey.mm before the Tab block). The older "Esc collides with apps" ruling is overturned by the owner for the sake of the same experience on all systems.
- Automatic testing on Windows: scripts/windows-ui-test.ps1 (SendInput into a WinForms text box, screenshots, exit code), run by the ui-test job of windows-build.yml, or over SSH in a logged-in session on a Windows VM (docs/windows-testing.md).

## Tried and ruled out
- Wine: no real low-level keyboard hooks. Running keyboard tests in an SSH session: there is no desktop there, use schtasks /it.

## Watch out
- The ui-test job has never run: whether windows-latest has an interactive desktop is unknown, the script says SKIP then and the job fails on purpose.
- A rename regex must skip file names, URLs, registry names and headers; check `git diff` after it.
