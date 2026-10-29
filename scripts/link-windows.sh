#!/bin/bash
# Compiles and LINKS the Windows program with mingw-w64 (x64 and x86), without resources, to find what the syntax check cannot:
# functions that are declared and never defined, libraries that are missing. It does not make a program that can be shipped (that
# is the job of Visual Studio, see .github/workflows/windows-build.yml) and nothing is run.
# Usage: scripts/link-windows.sh [x64|x86]   (both when no argument)
set -u
cd "$(dirname "$0")/.."
SRC=Sources/OpenKey/win32/OpenKey/OpenKey
ENG=Sources/OpenKey/engine
OUT=${TMPDIR:-/tmp}/vok-link
mkdir -p "$OUT"
status=0
for arch in ${1:-x64 x86}; do
    if [ "$arch" = x64 ]; then cc=x86_64-w64-mingw32-g++; else cc=i686-w64-mingw32-g++; fi
    command -v $cc >/dev/null || { echo "$cc not found: brew install mingw-w64"; exit 2; }
    dir="$OUT/$arch"; mkdir -p "$dir"
    objs=()
    sources=($(ls $SRC/*.cpp) $ENG/ConvertTool.cpp $ENG/Engine.cpp $ENG/Macro.cpp $ENG/SmartSwitchKey.cpp $ENG/Vietnamese.cpp \
              $ENG/MiniJson.cpp $ENG/SnippetSearch.cpp $ENG/SnippetStore.cpp $ENG/Suggest.cpp $ENG/SuggestSession.cpp $ENG/SensitiveField.cpp \
              $ENG/CaseTransform.cpp $ENG/MacroPresets.cpp $ENG/AIProtocol.cpp $ENG/AIPresets.cpp)
    pids=()
    for f in "${sources[@]}"; do
        o="$dir/$(basename "$f" .cpp).o"; objs+=("$o"); rm -f "$o"
        ( $cc -std=c++14 -c -w -fpermissive -O0 -DUNICODE -D_UNICODE -DWIN32 -D_WINDOWS -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00 \
            -D_WIN32_IE=0x0A00 -DGetTempPath2=GetTempPathW -include algorithm -finput-charset=UTF-8 -I"$SRC" "$f" -o "$o" 2>"$o.log" || { echo "COMPILE FAILED ($arch): $f"; head -20 "$o.log"; } ) &
        pids+=($!)
        if [ ${#pids[@]} -ge 6 ]; then wait "${pids[0]}"; pids=("${pids[@]:1}"); fi
    done
    wait
    for o in "${objs[@]}"; do [ -f "$o" ] || { status=1; }; done
    [ $status -ne 0 ] && continue
    if ! $cc -municode -mwindows -static -o "$dir/OpenKey.exe" "${objs[@]}" \
        -lcomctl32 -limm32 -lpsapi -lshell32 -lwinhttp -lcrypt32 -loleacc -lole32 -loleaut32 -luuid -lshlwapi -lurlmon \
        -lversion -lnormaliz -luxtheme -lgdi32 -luser32 -ladvapi32 -lcomdlg32 -lwininet 2>"$dir/link.log"; then
        echo "LINK FAILED ($arch):"; grep -E "undefined reference|cannot find" "$dir/link.log" | sort | uniq | head -40; status=1
    else
        echo "link ok ($arch): $(ls -l "$dir/OpenKey.exe" | awk '{print $5}') bytes"
    fi
done
exit $status
