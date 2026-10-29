#!/bin/zsh
# The real suggestion controller with Accessibility, the panel and the data folder replaced: no secret is suggested or learned.
# Builds the app first (like run-suggestion-apps-test.sh); no window is shown, the real learned.txt is not touched.
set -eu
HERE=${0:A:h}
ROOT=${HERE:h:h:h:h}
DERIVED="$ROOT/build/check"
xcodebuild -project "$ROOT/Sources/OpenKey/macOS/OpenKey.xcodeproj" -scheme OpenKey \
    -configuration Debug -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build > /tmp/vopenkey-suggestion-sensitive-build.log 2>&1 \
    || { tail -30 /tmp/vopenkey-suggestion-sensitive-build.log; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
OBJECTS=("$DERIVED/Build/Intermediates.noindex/OpenKey.build/Debug/OpenKey.build/Objects-normal/$(uname -m)"/*.o)
OBJECTS=("${(@)OBJECTS:#*/main.o}")
clang++ -std=c++17 -fobjc-arc -I"$HERE/../ModernKey" "$HERE/suggestion_sensitive_test.mm" \
    "${OBJECTS[@]}" -framework Cocoa -framework Carbon -framework QuartzCore \
    -framework Security -framework IOKit -framework ServiceManagement \
    -framework UniformTypeIdentifiers -framework EventKit -o "$WORK/suggestion_sensitive_test"
"$WORK/suggestion_sensitive_test"
