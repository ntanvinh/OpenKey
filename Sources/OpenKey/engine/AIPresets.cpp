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

bool parse(const std::string& jsonText, Presets& out, std::string* error) {
    out = Presets();
    vjson::Value root;
    if (!vjson::parse(jsonText, root) || !root.isObject())
        return fail(error, "not a JSON object");
    Presets result;
    result.promptTemplate = root["promptTemplate"].stringOr("");
    if (countOf(result.promptTemplate, "{instruction}") != 1 || countOf(result.promptTemplate, "{text}") != 1)
        return fail(error, "the template must have {instruction} and {text} once each");
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
        if (preset.id.empty() || preset.title.empty() || preset.instruction.empty())
            return fail(error, "a preset needs an id, a title and an instruction");
        if (!seen.insert(preset.id).second)
            return fail(error, "the id " + preset.id + " is used twice");
        result.list.push_back(preset);
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

} // namespace vpreset
