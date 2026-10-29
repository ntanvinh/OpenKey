# Windows port: what was checked and what must still be tried on a real Windows

The Windows version (x86 and x64) got the features of the macOS app: suggestion bar, snippets, case list, word restore,
AI assistant (HTTP services), common abbreviations, plus a fix of the updater for x86. It was written on a Mac.
Added 2026-10-29: the ready-made conversions of the AI window (14 buttons) and the donate window (VietQR and PayPal).

## Checked (on the Mac)

- `scripts/test-portable.sh`: the shared C++ code and its tests: suggestions, snippet search and list, JSON, AI protocol
  (addresses, keys, requests, streams, errors), case rules, abbreviation table, shortcut keys, word restore, the list and the
  request of the ready-made conversions (`ai_presets_test`), the donation data and the shape of the QR picture (`donation_info_test`).
- `windres` compiles `Features.rc` (with the new `RCDATA` presets and the `BITMAP` of the QR code) for x86 and x64, on a copy whose paths
  use `/` (the `\` paths of the file only work with the Windows resource compiler).
- That the QR picture says what the macOS code says: `Sources/OpenKey/macOS/tests/run-donation-test.sh` reads it back with `CIDetector`.
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
7a. Conversions in the AI window (Ctrl+Alt+A): 14 buttons under the box in 2 or 3 rows that follow the width of the window, none cut off at
   the minimum size, off while the box is empty; a click on "Lịch sự" with a text in the box asks at once (the box keeps its text, the
   button stays down), Ctrl+Enter asks the same again, typing a letter lifts the button; a poem says its rhymes were not checked; a tip
   shows what a button does; the Tab key reaches the buttons.
7b. Donate window (tray menu "Ủng hộ VOpenKey AI", or the button "Ủng hộ VOpenKey AI..." in "Gợi ý, snippet và công cụ...", next to "Cài đặt AI..."): the QR code is sharp (no blur, whole pixels
   per module) and a banking app reads it from the screen at 100%, 125%, 150% and 200% DPI; the window fits a 1366x768 screen at 100% and
   125% (at 150% on that size it may not: then make the QR smaller, see `px(190)` in `DonationDialog.cpp`); "Sao chép" puts the account
   number and the note on the clipboard; "Mở PayPal" opens the browser; "Tôi đã ủng hộ" shows the thanks and the tray item is gone the
   next time the menu opens; "Hoàn tác" brings both back; Esc closes; the tabs open on "Quốc tế" on a Windows that is not Vietnamese.
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
