// Tests of the list of snippets (portable C++).
//
//   clang++ -std=c++11 -I.. snippet_store_test.cpp ../SnippetStore.cpp ../SnippetSearch.cpp ../MiniJson.cpp ../Suggest.cpp -o /tmp/snippet_store_test && /tmp/snippet_store_test
#include "SnippetStore.h"
#include <cstdio>
#include <fstream>
#include <sstream>

using namespace vsnippet;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

static std::string readAll(const char* path) {
    std::ifstream f(path, std::ios::binary);
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

static const char* kTwoDefaults =
    "{\"version\":1,\"snippets\":["
    "{\"id\":\"builtin.a\",\"title\":\"Alpha\",\"keywords\":\"first\",\"content\":\"A {clipboard}\"},"
    "{\"id\":\"builtin.b\",\"title\":\"Beta\",\"keywords\":\"\",\"content\":\"B\"},"
    "{\"id\":\"user.not-builtin\",\"title\":\"Ignored\",\"content\":\"x\"}]}";

int main() {
    // the real defaults file of the app is valid and all of it is built in
    std::string real = readAll("../snippets/default-snippets.json");
    CHECK(!real.empty());
    Store check;
    check.load("", false, real);
    CHECK(check.snippets().size() >= 20);
    for (size_t i = 0; i < check.snippets().size(); i++)
        CHECK(check.snippets()[i].isBuiltIn() && !check.snippets()[i].title.empty() && !check.snippets()[i].content.empty());

    // new installation: all ready-made snippets, to be saved
    Store s;
    s.load("", false, kTwoDefaults);
    CHECK(s.snippets().size() == 2 && s.needsSave());           // "user.not-builtin" in the defaults file is not taken
    std::string saved = s.serialize();

    // read back: nothing to save, nothing duplicated
    Store t;
    t.load(saved, true, kTwoDefaults);
    CHECK(t.snippets().size() == 2 && !t.needsSave() && !t.fileWasUnreadable());

    // the user deletes one, adds one, edits one, uses one
    size_t user = t.add("user.1", "My address", "home", "Somewhere 1");
    CHECK(user == 2 && t.needsSave());
    t.remove(1);                                                // Beta
    t.update(0, "Alpha 2", "first second", "A2");
    t.recordUse(1, 1000.0);                                     // now at position 1: "My address"
    std::string saved2 = t.serialize();

    // a later version: Beta stays deleted, a new ready-made one appears, the edit stays
    const char* threeDefaults =
        "{\"snippets\":[{\"id\":\"builtin.a\",\"title\":\"Alpha\",\"content\":\"A\"},"
        "{\"id\":\"builtin.b\",\"title\":\"Beta\",\"content\":\"B\"},"
        "{\"id\":\"builtin.c\",\"title\":\"Gamma\",\"content\":\"C\"}]}";
    Store u;
    u.load(saved2, true, threeDefaults);
    CHECK(u.snippets().size() == 3);
    CHECK(u.indexOfId("builtin.b") == -1);                      // stays deleted
    CHECK(u.indexOfId("builtin.c") >= 0);                       // new one
    CHECK(u.snippets()[0].title == "Alpha 2");                  // the edit is kept
    CHECK(u.snippets()[1].useCount == 1 && u.snippets()[1].lastUsed == 1000.0);
    CHECK(u.needsSave());                                       // the new one has to be saved

    // search: the one used last comes first on an empty query
    std::vector<size_t> all = u.search("");
    CHECK(all.size() == 3 && u.snippets()[all[0]].id == "user.1");
    CHECK(u.search("address").size() == 1);
    CHECK(u.search("gamma").size() == 1);

    // changes show in the next search
    u.update((size_t)u.indexOfId("builtin.c"), "Delta", "", "D");
    CHECK(u.search("gamma").empty() && u.search("delta").size() == 1);

    // restore: the deleted comes back, the edited is as it was, the user's is not touched
    u.restoreDefaults(threeDefaults);
    CHECK(u.indexOfId("builtin.b") >= 0);
    CHECK(u.snippets()[(size_t)u.indexOfId("builtin.a")].title == "Alpha");
    CHECK(u.snippets()[(size_t)u.indexOfId("builtin.c")].title == "Gamma");
    CHECK(u.indexOfId("user.1") >= 0);

    // a file nobody can read: not used, flagged, the defaults start again
    Store v;
    v.load("this is not json", true, kTwoDefaults);
    CHECK(v.fileWasUnreadable() && v.snippets().size() == 2 && v.needsSave());

    // JSON of another shape: also unreadable, and entries without an id are dropped
    Store w;
    w.load("[1,2,3]", true, kTwoDefaults);
    CHECK(w.fileWasUnreadable());
    Store x;
    x.load("{\"snippets\":[{\"title\":\"no id\"},{\"id\":\"user.9\",\"title\":\"ok\",\"useCount\":-5}]}", true, "");
    CHECK(x.snippets().size() == 1 && x.snippets()[0].useCount == 0);

    // numbers of a file edited by hand never become undefined values
    Store n;
    n.load("{\"snippets\":[{\"id\":\"user.a\",\"useCount\":1e300,\"lastUsed\":-1e300},{\"id\":\"user.b\",\"useCount\":-3,\"lastUsed\":1e300},"
           "{\"id\":\"user.c\",\"useCount\":7.9,\"lastUsed\":1700000000}]}", true, "");
    CHECK(n.snippets().size() == 3);
    CHECK(n.snippets()[0].useCount == 1000000000 && n.snippets()[0].lastUsed == 0);
    CHECK(n.snippets()[1].useCount == 0 && n.snippets()[1].lastUsed == 0);
    CHECK(n.snippets()[2].useCount == 7 && n.snippets()[2].lastUsed == 1700000000.0);
    Store broken;
    broken.load("{\"snippets\":[{\"id\":\"user.a\",\"useCount\":1-2}]}", true, "");
    CHECK(broken.fileWasUnreadable());                                                       // not a number: not JSON

    // line breaks and accents survive a round trip
    Store y;
    y.load("", false, "");
    y.add("user.2", "T\xC3\xB3m t\xE1\xBA\xAFt", "tom tat", "Line 1\nLine 2\t\"quoted\"");
    Store z;
    z.load(y.serialize(), true, "");
    CHECK(z.snippets().size() == 1 && z.snippets()[0].content == "Line 1\nLine 2\t\"quoted\"");
    CHECK(z.search("tom tat").size() == 1);

    if (failures == 0)
        printf("snippet_store_test: all passed\n");
    return failures == 0 ? 0 : 1;
}
