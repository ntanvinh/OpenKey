//
//  AIPresets.h
//  VOpenKey
//
//  The ready-made conversions of the AI window (Sua loi, Lich su, Dich sang Anh...): the list and the request that is made of one
//  of them. The words live in engine/ai/ai-presets.json (UTF-8 data, like the default snippets); the Windows program reads that file
//  from its resources, and the macOS program has the same words in AIPresets.m, which tests/ai_assistant_test.m compares with the
//  file so that the two cannot drift apart. Plain C++11, ASCII source.
//
#ifndef AIPresets_h
#define AIPresets_h

#include <string>
#include <vector>

namespace vpreset {

struct Preset {
    std::string id;           //"fix", "polite", "lucBat"...: short and stable
    std::string title;        //what the button says (UTF-8)
    std::string summary;      //one line for the tooltip
    std::string instruction;  //what the AI is told to do with the text
    bool poem;                //the answer is not checked for syllables and rhymes: the window says so
};

struct Presets {
    std::string promptTemplate;  //has {instruction} and {text} in it, once each
    std::vector<Preset> list;
};

/// Reads the file. False (and `out` empty) when it is not JSON, has no presets, has a preset without an id, a title or an
/// instruction, repeats an id, or has a template that lacks {instruction} or {text}.
bool parse(const std::string& jsonText, Presets& out, std::string* error = NULL);

/// The preset with this id, NULL when there is none.
const Preset* find(const Presets& presets, const std::string& id);

/// What is sent to the AI: the template with the instruction and the text (blanks and line breaks at both ends cut off) put in. It is
/// done in one pass, so a text that itself contains "{instruction}" or "{text}" is left as it is.
std::string buildPrompt(const Presets& presets, const Preset& preset, const std::string& draft);

} // namespace vpreset

#endif /* AIPresets_h */
