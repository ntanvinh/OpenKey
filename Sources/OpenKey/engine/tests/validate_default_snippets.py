#!/usr/bin/env python3
"""Checks snippets/default-snippets.json, the snippets every installation starts with.

    python3 -I tests/validate_default_snippets.py [path-to-json]

The same rules the apps rely on: valid UTF-8 JSON, a list of snippets with unique "builtin." ids, a title and a text
for each, and only the placeholders that the engine fills in (see SnippetSearch.h) between braces on their own.
"""
import json
import os
import re
import sys

KNOWN_PLACEHOLDERS = {"{clipboard}", "{date}", "{time}"}
MIN_SNIPPETS, MAX_SNIPPETS = 20, 30

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "snippets", "default-snippets.json")
    errors = []
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    if data.get("version") != 1:
        errors.append("version must be 1")
    snippets = data.get("snippets")
    if not isinstance(snippets, list):
        sys.exit("FAIL: no list of snippets")
    if not MIN_SNIPPETS <= len(snippets) <= MAX_SNIPPETS:
        errors.append("%d snippets, expected %d to %d" % (len(snippets), MIN_SNIPPETS, MAX_SNIPPETS))

    seen_ids, seen_titles = set(), set()
    for i, s in enumerate(snippets):
        where = "snippet %d (%s)" % (i, s.get("id", "?"))
        for key in ("id", "title", "keywords", "content"):
            if not isinstance(s.get(key), str):
                errors.append("%s: %s is missing or not text" % (where, key))
        if errors and not all(isinstance(s.get(k), str) for k in ("id", "title", "content")):
            continue
        if not s["id"].startswith("builtin.") or not re.fullmatch(r"builtin\.[a-z0-9-]+", s["id"]):
            errors.append("%s: id must look like builtin.some-name" % where)
        if s["id"] in seen_ids:
            errors.append("%s: id used twice" % where)
        seen_ids.add(s["id"])
        if s["title"].strip() != s["title"] or not s["title"]:
            errors.append("%s: title empty or with spaces around it" % where)
        if s["title"].lower() in seen_titles:
            errors.append("%s: title used twice" % where)
        seen_titles.add(s["title"].lower())
        if len(s["content"].strip()) < 40:
            errors.append("%s: content is too short to be a template" % where)
        if s["content"] != s["content"].strip("\n"):
            errors.append("%s: content starts or ends with empty lines" % where)
        if "\r" in s["content"]:
            errors.append("%s: content has carriage returns" % where)
        for found in re.findall(r"\{[a-z_]+\}", s["content"]):
            if found not in KNOWN_PLACEHOLDERS:
                errors.append("%s: unknown placeholder %s" % (where, found))
        if len(s["keywords"].split()) < 3:
            errors.append("%s: give at least 3 keywords" % where)
        if any(ord(c) > 0x7f for c in s["keywords"]):
            # keywords are folded without accents by the search, writing them without keeps the file easy to edit
            errors.append("%s: keywords are written without accents" % where)

    if errors:
        print("\n".join("FAIL: " + e for e in errors))
        sys.exit(1)
    print("ALL OK (%d snippets)" % len(snippets))

main()
