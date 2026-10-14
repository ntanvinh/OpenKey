//
//  SuggestSession.h
//  VOpenKey
//
//  Everything about HOW suggestions behave while typing, independent of the platform: which words
//  are the context, when the bar shows, what is learned, what a key press accepts. A platform only
//  has to (1) draw the bar (Host), (2) tell the session what happened (keyProcessed, reset) and
//  (3) type the text it gets back from accept(). Same rules then apply on macOS, Windows and Linux.
//
//  Keys, the same on every platform:
//      Alt/Option+1-5 accepts suggestion 1-5 (slot 0-4)
//      Tab            accepts the first suggestion (slot 0) ONLY if the user turned that on: Tab is also the key that
//                     moves to the next field of a form, and a suggestion must never take it by surprise
//  Accepting replaces the word typed so far with the suggestion followed by a space, and the bar
//  goes on with the next word prediction, so a sentence can be typed with Tab Tab Tab.
//
//  Per platform glue, in the order things happen for each key press:
//      1. If session.isShowing() and the key is Tab or Alt+digit: ask accept(slot, currentWord, out).
//         When it returns true, swallow the key, send out.eraseCount backspaces then out.text, and
//         tell the typing engine to start a new word. When false let the key through.
//      2. Otherwise let the typing engine handle the key, then call
//         keyProcessed(kind, vGetTypingWord(), vGetTypingRawWord()) with the word that is now on screen
//         and the keys that were pressed for it.
//      3. Call refresh() soon after (directly, or from a timer / idle callback so that typing is
//         never slowed down). It computes the suggestions and calls the Host.
//      4. Mouse click, switching application or language, secure fields: call reset().
//
#ifndef SuggestSession_h
#define SuggestSession_h

#include <string>
#include <vector>

#include "Suggest.h"

namespace vsuggest {

/** Implemented once per platform: shows the suggestion bar near the text caret. */
class Host {
public:
    virtual ~Host() {}
    /**
     * Show or update the bar. `typed` is the word being completed, empty for next word predictions.
     * The first candidate is the one Tab accepts.
     */
    virtual void showCandidates(const std::vector<Candidate>& candidates, const std::string& typed) = 0;
    virtual void hideCandidates() = 0;
};

/** What the key that was just handled by the typing engine was. */
enum class KeyKind {
    Space,  //a plain space that the typing engine passed on unchanged
    Delete, //backspace
    Other   //anything else that is not part of a word: Enter, punctuation, arrows, shortcuts, a space that
            //triggered a macro...
};

struct Settings {
    bool enabled = false;
    bool nextWord = true;       //predict the next word after a space, before anything is typed
    bool learn = true;          //remember the user's words and word pairs
    bool compounds = true;      //suggest compound words too: "thietke" gives the compound with its accents
    size_t maxCandidates = 5;
};

/** What the platform has to type to carry out an accepted suggestion. */
struct Acceptance {
    std::string text;     //the suggestion and a space, UTF-8
    size_t eraseCount;    //characters (code points) of the word typed so far, delete them first
};

class Session {
public:
    Session(Engine& engine, Host& host);

    void setSettings(const Settings& settings);
    const Settings& settings() const { return settings_; }

    /**
     * currentWord: the word now on screen (what vGetTypingWord returns, as UTF-8), empty if no word is in progress.
     * rawWord: the keys pressed for it (vGetTypingRawWord), optional. Telex may have turned them into accents,
     * compounds typed without accents are looked up with these as well.
     */
    void keyProcessed(KeyKind kind, const std::string& currentWord, const std::string& rawWord = std::string());

    /** Computes the suggestions for the last keyProcessed and shows them. Cheap when nothing changed. */
    void refresh();

    /**
     * A suggestion was chosen. Returns false (and the key must go through as normal) when there is no
     * such suggestion or the bar is out of date compared with currentWord.
     */
    bool accept(size_t slot, const std::string& currentWord, Acceptance& out);

    bool isShowing() const { return showing_; }

    /** The flow of typing is broken (mouse, other application...): forget context and hide the bar. */
    void reset();

    /** The words before the current one, for tests and debugging. */
    const std::vector<std::string>& context() const { return context_; }

private:
    enum class Mode { Idle, Typing, NextWord };

    Engine& engine_;
    Host& host_;
    Settings settings_;

    std::vector<std::string> context_; //last two committed words, normalized
    std::string lastWord_;             //last word seen while typing, committed by the next space
    std::string typed_;                //what the pending refresh is for
    std::string rawTyped_;             //the keys behind typed_
    Mode mode_ = Mode::Idle;
    bool dirty_ = false;

    std::vector<Candidate> candidates_;
    std::string shownFor_;
    bool showing_ = false;

    void commit(const std::string& word);
    void hideNow();
};

} // namespace vsuggest

#endif /* SuggestSession_h */
