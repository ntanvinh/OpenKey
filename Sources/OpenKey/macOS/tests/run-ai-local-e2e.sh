#!/bin/zsh
# The whole installation of an AI on this Mac, for real (see ai_local_e2e.m): downloads about 0.5 GB from GitHub and from the
# library of Ollama, installs Ollama, starts it, downloads a small model, asks it a question. It lives in a temporary folder
# (HOME of Ollama, another port) that is removed at the end; nothing of the user's is touched. Needs the network.
#
#   VOK_E2E=1 Sources/OpenKey/macOS/tests/run-ai-local-e2e.sh [model, default gemma3:270m] [port, default 11555]
set -e
[ -n "$VOK_E2E" ] || { echo "This downloads about 0.5 GB. Run it with VOK_E2E=1 to confirm."; exit 2; }
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
MODEL=${1:-gemma3:270m}
PORT=${2:-11555}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; rm -f "$HOME/Library/Preferences/ai_local_e2e.plist"' EXIT
cd "$WORK"
for f in AIHardware AILocalModels AIModelAdvisor AIOllama AIOllamaInstaller AIOllamaRuntime AILocalSetup AIClient AIProvider AISettings AIKeychain AIAgentCLI AIAgentProcess AIAgentRunner; do
    clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/ai_local_e2e.m" -o ai_local_e2e.o
clang -framework Cocoa -framework Security -framework IOKit *.o -o ai_local_e2e
mkdir -p home
perl -e 'alarm 2400; exec @ARGV' ./ai_local_e2e "$WORK/home" "$PORT" "$MODEL"
