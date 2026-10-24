//
//  AIClient.h
//  VOpenKey AI, Windows
//
//  Asks an AI service for text and receives it as it is written, over HTTPS with WinHTTP, on a thread of its own: the
//  window that asked gets messages as the text arrives. What is sent, how the answer is read and what the errors are is
//  in the portable code (engine/AIProtocol.h). Care taken here:
//  - nothing is cached or stored: no cookies, no saved credentials;
//  - a redirect is never followed, so the key is never sent to another server than the one the user chose;
//  - the key goes only in a header (see AIProtocol), never in the address;
//  - the messages of errors have the key and anything that looks like one taken out.
//
#pragma once
#include "stdafx.h"
#include "../../../engine/AIProtocol.h"

namespace AIClient {

/// Messages posted to the window given to generate(). `wParam` is the id that generate() returned.
const UINT kMessageText = WM_APP + 61;     //lParam: std::wstring* with a piece of the answer; the window deletes it
const UINT kMessageDone = WM_APP + 62;     //lParam: Done*; the window deletes it
const UINT kMessageModels = WM_APP + 63;   //lParam: Models*; the window deletes it

struct Done {
    vai::Error error;          //code None: the answer is complete
    std::wstring message;      //what to tell the user when there is an error
};

struct Models {
    std::vector<std::string> names;
    vai::Error error;
    std::wstring message;
};

/// Sends the request. Returns an id (never 0), or 0 and the reason in `reason` when the request cannot be made.
unsigned generate(const vai::Config& config, const std::string& prompt, HWND window, std::wstring& reason);

/// Asks the service which models it offers (it also tells whether the key and the address work).
unsigned listModels(const vai::Config& config, HWND window, std::wstring& reason);

/// Stops a request. Whatever came is kept by the caller; nothing more is delivered for that id.
void cancel(unsigned id);

} // namespace AIClient
