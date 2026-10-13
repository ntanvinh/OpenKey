#!/bin/bash
# Build, sign and package VOpenKey for release.
#
#   scripts/release.sh                 build, sign, make dist/VOpenKey-<version>.dmg (+ .sha256)
#   scripts/release.sh --notarize      also have Apple notarize it and staple the ticket (what other Macs need to open it
#                                      without a warning)
#   scripts/release.sh --publish       also create the GitHub release with the dmg; this puts it online, so it needs
#                                      --notarize as well (ALLOW_UNNOTARIZED=1 to publish anyway)
#
# Signing uses the first "Developer ID Application" certificate in the keychain (SIGN_IDENTITY to pick another).
#
# Notarizing needs your Apple ID credentials in the keychain, once:
#   xcrun notarytool store-credentials VOpenKey-notary --apple-id <your apple id> --team-id <team id> --password <app-specific password>
# (app-specific password: appleid.apple.com > Sign-In and Security). NOTARY_PROFILE changes the profile name.
#
# The version comes from the Xcode project (MARKETING_VERSION and CURRENT_PROJECT_VERSION). Before releasing a new one,
# raise both there and in version.json, which is what the app's "check for updates" reads from the master branch.
source "$(dirname "$0")/common.sh"

NOTARIZE=0; PUBLISH=0
for arg in "$@"; do
    case "$arg" in
        --notarize) NOTARIZE=1 ;;
        --publish)  PUBLISH=1 ;;
        -h|--help)  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $arg (see --help)" ;;
    esac
done
NOTARY_PROFILE="${NOTARY_PROFILE:-VOpenKey-notary}"
if [ "$PUBLISH" = 1 ] && [ "$NOTARIZE" = 0 ] && [ "${ALLOW_UNNOTARIZED:-0}" != 1 ]; then
    die "--publish needs --notarize: an app that is not notarized cannot be opened on other Macs without a warning (ALLOW_UNNOTARIZED=1 to override)"
fi
if [ "$NOTARIZE" = 1 ]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || die "no notarytool profile named '$NOTARY_PROFILE' in the keychain. Create it once with:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <your apple id> --team-id <team id> --password <app-specific password>"
fi
if [ "$PUBLISH" = 1 ]; then
    command -v gh >/dev/null || die "--publish needs the GitHub CLI (brew install gh) and 'gh auth login'"
    gh auth status >/dev/null 2>&1 || die "gh is not logged in: run 'gh auth login'"
fi

IDENTITY="$(find_identity)"
[ -n "$IDENTITY" ] || die "no 'Developer ID Application' certificate in the keychain (set SIGN_IDENTITY to use another)"
VERSION="$(setting MARKETING_VERSION)"; BUILD="$(setting CURRENT_PROJECT_VERSION)"
[ -n "$VERSION" ] && [ -n "$BUILD" ] || die "could not read the version from the Xcode project"
say "Releasing $APP_NAME $VERSION (build $BUILD)"

BUILD_DIR="$ROOT/build/release"
DIST_DIR="$ROOT/dist"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -rf "$BUILD_DIR" "$BUILD_DIR.log" "$ROOT/build/dmg"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# --- build and sign -------------------------------------------------------------------------------------------------
APP="$(build_app Release "$BUILD_DIR" ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp")"
[ -d "$APP" ] || die "build did not produce $APP"

say "Checking the signature"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /' >&2
SIGNING="$(codesign -dv --verbose=4 "$APP" 2>&1)"
echo "$SIGNING" | grep -q "flags=.*runtime" || die "the app is not signed with the hardened runtime, Apple would refuse to notarize it"
echo "$SIGNING" | grep -q "Timestamp=" || die "the signature has no secure timestamp, Apple would refuse to notarize it"
echo "    architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")" >&2
echo "    identity:      $(echo "$SIGNING" | sed -n 's/^Authority=\(Developer ID Application.*\)$/\1/p' | head -1)" >&2

# --- notarization -----------------------------------------------------------------------------------------------------
# submit <file>: waits for Apple's verdict, shows the log when it is not "Accepted"
notarize() {
    local file="$1" result
    say "Notarizing $(basename "$file") (this takes a few minutes)"
    if ! result="$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"; then
        echo "$result" >&2; die "notarization failed"
    fi
    echo "$result" | sed 's/^/    /' >&2
    if ! echo "$result" | grep -q "status: Accepted"; then
        local id; id="$(echo "$result" | sed -n 's/^ *id: //p' | head -1)"
        [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2
        die "Apple did not accept $(basename "$file")"
    fi
}

if [ "$NOTARIZE" = 1 ]; then
    ZIP="$ROOT/build/$APP_NAME-notarize.zip"
    rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"
    say "Stapling the ticket to the app"
    xcrun stapler staple "$APP" >&2
fi

# --- disk image -------------------------------------------------------------------------------------------------------
say "Making $(basename "$DMG")"
STAGING="$ROOT/build/dmg/$APP_NAME"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

if [ "$NOTARIZE" = 1 ]; then
    notarize "$DMG"
    say "Stapling the ticket to the disk image"
    xcrun stapler staple "$DMG" >&2
    xcrun stapler validate "$DMG" >&2
fi

( cd "$DIST_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )

# --- what macOS thinks of it ------------------------------------------------------------------------------------------
say "Gatekeeper's verdict"
spctl -a -vv -t exec "$STAGING/$APP_NAME.app" 2>&1 | sed 's/^/    /' >&2 || true
if [ "$NOTARIZE" = 0 ]; then
    warn "not notarized: it runs on this Mac, but another Mac will warn that it cannot check it for malicious software. Use --notarize for a release."
fi

# --- GitHub release ---------------------------------------------------------------------------------------------------
if [ "$PUBLISH" = 1 ]; then
    REPO="$(echo "$(git -C "$ROOT" remote get-url origin)" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
    TAG="v$VERSION"
    gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && die "release $TAG already exists on $REPO (raise the version first)"
    say "Publishing $TAG on $REPO"
    gh release create "$TAG" "$DMG" "$DMG.sha256" --repo "$REPO" --title "$APP_NAME $VERSION" --generate-notes
    warn "the app's update check reads version.json from the master branch of $REPO: make sure the version in it ($VERSION, build $BUILD) is pushed"
fi

say "Done"
echo "$DMG"
echo "$(cut -d' ' -f1 "$DMG.sha256")  sha256"
