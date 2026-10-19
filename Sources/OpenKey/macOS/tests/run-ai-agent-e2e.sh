#!/bin/zsh
# The AI agent programs for real (see ai_agent_e2e.m): each one that is installed (codex, claude, agy) is asked one short question
# through the code of the assistant. It uses the accounts the programs are signed in with, a few words each, and the network.
# Nothing of the user's is changed.
#
#   VOK_E2E=1 Sources/OpenKey/macOS/tests/run-ai-agent-e2e.sh [codex-cli] [claude-cli] [agy-cli]
set -e
[ -n "$VOK_E2E" ] || { echo "This uses the accounts of the installed agent programs (a few words each). Run it with VOK_E2E=1 to confirm."; exit 2; }
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ai-agent-e2e.XXXXXX")
trap 'rm -rf "$WORK"; rm -f "$HOME/Library/Preferences/ai_agent_e2e.plist"' EXIT
cd "$WORK"
for f in AIProvider AIKeychain AISettings AIClient AIAgentCLI AIAgentProcess AIAgentRunner; do
    clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/ai_agent_e2e.m" -o ai_agent_e2e.o
clang -framework Cocoa -framework Security *.o -o ai_agent_e2e
perl -e 'alarm 900; exec @ARGV' ./ai_agent_e2e "$@"
