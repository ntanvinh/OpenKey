//
//  WordSpeech.h
//  VOpenKey
//
//  What the dictionary may read aloud, the same on every platform: plain C++11, UTF-8 std::string, no platform code.
//
//  The speech engine of the system (AVSpeechSynthesizer on macOS, SAPI on Windows) is given an English word, so two things are
//  decided here and not twice: is this headword an English word that can be pronounced (letters, and a space, a hyphen, an
//  apostrophe or a dot inside it), and does the dictionary it comes from say it is English. A Vietnamese headword such as "ba"
//  is made only of ASCII letters too, so the letters alone are not enough: the language of the dictionary decides when it is known.
//

#ifndef WordSpeech_h
#define WordSpeech_h

#include <string>
#include <vector>

namespace vspeech {

/**
 * The text to give to an English voice for a headword, or "" when it is not something to pronounce: it has to start with a
 * letter, hold only the letters A-Z, and inside it single spaces, hyphens, apostrophes (the curly one of the dictionaries is
 * turned into the straight one) and dots; at most 64 characters; no digit, no accent (an accented word is not English).
 * Spaces at both ends are dropped and a run of spaces becomes one.
 */
std::string SpeakableEnglish(const std::string& headword);

/** "en", "EN", "en-US", "en_GB" and "eng" are English. */
bool IsEnglishLang(const std::string& code);

/** A dictionary whose language is not given, as a dictionary that the user imported is. */
bool IsUnknownLang(const std::string& code);

/**
 * What to speak for a headword found in dictionaries whose source languages are `sourceLangs` (one per dictionary that has
 * an entry for it), or "" for nothing: English when one of them is English; the headword itself when no language is known;
 * nothing when every language is known and none is English (a Vietnamese or a Japanese headword).
 */
std::string TextToSpeak(const std::string& headword, const std::vector<std::string>& sourceLangs);

}

#endif
