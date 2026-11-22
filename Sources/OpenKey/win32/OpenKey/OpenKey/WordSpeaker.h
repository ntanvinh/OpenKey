//
//  WordSpeaker.h
//  VOpenKey AI, Windows
//
//  Reads an English word aloud with a voice of Windows (SAPI): no network, no key, no cost. What may be read is decided in
//  engine/WordSpeech.h, the same on macOS. Use it from the thread of the windows only (the voice lives in that COM apartment).
//
#pragma once
#include <string>

namespace WordSpeaker {

/// Reads `text` in English, after stopping what is being read. False when Windows has no English voice or SAPI cannot start
/// (nothing is read then).
bool speak(const std::wstring& text);

void stop();

}
