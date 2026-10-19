#!/bin/zsh
# Builds the AI classes of the app and runs ai_test.m against the fake server mock_ai_server.py, which it starts and stops.
# Needs the Xcode command line tools and python3. No real AI service is contacted, no real key is used.
#
#   Sources/OpenKey/macOS/tests/run-ai-test.sh
#
# Everything is built in a temporary folder that is removed afterwards.
set -e
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
WORK=$(mktemp -d)
SERVER=""
cleanup() {
    [ -n "$SERVER" ] && kill $SERVER 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT
cd "$WORK"

for f in AIProvider AIKeychain AISettings AIClient AIAgentCLI AIAgentProcess AIAgentRunner; do
    clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/ai_test.m" -o ai_test.o
clang -framework Cocoa -framework Security *.o -o ai_test

python3 -I "$HERE/mock_ai_server.py" > port.txt &
SERVER=$!
for i in {1..50}; do [ -s port.txt ] && break; sleep 0.1; done
PORT=$(head -1 port.txt)
[ -n "$PORT" ] || { echo "the fake server did not start"; exit 2; }

# the test keeps its preferences in a folder of its own, not in ~/Library/Preferences
HOME_BACKUP=$HOME
perl -e 'alarm 180; exec @ARGV' ./ai_test "$PORT"
STATUS=$?
rm -f "$HOME_BACKUP/Library/Preferences/ai_test.plist"
exit $STATUS
