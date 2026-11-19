#!/bin/zsh
# Makes engine/ai/ai-presets.json, the data of the ready-made conversions and picture sizes that the Windows program reads, from the words in
# macOS/ModernKey/AIPresets.m. Run it again after a word of AIPresets.m changes; tests/ai_assistant_test.m (VOK_PRESETS_JSON) fails when the
# file and the code differ.
set -e
HERE=${0:A:h}
ROOT=${HERE:h}
MAC=$ROOT/Sources/OpenKey/macOS/ModernKey
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
clang -fobjc-arc -Wall -I"$MAC" -c "$MAC/AIPresets.m" -o "$WORK/AIPresets.o"
clang -fobjc-arc -Wall -I"$MAC" -c "$HERE/make-ai-presets.m" -o "$WORK/tool.o"
clang -framework Cocoa "$WORK/AIPresets.o" "$WORK/tool.o" -o "$WORK/make-ai-presets"
"$WORK/make-ai-presets" "$ROOT/Sources/OpenKey/engine/ai/ai-presets.json"
