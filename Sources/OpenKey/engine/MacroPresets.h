//
//  MacroPresets.h
//  VOpenKey
//
//  The table of common Vietnamese abbreviations (ko = khong, dc = duoc...) that comes with the program
//  (engine/dictionaries/vi-macros.txt), for the user to add to their own table. Reading the list only: adding to the table of
//  the user is done by the platform with addMacro (Macro.h), and never replaces an abbreviation the user already has.
//  Plain C++11, UTF-8, ASCII source.
//
//  The file has one abbreviation per line, "abbreviation:full text"; a line that starts with ";" is a comment.
//
#ifndef MacroPresets_h
#define MacroPresets_h

#include <string>
#include <vector>

namespace vmacro {

struct Preset {
    std::string text;     //what is typed: "ko"
    std::string content;  //what it becomes
};

/// The abbreviations of the file text, in its order. Lines without a colon, with nothing before it or after it, are skipped; the
/// first colon separates (the full text may have colons); a repeated abbreviation counts once, the first one.
std::vector<Preset> parsePresets(const std::string& fileText);

/// A few of them as a sentence: "ko -> khong, dc -> duoc, vs -> voi" (an arrow of two characters; the platform may write its own).
std::string examples(const std::vector<Preset>& presets, size_t count);

} // namespace vmacro

#endif /* MacroPresets_h */
