//
//  AIText.h
//  VOpenKey AI, Windows
//
//  The sentences the user reads about the AI: what went wrong and what to do about it. The portable protocol code gives codes
//  and details; the words are here, in Vietnamese like the rest of the Windows program.
//
#pragma once
#include "stdafx.h"
#include "../../../engine/AIProtocol.h"

namespace AIText {

std::wstring forAddressProblem(vai::AddressProblem problem);
std::wstring forKeyProblem(vai::KeyProblem problem);

/// The message of an error of a request, for the configuration that made it.
std::wstring forError(const vai::Error& error, const vai::Config& config);

/// A line under the name of a service in the settings, empty when there is nothing to add.
std::wstring noteForProvider(const std::string& providerId);

/// The name of a service as the menu shows it.
std::wstring displayName(const vai::Provider& provider);

} // namespace AIText
