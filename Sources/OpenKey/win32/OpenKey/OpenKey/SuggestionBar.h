//
//  SuggestionBar.h
//  VOpenKey AI, Windows
//
//  The window of the suggestion bar: a small popup under the text caret that never takes the focus or the mouse,
//  so the application the user types in is not disturbed. It only draws; what it shows and when comes from
//  SuggestionController.
//
#pragma once
#include "stdafx.h"

class SuggestionBar {
public:
    static const UINT kMessageRefresh = WM_APP + 41;  //posted by the controller: work out the suggestions now
    static const UINT kMessageCaret = WM_APP + 42;    //a worker found the caret of an application (see SuggestionController)
    static const UINT kMessageField = WM_APP + 43;    //a worker found out whether the field holds a secret (see SuggestionController)

    /// Creates the (hidden) window. Call once, from the thread that runs the message loop.
    static bool create(HINSTANCE instance);
    static void destroy();
    static HWND handle();

    /// The words of the bar; the first one is the one Tab chooses.
    static void setWords(const std::vector<std::wstring>& words, bool firstUsesTab);
    /// Shows the bar under a text line (screen coordinates), above it when there is no room below.
    static void showBelow(const RECT& line);
    static void hide();
    static bool isVisible();
};
