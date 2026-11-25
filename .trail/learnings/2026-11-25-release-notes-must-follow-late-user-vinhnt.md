---
title: Release notes must follow late user-visible commits (3.7.33)
author: Vinhnt
date: 2026-11-25
branch: master
cost: { minutes: 1, tokens: 44755 }
touches:
  - CHANGELOG.md
  - CLAUDE.md
  - Sources/OpenKey/macOS/ModernKey/SecureInputHolder.h
  - Sources/OpenKey/macOS/ModernKey/SecureInputHolder.m
  - Sources/OpenKey/macOS/ModernKey/SecureInputMonitor.m
  - Sources/OpenKey/macOS/ModernKey/SecureInputWindow.m
  - Sources/OpenKey/macOS/tests/secure_input_holder_test.m
  - Sources/OpenKey/macOS/tests/secure_input_ui_test.m
  - marketing/releases/notes/3.7.33.md
  - scripts/release-notes.sh
---

## Decided
3.7.33 had no tag or GitHub release, so the AI login-status change and the Secure Input holder change went into marketing/releases/notes/3.7.33.md (en-US + vi) and the CHANGELOG entry, with the date moved to 2026-11-25. No version bump. Rule added to CLAUDE.md.

## Tried and ruled out
Bumping to 3.7.34: the version is unreleased, so the notes belong to 3.7.33. Checked with git tag and gh release list.

## Watch out
Validate with notes_problem from scripts/release-notes.sh (needs ROOT set). version.sh notes prints the CHANGELOG entry.
