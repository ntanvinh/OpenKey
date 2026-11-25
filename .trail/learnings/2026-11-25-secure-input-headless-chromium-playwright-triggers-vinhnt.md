---
title: "Secure Input: headless Chromium/Playwright triggers global Secure Input on macOS, detected off-thread + WebKit helper spam fixed"
author: Vinhnt
date: 2026-11-25
branch: master
touches:
  - Sources/OpenKey/macOS/ModernKey/SecureInputHolder.h
  - Sources/OpenKey/macOS/ModernKey/SecureInputHolder.m
  - Sources/OpenKey/macOS/ModernKey/SecureInputMonitor.m
  - Sources/OpenKey/macOS/ModernKey/SecureInputWindow.m
  - Sources/OpenKey/macOS/tests/secure_input_holder_test.m
  - Sources/OpenKey/macOS/tests/secure_input_ui_test.m
---

## Decided
- Root cause of intermittent ("chập chờn") Secure Input on macOS even after closing password managers / RDP apps: headless Chromium (`Google Chrome --headless`, `Google Chrome for Testing`, Playwright/Puppeteer) calls `EnableSecureEventInput()` globally on macOS whenever a hidden page focuses `<input type="password">`, and releases it when the dialog closes or loses focus. Observed live on 2026-11-25 with `v_cyber_security/apps/desktop/e2e/quickconnect-signin-ui.mjs` running under a background Claude session in VApp Manager.
- `SecureInputSuspect` (`SecureInputHolder.h/m`) now detects headless/automated browser parent processes via `proc_listallpids` + `proc_pidpath` + `sysctl(KERN_PROCARGS2)` (`+reasonForCommandLineArguments:executablePath:`, `+suspectsAmongProcesses:excludingPIDs:`, `+runningHeadlessBrowserSuspectsExcludingPIDs:`), excluding child helpers (`--type=`, `--monitor-self`, ` Helper`, `crashpad`) and non-browser tools (`java -Djava.awt.headless=true`), and reporting PID + parent process name (e.g. `mở bởi node`).
- `SecureInputMonitor` runs the process-argument scan on a dedicated serial background queue (`_suspectQueue`, never on the main thread, throttled to every 3 s while secure input is on, reset per stretch) and tracks OFF->ON transition timestamps within 60 s (`recentToggleCount`, surfaced when >= 3) so `SecureInputWindow` warns about intermittent flapping caused by background/automated processes.
- Fixed WebKit/macOS XPC helper spam in `SecureInputSuspect` (`com.apple.WebKit.*`, `AutoFill`, `ThemeWidgetControlViewService`) where Remote Desktop Manager previously produced 20+ duplicate suspect entries, and deduplicated identical `(bundleID, name)` suspects.

## Tried and ruled out
- Matching `-headless` loosely: ruled out because Java/Kotlin daemons run with `-Djava.awt.headless=true`; only exact `--headless` / `--headless=...` flags on browser/Electron paths (or `Chrome for Testing` / `chromium_headless_shell` / `ms-playwright` / `playwright`/`puppeteer` args) count.
- Scanning live processes inside tests that only set `setApplicationsProvider:`: ruled out to avoid flakiness when Playwright runs on the developer's Mac; `runningHeadlessBrowserSuspectsExcludingPIDs:` returns `@[]` when `setApplicationsProvider:` is set without `setProcessesProvider:`.
- Touching macOS Vietnamese IM fallback rule: kept untouched per owner decision 2026-11-09.

## Watch out
- Live probe measured 9.52 ms for scanning all processes on a busy Mac; keep it strictly on `_suspectQueue`, never on the main thread.
- `trail check` reports lexical false positives against earlier Secure Input learnings (not real conflicts: none of `log show`, lazy icon loading, or dictionary test changes were introduced).
- App bundle in `/Users/vinh/Applications/VOpenKey AI.app` is NOT rebuilt/replaced automatically; only verified via `xcodebuild` Debug (`PRODUCT_BUNDLE_IDENTIFIER=vn.io.lssoft.vopenkey.uitest`), `run-secure-input-holder-test.sh`, `run-secure-input-ui-test.sh`, and a live probe binary.
