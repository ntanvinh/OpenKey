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
    CHECK(real.list.size() == 25);
    // by group: tones, the occasions, poems, length and translation
    const char* expected[] = {"fix", "polite", "friendly", "humorous", "formal", "romantic",
                              "congrats", "work", "boss", "colleague", "friend", "family", "customer", "thanks", "apology", "invite", "condolence",
                              "poetry", "rhyme", "lucBat", "tuTuyet", "short", "longer", "toEnglish", "toVietnamese"};
    for (size_t i = 0; i < real.list.size() && i < 25; i++)
        CHECK(real.list[i].id == expected[i]);
    CHECK(real.groups.size() == 4 && real.groups[0].id == "tone" && real.groups[1].id == "occasion" && real.groups[2].id == "poem" && real.groups[3].id == "length");
    CHECK(inGroup(real, "tone").size() == 6 && inGroup(real, "occasion").size() == 11 && inGroup(real, "poem").size() == 4 && inGroup(real, "length").size() == 4);
    CHECK(inGroup(real, "nope").empty());
    for (size_t g = 0; g < real.groups.size(); g++)
        CHECK(!real.groups[g].title.empty() && !inGroup(real, real.groups[g].id).empty());       // no tab is empty
    CHECK(find(real, "congrats")->group == "occasion" && find(real, "lucBat")->group == "poem" && find(real, "fix")->group == "tone");
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
    // the presets for an occasion write a whole message from a few ideas, and say not to invent ("Khong bia them")
    for (size_t i = 0; i < real.list.size(); i++)
        if (real.list[i].group == "occasion")
            CHECK(real.list[i].instruction.find("Kh\xC3\xB4ng b\xE1\xBB\x8B" "a th\xC3\xAAm") != std::string::npos);
    CHECK(find(real, "lucBat") != NULL && find(real, "lucBat")->instruction.find("2/2/2") != std::string::npos);   // the rules of the form are in it
    CHECK(find(real, "toEnglish") != NULL && find(real, "toEnglish")->instruction.find("D\xE1\xBB\x8B" "ch sang ti\xE1\xBA\xBF" "ng Anh") == 0);


    // --- the sizes of pictures
    CHECK(real.imageGroups.size() == 3 && real.imageGroups[0].id == "social" && real.imageGroups[1].id == "icon" && real.imageGroups[2].id == "card");
    CHECK(real.imageSizes.size() == 18);
    std::set<std::string> sizeIds, labels;
    for (size_t i = 0; i < real.imageSizes.size(); i++) {
        const ImageSize& size = real.imageSizes[i];
        sizeIds.insert(size.id);
        labels.insert(imageSizeLabel(size));
        CHECK(!size.title.empty() && !size.summary.empty() && !size.ratio.empty() && size.hint.size() > 20);
        CHECK(size.width >= 256 && size.width <= 2560 && size.height >= 256 && size.height <= 2560);   // what a model can be asked for
        bool listed = false;
        for (size_t g = 0; g < real.imageGroups.size(); g++)
            listed |= real.imageGroups[g].id == size.group;
        CHECK(listed);
        // the picture is cut to this size: from a canvas of the model, never more than 2x its smaller side, so it is not blown up much
        int x, y, w, h;
        CHECK(coverCrop(1536, 1024, size.width, size.height, x, y, w, h) && w >= 1 && h >= 1 && x >= 0 && y >= 0 && x + w <= 1536 && y + h <= 1024);
        long long off = (long long)w * size.height - (long long)h * size.width;                     // 0 when the proportions are exactly those of the size
        if (off < 0) off = -off;
        CHECK(off <= ((size.width > size.height ? size.width : size.height) + 1) / 2);              // never more than half a pixel off
    }
    CHECK(sizeIds.size() == real.imageSizes.size() && labels.size() == real.imageSizes.size());
    const ImageSize* square = findImageSize(real, "squarePost");
    CHECK(square != NULL && square->width == 1080 && square->height == 1080 && square->ratio == "1:1");
    const ImageSize* thumb = findImageSize(real, "youtubeThumbnail");
    CHECK(thumb != NULL && thumb->width == 1280 && thumb->height == 720);
    const ImageSize* story = findImageSize(real, "story");
    CHECK(story != NULL && story->width == 1080 && story->height == 1920);
    CHECK(findImageSize(real, "appIcon") != NULL && findImageSize(real, "cardPortrait") != NULL && findImageSize(real, "nope") == NULL);
    CHECK(imageSizeLabel(*square).find(" (1080\xC3\x97" "1080)") != std::string::npos);

    // the request for a picture: the description, then the canvas; no size = the description alone
    CHECK(buildImageRequest(real, NULL, "\n  a cat \n") == "a cat");
    std::string request = buildImageRequest(real, story, "  a cat on a roof \n");
    CHECK(request.compare(0, 21, "a cat on a roof\n\nCanv") == 0);
    CHECK(request.find("1080 x 1920 px") != std::string::npos && request.find("9:16") != std::string::npos && request.find(story->hint) != std::string::npos);
    CHECK(request.find("{width}") == std::string::npos && request.find("{height}") == std::string::npos &&
          request.find("{ratio}") == std::string::npos && request.find("{hint}") == std::string::npos);
    // done in one pass: a place to fill inside the description is left alone
    CHECK(buildImageRequest(real, story, "{width}").compare(0, 7, "{width}") == 0);

    // cutting to a size: the part that is kept has the proportions of the size, is centred, and is as large as can be
    int cx, cy, cw, ch;
    CHECK(coverCrop(1536, 1024, 1080, 1080, cx, cy, cw, ch) && cx == 256 && cy == 0 && cw == 1024 && ch == 1024);      // a wide picture to a square: the sides go
    CHECK(coverCrop(1024, 1536, 1080, 1080, cx, cy, cw, ch) && cx == 0 && cy == 256 && cw == 1024 && ch == 1024);      // a tall picture to a square: the top and bottom go
    CHECK(coverCrop(1024, 1024, 1584, 396, cx, cy, cw, ch) && cx == 0 && cy == 384 && cw == 1024 && ch == 256);        // 4:1 banner from a square
    CHECK(coverCrop(1024, 1536, 1000, 1500, cx, cy, cw, ch) && cx == 0 && cy == 0 && cw == 1024 && ch == 1536);        // same proportions (2:3): nothing is cut
    CHECK(coverCrop(1000, 1000, 1000, 1000, cx, cy, cw, ch) && cw == 1000 && ch == 1000);
    CHECK(!coverCrop(0, 10, 10, 10, cx, cy, cw, ch) && !coverCrop(10, 10, 10, 0, cx, cy, cw, ch));

    // what is refused in the sizes
    Presets sizeBad;
    const std::string base = std::string("{") + kTemplate + ", \"presets\": [{\"id\":\"a\",\"title\":\"A\",\"instruction\":\"x\"}], ";
    const std::string note = "\"imageNote\": \"{width} {height} {ratio} {hint}\", ";
    const std::string one = "{\"id\":\"s\",\"title\":\"S\",\"width\":100,\"height\":200,\"ratio\":\"1:2\",\"hint\":\"h\"}";
    CHECK(parse(base + note + "\"imageSizes\": [" + one + "]}", sizeBad) && sizeBad.imageSizes.size() == 1 && sizeBad.imageSizes[0].height == 200);
    CHECK(!parse(base + "\"imageSizes\": [" + one + "]}", sizeBad));                                                   // no note
    CHECK(!parse(base + "\"imageNote\": \"{width} {height} {ratio}\", \"imageSizes\": [" + one + "]}", sizeBad));      // note without {hint}
    CHECK(!parse(base + note + "\"imageSizes\": [{\"id\":\"s\",\"title\":\"S\",\"width\":0,\"height\":200,\"ratio\":\"r\"}]}", sizeBad));    // a side of 0
    CHECK(!parse(base + note + "\"imageSizes\": [{\"id\":\"s\",\"title\":\"S\",\"width\":100,\"height\":9000,\"ratio\":\"r\"}]}", sizeBad));  // too large
    CHECK(!parse(base + note + "\"imageSizes\": [" + one + "," + one + "]}", sizeBad));                                // an id twice
    CHECK(!parse(base + note + "\"imageGroups\": [{\"id\":\"g\",\"title\":\"G\"}], \"imageSizes\": [" + one + "]}", sizeBad));   // group not listed
    CHECK(!parse(std::string("{") + kTemplate + ", \"groups\": [{\"id\":\"g\",\"title\":\"G\"}], \"presets\": [{\"id\":\"a\",\"group\":\"h\",\"title\":\"A\",\"instruction\":\"x\"}]}", sizeBad));
    CHECK(sizeBad.imageSizes.empty());

    if (failures == 0)
        printf("ai_presets_test: all passed\n");
    return failures == 0 ? 0 : 1;
}
