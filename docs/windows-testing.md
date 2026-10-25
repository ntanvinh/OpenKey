# Testing the Windows version without sitting at a Windows PC

Three levels, from cheap to real. An agent can do the first two on a Mac, and the third one wherever a Windows exists.

1. **On the Mac** (no Windows needed, runs in seconds to minutes). Proves the code compiles for x86 and x64 and links, and runs the
   shared C++ tests. Does not run the program.

       brew install mingw-w64
       scripts/check-windows.sh      # syntax of every Windows source, x86 + x64
       scripts/link-windows.sh       # the whole program links, x86 + x64
       scripts/test-portable.sh      # tests of engine/ and the pure parts of win32/

2. **GitHub Actions, windows-latest** (`.github/workflows/windows-build.yml`). Builds with Visual Studio for x86 and x64, then the
   `ui-test` job starts the real program and types into a real window (`scripts/windows-ui-test.ps1`): Telex gives "Việt Nam",
   the suggestion bar shows and Esc hides it, the snippet, case and AI windows open with their shortcuts, the case list changes a
   selection. It saves a screenshot per step as the artifact `ui-test-x86` / `ui-test-x64`.
   An agent starts it with `gh workflow run windows-build.yml --ref <branch>`, waits with `gh run watch`, reads the log with
   `gh run view --log` and looks at the pictures with `gh run download`. It needs the branch pushed, so the owner has to agree.
   Verified on 2026-10-25 (run 40193303430): the hosted runner (Windows Server 2025) has an interactive desktop, SendInput and
   screenshots work, and all 9 steps pass for x86 and x64. Lessons from getting there: PowerShell variables ignore case (a
   parameter `$vk` hid the table `$VK`), a `$null` passed to a string parameter of FindWindow becomes "" and matches no window,
   the test window must not live in powershell.exe (terminals are excluded from suggestions; the script re-runs itself in a renamed
   copy), and the mouse pointer must be out of the way (a pointer resting on the case list chooses its row). If the desktop is
   ever missing the script says SKIP, never PASS.

3. **A Windows machine or virtual machine** (Windows 11 in UTM or Parallels on the Mac, or any PC) with OpenSSH Server. Keyboard
   input only works in a logged-in desktop session, so the agent starts the script in that session, not in the SSH session:

       scp OpenKey64.exe scripts/windows-ui-test.ps1 user@windows:C:/vok/
       ssh user@windows "schtasks /create /tn vokui /sc once /st 00:00 /it /f /tr \"powershell -NoProfile -ExecutionPolicy Bypass -File C:\vok\windows-ui-test.ps1 -Exe C:\vok\OpenKey64.exe -Out C:\vok\shots > C:\vok\log.txt 2>&1\" && schtasks /run /tn vokui"
       ssh user@windows "type C:\vok\log.txt"; scp -r user@windows:C:/vok/shots .

   Windows 11 on ARM runs x64 and x86 programs too. This level is also where what the script cannot see (looks at 150% DPI, dark
   theme, Chrome, Word, games) is checked by an agent that looks at the screenshots.

Not possible: Wine (no real keyboard hooks, so the program cannot be tested there).
