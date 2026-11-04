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

Added 2026-11-04 (third part: pictures with Codex), checked on the Mac only: `ai_agent_test` now also covers the sentence said to Codex, the
arguments with `--json`, `$CODEX_HOME`, the safe names of threads and which picture is the one of a run (9 mutations caught); every Windows
source compiles and the program links for x86 and x64 (it now needs `windowscodecs`).

Added 2026-11-04 (second part: the case list that comes up by itself, and the agent programs as the AI), checked on the Mac only: `ai_agent_test`
(the models the programs list, what is passed, how their output is read, the errors, and the Windows command line read back with the rules of
Microsoft; 10 mutations of AIAgent.cpp are caught), `ai_protocol_test` for the three new providers; every Windows source compiles and the program
links for x86 and x64.

Added 2026-11-04 (parity with the macOS 3.7.x changes), checked on the Mac only: `scripts/test-portable.sh` now also runs
`suggest_appearance_test` (the two transparency levels, same numbers as macOS), `app_exclusions_test` (what a program name is, how the
list is kept) and the new `spaceAdjustmentPending` checks in `suggest_test`; every Windows source compiles (`check-windows.sh`) and the
program links (`link-windows.sh`) for x86 and x64; `OpenKeyUpdate.cpp` compiles with mingw; the `.sha256` file of a real release
(v3.7.19) has the shape the updater reads and equals the SHA-256 of its zip.

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

10. Suggestion bar look and programs (added 2026-11-04): "Gợi ý, snippet và công cụ..." > "Trong suốt và chương trình tự tắt...": the two sliders
   change the bar that is up at once (0% fully drawn, the hover level always above the normal one and it follows when the normal level
   is raised past it), the check box and the list: "Thêm" with a typed name (`putty`, `C:\x\PuTTY.exe`, quotes), "Chọn chương trình..."
   (the file dialog), "Bỏ khỏi danh sách", "Khôi phục mặc định", an emptied list stays empty after a restart, the master switch off keeps
   the list but the bar shows in cmd.exe; the window fits a 1366x768 screen and the Trackbar controls work with the keyboard (arrows).
11. A suggestion chosen with Tab, then a closing mark (`.` `,` `)`...): the space is replaced by the mark (`xin.` and not `xin .`), a letter
   typed right after the mark gets a space first (`xin. Chao`); with Ctrl/Alt held nothing changes; on a layout with dead keys (US
   International, French) the typed character is still right and no accent is lost.
12. AI window: "Sao chép và đóng (Ctrl+Shift+C)" puts the answer on the clipboard and closes the window; when another program holds the
   clipboard the window stays and says so; the text pastes elsewhere with Ctrl+V.
13. About: under the version there are "Phát triển bởi: LSSoft - lssoft.io.vn" and "Liên hệ: lssoft.adm@gmail.com" lines; both links open
   the browser / the mail program; the lines are not cut off at 100% and 150% DPI.
14. Update (added 2026-11-04): a fresh install now looks for a new version by itself (15 seconds after the start, then every 6 hours, 10 minutes
   after a failed try) in a thread of its own: with the network cable out at logon the keyboard must not lag. Start the program at logon
   (task of the Task Scheduler: its current folder is the folder of Windows), announce a newer version in `version.json` and check that the
   question comes up, "Có" starts `OpenKeyUpdate.exe` from the program's own folder, the zip is checked against its `.sha256` (change one
   byte of the zip on a test server to see the refusal), the program comes back after the message. A program that cannot find
   `OpenKeyUpdate.exe` says so and stays open. NOTE: `OpenKeyUpdate.exe` is never replaced by an update (it is running), so the checks of
   its SHA-256 and the restart reach people who install from a new zip, not those who only update.

15. Case list that comes up by itself (added 2026-11-04): in Notepad, Word and Edge/Chrome drag over some words, double click one, Shift+click,
   Shift+arrows, Ctrl+A: the list shows under the selection after about a quarter of a second; Alt+1..Alt+9 apply a style (the text is
   replaced), Up/Down/Enter/Esc go to the program until the shortcut is pressed (then the list takes them); another key, a click elsewhere,
   the wheel, another program, 20 seconds: it goes away; the clipboard is never touched while it is up (put an image on it first). Nothing
   shows in cmd.exe / Windows Terminal, in a password field (a web page's too), in the settings windows, or for a program that does not
   expose its text (the shortcut still works there). Switched off in "Gợi ý, snippet và công cụ...": no list, no UI Automation call.
   Watch for: a list that comes up while only clicking, selecting files in Explorer, or typing fast; keys lagging while it is up.
16. Codex, Claude Code and Antigravity as the AI (added 2026-11-04, nothing of it was ever run on Windows; the paths and the flags of the Windows
   builds of these programs are guesses taken from macOS): Cài đặt AI > "Codex CLI": the program is found (PATH, `%APPDATA%\npm`,
   `%USERPROFILE%\.local\bin`...) or "Chọn..." works; "Tải danh sách" fills the model box (Codex: `codex debug models`, fast; Antigravity:
   `agy models`, several seconds); the level box follows the model; a request streams into the assistant window; Esc stops it and no
   `codex.exe` / `node.exe` is left in Task Manager (job object); signed out gives the sentence with `codex login`; a wrong model name
   says so; "Claude Code CLI" with `claude.cmd` says it needs the .exe, with `claude.exe` works; Antigravity says its prompt limit for
   a 40,000 character selection; the folder `%TEMP%\VOpenKey-agent-*` is gone after each request; a request that runs 10 minutes is
   stopped. Running as Administrator: the programs run elevated too, so they look at the profile of that account (a different admin
   account has no login for them).

17. Pictures with Codex (added 2026-11-04, never run on Windows): with "Codex CLI" chosen, "Tạo ảnh (Ctrl+Alt+Enter)" is on (off for the other
   services and while a request runs); an empty box says to describe the picture; ask for "một con mèo màu cam": about 20 to 40 seconds,
   the seconds are counted, Esc stops it and kills Codex (Task Manager); the picture appears in the place of the answer box, as large as fits
   without being blown up, on the field colour in light and dark theme, and follows the size of the window; a click opens it in the program of the
   user for PNG; "Lưu vào Downloads" makes `VOpenKey AI <date>.png` there and never over a file; "Hiện file ảnh" opens Explorer with the file
   chosen; Ctrl+Shift+C puts a bitmap (and a "PNG") on the clipboard and closes: paste in Paint (bitmap) and in Word/Teams (PNG keeps
   transparency); Ctrl+Shift+Enter pastes into the program that was in front and the clipboard of the user comes back (test with text on
   it); a transparent PNG shows on white; Codex that makes no picture says so with what it said; `%CODEX_HOME%` set elsewhere is found;
   Settings > AI > Codex CLI shows "Lệnh tạo ảnh" and "Dùng lệnh mặc định" and keeps an edited sentence after a restart.
   Check the path `generated_images\<thread id>\*.png` on the real Windows build of Codex: it is taken from macOS.

Automatic version of most of this list: `scripts/windows-ui-test.ps1`, see docs/windows-testing.md.

Seen working on a real Windows (CI, Windows Server 2025, x86 and x64, 2026-10-25): program starts, Telex "Việt Nam", suggestion bar and
Esc, snippet window, case list on a selection, AI window with the selection copied in. Still to try by hand: the rest of the list above
(real browsers, Word, DPI 150%, dark theme, Alt+n accept, restore shortcut, a real AI request, update from a zip).
