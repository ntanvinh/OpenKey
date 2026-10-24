// Tests of the case rules (portable code) with the Unicode data of macOS (CoreFoundation) behind them. The same checks as
// macOS/tests/case_transform_test.m, which tests the Objective-C version of the app.
//
//   clang++ -std=c++11 -I.. case_transform_test.cpp ../CaseTransform.cpp -framework CoreFoundation -o /tmp/case_transform_test && /tmp/case_transform_test
//
// The strings are UTF-8 literals, MSVC needs /utf-8 for this file. (The Windows program gets its Unicode data from
// CaseTransformWindows.cpp, which only a Windows build can test.)
#include "CaseTransform.h"
#include <CoreFoundation/CoreFoundation.h>
#include <cstdio>
#include <ctime>

using vcase::Unicode; using vcase::Kind; using vcase::Offer;
using vcase::apply; using vcase::offersForText; using vcase::nameOfStyle; using vcase::stylesByPopularity;
using vcase::toUtf16; using vcase::toUtf8;
typedef vcase::Style CaseStyle; //"Style" alone clashes with a type of the macOS headers

class AppleUnicode : public Unicode {
public:
    std::u16string toUpper(const std::u16string& t) const override { return map(t, true); }
    std::u16string toLower(const std::u16string& t) const override { return map(t, false); }
    std::u16string decompose(const std::u16string& t) const override { return normalize(t, kCFStringNormalizationFormD); }
    std::u16string compose(const std::u16string& t) const override { return normalize(t, kCFStringNormalizationFormC); }
    Kind kindOf(char32_t c) const override {
        static CFCharacterSetRef upper = makeUpper(), lower = CFCharacterSetGetPredefined(kCFCharacterSetLowercaseLetter),
            digit = CFCharacterSetGetPredefined(kCFCharacterSetDecimalDigit), letter = CFCharacterSetGetPredefined(kCFCharacterSetLetter),
            nonBase = CFCharacterSetGetPredefined(kCFCharacterSetNonBase);
        if (CFCharacterSetIsLongCharacterMember(upper, c)) return Kind::Upper;
        if (CFCharacterSetIsLongCharacterMember(lower, c)) return Kind::Lower;
        if (CFCharacterSetIsLongCharacterMember(digit, c)) return Kind::Digit;
        if (CFCharacterSetIsLongCharacterMember(letter, c) || CFCharacterSetIsLongCharacterMember(nonBase, c)) return Kind::Other;
        return Kind::Separator;
    }
    bool isMark(char32_t c) const override {
        return CFCharacterSetIsLongCharacterMember(CFCharacterSetGetPredefined(kCFCharacterSetNonBase), c);
    }
private:
    static CFCharacterSetRef makeUpper() {
        CFMutableCharacterSetRef set = CFCharacterSetCreateMutableCopy(NULL, CFCharacterSetGetPredefined(kCFCharacterSetUppercaseLetter));
        CFCharacterSetAddCharactersInString(set, CFSTR("ǅǈǋǲ"));
        return set;
    }
    static CFMutableStringRef make(const std::u16string& t) {
        CFMutableStringRef s = CFStringCreateMutable(NULL, 0);
        CFStringAppendCharacters(s, (const UniChar*)t.data(), (CFIndex)t.size());
        return s;
    }
    static std::u16string read(CFStringRef s) {
        std::u16string out((size_t)CFStringGetLength(s), u' ');
        CFStringGetCharacters(s, CFRangeMake(0, CFStringGetLength(s)), (UniChar*)&out[0]);
        return out;
    }
    static std::u16string map(const std::u16string& t, bool upper) {
        CFMutableStringRef s = make(t);
        if (upper) CFStringUppercase(s, NULL); else CFStringLowercase(s, NULL);
        std::u16string out = read(s);
        CFRelease(s);
        return out;
    }
    static std::u16string normalize(const std::u16string& t, CFStringNormalizationForm form) {
        CFMutableStringRef s = make(t);
        CFStringNormalize(s, form);
        std::u16string out = read(s);
        CFRelease(s);
        return out;
    }
};

static AppleUnicode apple;
static int failures = 0;

static std::u16string u(const char* utf8) { return toUtf16(utf8); }
static std::u16string nfd(const char* utf8) { return apple.decompose(u(utf8)); }

static void Check(CaseStyle style, const std::u16string& input, const std::u16string& expected) {
    std::u16string got = apply(apple, style, input);
    if (got != expected) {
        failures++;
        printf("FAIL %s: [%s] -> [%s], expected [%s]\n", nameOfStyle(style).c_str(), toUtf8(input).c_str(), toUtf8(got).c_str(),
               toUtf8(expected).c_str());
    }
}
static void Check(CaseStyle style, const char* input, const char* expected) { Check(style, u(input), u(expected)); }

int main() {
    // Vietnamese, precomposed
    Check(CaseStyle::Upper, "xin chào thế giới", "XIN CHÀO THẾ GIỚI");
    Check(CaseStyle::Lower, "XIN CHÀO THẾ GIỚI Đà Nẵng", "xin chào thế giới đà nẵng");
    Check(CaseStyle::Upper, "đường", "ĐƯỜNG");
    Check(CaseStyle::Title, "xin chào thế giới", "Xin Chào Thế Giới");
    Check(CaseStyle::Title, "XIN CHÀO ĐÀ NẴNG", "Xin Chào Đà Nẵng");
    Check(CaseStyle::Title, "don't stop well-known", "Don't Stop Well-Known");
    Check(CaseStyle::Title, "line one\nline two", "Line One\nLine Two");
    // separate accents (NFD) keep working
    Check(CaseStyle::Upper, nfd("xin chào"), nfd("XIN CHÀO"));
    Check(CaseStyle::Title, nfd("xin chào"), nfd("Xin Chào"));
    Check(CaseStyle::StripMarks, nfd("xin chào"), u("xin chao"));
    // other scripts
    Check(CaseStyle::Upper, "straße", "STRASSE");
    Check(CaseStyle::Upper, "привет мир", "ПРИВЕТ МИР");
    Check(CaseStyle::Lower, "ΟΔΥΣΣΕΥΣ", "οδυσσευς");
    Check(CaseStyle::Title, "привет мир", "Привет Мир");
    Check(CaseStyle::Upper, "日本語 abc", "日本語 ABC");
    Check(CaseStyle::Upper, "😀 ok", "😀 OK");
    Check(CaseStyle::Title, "élan vital ñandú", "Élan Vital Ñandú");
    // sentence case
    Check(CaseStyle::Sentence, "XIN CHÀO. TÔI LÀ VINH! bạn khỏe không? tốt", "Xin chào. Tôi là vinh! Bạn khỏe không? Tốt");
    Check(CaseStyle::Sentence, "giá là 3.14 usd. xem vinh.com ngay", "Giá là 3.14 usd. Xem vinh.com ngay");
    Check(CaseStyle::Sentence, "dòng một\ndòng hai", "Dòng một\nDòng hai");
    Check(CaseStyle::Sentence, "1. đầu tiên. 2. thứ hai", "1. Đầu tiên. 2. Thứ hai");
    Check(CaseStyle::Sentence, "\"đã xong\" rồi", "\"Đã xong\" rồi");
    Check(CaseStyle::Sentence, "  đã xong", "  Đã xong");
    // names
    Check(CaseStyle::Camel, "xin chào thế giới", "xinChàoThếGiới");
    Check(CaseStyle::Pascal, "xin chào thế giới", "XinChàoThếGiới");
    Check(CaseStyle::Snake, "Xin chào thế giới", "xin_chào_thế_giới");
    Check(CaseStyle::Kebab, "Xin chào thế giới", "xin-chào-thế-giới");
    Check(CaseStyle::Constant, "Xin chào thế giới", "XIN_CHÀO_THẾ_GIỚI");
    Check(CaseStyle::Snake, "myVariableName", "my_variable_name");
    Check(CaseStyle::Camel, "my_variable_name", "myVariableName");
    Check(CaseStyle::Kebab, "HTMLParser", "html-parser");
    Check(CaseStyle::Snake, "XMLHttpRequest2Go", "xml_http_request2_go");
    Check(CaseStyle::Pascal, "user-id  number", "UserIdNumber");
    Check(CaseStyle::Constant, "max.retry.count", "MAX_RETRY_COUNT");
    Check(CaseStyle::Snake, "  indented line  ", "  indented_line  ");
    Check(CaseStyle::Snake, "first line\n  second Line\r\nthird", "first_line\n  second_line\r\nthird");
    Check(CaseStyle::Snake, "!!! ???", "!!! ???");
    Check(CaseStyle::Camel, "привет мир", "приветМир");
    Check(CaseStyle::Snake, "ĐàNẵng", "đà_nẵng");
    Check(CaseStyle::Snake, nfd("xin chào"), nfd("xin_chào"));
    // without accents
    Check(CaseStyle::StripMarks, "Xin chào thế giới, Đà Nẵng đẹp quá! Ơ Ư ơ ư", "Xin chao the gioi, Da Nang dep qua! O U o u");
    Check(CaseStyle::StripMarks, "Ångström Łódź Øl café", "Angstrom Lodz Ol cafe");
    Check(CaseStyle::StripMarks, "ไทย हिन्दी", "ไทย हिन्दी");
    Check(CaseStyle::Slug, "Xin chào, Thế giới! Đà Nẵng 2026", "xin-chao-the-gioi-da-nang-2026");
    Check(CaseStyle::Slug, "  iPhone 15 Pro  ", "  iphone-15-pro  ");
    // empty and tiny
    Check(CaseStyle::Upper, "", "");
    Check(CaseStyle::Title, "a", "A");
    Check(CaseStyle::Sentence, "é", "É");

    // what the list offers
    std::vector<Offer> offers = offersForText(apple, u("hello"));
    if (offers.size() != 2 || offers[0].name != nameOfStyle(CaseStyle::Upper) || offers[1].name != nameOfStyle(CaseStyle::Title)) {
        failures++;
        printf("FAIL offers hello (%zu)\n", offers.size());
    }
    offers = offersForText(apple, u("Xin chào thế giới"));
    if (offers.size() != 10 || offers[0].name != "CHỮ HOA") { failures++; printf("FAIL offers count %zu\n", offers.size()); }
    if (!offersForText(apple, u("123")).empty()) { failures++; printf("FAIL offers digits\n"); }

    // a long text must not be slow
    std::u16string big;
    for (int i = 0; i < 2000; i++) big += u("Xin chào thế giới. ");
    clock_t t = clock();
    std::vector<CaseStyle> styles = stylesByPopularity();
    for (size_t i = 0; i < styles.size(); i++) apply(apple, styles[i], big);
    printf("11 styles on %zu characters: %.2f s\n", big.size(), (double)(clock() - t) / CLOCKS_PER_SEC);

    printf(failures == 0 ? "ALL OK\n" : "%d FAILURES\n", failures);
    return failures != 0;
}
