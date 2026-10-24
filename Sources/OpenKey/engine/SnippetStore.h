//
//  SnippetStore.h
//  VOpenKey
//
//  The list of snippets of the user, without any platform code: the platform reads and writes the file and gives the
//  text of it here. Plain C++11, UTF-8, ASCII source. The file is JSON:
//
//      { "version": 1, "seeded": ["builtin.summarize", ...], "snippets": [ {"id", "title", "keywords", "content",
//        "useCount", "lastUsed"}, ... ] }
//
//  A new installation starts with the ready-made snippets (engine/snippets/default-snippets.json, ids "builtin.*"),
//  copied into the list so they are edited and deleted like the user's own. A later version that brings new ready-made
//  snippets adds only those ("seeded" remembers which were added once), and one that the user deleted stays deleted.
//  Same rules as the macOS app.
//
#ifndef SnippetStore_h
#define SnippetStore_h

#include <set>
#include <string>
#include <vector>
#include <memory>

#include "SnippetSearch.h"

namespace vsnippet {

struct Snippet {
    std::string id;       //"builtin.summarize" or "user.<uuid>", never changes
    std::string title;
    std::string keywords;
    std::string content;
    int useCount;
    double lastUsed;      //seconds since 1970, 0 = never

    Snippet() : useCount(0), lastUsed(0) {}
    bool isBuiltIn() const { return id.compare(0, 8, "builtin.") == 0; }
};

class Store {
public:
    Store();

    /**
     * Reads the file. `fileText` is its content, `fileExists` false when there is no file yet.
     * A file that exists but is not readable JSON is not used (see fileWasUnreadable) and the list starts again.
     * The ready-made snippets are merged in. Afterwards needsSave() tells whether the file should be written.
     */
    void load(const std::string& fileText, bool fileExists, const std::string& defaultsText);

    /** True after load() when the file existed but could not be read: the platform keeps a copy of it before saving. */
    bool fileWasUnreadable() const { return unreadable_; }

    /** The content of the file for the current list. */
    std::string serialize() const;

    bool needsSave() const { return needsSave_; }
    void markSaved() { needsSave_ = false; }

    const std::vector<Snippet>& snippets() const { return snippets_; }

    /** Positions in snippets() of what matches, best first (empty query: all, the ones used last first). */
    std::vector<size_t> search(const std::string& query);

    /** -1 when there is none. */
    int indexOfId(const std::string& id) const;

    /** Adds a snippet of the user at the end; `id` must be new ("user.<uuid>"). Returns its position. */
    size_t add(const std::string& id, const std::string& title, const std::string& keywords, const std::string& content);
    void update(size_t position, const std::string& title, const std::string& keywords, const std::string& content);
    void remove(size_t position);
    /** Counts a use: the ones used most and last come first. `now` is seconds since 1970. */
    void recordUse(size_t position, double now);

    /** Puts the ready-made snippets back: deleted ones come back, edited ones are as they were. The user's are not touched. */
    void restoreDefaults(const std::string& defaultsText);

private:
    std::vector<Snippet> snippets_;
    std::set<std::string> seeded_;
    bool needsSave_;
    bool unreadable_;
    bool indexStale_;
    std::unique_ptr<Index> index_;
    std::vector<size_t> indexedPositions_; //snippets_ as it was when the index was made

    static std::vector<Snippet> readList(const std::string& text, bool builtInOnly);
    void changed();
};

} // namespace vsnippet

#endif /* SnippetStore_h */
