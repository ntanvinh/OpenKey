//
//  Does the suggestion bar know a secret is being typed? The same cases as macOS' sensitive_field_test.m, which come from what
//  Accessibility really answered for the login page of the Bravo 10 web app (2026-10-29). ASCII-only source.
//
#include "../SensitiveField.h"
#include "../Suggest.h"
#include <chrono>
#include <cstdio>
#include <string>

static int failures;
#define CHECK(c, m) do { if (!(c)) { std::printf("FAIL: %s\n", m); failures++; } } while (0)

static void Label(const std::string& label, bool secret) {
    std::string message = "name \"" + label + "\" is " + (secret ? "a secret" : "not a secret");
    CHECK(vsuggest::namesASecret(label) == secret, message.c_str());
}

int main() {
    for (const char* label : {"Password", "PASSWORD", "Enter your password", "Confirm password:", "New passwords", "M\xE1\xBA\xAD""t kh\xE1\xBA\xA9""u", "M\xE1\xBA\xAC""T KH\xE1\xBA\xA8""U", "Nh\xE1\xBA\xAD""p m\xE1\xBA\xAD""t kh\xE1\xBA\xA9""u m\xE1\xBB\x9B""i *", "Mat khau", "m\xE1\xBA\xAD""t m\xC3\xA3""", "Passcode", "Passphrase", "M\xC3\xA3"" PIN", "PIN", "OTP", "M\xC3\xA3"" OTP", "M\xC3\xA3"" x\xC3\xA1""c th\xE1\xBB\xB1""c", "M\xC3\xA3"" b\xE1\xBA\xA3""o m\xE1\xBA\xAD""t", "CVV", "Security code", "Verification code", "Secret key", "loginPassword", "\xE5\xAF\x86""\xE7\xA0\x81""", "\xE3\x83\x91""\xE3\x82\xB9""\xE3\x83\xAF""\xE3\x83\xBC""\xE3\x83\x89"""})
        Label(label, true);
    //the same name written as separate marks (NFD)
    Label("Ma\xCC\xA3""\xCC\x82""t kha\xCC\x82""\xCC\x89""u", true);
    for (const char* label : {"T\xC3\xAA""n ng\xC6\xB0""\xE1\xBB\x9D""i d\xC3\xB9""ng", "T\xC3\xAA""n \xC4\x91""\xC4\x83""ng nh\xE1\xBA\xAD""p", "Email", "Search", "T\xC3\xAC""m ki\xE1\xBA\xBF""m", "\xC4\x90""\xE1\xBB\x8B""a ch\xE1\xBB\x89""", "Message", "Ghi ch\xC3\xBA""", "B\xC3\xAC""nh lu\xE1\xBA\xAD""n", "Shipping address", "Spinning speed", "Opinion", "Options", "Hotpot", "Passenger name", "T\xC3\xAA""n m\xE1\xBA\xAD""t", "Ng\xC3\xA0""y sinh", "S\xE1\xBB\x91"" \xC4\x91""i\xE1\xBB\x87""n tho\xE1\xBA\xA1""i", ""})
        Label(label, false);

    //a secret far behind a long text is not looked for, and a long text is answered quickly
    std::string longText;
    for (int i = 0; i < 2000; i++)
        longText += "lorem ipsum ";
    longText += " password";
    auto start = std::chrono::steady_clock::now();
    CHECK(!vsuggest::namesASecret(longText), "a secret far behind a long text is not looked for");
    CHECK(std::chrono::steady_clock::now() - start < std::chrono::milliseconds(50), "a long text is answered quickly");

    std::printf(failures == 0 ? "sensitive_field_test: all passed\n" : "sensitive_field_test: %d FAILED\n", failures);
    return failures == 0 ? 0 : 1;
}
