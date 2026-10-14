//
//  SuggestSession.cpp
//  VOpenKey
//
//  See SuggestSession.h.
//
#include "SuggestSession.h"

#include <algorithm>

namespace vsuggest {

namespace {

size_t codePointCount(const std::string& s) {
    size_t n = 0;
    for (char c : s) {
        if (((unsigned char)c & 0xC0) != 0x80)
            n++;
    }
    return n;
}

const size_t kContextWords = 2;

} // namespace

Session::Session(Engine& engine, Host& host) : engine_(engine), host_(host) {}

void Session::setSettings(const Settings& settings) {
    bool wasEnabled = settings_.enabled;
    settings_ = settings;
    if (wasEnabled && !settings_.enabled)
        reset();
}

void Session::commit(const std::string& word) {
    if (settings_.learn)
        engine_.learn(context_, word);
    context_.push_back(Engine::normalizeWord(word));
    if (context_.size() > kContextWords)
        context_.erase(context_.begin());
}

void Session::hideNow() {
    dirty_ = false;
    mode_ = Mode::Idle;
    candidates_.clear();
    shownFor_.clear();
    if (showing_) {
        showing_ = false;
        host_.hideCandidates();
    }
}

void Session::reset() {
    context_.clear();
    lastWord_.clear();
    typed_.clear();
    hideNow();
}

void Session::keyProcessed(KeyKind kind, const std::string& currentWord, const std::string& rawWord) {
    if (!settings_.enabled)
        return;

    if (!currentWord.empty()) {
        //backspacing over a space brings the previous word back for editing: it is no longer context
        if (kind == KeyKind::Delete && lastWord_.empty() && !context_.empty() &&
            Engine::normalizeWord(currentWord) == context_.back()) {
            context_.pop_back();
        }
        lastWord_ = currentWord;
        typed_ = currentWord;
        rawTyped_ = rawWord;
        mode_ = Mode::Typing;
        dirty_ = true;
        return;
    }

    if (kind == KeyKind::Space && !lastWord_.empty()) { //the word is finished
        commit(lastWord_);
        lastWord_.clear();
        if (settings_.nextWord) {
            typed_.clear();
            mode_ = Mode::NextWord;
            dirty_ = true;
        } else {
            hideNow();
        }
        return;
    }

    if (kind == KeyKind::Delete) { //deleted the last letter of a word: the context is still valid
        lastWord_.clear();
        hideNow();
        return;
    }

    //Enter, punctuation, a shortcut...: a new phrase starts
    context_.clear();
    lastWord_.clear();
    hideNow();
}

void Session::refresh() {
    if (!dirty_)
        return;
    dirty_ = false;
    if (!settings_.enabled || mode_ == Mode::Idle) {
        hideNow();
        return;
    }
    //a single letter says too little, unless the words before it narrow it down
    if (mode_ == Mode::Typing && codePointCount(typed_) < 2 && context_.empty()) {
        hideNow();
        return;
    }
    std::vector<Candidate> found = engine_.suggest(context_, typed_, settings_.maxCandidates);
    if (settings_.compounds && mode_ == Mode::Typing) {
        std::vector<std::string> inputs(1, typed_);
        if (!rawTyped_.empty() && rawTyped_ != typed_)
            inputs.push_back(rawTyped_);
        std::vector<Candidate> compounds = engine_.suggestCompounds(context_, inputs, settings_.maxCandidates);
        for (const Candidate& c : compounds) {
            bool known = false;
            for (const Candidate& f : found)
                known = known || f.text == c.text;
            if (!known)
                found.push_back(c);
        }
        std::stable_sort(found.begin(), found.end(),
                         [](const Candidate& a, const Candidate& b) { return a.score > b.score; });
        if (found.size() > settings_.maxCandidates)
            found.resize(settings_.maxCandidates);
    }
    if (found.empty()) {
        hideNow();
        return;
    }
    candidates_ = found;
    shownFor_ = typed_;
    showing_ = true;
    host_.showCandidates(candidates_, typed_);
}

bool Session::accept(size_t slot, const std::string& currentWord, Acceptance& out) {
    if (!settings_.enabled || !showing_ || slot >= candidates_.size())
        return false;
    if (currentWord != shownFor_) //the bar belongs to what was typed a moment ago
        return false;

    const std::string word = candidates_[slot].text;
    out.text = word + " ";
    out.eraseCount = codePointCount(currentWord);

    //a compound is several words: all of them become context, and the compound itself is remembered
    std::vector<std::string> syllables;
    size_t from = 0;
    while (from <= word.size()) {
        size_t space = word.find(' ', from);
        syllables.push_back(word.substr(from, space == std::string::npos ? std::string::npos : space - from));
        if (space == std::string::npos)
            break;
        from = space + 1;
    }
    for (const std::string& syllable : syllables)
        commit(syllable);
    if (syllables.size() > 1 && settings_.learn)
        engine_.learnCompound(syllables);
    lastWord_.clear();

    //the platform types the text now. With next word prediction the bar stays up, but with nothing
    //to accept, until refresh() replaces it with the new list or hides it
    candidates_.clear();
    shownFor_.clear();
    if (settings_.nextWord) {
        typed_.clear();
        mode_ = Mode::NextWord;
        dirty_ = true;
    } else {
        hideNow();
    }
    return true;
}

} // namespace vsuggest
