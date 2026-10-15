#!/bin/zsh
# Builds AISelection and runs ai_selection_test.m against a window of another program (ax_helper.m). Needs the Xcode command
# line tools, and Accessibility for the program that runs it (the terminal); without it the tests of Accessibility are skipped.
#
#   Sources/OpenKey/macOS/tests/run-ai-selection-test.sh
#
# Nothing is typed or pressed. The helper window opens for a second or two, without taking the keyboard.
#
# The test runs in the background and writes to a file, and this script gives up waiting after two minutes: a program that
# crashes can stay in the state "exiting" for a long time on a loaded Mac, and must not make this script hang with it.
set -e
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
ENGINE=${HERE:h:h}/engine
WORK=$(mktemp -d)
trap 'pkill -f "$WORK/ax_helper" 2>/dev/null; rm -rf "$WORK"' EXIT
cd "$WORK"

clang -fobjc-arc -Wall -g -framework Cocoa "$HERE/ax_helper.m" -o ax_helper
clang++ -std=c++17 -fobjc-arc -Wall -g -I"$MAC" -I"$ENGINE" -c "$MAC/SnippetInserter.mm" -o SnippetInserter.o
clang++ -std=c++17 -g -Wno-deprecated-declarations -I"$ENGINE" -c "$ENGINE/SnippetSearch.cpp" -o SnippetSearch.o
clang++ -std=c++17 -g -Wno-deprecated-declarations -I"$ENGINE" -c "$ENGINE/Suggest.cpp" -o Suggest.o
clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/AISelection.m" -o AISelection.o
clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/ai_selection_test.m" -o ai_selection_test.o
clang++ -framework Cocoa -framework Carbon -framework ApplicationServices SnippetInserter.o SnippetSearch.o Suggest.o AISelection.o ai_selection_test.o -o ai_selection_test

nohup ./ai_selection_test "$WORK/ax_helper" > output.txt 2>&1 &
TEST=$!
for i in {1..240}; do
    kill -0 $TEST 2>/dev/null || break
    # a program that has said its verdict is done, even if it is slow to leave
    grep -qE "ALL OK|FAILURES|skipped" output.txt && break
    sleep 0.5
done
cat output.txt
grep -q "ALL OK" output.txt || grep -q "skipped" output.txt
