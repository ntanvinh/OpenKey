#!/usr/bin/env python3
"""Rebuilds Sources/OpenKey/engine/ai/local-models.json, the list of models offered when a user installs an AI that runs on
their Mac (Settings > AI > "Cai AI chay tren may").

    python3 -I scripts/update-local-models.py            # write the file
    python3 -I scripts/update-local-models.py --check    # only check that every tag still exists and sizes still match

What is curated by hand is in MODELS below (names, notes, the opinions about quality). What is looked up is the size of the
download: the public registry of Ollama (registry.ollama.ai) gives the manifest of every tag, and the sizes of its layers add up
to what `ollama pull` downloads. A tag that the registry does not know makes the script fail, so a model that was renamed or
removed cannot stay in the list unnoticed.

Run it again when models change, and commit the result. The app never reads the registry for this list: it ships with it.

Why these models: a text assistant wants a model that answers directly, not one that first "thinks" for a long time, and that
writes Vietnamese. Gemma 3 (Google, 140+ languages) and Qwen 2.5 (Alibaba, 29+ languages with Vietnamese) are the two families
that fit, in sizes from 1B to 32B. Models that reason first (Qwen 3, Gemma 4, DeepSeek R1...) work too, VOpenKey drops what they
think, but they take much longer to start answering; the user can still type any name by hand.
"""
import json
import os
import sys
import urllib.error
import urllib.request

REGISTRY = "https://registry.ollama.ai/v2/%s/manifests/%s"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Sources", "OpenKey", "engine", "ai", "local-models.json")

# quality and speed are 1..5, compared with each other. vietnamese: the opinion on the Vietnamese they write. The summaries say
# nothing about the RAM needed: the app works that out from the size (AIModelAdvisor), one source for it.
MODELS = [
    {"tag": "gemma3:1b", "name": "Gemma 3 1B", "family": "Gemma 3 (Google)", "parameters": "1B", "quality": 1, "speed": 5,
     "vietnamese": "Cơ bản",
     "summary": "Nhỏ nhất dùng được. Viết ngắn và sửa lỗi đơn giản được, nhưng hay sai ý và tiếng Việt còn gượng. Hợp để thử hoặc máy rất yếu."},
    {"tag": "qwen2.5:3b", "name": "Qwen 2.5 3B", "family": "Qwen 2.5 (Alibaba)", "parameters": "3B", "quality": 2, "speed": 5,
     "vietnamese": "Cơ bản",
     "summary": "Nhẹ và nhanh, dịch và viết lại câu ngắn ổn. Chạy được trên Mac 8 GB mà vẫn để chỗ cho ứng dụng khác."},
    {"tag": "gemma3:4b", "name": "Gemma 3 4B", "family": "Gemma 3 (Google)", "parameters": "4B", "quality": 3, "speed": 4,
     "vietnamese": "Khá",
     "summary": "Cân bằng tốt cho máy ít RAM: viết, dịch, tóm tắt khá ổn, tiếng Việt tự nhiên hơn các model cùng cỡ."},
    {"tag": "qwen2.5:7b", "name": "Qwen 2.5 7B", "family": "Qwen 2.5 (Alibaba)", "parameters": "7B", "quality": 3, "speed": 4,
     "vietnamese": "Khá",
     "summary": "Lựa chọn quen thuộc cho Mac 16 GB: làm theo yêu cầu tốt, viết gọn, dịch Việt - Anh ổn."},
    {"tag": "gemma3:12b", "name": "Gemma 3 12B", "family": "Gemma 3 (Google)", "parameters": "12B", "quality": 4, "speed": 3,
     "vietnamese": "Tốt",
     "summary": "Viết văn bản dài và tiếng Việt tốt rõ rệt so với 4B."},
    {"tag": "qwen2.5:14b", "name": "Qwen 2.5 14B", "family": "Qwen 2.5 (Alibaba)", "parameters": "14B", "quality": 4, "speed": 3,
     "vietnamese": "Tốt",
     "summary": "Làm theo chỉ dẫn chính xác, hợp việc biên tập, tóm tắt và viết nội dung công việc."},
    {"tag": "gemma3:27b", "name": "Gemma 3 27B", "family": "Gemma 3 (Google)", "parameters": "27B", "quality": 5, "speed": 2,
     "vietnamese": "Rất tốt",
     "summary": "Chất lượng gần với các dịch vụ trả phí cho việc viết và dịch. Nặng, trả lời chậm hơn các model nhỏ."},
    {"tag": "qwen2.5:32b", "name": "Qwen 2.5 32B", "family": "Qwen 2.5 (Alibaba)", "parameters": "32B", "quality": 5, "speed": 2,
     "vietnamese": "Rất tốt",
     "summary": "Mạnh nhất trong danh sách cho văn bản dài và yêu cầu phức tạp. Rất nặng, trả lời chậm hơn các model nhỏ."},
]


def manifest_bytes(tag):
    name, _, version = tag.partition(":")
    request = urllib.request.Request(REGISTRY % ("library/" + name, version),
                                     headers={"Accept": "application/vnd.docker.distribution.manifest.v2+json"})
    with urllib.request.urlopen(request, timeout=40) as response:
        manifest = json.load(response)
    return sum(layer["size"] for layer in manifest["layers"]) + manifest.get("config", {}).get("size", 0)


def main():
    check = "--check" in sys.argv
    result = []
    failed = False
    for model in MODELS:
        try:
            size = manifest_bytes(model["tag"])
        except urllib.error.HTTPError as error:
            print("FAIL: %s is not in the registry (HTTP %d): renamed or removed?" % (model["tag"], error.code))
            failed = True
            continue
        entry = dict(model)
        entry["bytes"] = size
        result.append(entry)
        print("%-14s %6.2f GB" % (model["tag"], size / 1e9))
    if failed:
        return 1
    document = {"version": 1, "models": result}
    text = json.dumps(document, ensure_ascii=False, indent=2) + "\n"
    if check:
        current = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if current != text:
            print("the file is out of date: run this script without --check")
            return 1
        print("up to date")
        return 0
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write(text)
    print("written", os.path.normpath(OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
