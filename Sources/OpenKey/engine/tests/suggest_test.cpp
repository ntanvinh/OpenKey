// Tests of the portable suggestion engine and session (no platform code involved).
//
//   clang++ -std=c++11 -I.. suggest_test.cpp ../Suggest.cpp ../SuggestSession.cpp -o /tmp/suggest_test
//   /tmp/suggest_test ../dictionaries/vi-base.txt       (the dictionary argument is optional)
//
// The strings are UTF-8 literals, MSVC needs /utf-8 for this file.
#include "SuggestSession.h"
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <iostream>
using namespace vsuggest;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

static std::string join(const std::vector<Candidate>& c) {
    std::string s;
    for (size_t i = 0; i < c.size(); i++) { if (i) s += " | "; s += c[i].text; }
    return s;
}
static std::string top(const std::vector<Candidate>& c) { return c.empty() ? "" : c[0].text; }

struct FakeHost : Host {
    std::vector<Candidate> shown; std::string typed; bool visible = false; int shows = 0, hides = 0;
    void showCandidates(const std::vector<Candidate>& c, const std::string& t) override { shown = c; typed = t; visible = true; shows++; }
    void hideCandidates() override { visible = false; hides++; }
};

// dictionary written with real accents, as users will write it
static const char* kDict =
    "# test dictionary\n"
    "h\xE1\xBB\x8D" "c\t300\n"            // học
    "h\xC3\xB3" "a\t100\n"                // hóa
    "h\xE1\xBB\x99" "c\t20\n"             // hộc
    "h\xC3\xB4" "m\t50\n"                 // hôm
    "xin\t500\n"
    "ch\xC3\xA0o\t400\n"                  // chào
    "ch\xE1\xBA\xBF\t10\n"                // chế
    "c\xC3\xA1" "c\t900\n"                // các
    "b\xE1\xBA\xA1n\t800\n"               // bạn
    "xin ch\xC3\xA0o\t3000\n"             // xin chào
    "xin ch\xC3\xA0o c\xC3\xA1" "c b\xE1\xBA\xA1n\t200\n"  // xin chào các bạn
    "xin l\xE1\xBB\x97i\t100\n"           // xin lỗi
    "\xC4\x91\xE1\xBB\x83\t70\n"          // để
    "\xC4\x91\xC3\xA3\t90\n"              // đã
    "\xC4\x91\xE1\xBA\xA1i\t60\n"         // đại
    "Vi\xE1\xBB\x87t\t400\n"              // Việt (capitalised in the file)
    "vi\xE1\xBA\xBFt\t300\n"              // viết
    "vi\xE1\xBB\x87n\t100\n";             // viện

int main(int argc, char** argv) {
    // ---- 1. precomposed vs combining input are the same word
    {
        Engine e;
        // "hoc" with combining dot below + circumflex? use: o + horn? keep simple: a + circumflex + acute
        std::string composed = "\xE1\xBA\xA5";            // ấ
        std::string combining = "a\xCC\x82\xCC\x81";      // a + circumflex + acute
        CHECK(Engine::normalizeWord(combining) == composed);
        CHECK(Engine::normalizeWord("\xE1\xBA\xA4") == composed);  // Ấ lowercases
        CHECK(Engine::normalizeWord("\xC4\x90") == "\xC4\x91");    // Đ -> đ
        CHECK(Engine::normalizeWord("HELLO") == "hello");
    }
    // ---- 2. tone-insensitive prefix completion
    Engine eng;
    CHECK(eng.loadText(kDict) == 18);
    {
        auto c = eng.suggest({}, "hoc", 5);
        printf("hoc -> %s\n", join(c).c_str());
        CHECK(c.size() == 2);                       // học, hộc (hóa and hôm do not continue with "c")
        CHECK(top(c) == "h\xE1\xBB\x8D" "c");        // học first (most frequent)
    }
    {
        auto c = eng.suggest({}, "h\xC3\xB4", 5);   // typed "hô": only words with ô
        printf("hô -> %s\n", join(c).c_str());
        CHECK(top(c) == "h\xC3\xB4" "m");
        CHECK(c.size() == 2);                       // hôm, hộc: "ô" without a tone also finds "ộ"
    }
    {
        auto c = eng.suggest({}, "h\xE1\xBB\x8D", 5);  // typed "họ": exact tone required
        printf("họ -> %s\n", join(c).c_str());
        CHECK(c.size() == 2);                          // học, hộc: a tone is fixed but the vowel shape is not
    }
    {
        auto c = eng.suggest({}, "d", 5);              // d also matches đ
        printf("d -> %s\n", join(c).c_str());
        CHECK(c.size() == 3);
    }
    {
        auto c = eng.suggest({}, "\xC4\x91", 5);       // typed "đ": only đ words
        CHECK(c.size() == 3);
    }
    {
        auto c = eng.suggest({}, "Vi", 5);             // capital follows the typed case
        printf("Vi -> %s\n", join(c).c_str());
        CHECK(c.size() == 3);
        CHECK(top(c) == "Vi\xE1\xBB\x87t");
        auto u = eng.suggest({}, "VI", 5);
        CHECK(top(u) == "VI\xE1\xBB\x86T");
    }
    // ---- 3. context beats frequency
    {
        auto none = eng.suggest({}, "c", 5);           // no context: các (900) beats chào (400)... chế
        printf("c -> %s\n", join(none).c_str());
        CHECK(top(none) == "c\xC3\xA1" "c");
        auto ctx = eng.suggest({"xin"}, "c", 5);       // after "xin": chào wins
        printf("xin + c -> %s\n", join(ctx).c_str());
        CHECK(top(ctx) == "ch\xC3\xA0o");
        auto ctx2 = eng.suggest({"xin", "ch\xC3\xA0o"}, "c", 5);   // after "xin chào": các
        printf("xin chào + c -> %s\n", join(ctx2).c_str());
        CHECK(top(ctx2) == "c\xC3\xA1" "c");
    }
    // ---- 4. next word prediction
    {
        auto n = eng.suggest({"xin"}, "", 5);
        printf("xin + _ -> %s\n", join(n).c_str());
        CHECK(top(n) == "ch\xC3\xA0o");
        CHECK(n.size() == 2);                          // chào, lỗi
        auto n2 = eng.suggest({"xin", "ch\xC3\xA0o"}, "", 5);
        CHECK(top(n2) == "c\xC3\xA1" "c");
        CHECK(eng.suggest({}, "", 5).empty());
    }
    // ---- 5. learning changes the ranking, and survives save/load
    {
        Engine e2;
        e2.loadText(kDict);
        for (int i = 0; i < 30; i++) e2.learn({"xin"}, "l\xE1\xBB\x97i");   // the user always says "xin lỗi"
        auto n = e2.suggest({"xin"}, "", 5);
        printf("learned xin + _ -> %s\n", join(n).c_str());
        CHECK(top(n) == "l\xE1\xBB\x97i");
        CHECK(e2.hasUnsavedLearning());
        std::string saved = e2.serializeUser();
        CHECK(!e2.hasUnsavedLearning());
        Engine e3;
        e3.loadText(kDict);
        e3.loadText(saved, Target::User);
        CHECK(top(e3.suggest({"xin"}, "", 5)) == "l\xE1\xBB\x97i");
        // junk is not learned
        Engine e4;
        e4.learn({}, "12345"); e4.learn({}, "a@b.com"); e4.learn({}, "");
        CHECK(e4.wordCount(Target::User) == 0);
    }
    // ---- 6. fallback provider only fills the gaps, and is checked against the typed letters
    {
        Engine e5;
        e5.loadText("xin\t10\n");
        int calls = 0;
        e5.setFallback([&](const std::string& typed, std::vector<std::string>& out) {
            calls++;
            out.push_back("xinh"); out.push_back("xin"); out.push_back("sai"); out.push_back("x\xE1\xBB\x89n");
            (void)typed;
        });
        auto c = e5.suggest({}, "xi", 5);
        printf("fallback xi -> %s\n", join(c).c_str());
        CHECK(calls == 1);
        CHECK(c.size() == 3);   // xin (dictionary), xinh and xỉn from the fallback; "sai" does not start with "xi"
        CHECK(top(c) == "xin");
    }
    // ---- 7. session behaviour
    {
        Engine e;
        e.loadText(kDict);
        FakeHost host;
        Session s(e, host);
        Settings st; st.enabled = true; s.setSettings(st);

        // disabled -> nothing
        { Settings off; Session s2(e, host); s2.setSettings(off); s2.keyProcessed(KeyKind::Other, "xin"); s2.refresh(); CHECK(!host.visible); }

        // typing "xin" then space: context becomes [xin], next word bar shows chào first
        s.keyProcessed(KeyKind::Other, "x"); s.refresh();
        CHECK(!host.visible);                          // one letter, no context: too little
        s.keyProcessed(KeyKind::Other, "xi"); s.refresh();
        CHECK(host.visible);
        s.keyProcessed(KeyKind::Other, "xin"); s.refresh();
        printf("session xin -> %s\n", join(host.shown).c_str());
        s.keyProcessed(KeyKind::Space, ""); s.refresh();
        CHECK(s.context().size() == 1 && s.context()[0] == "xin");
        CHECK(host.visible && host.typed.empty());
        printf("session xin_ -> %s\n", join(host.shown).c_str());
        CHECK(top(host.shown) == "ch\xC3\xA0o");

        // Tab with the next-word bar: inserts "chào " and keeps predicting
        Acceptance a;
        CHECK(s.accept(0, "", a));
        CHECK(a.text == "ch\xC3\xA0o " && a.eraseCount == 0);
        s.refresh();
        CHECK(host.visible);
        printf("session xin chào_ -> %s\n", join(host.shown).c_str());
        CHECK(top(host.shown) == "c\xC3\xA1" "c");
        CHECK(s.context().size() == 2);

        // type "c", Tab replaces it
        s.keyProcessed(KeyKind::Other, "c"); s.refresh();
        CHECK(host.visible);                           // context exists: one letter is enough
        CHECK(top(host.shown) == "c\xC3\xA1" "c");
        CHECK(!s.accept(0, "cx", a));                  // out of date: word changed since the bar was computed
        CHECK(s.accept(0, "c", a));
        CHECK(a.text == "c\xC3\xA1" "c " && a.eraseCount == 1);
        s.refresh();
        CHECK(top(host.shown) == "b\xE1\xBA\xA1n");    // "xin chào các" -> bạn

        // slot 2 picks the third candidate
        s.keyProcessed(KeyKind::Other, "d"); s.refresh();
        CHECK(host.shown.size() == 3);
        CHECK(s.accept(2, "d", a));
        CHECK(a.eraseCount == 1);

        // a punctuation/Enter breaks the phrase and hides the bar
        s.keyProcessed(KeyKind::Other, ""); s.refresh();
        CHECK(!host.visible);
        CHECK(s.context().empty());

        // delete back into the previous word: it is not context any more
        s.reset();
        s.keyProcessed(KeyKind::Other, "xin"); s.keyProcessed(KeyKind::Space, ""); s.refresh();
        CHECK(s.context().size() == 1);
        s.keyProcessed(KeyKind::Delete, "xin");        // engine restored the word after the space
        CHECK(s.context().empty());

        // reset hides
        s.keyProcessed(KeyKind::Other, "xi"); s.refresh(); CHECK(host.visible);
        s.reset(); CHECK(!host.visible);

        // accepting nothing when no bar
        CHECK(!s.accept(0, "xi", a));

        // learning off: nothing learned
        Engine e6; e6.loadText(kDict); FakeHost h6; Session s6(e6, h6);
        Settings nolearn; nolearn.enabled = true; nolearn.learn = false; s6.setSettings(nolearn);
        s6.keyProcessed(KeyKind::Other, "xin"); s6.keyProcessed(KeyKind::Space, "");
        CHECK(!e6.hasUnsavedLearning());
        // next word off: no bar after a space
        Settings nonext; nonext.enabled = true; nonext.nextWord = false; s6.setSettings(nonext);
        s6.reset(); s6.keyProcessed(KeyKind::Other, "xin"); s6.keyProcessed(KeyKind::Space, ""); s6.refresh();
        CHECK(!h6.visible);
    }

    // ---- 8. compound words: typed together, without spaces or accents
    {
        Engine c;
        c.loadText(
            "#!compounds\n"
            "thiết kế\t900\n"
            "thiết bị\t700\n"
            "thiết lập\t400\n"
            "sinh viên\t700\n"
            "sinh nhật\t500\n"
            "hồ sơ\t300\n"
            "cơ sở dữ liệu\t400\n"
            "#!context\n"
            "sinh\t900\n"
            "thiết\t300\n"
            "kế\t100\n");
        CHECK(c.wordCount(Target::Base) >= 10);   // every syllable of a compound is a word as well

        auto r = c.suggestCompounds({}, {"thietke"}, 5);
        printf("thietke -> %s\n", join(r).c_str());
        CHECK(r.size() == 1 && top(r) == "thiết kế");

        r = c.suggestCompounds({}, {"thiet"}, 5);                 // half typed: the most used first
        printf("thiet -> %s\n", join(r).c_str());
        CHECK(r.size() == 3 && top(r) == "thiết kế");
        r = c.suggestCompounds({}, {"thiếtke"}, 5);               // some accents already typed
        CHECK(r.size() == 1 && top(r) == "thiết kế");
        r = c.suggestCompounds({}, {"thiêtke"}, 5);               // a circumflex without a tone still fits the compound
        CHECK(top(r) == "thiết kế");
        r = c.suggestCompounds({}, {"thiệtke"}, 5);               // a tone that the compound does not have
        CHECK(r.empty());
        r = c.suggestCompounds({}, {"sinhv"}, 5);
        CHECK(top(r) == "sinh viên");
        r = c.suggestCompounds({}, {"cosodulieu"}, 5);            // four syllables
        CHECK(top(r) == "cơ sở dữ liệu");
        r = c.suggestCompounds({}, {"th"}, 5);                    // too little typed
        CHECK(r.empty());
        r = c.suggestCompounds({}, {"Thietke"}, 5);               // case follows the typing
        CHECK(top(r) == "Thiết kế");
        r = c.suggestCompounds({}, {"THIETKE"}, 5);
        CHECK(top(r) == "THIẾT KẾ");
        // Telex turned the keys "hoso" into something else on screen, the keys still find the compound
        r = c.suggestCompounds({}, {"hố", "hoso"}, 5);
        CHECK(top(r) == "hồ sơ");
        r = c.suggestCompounds({}, {"hoso", "hoso"}, 5);
        CHECK(r.size() == 1);
        r = c.suggestCompounds({}, {"thie1ke"}, 5);               // not letters: nothing
        CHECK(r.empty());

    }

    // ---- 9. compounds in the session: ranked with the single words, accepted whole, learned
    {
        Engine e;
        e.loadText(
            "sinh\t900\n"
            "sinh ra\t100\n"
            "sinh hoạt\t40\n"
            "viên\t500\n"
            "#!compounds\n"
            "sinh viên\t700\n"
            "sinh nhật\t100\n");
        FakeHost host;
        Session s(e, host);
        Settings st; st.enabled = true; s.setSettings(st);
        Acceptance a;

        s.keyProcessed(KeyKind::Other, "sinhv", "sinhv"); s.refresh();
        printf("session sinhv -> %s\n", join(host.shown).c_str());
        CHECK(host.visible && host.shown.size() == 1 && top(host.shown) == "sinh viên");
        CHECK(s.accept(0, "sinhv", a));
        CHECK(a.text == "sinh viên " && a.eraseCount == 5);
        CHECK(s.context().size() == 2 && s.context()[0] == "sinh" && s.context()[1] == "viên");
        std::string saved = e.serializeUser();
        CHECK(saved.find("sinh_viên\t1") != std::string::npos);       // the compound itself is remembered
        CHECK(saved.find("sinh viên\t1") != std::string::npos);       // and the pair, as context

        // reloading what was saved does not count the pair twice
        Engine e2;
        e2.loadText(saved, Target::User);
        CHECK(e2.serializeUser() == saved);

        // typed sinh: the compound that is most of its use comes first, the compounds are all offered
        s.reset();
        s.keyProcessed(KeyKind::Other, "sinh", "sinh"); s.refresh();
        printf("session sinh -> %s\n", join(host.shown).c_str());
        CHECK(top(host.shown) == "sinh viên");

        // compounds off: only single words
        Settings nocompound = st; nocompound.compounds = false;
        s.setSettings(nocompound); s.reset();
        s.keyProcessed(KeyKind::Other, "sinhv", "sinhv"); s.refresh();
        CHECK(!host.visible);
        s.setSettings(st);

        // a compound the user accepts again and again climbs
        Engine learner;
        learner.loadText("#!compounds\nsinh viên\t100\nsinh nhật\t100\nsinh hoạt\t100\nsinh\t300\n");
        std::vector<Candidate> before = learner.suggestCompounds({}, {"sinh"}, 5);
        for (int i = 0; i < 20; i++) learner.learnCompound({"sinh", "viên"});
        std::vector<Candidate> after = learner.suggestCompounds({}, {"sinh"}, 5);
        printf("before: %s  after: %s\n", join(before).c_str(), join(after).c_str());
        CHECK(top(before) != "sinh viên");
        CHECK(top(after) == "sinh viên");
    }

    // ---- 9b. abbreviations the user has to confirm ("vn" must stay "vn" at the end of a domain name)
    {
        Engine e; e.loadText(kDict);
        FakeHost host;
        Session s(e, host);
        Settings st; st.enabled = true; s.setSettings(st);
        Acceptance a;
        const std::string vietnam = "Vi\xE1\xBB\x87t Nam";   // Việt Nam

        // one letter is enough for an abbreviation, and it is the first suggestion
        s.keyProcessed(KeyKind::Other, "v", "v", vietnam); s.refresh();
        CHECK(host.visible && top(host.shown) == vietnam);
        s.keyProcessed(KeyKind::Other, "vn", "vn", vietnam); s.refresh();
        CHECK(host.visible && top(host.shown) == vietnam);
        // a bar that was made for another word does not accept
        CHECK(!s.accept(0, "v", a));
        CHECK(s.accept(0, "vn", a));
        CHECK(a.text == vietnam + " " && a.eraseCount == 2);
        CHECK(s.context().empty());                                   // nothing of it was learned
        CHECK(e.serializeUser().find("Vi") == std::string::npos);

        // not choosing it: the next key ends the word, nothing replaces it
        s.reset();
        s.keyProcessed(KeyKind::Other, "vn", "vn", vietnam); s.refresh();
        CHECK(host.visible);
        s.keyProcessed(KeyKind::Space, "", "");
        s.refresh();
        CHECK(!(host.visible && top(host.shown) == vietnam));

        // a word that is no abbreviation: the usual suggestions, and one letter still says too little
        s.reset();
        s.keyProcessed(KeyKind::Other, "h", "h"); s.refresh();
        CHECK(!host.visible);
        s.keyProcessed(KeyKind::Other, "ho", "ho"); s.refresh();
        CHECK(host.visible && top(host.shown) != "");

        // an abbreviation that is also the start of words: the abbreviation first, the words after it
        s.reset();
        s.keyProcessed(KeyKind::Other, "ho", "ho", "hello"); s.refresh();
        CHECK(top(host.shown) == "hello" && host.shown.size() > 1);
        CHECK(s.accept(1, "ho", a) && a.text != "hello ");            // a word of the list still works

        // only the abbreviations: no words, no next word prediction, no learning
        Settings onlyMacros = st; onlyMacros.words = false; s.setSettings(onlyMacros); s.reset();
        s.keyProcessed(KeyKind::Other, "ho", "ho"); s.refresh();
        CHECK(!host.visible);
        s.keyProcessed(KeyKind::Other, "vn", "vn", vietnam); s.refresh();
        CHECK(host.visible && host.shown.size() == 1 && top(host.shown) == vietnam);
        CHECK(s.accept(0, "vn", a) && a.text == vietnam + " ");
        s.refresh();
        CHECK(!host.visible);                                         // no next word prediction after it
    }

    // ---- 10. the shipped dictionary, when it is given
    if (argc > 1) {
        std::ifstream in(argv[1], std::ios::binary);
        std::stringstream buffer; buffer << in.rdbuf();
        Engine real;
        int entries = real.loadText(buffer.str());
        printf("%s: %d entries, %zu words\n", argv[1], entries, real.wordCount(Target::Base));
        CHECK(entries > 400);
        CHECK(top(real.suggestCompounds({}, {"thietke"}, 5)) == "thiết kế");
        CHECK(top(real.suggestCompounds({}, {"sinhvien"}, 5)) == "sinh viên");
        CHECK(top(real.suggestCompounds({}, {"vietnam"}, 5)) == "việt nam");
        CHECK(top(real.suggestCompounds({}, {"cosodulieu"}, 5)) == "cơ sở dữ liệu");
        CHECK(top(real.suggestCompounds({}, {"hoso"}, 5)).empty());   // hồ sơ is not in the starter list
        printf("thiet -> %s\n", join(real.suggestCompounds({}, {"thiet"}, 5)).c_str());
        printf("dien -> %s\n", join(real.suggestCompounds({}, {"dien"}, 5)).c_str());
        printf("quan -> %s\n", join(real.suggestCompounds({}, {"quan"}, 5)).c_str());
    }

    printf(failures ? "\n%d FAILURES\n" : "\nALL OK\n", failures);
    return failures ? 1 : 0;
}
