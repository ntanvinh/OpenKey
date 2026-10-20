---
title: "VApp Manager website entry: docs/<slug>/product.json"
author: Vinhnt
date: 2026-10-20
branch: master
cost: { minutes: 1, tokens: 47083 }
touches:
  - docs/vopenkey-ai/product.json
  - marketing/features/ai-image-generation.json
  - marketing/features/ai-writing-assistant.json
  - marketing/features/contextual-word-suggestions.json
  - marketing/features/convert-vietnamese-encodings.json
  - marketing/features/custom-text-macros.json
  - marketing/features/flexible-vietnamese-input.json
  - marketing/features/keyboard-shortcuts.json
  - marketing/features/local-ai-setup.json
  - marketing/features/macos-menu-controls.json
---

## Decided
- VApp Manager's "Website entry" checklist item passes when docs/<slug>/product.json exists. Copy of marketing/website/product.json placed at docs/vopenkey-ai/product.json; slug vopenkey-ai guessed from sibling projects (vphone-fit, vbook-teller).

## Tried and ruled out
- Finding the slug in VAppManager's sqlite (kv table): nothing for this project. Sibling files carry extra fields (slug, sortOrder, icon, kind, platforms) that the given schema omits; not added.

## Watch out
- If the item still fails, the slug folder name is the first suspect. Keep marketing/website/product.json and docs copy in sync.
