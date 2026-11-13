---
title: "Windows is a shipped platform in the README, positioning and product files"
author: Vinhnt
date: 2026-11-13
branch: master
cost: { minutes: 5, tokens: 225261 }
touches:
  - ".github/workflows/msbuild.yml"
  - CLAUDE.md
  - README.md
  - Sources/OpenKey/win32/README.md
  - docs/vopenkey-ai/product.json
  - marketing/positioning.md
  - marketing/website/product.json
  - scripts/check-product-docs.py
  - marketing/product.json
---

## Decided
- The README, marketing/positioning.md, the three product.json files (marketing/product.json, marketing/website/product.json, docs/vopenkey-ai/product.json) and Sources/OpenKey/win32/README.md say the app ships for macOS and Windows.
- The Windows download link is releases/latest/download/VOpenKey-Windows.zip, the fixed-name copy that release-windows.yml attaches. The README also points to Sources/OpenKey/win32/README.md.
- The Windows README names OpenKey64.exe and OpenKey32.exe. The zip has no OpenKey.exe.
- scripts/check-product-docs.py guards this. The product-docs job in .github/workflows/msbuild.yml runs it on every push and PR. CLAUDE.md has a "Windows ships with every release" rule.

## Tried and ruled out
- Changing only the lines the review named. The Mac-only audience and promise lines in positioning.md, and the "on Mac" descriptions in the website and docs product.json files, contradicted the platform list, so they were changed too.
- Blanket-replacing "tuyenvm/OpenKey" across the repo. Many hits are legitimate: author credits, GPL headers, the upstream Linux link, the upstream donate links.

## Watch out
- In this session, running python3 (the check script and an inline YAML parse) and gh release view needed approval and were not run. The check script has never been run; run `python3 scripts/check-product-docs.py` first.
- The VOpenKey-Windows.zip link returns 404 until a release built by the workflow with the fixed-name copy (commit eabf1ad or later) is published. Whether the latest release already has it was not checked.
- Nothing was committed. This learning and the doc changes need committing together.
