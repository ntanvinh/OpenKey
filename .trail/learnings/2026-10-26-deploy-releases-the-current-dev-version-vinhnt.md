---
title: Deploy releases the current dev version
author: Vinhnt
date: 2026-10-26
branch: windows-port
touches:
  - docs/vopenkey-ai/product.json
  - scripts/deploy.sh
  - docs/vopenkey-ai/icon.png
  - docs/vopenkey-ai/screenshots/01-ai-writing-assistant.png
  - docs/vopenkey-ai/screenshots/02-local-ai-setup.png
  - docs/vopenkey-ai/screenshots/03-signed-in-ai-agents.png
  - docs/vopenkey-ai/screenshots/04-ai-image-generation.png
  - docs/vopenkey-ai/screenshots/05-prompt-snippet-library.png
  - docs/vopenkey-ai/screenshots/06-restore-accidental-typing.png
  - docs/vopenkey-ai/screenshots/07-contextual-word-suggestions.png
---

## Decided
`scripts/dev.sh` owns the patch version increment. `scripts/deploy.sh` must call `scripts/release.sh current --yes` so release uses the version already selected during development.

## Tried and ruled out
Using `patch` in deploy increments again and skips the stable version currently tested in dev.

## Watch out
`current` preserves the marketing version and build number, while the normal release flow still requires its signing, notarization, clean-tree, and GitHub checks. Do not run deploy as a verification step.
