#!/usr/bin/env python3
"""Checks ai/local-models.json, the models offered for an AI that runs on the Mac.

    python3 -I tests/validate_local_models.py [path-to-json]

The same rules the app relies on (AILocalModels): valid UTF-8 JSON, unique tags that Ollama can accept, a size for each, notes
in Vietnamese, ratings from 1 to 5. The file is made by scripts/update-local-models.py; this check does not need the network.
"""
import json
import os
import re
import sys

TAG = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._\-]*(/[A-Za-z0-9][A-Za-z0-9._\-]*){0,2}(:[A-Za-z0-9][A-Za-z0-9._\-]*)?$")
VIETNAMESE_RATINGS = {"Cơ bản", "Khá", "Tốt", "Rất tốt"}
MIN_MODELS, MAX_MODELS = 5, 15


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "ai", "local-models.json")
    errors = []
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    if data.get("version") != 1:
        errors.append("version must be 1")
    models = data.get("models")
    if not isinstance(models, list) or not (MIN_MODELS <= len(models) <= MAX_MODELS):
        errors.append("models must be a list of %d to %d entries" % (MIN_MODELS, MAX_MODELS))
        models = models if isinstance(models, list) else []

    seen = set()
    for index, model in enumerate(models):
        label = "model %d" % index
        if not isinstance(model, dict):
            errors.append(label + ": not an object")
            continue
        tag = model.get("tag")
        if not isinstance(tag, str) or not TAG.match(tag) or ".." in tag:
            errors.append("%s: bad tag %r" % (label, tag))
            continue
        label = tag
        if tag in seen:
            errors.append(label + ": duplicate tag")
        seen.add(tag)
        for key in ("name", "family", "parameters", "summary", "vietnamese"):
            if not isinstance(model.get(key), str) or not model[key].strip():
                errors.append("%s: %s is missing" % (label, key))
        if model.get("vietnamese") not in VIETNAMESE_RATINGS:
            errors.append("%s: vietnamese must be one of %s" % (label, sorted(VIETNAMESE_RATINGS)))
        for key in ("quality", "speed"):
            value = model.get(key)
            if not isinstance(value, int) or isinstance(value, bool) or not 1 <= value <= 5:
                errors.append("%s: %s must be an integer from 1 to 5" % (label, key))
        size = model.get("bytes")
        if not isinstance(size, int) or isinstance(size, bool) or not 100_000_000 <= size <= 200_000_000_000:
            errors.append("%s: bytes must be a plausible size of a download" % label)
        # the RAM a model needs is worked out by the app from its size: one source, not repeated in the notes
        if re.search(r"\d\s*GB\s*RAM", model.get("summary", "")):
            errors.append("%s: the summary must not state a RAM size (the app computes it)" % label)

    # a bigger model is not worse than a smaller one of the same family: catches a swapped rating
    families = {}
    for model in models:
        if isinstance(model, dict) and isinstance(model.get("bytes"), int) and isinstance(model.get("quality"), int):
            families.setdefault(model.get("family"), []).append(model)
    for family, members in families.items():
        members.sort(key=lambda m: m["bytes"])
        for smaller, larger in zip(members, members[1:]):
            if larger["quality"] < smaller["quality"]:
                errors.append("%s: %s is rated lower than the smaller %s" % (family, larger["tag"], smaller["tag"]))

    if errors:
        for error in errors:
            print("FAIL:", error)
        return 1
    print("local-models.json: %d models, all fine" % len(models))
    return 0


if __name__ == "__main__":
    sys.exit(main())
