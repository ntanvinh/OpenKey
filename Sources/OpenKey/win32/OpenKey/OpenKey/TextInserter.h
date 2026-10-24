//
//  TextInserter.h
//  VOpenKey AI, Windows
//
//  Puts text into the program that has the keyboard: for snippets, the case bar and the AI assistant.
//
//  The text is pasted (Ctrl+V), not typed: typed, every line break of a prompt would be an Enter, and in a chat box that
//  sends the message half way. Pasting needs the clipboard, so what the user had copied is put back a moment later, unless
//  something else was copied in the meantime. The text is marked on the clipboard so that Windows' clipboard history
//  (Win+V) and cloud clipboard do not keep it.
//
#pragma once
#include "stdafx.h"
#include "../../../engine/SnippetSearch.h"

namespace TextInserter {

/// Brings `window` to the front (it had the keyboard before our own window opened), as far as Windows allows it.
void activateWindow(HWND window);

/// Pastes `text` as it is into `target` (nothing is replaced in it). A selection in the program is replaced by the text.
/// `target` may be NULL: then the program that is in front gets it.
void insertText(const std::wstring& text, HWND target);

/// `text` (UTF-8) with {clipboard}, {date} and {time} replaced: the clipboard text of the user, 14/10/2026, 09:05.
std::string expandedText(const std::string& text);

/// Inserts a snippet (its text, placeholders not replaced yet).
void insertSnippetContent(const std::string& content, HWND target);

/// Presses Ctrl and a key in the program that has the keyboard, without our own keyboard hook treating it as typing.
void postControlKey(WORD virtualKey);

/// Finds the text selected in the program that has the keyboard: presses Ctrl+C, reads what arrives on the clipboard and
/// puts the clipboard of the user back. False when nothing was selected (or the program does not copy). Takes up to about
/// 0.4 s; the modifier keys of the user must be up (see runWhenKeysReleased).
bool copySelection(std::wstring& text);

/// Runs `action` as soon as Ctrl, Alt, Shift and Windows are all up (or after 1.5 s anyway). A shortcut like Ctrl+Alt+C
/// still has its keys down when it is noticed, and a Ctrl+C sent then would be Ctrl+Alt+C. Never blocks the keyboard hook.
void runWhenKeysReleased(void (*action)());

/// The text on the clipboard now, empty when there is none.
std::wstring clipboardText();

/// Gives the clipboard back to the user now if a text of ours is still on it (for when the program quits).
void restoreClipboardNow();

} // namespace TextInserter
