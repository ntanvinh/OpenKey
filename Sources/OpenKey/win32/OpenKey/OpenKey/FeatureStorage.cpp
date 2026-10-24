//
//  FeatureStorage.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "FeatureStorage.h"
#include <shlobj.h>

namespace FeatureStorage {

std::wstring dataFolder() {
    wchar_t path[MAX_PATH] = {0};
    if (FAILED(SHGetFolderPathW(NULL, CSIDL_APPDATA | CSIDL_FLAG_CREATE, NULL, SHGFP_TYPE_CURRENT, path)))
        return L"";
    std::wstring folder = std::wstring(path) + L"\\VOpenKey";
    CreateDirectoryW(folder.c_str(), NULL);
    return folder;
}

std::wstring subFolder(const wchar_t* name) {
    std::wstring base = dataFolder();
    if (base.empty())
        return L"";
    std::wstring folder = base + L"\\" + name;
    CreateDirectoryW(folder.c_str(), NULL);
    return folder;
}

std::string readFile(const std::wstring& path) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
                              FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE)
        return std::string();
    std::string content;
    char buffer[65536];
    DWORD got = 0;
    while (ReadFile(file, buffer, sizeof(buffer), &got, NULL) && got > 0)
        content.append(buffer, got);
    CloseHandle(file);
    //a file written by Notepad may start with a byte order mark
    if (content.size() >= 3 && (unsigned char)content[0] == 0xEF && (unsigned char)content[1] == 0xBB &&
        (unsigned char)content[2] == 0xBF)
        content.erase(0, 3);
    return content;
}

bool writeFile(const std::wstring& path, const std::string& content) {
    std::wstring temporary = path + L".tmp";
    HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE)
        return false;
    size_t done = 0;
    bool ok = true;
    while (done < content.size()) {
        DWORD wrote = 0;
        DWORD chunk = (DWORD)(content.size() - done > 1048576 ? 1048576 : content.size() - done);
        if (!WriteFile(file, content.data() + done, chunk, &wrote, NULL) || wrote == 0) {
            ok = false;
            break;
        }
        done += wrote;
    }
    ok = ok && FlushFileBuffers(file);
    CloseHandle(file);
    if (!ok || !MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(temporary.c_str());
        return false;
    }
    return true;
}

static const wchar_t kSettingsKey[] = L"SOFTWARE\\TuyenMai\\OpenKey";

static HKEY openSettings(REGSAM access) {
    HKEY key = NULL;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kSettingsKey, 0, NULL, REG_OPTION_NON_VOLATILE, access, NULL, &key, NULL) != ERROR_SUCCESS)
        return NULL;
    return key;
}

std::vector<unsigned char> getSettingBytes(const wchar_t* name) {
    std::vector<unsigned char> bytes;
    HKEY key = openSettings(KEY_QUERY_VALUE);
    if (!key)
        return bytes;
    DWORD size = 0, type = 0;
    if (RegQueryValueExW(key, name, NULL, &type, NULL, &size) == ERROR_SUCCESS && size > 0 && size < (1u << 20)) {
        bytes.resize(size);
        if (RegQueryValueExW(key, name, NULL, &type, bytes.data(), &size) != ERROR_SUCCESS)
            bytes.clear();
        else
            bytes.resize(size);
    }
    RegCloseKey(key);
    return bytes;
}

void setSettingBytes(const wchar_t* name, const std::vector<unsigned char>& bytes) {
    HKEY key = openSettings(KEY_SET_VALUE);
    if (!key)
        return;
    RegSetValueExW(key, name, 0, REG_BINARY, bytes.data(), (DWORD)bytes.size());
    RegCloseKey(key);
}

std::string getSettingText(const wchar_t* name, const std::string& fallback) {
    std::vector<unsigned char> bytes = getSettingBytes(name);
    if (bytes.size() < sizeof(wchar_t))
        return fallback;
    std::wstring text((const wchar_t*)bytes.data(), bytes.size() / sizeof(wchar_t));
    while (!text.empty() && text[text.size() - 1] == L'\0')
        text.erase(text.size() - 1);
    return wideStringToUtf8(text);
}

void setSettingText(const wchar_t* name, const std::string& value) {
    HKEY key = openSettings(KEY_SET_VALUE);
    if (!key)
        return;
    std::wstring text = utf8ToWideString(value);
    RegSetValueExW(key, name, 0, REG_SZ, (const BYTE*)text.c_str(), (DWORD)((text.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(key);
}

void deleteSetting(const wchar_t* name) {
    HKEY key = openSettings(KEY_SET_VALUE);
    if (!key)
        return;
    RegDeleteValueW(key, name);
    RegCloseKey(key);
}

std::string resourceText(int id) {
    HRSRC found = FindResourceW(NULL, MAKEINTRESOURCEW(id), (LPCWSTR)RT_RCDATA);
    if (!found)
        return std::string();
    HGLOBAL loaded = LoadResource(NULL, found);
    DWORD size = SizeofResource(NULL, found);
    const char* bytes = loaded ? (const char*)LockResource(loaded) : NULL;
    if (!bytes)
        return std::string();
    return std::string(bytes, size);
}

} // namespace FeatureStorage
