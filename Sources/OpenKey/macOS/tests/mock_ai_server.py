#!/usr/bin/env python3
"""A small fake of the three kinds of AI server VOpenKey talks to, for ai_test.m. Listens on 127.0.0.1 on a free port, prints
the port on its first line, and records the last request it received at GET /_last.

The model name in the request chooses what happens, so one server is enough for every case:
    missing -> 404, limited -> 429, boom -> 500, redirect -> 302, empty -> an answer without text,
    midstream -> an error after two pieces, slow -> a piece every 150 ms for 3 seconds, plain -> one JSON, not a stream,
    thinktail -> OpenAI only: the whole answer is "<t", which is kept,
    thinkinline -> OpenAI only: reasoning written between <think> tags in the text, then the normal answer,
    blocked / thinking -> Gemini only, err -> Anthropic only. Anything else gives the normal answer.
The streams are written a few bytes at a time so that pieces arrive cut anywhere, even in the middle of a letter.
"""
import http.server
import json
import sys
import threading
import time
import urllib.parse

GOOD_KEY = "test-key-123"
PIECES = ["Xin", " chào", " các", " bạn", " ❤️ đẹp"]   # Vietnamese letters and an emoji: several bytes each
STATE = {"last": None, "stolen": 0, "slow_aborted": 0}


class Handler(http.server.BaseHTTPRequestHandler):
    # HTTP/1.0: the answer ends when the connection closes, so a stream needs no chunk framing
    def log_message(self, *args):
        pass

    # ---- helpers
    def body_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw.decode("utf-8")) if raw else {}
        except ValueError:
            return {}

    def send_json(self, status, obj, headers=None):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def start_stream(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

    def write_cut(self, text, delay=0.004):
        data = text.encode("utf-8")
        for i in range(0, len(data), 5):
            self.wfile.write(data[i:i + 5])
            self.wfile.flush()
            time.sleep(delay)

    def record(self, body):
        STATE["last"] = {"path": self.path, "method": self.command,
                         "headers": {k.lower(): v for k, v in self.headers.items()}, "body": body}

    # ---- routes
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/_last":
            return self.send_json(200, {"last": STATE["last"], "stolen": STATE["stolen"], "slow_aborted": STATE["slow_aborted"]})
        if path == "/stolen":
            STATE["stolen"] += 1
            return self.send_json(200, {"ok": True})
        self.record(None)
        if path == "/v1/models":
            auth = self.headers.get("Authorization")
            if self.headers.get("X-Expect-Key") and auth != "Bearer " + GOOD_KEY:
                return self.send_json(401, {"error": {"message": "Incorrect API key provided: " + (auth or "")[7:], "type": "invalid_request_error", "code": "invalid_api_key"}})
            return self.send_json(200, {"data": [{"id": "zeta-large"}, {"id": "alpha-1"}, {"id": "text-embedding-3-small"}, {"id": "gpt-4o-mini"}, {"id": "whisper-1"}, {"id": "alpha-10"}, {"id": "alpha-2"}]})
        if path == "/v1beta/models":
            if self.headers.get("x-goog-api-key") != GOOD_KEY:
                return self.send_json(403, {"error": {"code": 403, "message": "API key not valid", "status": "PERMISSION_DENIED"}})
            return self.send_json(200, {"models": [
                {"name": "models/gemini-pro-latest", "supportedGenerationMethods": ["generateContent", "countTokens"]},
                {"name": "models/text-embedding-004", "supportedGenerationMethods": ["embedContent"]},
                {"name": "models/gemini-flash-latest", "supportedGenerationMethods": ["generateContent"]}]})
        if path == "/anthropic/v1/models":
            if self.headers.get("x-api-key") != GOOD_KEY:
                return self.send_json(401, {"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}})
            return self.send_json(200, {"data": [{"id": "claude-b"}, {"id": "claude-a"}]})
        self.send_json(404, {"error": {"message": "no such route " + path}})

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        body = self.body_json()
        self.record(body)
        if "key=" in (parsed.query or "") or "key=" in parsed.path:
            return self.send_json(400, {"error": {"message": "the key is in the address"}})
        path = parsed.path
        if path == "/v1/chat/completions":
            return self.openai(body)
        if path.startswith("/v1beta/models/") and path.endswith(":streamGenerateContent"):
            return self.gemini(urllib.parse.unquote(path[len("/v1beta/models/"):-len(":streamGenerateContent")]), body)
        if path == "/anthropic/v1/messages":
            return self.anthropic(body)
        self.send_json(404, {"error": {"message": "no such route " + path}})

    def common_failure(self, model):
        if model == "missing":
            self.send_json(404, {"error": {"message": "The model `missing` does not exist", "type": "invalid_request_error", "code": "model_not_found"}})
        elif model == "limited":
            self.send_json(429, {"error": {"message": "You exceeded your current quota", "type": "insufficient_quota"}})
        elif model == "boom":
            data = b"<html>bad gateway</html>"
            self.send_response(500)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif model == "redirect":
            self.send_response(302)
            self.send_header("Location", "/stolen")
            self.send_header("Content-Length", "0")
            self.end_headers()
        else:
            return False
        return True

    # ---- OpenAI
    def openai(self, body):
        auth = self.headers.get("Authorization")
        model = body.get("model", "")
        if self.headers.get("X-Expect-Key") is not None or auth is not None:
            if auth != "Bearer " + GOOD_KEY:
                return self.send_json(401, {"error": {"message": "Incorrect API key provided: " + (auth or "")[7:] + ". You can find your API key at https://platform.openai.com.", "type": "invalid_request_error", "code": "invalid_api_key"}})
        if self.common_failure(model):
            return
        if model == "plain":
            return self.send_json(200, {"choices": [{"message": {"role": "assistant", "content": "Trả lời nguyên khối"}}]})
        self.start_stream()
        chunk = lambda delta, finish=None: "data: " + json.dumps({"choices": [{"delta": delta, "finish_reason": finish}]}, ensure_ascii=False) + "\n\n"
        try:
            if model == "empty":
                self.write_cut(chunk({"role": "assistant", "content": ""}) + "data: [DONE]\n\n")
            elif model == "midstream":
                self.write_cut(chunk({"content": "Một"}) + chunk({"content": " hai"}) + 'data: {"error":{"message":"The server is overloaded","type":"overloaded_error"}}\n\n')
            elif model == "thinkinline":
                # the reasoning is in the text, between <think> tags that arrive cut in the middle
                text = chunk({"content": "<thi"}) + chunk({"content": "nk>nghĩ thầm một lúc</th"}) + chunk({"content": "ink>\n\n"})
                for piece in PIECES:
                    text += chunk({"content": piece})
                self.write_cut(text + chunk({}, "stop") + "data: [DONE]\n\n")
            elif model == "thinktail":
                # the whole answer is what could have been the start of a tag: it is the answer, given when the stream ends
                self.write_cut(chunk({"content": "<t"}) + "data: [DONE]\n\n")
            elif model == "slow":
                for i in range(20):
                    self.write_cut(chunk({"content": "p%d " % i}))
                    time.sleep(0.15)
                self.write_cut("data: [DONE]\n\n")
            else:
                text = chunk({"role": "assistant", "content": ""}) + ": a comment line\r\n\r\n"
                text += chunk({"reasoning_content": "thinking out loud"}) + chunk({"content": None})
                for piece in PIECES:
                    text += chunk({"content": piece}).replace("\n\n", "\r\n\r\n")
                text += chunk({}, "stop") + "data: [DONE]\n\n"
                self.write_cut(text)
        except (BrokenPipeError, ConnectionResetError):
            STATE["slow_aborted"] += 1

    # ---- Gemini
    def gemini(self, model, body):
        if self.headers.get("x-goog-api-key") != GOOD_KEY:
            return self.send_json(403, {"error": {"code": 403, "message": "API key not valid. Please pass a valid API key: " + (self.headers.get("x-goog-api-key") or ""), "status": "PERMISSION_DENIED"}})
        if self.common_failure(model):
            return
        self.start_stream()
        event = lambda obj: "data: " + json.dumps(obj, ensure_ascii=False) + "\r\n\r\n"
        try:
            if model == "blocked":
                self.write_cut(event({"promptFeedback": {"blockReason": "SAFETY"}}))
            elif model == "thinking":
                self.write_cut(event({"candidates": [{"content": {"role": "model", "parts": [{"text": "suy nghĩ", "thought": True}]}}]}))
                self.write_cut(event({"candidates": [{"content": {"role": "model", "parts": [{"text": "Đáp án"}]}, "finishReason": "STOP"}]}))
            else:
                for i, piece in enumerate(PIECES):
                    obj = {"candidates": [{"content": {"role": "model", "parts": [{"text": piece}]}}]}
                    if i == len(PIECES) - 1:
                        obj["candidates"][0]["finishReason"] = "STOP"
                    self.write_cut(event(obj))
        except (BrokenPipeError, ConnectionResetError):
            pass

    # ---- Anthropic
    def anthropic(self, body):
        if self.headers.get("x-api-key") != GOOD_KEY or not self.headers.get("anthropic-version"):
            return self.send_json(401, {"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key: " + (self.headers.get("x-api-key") or "")}})
        model = body.get("model", "")
        if self.common_failure(model):
            return
        self.start_stream()
        ev = lambda name, obj: "event: %s\ndata: %s\n\n" % (name, json.dumps(obj, ensure_ascii=False))
        try:
            self.write_cut(ev("message_start", {"type": "message_start", "message": {"id": "m1", "content": []}}))
            if model == "err":
                self.write_cut(ev("error", {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}))
                return
            self.write_cut(ev("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}))
            self.write_cut(ev("ping", {"type": "ping"}))
            for piece in PIECES:
                self.write_cut(ev("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": piece}}))
            self.write_cut(ev("content_block_stop", {"type": "content_block_stop", "index": 0}))
            self.write_cut(ev("message_stop", {"type": "message_stop"}))
        except (BrokenPipeError, ConnectionResetError):
            pass


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True


if __name__ == "__main__":
    server = Server(("127.0.0.1", 0), Handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()
