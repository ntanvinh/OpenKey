#!/usr/bin/env python3
"""Checks dictionaries/catalog.json, the open-source dictionary catalog offered in-app.

    python3 -I tests/validate_dict_catalog.py [path-to-json]
"""
import json
import os
import re
import sys

ID_RE = re.compile(r"^[a-z0-9][a-z0-9\-]{1,48}$")
VALID_FORMATS = {"stardict-zip", "stardict-files", "fvdp-txt"}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "dictionaries", "catalog.json")
    errors = []
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    if data.get("version") != 1:
        errors.append("version must be 1")
    dicts = data.get("dictionaries")
    if not isinstance(dicts, list) or len(dicts) < 3:
        errors.append("dictionaries must be a list of at least 3 entries")
        dicts = dicts if isinstance(dicts, list) else []

    seen = set()
    prev_priority = -1
    for i, entry in enumerate(dicts):
        label = "dict %d" % i
        if not isinstance(entry, dict):
            errors.append(label + ": not an object")
            continue
        did = entry.get("id")
        if not isinstance(did, str) or not ID_RE.match(did):
            errors.append("%s: invalid id %r" % (label, did))
            continue
        label = did
        if did in seen:
            errors.append(label + ": duplicate id")
        seen.add(did)

        for key in ("name", "shortName", "badge", "sourceLang", "targetLang", "author", "license", "description", "format"):
            if not isinstance(entry.get(key), str) or not entry[key].strip():
                errors.append("%s: %s is missing" % (label, key))
        if entry.get("format") not in VALID_FORMATS:
            errors.append("%s: invalid format %r" % (label, entry.get("format")))

        prio = entry.get("priority")
        if not isinstance(prio, int) or isinstance(prio, bool) or prio < 1:
            errors.append("%s: priority must be positive int" % label)
        elif prio < prev_priority:
            errors.append("%s: priorities must be sorted ascending (%d < %d)" % (label, prio, prev_priority))
        else:
            prev_priority = prio

        dl = entry.get("downloadBytes")
        if not isinstance(dl, int) or isinstance(dl, bool) or dl <= 0:
            errors.append("%s: downloadBytes must be > 0" % label)

        hw = entry.get("headwordCount")
        if not isinstance(hw, int) or isinstance(hw, bool) or hw < 0:
            errors.append("%s: headwordCount must be >= 0" % label)

        files = entry.get("files")
        if not isinstance(files, list) or len(files) == 0:
            errors.append("%s: files must be non-empty" % label)
        else:
            total = 0
            for fobj in files:
                if not isinstance(fobj, dict):
                    errors.append("%s: file entry not object" % label)
                    continue
                url = fobj.get("url", "")
                if not isinstance(url, str) or not url.startswith("https://"):
                    errors.append("%s: file url must use https://: %r" % (label, url))
                if not isinstance(fobj.get("name"), str) or not fobj["name"].strip():
                    errors.append("%s: file name missing" % label)
                sb = fobj.get("sizeBytes")
                if not isinstance(sb, int) or isinstance(sb, bool) or sb <= 0:
                    errors.append("%s: file sizeBytes must be > 0" % label)
                else:
                    total += sb
            if isinstance(dl, int) and total != dl:
                errors.append("%s: downloadBytes (%d) != sum(file.sizeBytes) (%d)" % (label, dl, total))

    # Anh-Viet and Viet-Anh must lead the catalog (first entries)
    if len(dicts) >= 3:
        top_pairs = [(d.get("sourceLang"), d.get("targetLang")) for d in dicts[:3]]
        expected_pairs = [("en", "vi"), ("vi", "en"), ("en", "vi")]
        if top_pairs != expected_pairs:
            errors.append("top 3 dictionaries must be Anh-Viet / Viet-Anh, got %r" % (top_pairs,))

    if errors:
        for err in errors:
            print("FAIL:", err)
        return 1
    print("catalog.json: %d dictionaries, all fine" % len(dicts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
