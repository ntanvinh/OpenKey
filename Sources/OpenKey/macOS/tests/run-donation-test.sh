#!/bin/zsh
# Builds the donation screen (Donation, DonationWindow) and runs donation_test.m: the VietQR payload and its checksum, the picture of the
# code read back, the payee of AppInfo.h against marketing/pricing/pricing.json, and the window. Needs the Xcode command line tools.
# Nothing is shown on the screen and the clipboard of the user is not touched: it can run while somebody works on the Mac.
# It also reads back the picture of the QR code that the Windows program shows and compares engine/DonationInfo.h with AppInfo.h.
# Give a folder as the first argument to also get pictures of the window (light and dark) there.
#
#   Sources/OpenKey/macOS/tests/run-donation-test.sh [folder for pictures]
set -e
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
ROOT=${HERE:h:h:h:h}
WORK=$(mktemp -d)
cleanup() {
    rm -rf "$WORK"
    rm -f "$HOME/Library/Preferences/donation_test.plist"
}
trap cleanup EXIT
cd "$WORK"

for f in Donation DonationWindow VOKUI; do
    clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/donation_test.m" -o donation_test.o
clang -framework Cocoa -framework CoreImage *.o -o donation_test

# in the background, writing to a file, and given up on after a minute: a crashing test process stays in state UE on a loaded Mac and
# would hang a pipe (see run-ai-assistant-test.sh)
nohup ./donation_test "$ROOT/marketing/pricing/pricing.json" "$ROOT/Sources/OpenKey/engine" ${1:+"$1"} > output.txt 2>&1 &
TEST=$!
for i in {1..120}; do
    kill -0 $TEST 2>/dev/null || break
    grep -qE "ALL OK|FAILURES" output.txt && break
    sleep 0.5
done
cat output.txt
grep -q "ALL OK" output.txt
