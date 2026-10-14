//
//  Suggest.h
//  VOpenKey
//
//  Contextual suggestion engine (word completion + next word prediction), in the spirit of SwiftKey.
//
//  Portable on purpose (macOS, Windows, Linux): plain C++11, std only, UTF-8 std::string at every
//  boundary, no file or OS calls. The platform reads dictionary files itself and hands the text over
//  (loadText), and asks for the learned data as text (serializeUser) to store it however it likes.
//  Keep this file ASCII only (use \u escapes) so that compilers without a UTF-8 source charset
//  (MSVC without /utf-8) build the same tables. Not thread safe: call it from one thread.
//
//  Dictionary files are UTF-8 text, one entry per line:
//
//      # comment
//      la<TAB>50000              a word and how often it is used (the count is optional, default 1)
//      xin chao<TAB>3000         several words: teaches the engine which word follows which
//      xin chao cac ban<TAB>20   (every pair and triple of neighbours is learned)
//
//      thiet_ke<TAB>900          a compound word (syllables joined by "_"): it can be suggested whole,
//                                typing "thietke" (no spaces, no accents) offers it
//      #!compounds               from here on, several words on a line are one compound word, so a plain
//                                list of compounds can be written with spaces; "#!context" switches back
//
//  (the examples are written without accents, real files have them). A word is what the typing engine calls a word:
//  one syllable between spaces. Everything is case-insensitive and may be written with precomposed
//  or combining accents.
//
#ifndef Suggest_h
#define Suggest_h

#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace vsuggest {

enum class Target {
    Base, //dictionaries shipped with the app and added by the user
    User  //what the engine has learned from the user's typing
};

struct Candidate {
    std::string text; //UTF-8, cased like the word the user is typing
    double score;
};

class Model;

class Engine {
public:
    Engine();
    ~Engine();
    Engine(const Engine&) = delete;
    Engine& operator=(const Engine&) = delete;

    /** Add the entries of a dictionary (UTF-8 text, see above). Returns the number of entries read. */
    int loadText(const std::string& text, Target target = Target::Base);

    void clear(Target target);
    size_t wordCount(Target target) const;

    /** The learned data in the dictionary format, ready to be saved and loaded again with loadText. */
    std::string serializeUser();
    /** True when something was learned since the last serializeUser. */
    bool hasUnsavedLearning() const;

    /**
     * Remember that `word` was typed after the words in `context` (oldest first, only the last two count).
     * Ignored when the word is not a plain word (digits, punctuation, too long).
     */
    void learn(const std::vector<std::string>& context, const std::string& word);

    /**
     * Words the user is most likely to type next.
     * context: the words before the one being typed, oldest first.
     * typed: what has been typed of the current word, may be empty (then only context is used).
     *        Letters without accent also match accented ones: "hoc" finds "hoc" with any accent
     *        on the vowel.
     */
    std::vector<Candidate> suggest(const std::vector<std::string>& context,
                                   const std::string& typed,
                                   size_t maxCount) const;

    /** Remember that these syllables were accepted together as one compound word. */
    void learnCompound(const std::vector<std::string>& words);

    /**
     * Compound words for what has been typed. Unlike suggest() the typed text may span several
     * syllables without spaces or accents: "thietke" finds the compound "thiet ke" (with its accents), "sinhv" finds
     * "sinh vien".
     * inputs: the same text in different forms, e.g. what is on screen and the keys that were pressed
     * (Telex may have changed "hoso" into something else on screen); all are tried.
     */
    std::vector<Candidate> suggestCompounds(const std::vector<std::string>& context,
                                            const std::vector<std::string>& inputs,
                                            size_t maxCount) const;

    /**
     * Optional source of last resort, asked for completions when the dictionaries know too few
     * words for what was typed (the macOS layer plugs the system spell checker in here).
     */
    typedef std::function<void(const std::string& typed, std::vector<std::string>& words)> FallbackProvider;
    void setFallback(FallbackProvider provider);

    /** Lowercase, composed form of a word, as it is stored. */
    static std::string normalizeWord(const std::string& utf8);

    /**
     * Text for searching in: lowercase, accents taken off, "\u0111" written as "d" ("Tom tat" and "t\u00f3m t\u1eaft" are the same).
     * Everything that is not a letter stays as it is.
     */
    static std::string foldForSearch(const std::string& utf8);

private:
    std::unique_ptr<Model> base_;
    std::unique_ptr<Model> user_;
    FallbackProvider fallback_;
    bool userDirty_ = false;
};

} // namespace vsuggest

#endif /* Suggest_h */
