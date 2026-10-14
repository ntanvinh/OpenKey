//
//  SnippetSearch.cpp
//  VOpenKey
//
#include "SnippetSearch.h"

#include <algorithm>
#include <cmath>

#include "Suggest.h"

namespace vsnippet {

namespace {

std::vector<std::string> splitWords(const std::string& folded) {
    std::vector<std::string> words;
    std::string current;
    for (char c : folded) {
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            if (!current.empty())
                words.push_back(current);
            current.clear();
        } else {
            current += c;
        }
    }
    if (!current.empty())
        words.push_back(current);
    return words;
}

bool isWordCharacter(char c) {
    unsigned char u = (unsigned char)c;
    return (u >= '0' && u <= '9') || (u >= 'a' && u <= 'z') || u >= 0x80;
}

//how well a word is in a text: 0 = not at all, 3 = at the start of the text, 2 = at the start of a word, 1 = inside a word
int where(const std::string& text, const std::string& word) {
    size_t at = text.find(word);
    if (at == std::string::npos)
        return 0;
    if (at == 0)
        return 3;
    for (size_t pos = at; pos != std::string::npos; pos = text.find(word, pos + 1)) {
        if (pos == 0 || !isWordCharacter(text[pos - 1]))
            return 2;
    }
    return 1;
}

} // namespace

Index::Index(const std::vector<Entry>& entries) {
    folded_.reserve(entries.size());
    for (const Entry& e : entries) {
        Folded f;
        f.title = vsuggest::Engine::foldForSearch(e.title);
        f.keywords = vsuggest::Engine::foldForSearch(e.keywords);
        f.content = vsuggest::Engine::foldForSearch(e.content);
        f.useCount = e.useCount;
        f.lastUsed = e.lastUsed;
        folded_.push_back(std::move(f));
    }
}

std::vector<size_t> Index::search(const std::string& query) const {
    std::vector<std::string> words = splitWords(vsuggest::Engine::foldForSearch(query));

    struct Hit {
        size_t index;
        int score;
    };
    std::vector<Hit> hits;
    for (size_t i = 0; i < folded_.size(); i++) {
        const Folded& f = folded_[i];
        int score = 0;
        bool all = true;
        for (const std::string& word : words) {
            static const int kTitle[4] = {0, 50, 80, 100};
            static const int kKeywords[4] = {0, 25, 40, 45};
            int w = where(f.title, word);
            if (w > 0) {
                score += kTitle[w];
                continue;
            }
            w = where(f.keywords, word);
            if (w > 0) {
                score += kKeywords[w];
                continue;
            }
            if (f.content.find(word) != std::string::npos) {
                score += 8;
                continue;
            }
            all = false;
            break;
        }
        if (!all)
            continue;
        //what is used a lot comes first among the ones that match equally well
        score += (int)std::min(20.0, 4.0 * std::log2(1.0 + f.useCount));
        hits.push_back({i, score});
    }

    std::stable_sort(hits.begin(), hits.end(), [this, &words](const Hit& a, const Hit& b) {
        if (words.empty()) { //no query: used last, then used most
            if (folded_[a.index].lastUsed != folded_[b.index].lastUsed)
                return folded_[a.index].lastUsed > folded_[b.index].lastUsed;
            return folded_[a.index].useCount > folded_[b.index].useCount;
        }
        if (a.score != b.score)
            return a.score > b.score;
        if (folded_[a.index].lastUsed != folded_[b.index].lastUsed)
            return folded_[a.index].lastUsed > folded_[b.index].lastUsed;
        return false;
    });

    std::vector<size_t> result;
    result.reserve(hits.size());
    for (const Hit& h : hits)
        result.push_back(h.index);
    return result;
}

std::string expand(const std::string& text, const Values& values) {
    struct Placeholder {
        const char* name;
        const std::string Values::*value;
    };
    static const Placeholder kPlaceholders[] = {
        {"{clipboard}", &Values::clipboard},
        {"{date}", &Values::date},
        {"{time}", &Values::time},
    };

    std::string result;
    result.reserve(text.size());
    size_t i = 0;
    while (i < text.size()) {
        bool replaced = false;
        if (text[i] == '{') {
            for (const Placeholder& p : kPlaceholders) {
                size_t length = std::char_traits<char>::length(p.name);
                if (text.compare(i, length, p.name) == 0) {
                    result += values.*(p.value);
                    i += length;
                    replaced = true;
                    break;
                }
            }
        }
        if (!replaced)
            result += text[i++];
    }
    return result;
}

} // namespace vsnippet
