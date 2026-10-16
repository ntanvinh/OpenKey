#!/bin/bash
# Bump the patch version, build VOpenKey AI for development, sign it, put it in ~/Applications and open it.
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/vopenkey-dev.XXXXXX")"
INSTALL=""
cleanup() {
    rm -rf "$WORK"
    if [ -n "$INSTALL" ]; then
        if [ -d "$INSTALL/previous" ] && [ ! -e "$DEST" ]; then
            mv "$INSTALL/previous" "$DEST"
        fi
        rm -rf "$INSTALL"
    fi
}
trap cleanup EXIT
clang -fobjc-arc -framework Cocoa -framework CoreGraphics \
    "$ROOT/scripts/dev-app.m" -o "$WORK/dev-app"

say "Bumping patch version for this dev build"
"$ROOT/scripts/version.sh" bump patch

DERIVED="$ROOT/build/dev"
mkdir -p "$ROOT/build"
BUILT="$(build_app Debug "$DERIVED" OTHER_CODE_SIGN_FLAGS="--timestamp=none")"
[ -d "$BUILT" ] || die "build did not produce $BUILT"

DEST="$HOME/Applications/$DISPLAY_NAME.app"
mkdir -p "$HOME/Applications"
INSTALL="$(mktemp -d "$HOME/Applications/.vopenkey-install.XXXXXX")"
ditto "$BUILT" "$INSTALL/new"
codesign --verify --deep --strict "$INSTALL/new" || die "the new app has a bad signature"

say "Closing all $DISPLAY_NAME instances owned by this user"
"$WORK/dev-app" stop "$BUNDLE_ID" || die "could not stop the running app; refusing to replace it"

say "Installing to $DEST"
[ ! -e "$DEST" ] || mv "$DEST" "$INSTALL/previous"
mv "$INSTALL/new" "$DEST"
codesign --verify --deep --strict "$DEST" || die "the installed app has a bad signature"
rm -rf "$INSTALL"
INSTALL=""

# Before the rename the app was VOpenKey.app: the same bundle id would then exist twice, so the old copy goes to the Trash
OLD_DEST="$HOME/Applications/$APP_NAME.app"
if [ -d "$OLD_DEST" ] && [ "$OLD_DEST" != "$DEST" ]; then
    say "Moving the old $APP_NAME.app to the Trash (the app is now called $DISPLAY_NAME.app)"
    mv "$OLD_DEST" "$HOME/.Trash/$APP_NAME-$(date +%Y%m%d-%H%M%S).app"
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$DEST" || die "could not register the new app with macOS"

if [ "$RESET" = 1 ]; then
    say "Forgetting the permissions of $BUNDLE_ID"
    tccutil reset Accessibility "$BUNDLE_ID" || true
    tccutil reset ListenEvent "$BUNDLE_ID" || true
fi

if [ "$OPEN" = 1 ]; then
    if [ "$RESET" = 0 ]; then
        # The first launch after replacing the signed bundle can retain stale input/permission state.
        # Finish that launch, then start a fresh process, like quitting and reopening the app manually.
        say "Preparing the new app, then restarting its keyboard hook"
        open -n "$DEST"
        "$WORK/dev-app" wait "$BUNDLE_ID" "$DEST" || die "the new app did not finish launching"
        "$WORK/dev-app" stop "$BUNDLE_ID" || die "could not restart the new app"
    fi
    say "Opening $DEST"
    open -n "$DEST"
    "$WORK/dev-app" wait "$BUNDLE_ID" "$DEST" || die "the installed app did not finish launching"
    if [ "$RESET" = 0 ]; then
        "$WORK/dev-app" ready "$BUNDLE_ID" "$DEST" ||
            warn "The app is open but its keyboard hook is not ready. Check Accessibility, Input Monitoring and Secure Input; no permissions were reset."
    fi
fi
echo "$DEST"
