#!/bin/zsh
# Builds the classes that run AI agent programs (Codex, Claude Code, Antigravity) and runs ai_agent_test.m against a fake program,
# fake_agent_cli.py, that stands in for all three. No real program is run and nothing is sent anywhere. Needs the Xcode command line
# tools and python3.
#
#   Sources/OpenKey/macOS/tests/run-ai-agent-test.sh
#
# When `codex` is installed, its model catalog (`codex debug models`: offline, no account needed) is also read and checked, to
# catch the day the real program changes the shape of it. Everything is built in a temporary folder that is removed afterwards.
set -e
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ai-agent-test.XXXXXX")
trap 'rm -rf "$WORK"; rm -f "$HOME/Library/Preferences/ai_agent_test.plist"' EXIT
cd "$WORK"

for f in AIProvider AIKeychain AISettings AIClient AIAgentCLI AIAgentProcess AIAgentRunner; do
    clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/ai_agent_test.m" -o ai_agent_test.o
clang -framework Cocoa -framework Security *.o -o ai_agent_test

CATALOG=""
if command -v codex >/dev/null 2>&1; then
    codex debug models > catalog.json 2>/dev/null && CATALOG="$WORK/catalog.json" || CATALOG=""
fi
[ -n "$CATALOG" ] || echo "(codex is not installed here: its real catalog is not checked)"

perl -e 'alarm 240; exec @ARGV' ./ai_agent_test "$HERE/fake_agent_cli.py" "$CATALOG"
