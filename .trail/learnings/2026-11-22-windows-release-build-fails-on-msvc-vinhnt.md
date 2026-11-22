---
title: Windows release build fails on MSVC-only errors (2026-11-22)
author: Vinhnt
date: 2026-11-22
branch: master
cost: { minutes: 1, tokens: 51223 }
touches:
  - Sources/OpenKey/engine/DictStore.cpp
  - Sources/OpenKey/win32/OpenKey/OpenKey/DictionaryPalette.cpp
  - scripts/check-windows.sh
---

## Decided
- 3.7.33 Windows CI failed: _wfopen/wcsncpy (C4996 is an error with SDLCheck) and std::max( clashing with the windows.h max macro. Fixed with _wfopen_s, wcsncpy_s, (std::max)(...).
- scripts/check-windows.sh now greps for these, since mingw accepts them.

## Tried and ruled out
- Re-running the release for the same version: release-windows.yml checks out the tag, which still holds the broken code. A new patch version (or moving the tag, owner's call) is needed.

## Watch out
- Code only the Windows build compiles (engine files that include windows.h) must use the _s functions and (std::min)/(std::max) or std::max<T>(...).
