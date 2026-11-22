---
title: Dictionary badges as macOS capsule tags
author: Vinhnt
date: 2026-11-22
branch: master
cost: { minutes: 1, tokens: 42080 }
touches:
  - Sources/OpenKey/macOS/ModernKey/DictionaryPalette.m
---

## Decided
Badges in DictionaryPalette.m (catalog language tag, "Khuyên dùng", search-hit tag) use one helper, DictBadge + VOKDictBadgeView: capsule (radius = height/2), label centred on both axes, tinted fill that re-resolves in updateLayer on appearance change.

## Tried and ruled out
A wrapping NSTextField with a layer background: it draws text from the top (sat high in the pill) and CGColor froze the dynamic colour at creation.

## Watch out
Only syntax-checked with clang; not seen on screen. Windows has no equivalent change.
