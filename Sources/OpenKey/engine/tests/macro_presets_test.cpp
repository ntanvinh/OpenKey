// Tests of the reading of the table of abbreviations (portable C++).
//
//   clang++ -std=c++11 -I.. macro_presets_test.cpp ../MacroPresets.cpp -o /tmp/macro_presets_test && /tmp/macro_presets_test
#include "MacroPresets.h"
#include <cstdio>
#include <fstream>
#include <sstream>

using namespace vmacro;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main() {
    std::vector<Preset> p = parsePresets("\xEF\xBB\xBF;comment\n\nko:kh\xC3\xB4ng\r\n dc : \xC4\x91\xC6\xB0\xE1\xBB\xA3" "c \n;skipped:x\nnocolon\n:nothing\nempty:\nvs:v\xE1\xBB\x9Bi\nko:again\nurl:http://x.vn\n");
    CHECK(p.size() == 4);
    CHECK(p[0].text == "ko" && p[0].content == "kh\xC3\xB4ng");
    CHECK(p[1].text == "dc" && p[1].content == "\xC4\x91\xC6\xB0\xE1\xBB\xA3" "c");
    CHECK(p[2].text == "vs");
    CHECK(p[3].text == "url" && p[3].content == "http://x.vn");        // the first colon separates
    CHECK(parsePresets("").empty());
    CHECK(examples(p, 2) == "ko -> kh\xC3\xB4ng, dc -> \xC4\x91\xC6\xB0\xE1\xBB\xA3" "c");

    // the real file of the program
    std::ifstream f("../dictionaries/vi-macros.txt", std::ios::binary);
    std::stringstream ss; ss << f.rdbuf();
    std::vector<Preset> real = parsePresets(ss.str());
    CHECK(real.size() >= 30);
    for (size_t i = 0; i < real.size(); i++) CHECK(!real[i].text.empty() && !real[i].content.empty());
    CHECK(real[0].text == "ko");

    if (failures == 0)
        printf("macro_presets_test: all passed\n");
    return failures == 0 ? 0 : 1;
}
