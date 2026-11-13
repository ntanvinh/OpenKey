---
title: Meta description length guard in product.json and check-product-docs.py
author: Vinhnt
date: 2026-11-13
branch: master
cost: { minutes: 2, tokens: 90561 }
touches:
  - CLAUDE.md
  - docs/vopenkey-ai/product.json
  - marketing/website/product.json
  - scripts/check-product-docs.py
---

## Decided
- description.en in marketing/website/product.json and docs/vopenkey-ai/product.json is now the 139-character text from the VApp Manager report (was 159). description.vi is unchanged (142).
- scripts/check-product-docs.py now fails when description.en or description.vi is outside 70-155 characters, or when the website and docs copies of the description differ. CLAUDE.md has a Product description length section that says so.
- Feature-card descriptions in these files are longer than 155, but they are card text, not the meta description, so they were left alone.

## Tried and ruled out
- Running python3 scripts/check-product-docs.py and plutil -lint: this session needed approval for both, so they were not run. The new guard has not been executed.
- Patching the check in another interpreter to get around the approval gate: not done.

## Watch out
- The guard is untested. Run python3 scripts/check-product-docs.py before committing, then commit the learning with the change.
- The meta description range 70-155 comes from the app-marketing-seo skill notes on how VApp Manager measures the description. Check it if VApp Manager changes.
