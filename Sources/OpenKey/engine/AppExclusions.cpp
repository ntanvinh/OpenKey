//
//  AppExclusions.cpp
//  VOpenKey AI, portable
//
#include "AppExclusions.h"
#include <algorithm>

namespace vsuggest {
namespace appexclusions {

namespace {

bool isBlank(char c) {
    return c == ' ' || c == '\t';
}

bool isQuote(char c) {
    return c == '"' || c == '\'';
}

} // namespace

std::string normalizeName(const std::string& text) {
    std::string name = text;
    //blanks and quotes around it ("C:\Program Files\x.exe" is often pasted with quotes)
    for (;;) {
        size_t before = name.size();
        while (!name.empty() && (isBlank(name.back()) || isQuote(name.back())))
            name.pop_back();
        size_t start = 0;
        while (start < name.size() && (isBlank(name[start]) || isQuote(name[start])))
            start++;
        name.erase(0, start);
        if (name.size() == before)
            break;
    }
    //only the file name of a path
    size_t slash = name.find_last_of("\\/");
    if (slash != std::string::npos)
        name.erase(0, slash + 1);
    if (name.empty())
        return std::string();
    for (size_t i = 0; i < name.size(); i++) {
        unsigned char c = (unsigned char)name[i];
        if (c < 0x20 || c == 0x7F || c == '*' || c == '?' || c == '<' || c == '>' || c == '|' || c == ':')
            return std::string();
        if (c >= 'A' && c <= 'Z')
            name[i] = (char)(c - 'A' + 'a');
    }
    if (name == "." || name == "..")
        return std::string();
    if (name.find('.') == std::string::npos)
        name += ".exe";
    return name;
}

std::vector<std::string> normalizeList(const std::vector<std::string>& names) {
    std::vector<std::string> result;
    for (size_t i = 0; i < names.size(); i++) {
        std::string name = normalizeName(names[i]);
        if (!name.empty() && std::find(result.begin(), result.end(), name) == result.end())
            result.push_back(name);
    }
    return result;
}

std::string serialize(const std::vector<std::string>& names) {
    std::string text;
    for (size_t i = 0; i < names.size(); i++) {
        if (i > 0)
            text += '\n';
        text += names[i];
    }
    return text;
}

std::vector<std::string> parse(const std::string& text) {
    std::vector<std::string> lines;
    std::string line;
    for (size_t i = 0; i < text.size(); i++) {
        if (text[i] == '\n' || text[i] == '\r') {
            lines.push_back(line);
            line.clear();
        } else {
            line += text[i];
        }
    }
    lines.push_back(line);
    return normalizeList(lines);
}

bool contains(const std::vector<std::string>& names, const std::string& exeName) {
    return !exeName.empty() && std::find(names.begin(), names.end(), exeName) != names.end();
}

} // namespace appexclusions
} // namespace vsuggest
