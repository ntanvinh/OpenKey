---
title: "Dictionary entries: six source formats, one parser in engine/DictStore.cpp, macOS-style render (2026-11-22)"
author: Vinhnt
date: 2026-11-22
branch: master
cost: { minutes: 18, tokens: 254055 }
touches:
  - CHANGELOG.md
  - Sources/OpenKey/engine/DictStore.cpp
  - Sources/OpenKey/engine/DictStore.h
  - Sources/OpenKey/engine/tests/dict_test.cpp
  - Sources/OpenKey/macOS/ModernKey/DictionaryPalette.m
  - Sources/OpenKey/macOS/ModernKey/DictionaryService.h
  - Sources/OpenKey/macOS/ModernKey/DictionaryService.mm
  - Sources/OpenKey/macOS/OpenKey.xcodeproj/project.pbxproj
  - Sources/OpenKey/macOS/tests/dictionary_speech_test.m
  - Sources/OpenKey/macOS/tests/run-dictionary-speech-test.sh
---

## Decided
- The dictionaries of the catalog write an entry in six ways (measured on 9 real dictionaries, raw bytes via the .vdict): Thich Hoc = HTML with a <style> block (its CSS was shown as text), numbers as <b>1.</b>; OVDP (en-vi, vi-en, fr-vi, de-vi...) = ONE flat line "* pos - sense =example+translation !idiom @field -sense" (the source lost its line breaks; FVDP files keep them); Han-Viet = HTML with <br> and <li> never closed, ◇ ◎ § for quotations; Viet-Viet (Ho Ngoc Duc) = "- 1 dt. sense: example <br> - 2 ..." with <hr/><h3>word</h3> and <font color="white"> text for the old search; WordNet = "n 1: gloss; "ex" [syn: {a}] <br/> 2: ..." (from sense 9 the <br/> is missing; an inflected form starts with its base word "ring <br/> n 1: ...").
- ONE parser for all, in engine/DictStore.cpp (parseEntryRichText -> parseHtmlIntoLines / parseMarkupTextIntoLines / parseWordNetIntoLines, then finishLines): skips style/script/hidden font, tokenises the flat OVDP text by marks that follow white space, numbers senses only when their part of speech has several (marker "1."), joins an idiom with its meaning, cleans <hóa> -> (hóa), {{x}} -> x, entities. New BlockKind Idiom=8 and Section=9, FormattedLine.marker now filled. Shared by Windows (rich-edit shows numbers, ▸ idioms, capital field headings) and macOS (VOKDictionaryFormattedLine.marker).
- macOS render (DictionaryPalette.m renderedDefinitions:forHit:): Apple Dictionary style, system fonts and colours, numbers in a tab column of 24pt with hanging indent, part of speech bold italic with its forms quiet, examples italic with translation after, idioms after ▸, field as small capitals heading.
- Verified: engine dict_test (new testEntryFormatting, one sample per family), run under ASan/UBSan together with a sweep of 6527 words over 9 dictionaries (build/dict-border/sweep.cpp idea: count lines that still show <tag>, &#, CSS, marks); dictionary_speech_test (render checks), dictionary_test, case bar, tap test, mingw x64/x86 link, xcodebuild: all green. Red-green: removing the <style> skip makes the render test fail.

## Tried and ruled out
- Treating every "<word>" as HTML: OVDP writes the field of use as <hóa>, <thgt>, <thực>; "<thực>" even starts like the <th> tag. Only a whitelist of real tag names, ending in '>' / space / '/', counts as HTML.
- Comparing the first heading with the headword after removing accents: in Viet-Viet "run" and "rùn" are different words of one entry (they were dropped).
- A "hyphen starts a sense" rule without "after white space": "well-known", "x-ray" would split.

## Watch out
- The first sweep only looked at the first hit; always print the hit headword and the start of the raw entry next to a bad line (that is what showed the WordNet "ring <br/>" and the <thực> cases).
- C++ string literals: "\xADch", "\xA1c", "\xBAc" are read as one escape (hex digit after it): split the literal ("\xAD" "ch").
- engine/tests/dict_test.cpp must run with engine/tests as working directory (it reads ../dictionaries/catalog.json), otherwise testCatalog dereferences an empty vector and crashes.
- NOT verified: the Windows window itself (only compiled and linked), the real window on the owner's screen (renders were made off screen from the app's own drawing), dictionaries of the catalog that were not downloaded (ja/zh/ko/ru/es/it/cs/nb/pt-vi use the same OVDP format as fr-vi/de-vi but were not looked at).
