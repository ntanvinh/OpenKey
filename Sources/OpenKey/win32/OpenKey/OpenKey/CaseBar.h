//
//  CaseBar.h
//  VOpenKey AI, Windows
//
//  The list that offers to change the case of the selected text: CHỮ HOA, chữ thường, Viết Hoa Từng Từ, camelCase... each
//  with a preview of the selection in that style (the rules are in engine/CaseTransform.h).
//
//  It opens with a shortcut (Ctrl+Alt+C by default). The selection is found with Ctrl+C, the clipboard is put back
//  right away. The list does not take the keyboard, so the selection stays selected: Up/Down/Enter/Esc and Alt+1...Alt+9,
//  Alt+0 are read by the keyboard hook, a click on a row works too. The chosen text is pasted over the selection.
//
//  It also comes up by itself when text is selected (a drag, a double click, Shift+click, Shift+arrows, Ctrl+A), like on macOS,
//  unless switched off in the settings. The selection is then read with UI Automation, never with Ctrl+C: a program that does
//  not tell its selection that way gets no list (the shortcut still works there). That list takes Alt+digits only; pressing the
//  shortcut while it is up gives it the arrows, Enter and Esc too. It goes away after 20 seconds, on another key, a click
//  elsewhere, scrolling or another program in front. Nothing is read in a terminal, in a password field or in our own windows.
//
#pragma once
#include "stdafx.h"

extern int vCaseBarHotKey;
extern int vCaseBarAuto;     //the list comes up by itself when text is selected

namespace CaseBar {

/// Makes the window of the list (hidden) before the hooks are installed, so that the first selection does not have to make a window inside a
/// hook, which must answer fast. Does nothing while the list that comes up by itself is off (it is made when it is first needed).
void prepare();

/// The shortcut: opens the list for the selection of the program in front, or closes it when it is open.
void toggle();
bool isVisible();
void hide();

/// A key was pressed (every key, whether the list is up or not: a selection made with the keys is looked at). True when the list
/// used it: the hook must not pass it on, nor its key up.
bool keyDown(unsigned virtualKey, bool alt, bool control, bool shift, bool win);

/// A mouse button went down at `point` (screen): a click outside the list puts it away.
void mouseDown(POINT point, bool leftButton);

/// The left button came up at `point`: a drag, a double click or Shift+click made a selection, which is looked at soon.
void mouseUp(POINT point, bool shiftHeld);

/// The wheel turned: the list is put away.
void scrolled();

} // namespace CaseBar
