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

if len(sys.argv) > 1:
    ROOT = pathlib.Path(sys.argv[1]).resolve()
else:
    ROOT = pathlib.Path(__file__).resolve().parent.parent

problems = []
checks = 0


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
            expect(rel, "Windows" in description.get(lang, ""),
                   f"description.{lang} does not mention Windows")

if problems:
    for line in problems:
        print(line)
    print(f"product docs: {len(problems)} problem(s) found in {checks} checks")
    sys.exit(1)

print(f"product docs: all {checks} checks passed")
