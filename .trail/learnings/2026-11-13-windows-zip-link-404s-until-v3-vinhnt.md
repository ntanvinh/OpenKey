---
title: Windows zip link 404s until v3.7.26 is published; docs check verified
author: Vinhnt
date: 2026-11-13
branch: master
cost: { minutes: 1, tokens: 26947 }
touches:
  - ".github/workflows/msbuild.yml"
  - CLAUDE.md
  - README.md
  - Sources/OpenKey/win32/README.md
  - docs/vopenkey-ai/product.json
  - marketing/positioning.md
  - marketing/releases/notes/3.7.26.md
  - marketing/website/product.json
  - scripts/check-product-docs.py
  - scripts/release.sh
---

## Decided
- scripts/check-product-docs.py passes all 18 checks on the working tree. Run against the committed HEAD files it fails with 10 problems, so the guard catches the original mistake.

## Tried and ruled out
- gh release view fails from this sandbox with a TLS x509 error. Use curl against github.com for release checks.

## Watch out
- https://github.com/ntanvinh/OpenKey/releases/latest/download/VOpenKey-Windows.zip returns 404 today. "Latest" resolves to v3.7.23, which has no fixed-name zip. The v3.7.26 release page is also a 404, so 3.7.26 is not published yet.
- The fixed-name zip appears only after 3.7.26 is published through scripts/release.sh, which runs the Windows workflow (commit eabf1ad or later). Do not re-run that workflow for v3.7.23: it would put an old build under the "latest" name.
- The msbuild.yml product-docs job was parsed with Ruby's YAML (PyYAML is not installed here).
