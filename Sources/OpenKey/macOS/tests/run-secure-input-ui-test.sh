#!/bin/zsh
# The window behind "Secure Input đang bật bởi …" (SecureInputWindow), the yellow menu bar icon (VOKWarningStatusImage) and how the window
# follows SecureInputMonitor. Needs the Xcode command line tools.
# Nothing is shown on the screen and neither the keyboard nor the clipboard of the user is touched: it can run while somebody works on the
# Mac. Secure input and the session are faked, a child process that runs /bin/sleep stands in for the holder.
# Give a folder as the first argument to also get pictures of the window in every state (light and dark) and of the icon there.
#
#   Sources/OpenKey/macOS/tests/run-secure-input-ui-test.sh [folder for pictures]
set -eu
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-nullability-completeness -g \
    -DIsSecureEventInputEnabled=FakeSecure -DCGSessionCopyCurrentDictionary=FakeSession -I"$MAC" -c "$MAC/SecureInputMonitor.m" -o SecureInputMonitor.o
for f in SecureInputHolder SecureInputWindow VOKUI; do
    clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang -fobjc-arc -Wall -Wno-unused-parameter -Wno-nullability-completeness -Wno-incomplete-implementation -g \
    -DIsSecureEventInputEnabled=FakeSecure -DCGSessionCopyCurrentDictionary=FakeSession -I"$MAC" -c "$HERE/secure_input_ui_test.m" -o secure_input_ui_test.o
clang -framework Cocoa -framework Carbon *.o -o secure_input_ui_test

# in the background, writing to a file, and given up on after a minute: a crashing test process stays in state UE on a loaded Mac and
# would hang a pipe (see run-ai-assistant-test.sh)
VOK_RESOURCES="$MAC/Resources" nohup ./secure_input_ui_test ${1:+"$1"} > output.txt 2>&1 &
TEST=$!
for i in {1..240}; do
    kill -0 $TEST 2>/dev/null || break
    grep -qE "ALL OK|FAILED" output.txt && break
    sleep 0.5
done
cat output.txt
kill $TEST 2>/dev/null || true
grep -q "ALL OK" output.txt
