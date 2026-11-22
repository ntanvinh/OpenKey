//
//  What the dictionary may read aloud: which headwords are English words to pronounce, and when the language of the dictionary
//  decides. ASCII-only source (the accented words are written as UTF-8 escapes).
//
#include "../WordSpeech.h"
#include <cstdio>
#include <string>
#include <vector>

using namespace vspeech;

static int failures;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define CHECK_EQ(a, b) do { std::string x_ = (a), y_ = (b); if (x_ != y_) { std::printf("FAIL line %d: %s -> \"%s\", wanted \"%s\"\n", __LINE__, #a, x_.c_str(), y_.c_str()); failures++; } } while (0)

static std::vector<std::string> langs(const char* a, const char* b = 0, const char* c = 0) {
    std::vector<std::string> v;
    v.push_back(a);
    if (b) v.push_back(b);
    if (c) v.push_back(c);
    return v;
}

int main() {
    //plain words, as typed or as the dictionary has them
    CHECK_EQ(SpeakableEnglish("hello"), "hello");
    CHECK_EQ(SpeakableEnglish("Windows"), "Windows");
    CHECK_EQ(SpeakableEnglish("  hello  "), "hello");
    CHECK_EQ(SpeakableEnglish("ice   cream"), "ice cream");
    CHECK_EQ(SpeakableEnglish("well-known"), "well-known");
    CHECK_EQ(SpeakableEnglish("don't"), "don't");
    CHECK_EQ(SpeakableEnglish("e.g."), "e.g.");
    CHECK_EQ(SpeakableEnglish("a"), "a");

    //the curly apostrophe of the dictionaries becomes the straight one: "don<U+2019>t"
    CHECK_EQ(SpeakableEnglish("don\xE2\x80\x99t"), "don't");
    CHECK_EQ(SpeakableEnglish("\xE2\x80\x99" "tis"), "");           //it still has to start with a letter

    //not English words: Vietnamese with accents, digits, symbols, Japanese, empty
    CHECK_EQ(SpeakableEnglish("xin ch\xC3\xA0o"), "");
    CHECK_EQ(SpeakableEnglish("caf\xC3\xA9"), "");
    CHECK_EQ(SpeakableEnglish("\xE3\x81\x93\xE3\x82\x93\xE3\x81\xAB\xE3\x81\xA1\xE3\x81\xAF"), "");
    CHECK_EQ(SpeakableEnglish("window10"), "");
    CHECK_EQ(SpeakableEnglish("3d"), "");
    CHECK_EQ(SpeakableEnglish("-ing"), "");
    CHECK_EQ(SpeakableEnglish("'tis"), "");
    CHECK_EQ(SpeakableEnglish("a/b"), "");
    CHECK_EQ(SpeakableEnglish("hello!"), "");
    CHECK_EQ(SpeakableEnglish(""), "");
    CHECK_EQ(SpeakableEnglish("   "), "");

    //the length limit: 64 characters are read, 65 are not
    CHECK_EQ(SpeakableEnglish(std::string(64, 'a')), std::string(64, 'a'));
    CHECK_EQ(SpeakableEnglish(std::string(65, 'a')), "");

    //the codes of the languages
    CHECK(IsEnglishLang("en"));
    CHECK(IsEnglishLang("EN"));
    CHECK(IsEnglishLang("en-US"));
    CHECK(IsEnglishLang("en_GB"));
    CHECK(IsEnglishLang("eng"));
    CHECK(!IsEnglishLang("vi"));
    CHECK(!IsEnglishLang("ja"));
    CHECK(!IsEnglishLang("fr"));
    CHECK(!IsEnglishLang("enx"));
    CHECK(!IsEnglishLang(""));
    CHECK(IsUnknownLang(""));
    CHECK(IsUnknownLang("  "));
    CHECK(!IsUnknownLang("vi"));

    //what to speak: the language of the dictionary decides
    CHECK_EQ(TextToSpeak("hello", langs("en")), "hello");                     //an English-Vietnamese dictionary
    CHECK_EQ(TextToSpeak("hello", langs("en", "en")), "hello");               //and WordNet
    CHECK_EQ(TextToSpeak("hello", langs("vi", "en")), "hello");               //one of them is English
    CHECK_EQ(TextToSpeak("ba", langs("vi")), "");                             //a Vietnamese headword made of ASCII letters
    CHECK_EQ(TextToSpeak("an", langs("vi", "ja")), "");
    CHECK_EQ(TextToSpeak("hello", langs("")), "hello");                       //an imported dictionary without a language
    CHECK_EQ(TextToSpeak("hello", std::vector<std::string>()), "hello");      //nothing known: the letters decide
    CHECK_EQ(TextToSpeak("hello", langs("", "vi")), "");                      //a known language that is not English wins over unknown
    CHECK_EQ(TextToSpeak("xin ch\xC3\xA0o", langs("en")), "");                //an accented headword is never read in English
    CHECK_EQ(TextToSpeak("don\xE2\x80\x99t", langs("en")), "don't");
    CHECK_EQ(TextToSpeak("", langs("en")), "");

    std::printf(failures ? "FAILED: %d\n" : "ALL OK\n", failures);
    return failures ? 1 : 0;
}
