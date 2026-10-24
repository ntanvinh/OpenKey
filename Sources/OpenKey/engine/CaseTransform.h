//
//  CaseTransform.h
//  VOpenKey
//
//  Changes the case of a text: CHU HOA, chu thuong, Viet Hoa Tung Tu, camelCase... The rules (what a word is, where a
//  sentence ends, how a name is made) are here and the same on every platform. What only the operating system knows,
//  the case rules of every script and the accents, comes from a `Unicode` object the platform gives: Windows uses
//  LCMapStringEx and NormalizeString, the tests use CoreFoundation. Text is UTF-16 (std::u16string), ASCII source.
//
#ifndef CaseTransform_h
#define CaseTransform_h

#include <string>
#include <vector>

namespace vcase {

enum class Style {
    Upper,        //XIN CHAO THE GIOI
    Lower,        //xin chao the gioi
    Title,        //Xin Chao The Gioi
    Sentence,     //Xin chao the gioi. Toi la Vinh.
    Camel,        //xinChaoTheGioi
    Pascal,       //XinChaoTheGioi
    Snake,        //xin_chao_the_gioi
    Kebab,        //xin-chao-the-gioi
    Constant,     //XIN_CHAO_THE_GIOI
    StripMarks,   //Xin chao the gioi (the Vietnamese accents taken off)
    Slug          //xin-chao-the-gioi (accents off, for an address)
};

/// What a character is for cutting a text into words.
enum class Kind {
    Separator,
    Lower,
    Upper,
    Digit,
    Other       //a letter with no case (Chinese, Thai...) or a combining mark
};

/// What the platform knows about Unicode.
class Unicode {
public:
    virtual ~Unicode() {}
    /// Full case mapping of the text: "ss" for the German sharp s in upper case, a final sigma in lower case.
    virtual std::u16string toUpper(const std::u16string& text) const = 0;
    virtual std::u16string toLower(const std::u16string& text) const = 0;
    /// Canonical decomposition (accents as separate marks) and composition (back to one character).
    virtual std::u16string decompose(const std::u16string& text) const = 0;
    virtual std::u16string compose(const std::u16string& text) const = 0;
    /// The kind of one code point. A combining mark is Kind::Other.
    virtual Kind kindOf(char32_t codePoint) const = 0;
    /// A combining mark: it belongs to the letter before it.
    virtual bool isMark(char32_t codePoint) const = 0;
};

std::vector<Style> stylesByPopularity();

/// What the style is called on the list, UTF-8: "CHU HOA" (with the accents of Vietnamese) and so on, written the way it works.
std::string nameOfStyle(Style style);

/// The text in that style. A text without letters comes back as it is. The styles that make one name out of the text
/// (camelCase, snake_case...) work on one line at a time and keep the line breaks and the spaces at both ends of a line.
std::u16string apply(const Unicode& unicode, Style style, const std::u16string& text);

struct Offer {
    Style style;
    std::string name;       //UTF-8
    std::u16string text;
};

/// The styles that do something to the text and the text they give, most popular first. A style whose result a more popular
/// one already gives is left out ("hello": Title Case and PascalCase are the same).
std::vector<Offer> offersForText(const Unicode& unicode, const std::u16string& text);

/// UTF-8 <-> UTF-16, for the platforms that keep text in UTF-8.
std::u16string toUtf16(const std::string& utf8);
std::string toUtf8(const std::u16string& utf16);

} // namespace vcase

#endif /* CaseTransform_h */
