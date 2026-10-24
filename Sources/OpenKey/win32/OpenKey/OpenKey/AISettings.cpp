//
//  AISettings.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "AISettings.h"
#include "AIKeyStore.h"
#include "AIText.h"
#include "FeatureStorage.h"
#include "FeatureActions.h"

int vAICopySelection = 1;

namespace {

std::wstring perProvider(const vai::Provider& provider, const wchar_t* what) {
    return L"AI." + utf8ToWideString(provider.id) + L"." + what;
}

std::string trim(const std::string& s) {
    size_t a = 0, b = s.size();
    while (a < b && (s[a] == ' ' || s[a] == '\t' || s[a] == '\r' || s[a] == '\n')) a++;
    while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t' || s[b - 1] == '\r' || s[b - 1] == '\n')) b--;
    return s.substr(a, b - a);
}

//an empty value, or the value the service has itself, is not kept: the service's own then follows when it changes
void saveOrForget(const std::wstring& name, const std::string& value, const std::string& builtIn) {
    std::string trimmed = trim(value);
    if (trimmed.empty() || trimmed == builtIn)
        FeatureStorage::deleteSetting(name.c_str());
    else
        FeatureStorage::setSettingText(name.c_str(), trimmed);
}

} // namespace

namespace AISettings {

void load() {
    APP_GET_DATA(vAICopySelection, 1);
}

std::string defaultSystemPrompt() {
    return wideStringToUtf8(
        L"Bạn là trợ lý viết văn bản. Làm đúng yêu cầu của người dùng và chỉ trả về nội dung được yêu cầu, "
        L"không mở đầu, không giải thích thêm, không đặt trong dấu ngoặc kép hay khối code trừ khi được yêu cầu. "
        L"Giữ ngôn ngữ của người dùng, trừ khi họ yêu cầu ngôn ngữ khác.");
}

std::string systemPrompt() {
    std::string saved = FeatureStorage::getSettingText(L"AI.systemPrompt");
    return saved.empty() ? defaultSystemPrompt() : saved;
}

void setSystemPrompt(const std::string& prompt) {
    saveOrForget(L"AI.systemPrompt", prompt, defaultSystemPrompt());
}

std::string providerId() {
    std::string saved = FeatureStorage::getSettingText(L"AI.provider");
    return vai::findProvider(saved) ? saved : vai::defaultProvider().id;
}

void setProviderId(const std::string& id) {
    if (vai::findProvider(id))
        FeatureStorage::setSettingText(L"AI.provider", id);
}

const vai::Provider& provider() {
    const vai::Provider* found = vai::findProvider(providerId());
    return found ? *found : vai::defaultProvider();
}

std::string baseUrlFor(const vai::Provider& provider) {
    std::string saved = FeatureStorage::getSettingText(perProvider(provider, L"baseURL").c_str());
    return saved.empty() ? provider.baseUrl : saved;
}

void setBaseUrl(const vai::Provider& provider, const std::string& baseUrl) {
    saveOrForget(perProvider(provider, L"baseURL"), baseUrl, provider.baseUrl);
}

std::string modelFor(const vai::Provider& provider) {
    std::string saved = FeatureStorage::getSettingText(perProvider(provider, L"model").c_str());
    return saved.empty() ? provider.model : saved;
}

void setModel(const vai::Provider& provider, const std::string& model) {
    saveOrForget(perProvider(provider, L"model"), model, provider.model);
}

bool isReady(const vai::Provider& provider) {
    if (provider.needsKey && !AIKeyStore::hasKeyForProvider(provider.id))
        return false;
    vai::AddressProblem problem;
    return !vai::cleanBaseUrl(baseUrlFor(provider), problem).empty() && !modelFor(provider).empty();
}

bool configurationFor(const vai::Provider& provider, bool requireModel, vai::Config& out, std::wstring& reason) {
    vai::AddressProblem problem;
    std::string address = vai::cleanBaseUrl(baseUrlFor(provider), problem);
    if (address.empty()) {
        reason = AIText::forAddressProblem(problem);
        return false;
    }
    std::string model = modelFor(provider);
    if (requireModel && model.empty()) {
        reason = L"Chưa chọn model. Vào Cài đặt AI để nhập tên model.";
        return false;
    }
    std::string key = AIKeyStore::keyForProvider(provider.id);
    if (provider.needsKey && key.empty()) {
        vai::Config forText;
        forText.provider = provider;
        reason = AIText::forError(vai::Error(vai::ErrorCode::NoKey), forText);
        return false;
    }
    out = vai::Config();
    out.provider = provider;
    out.baseUrl = address;
    out.model = model;
    out.key = key;
    out.systemPrompt = systemPrompt();
    return true;
}

void resetToDefaults() {
    FeatureStorage::deleteSetting(L"AI.provider");
    FeatureStorage::deleteSetting(L"AI.systemPrompt");
    const std::vector<vai::Provider>& all = vai::providers();
    for (size_t i = 0; i < all.size(); i++) {
        FeatureStorage::deleteSetting(perProvider(all[i], L"baseURL").c_str());
        FeatureStorage::deleteSetting(perProvider(all[i], L"model").c_str());
    }
}

} // namespace AISettings
