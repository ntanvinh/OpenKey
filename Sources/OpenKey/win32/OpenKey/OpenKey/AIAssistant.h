//
//  AIAssistant.h
//  VOpenKey AI, Windows
//
//  The window that opens when the AI shortcut is pressed: the user says what text they want, an AI service writes it, and the
//  text is put where the user was typing.
//
//  - If something was selected in the program, it is already in the box when the window opens, with the cursor in front of it
//    to write the instruction ("Dịch sang tiếng Anh"). The answer then replaces the selection.
//  - Type the request, Ctrl+Enter to ask. The answer is written in the window as the service produces it; Esc stops it.
//  - Ctrl+Shift+Enter puts the answer into the program (it replaces the selection, or goes where the cursor was),
//    Ctrl+Shift+C copies it.
//  - Nothing typed or received is kept: the text is gone when the window closes.
//
#pragma once
#include "stdafx.h"

extern int vAICopySelection;

namespace AIAssistant {

/// What the shortcut does: opens the window for the selection of the program in front, or closes it when it is open.
void toggle();
bool isVisible();
void hide();

} // namespace AIAssistant
