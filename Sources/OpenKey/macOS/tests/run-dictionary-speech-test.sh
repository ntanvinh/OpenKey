#!/bin/zsh
# Builds WordSpeaker + DictionaryPalette + DictionaryService + portable engine and runs dictionary_speech_test: the edge of the
# dictionary window in light and dark, and the speaker button / ⌘P for English headwords. No network, no server, no sound:
# the voice is replaced by a hook, and the two test dictionaries are made "installed" from local zips.
#
#   Sources/OpenKey/macOS/tests/run-dictionary-speech-test.sh [snapshot-dir]
#
set -e
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
ENGINE=${HERE:h:h}/engine
WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

cd "$WORK"

python3 -I - "$WORK" << 'EOF'
import gzip, json, os, struct, sys, zipfile

work = sys.argv[1]

def make_stardict_zip(out_zip, bookname, same_type_seq, entries):
    idx = bytearray()
    dic = bytearray()
    for word, body in sorted(entries, key=lambda e: e[0]):
        b = body.encode("utf-8")
        off = len(dic)
        dic.extend(b)
        idx.extend(word.encode("utf-8") + b"\x00")
        idx.extend(struct.pack(">II", off, len(b)))
    ifo = (f"StarDict's dict ifo file\nversion=3.0.0\nbookname={bookname}\n"
           f"wordcount={len(entries)}\nidxfilesize={len(idx)}\nsametypesequence={same_type_seq}\n")
    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("dict/data.ifo", ifo)
        zf.writestr("dict/data.idx", bytes(idx))
        zf.writestr("dict/data.dict.dz", gzip.compress(bytes(dic)))

make_stardict_zip(os.path.join(work, "en-vi.zip"), "Anh - Việt (Test)", "h", [
    ("hello", '<span class="pos">thán từ</span><li>xin chào</li><div class="ex">Hello world! <i>Xin chào thế giới!</i></div>'),
    ("apple", '<div class="hw">apple <span class="ipa">/ˈæp.əl/</span></div><span class="pos">danh từ</span><li>quả táo</li>'),
    ("an", '<span class="pos">mạo từ</span><li>một</li>'),
])
make_stardict_zip(os.path.join(work, "vi-en.zip"), "Việt - Anh (Test)", "m", [
    ("ba", "@ba\n* số từ\n- three"),
    ("xin chào", "@xin chào\n* thán từ\n- hello, hi"),
    ("an", "@an\n* tính từ\n- safe"),
])

def entry(did, name, short, badge, src, dst, priority, size):
    return {"id": did, "name": name, "shortName": short, "badge": badge, "sourceLang": src, "targetLang": dst,
            "priority": priority, "recommended": True, "headwordCount": 3, "downloadBytes": size,
            "author": "Test", "license": "GPL", "description": "Test dictionary, never downloaded",
            "format": "stardict-zip",
            "files": [{"name": did + ".zip", "url": "https://example.invalid/" + did + ".zip", "sizeBytes": size}]}

with open(os.path.join(work, "catalog.json"), "w", encoding="utf-8") as f:
    json.dump({"version": 1, "dictionaries": [
        entry("en-vi-test", "Anh - Việt (Test)", "Anh-Việt", "EN→VI", "en", "vi", 10, 1000),
        entry("vi-en-test", "Việt - Anh (Test)", "Việt-Anh", "VI→EN", "vi", "en", 20, 1000),
    ]}, f)
EOF

for f in DictCatalog DictInflate DictStore MiniJson Suggest WordSpeech; do
    clang++ -std=c++17 -O2 -g -I"$ENGINE" -c "$ENGINE/$f.cpp" -o $f.o
done
clang++ -std=c++17 -fobjc-arc -g -I"$MAC" -I"$ENGINE" -c "$MAC/DictionaryService.mm" -o DictionaryService.o
clang++ -std=c++17 -fobjc-arc -g -I"$MAC" -I"$ENGINE" -c "$MAC/WordSpeaker.mm" -o WordSpeaker.o
clang++ -std=c++17 -fobjc-arc -g -I"$MAC" -I"$ENGINE" -c "$MAC/SnippetInserter.mm" -o SnippetInserter.o
clang++ -std=c++17 -g -Wno-deprecated-declarations -I"$ENGINE" -c "$ENGINE/SnippetSearch.cpp" -o SnippetSearch.o
for f in DictionaryPalette AISelection VOKUI; do
    clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/dictionary_speech_test.m" -o dictionary_speech_test.o
clang++ -framework Cocoa -framework QuartzCore -framework Carbon -framework ApplicationServices -framework AVFoundation \
    -framework UniformTypeIdentifiers *.o -o dictionary_speech_test

./dictionary_speech_test "$WORK/catalog.json" "$WORK/en-vi.zip" "$WORK/vi-en.zip" "$WORK/run" "${1:-}"
