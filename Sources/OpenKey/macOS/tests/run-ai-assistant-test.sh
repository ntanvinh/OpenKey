#!/bin/zsh
# Builds the AI window and runs ai_assistant_test.m against the fake server mock_ai_server.py, which it starts and stops.
# Needs the Xcode command line tools and python3. No real AI service is contacted, no real key is used. The window opens for a
# moment on the screen, without taking the keyboard from the application in front.
#
#   Sources/OpenKey/macOS/tests/run-ai-assistant-test.sh
set -e
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
ENGINE=${HERE:h:h}/engine
WORK=$(mktemp -d)
SERVER=""
cleanup() {
    [ -n "$SERVER" ] && kill $SERVER 2>/dev/null
    rm -rf "$WORK"
    rm -f "$HOME/Library/Preferences/ai_assistant_test.plist"
}
trap cleanup EXIT
cd "$WORK"

clang++ -std=c++17 -fobjc-arc -Wall -g -I"$MAC" -I"$ENGINE" -c "$MAC/SnippetInserter.mm" -o SnippetInserter.o
for f in SnippetSearch Suggest; do
    clang++ -std=c++17 -g -Wno-deprecated-declarations -I"$ENGINE" -c "$ENGINE/$f.cpp" -o $f.o
done
for f in AIProvider AIKeychain AISettings AIClient AIHardware AIOllama AIOllamaInstaller AIOllamaRuntime AISelection AIAssistant VOKUI; do
    clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/ai_assistant_test.m" -o ai_assistant_test.o
clang++ -framework Cocoa -framework Carbon -framework Security -framework IOKit -framework ApplicationServices *.o -o ai_assistant_test

python3 -I "$HERE/mock_ai_server.py" > port.txt &
SERVER=$!
for i in {1..50}; do [ -s port.txt ] && break; sleep 0.1; done
PORT=$(head -1 port.txt)
[ -n "$PORT" ] || { echo "the fake server did not start"; exit 2; }

# in the background, writing to a file, and given up on after two minutes: see run-ai-selection-test.sh
FREE=$(python3 -I -c "import socket; s = socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1])")
nohup ./ai_assistant_test "$PORT" "$HERE/fake_ollama.py" "$FREE" "$WORK" > output.txt 2>&1 &
TEST=$!
for i in {1..240}; do
    kill -0 $TEST 2>/dev/null || break
    grep -qE "ALL OK|FAILURES" output.txt && break
    sleep 0.5
done
cat output.txt
grep -q "ALL OK" output.txt
