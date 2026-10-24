#!/bin/zsh
set -eu
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -I"$MAC" \
    -framework Cocoa -framework QuartzCore "$MAC/SuggestionPanel.m" \
    "$HERE/suggestion_panel_test.m" -o "$WORK/suggestion_panel_test"
"$WORK/suggestion_panel_test"
