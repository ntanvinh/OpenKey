---
title: "AI window: occasion presets in tabs and ready-made picture sizes (2026-11-19)"
author: Vinhnt
date: 2026-11-19
branch: master
cost: { minutes: 20, tokens: 423759 }
touches:
  - README.md
  - Sources/OpenKey/engine/AIPresets.cpp
  - Sources/OpenKey/engine/AIPresets.h
  - Sources/OpenKey/engine/ai/ai-presets.json
  - Sources/OpenKey/engine/tests/ai_presets_test.cpp
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.h
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.m
  - Sources/OpenKey/macOS/ModernKey/AIPresets.h
  - Sources/OpenKey/macOS/ModernKey/AIPresets.m
  - Sources/OpenKey/macOS/ModernKey/CaseBarPanel.h
---

## Decided
- The 14 conversion chips became 25 in 4 tabs (Sửa & đổi giọng, Hoàn cảnh, Thơ, Độ dài & dịch). The 11 new ones (Chúc mừng, Công việc, Gửi sếp, Đồng nghiệp, Bạn bè, Gia đình, Khách hàng, Cảm ơn, Xin lỗi, Lời mời, Chia buồn) take a few ideas or a draft and write the whole message; the tone and the way of addressing people is chosen by the AI from the occasion. The instruction still is NOT written in the box (see the Oct 29 learning).
- Picture sizes: a menu "Kích thước ảnh" (18 sizes: social, icon/logo, cards/prints) next to "Tạo ảnh". The AI is told the canvas in English (note template in the data file) AND the picture is cut locally to exactly that many pixels (centre crop, then scale): image models draw at a few sizes of their own and do not keep to a size that is asked for. Session-only choice, not saved.
- One source of words: macOS/ModernKey/AIPresets.m; `scripts/make-ai-presets.sh` generates engine/ai/ai-presets.json (Windows reads it); ai_assistant_test (VOK_PRESETS_JSON) fails when they differ. No new app files, so no pbxproj change.
- Windows done in the same change (owner rule): tabs are push-like check boxes, the size menu is a combo box whose group titles bounce the choice back, cutting is WIC (clipper + Fant scaler + PNG encoder) in PictureFile::fitToSize, file kept in %TEMP%\VOpenKey AI and deleted with the picture.
## Tried and ruled out
- Size menu in the row of "Tạo": its closed state is ~230 px wide and squeezes the line that says where the text goes; it has its own row with "Tạo ảnh" now.
- Asking for the size in the prompt alone: not reliable, so the cut is done after.
## Watch out
- Verified: engine test, macOS UI test (ALL OK, incl. orientation of the cut picture), mingw syntax and link (x64) of the Windows code. NOT verified: anything run on Windows; real Codex with a size (only the fake one, 16x16); how real images look cropped to extreme ratios (LinkedIn 4:1 keeps a middle band of a 3:2 picture).
- A `//` comment that ends with a backslash swallows the next line in C++ (made PictureFile.cpp fail to compile once).
- Tab and size choice survive while the app runs, not a restart.
