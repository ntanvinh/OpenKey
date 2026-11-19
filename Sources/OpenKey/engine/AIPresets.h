//
//  AIPresets.h
//  VOpenKey
//
//  The ready-made conversions of the AI window (Sua loi, Lich su, Dich sang Anh...) and its ready-made sizes of pictures (Instagram,
//  YouTube, icon, greeting card...): the lists, the request that is made of one conversion, the note that tells the AI the canvas of a
//  picture, and the part of a picture that is kept when it is cut to a size. The words live in engine/ai/ai-presets.json (UTF-8 data, like the default snippets); the Windows program reads that file
//  from its resources, and the macOS program has the same words in AIPresets.m, which tests/ai_assistant_test.m compares with the
//  file so that the two cannot drift apart. Plain C++11, ASCII source.
//
#ifndef AIPresets_h
#define AIPresets_h

#include <string>
#include <vector>

namespace vpreset {

struct Group {
    std::string id;           //"tone", "occasion", "poem", "length" (or "social", "icon", "card" for sizes of pictures)
    std::string title;        //what the tab, or the section of the menu, says (UTF-8)
};

struct Preset {
    std::string id;           //"fix", "polite", "lucBat"...: short and stable
    std::string group;         //the id of its group; empty when the file has no groups
    std::string title;        //what the button says (UTF-8)
    std::string summary;      //one line for the tooltip
    std::string instruction;  //what the AI is told to do with the text
    bool poem;                //the answer is not checked for syllables and rhymes: the window says so
};

/// A ready-made size of a picture.
struct ImageSize {
    std::string id;           //"instagramSquare"...
    std::string group;        //the id of its group among Presets::imageGroups
    std::string title;        //where it is used (UTF-8)
    std::string summary;      //one line for the tooltip
    int width;
    int height;
    std::string ratio;        //"1:1", "4:5", "1.91:1"
    std::string hint;         //what the picture is for, told to the AI (English)
    ImageSize() : width(0), height(0) {}
};

struct Presets {
    std::string promptTemplate;  //has {instruction} and {text} in it, once each
    std::vector<Group> groups;   //the tabs, in order (may be empty: then the presets are not grouped)
    std::vector<Preset> list;
    std::string imageNote;       //has {width}, {height}, {ratio} and {hint} in it, once each (empty when there are no sizes)
    std::vector<Group> imageGroups;
    std::vector<ImageSize> imageSizes;
};

/// Reads the file. False (and `out` empty) when it is not JSON, has no presets, has a preset without an id, a title or an
/// instruction, repeats an id, has a template that lacks {instruction} or {text}, has a preset in a group that is not listed, or has a
/// size of picture that is wrong (no id or title, a side that is not between 16 and 8192 pixels, a group that is not listed, an id used
/// twice, or a note that lacks {width}, {height}, {ratio} or {hint}).
bool parse(const std::string& jsonText, Presets& out, std::string* error = NULL);

/// The preset with this id, NULL when there is none.
const Preset* find(const Presets& presets, const std::string& id);

/// The presets of one group, in order.
std::vector<const Preset*> inGroup(const Presets& presets, const std::string& groupId);

/// What is sent to the AI: the template with the instruction and the text (blanks and line breaks at both ends cut off) put in. It is
/// done in one pass, so a text that itself contains "{instruction}" or "{text}" is left as it is.
std::string buildPrompt(const Presets& presets, const Preset& preset, const std::string& draft);

/// The size of picture with this id, NULL when there is none.
const ImageSize* findImageSize(const Presets& presets, const std::string& id);

/// The title with the pixels, as the menu of the sizes shows it: "Instagram - Vuong (1080x1080)" (the multiplication sign U+00D7 between).
std::string imageSizeLabel(const ImageSize& size);

/// What goes in the request for a picture in place of the description alone: the description (blanks and line breaks at both ends cut off),
/// then the note with the canvas. Filled in one pass, like buildPrompt. A size that is NULL gives the description alone.
std::string buildImageRequest(const Presets& presets, const ImageSize* size, const std::string& description);

/// The part of a picture of srcW x srcH pixels that has the proportions of dstW x dstH and is centred (as large as it can be): what is kept
/// when the picture is cut to a size. Whole pixels. False when a side is not positive.
bool coverCrop(int srcW, int srcH, int dstW, int dstH, int& x, int& y, int& w, int& h);

} // namespace vpreset

#endif /* AIPresets_h */
