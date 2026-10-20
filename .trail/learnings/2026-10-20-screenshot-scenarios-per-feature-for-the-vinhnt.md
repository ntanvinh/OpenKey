---
title: Screenshot scenarios per feature for the VApp Manager desktop pipeline (marketing/screenshots/desktop/scenarios.md)
author: Vinhnt
date: 2026-10-20
branch: master
cost: { minutes: 7, tokens: 174530 }
touches:
  - marketing/screenshots/desktop/scenarios.md
---

## Decided
- Desktop pictures follow VApp Manager's desktop autopilot: one PNG per feature, max 8, in website order (tier unique, value, common, then rank), saved as marketing/screenshots/desktop/NN-<feature id>.png and referenced by `image` in marketing/features/<id>.json. So the first 8 by that order get pictures (ai-writing-assistant ... smooth-vietnamese-typing); the other 8 only have a reserve scenario.
- The per-feature data scenario lives in marketing/screenshots/desktop/scenarios.md, not inside features/*.json: VApp Manager owns those files and may rewrite them. One persona (Lan, sells coffee online) runs through every picture; AI answers and images must be generated for real, never typed in.
- Each scenario names who can capture it: the AI alone only for the app's own settings windows; a person (cmd+shift+4, or paste) for anything that needs real typing, a global hotkey, the status menu or a panel next to another window.

## Tried and ruled out
- Putting the scenario into the feature JSON (extra keys): the feature schema in VApp Manager is a fixed zod object.
- A TextEdit picture for restore-accidental-typing: the end result "restore" looks like ordinary English, a still image cannot show the recovery; the settings rows carry it.
- Showing text in the convert tool picture: ConvertToolViewController has two code-table popups, options and a Convert button, it works on the clipboard and has no text area.

## Watch out
- ~/Library/Application Support/VOpenKey/ is shared by the uitest build and the real app: never seed demo snippets or learned words there.
- The AI cannot drive real typing or hotkeys from the shell (synthesized events do not arrive), so suggestion bar, restore and underline pictures need a person.
- Pictures show a Vietnamese UI while product.json says media locale en-US: the owner has to decide.
- Nothing was captured and no feature file was changed; the scenarios were read from the source, not run.
