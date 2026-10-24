//
//  CaseTransform.cpp
//  VOpenKey
//
#include "CaseTransform.h"

#include <map>
#include <set>

namespace vcase {

typedef std::u16string U16;

namespace {

bool isHigh(char16_t c) { return c >= 0xD800 && c <= 0xDBFF; }
bool isLow(char16_t c) { return c >= 0xDC00 && c <= 0xDFFF; }

char32_t codePointAt(const U16& s, size_t i) {
    if (isHigh(s[i]) && i + 1 < s.size() && isLow(s[i + 1]))
        return 0x10000 + (((char32_t)s[i] - 0xD800) << 10) + ((char32_t)s[i + 1] - 0xDC00);
    return s[i];
}

size_t lengthOfCodePoint(const U16& s, size_t i) {
    return (isHigh(s[i]) && i + 1 < s.size() && isLow(s[i + 1])) ? 2 : 1;
}

bool isWhitespace(char16_t c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 0x0B || c == 0x0C || c == 0x85 || c == 0xA0 || c == 0x1680 ||
           (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000;
}

//a letter with its accents: a code point and the marks after it
std::vector<U16> clusters(const Unicode& unicode, const U16& text) {
    std::vector<U16> result;
    size_t i = 0;
    while (i < text.size()) {
        size_t n = lengthOfCodePoint(text, i);
        U16 cluster = text.substr(i, n);
        i += n;
        while (i < text.size() && unicode.isMark(codePointAt(text, i))) {
            size_t m = lengthOfCodePoint(text, i);
            cluster += text.substr(i, m);
            i += m;
        }
        result.push_back(cluster);
    }
    return result;
}

Kind kindOfCluster(const Unicode& unicode, const U16& cluster) {
    return unicode.kindOf(codePointAt(cluster, 0));
}

bool isLetterKind(Kind k) { return k == Kind::Lower || k == Kind::Upper || k == Kind::Other; }

U16 join(const std::vector<U16>& parts, const U16& glue) {
    U16 result;
    for (size_t i = 0; i < parts.size(); i++) {
        if (i > 0)
            result += glue;
        result += parts[i];
    }
    return result;
}

//The first letter in capitals, the rest in small letters
U16 capitalized(const Unicode& unicode, const U16& word) {
    U16 lowered = unicode.toLower(word);
    std::vector<U16> parts = clusters(unicode, lowered);
    if (parts.empty())
        return lowered;
    U16 result = unicode.toUpper(parts[0]);
    for (size_t i = 1; i < parts.size(); i++)
        result += parts[i];
    return result;
}

//The words of a line as one name sees them: cut at everything that is not a letter or a digit, and, with `splitCamel`,
//inside "myVariableName" and "HTMLParser" (HTML, Parser).
std::vector<U16> wordsOfLine(const Unicode& unicode, const U16& line, bool splitCamel) {
    std::vector<U16> characters = clusters(unicode, line);
    std::vector<Kind> kinds;
    for (size_t i = 0; i < characters.size(); i++)
        kinds.push_back(kindOfCluster(unicode, characters[i]));

    std::vector<U16> words;
    U16 word;
    Kind previous = Kind::Separator;
    for (size_t i = 0; i < characters.size(); i++) {
        Kind kind = kinds[i];
        if (kind == Kind::Separator) {
            if (!word.empty())
                words.push_back(word);
            word.clear();
            previous = Kind::Separator;
            continue;
        }
        if (splitCamel && !word.empty()) {
            Kind next = i + 1 < characters.size() ? kinds[i + 1] : Kind::Separator;
            bool lowerToUpper = (previous == Kind::Lower || previous == Kind::Digit) && kind == Kind::Upper;
            bool acronymEnds = previous == Kind::Upper && kind == Kind::Upper && next == Kind::Lower; //HTMLParser: the P starts a word
            if (lowerToUpper || acronymEnds) {
                words.push_back(word);
                word.clear();
            }
        }
        word += characters[i];
        previous = kind;
    }
    if (!word.empty())
        words.push_back(word);
    return words;
}

//One line to one name: `glue` between the words and `style` for each of them (index 0 is the first word)
U16 nameFromLine(const Unicode& unicode, const U16& line, bool splitCamel, const U16& glue, Style style) {
    //the spaces at both ends stay where they were (indentation, a line break of Windows)
    size_t start = 0, end = line.size();
    while (start < end && isWhitespace(line[start]))
        start++;
    while (end > start && isWhitespace(line[end - 1]))
        end--;
    std::vector<U16> words = wordsOfLine(unicode, line.substr(start, end - start), splitCamel);
    if (words.empty())
        return line;
    std::vector<U16> styled;
    for (size_t i = 0; i < words.size(); i++) {
        switch (style) {
            case Style::Camel: styled.push_back(i == 0 ? unicode.toLower(words[i]) : capitalized(unicode, words[i])); break;
            case Style::Pascal: styled.push_back(capitalized(unicode, words[i])); break;
            case Style::Constant: styled.push_back(unicode.toUpper(words[i])); break;
            default: styled.push_back(unicode.toLower(words[i])); break;
        }
    }
    return line.substr(0, start) + join(styled, glue) + line.substr(end);
}

U16 byLine(const U16& text, const Unicode& unicode, bool splitCamel, const U16& glue, Style style) {
    if (text.find(u'\n') == U16::npos)
        return nameFromLine(unicode, text, splitCamel, glue, style);
    std::vector<U16> lines;
    size_t from = 0;
    while (true) {
        size_t at = text.find(u'\n', from);
        if (at == U16::npos) {
            lines.push_back(nameFromLine(unicode, text.substr(from), splitCamel, glue, style));
            break;
        }
        lines.push_back(nameFromLine(unicode, text.substr(from, at - from), splitCamel, glue, style));
        from = at + 1;
    }
    return join(lines, U16(1, u'\n'));
}

// --- sentence case ------------------------------------------------------------------------------------------------

//All small, then a capital at the start and after the end of a sentence: ! ? ... and a full stop followed by a space (not
//the one in "3.14" or "vinh.com"), and after every line break.
U16 sentenceCase(const Unicode& unicode, const U16& text) {
    std::vector<U16> characters = clusters(unicode, unicode.toLower(text));
    U16 result;
    bool needsCapital = true;
    for (size_t i = 0; i < characters.size(); i++) {
        const U16& character = characters[i];
        Kind kind = kindOfCluster(unicode, character);
        char16_t c = character[0];
        if (needsCapital && isLetterKind(kind)) {
            result += unicode.toUpper(character);
            needsCapital = false;
            continue;
        }
        result += character;
        if (kind == Kind::Digit) {
            needsCapital = false;
        } else if (c == '!' || c == '?' || c == 0x2026 || c == '\n' || c == '\r' || c == 0x3002 || c == 0xFF01 || c == 0xFF1F) {
            needsCapital = true;
        } else if (c == '.') {
            if (i + 1 >= characters.size() || isWhitespace(characters[i + 1][0]))
                needsCapital = true;
        }
    }
    return result;
}

// --- without accents ----------------------------------------------------------------------------------------------

//Letters that have no accent to take off and still have a plain form
const U16* plainLetter(char16_t c) {
    static std::map<char16_t, U16> letters;
    if (letters.empty()) {
        letters[0x0111] = u"d";  letters[0x0110] = u"D";   //d and D with stroke
        letters[0x0142] = u"l";  letters[0x0141] = u"L";
        letters[0x00F8] = u"o";  letters[0x00D8] = u"O";
        letters[0x0127] = u"h";  letters[0x0126] = u"H";
        letters[0x0131] = u"i";
        letters[0x00F0] = u"d";  letters[0x00D0] = u"D";
        letters[0x00DF] = u"ss";
    }
    std::map<char16_t, U16>::const_iterator it = letters.find(c);
    return it == letters.end() ? NULL : &it->second;
}

//Only the accents of Latin letters go: the marks of other scripts (Thai, Hindi...) are part of their letters
bool isLatinBase(char16_t c) {
    return c < 0x250 || (c >= 0x1E00 && c <= 0x1EFF);
}

U16 stripMarks(const Unicode& unicode, const U16& text) {
    U16 result;
    std::vector<U16> characters = clusters(unicode, text);
    for (size_t i = 0; i < characters.size(); i++) {
        const U16& character = characters[i];
        char16_t first = character[0];
        if (!isLatinBase(first) || (character.size() == 1 && first < 0x80)) {
            result += character;
            continue;
        }
        if (character.size() == 1) {
            const U16* plain = plainLetter(first);
            if (plain) {
                result += *plain;
                continue;
            }
        }
        U16 decomposed = unicode.decompose(character);
        U16 kept;
        for (size_t k = 0; k < decomposed.size(); k++) {
            if (decomposed[k] < 0x300 || decomposed[k] > 0x36F)
                kept += decomposed[k];
        }
        U16 base = unicode.compose(kept);
        if (base.size() == 1 && plainLetter(base[0]))
            result += *plainLetter(base[0]);
        else
            result += base;
    }
    return result;
}

// --- title case ---------------------------------------------------------------------------------------------------

//Cuts a text into the words a person sees: letters, digits and marks, and an apostrophe, a full stop or a comma between
//two of them ("don't", "vinh.com", "3.14"). A hyphen cuts ("well-known" is two words).
U16 titleCase(const Unicode& unicode, const U16& text) {
    std::vector<U16> characters = clusters(unicode, text);
    std::vector<Kind> kinds;
    for (size_t i = 0; i < characters.size(); i++)
        kinds.push_back(kindOfCluster(unicode, characters[i]));

    U16 result;
    size_t i = 0;
    while (i < characters.size()) {
        if (kinds[i] == Kind::Separator) {
            result += characters[i];
            i++;
            continue;
        }
        U16 word;
        while (i < characters.size()) {
            if (kinds[i] != Kind::Separator) {
                word += characters[i];
                i++;
                continue;
            }
            char16_t c = characters[i][0];
            bool joiner = (c == '\'' || c == 0x2019 || c == '.' || c == ',') && i + 1 < characters.size() && !word.empty() &&
                          kinds[i + 1] != Kind::Separator;
            if (joiner && (c == '.' || c == ',')) {
                //a full stop or comma joins two letters or two digits, not a letter and a digit
                Kind before = kindOfCluster(unicode, characters[i - 1]);
                Kind after = kinds[i + 1];
                bool digits = before == Kind::Digit && after == Kind::Digit;
                bool letters = isLetterKind(before) && isLetterKind(after) && c == '.';
                joiner = digits || letters;
            }
            if (!joiner)
                break;
            word += characters[i];
            i++;
        }
        result += capitalized(unicode, word);
    }
    return result;
}

} // namespace

std::vector<Style> stylesByPopularity() {
    static const Style styles[] = {Style::Upper, Style::Lower, Style::Title, Style::Sentence, Style::Camel, Style::Pascal,
                                   Style::Snake, Style::Kebab, Style::Constant, Style::StripMarks, Style::Slug};
    return std::vector<Style>(styles, styles + sizeof(styles) / sizeof(styles[0]));
}

std::string nameOfStyle(Style style) {
    switch (style) {
        case Style::Upper: return "CH\xE1\xBB\xAE HOA";
        case Style::Lower: return "ch\xE1\xBB\xAF th\xC6\xB0\xE1\xBB\x9Dng";
        case Style::Title: return "Vi\xE1\xBA\xBF" "t Hoa T\xE1\xBB\xABng T\xE1\xBB\xAB";
        case Style::Sentence: return "Vi\xE1\xBA\xBF" "t hoa \xC4\x91\xE1\xBA\xA7u c\xC3\xA2u";
        case Style::Camel: return "camelCase";
        case Style::Pascal: return "PascalCase";
        case Style::Snake: return "snake_case";
        case Style::Kebab: return "kebab-case";
        case Style::Constant: return "CONSTANT_CASE";
        case Style::StripMarks: return "B\xE1\xBB\x8F" " d\xE1\xBA\xA5u ti\xE1\xBA\xBF" "ng Vi\xE1\xBB\x87t";
        case Style::Slug: return "\xC4\x90\xC6\xB0\xE1\xBB\x9Dng d\xE1\xBA\xABn (b\xE1\xBB\x8F d\xE1\xBA\xA5u)";
    }
    return "";
}

U16 apply(const Unicode& unicode, Style style, const U16& text) {
    if (text.empty())
        return text;
    switch (style) {
        case Style::Upper: return unicode.toUpper(text);
        case Style::Lower: return unicode.toLower(text);
        case Style::Title: return titleCase(unicode, text);
        case Style::Sentence: return sentenceCase(unicode, text);
        case Style::StripMarks: return stripMarks(unicode, text);
        case Style::Camel: return byLine(text, unicode, true, U16(), Style::Camel);
        case Style::Pascal: return byLine(text, unicode, true, U16(), Style::Pascal);
        case Style::Snake: return byLine(text, unicode, true, U16(1, u'_'), Style::Snake);
        case Style::Kebab: return byLine(text, unicode, true, U16(1, u'-'), Style::Kebab);
        case Style::Constant: return byLine(text, unicode, true, U16(1, u'_'), Style::Constant);
        case Style::Slug:
            //an address is made of the words of a title: "iPhone" stays one word here
            return byLine(stripMarks(unicode, text), unicode, false, U16(1, u'-'), Style::Kebab);
    }
    return text;
}

std::vector<Offer> offersForText(const Unicode& unicode, const U16& text) {
    std::vector<Offer> offers;
    std::set<U16> seen;
    seen.insert(text);
    std::vector<Style> styles = stylesByPopularity();
    for (size_t i = 0; i < styles.size(); i++) {
        U16 result = apply(unicode, styles[i], text);
        if (!seen.insert(result).second)
            continue;
        Offer offer;
        offer.style = styles[i];
        offer.name = nameOfStyle(styles[i]);
        offer.text = result;
        offers.push_back(offer);
    }
    return offers;
}

U16 toUtf16(const std::string& s) {
    U16 out;
    size_t i = 0;
    while (i < s.size()) {
        unsigned char c = (unsigned char)s[i];
        char32_t cp;
        size_t n;
        if (c < 0x80) { cp = c; n = 1; }
        else if ((c >> 5) == 6) { cp = c & 0x1F; n = 2; }
        else if ((c >> 4) == 14) { cp = c & 0x0F; n = 3; }
        else if ((c >> 3) == 30) { cp = c & 0x07; n = 4; }
        else { out += (char16_t)0xFFFD; i++; continue; }
        if (i + n > s.size()) { out += (char16_t)0xFFFD; break; }
        bool ok = true;
        for (size_t k = 1; k < n; k++) {
            unsigned char d = (unsigned char)s[i + k];
            if ((d >> 6) != 2) { ok = false; break; }
            cp = (cp << 6) | (d & 0x3F);
        }
        if (!ok) { out += (char16_t)0xFFFD; i++; continue; }
        i += n;
        if (cp >= 0x10000) {
            cp -= 0x10000;
            out += (char16_t)(0xD800 + (cp >> 10));
            out += (char16_t)(0xDC00 + (cp & 0x3FF));
        } else {
            out += (char16_t)cp;
        }
    }
    return out;
}

std::string toUtf8(const U16& s) {
    std::string out;
    for (size_t i = 0; i < s.size(); i++) {
        char32_t cp = codePointAt(s, i);
        if (cp >= 0x10000)
            i++;
        if (cp < 0x80) {
            out += (char)cp;
        } else if (cp < 0x800) {
            out += (char)(0xC0 | (cp >> 6));
            out += (char)(0x80 | (cp & 0x3F));
        } else if (cp < 0x10000) {
            out += (char)(0xE0 | (cp >> 12));
            out += (char)(0x80 | ((cp >> 6) & 0x3F));
            out += (char)(0x80 | (cp & 0x3F));
        } else {
            out += (char)(0xF0 | (cp >> 18));
            out += (char)(0x80 | ((cp >> 12) & 0x3F));
            out += (char)(0x80 | ((cp >> 6) & 0x3F));
            out += (char)(0x80 | (cp & 0x3F));
        }
    }
    return out;
}

} // namespace vcase
