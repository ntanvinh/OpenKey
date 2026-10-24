//
//  SnippetPalette.h
//  VOpenKey AI, Windows
//
//  The window that opens with the snippet shortcut: type a few words, pick a snippet, Enter, and its text is pasted into
//  the program the user was typing in. Up/Down choose, Enter inserts, Esc or a click elsewhere closes it.
//
#pragma once
#include "stdafx.h"

namespace SnippetPalette {

/// Opens the window, or closes it when it is open.
void toggle();
bool isVisible();
void close();

/// The window that has the keyboard of the snippets (for the hook: keys typed there are not typing to suggest from).
HWND handle();

} // namespace SnippetPalette
