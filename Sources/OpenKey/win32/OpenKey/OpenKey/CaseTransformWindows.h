//
//  CaseTransformWindows.h
//  VOpenKey AI, Windows
//
//  What Windows knows about Unicode, for the portable case rules (engine/CaseTransform.h): upper and lower case of every
//  script (LCMapStringEx), accents (NormalizeString) and what kind of character a character is (GetStringTypeW).
//  Characters beyond the Basic Multilingual Plane (emoji...) have no case and are treated as separators, like symbols.
//
#pragma once
#include "stdafx.h"
#include "../../../engine/CaseTransform.h"

namespace CaseTransformWindows {

/// The one object that gives the portable rules their Unicode data.
const vcase::Unicode& unicode();

/// A std::wstring (UTF-16 on Windows) as the portable code's text and back.
std::u16string toU16(const std::wstring& text);
std::wstring toWide(const std::u16string& text);

} // namespace CaseTransformWindows
