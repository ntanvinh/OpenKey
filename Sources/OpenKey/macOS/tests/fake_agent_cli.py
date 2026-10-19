#!/usr/bin/env python3
# Stands in for the programs `codex`, `claude` and `agy` in the tests of the AI agents (ai_agent_test.m). Which one it is: the name it
# is started under (the tests make a link for each). What it does: the environment variable FAKE_AGENT_MODE.
#
# It writes what it was started with (name, arguments, folder, what came on its input, the PATH) as JSON to FAKE_AGENT_LOG, before
# doing anything else, so that a test can read it even when the program is stopped halfway.
#
# Nothing here talks to a network or to a real AI.
import hashlib
import json
import os
import subprocess
import sys
import time

name = os.path.basename(sys.argv[0])
args = sys.argv[1:]
mode = os.environ.get("FAKE_AGENT_MODE", "ok")
log_path = os.environ.get("FAKE_AGENT_LOG")
pids_path = os.environ.get("FAKE_AGENT_PIDS")


def out(text, flush=True):
    sys.stdout.write(text)
    if flush:
        sys.stdout.flush()


def out_bytes(data):
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


# --- what they print besides answers -------------------------------------------------------------------------------------------

CATALOG = {"models": [
    {"slug": "fake-frontier", "display_name": "Fake-Frontier", "description": "Frontier intelligence for the most demanding work.",
     "default_reasoning_level": "low", "visibility": "list", "priority": 2, "supported_in_api": True,
     "supported_reasoning_levels": [{"effort": "low", "description": "x"}, {"effort": "medium", "description": "x"},
                                    {"effort": "high", "description": "x"}, {"effort": "ultra", "description": "x"}]},
    {"slug": "fake-workhorse", "display_name": "Fake-Workhorse", "description": "Latest workhorse model for coding and everyday work.",
     "default_reasoning_level": "medium", "visibility": "list", "priority": 1, "supported_in_api": True,
     "supported_reasoning_levels": [{"effort": "low", "description": "x"}, {"effort": "medium", "description": "x"}, {"effort": "high", "description": "x"}]},
    {"slug": "fake-mini", "display_name": "Fake-Mini", "description": "Fast and affordable model for easier tasks.",
     "default_reasoning_level": "medium", "visibility": "list", "priority": 4, "supported_in_api": True,
     "supported_reasoning_levels": [{"effort": "minimal", "description": "x"}, {"effort": "low", "description": "x"}, {"effort": "medium", "description": "x"}]},
    {"slug": "fake-old-mini", "display_name": "Fake-Old-Mini", "description": "Older fast and efficient model.",
     "default_reasoning_level": "medium", "visibility": "list", "priority": 9, "supported_in_api": True,
     "supported_reasoning_levels": [{"effort": "low", "description": "x"}]},
    {"slug": "fake-hidden", "display_name": "Fake-Hidden", "description": "Automatic review.", "visibility": "hide", "priority": 43,
     "supported_reasoning_levels": [{"effort": "low", "description": "x"}]},
]}

if name == "codex" and args[:2] == ["debug", "models"]:
    out(json.dumps(CATALOG))
    sys.exit(0)

if name == "agy" and args[:1] == ["models"]:
    # what the real `agy models` prints: a status line on the standard error, then "identifier<TAB>name" on the standard output
    sys.stderr.write("Fetching available models...\n")
    if mode == "models-empty":
        sys.exit(0)
    out("gemini-4-argon-medium\tGemini 4 Argon (Medium)\n"
        "gemini-4-argon-high\tGemini 4 Argon (High)\n"
        "gemini-4-argon-low\tGemini 4 Argon (Low)\n"
        "gemini-3.8-flash-high\tGemini 3.8 Flash (High)\n"
        "gemini-3.8-flash-medium\tGemini 3.8 Flash (Medium)\n"
        "gemini-3.8-flash-low\tGemini 3.8 Flash (Low)\n"
        "claude-opus-5-5-low\tClaude Opus 5.5 (Low)\n"
        "claude-opus-5-5-medium\tClaude Opus 5.5 (Medium)\n"
        "claude-opus-5-5-high\tClaude Opus 5.5 (High)\n"
        "claude-sonnet-5-5-low\tClaude Sonnet 5.5 (Low)\n"
        "claude-sonnet-5-5-medium\tClaude Sonnet 5.5 (Medium)\n"
        "claude-sonnet-5-5-high\tClaude Sonnet 5.5 (High)\n"
        "gpt-oss-120b-medium\tGPT-OSS 120B (Medium)\n"
        "plain-model\tA Model Without Levels\n")
    sys.exit(0)

# --- a request -----------------------------------------------------------------------------------------------------------------

stdin_data = b""
if mode != "no-read":
    stdin_data = sys.stdin.buffer.read() if not sys.stdin.isatty() else b""

if log_path:
    try:
        listing = sorted(os.listdir(os.getcwd()))
    except OSError:
        listing = ["?"]
    with open(log_path, "w") as f:
        json.dump({
            "name": name, "args": args, "cwd": os.getcwd(), "cwd_listing": listing, "cwd_mode": oct(os.stat(os.getcwd()).st_mode & 0o777),
            "stdin_length": len(stdin_data), "stdin_sha256": hashlib.sha256(stdin_data).hexdigest(),
            "stdin_head": stdin_data[:4000].decode("utf-8", "replace"), "path": os.environ.get("PATH", ""),
            "no_color": os.environ.get("NO_COLOR"), "pid": os.getpid(),
        }, f)

if mode == "no-read":
    sys.exit(0)                                         # ended without reading its input: writing to it must not kill the parent

ANSWER = ["Xin chào, ", "đây là ", "câu trả lời."]


def answer_claude(pieces):
    out(json.dumps({"type": "system", "subtype": "init", "model": "fake"}) + "\n")
    out(json.dumps({"type": "stream_event", "event": {"type": "message_start"}}) + "\n")
    # what the model thinks is not part of the answer
    out(json.dumps({"type": "stream_event", "event": {"type": "content_block_delta", "index": 0,
                                                       "delta": {"type": "thinking_delta", "thinking": "hmm, let me think"}}}) + "\n")
    for piece in pieces:
        out(json.dumps({"type": "stream_event", "event": {"type": "content_block_delta", "index": 1,
                                                           "delta": {"type": "text_delta", "text": piece}}}) + "\n")
        time.sleep(0.05)
    out(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "".join(pieces)}]}}) + "\n")
    out(json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": "".join(pieces)}) + "\n")


def claude_error(text):
    out(json.dumps({"type": "result", "subtype": "success", "is_error": True, "result": text}) + "\n")
    sys.exit(1)


if mode in ("ok", "delayed"):
    if mode == "delayed":                               # the first word takes a few seconds, as it does for a program that thinks
        time.sleep(3.3)
    if name == "claude":
        answer_claude(ANSWER)
    elif name == "codex":
        out("".join(ANSWER))
    else:
        out(ANSWER[0])
        time.sleep(0.05)
        out(ANSWER[1] + ANSWER[2])
    sys.exit(0)

if mode == "claude-no-deltas":                          # the answer is only in the messages that complete it
    out(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "Cả khối."}]}}) + "\n")
    out(json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": "Cả khối."}) + "\n")
    sys.exit(0)

if mode == "claude-result-only":
    out(json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": "Chỉ có kết quả."}) + "\n")
    sys.exit(0)

if mode == "login":
    if name == "claude":
        claude_error("Not logged in · Please run /login")
    sys.stderr.write("OpenAI Codex v0.0\n--------\nworkdir: /x\nmodel: y\n--------\nuser\nthe prompt that must not be mistaken for the error\n"
                     "ERROR: Not logged in. Run `codex login` first.\n")
    sys.exit(1)

if mode == "ratelimit":
    if name == "claude":
        claude_error("Claude usage limit reached. Your limit will reset at 5pm.")
    sys.stderr.write("ERROR: You've hit your usage limit. Try again later (429).\n")
    sys.exit(1)

if mode == "badmodel":
    if name == "claude":
        claude_error("There's an issue with the selected model (nope). It may not exist or you may not have access to it.")
    sys.stderr.write("ERROR: The model `nope` does not exist or you do not have access to it.\n")
    sys.exit(1)

if mode == "badeffort":
    sys.stderr.write("error: invalid value for reasoning effort 'ultra': unsupported for this model\n")
    sys.exit(2)

if mode == "secret":                                    # an error that carries something that looks like a key
    sys.stderr.write("ERROR: request failed with key sk-abcdefghijklmnop123456 and Bearer abcdefgh12345678\n")
    sys.exit(1)

if mode == "empty":
    sys.exit(0)

if mode == "crash":
    sys.exit(3)

if mode == "ansi":
    out("\x1b[1mXin\x1b[0m chào \x1b[32mbạn\x1b[0m\n")
    sys.exit(0)

if mode == "split-utf8":                                # a letter of UTF-8 cut between two writes
    data = "Tiếng Việt: ế".encode("utf-8")
    cut = data.index("ế".encode("utf-8")) + 1
    out_bytes(data[:cut])
    time.sleep(0.2)
    out_bytes(data[cut:])
    sys.exit(0)

if mode == "slow":                                      # still running when it is stopped; leaves a child behind
    child = subprocess.Popen(["/bin/sleep", "120"])
    if pids_path:
        with open(pids_path, "w") as f:
            f.write("%d %d\n" % (os.getpid(), child.pid))
    out("đang nghĩ…")
    time.sleep(120)
    sys.exit(0)

if mode == "lingering":                                 # ends, but a child it started keeps its output open
    child = subprocess.Popen(["/bin/sleep", "20"], stdout=sys.stdout, stderr=sys.stderr)
    if pids_path:
        with open(pids_path, "w") as f:
            f.write("%d %d\n" % (os.getpid(), child.pid))
    out("xong rồi")
    sys.exit(0)

if mode == "flood":                                     # more text than any answer
    chunk = ("x" * 65536)
    for _ in range(80):
        try:
            out(chunk)
        except BrokenPipeError:
            break
    time.sleep(60)
    sys.exit(0)

if mode == "echo-length":                               # answers with what it got on its input
    text = "got %d bytes" % len(stdin_data)
    if name == "claude":
        answer_claude([text])
    else:
        out(text)
    sys.exit(0)

sys.stderr.write("unknown mode %s\n" % mode)
sys.exit(9)
