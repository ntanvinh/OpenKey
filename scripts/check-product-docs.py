#!/usr/bin/env python3
"""Check that the docs and product files agree that VOpenKey AI ships for macOS and Windows.

Usage: python3 scripts/check-product-docs.py [repo-root]

Standard library only. Prints one line per problem and exits 1 if there is any.
Runs in the product-docs job of .github/workflows/msbuild.yml (see CLAUDE.md).
"""
import json
import pathlib
import re
import sys

WINDOWS_URL = "https://github.com/ntanvinh/OpenKey/releases/latest/download/VOpenKey-Windows.zip"
UPSTREAM_WINDOWS = "tuyenvm/OpenKey/tree/master/Sources/OpenKey/win32"
WEBSITE_PRODUCT = "marketing/website/product.json"
DOCS_PRODUCT = "docs/vopenkey-ai/product.json"
META_MIN, META_MAX = 70, 155  # description is the meta description, see CLAUDE.md

if len(sys.argv) > 1:
    ROOT = pathlib.Path(sys.argv[1]).resolve()
else:
    ROOT = pathlib.Path(__file__).resolve().parent.parent

problems = []
checks = 0
descriptions = {}


def read(rel):
    path = ROOT / rel
    if not path.is_file():
        problems.append(f"{rel}: file is missing")
        return ""
    return path.read_text(encoding="utf-8")


def expect(rel, ok, message):
    global checks
    checks += 1
    if not ok:
        problems.append(f"{rel}: {message}")


def must_contain(rel, text, needle):
    expect(rel, needle in text, f"must contain {needle!r}")


def must_not_match(rel, text, pattern, message):
    expect(rel, re.search(pattern, text, re.IGNORECASE) is None, message)


# README and the positioning doc: Windows is this app's own release, not upstream's.
README = "README.md"
text = read(README)
must_contain(README, text, WINDOWS_URL)
must_contain(README, text, "Sources/OpenKey/win32/README.md")
expect(README, UPSTREAM_WINDOWS not in text,
       "links the Windows app to the upstream project; link to this app's VOpenKey-Windows.zip instead")

POSITIONING = "marketing/positioning.md"
text = read(POSITIONING)
must_contain(POSITIONING, text, "VOpenKey-<version>-Windows.zip")
must_not_match(POSITIONING, text, r"Windows[^\n]*unverified",
               "calls Windows unverified; state what is released instead")
must_not_match(POSITIONING, text, r"upstream OpenKey Windows",
               "calls the Windows app an upstream project")

# The Windows README must name the program files that the zip really contains.
WIN32_README = "Sources/OpenKey/win32/README.md"
must_contain(WIN32_README, read(WIN32_README), "OpenKey64.exe")

# The release workflow must attach the fixed-name zip that the links point to.
RELEASE_WORKFLOW = ".github/workflows/release-windows.yml"
must_contain(RELEASE_WORKFLOW, read(RELEASE_WORKFLOW), "VOpenKey-Windows.zip")

# Every product file lists both platforms, links to the same Windows zip,
# and, where it has descriptions, says Windows in both languages.
for rel in ["marketing/product.json", "marketing/website/product.json", "docs/vopenkey-ai/product.json"]:
    try:
        data = json.loads(read(rel) or "{}")
    except json.JSONDecodeError as error:
        problems.append(f"{rel}: not valid JSON ({error})")
        continue
    platforms = data.get("platforms", [])
    expect(rel, "macOS" in platforms and "Windows" in platforms,
           f"platforms is {platforms}; it must list both macOS and Windows")
    links = data.get("links", {})
    expect(rel, links.get("windows") == WINDOWS_URL,
           f"links.windows is {links.get('windows')!r}; it must be the VOpenKey-Windows.zip link")
    description = data.get("description")
    if isinstance(description, dict):
        for lang in ("en", "vi"):
            value = description.get(lang, "")
            expect(rel, "Windows" in value,
                   f"description.{lang} does not mention Windows")
            # The description is the page's meta description: search results cut it near 155.
            expect(rel, META_MIN <= len(value) <= META_MAX,
                   f"description.{lang} is {len(value)} characters; it must be {META_MIN}-{META_MAX}")
        if rel in (WEBSITE_PRODUCT, DOCS_PRODUCT):
            descriptions[rel] = description

# The website product entry and its docs copy are the same text; keep them identical.
if WEBSITE_PRODUCT in descriptions and DOCS_PRODUCT in descriptions:
    expect(DOCS_PRODUCT, descriptions[DOCS_PRODUCT] == descriptions[WEBSITE_PRODUCT],
           f"description differs from {WEBSITE_PRODUCT}; copy the same text into both files")

# Feature texts are copied by hand from marketing/features/<id>.json into the docs product file.
# A feature with a picture needs one entry there with the same text, and visitor text must not
# point at an internal file (the README, a changelog) that a visitor cannot open.
FEATURES_DIR = "marketing/features"
INTERNAL_REFERENCE = r"\bREADME\b|\.md\b|CHANGELOG"
try:
    docs_features = json.loads(read(DOCS_PRODUCT) or "{}").get("features", [])
except json.JSONDecodeError:
    docs_features = []  # already reported above
for path in sorted((ROOT / FEATURES_DIR).glob("*.json")):
    rel = f"{FEATURES_DIR}/{path.name}"
    feature = json.loads(path.read_text(encoding="utf-8"))
    if "image" not in feature:
        continue  # no picture, so the docs product file has no entry for it
    visitor_text = {
        "title.vi": feature["title"]["vi"],
        "title.en": feature["title"]["en-US"],
        "description.vi": feature["description"]["vi"],
        "description.en": feature["description"]["en-US"],
    }
    for label, value in visitor_text.items():
        must_not_match(rel, value, INTERNAL_REFERENCE,
                       f"{label} points at an internal file that visitors cannot open")
    copies = [item for item in docs_features
              if item.get("image", "").endswith(f"-{feature['id']}.png")]
    expect(rel, len(copies) == 1,
           f"{DOCS_PRODUCT} has {len(copies)} entries for {feature['id']}; it needs exactly one")
    for copy in copies:
        text = copy.get("text", {})
        description = copy.get("description", {})
        copied = {
            "title.vi": text.get("vi"),
            "title.en": text.get("en"),
            "description.vi": description.get("vi"),
            "description.en": description.get("en"),
        }
        for label, value in visitor_text.items():
            expect(DOCS_PRODUCT, copied[label] == value,
                   f"{label} of {feature['id']} differs from {rel}; copy the same text into both files")

if problems:
    for line in problems:
        print(line)
    print(f"product docs: {len(problems)} problem(s) found in {checks} checks")
    sys.exit(1)

print(f"product docs: all {checks} checks passed")
