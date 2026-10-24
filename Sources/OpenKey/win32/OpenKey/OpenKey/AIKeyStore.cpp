//
//  AIKeyStore.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "AIKeyStore.h"
#include "FeatureStorage.h"
#include <wincrypt.h>

#pragma comment(lib, "crypt32.lib")

namespace {

//DPAPI keeps the blob for this account; the entropy ties it to this program, so another program of the same user does not
//open it by calling the same function with no entropy
const BYTE kEntropy[] = {'V', 'O', 'p', 'e', 'n', 'K', 'e', 'y', 'A', 'I', '.', 'k', 'e', 'y', 's'};

std::wstring valueName(const std::string& providerId) {
    return L"AIKey." + utf8ToWideString(providerId);
}

} // namespace

namespace AIKeyStore {

std::string keyForProvider(const std::string& providerId) {
    std::vector<unsigned char> stored = FeatureStorage::getSettingBytes(valueName(providerId).c_str());
    if (stored.empty())
        return std::string();
    DATA_BLOB in = {(DWORD)stored.size(), stored.data()};
    DATA_BLOB entropy = {(DWORD)sizeof(kEntropy), (BYTE*)kEntropy};
    DATA_BLOB out = {0, NULL};
    if (!CryptUnprotectData(&in, NULL, &entropy, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &out))
        return std::string();
    std::string key((const char*)out.pbData, out.cbData);
    SecureZeroMemory(out.pbData, out.cbData);
    LocalFree(out.pbData);
    return key;
}

bool hasKeyForProvider(const std::string& providerId) {
    return !keyForProvider(providerId).empty();
}

bool setKeyForProvider(const std::string& providerId, const std::string& key) {
    std::wstring name = valueName(providerId);
    if (key.empty()) {
        FeatureStorage::deleteSetting(name.c_str());
        return true;
    }
    DATA_BLOB in = {(DWORD)key.size(), (BYTE*)key.data()};
    DATA_BLOB entropy = {(DWORD)sizeof(kEntropy), (BYTE*)kEntropy};
    DATA_BLOB out = {0, NULL};
    if (!CryptProtectData(&in, L"VOpenKey AI", &entropy, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &out))
        return false;
    FeatureStorage::setSettingBytes(name.c_str(), std::vector<unsigned char>(out.pbData, out.pbData + out.cbData));
    LocalFree(out.pbData);
    return true;
}

} // namespace AIKeyStore
