---
title: "Windows donate window and conversion buttons share data files with macOS (QR picture, presets JSON)"
author: Vinhnt
date: 2026-10-29
branch: windows-port
cost: { minutes: 26, tokens: 681586 }
touches:
  - CHANGELOG.md
  - PRIVACY.md
  - README.md
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.h
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.m
  - Sources/OpenKey/macOS/ModernKey/AppDelegate.h
  - Sources/OpenKey/macOS/ModernKey/AppDelegate.m
  - Sources/OpenKey/macOS/ModernKey/AppInfo.h
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/ModernKey/StatusMenuController.m
---

## Decided
- Windows got the donate window and the 14 conversion buttons (owner answered "Làm cả hai" on 2026-10-29). Both programs read the SAME data so they cannot drift: `engine/ai/ai-presets.json` (generated from `AIPresets.m`; read by the portable `engine/AIPresets.{h,cpp}`), `engine/DonationInfo.h` (payee constants), `engine/donation/donation-qr.bmp` (the QR code as a picture, made by `scripts/make-donation-qr.sh` from the macOS `Donation.m`; Windows has no QR encoder and writing one in C++ with nothing to run it on was the riskiest option).
- Tests tie the two together: `ai_assistant_test` compares the JSON with `AIPresets.m` (`VOK_PRESETS_JSON`), `donation_test` compares `DonationInfo.h` with `AppInfo.h` and with `pricing.json`, and decodes the BMP with CIDetector to the exact macOS payload. Portable: `ai_presets_test`, `donation_info_test` (in `scripts/test-portable.sh`, so CI runs them on Linux).
- Windows donate window: `DonationDialog.{h,cpp}`, two columns (QR left, account right) so the client height stays about 536 px at 100% DPI, `vDonationAcknowledged` in the registry, tray item removed/inserted by `syncDonateItem()` before each `TrackPopupMenu`, action `FeatureActions::OpenDonation`, button "Ủng hộ VOpenKey AI..." on the "Cài đặt AI..." row of `FeaturesDialog`. Conversions: `buildPresets/layoutPresets/applyPreset` in `AIAssistant.cpp`; buttons are `BS_CHECKBOX|BS_PUSHLIKE` with the state set by hand. The UI test (`windows-ui-test.ps1`) counts >= 18 buttons in the AI window.
## Tried and ruled out
- Radio buttons for the two donate tabs: the group breaks when the control that closes it (WS_GROUP) is hidden on the other page. Two push-like check boxes instead.
- `DM_SETDEFID` to change the default button: does nothing for a window that is not a dialog; only the `BS_DEFPUSHBUTTON` style matters with `IsDialogMessage`.
- A new "Ủng hộ" section in `FeaturesDialog`: +104 px would push the window past a 1366x768 screen; the button shares the AI row instead.
- A mutation that flips one QR module to prove the BMP test: Reed-Solomon (level M) repairs it, the decode is unchanged. Change the payee (AppInfo.h note) instead: that one fails line `ReadQR(picture)`.
## Watch out
- Nothing of the Windows side was run. Checked: portable tests, mingw syntax and link for x86+x64, and `windres` on a copy of `Features.rc` (its `\` paths only work with the Windows resource compiler, so use `/` on a Mac). The first MSVC compile is the CI job; the donate window layout is computed by hand, and the QR must be scanned from a real Windows screen at 125/150% DPI. List in `docs/windows-port-checklist.md` (7a, 7b).
- After the payee changes, run `scripts/make-donation-qr.sh` again (tests fail until then) and edit `AppInfo.h`, `engine/DonationInfo.h` and `marketing/pricing/pricing.json` together.
- Another session bumped `CHANGELOG.md` and `OpenKey.rc` to 3.7.15 while this was written: not part of this change. `trail check` flags about 20 keyword false positives (CHANGELOG, README, PRIVACY: "open key", "preset box").
