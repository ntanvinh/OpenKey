//
//  DictionaryPalette.h
//  VOpenKey AI, Windows
//
//  Floating 2-column dictionary lookup and open-source catalog manager window.
//
#pragma once
#include "stdafx.h"
#include <string>

namespace DictionaryPalette {

void show();
void showWithText(const std::u16string& text);
void showManager();
void toggle();
void hide();
bool isVisible();

} // namespace DictionaryPalette
