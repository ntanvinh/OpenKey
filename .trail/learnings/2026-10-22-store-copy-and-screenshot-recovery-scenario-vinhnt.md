---
title: Store copy and screenshot recovery scenario are separate
author: Vinhnt
date: 2026-10-22
branch: master
touches:
  - marketing/listing/en-US.json
  - marketing/listing/vi.json
  - marketing/website/product.json
  - marketing/releases/notes/3.7.5.md
---

## Decided
- App Store descriptions may accurately describe word recovery as a product feature; a screenshot scenario's limitation does not restrict listing copy.
- The trail check can lexically match restore wording in en-US store copy against the screenshot note even when the file and purpose differ.

## Tried and ruled out
- Removing the recovery feature from the store description to satisfy a screenshot-specific note would make the listing less accurate.

## Watch out
- If trail check reports the screenshot recovery note against listing copy, treat it as a scope mismatch: the note only rules out a still image as proof of recovery.
