#!/bin/zsh
# Builds the updater (AppUpdater.m: the check for a new version, the download, the checks of the file and of the signature, the install by a
# helper that waits for the app to quit) and runs its tests against a fake GitHub that lives inside the test program (MockGitHub in
# app_update_test.m, no port is opened). Nothing is fetched from the internet, nothing is installed outside a temporary folder.
#
#   Sources/OpenKey/macOS/tests/run-app-update-test.sh
#   VOK_TEST_REAL_DMG=1 Sources/OpenKey/macOS/tests/run-app-update-test.sh     # also opens a real disk image with hdiutil, like the app does
#
# The fake releases (app_update_fixtures.py) hold their app in a zip, which the tests open with ditto; the one thing that therefore needs
# VOK_TEST_REAL_DMG=1 is the use of hdiutil. Without it that test says SKIPPED.
#
# Everything is built in a temporary folder that is removed afterwards.
set -e
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
WORK=$(mktemp -d "${TMPDIR:-/tmp}/vok-update-test.XXXXXX")
cleanup() {
    chmod -R u+w "$WORK" 2>/dev/null     # a test that stopped half way can leave a folder that cannot be written
    rm -rf "$WORK"
    rm -f "$HOME/Library/Preferences/app_update_test.plist"
}
trap cleanup EXIT
cd "$WORK"

clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/AppUpdater.m" -o AppUpdater.o
clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/app_update_test.m" -o app_update_test.o
clang -framework Cocoa -framework Security AppUpdater.o app_update_test.o -o app_update_test

python3 -I "$HERE/app_update_fixtures.py" "$WORK/fixtures"

mkdir -p run-folder
perl -e 'alarm 600; exec @ARGV' ./app_update_test "$WORK/fixtures" "$WORK/run-folder"
