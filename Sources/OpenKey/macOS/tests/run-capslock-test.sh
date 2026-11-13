#!/bin/zsh
# The Caps Lock notice: CapsLockMonitor (the state and the notification), CapsLockToast (the message) and the red menu bar icon
# (VOKCapsLockStatusImage). Needs the Xcode command line tools.
# Nothing is shown on the screen and neither the keyboard nor the clipboard of the user is touched: it can run while somebody works on
# the Mac. The keyboard is a stand-in, the toast sits far outside every screen.
# Give a folder as the first argument to also get pictures of the toast (on and off, light and dark) and of the icons there.
#
#   Sources/OpenKey/macOS/tests/run-capslock-test.sh [folder for pictures]
set -eu
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -g -DVOKReadCapsLock=FakeCaps -I"$MAC" -c "$MAC/CapsLockMonitor.m" -o CapsLockMonitor.o
for f in CapsLockToast VOKUI; do
    clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang -fobjc-arc -Wall -Wno-unused-parameter -g -I"$MAC" -c "$HERE/capslock_test.m" -o capslock_test.o
clang -framework Cocoa -framework QuartzCore capslock_test.o CapsLockMonitor.o CapsLockToast.o VOKUI.o -o capslock_test

# in the background, writing to a file, and given up on after a minute: a crashing test process stays in state UE on a loaded Mac and
# would hang a pipe (see run-ai-assistant-test.sh)
VOK_RESOURCES="$MAC/Resources" nohup ./capslock_test ${1:+"$1"} > output.txt 2>&1 &
TEST=$!
for i in {1..240}; do
    kill -0 $TEST 2>/dev/null || break
    grep -qE "ALL OK|FAILED" output.txt && break
    sleep 0.5
done
cat output.txt
kill $TEST 2>/dev/null || true
grep -q "ALL OK" output.txt
