#!/bin/zsh
# The suggestion bar goes away when macOS starts hiding the keys. Standalone; secure input is faked, no window is shown.
set -eu
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-nullability-completeness -DIsSecureEventInputEnabled=FakeSecure -I"$MAC" \
    -framework Cocoa -framework Carbon "$MAC/SecureInputMonitor.m" \
    "$HERE/secure_input_suggestion_test.m" -o "$WORK/secure_input_suggestion_test"
"$WORK/secure_input_suggestion_test"
