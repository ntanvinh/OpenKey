# Windows port: what was checked and what must still be tried on a real Windows

The Windows version (x86 and x64) got the features of the macOS app: suggestion bar, snippets, case list, word restore,
AI assistant (HTTP services), common abbreviations, plus a fix of the updater for x86. It was written on a Mac.

## Checked (on the Mac)

- `scripts/test-portable.sh`: the shared C++ code and its tests: suggestions, snippet search and list, JSON, AI protocol
  (addresses, keys, requests, streams, errors), case rules, abbreviation table, shortcut keys, word restore.
- `scripts/check-windows.sh`: every Windows source compiles with mingw-w64 for x86 and x64.
- `scripts/link-windows.sh`: the whole program links for x86 and x64 (no missing function or library).
- `.github/workflows/windows-build.yml`: builds with Visual Studio for x86 and x64 on every change (not yet run: the first push
  of the branch does it).

## NOT checked: nothing of the Windows program was run

Try each on Windows 10 or 11, x64 and x86 (a 32 bit Windows or WoW64):

1. Typing Vietnamese still works as before (Telex, VNI, other code tables), switch shortcut, smart switch, macros.
2. Suggestion bar (Settings > "Gợi ý, snippet và công cụ..." > on): it shows under the caret in Notepad, Word, Chrome, VS Code;
   Tab and Alt+1..5 type the word (with Alt held the application must not see Alt+Backspace); Esc hides (the same on macOS now); no bar in cmd and
   PowerShell; the bar fades when the pointer is on it; a macro waits on the bar.
3. Snippet window: Ctrl+Alt+S opens it, Vietnamese can be typed in the search box, Enter pastes into the program that had
   the keyboard, the clipboard of the user comes back (test with an image on the clipboard), the editor adds, edits, deletes.
4. Case list: select text, Ctrl+Alt+C, rows with previews, Alt+n and Enter replace the selection; empty selection says so.
5. Restore: type `restore` in Telex, Ctrl+Alt+R gives the keys back.
6. AI assistant: key saved and shown only as "saved", list of models, a request streams into the window, Esc stops, Ctrl+Shift+Enter
   inserts; a local Ollama needs no key; a wrong key shows the message; the key is not in the registry in the clear.
7. Dark and light theme, 100% and 150% DPI, a second monitor.
8. Update from a release zip on x86 and on x64 (`OpenKeyUpdate.exe` now replaces the file that is there and keeps the old one if
   the new one is missing).
9. The app is called "VOpenKey AI" everywhere a person sees it, on Windows too (OpenKey.rc, tray menu, message boxes, shortcut
   name `VOpenKey AI.lnk`, About window). Kept as they were because they are identifiers or credit: `OpenKey64.exe` / `OpenKey32.exe`
   / `OpenKeyUpdate.exe`, the registry key `SOFTWARE\TuyenMai\OpenKey` and the "OpenKey" start-up entry, the clipboard format,
   github URLs, the licence headers. Check that nothing visible still says "OpenKey" (title bars, the main window, the About window).

Automatic version of most of this list: `scripts/windows-ui-test.ps1`, see docs/windows-testing.md.

Seen working on a real Windows (CI, Windows Server 2025, x86 and x64, 2026-10-25): program starts, Telex "Việt Nam", suggestion bar and
Esc, snippet window, case list on a selection, AI window with the selection copied in. Still to try by hand: the rest of the list above
(real browsers, Word, DPI 150%, dark theme, Alt+n accept, restore shortcut, a real AI request, update from a zip).
