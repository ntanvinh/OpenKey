#!/usr/bin/env python3
"""Build a suggestion dictionary for VOpenKey from Vietnamese text.

    scripts/build-dictionary.py -o vi-big.txt corpus/*.txt some-folder/

Reads UTF-8 text files (every .txt/.md/.text file inside folders too), splits the text into
syllables and counts them, pairs and triples. Compound words written with an underscore, as in
text that has been word-segmented (thiết_kế), are counted as compounds; a plain list of compound
words, one per line (spaces or underscores, an optional count after a tab), can be added with
--compound-list. Typing a compound together, without spaces or accents ("thietke"), then offers it. The result is a dictionary file in the format of
engine/Suggest.h: copy it to the Dictionaries folder (macOS: ~/Library/Application Support/VOpenKey/
Dictionaries/) and it is used together with the dictionaries shipped with the app.

The more text, the better the suggestions: news, books, subtitles, your own writing...
Words never cross a punctuation mark or a line break, so pairs are real neighbours.
"""
import argparse
import collections
import os
import re
import sys
import unicodedata

# a syllable: letters only (so numbers, URLs and symbols never become suggestions); syllables joined
# by underscores are a compound word
WORD = re.compile(r"[^\W\d_]+(?:_[^\W\d_]+)*", re.UNICODE)
EXTENSIONS = (".txt", ".md", ".text")


def files(paths):
    for path in paths:
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                for name in sorted(names):
                    if name.lower().endswith(EXTENSIONS):
                        yield os.path.join(root, name)
        else:
            yield path


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("inputs", nargs="+", help="text files or folders")
    parser.add_argument("-o", "--output", required=True, help="dictionary file to write")
    parser.add_argument("--min-word", type=int, default=2, help="drop words seen fewer times (default 2)")
    parser.add_argument("--min-pair", type=int, default=2, help="drop word pairs seen fewer times (default 2)")
    parser.add_argument("--min-triple", type=int, default=3, help="drop word triples seen fewer times (default 3)")
    parser.add_argument("--max-length", type=int, default=12, help="ignore syllables longer than this (default 12)")
    parser.add_argument("--min-compound", type=int, default=2, help="drop compounds seen fewer times (default 2)")
    parser.add_argument("--compound-list", action="append", default=[], metavar="FILE",
                        help="text file with one compound word per line (optional count after a tab); can be repeated")
    args = parser.parse_args()

    uni = collections.Counter()
    bi = collections.Counter()
    tri = collections.Counter()
    compounds = collections.Counter()
    read = 0
    for path in files(args.inputs):
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = unicodedata.normalize("NFC", line).lower()
                    # punctuation ends a phrase: split on everything that is not a letter, digit or space
                    for part in re.split(r"[^\w\s]+|\d+", line):
                        tokens = [t for t in WORD.findall(part) if all(len(x) <= args.max_length for x in t.split("_"))]
                        words = []
                        for token in tokens:
                            syllables = token.split("_")
                            if len(syllables) > 1:
                                compounds["_".join(syllables)] += 1
                            words.extend(syllables)
                        for i, w in enumerate(words):
                            uni[w] += 1
                            if i >= 1:
                                bi[(words[i - 1], w)] += 1
                            if i >= 2:
                                tri[(words[i - 2], words[i - 1], w)] += 1
            read += 1
        except OSError as e:
            print("skipped %s: %s" % (path, e), file=sys.stderr)

    for path in args.compound_list:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = unicodedata.normalize("NFC", line).strip().lower()
                if not line or line.startswith("#"):
                    continue
                text, _, count = line.partition("\t")
                syllables = [x for x in re.split(r"[\s_]+", text) if x]
                if len(syllables) > 1 and all(WORD.fullmatch(x) for x in syllables):
                    compounds["_".join(syllables)] += int(count) if count.strip().isdigit() else args.min_compound

    with open(args.output, "w", encoding="utf-8") as out:
        out.write("# Built by scripts/build-dictionary.py from %d file(s).\n" % read)
        for words, count in sorted(uni.items(), key=lambda kv: (-kv[1], kv[0])):
            if count >= args.min_word:
                out.write("%s\t%d\n" % (words, count))
        for words, count in sorted(bi.items(), key=lambda kv: (-kv[1], kv[0])):
            if count >= args.min_pair:
                out.write("%s\t%d\n" % (" ".join(words), count))
        for words, count in sorted(tri.items(), key=lambda kv: (-kv[1], kv[0])):
            if count >= args.min_triple:
                out.write("%s\t%d\n" % (" ".join(words), count))
        for word, count in sorted(compounds.items(), key=lambda kv: (-kv[1], kv[0])):
            if count >= args.min_compound:
                out.write("%s\t%d\n" % (word, count))
    print("%s: %d words, %d pairs, %d triples, %d compounds kept (from %d files)" % (
        args.output,
        sum(1 for c in uni.values() if c >= args.min_word),
        sum(1 for c in bi.values() if c >= args.min_pair),
        sum(1 for c in tri.values() if c >= args.min_triple),
        sum(1 for c in compounds.values() if c >= args.min_compound),
        read))


if __name__ == "__main__":
    main()
