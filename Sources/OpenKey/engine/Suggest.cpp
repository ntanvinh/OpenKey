//
//  Suggest.cpp
//  VOpenKey
//
//  See Suggest.h.
//
#include "Suggest.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

namespace vsuggest {

namespace {

typedef char32_t Cp;

/*==========================================================================================================*/
// Letters: base letter + shape + tone, so that "hoc" can find the same word with any tone on the o, and an o with a circumflex any tone on it
/*==========================================================================================================*/

enum : unsigned char { ShapeNone, ShapeCirc, ShapeBreve, ShapeHorn, ShapeStroke };

struct Letter {
    Cp base = 0;                //lowercase base letter: a, o, d...
    unsigned char shape = ShapeNone;
    unsigned char tone = 0;     //0 none, 1 grave, 2 acute, 3 hook, 4 tilde, 5 dot below
    bool upper = false;
};

struct Group {
    Cp lower[6]; //the letter with tone 0 to 5
    Cp upper[6];
    Cp base;
    unsigned char shape;
};

const Group kGroups[] = {
    {{0x0061, 0x00E0, 0x00E1, 0x1EA3, 0x00E3, 0x1EA1},
     {0x0041, 0x00C0, 0x00C1, 0x1EA2, 0x00C3, 0x1EA0},
     'a', ShapeNone},
    {{0x0103, 0x1EB1, 0x1EAF, 0x1EB3, 0x1EB5, 0x1EB7},
     {0x0102, 0x1EB0, 0x1EAE, 0x1EB2, 0x1EB4, 0x1EB6},
     'a', ShapeBreve},
    {{0x00E2, 0x1EA7, 0x1EA5, 0x1EA9, 0x1EAB, 0x1EAD},
     {0x00C2, 0x1EA6, 0x1EA4, 0x1EA8, 0x1EAA, 0x1EAC},
     'a', ShapeCirc},
    {{0x0065, 0x00E8, 0x00E9, 0x1EBB, 0x1EBD, 0x1EB9},
     {0x0045, 0x00C8, 0x00C9, 0x1EBA, 0x1EBC, 0x1EB8},
     'e', ShapeNone},
    {{0x00EA, 0x1EC1, 0x1EBF, 0x1EC3, 0x1EC5, 0x1EC7},
     {0x00CA, 0x1EC0, 0x1EBE, 0x1EC2, 0x1EC4, 0x1EC6},
     'e', ShapeCirc},
    {{0x0069, 0x00EC, 0x00ED, 0x1EC9, 0x0129, 0x1ECB},
     {0x0049, 0x00CC, 0x00CD, 0x1EC8, 0x0128, 0x1ECA},
     'i', ShapeNone},
    {{0x006F, 0x00F2, 0x00F3, 0x1ECF, 0x00F5, 0x1ECD},
     {0x004F, 0x00D2, 0x00D3, 0x1ECE, 0x00D5, 0x1ECC},
     'o', ShapeNone},
    {{0x00F4, 0x1ED3, 0x1ED1, 0x1ED5, 0x1ED7, 0x1ED9},
     {0x00D4, 0x1ED2, 0x1ED0, 0x1ED4, 0x1ED6, 0x1ED8},
     'o', ShapeCirc},
    {{0x01A1, 0x1EDD, 0x1EDB, 0x1EDF, 0x1EE1, 0x1EE3},
     {0x01A0, 0x1EDC, 0x1EDA, 0x1EDE, 0x1EE0, 0x1EE2},
     'o', ShapeHorn},
    {{0x0075, 0x00F9, 0x00FA, 0x1EE7, 0x0169, 0x1EE5},
     {0x0055, 0x00D9, 0x00DA, 0x1EE6, 0x0168, 0x1EE4},
     'u', ShapeNone},
    {{0x01B0, 0x1EEB, 0x1EE9, 0x1EED, 0x1EEF, 0x1EF1},
     {0x01AF, 0x1EEA, 0x1EE8, 0x1EEC, 0x1EEE, 0x1EF0},
     'u', ShapeHorn},
    {{0x0079, 0x1EF3, 0x00FD, 0x1EF7, 0x1EF9, 0x1EF5},
     {0x0059, 0x1EF2, 0x00DD, 0x1EF6, 0x1EF8, 0x1EF4},
     'y', ShapeNone},
};

const Cp kCombiningTones[6] = {0, 0x0300, 0x0301, 0x0309, 0x0303, 0x0323};

struct Tables {
    std::unordered_map<Cp, Letter> decomposed;
    std::unordered_map<uint32_t, Cp> composedLower;
    std::unordered_map<uint32_t, Cp> composedUpper;

    static uint32_t key(const Letter& l) {
        return ((uint32_t)l.base << 16) | ((uint32_t)l.shape << 8) | l.tone;
    }

    void add(Letter l, Cp lower, Cp upper) {
        l.upper = false;
        decomposed[lower] = l;
        composedLower[key(l)] = lower;
        l.upper = true;
        decomposed[upper] = l;
        composedUpper[key(l)] = upper;
    }

    Tables() {
        for (const Group& g : kGroups) {
            for (unsigned char tone = 0; tone < 6; tone++) {
                Letter l;
                l.base = g.base;
                l.shape = g.shape;
                l.tone = tone;
                add(l, g.lower[tone], g.upper[tone]);
            }
        }
        Letter d;
        d.base = 'd';
        d.shape = ShapeStroke;
        add(d, 0x0111, 0x0110); //d with stroke, lowercase and uppercase
    }
};

const Tables& tables() {
    static const Tables t;
    return t;
}

/*==========================================================================================================*/
// UTF-8
/*==========================================================================================================*/

Cp nextCodePoint(const std::string& s, size_t& i) {
    unsigned char c = (unsigned char)s[i];
    if (c < 0x80) {
        i++;
        return c;
    }
    int extra = c >= 0xF0 ? 3 : (c >= 0xE0 ? 2 : (c >= 0xC0 ? 1 : 0));
    if (extra == 0 || i + extra >= s.size()) { //stray continuation byte or cut sequence
        i++;
        return 0xFFFD;
    }
    Cp r = c & (0x3F >> extra);
    for (int k = 1; k <= extra; k++) {
        unsigned char cc = (unsigned char)s[i + k];
        if ((cc & 0xC0) != 0x80) {
            i++;
            return 0xFFFD;
        }
        r = (r << 6) | (cc & 0x3F);
    }
    i += extra + 1;
    return r;
}

void appendUtf8(std::string& s, Cp c) {
    if (c < 0x80) {
        s += (char)c;
    } else if (c < 0x800) {
        s += (char)(0xC0 | (c >> 6));
        s += (char)(0x80 | (c & 0x3F));
    } else if (c < 0x10000) {
        s += (char)(0xE0 | (c >> 12));
        s += (char)(0x80 | ((c >> 6) & 0x3F));
        s += (char)(0x80 | (c & 0x3F));
    } else {
        s += (char)(0xF0 | (c >> 18));
        s += (char)(0x80 | ((c >> 12) & 0x3F));
        s += (char)(0x80 | ((c >> 6) & 0x3F));
        s += (char)(0x80 | (c & 0x3F));
    }
}

/*==========================================================================================================*/
// Letters <-> text
/*==========================================================================================================*/

Letter makeLetter(Cp c) {
    const Tables& t = tables();
    auto it = t.decomposed.find(c);
    if (it != t.decomposed.end())
        return it->second;
    Letter l;
    l.base = c;
    if (c >= 'A' && c <= 'Z') {
        l.base = c + 32;
        l.upper = true;
    }
    return l;
}

/** Applies a combining accent to the letter before it, returns false if c is not one. */
bool applyCombining(Cp c, Letter& l) {
    for (unsigned char tone = 1; tone < 6; tone++) {
        if (kCombiningTones[tone] == c) {
            l.tone = tone;
            return true;
        }
    }
    switch (c) {
        case 0x0302: l.shape = ShapeCirc; return true;
        case 0x0306: l.shape = ShapeBreve; return true;
        case 0x031B: l.shape = ShapeHorn; return true;
    }
    return false;
}

std::vector<Letter> decode(const std::string& s) {
    std::vector<Letter> out;
    out.reserve(s.size());
    size_t i = 0;
    while (i < s.size()) {
        Cp c = nextCodePoint(s, i);
        if (c >= 0x0300 && c <= 0x036F) { //combining mark: belongs to the previous letter
            if (!out.empty())
                applyCombining(c, out.back());
            continue;
        }
        out.push_back(makeLetter(c));
    }
    return out;
}

void appendLetter(std::string& out, const Letter& l) {
    const Tables& t = tables();
    if (l.base < 128) {
        const auto& map = l.upper ? t.composedUpper : t.composedLower;
        auto it = map.find(Tables::key(l));
        if (it != map.end()) {
            appendUtf8(out, it->second);
            return;
        }
    }
    Cp b = l.base;
    if (l.upper && b >= 'a' && b <= 'z')
        b -= 32;
    appendUtf8(out, b);
    switch (l.shape) {
        case ShapeCirc: appendUtf8(out, 0x0302); break;
        case ShapeBreve: appendUtf8(out, 0x0306); break;
        case ShapeHorn: appendUtf8(out, 0x031B); break;
    }
    if (l.tone > 0 && l.tone < 6)
        appendUtf8(out, kCombiningTones[l.tone]);
}

std::string encode(const std::vector<Letter>& letters) {
    std::string out;
    out.reserve(letters.size() * 2);
    for (const Letter& l : letters)
        appendLetter(out, l);
    return out;
}

/** Letters without any accent, used to find words quickly: a word with accents becomes the plain letters. */
std::string baseKey(const std::vector<Letter>& letters) {
    std::string key;
    key.reserve(letters.size());
    for (const Letter& l : letters)
        appendUtf8(key, l.base);
    return key;
}

/** A letter the user typed matches a letter of a word if it is that letter with fewer accents. */
bool letterMatches(const Letter& typed, const Letter& word) {
    if (typed.base != word.base)
        return false;
    if (typed.shape != ShapeNone && typed.shape != word.shape)
        return false;
    if (typed.tone != 0 && typed.tone != word.tone)
        return false;
    return true;
}

bool sameLetter(const Letter& a, const Letter& b) {
    return a.base == b.base && a.shape == b.shape && a.tone == b.tone;
}

bool matchesPrefix(const std::vector<Letter>& typed, const std::vector<Letter>& word) {
    if (word.size() < typed.size())
        return false;
    for (size_t i = 0; i < typed.size(); i++) {
        if (!letterMatches(typed[i], word[i]))
            return false;
    }
    return true;
}

bool isExactPrefix(const std::vector<Letter>& typed, const std::vector<Letter>& word) {
    if (word.size() < typed.size())
        return false;
    for (size_t i = 0; i < typed.size(); i++) {
        if (!sameLetter(typed[i], word[i]))
            return false;
    }
    return true;
}

/** The letters of a compound word written together, as someone would type it: "thiet ke" -> "thietke" (with accents). */
std::vector<Letter> joinedLetters(const std::string& phrase) {
    std::vector<Letter> letters = decode(phrase);
    letters.erase(std::remove_if(letters.begin(), letters.end(), [](const Letter& l) { return l.base == ' '; }),
                  letters.end());
    return letters;
}

/** Plain words only: letters, not too long. Keeps numbers, URLs and symbols out of the model. */
bool isWordLike(const std::vector<Letter>& letters) {
    if (letters.empty() || letters.size() > 24)
        return false;
    for (const Letter& l : letters) {
        if (l.base < 128) {
            if (l.base < 'a' || l.base > 'z')
                return false;
        } else if (l.base < 0xC0 || l.base >= 0x2000) {
            return false;
        }
    }
    return true;
}

/*==========================================================================================================*/
// Counts
/*==========================================================================================================*/

const double kCompoundBoost = 3.0;     //with the ratio below: a compound goes first when it is at least half of the use of its first syllable
const size_t kCompoundMinLetters = 3;  //typing less than this says too little about a compound
const double kBigramConfidence = 4.0;  //counts needed before a bigram is trusted as much as the unigram
const double kTrigramConfidence = 4.0;
const uint32_t kMaxCount = 0x3FFFFFFF;

void addCount(uint32_t& slot, uint32_t c) {
    slot = (slot > kMaxCount - c) ? kMaxCount : slot + c;
}

} // namespace

/*==========================================================================================================*/
// Model: how often words, word pairs and word triples were seen
/*==========================================================================================================*/

class Model {
public:
    typedef std::unordered_map<std::string, uint32_t> Counts;

    Counts uni;
    std::unordered_map<std::string, Counts> bi;  //previous word -> next word -> count
    std::unordered_map<std::string, Counts> tri; //"previous2 previous1" -> next word -> count
    std::unordered_map<std::string, uint64_t> biTotal;
    std::unordered_map<std::string, uint64_t> triTotal;
    std::unordered_map<std::string, uint32_t> phr; //compound words, syllables separated by a space
    uint64_t uniTotal = 0;

    void clear() {
        phr.clear();
        phraseIndex_.clear();
        phraseDirty_ = false;
        uni.clear();
        bi.clear();
        tri.clear();
        biTotal.clear();
        triTotal.clear();
        uniTotal = 0;
        index_.clear();
        indexDirty_ = false;
    }

    void addUni(const std::string& w, uint32_t c) {
        auto r = uni.emplace(w, 0);
        if (r.second)
            indexDirty_ = true;
        addCount(r.first->second, c);
        uniTotal += c;
    }

    void ensureUni(const std::string& w) {
        if (uni.find(w) == uni.end())
            addUni(w, 1);
    }

    void addPhrase(const std::string& phrase, uint32_t c) {
        auto r = phr.emplace(phrase, 0);
        if (r.second)
            phraseDirty_ = true;
        addCount(r.first->second, c);
    }

    /** How much of the use of the first syllable is this compound: 0 to 1, a half when they are used equally often. */
    double phraseRatio(const std::string& phrase, const std::string& first) const {
        auto p = phr.find(phrase);
        if (p == phr.end())
            return 0;
        auto u = uni.find(first);
        double alone = (u == uni.end()) ? 1.0 : (double)u->second;
        return (double)p->second / ((double)p->second + alone);
    }

    /** Compounds that start with what was typed, however many syllables it spans: "thietke" finds "thiet ke" (accented). */
    void collectPhrases(const std::vector<Letter>& typed, const std::string& key, std::vector<std::string>& out) const {
        if (phraseDirty_)
            rebuildPhraseIndex();
        auto it = std::lower_bound(phraseIndex_.begin(), phraseIndex_.end(), std::make_pair(key, std::string()));
        for (; it != phraseIndex_.end() && it->first.compare(0, key.size(), key) == 0; ++it) {
            if (matchesPrefix(typed, joinedLetters(it->second)))
                out.push_back(it->second);
        }
    }

    void addBi(const std::string& a, const std::string& w, uint32_t c) {
        addCount(bi[a][w], c);
        biTotal[a] += c;
    }

    void addTri(const std::string& a, const std::string& b, const std::string& w, uint32_t c) {
        std::string k = a + ' ' + b;
        addCount(tri[k][w], c);
        triTotal[k] += c;
    }

    /**
     * Probability of w after c2 c1 (either may be empty). Trigram, bigram and unigram are blended, each
     * trusted in proportion to how much evidence there is for the context.
     */
    double prob(const std::string& c2, const std::string& c1, const std::string& w) const {
        double p = 0;
        if (uniTotal > 0) {
            auto it = uni.find(w);
            if (it != uni.end())
                p = (double)it->second / (double)uniTotal;
        }
        if (!c1.empty()) {
            auto total = biTotal.find(c1);
            if (total != biTotal.end() && total->second > 0) {
                double t = (double)total->second;
                double c = countOf(bi, c1, w);
                double lambda = t / (t + kBigramConfidence);
                p = lambda * (c / t) + (1.0 - lambda) * p;
            }
            if (!c2.empty()) {
                std::string k = c2 + ' ' + c1;
                auto total3 = triTotal.find(k);
                if (total3 != triTotal.end() && total3->second > 0) {
                    double t = (double)total3->second;
                    double c = countOf(tri, k, w);
                    double lambda = t / (t + kTrigramConfidence);
                    p = lambda * (c / t) + (1.0 - lambda) * p;
                }
            }
        }
        return p;
    }

    void collectPrefix(const std::vector<Letter>& typed, const std::string& key, std::vector<std::string>& out) const {
        if (indexDirty_)
            rebuildIndex();
        auto it = std::lower_bound(index_.begin(), index_.end(), std::make_pair(key, std::string()));
        for (; it != index_.end() && it->first.compare(0, key.size(), key) == 0; ++it) {
            if (matchesPrefix(typed, decode(it->second)))
                out.push_back(it->second);
        }
    }

    void collectNext(const std::string& c2, const std::string& c1, std::vector<std::string>& out) const {
        if (c1.empty())
            return;
        auto b = bi.find(c1);
        if (b != bi.end()) {
            for (const auto& kv : b->second)
                out.push_back(kv.first);
        }
        if (!c2.empty()) {
            auto t = tri.find(c2 + ' ' + c1);
            if (t != tri.end()) {
                for (const auto& kv : t->second)
                    out.push_back(kv.first);
            }
        }
    }

    void rebuildIndex() const {
        index_.clear();
        index_.reserve(uni.size());
        for (const auto& kv : uni)
            index_.emplace_back(baseKey(decode(kv.first)), kv.first);
        std::sort(index_.begin(), index_.end());
        indexDirty_ = false;
    }

    void rebuildPhraseIndex() const {
        phraseIndex_.clear();
        phraseIndex_.reserve(phr.size());
        for (const auto& kv : phr)
            phraseIndex_.emplace_back(baseKey(joinedLetters(kv.first)), kv.first);
        std::sort(phraseIndex_.begin(), phraseIndex_.end());
        phraseDirty_ = false;
    }

    void prepare() const {
        if (indexDirty_)
            rebuildIndex();
        if (phraseDirty_)
            rebuildPhraseIndex();
    }

    void write(std::ostream& out) const {
        std::vector<std::pair<std::string, uint32_t>> lines;
        for (const auto& kv : uni)
            lines.emplace_back(kv.first, kv.second);
        flush(out, lines);
        for (const auto& a : bi) {
            for (const auto& kv : a.second)
                lines.emplace_back(a.first + ' ' + kv.first, kv.second);
        }
        flush(out, lines);
        for (const auto& a : tri) {
            for (const auto& kv : a.second)
                lines.emplace_back(a.first + ' ' + kv.first, kv.second);
        }
        flush(out, lines);
        for (const auto& kv : phr) {
            std::string joined = kv.first;
            std::replace(joined.begin(), joined.end(), ' ', '_');
            lines.emplace_back(joined, kv.second);
        }
        flush(out, lines);
    }

private:
    mutable bool phraseDirty_ = true;
    mutable std::vector<std::pair<std::string, std::string>> phraseIndex_; //accent-free key without spaces, compound; sorted
    mutable bool indexDirty_ = true;
    mutable std::vector<std::pair<std::string, std::string>> index_; //accent-free key, word; sorted

    static double countOf(const std::unordered_map<std::string, Counts>& map, const std::string& k, const std::string& w) {
        auto a = map.find(k);
        if (a == map.end())
            return 0;
        auto it = a->second.find(w);
        return it == a->second.end() ? 0 : (double)it->second;
    }

    static void flush(std::ostream& out, std::vector<std::pair<std::string, uint32_t>>& lines) {
        std::sort(lines.begin(), lines.end());
        for (const auto& l : lines)
            out << l.first << '\t' << l.second << '\n';
        lines.clear();
    }
};

/*==========================================================================================================*/
// Engine
/*==========================================================================================================*/

namespace {

std::vector<std::string> splitWords(const std::string& body) {
    std::vector<std::string> words;
    std::string cur;
    for (char c : body) {
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            if (!cur.empty())
                words.push_back(cur);
            cur.clear();
        } else {
            cur += c;
        }
    }
    if (!cur.empty())
        words.push_back(cur);
    return words;
}

struct ParseMode {
    bool spacedCompounds = false; //after "#!compounds": several words on one line are one compound word
    bool teachNgrams = true;      //false for the learned data, whose word pairs are written out on their own lines
};

std::string joinSyllables(const std::vector<std::string>& syllables) {
    std::string joined;
    for (const std::string& s : syllables)
        joined += (joined.empty() ? "" : " ") + s;
    return joined;
}

/** Returns true if the line held an entry. */
bool parseLine(std::string line, Model& model, const ParseMode& mode) {
    while (!line.empty() && (line.back() == '\r' || line.back() == '\n'))
        line.pop_back();
    size_t start = line.find_first_not_of(" \t");
    if (start == std::string::npos || line[start] == '#')
        return false;

    std::string body = line;
    uint32_t count = 1;
    size_t tab = line.rfind('\t');
    if (tab != std::string::npos) {
        std::string tail = line.substr(tab + 1);
        char* end = nullptr;
        unsigned long long v = strtoull(tail.c_str(), &end, 10);
        if (end != tail.c_str() && *end == '\0') {
            body = line.substr(0, tab);
            count = v < 1 ? 1 : (v > kMaxCount / 4 ? kMaxCount / 4 : (uint32_t)v);
        }
    }

    //every word of the line as its syllables: "xin" is one, "thiet_ke" is two; empty if it is not a plain word
    std::vector<std::vector<std::string>> parts;
    bool hasJoined = false, allPlain = true;
    for (const std::string& token : splitWords(body)) {
        std::vector<std::string> syllables;
        size_t from = 0;
        while (true) {
            size_t underscore = token.find('_', from);
            std::string w = Engine::normalizeWord(token.substr(from, underscore == std::string::npos ? std::string::npos : underscore - from));
            if (!isWordLike(decode(w))) {
                syllables.clear();
                break;
            }
            syllables.push_back(w);
            if (underscore == std::string::npos)
                break;
            from = underscore + 1;
        }
        hasJoined = hasJoined || syllables.size() > 1;
        allPlain = allPlain && syllables.size() == 1;
        parts.push_back(syllables);
    }
    if (parts.empty())
        return false;

    if (parts.size() == 1) {
        if (parts[0].empty())
            return false;
        if (parts[0].size() == 1) { //a word and how often it is used
            model.addUni(parts[0][0], count);
            return true;
        }
    } else if (mode.spacedCompounds && !hasJoined && allPlain) { //the whole line is one compound
        std::vector<std::string> all;
        for (const auto& p : parts)
            all.push_back(p[0]);
        parts.assign(1, all);
    }

    std::string prev1, prev2;
    bool any = false;
    for (const std::vector<std::string>& syllables : parts) {
        if (syllables.empty()) { //a number or symbol cuts the phrase in two
            prev1.clear();
            prev2.clear();
            continue;
        }
        if (syllables.size() > 1) {
            model.addPhrase(joinSyllables(syllables), count);
            any = true;
            if (!mode.teachNgrams) //its pairs are on lines of their own
                continue;
        }
        for (const std::string& w : syllables) {
            model.ensureUni(w);
            if (!prev1.empty()) {
                model.addBi(prev1, w, count);
                if (!prev2.empty())
                    model.addTri(prev2, prev1, w, count);
            }
            prev2 = prev1;
            prev1 = w;
            any = true;
        }
    }
    return any;
}

} // namespace

Engine::Engine() : base_(new Model()), user_(new Model()) {}

Engine::~Engine() {}

int Engine::loadText(const std::string& text, Target target) {
    Model& model = target == Target::Base ? *base_ : *user_;
    ParseMode mode;
    mode.teachNgrams = target == Target::Base;
    int entries = 0;
    size_t pos = 0;
    if (text.compare(0, 3, "\xEF\xBB\xBF") == 0) //byte order mark
        pos = 3;
    while (pos < text.size()) {
        size_t end = text.find('\n', pos);
        if (end == std::string::npos)
            end = text.size();
        std::string line = text.substr(pos, end - pos);
        if (line.compare(0, 2, "#!") == 0) { //switches how the lines below are read
            mode.spacedCompounds = line.compare(0, 11, "#!compounds") == 0;
        } else if (parseLine(line, model, mode)) {
            entries++;
        }
        pos = end + 1;
    }
    model.prepare();
    return entries;
}

void Engine::clear(Target target) {
    (target == Target::Base ? base_ : user_)->clear();
}

size_t Engine::wordCount(Target target) const {
    return (target == Target::Base ? base_ : user_)->uni.size();
}

std::string Engine::serializeUser() {
    std::ostringstream out;
    out << "# VOpenKey: words learned from your typing. Delete this file to forget everything.\n";
    user_->write(out);
    userDirty_ = false;
    return out.str();
}

bool Engine::hasUnsavedLearning() const {
    return userDirty_;
}

void Engine::setFallback(FallbackProvider provider) {
    fallback_ = provider;
}

std::string Engine::foldForSearch(const std::string& utf8) {
    return baseKey(decode(utf8));
}

std::string Engine::normalizeWord(const std::string& utf8) {
    std::vector<Letter> letters = decode(utf8);
    for (Letter& l : letters)
        l.upper = false;
    return encode(letters);
}

void Engine::learn(const std::vector<std::string>& context, const std::string& word) {
    std::string w = normalizeWord(word);
    if (!isWordLike(decode(w)))
        return;
    std::string c1, c2;
    size_t n = context.size();
    if (n >= 1) {
        c1 = normalizeWord(context[n - 1]);
        if (!isWordLike(decode(c1)))
            c1.clear();
    }
    if (n >= 2 && !c1.empty()) {
        c2 = normalizeWord(context[n - 2]);
        if (!isWordLike(decode(c2)))
            c2.clear();
    }
    user_->addUni(w, 1);
    if (!c1.empty()) {
        user_->addBi(c1, w, 1);
        if (!c2.empty())
            user_->addTri(c2, c1, w, 1);
    }
    userDirty_ = true;
}

void Engine::learnCompound(const std::vector<std::string>& words) {
    std::vector<std::string> syllables;
    for (const std::string& w : words) {
        std::string n = normalizeWord(w);
        if (!isWordLike(decode(n)))
            return;
        syllables.push_back(n);
    }
    if (syllables.size() < 2)
        return;
    user_->addPhrase(joinSyllables(syllables), 1);
    userDirty_ = true;
}

/** Gives the candidates the case the user is typing in: "Vi" gives a capital first letter, "VI" all capitals. */
static void followCase(const std::vector<Letter>& typed, std::vector<Candidate>& candidates) {
    bool allUpper = typed.size() >= 2;
    for (const Letter& l : typed)
        allUpper = allUpper && l.upper;
    bool firstUpper = !typed.empty() && typed[0].upper;
    if (!allUpper && !firstUpper)
        return;
    for (Candidate& c : candidates) {
        std::vector<Letter> letters = decode(c.text);
        if (letters.empty())
            continue;
        if (allUpper) {
            for (Letter& l : letters)
                l.upper = true;
        } else {
            letters[0].upper = true;
        }
        c.text = encode(letters);
    }
}

std::vector<Candidate> Engine::suggestCompounds(const std::vector<std::string>& context,
                                                const std::vector<std::string>& inputs,
                                                size_t maxCount) const {
    std::vector<Candidate> result;
    if (maxCount == 0)
        return result;

    std::string c1, c2;
    size_t n = context.size();
    if (n >= 1)
        c1 = normalizeWord(context[n - 1]);
    if (n >= 2)
        c2 = normalizeWord(context[n - 2]);

    std::unordered_set<std::string> seen;
    std::vector<Letter> firstTyped;
    for (const std::string& input : inputs) {
        std::vector<Letter> typed = decode(input);
        if (typed.size() < kCompoundMinLetters || !isWordLike(typed))
            continue;
        if (firstTyped.empty())
            firstTyped = typed;
        std::string key = baseKey(typed);
        std::vector<std::string> found;
        base_->collectPhrases(typed, key, found);
        user_->collectPhrases(typed, key, found);
        for (const std::string& phrase : found) {
            if (!seen.insert(phrase).second)
                continue;
            std::string first = phrase.substr(0, phrase.find(' '));
            double alone = base_->prob(c2, c1, first) + user_->prob(c2, c1, first);
            if (alone < 1e-9)
                alone = 1e-9;
            double ratio = std::max(base_->phraseRatio(phrase, first), user_->phraseRatio(phrase, first));
            double score = kCompoundBoost * alone * ratio;
            if (isExactPrefix(typed, joinedLetters(phrase)))
                score *= 1.25;
            result.push_back({phrase, score});
        }
    }

    size_t k = std::min(maxCount, result.size());
    std::partial_sort(result.begin(), result.begin() + k, result.end(),
                      [](const Candidate& a, const Candidate& b) {
                          if (a.score != b.score)
                              return a.score > b.score;
                          return a.text < b.text;
                      });
    result.resize(k);
    followCase(firstTyped, result);
    return result;
}

std::vector<Candidate> Engine::suggest(const std::vector<std::string>& context,
                                       const std::string& typed,
                                       size_t maxCount) const {
    std::vector<Candidate> scored;
    if (maxCount == 0)
        return scored;

    std::string c1, c2;
    size_t n = context.size();
    if (n >= 1)
        c1 = normalizeWord(context[n - 1]);
    if (n >= 2)
        c2 = normalizeWord(context[n - 2]);

    std::vector<Letter> typedLetters = decode(typed);
    std::string typedLower = normalizeWord(typed);

    std::vector<std::string> words;
    if (typedLetters.empty()) {
        if (c1.empty())
            return scored;
        base_->collectNext(c2, c1, words);
        user_->collectNext(c2, c1, words);
    } else {
        std::string key = baseKey(typedLetters);
        base_->collectPrefix(typedLetters, key, words);
        user_->collectPrefix(typedLetters, key, words);
    }

    std::unordered_set<std::string> seen;
    for (const std::string& w : words) {
        if (!seen.insert(w).second || w == typedLower)
            continue;
        double s = base_->prob(c2, c1, w) + user_->prob(c2, c1, w);
        if (!typedLetters.empty() && isExactPrefix(typedLetters, decode(w)))
            s *= 1.25; //what was typed literally beats what only matches once accents are ignored
        scored.push_back({w, s});
    }

    if (fallback_ && !typedLetters.empty() && scored.size() < maxCount) {
        std::vector<std::string> extra;
        fallback_(typed, extra);
        double s = 1e-9;
        for (const std::string& e : extra) {
            std::string w = normalizeWord(e);
            std::vector<Letter> letters = decode(w);
            if (!isWordLike(letters) || w == typedLower || !matchesPrefix(typedLetters, letters))
                continue;
            if (!seen.insert(w).second)
                continue;
            scored.push_back({w, s});
            s *= 0.9;
        }
    }

    size_t k = std::min(maxCount, scored.size());
    std::partial_sort(scored.begin(), scored.begin() + k, scored.end(),
                      [](const Candidate& a, const Candidate& b) {
                          if (a.score != b.score)
                              return a.score > b.score;
                          if (a.text.size() != b.text.size())
                              return a.text.size() < b.text.size();
                          return a.text < b.text;
                      });
    scored.resize(k);

    followCase(typedLetters, scored);
    return scored;
}

} // namespace vsuggest
