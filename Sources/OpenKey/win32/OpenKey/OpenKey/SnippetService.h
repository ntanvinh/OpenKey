//
//  SnippetService.h
//  VOpenKey AI, Windows
//
//  The snippets of the user on Windows: the shared list (engine/SnippetStore.h) kept in
//  %APPDATA%\VOpenKey\Snippets\snippets.json, a file that can also be read and edited by hand. The ready-made snippets
//  are inside the program (Features.rc). Everything runs on the thread of the message loop.
//
#pragma once
#include "stdafx.h"
#include "../../../engine/SnippetStore.h"

extern int vSnippetsEnabled;
extern int vSnippetHotKey;

namespace SnippetService {

/// The list of the program, loaded on first use.
vsnippet::Store& store();

/// Saves a moment after the last change (changes made in quick succession, like typing in the editor, are saved once).
void changed();
/// Saves now, if something is waiting.
void flush();

/// "user.<guid>" for a new snippet.
std::string newIdentifier();

/// The ready-made snippets of this version, as the text of the file inside the program.
std::string defaultsText();

} // namespace SnippetService
