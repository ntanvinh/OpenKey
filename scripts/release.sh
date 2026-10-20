#!/bin/bash
# Build, sign and package VOpenKey AI for release, and with a version argument do the whole release in one go.
#
#   scripts/release.sh patch           raise the version (3.0.0 -> 3.0.1; minor, major or an explicit 3.1.0 also work), build,
#                                      sign, notarize, push, publish the GitHub release with the dmg, wait for the Windows
#                                      build that GitHub Actions attaches to it, and only then announce the new version in
#                                      version.json (read by the Windows app and by Mac apps older than the self-updating one).
#                                      The Mac app finds the release by itself, from GitHub, as soon as it is online and downloads
#                                      VOpenKey-<version>.dmg. The release also carries VOpenKey.dmg, the same file without the
#                                      version in its name, for the fixed link of the website. "current" releases the version
#                                      that is in the project without raising it.
#   scripts/release.sh patch --yes     the same without asking for confirmation
#   scripts/release.sh patch --dry-run check everything and say what would happen, change nothing
#
#   scripts/release.sh                 no version argument: only build, sign, make dist/VOpenKey-<version>.dmg (+ .sha256)
#   scripts/release.sh --notarize      also have Apple notarize it and staple the ticket (what other Macs need to open it
#                                      without a warning)
#   scripts/release.sh --publish       also create the GitHub release with the dmg; this puts it online, so it needs
#                                      --notarize as well (ALLOW_UNNOTARIZED=1 to publish anyway)
#   scripts/release.sh --announce      only write the current version to version.json, commit and push it (the last step of
#                                      a release, for when the Windows build had to be repaired by hand)
#
#   --no-windows                       do not wait for, and do not announce, the Windows build
#
# Signing uses the first "Developer ID Application" certificate in the keychain (SIGN_IDENTITY to pick another).
#
# Notarizing needs your Apple ID credentials in the keychain, once:
#   xcrun notarytool store-credentials VOpenKey-notary --apple-id <your apple id> --team-id <team id> --password <app-specific password>
# (app-specific password: appleid.apple.com > Sign-In and Security). NOTARY_PROFILE changes the profile name.
#
# The Windows zip is built by .github/workflows/release-windows.yml when the release is published, see RELEASING.md.
source "$(dirname "$0")/common.sh"

BUMP=""; NOTARIZE=0; PUBLISH=0; WINDOWS=1; ASSUME_YES=0; DRY_RUN=0; ANNOUNCE_ONLY=0
for arg in "$@"; do
    case "$arg" in
        patch|minor|major|current) BUMP="$arg" ;;
        [0-9]*.[0-9]*.[0-9]*)      BUMP="$arg" ;;
        --notarize)  NOTARIZE=1 ;;
        --publish)   PUBLISH=1 ;;
        --no-windows) WINDOWS=0 ;;
        --yes|-y)    ASSUME_YES=1 ;;
        --dry-run)   DRY_RUN=1 ;;
        --announce)  ANNOUNCE_ONLY=1 ;;
        -h|--help)   sed -n '2,/^source/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $arg (see --help)" ;;
    esac
done
[ "$DRY_RUN" = 0 ] || [ -n "$BUMP" ] || die "--dry-run goes with a version argument: scripts/release.sh patch --dry-run"
FULL=0
if [ -n "$BUMP" ]; then # a whole release: it goes online, so it is notarized
    FULL=1; PUBLISH=1
    [ "${ALLOW_UNNOTARIZED:-0}" = 1 ] || NOTARIZE=1
fi
NOTARY_PROFILE="${NOTARY_PROFILE:-VOpenKey-notary}"
REPO="$(git -C "$ROOT" config --get remote.origin.url | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
VERSION_SH="$ROOT/scripts/version.sh"
EDIT_FILES=("Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj" "Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.rc" "CHANGELOG.md")
WINDOWS_WORKFLOW=".github/workflows/release-windows.yml"

# if something goes wrong after the version was raised, the files go back to what they were
EDITED=0
on_exit() {
    local status=$?
    if [ "$status" -ne 0 ] && [ "$EDITED" = 1 ]; then
        git -C "$ROOT" checkout -- "${EDIT_FILES[@]}" 2>/dev/null && warn "the release did not finish: the version change was undone"
    fi
}
trap on_exit EXIT

need_gh() {
    command -v gh >/dev/null || die "this needs the GitHub CLI (brew install gh) and 'gh auth login'"
    gh auth status >/dev/null 2>&1 || die "gh is not logged in: run 'gh auth login'"
}
need_clean_master() {
    [ "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)" = master ] || die "releases are made from the master branch"
    git -C "$ROOT" fetch origin master --quiet || die "cannot reach GitHub to check master"
    [ "$(git -C "$ROOT" rev-list --count HEAD..origin/master)" = 0 ] || die "master is behind origin/master: git pull first"
}
need_clean_tree() {
    [ -z "$(git -C "$ROOT" status --porcelain)" ] || die "there are uncommitted changes, commit or stash them first (the release makes its own commit):
$(git -C "$ROOT" status --short | sed 's/^/    /')"
}

# --- announce only --------------------------------------------------------------------------------------------------
announce_release() {
    local flag=""; [ "$WINDOWS" = 1 ] || flag="--no-windows"
    "$VERSION_SH" announce $flag
    git -C "$ROOT" add version.json
    if git -C "$ROOT" diff --cached --quiet; then say "version.json already says this version"; return; fi
    git -C "$ROOT" commit -q -m "release: announce $(setting MARKETING_VERSION) in version.json"
    git -C "$ROOT" push -q origin HEAD:master
    say "Pushed: from now on the apps tell users about $(setting MARKETING_VERSION)"
}
if [ "$ANNOUNCE_ONLY" = 1 ]; then
    need_gh; need_clean_master; need_clean_tree
    announce_release
    exit 0
fi

# --- checks, before anything is changed -----------------------------------------------------------------------------
if [ "$PUBLISH" = 1 ] && [ "$NOTARIZE" = 0 ] && [ "${ALLOW_UNNOTARIZED:-0}" != 1 ]; then
    die "--publish needs --notarize: an app that is not notarized cannot be opened on other Macs without a warning (ALLOW_UNNOTARIZED=1 to override)"
fi
if [ "$NOTARIZE" = 1 ]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || die "no notarytool profile named '$NOTARY_PROFILE' in the keychain. Create it once with:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <your apple id> --team-id <team id> --password <app-specific password>"
fi
[ "$PUBLISH" = 1 ] && need_gh
if [ "$FULL" = 1 ]; then
    need_clean_master
    need_clean_tree
    if [ "$WINDOWS" = 1 ]; then
        git -C "$ROOT" ls-files --error-unmatch "$WINDOWS_WORKFLOW" >/dev/null 2>&1 \
            || die "$WINDOWS_WORKFLOW is not committed: without it GitHub does not build the Windows version (--no-windows to skip it)"
    fi
    NEXT="$("$VERSION_SH" next "$BUMP")" # a plain assignment: when version.sh refuses the version the script stops here
    read -r NEXT_VERSION NEXT_BUILD <<< "$NEXT"
    [ -n "$NEXT_VERSION" ] && [ -n "$NEXT_BUILD" ] || die "could not work out the next version"
    TAG="v$NEXT_VERSION"
    gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && die "release $TAG already exists on $REPO"
    git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"

    say "Plan"
    {
        echo "  $APP_NAME $(setting MARKETING_VERSION) (build $(setting CURRENT_PROJECT_VERSION))  ->  $NEXT_VERSION (build $NEXT_BUILD)"
        echo "  1. raise the version in the Xcode project, the Windows resources and the change log"
        if [ "$NOTARIZE" = 1 ]; then echo "  2. build, sign and notarize $DISPLAY_NAME.app and the dmg"; else echo "  2. build and sign $DISPLAY_NAME.app and the dmg (NOT notarized)"; fi
        echo "  3. commit and push to master, create the GitHub release $TAG on $REPO with the dmg"
        [ "$WINDOWS" = 1 ] && echo "  4. wait for GitHub Actions to build the Windows version and attach it to the release"
        echo "  5. write the version in version.json and push it: only then does the Windows app offer the update (the Mac app already does, from step 3)"
    } >&2
    [ "$DRY_RUN" = 1 ] && { say "Dry run: every check passed, nothing was changed"; exit 0; }
    if [ "$ASSUME_YES" != 1 ]; then
        [ -t 0 ] || die "no terminal to ask on, use --yes"
        read -r -p "Go ahead? This puts a release online. [y/N] " answer
        case "$answer" in [yY]*) ;; *) die "cancelled" ;; esac
    fi

    "$VERSION_SH" bump "$BUMP"
    EDITED=1
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
echo "    architectures: $(lipo -archs "$APP/Contents/MacOS/$DISPLAY_NAME")" >&2
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
ditto "$APP" "$STAGING/$DISPLAY_NAME.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$DISPLAY_NAME $VERSION" -srcfolder "$STAGING" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

if [ "$NOTARIZE" = 1 ]; then
    notarize "$DMG"
    say "Stapling the ticket to the disk image"
    xcrun stapler staple "$DMG" >&2
    xcrun stapler validate "$DMG" >&2
fi

( cd "$DIST_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )

# The same file under a name without the version, attached to every release too: GitHub sends
#   https://github.com/<repo>/releases/latest/download/VOpenKey.dmg
# to this file of the newest release, so the website links to that address and never has to change it. (The app updates itself from
# VOpenKey-<version>.dmg, it does not use this copy.)
LATEST_DMG="$DIST_DIR/$APP_NAME.dmg"
cp "$DMG" "$LATEST_DMG"

# --- what macOS thinks of it ------------------------------------------------------------------------------------------
say "Gatekeeper's verdict"
spctl -a -vv -t exec "$STAGING/$DISPLAY_NAME.app" 2>&1 | sed 's/^/    /' >&2 || true
if [ "$NOTARIZE" = 0 ]; then
    warn "not notarized: it runs on this Mac, but another Mac will warn that it cannot check it for malicious software. Use --notarize for a release."
fi

# --- GitHub release ---------------------------------------------------------------------------------------------------
wait_for_windows() { # <tag> <commit>
    local tag="$1" sha="$2" run="" i status conclusion url
    say "Waiting for GitHub Actions to build the Windows version (a few minutes)"
    for i in $(seq 1 24); do
        run="$(gh run list --repo "$REPO" --workflow release-windows.yml --event release --json databaseId,headSha \
               --jq ".[] | select(.headSha == \"$sha\") | .databaseId" 2>/dev/null | head -1)"
        [ -n "$run" ] && break
        sleep 5
    done
    [ -n "$run" ] || die "GitHub did not start the Windows build. Are Actions enabled on $REPO (Settings > Actions)? The macOS release is online.
After fixing it: gh workflow run release-windows.yml --repo $REPO -f tag=$tag   then   scripts/release.sh --announce"
    url="https://github.com/$REPO/actions/runs/$run"
    while true; do
        status="$(gh run view "$run" --repo "$REPO" --json status --jq .status)"
        [ "$status" = completed ] && break
        sleep 15
    done
    conclusion="$(gh run view "$run" --repo "$REPO" --json conclusion --jq .conclusion)"
    [ "$conclusion" = success ] || die "the Windows build ended with '$conclusion': $url
The macOS release is online (the Mac app updates itself from it) and version.json was not changed, so the Windows app is not offered the update yet.
After fixing it: gh workflow run release-windows.yml --repo $REPO -f tag=$tag   then   scripts/release.sh --announce"
    gh release view "$tag" --repo "$REPO" --json assets --jq '.assets[].name' | grep -q "^$APP_NAME-.*-Windows.zip$" \
        || die "the Windows build succeeded but its zip is not on the release $tag: $url"
    say "The Windows version is on the release"
}

if [ "$PUBLISH" = 1 ]; then
    TAG="v$VERSION"
    gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && die "release $TAG already exists on $REPO (raise the version first)"
    if [ "$FULL" = 1 ]; then
        say "Committing and pushing the new version"
        git -C "$ROOT" add "${EDIT_FILES[@]}"
        if ! git -C "$ROOT" diff --cached --quiet; then
            git -C "$ROOT" commit -q -m "release: $APP_NAME $VERSION (build $BUILD)"
        fi
        EDITED=0 # it is in the history now, it stays
        git -C "$ROOT" push -q origin HEAD:master
        SHA="$(git -C "$ROOT" rev-parse HEAD)"
        NOTES="$ROOT/build/release-notes.md"
        "$VERSION_SH" notes > "$NOTES"
        say "Publishing $TAG on $REPO"
        if [ -s "$NOTES" ]; then
            gh release create "$TAG" "$DMG" "$DMG.sha256" "$LATEST_DMG" --repo "$REPO" --target "$SHA" --title "$DISPLAY_NAME $VERSION" --notes-file "$NOTES"
        else
            gh release create "$TAG" "$DMG" "$DMG.sha256" "$LATEST_DMG" --repo "$REPO" --target "$SHA" --title "$DISPLAY_NAME $VERSION" --generate-notes
        fi
        if [ "$WINDOWS" = 1 ]; then wait_for_windows "$TAG" "$SHA"; fi
        announce_release
        say "Released: https://github.com/$REPO/releases/tag/$TAG"
        say "Always the newest version, for the website: https://github.com/$REPO/releases/latest/download/$APP_NAME.dmg"
    else
        say "Publishing $TAG on $REPO"
        gh release create "$TAG" "$DMG" "$DMG.sha256" "$LATEST_DMG" --repo "$REPO" --title "$DISPLAY_NAME $VERSION" --generate-notes
        warn "the Mac app finds this release by itself; the Windows app and the Mac apps older than the self-updating one read version.json from the master branch of $REPO: make sure the version in it ($VERSION, build $BUILD) is pushed (scripts/release.sh --announce)"
    fi
fi

say "Done"
echo "$DMG"
echo "$(cut -d' ' -f1 "$DMG.sha256")  sha256"
