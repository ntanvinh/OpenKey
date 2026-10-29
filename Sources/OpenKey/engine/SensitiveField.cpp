#include "SensitiveField.h"
#include "Suggest.h"
#include <cstring>

namespace vsuggest {
namespace {

//Written without accents and in lower case: the text is folded the same way. These are long enough not to be part of other
//words, so they count anywhere in the text ("loginPassword", "matkhau").
const char* const kSecretWords[] = {
    "password",
    "passwd",
    "passcode",
    "passphrase",
    "passwort",
    "mot de passe",
    "contrasena",
    "mat khau",
    "matkhau",
    "mat ma",
    "\xD0\xBF""\xD0\xB0""\xD1\x80""\xD0\xBE""\xD0\xBB""\xD1\x8C""",
    "\xE5\xAF\x86""\xE7\xA0\x81""",
    "\xE5\xAF\x86""\xE7\xA2\xBC""",
    "\xE3\x83\x91""\xE3\x82\xB9""\xE3\x83\xAF""\xE3\x83\xBC""\xE3\x83\x89""",
    "\xEB\xB9\x84""\xEB\xB0\x80""\xEB\xB2\x88""\xED\x98\xB8"""
};

//Short or common words ("pin" is in "spinning", "secret" in "secretary"): only as whole words.
const char* const kSecretPhrases[] = {
    "pin",
    "otp",
    "cvv",
    "cvc",
    "2fa",
    "secret",
    "ma xac thuc",
    "ma xac minh",
    "ma bao mat",
    "security code",
    "verification code",
    "one-time code",
    "one time code"
};

//a program may answer with a whole paragraph: the name of a field is at the start
const size_t kMaxBytes = 160;

bool isWordChar(char c) {
    return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
}

bool containsWhole(const std::string& text, const char* phrase) {
    size_t length = std::strlen(phrase);
    for (size_t at = text.find(phrase); at != std::string::npos; at = text.find(phrase, at + 1)) {
        bool before = at == 0 || !isWordChar(text[at - 1]);
        bool after = at + length >= text.size() || !isWordChar(text[at + length]);
        if (before && after)
            return true;
    }
    return false;
}

} // namespace

bool namesASecret(const std::string& utf8) {
    std::string text = utf8;
    if (text.size() > kMaxBytes) {
        size_t cut = kMaxBytes;
        while (cut > 0 && (static_cast<unsigned char>(text[cut]) & 0xC0) == 0x80) //not in the middle of a character
            cut--;
        text.resize(cut);
    }
    std::string folded = Engine::foldForSearch(text);
    for (const char* word : kSecretWords) {
        if (folded.find(word) != std::string::npos)
            return true;
    }
    for (const char* phrase : kSecretPhrases) {
        if (containsWhole(folded, phrase))
            return true;
    }
    return false;
}

} // namespace vsuggest
