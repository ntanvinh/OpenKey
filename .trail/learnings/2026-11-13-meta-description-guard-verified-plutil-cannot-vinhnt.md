---
title: Meta description guard verified; plutil cannot lint product JSON
author: Vinhnt
date: 2026-11-13
branch: master
cost: { minutes: 1, tokens: 34273 }
touches:
  - CHANGELOG.md
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.rc
  - marketing/releases/notes/3.7.27.md
  - CLAUDE.md
  - docs/vopenkey-ai/product.json
  - marketing/features/smooth-vietnamese-typing.json
  - marketing/website/product.json
  - scripts/check-product-docs.py
---

## Decided
- The meta description guard in scripts/check-product-docs.py is verified. The check passes with 122 checks on the current files. A scratch copy with a 263-character docs description and a drifted website copy fails with two messages, as intended.
- Validate the product JSON files with the check script, which uses Python's json module. Do not use plutil.

## Tried and ruled out
- plutil -lint on marketing/website/product.json and docs/vopenkey-ai/product.json: it fails with Unexpected character { at line 1 on files that Python parses fine.

## Watch out
- The earlier 2026-11-13 meta-description learning says the guard is untested. That is out of date now; this note replaces that status.
- Commit 989dd04 (author vinhnt) carried these edits along with other people's changes. Version bumps 3.7.27 and 3.7.28 landed after it. This session made none of those commits. Check git log before editing this repo, because someone else may be committing here.
