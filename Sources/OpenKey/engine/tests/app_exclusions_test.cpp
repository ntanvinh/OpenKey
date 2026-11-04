//
//  What a program name in the list of programs without suggestions is, and how the list is kept. ASCII-only source.
//
#include "../AppExclusions.h"
#include <cstdio>
#include <string>
#include <vector>

using namespace vsuggest::appexclusions;

static int failures;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

typedef std::vector<std::string> List;

int main() {
    //a name
    CHECK(normalizeName("cmd.exe") == "cmd.exe");
    CHECK(normalizeName("CMD.EXE") == "cmd.exe");
    CHECK(normalizeName("  WindowsTerminal.exe \t") == "windowsterminal.exe");
    CHECK(normalizeName("notepad") == "notepad.exe");                       //no extension: it is a program
    CHECK(normalizeName("Notepad++") == "notepad++.exe");
    CHECK(normalizeName("\"C:\\Program Files\\PuTTY\\putty.exe\"") == "putty.exe");   //pasted path with quotes
    CHECK(normalizeName("C:\\Windows\\System32\\cmd.exe") == "cmd.exe");
    CHECK(normalizeName("/usr/bin/xterm") == "xterm.exe");
    CHECK(normalizeName("'  x.exe  '") == "x.exe");
    CHECK(normalizeName("my app.exe") == "my app.exe");                     //a space inside is part of a name
    CHECK(normalizeName("t\xC3\xA9st.exe") == "t\xC3\xA9st.exe");           //UTF-8 stays as it is (only ASCII letters are folded)
    CHECK(normalizeName("MIXED.Exe") == "mixed.exe");

    //not names
    CHECK(normalizeName("").empty() && normalizeName("   ").empty() && normalizeName("\"\"").empty());
    CHECK(normalizeName("C:\\folder\\").empty());                           //a folder
    CHECK(normalizeName(".").empty() && normalizeName("..").empty());
    CHECK(normalizeName("a*.exe").empty() && normalizeName("a?.exe").empty() && normalizeName("a|b.exe").empty());
    CHECK(normalizeName("a<b>.exe").empty() && normalizeName("c:x.exe").empty());
    CHECK(normalizeName(std::string("a\0b.exe", 7)).empty() && normalizeName("a\tb\x01.exe").empty());

    //a list: normalised, no repeats, order kept
    List raw;
    raw.push_back("CMD.exe"); raw.push_back("cmd.exe"); raw.push_back(""); raw.push_back("putty"); raw.push_back("C:\\x\\PuTTY.EXE");
    raw.push_back("a?.exe"); raw.push_back("Kitty.exe");
    List clean = normalizeList(raw);
    CHECK(clean.size() == 3 && clean[0] == "cmd.exe" && clean[1] == "putty.exe" && clean[2] == "kitty.exe");
    CHECK(normalizeList(List()).empty());

    //saved and read back
    CHECK(serialize(clean) == "cmd.exe\nputty.exe\nkitty.exe");
    CHECK(serialize(List()).empty());
    List back = parse(serialize(clean));
    CHECK(back == clean);
    CHECK(parse("").empty() && parse("\n\r\n \n").empty());                 //an empty list is kept as empty
    List crlf = parse("a.exe\r\nB.EXE\rc\n\n a.exe ");
    CHECK(crlf.size() == 3 && crlf[0] == "a.exe" && crlf[1] == "b.exe" && crlf[2] == "c.exe");
    CHECK(parse(serialize(parse("x\ny\nx"))) == parse("x\ny"));

    //lookup: the name of the program in front is already lower case
    CHECK(contains(clean, "cmd.exe") && contains(clean, "kitty.exe"));
    CHECK(!contains(clean, "notepad.exe") && !contains(clean, "") && !contains(List(), "cmd.exe"));
    CHECK(!contains(clean, "cmd"));                                         //exact, not a prefix

    std::printf(failures == 0 ? "app_exclusions_test: all passed\n" : "app_exclusions_test: %d FAILED\n", failures);
    return failures == 0 ? 0 : 1;
}
