---
title: "What's New for 3.7.23: range since v3.7.20, Windows lines and what is unverified"
author: Vinhnt
date: 2026-11-10
branch: master
cost: { minutes: 1, tokens: 2891 }
touches:
  - marketing/releases/notes/3.7.23.md
---

## Decided
- The What's New text for the next release is built from `git log v3.7.20..HEAD`, the last tag. That range includes 3.7.21 and 3.7.22, which have no tags and no notes. The CHANGELOG repeats the same few commits under the 3.7.21, 3.7.22 and 3.7.23 headings, so do not copy from it.
- Windows lines stay in the release notes with a platform label, as in 3.7.12. The Mac App Store text shows them too; store-specific text would need its own file.
- The Windows update check is listed because it is on by default and goes online. It can be turned off in Settings.
- Left out because a user would not notice them: the 1 s delay before the input-source fallback, the store-listing refresh, the desktop captures, version bumps, tests and learnings.
- Result: en-US and vi, 4 bullets each, about 565 characters per language (limit 4000). The date is the drafting date and should be set to the real release date.

## Tried and ruled out
- Writing the notes from the CHANGELOG headings: they repeat commits across 3.7.21 to 3.7.23 and do not show what a user gets.

## Watch out
- None of the Windows features in this range has run on Windows: agent CLIs, Codex pictures, the auto case list, suggestion bar options and the update flow. Test the Windows build before publishing those bullets.
- The Windows install folders and flags for Codex, Claude Code and Antigravity were taken from macOS. They may differ on Windows.
- `marketing/listing/*.json` still holds the 3.7.20 `whatsNew` text. The notes task did not change it.
