---
title: Auto-update of the Mac app from GitHub releases (AppUpdater) and the fixed website link
author: Vinhnt
date: 2026-10-20
branch: master
cost: { minutes: 46, tokens: 746175 }
touches:
  - CLAUDE.md
  - README.md
  - RELEASING.md
  - Sources/OpenKey/macOS/ModernKey/AppDelegate.m
  - Sources/OpenKey/macOS/ModernKey/AppInfo.h
  - Sources/OpenKey/macOS/ModernKey/OpenKeyManager.h
  - Sources/OpenKey/macOS/ModernKey/OpenKeyManager.m
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/ModernKey/StatusMenuController.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
---

## Decided
- Own updater (AppUpdater.m), not Sparkle: same pinned Team ID pattern as AIOllamaInstaller. Source of truth is the GitHub API releases/latest (fallback: the redirect of releases/latest when the API answers 403/429/5xx), not version.json. version.json is still written by release.sh for Windows and old Mac apps.
- Every release also carries VOpenKey.dmg (copy of VOpenKey-version.dmg). The website links to releases/latest/download/VOpenKey.dmg (links.macos in docs/vopenkey-ai/product.json and marketing/website/product.json, keep both equal), so it never changes per release.
- Install: verify the COPY taken out of the dmg (id, version equal to the tag, signature requirement with Team 39SH232CQ4), keep it in Application Support/VOpenKey/Updates/ready, a detached sh helper waits for the app pid, swaps the bundle beside the old one, reopens it; any failure reopens the old app. Auto download is the default (AutoInstallUpdates); the restart is asked once, a deferred update is installed at the next launch, once per version.
- Notarization is not required by the updater (our own downloads carry no quarantine).

## Tried and ruled out
- NSURLSessionDownloadTask: it writes a temp file in /var/folders, which sandboxed shells cannot write; a data task written straight to the target file works everywhere. Same for writeToFile atomically:YES in tests, and NSTemporaryDirectory (ignores TMPDIR).
- A Python mock server on a local port: local port binding is blocked in the sandbox. The tests use an NSURLProtocol stub inside the test program (MockGitHub) via the protocolClasses test seam.
- Waiting with kill -0 on a child of the test: a quit child stays a zombie and still answers. The test uses a grandchild sleep.

## Watch out
- Not verified: real hdiutil attach (run VOK_TEST_REAL_DMG=1 tests/run-app-update-test.sh), the full Xcode build, the alerts/menu item/Settings button, a real replacement of the installed app (TCC App Management, Accessibility survival), a real release.
- Changing the signing certificate to another Team makes installed apps refuse the update: change VOK_TEAM_ID and have users download once by hand.
