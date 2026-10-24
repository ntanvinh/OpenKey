//
//  MacroPresets.cpp
//  VOpenKey
//
#include "MacroPresets.h"

#include <set>

namespace vmacro {

static std::string trim(const std::string& s) {
    size_t a = 0, b = s.size();
    while (a < b && (s[a] == ' ' || s[a] == '\t' || s[a] == '\r' || s[a] == '\n')) a++;
    while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t' || s[b - 1] == '\r' || s[b - 1] == '\n')) b--;
    return s.substr(a, b - a);
}

std::vector<Preset> parsePresets(const std::string& fileText) {
    std::vector<Preset> presets;
    std::set<std::string> seen;
    std::string text = fileText;
    if (text.compare(0, 3, "\xEF\xBB\xBF") == 0)
        text.erase(0, 3);
    size_t from = 0;
    while (from <= text.size()) {
        size_t end = text.find('\n', from);
        std::string line = trim(text.substr(from, end == std::string::npos ? std::string::npos : end - from));
        from = end == std::string::npos ? text.size() + 1 : end + 1;
        if (line.empty() || line[0] == ';')
            continue;
        size_t colon = line.find(':');
        if (colon == std::string::npos)
            continue;
        std::string abbreviation = trim(line.substr(0, colon));
        std::string content = trim(line.substr(colon + 1));
        if (abbreviation.empty() || content.empty() || !seen.insert(abbreviation).second)
            continue;
        Preset preset;
        preset.text = abbreviation;
        preset.content = content;
        presets.push_back(preset);
    }
    return presets;
}

std::string examples(const std::vector<Preset>& presets, size_t count) {
    std::string result;
    for (size_t i = 0; i < presets.size() && i < count; i++) {
        if (i > 0)
            result += ", ";
        result += presets[i].text + " -> " + presets[i].content;
    }
    return result;
}

} // namespace vmacro
