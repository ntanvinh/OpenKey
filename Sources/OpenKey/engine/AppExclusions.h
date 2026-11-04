//
//  AppExclusions.h
//  VOpenKey AI, portable
//
//  The list of programs where the suggestion bar stays away (the ones where Tab belongs to the program: terminals). The user edits
//  it in Settings. macOS keeps bundle identifiers in its own code; Windows keeps the file names of programs here, so that the rules
//  of what a name is are tested. Names are UTF-8; only ASCII letters are folded to lower case, like the Windows side does for
//  the name of the program in front. ASCII-only source.
//
#pragma once
#include <string>
#include <vector>

namespace vsuggest {
namespace appexclusions {

/**
 * What the user typed or picked, as a name to keep: surrounding blanks and quotes and any folder in front are dropped, ASCII
 * letters are made lower case, ".exe" is added to a name that has no extension. Empty when nothing usable is left (empty text,
 * a control character, or one of * ? < > | :).
 */
std::string normalizeName(const std::string& text);

/** Every name normalised, those that came out empty and the repeats dropped, the order kept. */
std::vector<std::string> normalizeList(const std::vector<std::string>& names);

/** One name per line. */
std::string serialize(const std::vector<std::string>& names);

/** The other way round: lines (LF, CR or CR LF) normalised like normalizeList. */
std::vector<std::string> parse(const std::string& text);

/** True when `exeName` (already in lower case, as the program in front reports it) is in the list. */
bool contains(const std::vector<std::string>& names, const std::string& exeName);

} // namespace appexclusions
} // namespace vsuggest
