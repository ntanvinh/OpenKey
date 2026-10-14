#!/bin/zsh
# Builds and runs snippets_test.m against the real sources of the app. Needs the Xcode command line tools.
#
#   Sources/OpenKey/macOS/tests/run-snippets-test.sh
#
# Everything is built and written in a temporary folder that is removed afterwards.
set -e
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
ENGINE=${HERE:h:h}/engine
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

for f in SnippetStore SnippetInserter; do
    clang++ -std=c++17 -fobjc-arc -Wall -g -I"$MAC" -I"$ENGINE" -c "$MAC/$f.mm" -o $f.o
done
for f in SnippetSearch Suggest; do
    clang++ -std=c++17 -g -I"$ENGINE" -c "$ENGINE/$f.cpp" -o $f.o
done
for f in SnippetPalette SnippetEditorController VOKUI; do
    clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/snippets_test.m" -o test.o
clang++ -framework Cocoa -framework Carbon *.o -o snippets_test

# the files the test writes go to the temporary folder too
TMPDIR="$WORK/" perl -e 'alarm 120; exec @ARGV' ./snippets_test "$ENGINE/snippets/default-snippets.json" 2>&1 | grep -v "could not be read"
exit ${pipestatus[1]}
