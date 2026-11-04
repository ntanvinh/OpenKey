//
//  AIAgentRunner.h
//  VOpenKey AI, Windows
//
//  Runs an AI agent program (Codex CLI, Claude Code CLI, Antigravity CLI) for the assistant, in place of a request to a server: finds
//  the program, starts it for one request in a folder of its own that is empty, writes the request on its standard input, reads what it
//  prints as it comes and tells the window with the same messages as AIClient (kMessageText, kMessageDone, kMessageModels), so that the
//  window does not care which of the two answers. What each program is, what is passed to it and how its output is read is in the portable
//  code (engine/AIAgent.h). Care taken here:
//  - the program is started without a window, in a job object: stopping a request (or the program ending) takes down everything it started;
//  - a script (.cmd, .bat: how npm installs Codex) runs through cmd.exe only when nothing in its arguments means something to cmd.exe;
//  - the standard handles are the only handles the program inherits;
//  - nothing the program prints is trusted to have a shape: a request ends after 10 minutes or 2 MB, whatever it does.
//
#pragma once
#include "stdafx.h"
#include "../../../engine/AIAgent.h"

namespace AIAgentRunner {

/// The file to run for an agent: `chosen` (what the user picked in the settings) when it can be run, otherwise the first the search finds in
/// the folders of PATH and the folders programs like these are usually installed in. Empty when there is none.
std::wstring findProgram(const vai::agent::Agent& agent, const std::wstring& chosen);

/// Whether the file can be started: a program (.exe, .com) or a script (.cmd, .bat) that exists.
bool isRunnable(const std::wstring& path);

/// The models asked of the program so far (Claude Code has a fixed list); empty before the first answer.
std::vector<vai::agent::Model> knownModels(const vai::agent::Agent& agent);

/// Sends the request, like AIClient::generate: `config.executable` is the program, `config.model` and `config.effort` what the user chose.
unsigned generate(const vai::Config& config, const std::string& prompt, HWND window, std::wstring& reason);

/// Asks Codex for a picture: `request` is said to it as it is, the picture it makes comes as AIClient::kMessageImage with the file (Codex keeps it in
/// its own folder, under generated_images). Anything but Codex is refused with the reason.
unsigned generateImage(const vai::Config& config, const std::string& request, HWND window, std::wstring& reason);

/// Asks the program for its models; the answer comes as AIClient::kMessageModels with the identifiers.
unsigned listModels(const vai::Config& config, HWND window, std::wstring& reason);

/// Stops a request. Nothing more is delivered for that id.
void cancel(unsigned id);

} // namespace AIAgentRunner
