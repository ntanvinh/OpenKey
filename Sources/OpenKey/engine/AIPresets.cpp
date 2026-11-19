//
//  AIPresets.cpp
//  VOpenKey
//
#include "AIPresets.h"
#include "MiniJson.h"

#include <set>

namespace vpreset {

static bool fail(std::string* error, const std::string& message) {
    if (error != NULL)
        *error = message;
    return false;
}

static size_t countOf(const std::string& text, const std::string& what) {
    size_t count = 0;
    for (size_t at = text.find(what); at != std::string::npos; at = text.find(what, at + what.size()))
        count++;
    return count;
}

static bool parseGroups(const vjson::Value& list, std::vector<Group>& out, std::set<std::string>& ids, std::string* error) {
    if (list.isNull())
        return true;
    if (!list.isArray())
        return fail(error, "groups must be a list");
    for (size_t i = 0; i < list.items().size(); i++) {
        Group group;
        group.id = list.items()[i]["id"].stringOr("");
        group.title = list.items()[i]["title"].stringOr("");
        if (group.id.empty() || group.title.empty())
            return fail(error, "a group needs an id and a title");
        if (!ids.insert(group.id).second)
            return fail(error, "the group " + group.id + " is used twice");
        out.push_back(group);
    }
    return true;
}

bool parse(const std::string& jsonText, Presets& out, std::string* error) {
    out = Presets();
    vjson::Value root;
    if (!vjson::parse(jsonText, root) || !root.isObject())
        return fail(error, "not a JSON object");
    Presets result;
    result.promptTemplate = root["promptTemplate"].stringOr("");
    if (countOf(result.promptTemplate, "{instruction}") != 1 || countOf(result.promptTemplate, "{text}") != 1)
        return fail(error, "the template must have {instruction} and {text} once each");
    std::set<std::string> groupIds, imageGroupIds;
    if (!parseGroups(root["groups"], result.groups, groupIds, error) || !parseGroups(root["imageGroups"], result.imageGroups, imageGroupIds, error))
        return false;
    const vjson::Value& list = root["presets"];
    if (!list.isArray() || list.items().empty())
        return fail(error, "no presets");
    std::set<std::string> seen;
    for (size_t i = 0; i < list.items().size(); i++) {
        const vjson::Value& item = list.items()[i];
        Preset preset;
        preset.id = item["id"].stringOr("");
        preset.title = item["title"].stringOr("");
        preset.summary = item["summary"].stringOr("");
        preset.instruction = item["instruction"].stringOr("");
        preset.poem = item["poem"].asBool(false);
        preset.group = item["group"].stringOr("");
        if (!groupIds.empty() && groupIds.count(preset.group) == 0)
            return fail(error, "the preset " + preset.id + " is in a group that is not listed");
        if (preset.id.empty() || preset.title.empty() || preset.instruction.empty())
            return fail(error, "a preset needs an id, a title and an instruction");
        if (!seen.insert(preset.id).second)
            return fail(error, "the id " + preset.id + " is used twice");
        result.list.push_back(preset);
    }
    result.imageNote = root["imageNote"].stringOr("");
    const vjson::Value& sizes = root["imageSizes"];
    if (!sizes.isNull() && !sizes.isArray())
        return fail(error, "imageSizes must be a list");
    if (sizes.isArray() && !sizes.items().empty()) {
        static const char* const kPlaces[] = {"{width}", "{height}", "{ratio}", "{hint}"};
        for (size_t k = 0; k < 4; k++)
            if (countOf(result.imageNote, kPlaces[k]) != 1)
                return fail(error, std::string("the note of the picture sizes must have ") + kPlaces[k] + " once");
        std::set<std::string> seenSizes;
        for (size_t i = 0; i < sizes.items().size(); i++) {
            const vjson::Value& item = sizes.items()[i];
            ImageSize size;
            size.id = item["id"].stringOr("");
            size.group = item["group"].stringOr("");
            size.title = item["title"].stringOr("");
            size.summary = item["summary"].stringOr("");
            size.ratio = item["ratio"].stringOr("");
            size.hint = item["hint"].stringOr("");
            size.width = (int)item["width"].asNumber(0);
            size.height = (int)item["height"].asNumber(0);
            if (size.id.empty() || size.title.empty() || size.ratio.empty())
                return fail(error, "a size of picture needs an id, a title and a ratio");
            if (size.width < 16 || size.width > 8192 || size.height < 16 || size.height > 8192)
                return fail(error, "the size " + size.id + " has a side that is not between 16 and 8192 pixels");
            if (!imageGroupIds.empty() && imageGroupIds.count(size.group) == 0)
                return fail(error, "the size " + size.id + " is in a group that is not listed");
            if (!seenSizes.insert(size.id).second)
                return fail(error, "the size " + size.id + " is used twice");
            result.imageSizes.push_back(size);
        }
    }
    out = result;
    return true;
}

const Preset* find(const Presets& presets, const std::string& id) {
    for (size_t i = 0; i < presets.list.size(); i++)
        if (presets.list[i].id == id)
            return &presets.list[i];
    return NULL;
}

std::vector<const Preset*> inGroup(const Presets& presets, const std::string& groupId) {
    std::vector<const Preset*> found;
    for (size_t i = 0; i < presets.list.size(); i++)
        if (presets.list[i].group == groupId)
            found.push_back(&presets.list[i]);
    return found;
}

static std::string trim(const std::string& s) {
    size_t a = 0, b = s.size();
    while (a < b && (s[a] == ' ' || s[a] == '\t' || s[a] == '\r' || s[a] == '\n')) a++;
    while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t' || s[b - 1] == '\r' || s[b - 1] == '\n')) b--;
    return s.substr(a, b - a);
}

std::string buildPrompt(const Presets& presets, const Preset& preset, const std::string& draft) {
    const std::string text = trim(draft);
    const std::string& templ = presets.promptTemplate;
    std::string result;
    size_t at = 0;
    while (at < templ.size()) {
        if (templ.compare(at, 13, "{instruction}") == 0) {
            result += preset.instruction;
            at += 13;
        } else if (templ.compare(at, 6, "{text}") == 0) {
            result += text;
            at += 6;
        } else {
            result += templ[at++];
        }
    }
    return result;
}

const ImageSize* findImageSize(const Presets& presets, const std::string& id) {
    for (size_t i = 0; i < presets.imageSizes.size(); i++)
        if (presets.imageSizes[i].id == id)
            return &presets.imageSizes[i];
    return NULL;
}

std::string imageSizeLabel(const ImageSize& size) {
    return size.title + " (" + std::to_string(size.width) + "\xC3\x97" + std::to_string(size.height) + ")";
}

std::string buildImageRequest(const Presets& presets, const ImageSize* size, const std::string& description) {
    const std::string text = trim(description);
    if (size == NULL)
        return text;
    const std::string& note = presets.imageNote;
    struct Place { const char* key; size_t length; std::string value; };
    const Place places[] = {{"{width}", 7, std::to_string(size->width)}, {"{height}", 8, std::to_string(size->height)},
                            {"{ratio}", 7, size->ratio}, {"{hint}", 6, size->hint}};
    std::string filled;
    size_t at = 0;
    while (at < note.size()) {
        bool matched = false;
        if (note[at] == '{') {
            for (size_t k = 0; k < 4 && !matched; k++) {
                if (note.compare(at, places[k].length, places[k].key) == 0) {
                    filled += places[k].value;
                    at += places[k].length;
                    matched = true;
                }
            }
        }
        if (!matched)
            filled += note[at++];
    }
    return text + "\n\n" + filled;
}

bool coverCrop(int srcW, int srcH, int dstW, int dstH, int& x, int& y, int& w, int& h) {
    if (srcW <= 0 || srcH <= 0 || dstW <= 0 || dstH <= 0)
        return false;
    w = srcW;
    h = srcH;
    if ((long long)srcW * dstH > (long long)dstW * srcH) {          // the picture is the wider one: the sides are cut
        w = (int)(((long long)srcH * dstW + dstH / 2) / dstH);
        if (w < 1) w = 1;
        if (w > srcW) w = srcW;
    } else {                                                          // the taller one, or the same proportions: the top and the bottom are cut
        h = (int)(((long long)srcW * dstH + dstW / 2) / dstW);
        if (h < 1) h = 1;
        if (h > srcH) h = srcH;
    }
    x = (srcW - w) / 2;
    y = (srcH - h) / 2;
    return true;
}

} // namespace vpreset
