---
title: AI assistant copy and close with Shift-Command-C
author: Vinhnt
date: 2026-10-29
branch: windows-port
touches:
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.h
  - Sources/OpenKey/macOS/ModernKey/AIAssistant.m
  - Sources/OpenKey/macOS/tests/ai_assistant_test.m
---

## Decided
The macOS AI assistant uses “Sao chép và đóng” for both text and generated images. Shift-Command-C runs the same action. Close through hideAssistant only after the pasteboard reports a successful write; failure keeps the answer visible for retry.

## Tried and ruled out
The old transient green copied check is no longer needed because success immediately hides the panel.

## Watch out
The footer has a fixed 620-point window width: allow the shortcut hint to wrap when using the longer button title. Keep insertion and lightbox copy behavior independent. Run run-ai-assistant-test.sh with fake providers and its private pasteboard; VOK_SNAPSHOT_DIR exports light and dark UI captures.
