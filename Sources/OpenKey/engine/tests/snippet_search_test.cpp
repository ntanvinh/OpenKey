// Tests of the snippet search (portable C++, no platform code).
//
//   clang++ -std=c++11 -I.. snippet_search_test.cpp ../SnippetSearch.cpp ../Suggest.cpp -o /tmp/snippet_search_test && /tmp/snippet_search_test
//
// The strings are UTF-8 literals, MSVC needs /utf-8 for this file.
#include "SnippetSearch.h"
#include <cstdio>
#include <string>

using namespace vsnippet;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

static std::string titles(const std::vector<Entry>& all, const std::vector<size_t>& found) {
    std::string s;
    for (size_t i : found) s += (s.empty() ? "" : " | ") + all[i].title;
    return s;
}

int main() {
    std::vector<Entry> all = {
        {"Tóm tắt văn bản", "tom tat summary summarize tldr", "Hãy tóm tắt văn bản dưới đây thành 5 ý chính. {clipboard}", 0, 0},
        {"Dịch sang tiếng Anh", "dich english translate en", "Dịch đoạn sau sang tiếng Anh tự nhiên.", 0, 0},
        {"Dịch sang tiếng Việt", "dich vietnamese translate vi", "Dịch đoạn sau sang tiếng Việt tự nhiên.", 0, 0},
        {"Đóng vai chuyên gia", "role expert persona", "Hãy đóng vai một chuyên gia hàng đầu.", 0, 0},
        {"Code review", "review code pull request", "Review đoạn code dưới đây. Tóm tắt các rủi ro.", 0, 0},
        {"Viết commit message", "git commit conventional", "Viết commit message theo chuẩn.", 0, 0},
    };
    Index index(all);

    // without accents, any case
    auto r = index.search("tom tat");
    printf("tom tat -> %s\n", titles(all, r).c_str());
    CHECK(!r.empty() && r[0] == 0);                              // the title itself first
    CHECK(r.size() == 2 && r[1] == 4);                           // "Code review" mentions "tóm tắt" in its content only
    CHECK(index.search("TÓM TẮT").size() == 2);                  // with accents and capitals: the same

    // đ is d
    r = index.search("dong vai");
    CHECK(r.size() == 1 && r[0] == 3);
    r = index.search("đóng");
    CHECK(r.size() == 1 && r[0] == 3);

    // every word has to be found, in any order
    r = index.search("dich anh");
    CHECK(r.size() == 1 && r[0] == 1);                           // not the one that translates into Vietnamese
    r = index.search("anh dich");
    CHECK(r.size() == 1 && r[0] == 1);
    CHECK(index.search("dich xyz").empty());

    // title beats keywords beats content
    r = index.search("review");
    CHECK(!r.empty() && r[0] == 4);
    r = index.search("summary");                                 // only in the keywords
    CHECK(r.size() == 1 && r[0] == 0);
    r = index.search("rui ro");                                  // only in the content
    CHECK(r.size() == 1 && r[0] == 4);

    // the start of a word beats the inside of a word
    std::vector<Entry> two = {{"Reviewer notes", "", "", 0, 0}, {"Code preview", "", "", 0, 0}};
    Index viewIndex(two);
    r = viewIndex.search("view");
    CHECK(r.size() == 2);
    r = viewIndex.search("rev");
    CHECK(r.size() == 2 && r[0] == 0);                           // both have it, "Reviewer" starts with it
    std::vector<Entry> three = {{"Preview", "", "", 0, 0}, {"A view", "", "", 0, 0}};
    r = Index(three).search("view");
    CHECK(r.size() == 2 && r[0] == 1);                           // "view" starts a word in "A view", not in "Preview"

    // what is used a lot comes first among equals
    std::vector<Entry> used = {{"Dịch A", "", "", 0, 0}, {"Dịch B", "", "", 50, 5}, {"Dịch C", "", "", 3, 9}};
    r = Index(used).search("dich");
    CHECK(r.size() == 3 && r[0] == 1);

    // an empty query lists everything: last used first, then most used, then as listed
    r = Index(used).search("");
    CHECK(r.size() == 3 && r[0] == 2 && r[1] == 1 && r[2] == 0);
    r = index.search("   ");
    CHECK(r.size() == all.size() && r[0] == 0 && r[5] == 5);   // never used: the order of the list

    // punctuation and symbols in the query are not special
    CHECK(index.search("{clipboard}").size() == 1);
    CHECK(index.search("(").empty());

    // no entries
    CHECK(Index(std::vector<Entry>()).search("a").empty());

    // placeholders
    Values v;
    v.clipboard = "ABC {date}";
    v.date = "14/10/2026";
    v.time = "09:05";
    CHECK(expand("Ng\xc3\xa0y {date} l\xc3\xba" "c {time}.", v) == "Ng\xc3\xa0y 14/10/2026 l\xc3\xba" "c 09:05.");
    CHECK(expand("{clipboard}", v) == "ABC {date}");                      // one pass: the clipboard is not expanded again
    CHECK(expand("a{clipboard}b{clipboard}c", v) == "aABC {date}bABC {date}c");
    CHECK(expand("if (x) { return {y}; } {Date} {date", v) == "if (x) { return {y}; } {Date} {date"); // not ours: untouched
    CHECK(expand("", v).empty());
    CHECK(expand("{", v) == "{" && expand("{{date}}", v) == "{14/10/2026}");
    CHECK(expand("{clipboard}", Values()).empty());                       // nothing on the clipboard

    printf(failures ? "\n%d FAILURES\n" : "ALL OK\n", failures);
    return failures ? 1 : 0;
}
