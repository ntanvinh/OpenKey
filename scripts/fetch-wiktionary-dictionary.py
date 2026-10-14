#!/usr/bin/env python3
"""Build a suggestion dictionary for VOpenKey from the Vietnamese Wiktionary.

    scripts/fetch-wiktionary-dictionary.py -o Sources/OpenKey/engine/dictionaries/vi-wiktionary.txt

Asks the MediaWiki API of vi.wiktionary.org for the titles of the category "Mục từ tiếng Việt"
(entries for Vietnamese words) and writes them in the dictionary format of engine/Suggest.h:
single syllables as words, entries of several syllables as compound words.

Only the titles are used, no definitions. The text of Wiktionary is available under
Creative Commons Attribution-ShareAlike 4.0 (https://creativecommons.org/licenses/by-sa/4.0/),
the output file says where it comes from and under which licence, keep that header.
Wiktionary has no word frequencies, every entry gets the same small count: the dictionaries
with real counts (and what the user types) decide the order.
"""
import argparse
import datetime
import json
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request

API = "https://vi.wiktionary.org/w/api.php"
USER_AGENT = "VOpenKey-dictionary-builder/1.0 (https://github.com/ntanvinh/OpenKey)"
CATEGORY = "Thể loại:Mục từ tiếng Việt"

# a Vietnamese syllable: optional initial consonant, one to three vowels, optional final consonant.
# Keeps out numbers, symbols, abbreviations and words of other languages that the site also lists.
VOWELS = "aàáảãạăằắẳẵặâầấẩẫậeèéẻẽẹêềếểễệiìíỉĩịoòóỏõọôồốổỗộơờớởỡợuùúủũụưừứửữựyỳýỷỹỵ"
SYLLABLE = re.compile(r"^(?:ngh|ng|nh|ch|gh|gi|kh|ph|qu|th|tr|[bcdđghklmnpqrstvx])?[%s]{1,3}(?:ch|ng|nh|[cmnpt])?$" % VOWELS)


def call(params):
    params = dict(params, format="json")
    request = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers={"User-Agent": USER_AGENT})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except OSError as error:
            if attempt == 3:
                raise
            print("retrying after: %s" % error, file=sys.stderr)
            time.sleep(2 * (attempt + 1))


def category_titles(delay):
    params = {"action": "query", "list": "categorymembers", "cmtitle": CATEGORY,
              "cmnamespace": 0, "cmlimit": 500, "cmtype": "page"}
    while True:
        data = call(params)
        if "error" in data:
            sys.exit("API error: %s" % data["error"])
        for member in data["query"]["categorymembers"]:
            yield member["title"]
        if "continue" not in data:
            return
        params.update(data["continue"])
        time.sleep(delay)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-o", "--output", required=True, help="dictionary file to write")
    parser.add_argument("--count", type=int, default=10, help="count given to every compound (default 10)")
    parser.add_argument("--any-letters", action="store_true", help="also keep entries that are not Vietnamese syllables")
    parser.add_argument("--max-syllables", type=int, default=6, help="skip entries longer than this (default 6)")
    parser.add_argument("--delay", type=float, default=0.3, help="seconds between API calls (default 0.3)")
    args = parser.parse_args()

    singles, compounds = set(), set()
    seen = skipped = 0
    for title in category_titles(args.delay):
        seen += 1
        parts = unicodedata.normalize("NFC", title).lower().split()
        plain = re.compile(r"^[^\W\d_]+$", re.UNICODE) if args.any_letters else SYLLABLE
        if not parts or len(parts) > args.max_syllables or not all(plain.match(p) for p in parts):
            skipped += 1
            continue
        (singles if len(parts) == 1 else compounds).add(" ".join(parts))
        if seen % 5000 == 0:
            print("%d titles..." % seen, file=sys.stderr)

    with open(args.output, "w", encoding="utf-8") as out:
        out.write("# Words of the Vietnamese Wiktionary (vi.wiktionary.org), category \"Muc tu tieng Viet\".\n")
        out.write("# Source: https://vi.wiktionary.org  Retrieved: %s  by scripts/fetch-wiktionary-dictionary.py\n"
                  % datetime.date.today().isoformat())
        out.write("# Licence: Creative Commons Attribution-ShareAlike 4.0, https://creativecommons.org/licenses/by-sa/4.0/\n")
        out.write("# Only the titles are used. Contributors: see the history of each page on the site.\n")
        out.write("\n#!context\n")
        for word in sorted(singles):
            out.write("%s\t1\n" % word)
        out.write("\n#!compounds\n")
        for word in sorted(compounds):
            out.write("%s\t%d\n" % (word, args.count))
        out.write("\n#!context\n")
    print("%d titles read: %d syllables, %d compounds kept, %d skipped" % (seen, len(singles), len(compounds), skipped))


if __name__ == "__main__":
    main()
