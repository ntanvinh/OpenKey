//
//  SnippetService.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "SnippetService.h"
#include "FeatureStorage.h"
#include <objbase.h>
#include <memory>

#pragma comment(lib, "ole32.lib")

int vSnippetsEnabled = 1;
int vSnippetHotKey = 0x353; //Ctrl+Alt+S

namespace {

const UINT kSaveDelayMs = 400;

std::unique_ptr<vsnippet::Store> g_store;
UINT_PTR g_saveTimer = 0;

std::wstring snippetFile() {
    return FeatureStorage::subFolder(L"Snippets") + L"\\snippets.json";
}

void CALLBACK saveTimerProc(HWND, UINT, UINT_PTR, DWORD) {
    SnippetService::flush();
}

} // namespace

namespace SnippetService {

std::string defaultsText() {
    return FeatureStorage::resourceText(IDR_SNIPPETS_DEFAULT);
}

vsnippet::Store& store() {
    if (!g_store) {
        g_store.reset(new vsnippet::Store());
        std::wstring file = snippetFile();
        std::string text = FeatureStorage::readFile(file);
        bool exists = GetFileAttributesW(file.c_str()) != INVALID_FILE_ATTRIBUTES;
        g_store->load(text, exists, defaultsText());
        if (g_store->fileWasUnreadable()) {
            //not something this program wrote and not readable: keep it where the user can find it, then start over
            wchar_t stamp[32];
            wsprintfW(stamp, L"%u", (unsigned)GetTickCount());
            std::wstring broken = FeatureStorage::subFolder(L"Snippets") + L"\\snippets-unreadable-" + stamp + L".json";
            MoveFileExW(file.c_str(), broken.c_str(), MOVEFILE_REPLACE_EXISTING);
        }
        if (g_store->needsSave())
            changed();
    }
    return *g_store;
}

void changed() {
    if (g_saveTimer)
        return;
    g_saveTimer = SetTimer(NULL, 0, kSaveDelayMs, saveTimerProc);
}

void flush() {
    if (g_saveTimer) {
        KillTimer(NULL, g_saveTimer);
        g_saveTimer = 0;
    }
    if (!g_store || !g_store->needsSave())
        return;
    if (FeatureStorage::writeFile(snippetFile(), g_store->serialize()))
        g_store->markSaved();
}

std::string newIdentifier() {
    GUID guid;
    if (FAILED(CoCreateGuid(&guid))) {
        wchar_t fallback[40];
        wsprintfW(fallback, L"t%u-%u", (unsigned)GetTickCount(), (unsigned)GetCurrentProcessId());
        return "user." + wideStringToUtf8(fallback);
    }
    wchar_t text[64] = {0};
    StringFromGUID2(guid, text, 64);
    return "user." + wideStringToUtf8(text);
}

} // namespace SnippetService
