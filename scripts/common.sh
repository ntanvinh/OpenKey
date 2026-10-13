#!/bin/bash
# Shared by dev.sh and release.sh. Source it, do not run it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Sources/OpenKey/macOS/OpenKey.xcodeproj"
SCHEME="OpenKey"
APP_NAME="VOpenKey"
BUNDLE_ID="vn.io.lssoft.vopenkey"

say()  { printf '\033[1m==> %s\033[0m\n' "$*" >&2; } # stderr: stdout is for values a function returns
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# The certificate used to sign: SIGN_IDENTITY if set, otherwise the first "Developer ID Application" in the keychain.
find_identity() {
    if [ -n "${SIGN_IDENTITY:-}" ]; then echo "$SIGN_IDENTITY"; return; fi
    security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1
}

# "Developer ID Application: Name (TEAMID)" -> TEAMID
team_of() { echo "$1" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p'; }

setting() { xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | sed -n "s/^ *$1 = //p" | head -1; }

# build <Debug|Release> <derived data dir> <extra xcodebuild args...>  ->  prints the path of the built app
build_app() {
    local configuration="$1" derived="$2"; shift 2
    local identity; identity="$(find_identity)"
    [ -n "$identity" ] || die "no 'Developer ID Application' certificate in the keychain (set SIGN_IDENTITY to use another)"
    local team; team="$(team_of "$identity")"
    say "Building $APP_NAME ($configuration), signed as: $identity"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$configuration" -derivedDataPath "$derived" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" PROVISIONING_PROFILE_SPECIFIER="" \
        "$@" build > "$derived.log" 2>&1 || { tail -30 "$derived.log" >&2; die "build failed, full log: $derived.log"; }
    echo "$derived/Build/Products/$configuration/$APP_NAME.app"
}
