//
//  AISettings.h
//  VOpenKey AI, Windows
//
//  What the user chose for the AI assistant: which service, which model, the address of the server and the instruction
//  given with every request. Saved in the registry like the other settings, except the API key (AIKeyStore). The shortcut
//  and the switch of the assistant are in FeatureActions (vAIHotKey, vAIEnabled).
//
#pragma once
#include "stdafx.h"
#include "../../../engine/AIProtocol.h"

extern int vAICopySelection;   //copy the selected text with Ctrl+C when the shortcut opens the assistant

namespace AISettings {

void load();

/// What the assistant is told before every request.
std::string defaultSystemPrompt();
std::string systemPrompt();
void setSystemPrompt(const std::string& prompt);   //empty, or the default one, brings the default back

/// The service in use.
std::string providerId();
void setProviderId(const std::string& id);
const vai::Provider& provider();

/// Address and model of a service as the user set them, the service's own when the user did not.
std::string baseUrlFor(const vai::Provider& provider);
void setBaseUrl(const vai::Provider& provider, const std::string& baseUrl);
std::string modelFor(const vai::Provider& provider);
void setModel(const vai::Provider& provider, const std::string& model);

/// The service can be used now: it has a key (or does not need one), an address that is allowed and a model.
bool isReady(const vai::Provider& provider);

/// The configuration of a service with its key. False with the reason (ready to show) when it cannot be used. With
/// `requireModel` false the model may be empty: to list the models a service has.
bool configurationFor(const vai::Provider& provider, bool requireModel, vai::Config& out, std::wstring& reason);

/// Forgets the choices (service, models, addresses, instruction). The keys stay where they are.
void resetToDefaults();

} // namespace AISettings
