#!/bin/zsh
# What is found out about the process that holds secure input (SecureInputHolder) and how SecureInputMonitor hands it on.
# Standalone: secure input, the session and the input sources are faked (the real input source of the Mac is never touched), a child
# process that runs /bin/sleep stands in for the holder, nothing is shown.
#
#   Sources/OpenKey/macOS/tests/run-secure-input-holder-test.sh
set -eu
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-nullability-completeness -Wno-incomplete-implementation \
    -DIsSecureEventInputEnabled=FakeSecure -DCGSessionCopyCurrentDictionary=FakeSession \
    -DTISCopyCurrentKeyboardInputSource=FakeCurrentSource -DTISCreateInputSourceList=FakeSourceList \
    -DTISSelectInputSource=FakeSelectSource -DTISGetInputSourceProperty=FakeSourceProperty -I"$MAC" \
    -framework Cocoa -framework Carbon "$MAC/SecureInputMonitor.m" "$MAC/SecureInputHolder.m" \
    "$HERE/secure_input_holder_test.m" -o "$WORK/secure_input_holder_test"
# in the background, writing to a file, and given up on after a minute (see run-donation-test.sh)
cd "$WORK"
nohup ./secure_input_holder_test > output.txt 2>&1 &
TEST=$!
for i in {1..120}; do
    kill -0 $TEST 2>/dev/null || break
    grep -qE "ALL OK|FAILED" output.txt && break
    sleep 0.5
done
cat output.txt
kill $TEST 2>/dev/null || true
grep -q "ALL OK" output.txt
