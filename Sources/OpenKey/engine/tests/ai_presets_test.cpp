// Tests of the ready-made conversions of the AI window (portable C++): the reading of the list, what is refused, the request that is
// made of a preset, and the real file of the program (engine/ai/ai-presets.json).
//
//   clang++ -std=c++11 -I.. ai_presets_test.cpp ../AIPresets.cpp ../MiniJson.cpp -o /tmp/ai_presets_test && /tmp/ai_presets_test
#include "AIPresets.h"
#include <cstdio>
#include <fstream>
#include <set>
#include <sstream>

using namespace vpreset;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

static const char* kTemplate = "\"promptTemplate\": \"{instruction} / {text}\"";

static bool parseText(const std::string& text, Presets& out) {
    return parse(text, out);
}

int main() {
    Presets p;
    // a small list: the order is kept, a missing "poem" is false
    CHECK(parseText(std::string("{") + kTemplate + ", \"presets\": [{\"id\":\"a\",\"title\":\"A\",\"instruction\":\"do a\"},"
                    "{\"id\":\"b\",\"title\":\"B\",\"summary\":\"sb\",\"instruction\":\"do b\",\"poem\":true}]}", p));
    CHECK(p.list.size() == 2 && p.list[0].id == "a" && p.list[1].id == "b");
    CHECK(!p.list[0].poem && p.list[1].poem && p.list[0].summary.empty() && p.list[1].summary == "sb");
    CHECK(find(p, "b") == &p.list[1] && find(p, "zz") == NULL);

    // the request: instruction and text put in, the text trimmed
    CHECK(buildPrompt(p, p.list[0], "\n\n  hello \r\n") == "do a / hello");
    CHECK(buildPrompt(p, p.list[1], "") == "do b / ");
    // done in one pass: what looks like a place to fill inside the text, or inside the instruction, is left alone
    CHECK(buildPrompt(p, p.list[0], "{instruction} and {text}") == "do a / {instruction} and {text}");
    Presets tricky;
    CHECK(parseText(std::string("{") + kTemplate + ", \"presets\": [{\"id\":\"t\",\"title\":\"T\",\"instruction\":\"say {text}\"}]}", tricky));
    CHECK(buildPrompt(tricky, tricky.list[0], "x") == "say {text} / x");

    // what is refused, and `out` stays empty
    Presets bad;
    std::string error;
    CHECK(!parse("", bad, &error) && !error.empty());
    CHECK(!parse("[]", bad));
    CHECK(!parse("{\"promptTemplate\": \"{instruction} {text}\"}", bad));                                       // no list
    CHECK(!parse("{\"promptTemplate\": \"{instruction} {text}\", \"presets\": []}", bad));                      // empty list
    CHECK(!parse("{\"promptTemplate\": \"{instruction}\", \"presets\": [{\"id\":\"a\",\"title\":\"A\",\"instruction\":\"x\"}]}", bad));        // no {text}
    CHECK(!parse("{\"promptTemplate\": \"{text}\", \"presets\": [{\"id\":\"a\",\"title\":\"A\",\"instruction\":\"x\"}]}", bad));               // no {instruction}
    CHECK(!parse("{\"promptTemplate\": \"{instruction} {text} {text}\", \"presets\": [{\"id\":\"a\",\"title\":\"A\",\"instruction\":\"x\"}]}", bad));  // twice
    CHECK(!parse(std::string("{") + kTemplate + ", \"presets\": [{\"id\":\"\",\"title\":\"A\",\"instruction\":\"x\"}]}", bad));
    CHECK(!parse(std::string("{") + kTemplate + ", \"presets\": [{\"id\":\"a\",\"title\":\"\",\"instruction\":\"x\"}]}", bad));
    CHECK(!parse(std::string("{") + kTemplate + ", \"presets\": [{\"id\":\"a\",\"title\":\"A\",\"instruction\":\"\"}]}", bad));
    CHECK(!parse(std::string("{") + kTemplate + ", \"presets\": [{\"id\":\"a\",\"title\":\"A\",\"instruction\":\"x\"},{\"id\":\"a\",\"title\":\"B\",\"instruction\":\"y\"}]}", bad));
    CHECK(bad.list.empty() && bad.promptTemplate.empty());

    // the real file of the program
    std::ifstream f("../ai/ai-presets.json", std::ios::binary);
    std::stringstream ss; ss << f.rdbuf();
    Presets real;
    std::string why;
    CHECK(parse(ss.str(), real, &why));
    CHECK(real.list.size() == 14);
    const char* expected[] = {"fix", "polite", "friendly", "humorous", "formal", "romantic", "poetry", "rhyme", "lucBat", "tuTuyet",
                              "short", "longer", "toEnglish", "toVietnamese"};
    for (size_t i = 0; i < real.list.size() && i < 14; i++)
        CHECK(real.list[i].id == expected[i]);
    std::set<std::string> titles;
    for (size_t i = 0; i < real.list.size(); i++) {
        const Preset& preset = real.list[i];
        titles.insert(preset.title);
        CHECK(!preset.summary.empty() && preset.instruction.size() > 20);
        const bool isPoem = preset.id == "poetry" || preset.id == "rhyme" || preset.id == "lucBat" || preset.id == "tuTuyet";
        CHECK(preset.poem == isPoem);
        std::string prompt = buildPrompt(real, preset, "  xin chao  ");
        CHECK(prompt.compare(0, preset.instruction.size(), preset.instruction) == 0);
        CHECK(prompt.size() > 8 && prompt.substr(prompt.size() - 8) == "xin chao");              // the text, trimmed, comes last
        CHECK(prompt.find("{text}") == std::string::npos && prompt.find("{instruction}") == std::string::npos);
    }
    CHECK(titles.size() == real.list.size());
    CHECK(find(real, "lucBat") != NULL && find(real, "lucBat")->instruction.find("2/2/2") != std::string::npos);   // the rules of the form are in it
    CHECK(find(real, "toEnglish") != NULL && find(real, "toEnglish")->instruction.find("D\xE1\xBB\x8B" "ch sang ti\xE1\xBA\xBF" "ng Anh") == 0);

    if (failures == 0)
        printf("ai_presets_test: all passed\n");
    return failures == 0 ? 0 : 1;
}
