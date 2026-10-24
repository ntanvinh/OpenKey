#!/bin/bash
# Syntax check of the Windows sources on a Mac or Linux with the mingw-w64 cross compiler (brew install mingw-w64).
# It does not link and does not run anything: it only proves the files compile for x86 and x64.
# Usage: scripts/check-windows.sh [file.cpp ...]   (no argument: every .cpp of the Windows project)
set -u
cd "$(dirname "$0")/.."
DIR=Sources/OpenKey/win32/OpenKey/OpenKey
FILES=("$@")
# Files of the original OpenKey that gcc is stricter about than Visual Studio (they were never compiled with gcc): not checked.
SKIP="AppDelegate.cpp BaseDialog.cpp OpenKeyHelper.cpp"
if [ ${#FILES[@]} -eq 0 ]; then
    for f in "$DIR"/*.cpp; do
        case " $SKIP " in *" $(basename "$f") "*) ;; *) FILES+=("$f");; esac
    done
fi
status=0
for cc in x86_64-w64-mingw32-g++ i686-w64-mingw32-g++; do
    command -v $cc >/dev/null || { echo "$cc not found: brew install mingw-w64"; exit 2; }
    for f in "${FILES[@]}"; do
        [ -f "$f" ] || f="$DIR/$f"
        out=$($cc -std=c++14 -fsyntax-only -DUNICODE -D_UNICODE -DWIN32 -D_WINDOWS -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00 -D_WIN32_IE=0x0A00 -finput-charset=UTF-8 \
              -Wall -Wno-unknown-pragmas -Wno-sign-compare -Wno-unused-variable -Wno-conversion-null -I"$DIR" "$f" 2>&1)
        if [ $? -ne 0 ] || echo "$out" | grep -q "warning:"; then
            echo "== $cc $f"; echo "$out" | head -40; status=1
        fi
    done
done
[ $status -eq 0 ] && echo "windows check: all files compile for x86 and x64"
exit $status
