---
title: Donate window like VMonitor AI and ready-made conversion buttons in the AI window like VAlo (macOS)
author: Vinhnt
date: 2026-10-29
branch: windows-port
cost: { minutes: 29, tokens: 498332 }
touches:
  - PRIVACY.md
  - README.md
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.h
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.m
  - Sources/OpenKey/macOS/ModernKey/AppDelegate.h
  - Sources/OpenKey/macOS/ModernKey/AppDelegate.m
  - Sources/OpenKey/macOS/ModernKey/AppInfo.h
  - Sources/OpenKey/macOS/ModernKey/SettingsWindowController.m
  - Sources/OpenKey/macOS/ModernKey/StatusMenuController.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
---

## Decided
- Donate (macOS only): `Donation` (static VietQR payload + CRC16, `CIQRCodeGenerator` picture, `DonationAcknowledged` default) and `DonationWindow` (Việt Nam | Quốc tế tabs, copy buttons, "Mở PayPal", "Tôi đã ủng hộ" = the user's own word, thanks page with undo, scroll view on a low screen). Entry points: status menu "Ủng hộ VOpenKey AI" (hidden once acknowledged) and Settings > Hệ thống > "Ủng hộ…" (always). Same screen as VMonitor AI (`v_screen/apps/desktop/src/renderer/features/donate`).
- The payee lives twice: `VOK_DONATE_*` in `AppInfo.h` and `marketing/pricing/pricing.json#payments.trusted`; `tests/donation_test.m` fails when they differ. I added the `international` PayPal block (paypal.me/ntanvinh, copied from VMonitor's pricing.json): the Oct 27 note that it was "left empty on purpose" no longer applies, the owner asked for the VMonitor donate info.
- The payload is byte-identical to VMonitor's `donationQrPayload` (run with `node --experimental-strip-types` on a copy with the JSON import inlined) and the picture is decoded back with `CIDetector` in the test.
- Presets: `AIPresets` (14 modes taken from VAlo `packages/core/src/ai/writing.ts`, poem rules from `poetry.ts`). One click on a chip chooses it and asks at once; the prompt is built in `-[AIAssistant ask]` (instruction + text) and is NOT written in the box; the chip stays lit so "Tạo lại" repeats it; typing clears it. Poem answers say the rhymes and syllables were not checked (VAlo checks and retries; not ported).
- PRIVACY.md (both languages) now says a fixed sentence goes in front of the text for a preset and what the donate window does.
## Tried and ruled out
- Putting the preset instruction into the box: the poem rules are 600+ characters and bury the text; the box must stay the user's own text.
- A custom-drawn chip view: a rounded small `NSButton` with `bezelColor = controlAccentColor` while chosen looks right in light and dark and keeps native focus and accessibility.
- Windows port in this change: it needs a QR encoder in C++ (no CoreImage there), a Win32 chip row and a donate dialog, none of which can be run here. Left as an open question for the owner.
## Watch out
- Run ai_assistant_test ONE copy at a time: copies share the defaults domain `ai_assistant_test` and overwrite each other's provider address, which looked like real request failures (including a bogus failure at the "Cài AI chạy trên máy" check).
- `tap_test` fails at `[pasted isEqualToString:@"XIN CHÀO"]` (tap_test.mm:466) on a clean HEAD too: it was failing before this change.
- A stack view lays buttons out by alignment rect and `intrinsicContentSize` is already that size; a row that is too long squeezes its last button to a few points without a warning. A wrapping `VOKLabel` has no width of its own: use `labelWithString:` for a one-line caption.
- Offscreen snapshots: a light picture taken after a dark one in the same process came out with white text. The first picture of a pair is reliable.
- The status menu item and the Settings row were built but never seen (the menu cannot be popped from a test build).
