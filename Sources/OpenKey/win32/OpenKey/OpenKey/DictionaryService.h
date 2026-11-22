//
//  DictionaryService.h
//  VOpenKey AI, Windows
//
//  Manages open-source dictionary catalog, downloads via WinHTTP, StarDict/FVDP local imports,
//  and sub-millisecond multi-dictionary search on Windows.
//
#pragma once
#include "stdafx.h"
#include "../../../engine/DictCatalog.h"
#include "../../../engine/DictStore.h"

#define VOK_DICTIONARY_DEFAULT_HOTKEY 0x344 // Ctrl+Alt+D
extern int vDictionaryHotKey;

namespace DictionaryService {

struct CatalogStatusItem {
    std::string dictId;
    std::wstring name;
    std::wstring shortName;
    std::wstring badge;
    std::string sourceLang;
    std::string targetLang;
    std::wstring author;
    std::wstring license;
    std::wstring description;
    int priority;
    bool recommended;
    bool isCustom;
    uint64_t headwordCount;
    uint64_t downloadBytes;
    std::wstring downloadSizeText;
    bool installed;
    bool enabled;
    bool downloading;
    double downloadProgress; // 0..1
    std::wstring statusText;
    std::wstring errorText;
};

void start();
void stop();

void registerNotifyWindow(HWND window, UINT message);

std::vector<CatalogStatusItem> allDictionaries();
std::vector<CatalogStatusItem> installedDictionaries();
bool hasInstalledDictionary();
bool hasActiveDownload();

void downloadDictionaries(const std::vector<std::string>& dictIds);
void cancelDownload(const std::string& dictId);
void setDictionaryEnabled(const std::string& dictId, bool enabled);
void removeDictionary(const std::string& dictId);

/// Imports a local .zip, .ifo, .txt, or folder asynchronously; posts `doneMsg` (WPARAM = 1 ok / 0 fail, LPARAM = new std::wstring* statusText).
void importLocalPath(const std::wstring& path, HWND notifyHwnd, UINT doneMsg);

std::vector<vdict::SearchItem> search(const std::string& query,
                                      const std::string& filterDictId,
                                      size_t maxResults = 80);

std::vector<vdict::DefinitionSection> loadDefinitions(const vdict::SearchItem& item,
                                                      const std::string& filterDictId = "");

std::wstring utf8ToWide(const std::string& utf8);
std::string wideToUtf8(const std::wstring& wide);

} // namespace DictionaryService
