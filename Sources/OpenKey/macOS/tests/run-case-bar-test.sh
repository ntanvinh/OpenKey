#!/bin/zsh
# Builds the case bar (CaseTransform, CaseBarPanel, CaseBar) and runs case_transform_test.m (the Unicode rules) and
# case_bar_test.m (when the list shows, which keys it takes, what it pastes; the real panel, moved off screen at once).
#
#   Sources/OpenKey/macOS/tests/run-case-bar-test.sh [directory for pictures of the panel]
#
# Nothing is typed or pressed and no application is asked anything: the application, Accessibility and the paste are stand-ins.
set -e
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
ENGINE=${HERE:h:h}/engine
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

clang -fobjc-arc -Wall -g -I"$MAC" -framework Foundation "$MAC/CaseTransform.m" "$HERE/case_transform_test.m" -o case_transform_test
./case_transform_test

clang++ -std=c++17 -fobjc-arc -Wall -g -I"$MAC" -I"$ENGINE" -c "$MAC/SnippetInserter.mm" -o SnippetInserter.o
clang++ -std=c++17 -g -Wno-deprecated-declarations -I"$ENGINE" -c "$ENGINE/SnippetSearch.cpp" -o SnippetSearch.o
clang++ -std=c++17 -g -Wno-deprecated-declarations -I"$ENGINE" -c "$ENGINE/Suggest.cpp" -o Suggest.o
for f in CaseTransform CaseBarPanel CaseBar AISelection CaretLocator SuggestionPanel; do
    clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/case_bar_test.m" -o case_bar_test.o
clang++ -framework Cocoa -framework Carbon -framework ApplicationServices SnippetInserter.o SnippetSearch.o Suggest.o CaseTransform.o \
    CaseBarPanel.o CaseBar.o AISelection.o CaretLocator.o SuggestionPanel.o case_bar_test.o -o case_bar_test
nohup ./case_bar_test "${1:-}" > output.txt 2>&1 &
TEST=$!
for i in {1..240}; do
    kill -0 $TEST 2>/dev/null || break
    grep -qE "ALL OK|FAILURES" output.txt && break
    sleep 0.5
done
cat output.txt
grep -q "ALL OK" output.txt
