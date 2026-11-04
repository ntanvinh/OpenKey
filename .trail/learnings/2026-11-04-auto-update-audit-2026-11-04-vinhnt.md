---
title: "Auto-update audit 2026-11-04: wired and detects release 3.7.20, what the sandbox cannot check"
author: Vinhnt
date: 2026-11-04
branch: master
cost: { minutes: 6, tokens: 166219 }
touches:
  - version.json
  - RELEASING.md
---

## Decided
- 2026-11-04 audit of the Mac auto-update: it is wired and detects the real release. AppDelegate.m:198 calls OpenKeyManager startAutomaticUpdates at launch; a check runs 1s later and every 6h (10 min after a failure); with AutoInstallUpdates (default YES) the dmg is downloaded quietly, and the user is asked once to restart (a deferred update is installed at the next launch). The swap needs the restart: it is not a silent hot swap.
- Evidence: run-app-update-test.sh prints all passed (mock GitHub, real-dmg test skipped). The production releaseFromAPIData parser fed the REAL answer of releases/latest gives 3.7.20, size 3697287, sha256 417303ee..., newer than 3.7.19, not newer than 3.7.20; the release API digest, the published .sha256 file and the sha256 of the dmg downloaded with curl are all equal.

## Tried and ruled out
- Running the production AppUpdater against the real network inside the sandbox: NSURLSession does not use the sandbox proxy, so the check says it cannot reach GitHub (curl does reach it). hdiutil attach and imageinfo fail with Device not configured, so the real dmg cannot be opened or its signature checked there. codesign -R on the installed app gives CSSMERR_TP_NOT_TRUSTED, inconclusive (Authority is unavailable in the sandbox, even for another Developer ID app).
- Tooling: the Write tool refuses /tmp/claude-501 but accepts ~/Library/Caches; Bash refuses a heredoc that holds a brace followed by a quote, and a download with a query string needs approval.

## Watch out
- trail grep does not list the call of startAutomaticUpdates (it is in AppDelegate.m:198); use grep -rn.
- Release v3.7.20 has only the dmg, its .sha256 and VOpenKey.dmg: no VOpenKey-3.7.20-Windows.zip, and version.json still announces 3.7.19, so Windows users are not offered 3.7.20 (the release flow writes version.json last, see RELEASING.md step 6).
- The app installed on this Mac is already 3.7.20 (a Debug build signed with the Developer ID of Team 39SH232CQ4) and the Application Support/VOpenKey/Updates folder never existed: no update was ever staged here. The first real test on an installed app is the next release.
- Still NOT verified: real hdiutil and signature of the published 3.7.20 dmg in this session (outside the sandbox: VOK_TEST_REAL_DMG=1 tests/run-app-update-test.sh), the alerts, the real relaunch, macOS 15 App Management on a real swap.
