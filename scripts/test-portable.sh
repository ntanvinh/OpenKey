#!/bin/bash
# Builds and runs the tests of the portable code (engine/ and the pure parts of the Windows port) with the compiler of the
# machine: nothing here needs Windows or macOS frameworks, except case_transform_test (macOS only, it uses CoreFoundation).
# Usage: scripts/test-portable.sh
set -u
cd "$(dirname "$0")/../Sources/OpenKey/engine/tests"
CXX=${CXX:-c++}
OUT=$(mktemp -d)
status=0
run() { # name, sources...
    name=$1; shift
    if ! $CXX -std=c++11 -Wall -I.. "$@" -o "$OUT/$name" 2>"$OUT/$name.log"; then
        echo "BUILD FAILED: $name"; cat "$OUT/$name.log"; status=1; return
    fi
    if ! "$OUT/$name" > "$OUT/$name.out" 2>&1; then
        echo "TEST FAILED: $name"; tail -20 "$OUT/$name.out"; status=1
    else
        echo "ok: $name ($(tail -1 "$OUT/$name.out"))"
    fi
}
run suggest_test suggest_test.cpp ../Suggest.cpp ../SuggestSession.cpp
run snippet_search_test snippet_search_test.cpp ../SnippetSearch.cpp ../Suggest.cpp
run snippet_store_test snippet_store_test.cpp ../SnippetStore.cpp ../SnippetSearch.cpp ../MiniJson.cpp ../Suggest.cpp
run minijson_test minijson_test.cpp ../MiniJson.cpp
run macro_presets_test macro_presets_test.cpp ../MacroPresets.cpp
run ai_presets_test ai_presets_test.cpp ../AIPresets.cpp ../MiniJson.cpp
run donation_info_test donation_info_test.cpp ../MiniJson.cpp
run ai_protocol_test ai_protocol_test.cpp ../AIProtocol.cpp ../MiniJson.cpp
run restore_test restore_test.cpp ../Engine.cpp ../Vietnamese.cpp ../Macro.cpp ../SmartSwitchKey.cpp ../ConvertTool.cpp
run suggestion_keys_test ../../win32/OpenKey/tests/suggestion_keys_test.cpp -I../../win32/OpenKey/OpenKey
if [ "$(uname)" = "Darwin" ]; then
    run case_transform_test case_transform_test.cpp ../CaseTransform.cpp -framework CoreFoundation
fi
rm -rf "$OUT"
exit $status
