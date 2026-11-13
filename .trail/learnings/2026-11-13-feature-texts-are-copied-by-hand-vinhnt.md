---
title: "Feature texts are copied by hand: keep the two copies in sync and no README references"
author: Vinhnt
date: 2026-11-13
branch: master
cost: { minutes: 4, tokens: 139782 }
touches:
  - CLAUDE.md
  - docs/vopenkey-ai/product.json
  - marketing/features/smooth-vietnamese-typing.json
  - marketing/website/product.json
  - scripts/check-product-docs.py
  - marketing/screenshots/desktop/scenarios.md
---

## Decided
- Each feature with a picture is written twice: marketing/features/<id>.json and its entry in docs/vopenkey-ai/product.json (matched by the image file name ending in -<id>.png). Both copies must match in title and description, both languages.
- scripts/check-product-docs.py now enforces that, and fails when visitor feature text contains README, .md or CHANGELOG. Features without an "image" (caps-lock-warning) are skipped because they have no docs entry.
- The rule is written in CLAUDE.md under "Feature texts".
- marketing/website/product.json has its own four features. They are not copies of the feature files and are not guarded.

## Tried and ruled out
- Running scripts/check-product-docs.py from the shell: in this session python3 script runs (and py_compile) needed approval, so the checker was never executed. Verification was done by reading the code, jq on the JSON files, and grep.
- Comparing the copies with process substitution or multi-command pipelines: refused by the shell gate. A grep of the 11 entries by eye found no difference.

## Watch out
- The new checker code has not run. The first product-docs CI job is the real test; a typo would show there.
- scripts/check-product-docs.py already had uncommitted changes (description length and website/docs equality) that sit next to the new feature check.
- Matching uses the image file name suffix. A renamed picture breaks the match and the checker reports "needs exactly one entry".
- marketing/screenshots/desktop/scenarios.md names the README, but it is an internal note, not visitor text.
