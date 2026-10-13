#!/bin/bash
# Build VOpenKey for development, sign it, put it in ~/Applications and open it.
#
# Why not just run it from Xcode or from the build folder: macOS only lists an app in
# System Settings > Privacy & Security when it can find it, and an app that runs from a hidden build folder is
# neither listed nor easy to pick with the "+" button. In ~/Applications it is both. Signing with the same
# certificate every time also keeps the permissions you granted from one build to the next.
#
#   scripts/dev.sh                       build, install to ~/Applications, open
#   scripts/dev.sh --reset-permissions   also forget the Accessibility / Input Monitoring grants (to see the first run again)
#   scripts/dev.sh --no-open             do not open it
source "$(dirname "$0")/common.sh"

RESET=0; OPEN=1
for arg in "$@"; do
    case "$arg" in
        --reset-permissions) RESET=1 ;;
        --no-open) OPEN=0 ;;
        *) die "unknown option: $arg" ;;
    esac
done

DERIVED="$ROOT/build/dev"
mkdir -p "$ROOT/build"
BUILT="$(build_app Debug "$DERIVED" OTHER_CODE_SIGN_FLAGS="--timestamp=none")"
[ -d "$BUILT" ] || die "build did not produce $BUILT"

DEST="$HOME/Applications/$APP_NAME.app"
say "Closing $APP_NAME if it is running"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
for _ in $(seq 1 20); do pgrep -f "$DEST/Contents/MacOS/$APP_NAME" >/dev/null || break; sleep 0.25; done

say "Installing to $DEST"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"
codesign --verify --deep --strict "$DEST" || die "the installed app has a bad signature"

if [ "$RESET" = 1 ]; then
    say "Forgetting the permissions of $BUNDLE_ID"
    tccutil reset Accessibility "$BUNDLE_ID" || true
    tccutil reset ListenEvent "$BUNDLE_ID" || true
fi

if [ "$OPEN" = 1 ]; then
    say "Opening $DEST"
    open "$DEST"
fi
echo "$DEST"
