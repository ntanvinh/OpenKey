#!/bin/zsh
# Builds OpenKey.mm (the event tap) with the real typing engine and runs tap_test.mm against it. Needs the Xcode command
# line tools. Nothing is sent to the system: see tap_test.mm.
#
#   Sources/OpenKey/macOS/tests/run-tap-test.sh
#
# Everything is built in a temporary folder that is removed afterwards.
set -e
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
ENGINE=${HERE:h:h}/engine
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

for f in Engine Vietnamese Macro SmartSwitchKey ConvertTool Suggest SuggestSession SnippetSearch; do
    clang++ -std=c++17 -g -Wno-deprecated-declarations -I"$ENGINE" -c "$ENGINE/$f.cpp" -o $f.o
done
# the event tap itself: what it posts goes to Posted() of the test instead of the system
clang++ -std=c++17 -fobjc-arc -g -DCGEventTapPostEvent=Posted -I"$MAC" -I"$ENGINE" -c "$MAC/OpenKey.mm" -o OpenKey.o
for f in SuggestionController SnippetStore SnippetInserter; do
    clang++ -std=c++17 -fobjc-arc -g -I"$MAC" -I"$ENGINE" -c "$MAC/$f.mm" -o $f.o
done
for f in CaretLocator SuggestionPanel SecureInputMonitor ShortcutRecorder VOKUI SnippetPalette SnippetEditorController WordRestore; do
    clang -fobjc-arc -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang++ -std=c++17 -fobjc-arc -g -Wno-incomplete-implementation -I"$MAC" -I"$ENGINE" -c "$HERE/tap_test.mm" -o tap_test.o
clang++ -framework Cocoa -framework Carbon -framework ApplicationServices *.o -o tap_test

perl -e 'alarm 120; exec @ARGV' ./tap_test
