#!/usr/bin/env python3
"""A stand-in for the `ollama` program, for ai_local_runtime_test.m and ai_local_setup_test.m. `fake_ollama.py serve` listens on
OLLAMA_HOST and answers like the real server once it is ready: /api/version, /api/tags, /api/pull (instantly "success"),
/api/delete, /api/ps (the models in memory), /api/generate with keep_alive 0 (takes one out), and a chat at /v1/chat/completions that says a few words (a model called silent:... says nothing, crash:... fails).
The models it has are kept in the file FAKE_OLLAMA_MODELS, so that they survive a restart. What it does besides is chosen by
FAKE_OLLAMA_MODE:
    normal      answers after FAKE_OLLAMA_DELAY seconds (default 0)
    die         prints a message and exits with 1 at once
    hang        listens never: runs for ever without answering
    ignore-term does not stop on SIGTERM (only SIGKILL stops it)
Each start is recorded as a line of JSON in FAKE_OLLAMA_LOG: the arguments, the address and the few variables that matter.
"""
import http.server
import json
import os
import signal
import sys
import time

mode = os.environ.get("FAKE_OLLAMA_MODE", "normal")
if len(sys.argv) < 2 or sys.argv[1] != "serve":
    print("fake ollama: only `serve` is supported", file=sys.stderr)
    sys.exit(2)

with open(os.environ["FAKE_OLLAMA_LOG"], "a") as log:
    log.write(json.dumps({"argv": sys.argv[1:], "host": os.environ.get("OLLAMA_HOST"), "keep_alive": os.environ.get("OLLAMA_KEEP_ALIVE"),
                          "cwd": os.getcwd(), "pid": os.getpid()}) + "\n")

if mode == "die":
    print("Error: listen tcp 127.0.0.1:11434: bind: address already in use", file=sys.stderr, flush=True)
    sys.exit(1)
if mode == "ignore-term":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
if mode == "hang":
    while True:
        time.sleep(1)

time.sleep(float(os.environ.get("FAKE_OLLAMA_DELAY", "0")))
host, _, port = os.environ["OLLAMA_HOST"].rpartition(":")


MODELS = os.environ.get("FAKE_OLLAMA_MODELS")
LOADED = []         # the models "in memory": a model is loaded when it answers a chat, and leaves when unloaded (keep_alive 0)
PULLS = {}          # tag -> how many times it was asked for: some models fail the first times (a connection that breaks)
EOF_ERROR = ('max retries exceeded: Get "https://dd20bb891979d25aebc8bec07b2b3bbc.r2.cloudflarestorage.com/ollama/blob/data?'
             'X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=SECRET123": EOF')


def models():
    try:
        return json.load(open(MODELS)) if MODELS else []
    except (OSError, ValueError):
        return []


def save(names):
    if MODELS:
        json.dump(names, open(MODELS, "w"))


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, status, obj):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            return json.loads(self.rfile.read(length).decode()) if length else {}
        except ValueError:
            return {}

    def do_GET(self):
        if self.path == "/api/version":
            return self.send_json(200, {"version": "0.0.0-fake"})
        if self.path == "/api/ps":
            return self.send_json(200, {"models": [{"name": n, "size": 2000000000, "size_vram": 2000000000} for n in LOADED]})
        if self.path == "/_pulls":
            return self.send_json(200, PULLS)
        if self.path == "/api/tags":
            return self.send_json(200, {"models": [{"name": n, "size": 1000} for n in models()]})
        self.send_json(404, {"error": "no such route"})

    def do_POST(self):
        body = self.body()
        if self.path == "/api/pull":
            tag = body.get("model", "")
            self.send_response(200)
            self.end_headers()
            PULLS[tag] = PULLS.get(tag, 0) + 1
            n = PULLS[tag]
            lines = [{"status": "pulling manifest"}]
            layer = lambda done: {"status": "pulling aaaa", "digest": "sha256:aaaa", "total": 500000000, "completed": done}
            if tag.startswith("flaky") and n <= 2:           # the connection breaks, with nothing downloaded; the third try works
                lines.append({"error": EOF_ERROR})
            elif tag.startswith("offline"):                  # always breaks
                lines.append({"error": EOF_ERROR})
            elif tag.startswith("halfway") and n == 1:       # breaks after 30 MB of 500: the second try continues
                lines += [layer(10000000), layer(30000000), {"error": EOF_ERROR}]
            elif tag.startswith("progressing") and n <= 12:  # breaks every time, but each time a bit further
                lines += [layer(6000000 * n), {"error": EOF_ERROR}]
            elif tag.startswith("missing"):
                lines.append({"error": "pull model manifest: file does not exist"})
            elif tag.startswith("slow"):                 # 30 reports, a fifth of a second apart: time to cancel it
                lines += [{"status": "pulling aaaa", "digest": "sha256:aaaa", "total": 3000, "completed": 100 * i} for i in range(1, 31)]
                lines.append({"status": "success"})
            else:
                lines += [{"status": "pulling aaaa", "digest": "sha256:aaaa", "total": 1000, "completed": 500},
                          {"status": "pulling aaaa", "digest": "sha256:aaaa", "total": 1000, "completed": 1000},
                          {"status": "success"}]
            try:
                for line in lines:
                    self.wfile.write((json.dumps(line) + "\n").encode())
                    self.wfile.flush()
                    if tag.startswith("slow"):
                        time.sleep(0.2)
            except (BrokenPipeError, ConnectionResetError):
                return                                   # cancelled: the model is not complete
            if lines[-1].get("status") == "success":
                names = models()
                if tag not in names:
                    save(names + [tag])
            return
        if self.path == "/api/generate":                 # with keep_alive 0 it takes a model out of memory
            model = body.get("model", "")
            if model in LOADED:
                LOADED.remove(model)
                return self.send_json(200, {"model": model, "done": True, "done_reason": "unload"})
            if model in models():
                return self.send_json(200, {"model": model, "done": True})
            return self.send_json(404, {"error": "model '%s' not found" % model})
        if self.path == "/v1/chat/completions":
            model = body.get("model", "")
            if model not in LOADED and not model.startswith("crash"):
                LOADED.append(model)
            if model.startswith("crash"):
                return self.send_json(500, {"error": {"message": "model runner has unexpectedly stopped"}})
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            pieces = [] if model.startswith("silent") else ["Xin", " chào", " bạn", ",", " mình", " khỏe", "."]
            for piece in pieces:
                self.wfile.write(("data: " + json.dumps({"choices": [{"delta": {"content": piece}}]}) + "\n\n").encode())
                self.wfile.flush()
                time.sleep(0.03)
            self.wfile.write(b"data: [DONE]\n\n")
            return
        self.send_json(404, {"error": "no such route"})

    def do_DELETE(self):
        body = self.body()
        names = models()
        if self.path == "/api/delete" and body.get("model") in names:
            names.remove(body["model"])
            save(names)
            return self.send_json(200, {})
        self.send_json(404, {"error": "model not found"})


print("fake ollama listening on", host, port, flush=True)
http.server.ThreadingHTTPServer((host, int(port)), Handler).serve_forever()
