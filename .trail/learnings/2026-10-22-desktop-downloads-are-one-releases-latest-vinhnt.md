---
title: "Desktop downloads are one releases/latest link, the AI writes PRIVACY.md, Releases tab finds a native app's repo"
author: Vinhnt
date: 2026-10-22
branch: master
cost: { minutes: 17, tokens: 456579 }
touches:
  - PRIVACY.md
  - scripts/release.sh
  - AGENTS.md
---

## Decided
- The website's macos/windows/linux links are `https://github.com/<o>/<r>/releases/latest` for every computer platform the app runs on, taken from the `origin` of the project's git repository (never `upstream`: a fork's origin is the person's). A release then only needs its notes; the website never changes. `shared/githubDownloads.ts` is the rule; `withDownloadLinks` / `applyDownloadLinks` in `marketing/website/links.ts`; *Apply links* fills the blank ones, `force` also replaces `/releases` and version links of the same repo.
- Privacy for an app that runs on computers only: the AI writes a `PRIVACY.md` in the project (EN + VI, every statement backed by code it read) and sets `links.privacyPolicy` to `https://github.com/<o>/<r>/blob/HEAD/PRIVACY.md`. This replaces the same-day rule "the AI never writes a privacy policy", which left the person with no link. The person must read it and push it; the AI never commits.
- Releases tab of a desktop app: `findGithubRepo(product, ctx)` falls back to git origin (VOpenKey has no package.json, so it said "No GitHub repository was found"), `GithubReleaseStatus.latestUrl` is shown with Copy/Open, and the top Refresh reads GitHub too (it only reloaded the version matrix).
- The Website tab watches `marketing/` (`marketing.watch` + `marketing:changed`): a screenshot taken 80 s after an AI run still showed `#` for links the AI had already written.

## Tried and ruled out
- `releases/latest/download/VOpenKey.dmg` as the default for all platforms: only works where a release attaches a fixed-name file (VOpenKey's release.sh does for macOS, not for Windows); the person asked for one latest link.
- Filling the desktop links at preview time like the store links: the website would show a live download button for a repository with no release.
- Publishing an unnotarized VOpenKey release to get past the missing notary profile: `scripts/release.sh` refuses on purpose, and this Mac has no notarytool profile at all (`security find-generic-password -s com.apple.gke.notary.tool` is empty).

## Watch out
- `scripts/release.sh current|patch` needs: profile `VOpenKey-notary` in the Keychain (`xcrun notarytool store-credentials VOpenKey-notary --apple-id … --team-id 39SH232CQ4 --password <app-specific>`), a clean tree on master, `gh` signed in. `releases/latest` answers 302 until the first release exists. The Releases tab stays read-only for desktop apps: there is no Publish button.
- `trail check` reports ~20 "conflicts" on AGENTS.md lines 50 and 57 for any edit near them: keyword matches in two huge paragraphs, not caused by a change.
