//
//  SuggestionController.h
//  VOpenKey AI, Windows
//
//  The glue between the keyboard hook (OpenKey.cpp), the portable suggestion engine (engine/SuggestSession.h) and the
//  bar window (SuggestionBar). The rules of what is suggested and when are in the engine, shared with macOS.
//
#pragma once
#include "stdafx.h"
#include "../../../engine/SuggestSession.h"

extern int vSuggestEnabled;     //the bar with words
extern int vSuggestNextWord;    //predict the next word
extern int vSuggestLearn;       //learn the words of the user
extern int vSuggestCompounds;   //offer compound words
extern int vSuggestTabAccepts;  //Tab chooses the first suggestion
extern int vMacroConfirm;       //an abbreviation waits for the user on the bar (needs the Unicode table)

namespace SuggestionController {

/// Loads the settings, the dictionaries and the learned words, creates the bar. After the engine is initialised.
void start(HINSTANCE instance);
void stop();

/// The settings changed (or the code table did): tell the engine of the suggestions.
void applySettings();

/// The suggestions (or the abbreviations that wait for a choice) are on: the hook only works out the words of the typing engine
/// for the controller when this is true, so that typing costs nothing when the features are off.
bool isActive();

/// True when a bar is up and a key could choose from it.
bool isShowing();

/// The flow of typing is broken (mouse, other application, language switch): forget the context, hide the bar.
void reset();

/// The key just handled by the typing engine. The words are UTF-8.
void keyProcessed(vsuggest::KeyKind kind, const std::string& word, const std::string& raw, const std::string& macro);

/// A key chose suggestion `slot`: false when there is nothing to choose (the key goes to the application).
bool accept(int slot, const std::string& currentWord, std::wstring& text, size_t& eraseCount);

/// The foreground application changed; `exeName` is its file name in lower case.
void applicationActivated(const std::string& exeName);

/// True for programs where Tab belongs to the program (terminals): no bar there.
bool isExcludedApplication(const std::string& exeName);

/// Where the caret of the program in front is, when the program tells it in the quick way (screen coordinates). For the
/// windows that open under the text, like the case list.
bool classicCaretLine(RECT& line);

void reloadDictionaries();
void forgetLearnedWords();
void openDictionaryFolder();

//called by the bar window
void refresh();
void saveLearning();
void caretFound(unsigned generation);

} // namespace SuggestionController
