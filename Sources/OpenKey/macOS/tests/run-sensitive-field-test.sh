#!/bin/zsh
# Does the suggestion bar recognise a field where a secret is typed? Standalone: nothing is shown, nothing is typed.
# VOK_PROBE_PID=<pid> [VOK_PROBE_PLACEHOLDER=<text>] [VOK_PROBE_EXPECT=sensitive|normal] also asks a running application (read-only).
set -eu
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -I"$MAC" \
    -framework Cocoa -framework ApplicationServices "$MAC/SensitiveField.m" "$MAC/CaretLocator.m" \
    "$HERE/sensitive_field_test.m" -o "$WORK/sensitive_field_test"
"$WORK/sensitive_field_test"
