//
//  SnippetSearch.h
//  VOpenKey
//
//  Searching a list of snippets as one types, the same on every platform. Plain C++11, UTF-8 std::string, no platform code.
//
//  The text is compared without case and without accents, so "tom tat" finds a snippet titled "Tom tat van ban" written
//  with accents, and "dong vai" finds the one titled with a D with stroke. A query is split into words and every word
//  has to be found, in the title, the keywords or the content. Titles count most, then keywords, then content; a word at
//  the start of a word counts more than one inside it. Snippets that are used often come first among equals.
//
//  Also here: filling in the placeholders of a snippet ({clipboard}, {date}, {time}) just before it is inserted.
//

#ifndef SnippetSearch_h
#define SnippetSearch_h

#include <string>
#include <vector>

namespace vsnippet {

struct Entry {
    std::string title;
    std::string keywords;   //extra words to find it by, written in any way
    std::string content;
    int useCount;
    long long lastUsed;     //any increasing number: a time, a counter; 0 = never

    Entry() : useCount(0), lastUsed(0) {}
    Entry(const std::string& t, const std::string& k, const std::string& c, int uses = 0, long long last = 0)
        : title(t), keywords(k), content(c), useCount(uses), lastUsed(last) {}
};

class Index {
public:
    explicit Index(const std::vector<Entry>& entries);

    /**
     * Positions in `entries` of the snippets that match, best first. An empty query matches all of them: the ones used
     * last first, then the ones used most, then in the order of the list.
     */
    std::vector<size_t> search(const std::string& query) const;

private:
    struct Folded {
        std::string title, keywords, content;
        int useCount;
        long long lastUsed;
    };
    std::vector<Folded> folded_;
};

/// What the placeholders of a snippet are replaced with. The platform fills it in: it knows the clipboard and the clock.
struct Values {
    std::string clipboard;
    std::string date;       //already written the way the user reads dates
    std::string time;
};

/**
 * Replaces {clipboard}, {date} and {time} in `text`, written exactly like that. Anything else between braces is left
 * as it is, so code in a snippet is safe. The replacement is made in one pass: a clipboard that happens to contain
 * "{date}" is not replaced again.
 */
std::string expand(const std::string& text, const Values& values);

} // namespace vsnippet

#endif /* SnippetSearch_h */
