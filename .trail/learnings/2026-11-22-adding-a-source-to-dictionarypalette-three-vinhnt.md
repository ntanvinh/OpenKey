---
title: "Adding a source to DictionaryPalette: three macOS test runners must link it (2026-11-22)"
author: Vinhnt
date: 2026-11-22
branch: master
cost: { minutes: 39, tokens: 375820 }
touches:
  - CHANGELOG.md
  - Sources/OpenKey/macOS/ModernKey/DictionaryPalette.h
  - Sources/OpenKey/macOS/ModernKey/DictionaryPalette.m
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/macOS/tests/run-case-bar-test.sh
  - Sources/OpenKey/macOS/tests/run-dictionary-test.sh
  - Sources/OpenKey/macOS/tests/run-tap-test.sh
  - Sources/OpenKey/win32/OpenKey/OpenKey/DictionaryPalette.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.rc
  - Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.vcxproj
---

## Decided
- Any new .m/.mm/.cpp that DictionaryPalette imports must be added to THREE runner scripts, not only the Xcode project: Sources/OpenKey/macOS/tests/run-dictionary-test.sh, run-case-bar-test.sh and run-tap-test.sh (each compiles DictionaryPalette.m and links by hand). Done for WordSpeaker.mm + WordSpeech.cpp + -framework AVFoundation. run-dictionary-speech-test.sh (new) is the no-network test for the border hairline and the speaker button.
- Verified unsandboxed 2026-11-22: xcodebuild Debug of the OpenKey scheme succeeds with the hand-edited pbxproj (app links AVFoundation, contains vspeech symbols); run-dictionary-test.sh gives ALL OK (0 failures); run-tap-test.sh ALL OK; every test of scripts/test-portable.sh passes; mingw link ok for x64 and x86; this Mac has an en-US voice (41 English voices) so WordSpeaker picks one.

## Tried and ruled out
- Reading `trail check` output as 9 real conflicts: all were keyword matches (the CHANGELOG/pbxproj/rc hits are the owner's own 3.7.30 bump; the DictionaryPalette.m hits are this session's learning describing the bug that was fixed, plus an unrelated AI-window and case-bar learning; the runner hits are my own earlier sandbox note and an unrelated SuggestionController swizzle note). None of the changes brings back a ruled-out approach.
- Capturing the real window with `screencapture -l` for a window parked at (-20000,-20000): "could not create image from window" even without the sandbox (an offscreen window is not composed). Putting it on screen would steal focus from the owner, so the WindowServer rim stays unverified.

## Watch out
- run-case-bar-test.sh fails 6 assertions (case_bar_test.m lines 218, 219, 225, 236, 241, 246: double click / shift+click / select-all showing the bar) on an untouched `git archive HEAD` copy too: pre-existing, not caused by the dictionary work. Probably the selection events cannot be synthesised in this session; not investigated.
- scripts/test-portable.sh ran out of its 10 minute background limit once while the machine was also running xcodebuild; the same tests run one by one finished in seconds (ai_agent_test included). Do not run it next to a build.
- Still NOT verified: real sound (AVSpeechSynthesizer / SAPI), anything on Windows beyond the mingw link, the rim the WindowServer draws.
