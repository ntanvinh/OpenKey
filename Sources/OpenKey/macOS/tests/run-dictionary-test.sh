#!/bin/zsh
# Builds DictionaryService + DictionaryPalette + portable engine and runs dictionary_test
# against a local mock HTTP server serving real StarDict .zip archives.
#
#   Sources/OpenKey/macOS/tests/run-dictionary-test.sh [snapshot-dir]
#
set -e
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
ENGINE=${HERE:h:h}/engine
WORK=$(mktemp -d)
SERVER_PID=""
cleanup() {
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

cd "$WORK"

# Build real StarDict ZIP fixtures + start local mock HTTP server
python3 - << 'EOF' "$WORK" &
import gzip, http.server, io, json, os, socketserver, struct, sys, threading, zipfile

work = sys.argv[1]
srv_dir = os.path.join(work, "srv")
os.makedirs(srv_dir, exist_ok=True)

def make_stardict_zip(out_zip, bookname, same_type_seq, entries, syns=()):
    idx = bytearray()
    dic = bytearray()
    for word, body in entries:
        b = body.encode("utf-8")
        off = len(dic)
        dic.extend(b)
        idx.extend(word.encode("utf-8") + b"\x00")
        idx.extend(struct.pack(">II", off, len(b)))
    dic_gz = gzip.compress(bytes(dic))
    ifo = (f"StarDict's dict ifo file\nversion=3.0.0\nbookname={bookname}\n"
           f"wordcount={len(entries)}\nidxfilesize={len(idx)}\n")
    if same_type_seq:
        ifo += f"sametypesequence={same_type_seq}\n"
    if syns:
        ifo += f"synwordcount={len(syns)}\n"
    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("dict/data.ifo", ifo)
        zf.writestr("dict/data.idx", bytes(idx))
        zf.writestr("dict/data.dict.dz", dic_gz)
        if syns:
            syn_b = bytearray()
            for sw, idx_pos in syns:
                syn_b.extend(sw.encode("utf-8") + b"\x00")
                syn_b.extend(struct.pack(">I", idx_pos))
            zf.writestr("dict/data.syn.dz", gzip.compress(bytes(syn_b)))

make_stardict_zip(
    os.path.join(srv_dir, "en-vi.zip"),
    "Anh - Việt (Mock)", "h",
    [
        ("apple", '<div class="hw">apple <span class="ipa">/ˈæp.əl/</span></div><span class="pos">danh từ</span><li>quả táo</li>'),
        ("hello", '<span class="pos">thán từ</span><li>xin chào</li><div class="ex">Hello world! <i>Xin chào thế giới!</i></div>'),
        ("stop", '<span class="pos">động từ</span><li>dừng lại</li>'),
    ],
    syns=[("stopped", 2), ("stopping", 2)]
)
make_stardict_zip(
    os.path.join(srv_dir, "vi-en.zip"),
    "Việt - Anh (Mock)", "m",
    [
        ("bàn", "@bàn\n* danh từ\n- table, desk"),
        ("mùa xuân", "@mùa xuân\n* danh từ\n- spring"),
        ("xin chào", "@xin chào\n* thán từ\n- hello, hi"),
    ]
)
make_stardict_zip(
    os.path.join(work, "local-wordnet.zip"),
    "WordNet (Local)", "",
    [
        ("hello", "m(n) an expression of greeting"),
    ]
)
make_stardict_zip(
    os.path.join(srv_dir, "ja-vi.zip"),
    "Nhật - Việt (Mock)", "m",
    [("こんにちは", "@こんにちは\n- xin chào")]
)

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=srv_dir, **kwargs)
    def do_GET(self):
        if self.path == "/fail-500.zip":
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"error")
            return
        super().do_GET()
    def log_message(self, *args): pass

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    port = httpd.server_address[1]
    base = f"http://127.0.0.1:{port}"
    # Intentionally put ja-vi before Anh-Viet in raw JSON to verify catalog sorting!
    cat = {
        "version": 1,
        "dictionaries": [
            {
                "id": "ja-vi-mock", "name": "Nhật - Việt (Mock)", "shortName": "Nhật-Việt", "badge": "JA→VI",
                "sourceLang": "ja", "targetLang": "vi", "priority": 60, "recommended": False,
                "headwordCount": 1, "downloadBytes": os.path.getsize(os.path.join(srv_dir, "ja-vi.zip")),
                "author": "Test", "license": "GPL", "description": "Mock JA-VI",
                "format": "stardict-zip", "files": [{"name": "ja-vi.zip", "url": base + "/ja-vi.zip", "sizeBytes": os.path.getsize(os.path.join(srv_dir, "ja-vi.zip"))}]
            },
            {
                "id": "vi-en-mock", "name": "Việt - Anh (Mock)", "shortName": "Việt-Anh", "badge": "VI→EN",
                "sourceLang": "vi", "targetLang": "en", "priority": 20, "recommended": True,
                "headwordCount": 3, "downloadBytes": os.path.getsize(os.path.join(srv_dir, "vi-en.zip")),
                "author": "Test", "license": "GPL", "description": "Mock VI-EN",
                "format": "stardict-zip", "files": [{"name": "vi-en.zip", "url": base + "/vi-en.zip", "sizeBytes": os.path.getsize(os.path.join(srv_dir, "vi-en.zip"))}]
            },
            {
                "id": "en-vi-mock", "name": "Anh - Việt (Mock)", "shortName": "Anh-Việt", "badge": "EN→VI",
                "sourceLang": "en", "targetLang": "vi", "priority": 10, "recommended": True,
                "headwordCount": 3, "downloadBytes": os.path.getsize(os.path.join(srv_dir, "en-vi.zip")),
                "author": "Test", "license": "CC BY-SA", "description": "Mock EN-VI",
                "format": "stardict-zip", "files": [{"name": "en-vi.zip", "url": base + "/en-vi.zip", "sizeBytes": os.path.getsize(os.path.join(srv_dir, "en-vi.zip"))}]
            },
            {
                "id": "broken-mock", "name": "Broken Test", "shortName": "Broken", "badge": "TEST",
                "sourceLang": "fr", "targetLang": "vi", "priority": 90, "recommended": False,
                "headwordCount": 0, "downloadBytes": 100,
                "author": "Test", "license": "GPL", "description": "HTTP 500 error check",
                "format": "stardict-zip", "files": [{"name": "fail.zip", "url": base + "/fail-500.zip", "sizeBytes": 100}]
            }
        ]
    }
    with open(os.path.join(work, "catalog.json"), "w", encoding="utf-8") as cf:
        json.dump(cat, cf)
    with open(os.path.join(work, "ready"), "w") as rf:
        rf.write(str(port))
    httpd.serve_forever()
EOF
SERVER_PID=$!

for i in {1..50}; do
    [ -f "$WORK/ready" ] && break
    sleep 0.1
done
[ -f "$WORK/ready" ] || { echo "mock server failed to start"; exit 1; }

for f in DictCatalog DictInflate DictStore MiniJson Suggest WordSpeech; do
    clang++ -std=c++17 -O2 -g -I"$ENGINE" -c "$ENGINE/$f.cpp" -o $f.o
done
clang++ -std=c++17 -fobjc-arc -g -I"$MAC" -I"$ENGINE" -c "$MAC/DictionaryService.mm" -o DictionaryService.o
clang++ -std=c++17 -fobjc-arc -g -I"$MAC" -I"$ENGINE" -c "$MAC/WordSpeaker.mm" -o WordSpeaker.o
clang++ -std=c++17 -fobjc-arc -g -I"$MAC" -I"$ENGINE" -c "$MAC/SnippetInserter.mm" -o SnippetInserter.o
clang++ -std=c++17 -g -Wno-deprecated-declarations -I"$ENGINE" -c "$ENGINE/SnippetSearch.cpp" -o SnippetSearch.o
for f in DictionaryPalette AISelection CaretLocator CaseTransform CaseBarPanel CaseBar SuggestionPanel VOKUI; do
    clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/dictionary_test.m" -o dictionary_test.o
clang++ -framework Cocoa -framework QuartzCore -framework Carbon -framework ApplicationServices -framework AVFoundation *.o -o dictionary_test

./dictionary_test "$WORK/catalog.json" "$WORK/local-wordnet.zip" "${1:-}"
