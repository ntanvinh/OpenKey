//
//  WordSpeaker.cpp
//  VOpenKey AI, Windows
//
//  ASCII only: the messages the user reads are in the window that calls this.
//
#include "stdafx.h"
#include "WordSpeaker.h"
#include <sapi.h>

#pragma comment(lib, "sapi.lib")
#pragma comment(lib, "ole32.lib")

namespace {

ISpVoice* g_voice = NULL;

//The first installed voice for English: United States first (the pronunciation most dictionaries print), then United Kingdom,
//then any voice that lists English (language id 9) among its languages. NULL when there is none.
ISpObjectToken* findEnglishVoice() {
    ISpObjectTokenCategory* category = NULL;
    if (FAILED(CoCreateInstance(CLSID_SpObjectTokenCategory, NULL, CLSCTX_ALL, IID_ISpObjectTokenCategory, (void**)&category)) || !category)
        return NULL;
    ISpObjectToken* found = NULL;
    if (SUCCEEDED(category->SetId(SPCAT_VOICES, FALSE))) {
        const wchar_t* wanted[] = {L"Language=409", L"Language=809", L"Language=9"};
        for (int i = 0; i < 3 && found == NULL; i++) {
            IEnumSpObjectTokens* tokens = NULL;
            if (SUCCEEDED(category->EnumTokens(wanted[i], NULL, &tokens)) && tokens) {
                ULONG fetched = 0;
                ISpObjectToken* token = NULL;
                if (tokens->Next(1, &token, &fetched) == S_OK && fetched == 1)
                    found = token;
                tokens->Release();
            }
        }
    }
    category->Release();
    return found;
}

bool ensureVoice() {
    if (g_voice != NULL)
        return true;
    //S_FALSE or a different mode: COM is there already, it is used as it is. It is not uninitialised: the voice lives as long as the program.
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    ISpObjectToken* token = findEnglishVoice();
    if (token == NULL)
        return false;
    ISpVoice* voice = NULL;
    if (FAILED(CoCreateInstance(CLSID_SpVoice, NULL, CLSCTX_ALL, IID_ISpVoice, (void**)&voice)) || voice == NULL) {
        token->Release();
        return false;
    }
    voice->SetVoice(token);
    token->Release();
    voice->SetRate(-1);     //a little slower than the default so that a learner hears each sound
    g_voice = voice;
    return true;
}

}

namespace WordSpeaker {

bool speak(const std::wstring& text) {
    if (text.empty() || !ensureVoice())
        return false;
    //asynchronous (the window stays usable); what is being read is dropped first; the text is plain, not SAPI XML
    return SUCCEEDED(g_voice->Speak(text.c_str(), (DWORD)(SPF_ASYNC | SPF_PURGEBEFORESPEAK | SPF_IS_NOT_XML), NULL));
}

void stop() {
    if (g_voice != NULL)
        g_voice->Speak(NULL, (DWORD)SPF_PURGEBEFORESPEAK, NULL);
}

}
