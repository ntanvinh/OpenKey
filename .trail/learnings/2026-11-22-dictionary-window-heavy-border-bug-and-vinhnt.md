---
title: "Dictionary window: heavy border bug and English pronunciation (2026-11-22)"
author: Vinhnt
date: 2026-11-22
branch: master
cost: { minutes: 26, tokens: 438151 }
touches:
  - CHANGELOG.md
  - Sources/OpenKey/macOS/ModernKey/DictionaryPalette.h
  - Sources/OpenKey/macOS/ModernKey/DictionaryPalette.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/win32/OpenKey/OpenKey/DictionaryPalette.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.rc
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.vcxproj
  - scripts/link-windows.sh
  - scripts/test-portable.sh
  - Sources/OpenKey/engine/WordSpeech.cpp
---

## Decided
- Border bug root cause (measured on the owner's screenshot: edge pixel #A8A8A8 on #2C2C2C; reproduced offscreen: 160 on 45 dark, 113 on 250 light): `[NSColor.separatorColor colorWithAlphaComponent:0.55]` REPLACES the alpha (0.12) instead of multiplying, so the veil border was white 55% (black 55% in light). Fix in DictionaryPalette.m: use `NSColor.separatorColor` as is, width `kHairline` 0.5 (the case bar / suggestion bar pattern). Corner radius 12 -> 14 like SnippetPalette and AIAssistant.
- Audit of the other macOS panels (Snippet, AI assistant, case bar, suggestion bar, Caps Lock toast, VOKCard): only the dictionary had the alpha mistake; the others have no layer border or use separatorColor unmodified. Windows dictionary uses the theme `border` colour on a 1px square rectangle: not the same bug, left alone.
- Pronunciation: system voices only (no network). Portable rule in engine/WordSpeech.{h,cpp} (SpeakableEnglish, IsEnglishLang, TextToSpeak(headword, sourceLangs)): English word = ASCII letters with inner space/hyphen/apostrophe/dot, max 64; the SOURCE LANGUAGE of the dictionary decides ("ba" of a vi-en dictionary is ASCII but Vietnamese; unknown language = letters decide; any English dictionary wins). macOS: WordSpeaker.mm (AVSpeechSynthesizer, best en-US voice, rate x0.9, `speakHook` for tests), speaker button left of "Sao chep nghia" (hidden for non-English words) and Cmd+P via VOKDictPanel performKeyEquivalent. Windows: WordSpeaker.cpp (SAPI ISpVoice, Language=409/809/9, async), "Phat am" button, Ctrl+P in the search edit, stop on WM_SHOWWINDOW hide.
- Footer hints now say "Cmd+P Phat am - Return Chep nghia" (the old "Cmd+C Chep nghia" was wrong: nothing handles Cmd+C, Return copies).
- Tests: engine/tests/word_speech_test.cpp (in test-portable.sh); macOS tests/dictionary_speech_test.m + run-dictionary-speech-test.sh (no network: the two test dictionaries are made "installed" by copying compiled .vdict files and writing state.json under the catalog ids). Red-green verified for the border (115/137 contrast with the old colour, 26/25 fixed) and for the language rule.

## Tried and ruled out
- run-dictionary-test.sh in the sandbox: needs a local HTTP server (port binding refused) and `mktemp -d` ignores TMPDIR (use a PATH stand-in or a project build/ dir). Wrote the separate no-network test instead.
- screencapture / CGWindowListCreateImage (obsoleted in macOS 15) to see the WindowServer rim: refused in the sandbox; only what the app draws can be rendered (cacheDisplayInRect, writeToFile atomically:NO because the atomic temp file is refused).
- A veil view's layer `borderColor` was assumed to be the system separator; reading pixels back (alpha out of premultiplied bitmap) is what showed the 0.55.

## Watch out
- NOT verified: real sound on a Mac (hook replaces the voice), any Windows build run or SAPI voice (only mingw compile/link via scripts/link-windows.sh with -lsapi), the Xcode app target build with the new files/AVFoundation (pbxproj edited by hand, plutil OK), the WindowServer rim in the real window.
- `colorWithAlphaComponent:` on any system semantic colour replaces its alpha; CaseBarPanel.m:222 already warns about the dynamic-colour side of it.
- The pbxproj, CHANGELOG.md and OpenKey.rc had uncommitted owner edits (version 3.7.30 bump) before this work: do not revert them.
