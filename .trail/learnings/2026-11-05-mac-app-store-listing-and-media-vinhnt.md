---
title: Mac App Store listing and media locale gaps
author: Vinhnt
date: 2026-11-05
branch: master
touches:
  - marketing/listing/en-US.json
  - marketing/listing/vi.json
  - marketing/product.json
  - version.json
---

## Decided
- `marketing/product.json` lists macOS and Windows. VApp Manager maps macOS to Mac App Store and offers no Google Play text for this desktop project, so keep the App Store copy and empty Android fields.
- The 3.7.20 release notes are dated 2026-11-03 while `version.json` still reports 3.7.19; confirm the release target before treating 3.7.20 as live.
- The eight desktop feature images are linked and marked `inUse`, but their capture language is Vietnamese while `locales.media` is en-US. Ask before changing screenshot locales or assets.

## Tried and ruled out
- Treating the existing desktop feature captures as visually verified store screenshots; this text task checked references and manifest only.

## Watch out
- Trail check may match Secure Input release copy to unrelated menu-bar screenshot tooling. Check the actual claim before changing accurate user-facing copy.
