//
//  CaseTransformWindows.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "CaseTransformWindows.h"
#include <winnls.h>

#pragma comment(lib, "normaliz.lib")

namespace {

using vcase::Kind;

bool isBmpLetter(wchar_t c) {
    WORD type = 0;
    return GetStringTypeW(CT_CTYPE1, &c, 1, &type) && (type & C1_ALPHA);
}

class WindowsUnicode : public vcase::Unicode {
public:
    std::u16string toUpper(const std::u16string& text) const override {
        std::u16string mapped = map(text, LCMAP_UPPERCASE);
        //Windows maps one character to one character: the German sharp s has no capital of its own, it becomes SS
        std::u16string result;
        for (size_t i = 0; i < mapped.size(); i++) {
            if (mapped[i] == 0x00DF)
                result += u"SS";
            else
                result += mapped[i];
        }
        return result;
    }

    std::u16string toLower(const std::u16string& text) const override {
        std::u16string lowered = map(text, LCMAP_LOWERCASE);
        //A capital sigma is a small sigma in the middle of a Greek word and a final sigma at the end of it. Windows has no
        //word context, so the end of a word is found here: a letter before it and none after it.
        if (lowered.size() == text.size()) {
            for (size_t i = 0; i < text.size(); i++) {
                if (text[i] != 0x03A3)
                    continue;
                bool afterLetter = i > 0 && isBmpLetter((wchar_t)text[i - 1]);
                bool beforeLetter = i + 1 < text.size() && isBmpLetter((wchar_t)text[i + 1]);
                if (afterLetter && !beforeLetter)
                    lowered[i] = 0x03C2;
            }
        }
        return lowered;
    }

    std::u16string decompose(const std::u16string& text) const override { return normalize(text, NormalizationD); }
    std::u16string compose(const std::u16string& text) const override { return normalize(text, NormalizationC); }

    Kind kindOf(char32_t codePoint) const override {
        if (codePoint > 0xFFFF)
            return Kind::Separator;
        wchar_t c = (wchar_t)codePoint;
        WORD type1 = 0, type3 = 0;
        GetStringTypeW(CT_CTYPE1, &c, 1, &type1);
        GetStringTypeW(CT_CTYPE3, &c, 1, &type3);
        if (type1 & C1_UPPER) return Kind::Upper;
        if (type1 & C1_LOWER) return Kind::Lower;
        if (type1 & C1_DIGIT) return Kind::Digit;
        if ((type1 & C1_ALPHA) || (type3 & (C3_NONSPACING | C3_DIACRITIC))) return Kind::Other;
        return Kind::Separator;
    }

    bool isMark(char32_t codePoint) const override {
        if (codePoint > 0xFFFF)
            return false;
        wchar_t c = (wchar_t)codePoint;
        WORD type3 = 0;
        return GetStringTypeW(CT_CTYPE3, &c, 1, &type3) && (type3 & C3_NONSPACING);
    }

private:
    static std::u16string map(const std::u16string& text, DWORD flags) {
        if (text.empty())
            return text;
        const wchar_t* source = (const wchar_t*)text.data();
        int length = (int)text.size();
        int needed = LCMapStringEx(LOCALE_NAME_INVARIANT, flags | LCMAP_LINGUISTIC_CASING, source, length, NULL, 0, NULL, NULL, 0);
        if (needed <= 0)
            return text;
        std::wstring out((size_t)needed, L'\0');
        int done = LCMapStringEx(LOCALE_NAME_INVARIANT, flags | LCMAP_LINGUISTIC_CASING, source, length, &out[0], needed, NULL, NULL, 0);
        if (done <= 0)
            return text;
        out.resize((size_t)done);
        return std::u16string(out.begin(), out.end());
    }

    static std::u16string normalize(const std::u16string& text, NORM_FORM form) {
        if (text.empty())
            return text;
        const wchar_t* source = (const wchar_t*)text.data();
        int length = (int)text.size();
        int capacity = NormalizeString(form, source, length, NULL, 0);
        for (int attempt = 0; attempt < 4 && capacity > 0; attempt++) {
            std::wstring out((size_t)capacity, L'\0');
            int done = NormalizeString(form, source, length, &out[0], capacity);
            if (done > 0) {
                out.resize((size_t)done);
                return std::u16string(out.begin(), out.end());
            }
            if (GetLastError() != ERROR_INSUFFICIENT_BUFFER)
                break;
            capacity = -done > capacity ? -done : capacity * 2;
        }
        return text;
    }
};

} // namespace

namespace CaseTransformWindows {

const vcase::Unicode& unicode() {
    static WindowsUnicode instance;
    return instance;
}

std::u16string toU16(const std::wstring& text) {
    return std::u16string(text.begin(), text.end());
}

std::wstring toWide(const std::u16string& text) {
    return std::wstring(text.begin(), text.end());
}

} // namespace CaseTransformWindows
