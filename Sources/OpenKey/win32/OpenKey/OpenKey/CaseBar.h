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
//  (Unlike on macOS the list does not appear by itself when text is selected: Windows programs do not tell their
//  selection, finding it would mean pressing Ctrl+C after every selection.)
//
#pragma once
#include "stdafx.h"

extern int vCaseBarHotKey;

namespace CaseBar {

/// The shortcut: opens the list for the selection of the program in front, or closes it when it is open.
void toggle();
bool isVisible();
void hide();

/// A key was pressed. True when the list used it: the hook must not pass it on, nor its key up.
bool keyDown(unsigned virtualKey, bool alt, bool control, bool shift, bool win);

/// A mouse button went down at `point` (screen): a click outside the list puts it away.
void mouseDown(POINT point);

} // namespace CaseBar
