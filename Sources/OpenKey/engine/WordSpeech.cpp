//
//  WordSpeech.cpp
//  VOpenKey
//

#include "WordSpeech.h"

namespace vspeech {

namespace {

const size_t kMaxLength = 64;

bool isLetter(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

bool isSpace(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

char lower(char c) {
    return (c >= 'A' && c <= 'Z') ? (char)(c - 'A' + 'a') : c;
}

}

std::string SpeakableEnglish(const std::string& headword) {
    //the apostrophe of the dictionaries is often U+2019 (E2 80 99): "don’t" is read as "don't"
    std::string text;
    for (size_t i = 0; i < headword.size(); i++) {
        if (i + 2 < headword.size() && (unsigned char)headword[i] == 0xE2 && (unsigned char)headword[i + 1] == 0x80 &&
            (unsigned char)headword[i + 2] == 0x99) {
            text += '\'';
            i += 2;
        } else {
            text += headword[i];
        }
    }

    size_t begin = 0, end = text.size();
    while (begin < end && isSpace(text[begin])) begin++;
    while (end > begin && isSpace(text[end - 1])) end--;
    if (begin == end || end - begin > kMaxLength)
        return "";

    std::string out;
    for (size_t i = begin; i < end; i++) {
        char c = text[i];
        if (isLetter(c)) {
            out += c;
        } else if (isSpace(c)) {
            if (out.empty() || out[out.size() - 1] == ' ')
                continue;       //a run of spaces is one
            out += ' ';
        } else if (c == '-' || c == '\'' || c == '.') {
            if (out.empty())
                return "";      //it starts with a letter
            out += c;
        } else {
            return "";          //a digit, an accented letter, a symbol: not an English word
        }
    }
    return out;
}

bool IsEnglishLang(const std::string& code) {
    std::string c;
    for (size_t i = 0; i < code.size(); i++)
        c += lower(code[i] == '_' ? '-' : code[i]);
    return c == "en" || c == "eng" || c.compare(0, 3, "en-") == 0;
}

bool IsUnknownLang(const std::string& code) {
    for (size_t i = 0; i < code.size(); i++)
        if (!isSpace(code[i]))
            return false;
    return true;
}

std::string TextToSpeak(const std::string& headword, const std::vector<std::string>& sourceLangs) {
    std::string text = SpeakableEnglish(headword);
    if (text.empty())
        return "";
    bool anyKnown = false;
    for (size_t i = 0; i < sourceLangs.size(); i++) {
        if (IsEnglishLang(sourceLangs[i]))
            return text;
        if (!IsUnknownLang(sourceLangs[i]))
            anyKnown = true;
    }
    return anyKnown ? "" : text;
}

}
