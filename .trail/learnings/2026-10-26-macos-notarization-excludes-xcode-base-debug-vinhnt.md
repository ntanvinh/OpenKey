---
title: macOS notarization excludes Xcode base debug entitlements
author: Vinhnt
date: 2026-10-26
branch: master
touches:
  - scripts/release.sh
---

## Decided
Set `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` only on the Release xcodebuild invocation in `scripts/release.sh`. Xcode's injected `com.apple.security.get-task-allow` blocks notarization; Debug builds keep their normal setting.

## Tried and ruled out
Apple's notarization log rejected the Release app on both x86_64 and arm64 because the executable requested `com.apple.security.get-task-allow`. The entitlements dump confirmed Xcode had embedded it.

## Watch out
Check the signed Release app's entitlements before submitting to Apple. `trail check` can report inherited lexical conflicts in the older Windows workflow and docs; keep the release fix scoped and explain in its commit message that those findings predate and do not involve `scripts/release.sh`.
