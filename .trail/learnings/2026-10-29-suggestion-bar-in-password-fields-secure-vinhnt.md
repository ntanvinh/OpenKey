---
title: "Suggestion bar in password fields: secure input hides the bar, SensitiveField reads Accessibility names (Bravo 10 case)"
author: Vinhnt
date: 2026-10-29
branch: windows-port
cost: { minutes: 16, tokens: 274392 }
touches:
  - Sources/OpenKey/macOS/ModernKey/CaretLocator.h
  - Sources/OpenKey/macOS/ModernKey/CaretLocator.m
  - Sources/OpenKey/macOS/ModernKey/SecureInputMonitor.m
  - Sources/OpenKey/macOS/ModernKey/SuggestionController.mm
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/macOS/ModernKey/SensitiveField.h
  - Sources/OpenKey/macOS/ModernKey/SensitiveField.m
  - Sources/OpenKey/macOS/tests/run-secure-input-suggestion-test.sh
  - Sources/OpenKey/macOS/tests/run-sensitive-field-test.sh
  - Sources/OpenKey/macOS/tests/run-suggestion-sensitive-test.sh
---

## Decided
- Two layers. (1) macOS secure input: a real password field in Chrome (also a Chrome app such as Bravo 10) makes Chrome hold secure input, every event tap is blind, so nothing is suggested or learned there. The bug seen in the owner's log (2026-10-29 17:10:57): the bar of the field before stayed up ~1.9 s over the password field. SecureInputMonitor.evaluate now calls [SuggestionController reset] when secure input starts or ends. (2) SensitiveField.{h,m}: reads the focused element's Accessibility attributes (AXSecureTextField subrole/role, "secure text field", and names in AXPlaceholderValue/AXTitle/AXDescription/AXHelp/AXIdentifier/AXDOMIdentifier/label: password, mật khẩu, OTP, PIN, CVV...). Text is folded (lower case, no accents, NFD ok, đ→d, first 160 chars). Long words match anywhere, short ones (pin, otp, secret...) only as whole words ("spinning", "secretary" are normal).
- SuggestionController asks once per word (first letter after a Tab/click/space) on _accessibilityQueue, before CaretLocator asks for the caret on the same serial queue, so the bar for the first letter is hidden before it was ever shown. A secret field sets settings.enabled=false: no bar, no context, nothing learned. No answer = ordinary field. App activation clears the flag.
- Tests: run-sensitive-field-test.sh (pure + optional live probe), run-secure-input-suggestion-test.sh (monitor with faked secure input), run-suggestion-sensitive-test.sh (real controller; Accessibility, panel and data folder replaced).

## Tried and ruled out
- AXSecureTextField alone (what AISelection.m uses): the Bravo 10 password field is an ordinary AXTextField for macOS (AXSubrole nil, role description "text field"), only AXPlaceholderValue "Mật khẩu" tells.
- Typing into the owner's real Bravo 10 window with synthetic keys or activating it for a test: takes the owner's keyboard; CGEventPostToPid also bypasses the tap, so it would not test VOpenKey.
- $HOME to isolate a test: NSApplicationSupportDirectory ignores it. Swizzle -[SuggestionController dataFolder] to a temp folder instead (the real learned.txt is shared with the running app).

## Watch out
- While a Chrome app is NOT active, AXFocusedUIElement of the app is the AXWebArea, not the field (the field only has AXFocused=1 inside the tree). The live probe therefore finds the field by placeholder (VOK_PROBE_PID=<pid> VOK_PROBE_PLACEHOLDER='Mật khẩu'); what an ACTIVE Chrome answers for the focused element, and real keys through the real tap, were NOT verified. Windows port (win32/SuggestionController.cpp) not covered.
- trail check on this branch lists 20 conflicts in CHANGELOG.md, PRIVACY.md, README.md, AIPresets.cpp from commits already on windows-port; none are in the files of this change. PRIVACY.md says macOS hides password keys from the app, still true.
