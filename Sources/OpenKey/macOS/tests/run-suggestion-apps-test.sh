#!/bin/zsh
# Build and test the real controller/settings section with isolated preferences.
set -eu
HERE=${0:A:h}
ROOT=${HERE:h:h:h:h}
DERIVED="$ROOT/build/check"
xcodebuild -project "$ROOT/Sources/OpenKey/macOS/OpenKey.xcodeproj" -scheme OpenKey \
    -configuration Debug -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build > /tmp/vopenkey-suggestion-apps-build.log 2>&1
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
OBJECTS=("$DERIVED/Build/Intermediates.noindex/OpenKey.build/Debug/OpenKey.build/Objects-normal/$(uname -m)"/*.o)
OBJECTS=("${(@)OBJECTS:#*/main.o}")
clang++ -std=c++17 -fobjc-arc -I"$HERE/../ModernKey" "$HERE/suggestion_apps_test.mm" \
    "${OBJECTS[@]}" -framework Cocoa -framework Carbon -framework QuartzCore \
    -framework Security -framework IOKit -framework ServiceManagement \
    -framework UniformTypeIdentifiers -framework EventKit -o "$WORK/suggestion_apps_test"
"$WORK/suggestion_apps_test"
