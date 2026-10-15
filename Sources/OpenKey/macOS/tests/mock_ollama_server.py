#!/usr/bin/env python3
"""A fake of everything the setup of a local AI talks to, for ai_ollama_test.m and ai_local_install_test.m: the API of Ollama
(version, tags, pull, delete), the public library of Ollama (manifests, for the size of a download), and the releases of Ollama on
GitHub (what the latest one is, and the file itself). Listens on 127.0.0.1 on a free port, prints the port on its first line.

    mock_ollama_server.py [--zip path-to-an-Ollama-darwin.zip]

The zip it serves as the release can be changed at any time with {"zip_path": "..."} in POST /_control.

The test changes what the server does through POST /_control (a JSON object merged into STATE) and reads what happened at GET
/_state. The tag in a pull request chooses what happens:
    missing:1b -> an error line in the stream, boom:1b -> HTTP 500, slow:1b -> progress for 6 seconds (to cancel),
    garbled:1b -> a line that is not JSON between good lines, cut:1b -> the stream ends without "success", huge:1b -> a line that never ends,
    full:1b -> "no space left on device" in the stream, eof:1b -> a broken connection (EOF) with a signed address in the message. Anything else downloads normally and is added to the models.
"""
import hashlib
import http.server
import json
import os
import sys
import threading
import time
import urllib.parse

STATE = {
    "models": [],               # names of the models "installed"
    "pulls": [],                # tags pulled
    "deleted": [],
    "version_failures": 0,      # the next N answers of /api/version are cut (Ollama busy starting)
    "version_calls": 0,
    "aborted": 0,               # streams the client closed before the end
    "zip_mode": "good",         # good | corrupt | short | slow | redirect-http | redirect-local | status500 | claims-huge
    "digest_mode": "good",      # good | wrong | missing | malformed
    "size_mode": "good",        # good | wrong
    "zip_downloads": 0,
    "release_requests": 0,
    "manifest_requests": [],
}
LIBRARY = {                     # tag -> sizes of layers, the way the real manifests look
    "gemma3:1b": [800000000, 6000, 1000, 400],
    "tiny:1b": [1000000, 500, 100],
    "slow:1b": [3000, 100],
    "silent:1b": [1000, 100],
}
ZIP = {"path": None, "bytes": None}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def body_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw.decode("utf-8")) if raw else {}
        except ValueError:
            return {}

    def send_json(self, status, obj):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def base(self):
        return "http://127.0.0.1:%d" % self.server.server_address[1]

    # ---- GET
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/_state":
            return self.send_json(200, STATE)
        if path == "/api/version":
            STATE["version_calls"] += 1
            if STATE["version_failures"] > 0:
                STATE["version_failures"] -= 1
                self.connection.close()
                return
            if STATE.get("version_html"):
                data = b"<html>not ollama</html>"
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            return self.send_json(200, {"version": "0.0.0-mock"})
        if path == "/api/tags":
            return self.send_json(200, {"models": [{"name": n, "size": 1234} for n in STATE["models"]]})
        if path.startswith("/v2/") and "/manifests/" in path:
            redirect = STATE.get("manifest_redirect")
            if redirect and "r=1" not in self.path:
                self.send_response(302)
                self.send_header("Location", "http://evil.example.invalid/manifest" if redirect == "external" else self.path + "?r=1")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            STATE["manifest_requests"].append(path)
            _, _, rest = path.partition("/v2/")
            repo, _, version = rest.partition("/manifests/")
            name = repo[len("library/"):] if repo.startswith("library/") else repo
            sizes = LIBRARY.get("%s:%s" % (name, version))
            if sizes is None:
                return self.send_json(404, {"errors": [{"code": "MANIFEST_UNKNOWN", "message": "manifest unknown"}]})
            return self.send_json(200, {"schemaVersion": 2, "config": {"size": sizes[-1]},
                                        "layers": [{"size": s, "digest": "sha256:" + "0" * 64} for s in sizes[:-1]]})
        if path == "/repos/ollama/ollama/releases/latest":
            return self.release()
        if path == "/files/Ollama-darwin.zip":
            return self.zip_file()
        if path == "/files/elsewhere":
            return self.send_json(200, {"reached": "elsewhere"})
        self.send_json(404, {"error": "no such route " + path})

    def release(self):
        STATE["release_requests"] += 1
        data = ZIP["bytes"] or b""
        digest = hashlib.sha256(data).hexdigest()
        asset = {"name": "Ollama-darwin.zip", "size": len(data), "digest": "sha256:" + digest,
                 "browser_download_url": self.base() + "/files/Ollama-darwin.zip"}
        if STATE["size_mode"] == "wrong":
            asset["size"] = len(data) + 1
        if STATE["digest_mode"] == "wrong":
            asset["digest"] = "sha256:" + "0" * 64
        elif STATE["digest_mode"] == "missing":
            del asset["digest"]
        elif STATE["digest_mode"] == "malformed":
            asset["digest"] = "sha256:xyz"
        assets = [{"name": "ollama-linux-amd64.tgz", "size": 5, "digest": "sha256:" + "1" * 64, "browser_download_url": self.base() + "/files/other"}, asset]
        if STATE.get("no_asset"):
            assets = assets[:1]
        if STATE.get("evil_url"):
            asset["browser_download_url"] = "http://evil.example.invalid/Ollama-darwin.zip"
        self.send_json(200, {"tag_name": "v0.0.0-mock", "assets": assets})

    def zip_file(self):
        STATE["zip_downloads"] += 1
        mode = STATE["zip_mode"]
        data = ZIP["bytes"] or b""
        if mode == "redirect-http":
            self.send_response(302)
            self.send_header("Location", "http://evil.example.invalid/Ollama-darwin.zip")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if mode == "redirect-local" and "again=1" not in self.path:
            self.send_response(302)
            self.send_header("Location", "/files/Ollama-darwin.zip?again=1")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if mode == "status500":
            return self.send_json(500, {"error": "boom"})
        if mode == "claims-huge":                       # says it is 3 GB, sends a little, and waits
            self.send_response(200)
            self.send_header("Content-Length", "3000000000")
            self.end_headers()
            try:
                self.wfile.write(b"PK" * 1000000)
                self.wfile.flush()
                time.sleep(5)
            except (BrokenPipeError, ConnectionResetError):
                STATE["aborted"] += 1
            return
        if mode == "corrupt":
            data = data[:len(data) // 2] + bytes(b ^ 0xFF for b in data[len(data) // 2:len(data) // 2 + 16]) + data[len(data) // 2 + 16:]
        length = len(data)
        if mode == "short":
            data = data[:len(data) // 2]
        self.send_response(200)
        self.send_header("Content-Type", "application/zip")
        self.send_header("Content-Length", str(length if mode != "short" else len(data)))
        self.end_headers()
        try:
            step = 1 << 20 if mode != "slow" else 1 << 16
            for i in range(0, len(data), step):
                self.wfile.write(data[i:i + step])
                if mode == "slow":
                    time.sleep(0.05)
        except (BrokenPipeError, ConnectionResetError):
            STATE["aborted"] += 1

    # ---- POST / DELETE
    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        body = self.body_json()
        if path == "/_control":
            if "zip_path" in body:                      # serve another file as the release
                with open(body.pop("zip_path"), "rb") as f:
                    ZIP["bytes"] = f.read()
            STATE.update(body)
            return self.send_json(200, STATE)
        if path == "/api/pull":
            return self.pull(body)
        self.send_json(404, {"error": "no such route " + path})

    def do_DELETE(self):
        path = urllib.parse.urlparse(self.path).path
        body = self.body_json()
        if path == "/api/delete":
            tag = body.get("model", "")
            if tag in STATE["models"]:
                STATE["models"].remove(tag)
                STATE["deleted"].append(tag)
                return self.send_json(200, {})
            return self.send_json(404, {"error": "model '%s' not found" % tag})
        self.send_json(404, {"error": "no such route " + path})

    def line(self, obj, cut=True):
        data = (json.dumps(obj) + "\n").encode("utf-8") if not isinstance(obj, bytes) else obj
        step = 7 if cut else len(data)                       # lines arrive cut anywhere
        for i in range(0, len(data), step):
            self.wfile.write(data[i:i + step])
            self.wfile.flush()
            time.sleep(0.001)

    def pull(self, body):
        tag = body.get("model") or body.get("name") or ""
        STATE["pulls"].append(tag)
        if tag == "boom:1b":
            return self.send_json(500, {"error": "the server exploded"})
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.end_headers()
        try:
            self.line({"status": "pulling manifest"})
            if tag == "missing:1b":
                return self.line({"error": "pull model manifest: file does not exist"})
            if tag == "eof:1b":
                return self.line({"error": 'max retries exceeded: Get "https://dd20bb891979d25aebc8bec07b2b3bbc.r2.cloudflarestorage.com/ollama/blob/data?'
                                           'X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=SECRET123": EOF'})
            if tag == "full:1b":
                self.line({"status": "pulling aaaaaaaaaaaa", "digest": "sha256:aaaaaaaaaaaa", "total": 1000, "completed": 10})
                return self.line({"error": "write /Users/x/.ollama/models/blobs/sha256-aaa-partial: no space left on device"})
            if tag == "huge:1b":
                for _ in range(40):
                    self.wfile.write(b"x" * 65536)
                    self.wfile.flush()
                return
            layers = [("aaaaaaaaaaaa", 1000000), ("bbbbbbbbbbbb", 8431), ("cccccccccccc", 61), ("dddddddddddd", 490)]
            steps = 40 if tag == "slow:1b" else 10
            for digest, total in layers:
                self.line({"status": "pulling " + digest, "digest": "sha256:" + digest, "total": total})
                for i in range(1, steps + 1):
                    if tag == "slow:1b":
                        time.sleep(0.15)
                    self.line({"status": "pulling " + digest, "digest": "sha256:" + digest, "total": total, "completed": total * i // steps})
                    if tag == "garbled:1b" and i == 3:
                        self.line(b"this is not json\n")
                if tag == "slow:1b":
                    break
            if tag == "cut:1b":
                return
            if tag == "garbled:1b":
                pass
            self.line({"status": "verifying sha256 digest"})
            self.line({"status": "writing manifest"})
            self.line({"status": "success"})
            if tag not in STATE["models"]:
                STATE["models"].append(tag)
        except (BrokenPipeError, ConnectionResetError):
            STATE["aborted"] += 1


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 64


if __name__ == "__main__":
    if "--zip" in sys.argv:
        ZIP["path"] = sys.argv[sys.argv.index("--zip") + 1]
        with open(ZIP["path"], "rb") as f:
            ZIP["bytes"] = f.read()
    server = Server(("127.0.0.1", 0), Handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()
