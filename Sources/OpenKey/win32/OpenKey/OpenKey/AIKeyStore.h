//
//  AIKeyStore.h
//  VOpenKey AI, Windows
//
//  The API keys of the AI services. A key is saved only encrypted with the Windows account of the user (DPAPI, the same
//  protection Windows gives to saved passwords): another user of the computer, or a copy of the registry on another computer,
//  cannot read it. It is never written in the settings in the clear, never in a log, and is given out only to make a request.
//
#pragma once
#include "stdafx.h"

namespace AIKeyStore {

/// The key of a service (its id, "openai"...), empty when there is none or it cannot be decrypted (another account).
std::string keyForProvider(const std::string& providerId);
bool hasKeyForProvider(const std::string& providerId);

/// Saves the key; an empty key removes it. False when it could not be saved.
bool setKeyForProvider(const std::string& providerId, const std::string& key);

} // namespace AIKeyStore
