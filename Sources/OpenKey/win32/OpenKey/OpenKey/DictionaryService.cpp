//
//  DictionaryService.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "DictionaryService.h"
#include "FeatureIds.h"
#include "FeatureStorage.h"
#include "../../../engine/MiniJson.h"
#include <winhttp.h>
#include <map>
#include <set>

#pragma comment(lib, "winhttp.lib")

int vDictionaryHotKey = VOK_DICTIONARY_DEFAULT_HOTKEY;

namespace {

const DWORD kProtocolTls12 = 0x00000800;
const DWORD kProtocolTls13 = 0x00002000;

struct InstalledEntry {
    std::string id;
    std::string name;
    std::string shortName;
    std::string badge;
    int priority;
    bool enabled;
    uint32_t entryCount;
    uint64_t fileBytes;
    bool isCustom;
};

struct ActiveJob {
    std::string dictId;
    vdict::CatalogEntry catalog;
    volatile LONG cancelled;
    double progress;
    std::wstring statusText;
    HANDLE thread;
    HINTERNET session;
    HINTERNET connect;
    HINTERNET request;
};

CRITICAL_SECTION g_stateLock;
CRITICAL_SECTION g_engineLock;
bool g_locksReady = false;
bool g_started = false;

std::vector<vdict::CatalogEntry> g_catalog;
std::map<std::string, InstalledEntry> g_installed;
std::map<std::string, std::wstring> g_lastErrors;
std::map<std::string, ActiveJob*> g_activeJobs;
vdict::DictEngine g_engine;

HWND g_notifyHwnd = NULL;
UINT g_notifyMsg = 0;

void ensureLocks() {
    if (!g_locksReady) {
        InitializeCriticalSection(&g_stateLock);
        InitializeCriticalSection(&g_engineLock);
        g_locksReady = true;
    }
}

void postNotify() {
    HWND w = g_notifyHwnd;
    UINT m = g_notifyMsg;
    if (w && m && IsWindow(w))
        PostMessageW(w, m, 0, 0);
}

std::wstring dictFolder() {
    return FeatureStorage::subFolder(L"LookupDictionaries");
}

std::wstring safeVdictPath(const std::string& dictId) {
    std::string safe = dictId;
    for (size_t i = 0; i < safe.size(); ++i) {
        if (safe[i] == '/' || safe[i] == '\\' || safe[i] == ':' || safe[i] == '.')
            safe[i] = '_';
    }
    return dictFolder() + L"\\" + DictionaryService::utf8ToWide(safe) + L".vdict";
}

bool fileExists(const std::wstring& path) {
    DWORD attr = GetFileAttributesW(path.c_str());
    return attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY);
}

std::wstring stateFilePath() {
    return dictFolder() + L"\\state.json";
}

void persistStateLocked() {
    vjson::Value root = vjson::Value::object();
    root.set("version", vjson::Value::number(1));
    vjson::Value inst = vjson::Value::object();
    for (std::map<std::string, InstalledEntry>::const_iterator it = g_installed.begin(); it != g_installed.end(); ++it) {
        const InstalledEntry& e = it->second;
        vjson::Value o = vjson::Value::object();
        o.set("id", vjson::Value::string(e.id));
        o.set("name", vjson::Value::string(e.name));
        o.set("shortName", vjson::Value::string(e.shortName));
        o.set("badge", vjson::Value::string(e.badge));
        o.set("priority", vjson::Value::number(e.priority));
        o.set("enabled", vjson::Value::boolean(e.enabled));
        o.set("entryCount", vjson::Value::number((double)e.entryCount));
        o.set("fileBytes", vjson::Value::number((double)e.fileBytes));
        o.set("custom", vjson::Value::boolean(e.isCustom));
        inst.set(it->first, o);
    }
    root.set("installed", inst);
    FeatureStorage::writeFile(stateFilePath(), vjson::write(root, true));
}

void loadStateLocked() {
    g_installed.clear();
    std::string text = FeatureStorage::readFile(stateFilePath());
    vjson::Value root;
    if (text.empty() || !vjson::parse(text, root) || !root.isObject())
        return;
    const vjson::Value& inst = root["installed"];
    if (!inst.isObject())
        return;
    const std::vector<std::pair<std::string, vjson::Value> >& members = inst.members();
    for (size_t i = 0; i < members.size(); ++i) {
        const std::string& id = members[i].first;
        const vjson::Value& v = members[i].second;
        if (!v.isObject() || !fileExists(safeVdictPath(id)))
            continue;
        InstalledEntry e;
        e.id = id;
        e.name = v["name"].stringOr(id);
        e.shortName = v["shortName"].stringOr(e.name);
        e.badge = v["badge"].stringOr("");
        e.priority = (int)v["priority"].asNumber(250);
        e.enabled = v["enabled"].asBool(true);
        e.entryCount = (uint32_t)v["entryCount"].asNumber(0);
        e.fileBytes = (uint64_t)v["fileBytes"].asNumber(0);
        e.isCustom = v["custom"].asBool(false);
        g_installed[id] = e;
    }
}

void reloadEngine() {
    std::vector<vdict::DictionarySpec> specs;
    EnterCriticalSection(&g_stateLock);
    for (std::map<std::string, InstalledEntry>::const_iterator it = g_installed.begin(); it != g_installed.end(); ++it) {
        const InstalledEntry& e = it->second;
        std::wstring vp = safeVdictPath(e.id);
        if (!e.enabled || !fileExists(vp))
            continue;
        vdict::DictionarySpec spec;
        spec.vdictPath = DictionaryService::wideToUtf8(vp);
        spec.dictId = e.id;
        spec.displayName = e.name;
        spec.shortName = e.shortName;
        spec.badge = e.badge;
        spec.priority = e.priority;
        spec.enabled = true;
        specs.push_back(spec);
    }
    LeaveCriticalSection(&g_stateLock);

    EnterCriticalSection(&g_engineLock);
    g_engine.setDictionaries(specs);
    LeaveCriticalSection(&g_engineLock);
}

bool crackUrl(const std::string& url,
              bool& https,
              std::wstring& host,
              INTERNET_PORT& port,
              std::wstring& pathAndQuery) {
    std::wstring wurl = DictionaryService::utf8ToWide(url);
    URL_COMPONENTSW uc;
    ZeroMemory(&uc, sizeof(uc));
    uc.dwStructSize = sizeof(uc);
    uc.dwHostNameLength = (DWORD)-1;
    uc.dwUrlPathLength = (DWORD)-1;
    uc.dwExtraInfoLength = (DWORD)-1;
    if (!WinHttpCrackUrl(wurl.c_str(), (DWORD)wurl.size(), 0, &uc))
        return false;
    https = (uc.nScheme == INTERNET_SCHEME_HTTPS);
    if (!https && uc.nScheme != INTERNET_SCHEME_HTTP)
        return false;
    host.assign(uc.lpszHostName, uc.dwHostNameLength);
    if (!https && host != L"127.0.0.1" && host != L"localhost")
        return false;
    port = uc.nPort;
    pathAndQuery.assign(uc.lpszUrlPath, uc.dwUrlPathLength);
    if (uc.dwExtraInfoLength > 0)
        pathAndQuery.append(uc.lpszExtraInfo, uc.dwExtraInfoLength);
    if (pathAndQuery.empty())
        pathAndQuery = L"/";
    return !host.empty();
}

bool downloadUrlToFile(ActiveJob* job,
                       const std::string& url,
                       uint64_t expectedBytes,
                       size_t fileIdx,
                       size_t fileCount,
                       const std::wstring& destPath,
                       std::wstring& outErr) {
    bool isHttps = false;
    std::wstring host, path;
    INTERNET_PORT port = 0;
    if (!crackUrl(url, isHttps, host, port, path)) {
        outErr = L"Địa chỉ tải không hợp lệ.";
        return false;
    }

    HINTERNET hSession = WinHttpOpen(L"VOpenKey-AI/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                                     WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!hSession) {
        outErr = L"Không khởi tạo được kết nối mạng WinHTTP.";
        return false;
    }
    DWORD protos = kProtocolTls12 | kProtocolTls13;
    WinHttpSetOption(hSession, WINHTTP_OPTION_SECURE_PROTOCOLS, &protos, sizeof(protos));
    WinHttpSetTimeouts(hSession, 15000, 15000, 30000, 60000);

    HINTERNET hConnect = WinHttpConnect(hSession, host.c_str(), port, 0);
    HINTERNET hRequest = hConnect ? WinHttpOpenRequest(hConnect, L"GET", path.c_str(), NULL, WINHTTP_NO_REFERER,
                                                       WINHTTP_DEFAULT_ACCEPT_TYPES,
                                                       isHttps ? WINHTTP_FLAG_SECURE : 0) : NULL;

    EnterCriticalSection(&g_stateLock);
    job->session = hSession;
    job->connect = hConnect;
    job->request = hRequest;
    LeaveCriticalSection(&g_stateLock);

    bool ok = false;
    HANDLE hFile = INVALID_HANDLE_VALUE;
    if (hRequest && WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
        WinHttpReceiveResponse(hRequest, NULL)) {
        DWORD status = 0, sz = sizeof(status);
        WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                            WINHTTP_HEADER_NAME_BY_INDEX, &status, &sz, WINHTTP_NO_HEADER_INDEX);
        if (status >= 200 && status < 300) {
            DWORD contentLen = 0;
            sz = sizeof(contentLen);
            if (!WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_CONTENT_LENGTH | WINHTTP_QUERY_FLAG_NUMBER,
                                     WINHTTP_HEADER_NAME_BY_INDEX, &contentLen, &sz, WINHTTP_NO_HEADER_INDEX)) {
                contentLen = 0;
            }
            uint64_t totalExpected = contentLen > 0 ? (uint64_t)contentLen : expectedBytes;

            hFile = CreateFileW(destPath.c_str(), GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
            if (hFile == INVALID_HANDLE_VALUE) {
                outErr = L"Không tạo được tệp tạm khi tải.";
            } else {
                uint64_t writtenTotal = 0;
                std::vector<uint8_t> buf(65536);
                ok = true;
                while (InterlockedCompareExchange(&job->cancelled, 0, 0) == 0) {
                    DWORD avail = 0;
                    if (!WinHttpQueryDataAvailable(hRequest, &avail)) { ok = false; break; }
                    if (avail == 0) break;
                    DWORD toRead = avail > (DWORD)buf.size() ? (DWORD)buf.size() : avail;
                    DWORD got = 0;
                    if (!WinHttpReadData(hRequest, &buf[0], toRead, &got)) { ok = false; break; }
                    if (got == 0) break;
                    DWORD bw = 0;
                    if (!WriteFile(hFile, &buf[0], got, &bw, NULL) || bw != got) { ok = false; outErr = L"Lỗi ghi đĩa."; break; }
                    writtenTotal += got;

                    double fileFrac = totalExpected > 0 ? (double)writtenTotal / (double)totalExpected : 0.5;
                    if (fileFrac > 1.0) fileFrac = 1.0;
                    double overall = ((double)fileIdx + fileFrac) / (double)(fileCount > 0 ? fileCount : 1) * 0.9;
                    EnterCriticalSection(&g_stateLock);
                    job->progress = overall;
                    job->statusText = L"Đang tải " + std::to_wstring((int)(overall * 100.0)) + L"%...";
                    LeaveCriticalSection(&g_stateLock);
                    postNotify();
                }
                CloseHandle(hFile);
                if (InterlockedCompareExchange(&job->cancelled, 0, 0) != 0) {
                    ok = false;
                    outErr = L"Đã hủy.";
                } else if (!ok && outErr.empty()) {
                    outErr = L"Mất kết nối trong khi tải xuống.";
                }
            }
        } else {
            outErr = L"Máy chủ trả về lỗi HTTP " + std::to_wstring(status) + L".";
        }
    } else if (outErr.empty()) {
        outErr = L"Không kết nối được máy chủ tải từ điển.";
    }

    EnterCriticalSection(&g_stateLock);
    job->request = NULL;
    job->connect = NULL;
    job->session = NULL;
    LeaveCriticalSection(&g_stateLock);

    if (hRequest) WinHttpCloseHandle(hRequest);
    if (hConnect) WinHttpCloseHandle(hConnect);
    if (hSession) WinHttpCloseHandle(hSession);
    if (!ok) DeleteFileW(destPath.c_str());
    return ok;
}

DWORD WINAPI downloadWorker(LPVOID param) {
    ActiveJob* job = (ActiveJob*)param;
    std::wstring staging = FeatureStorage::subFolder((L"LookupDictionaries\\staging_" + DictionaryService::utf8ToWide(job->dictId)).c_str());
    std::vector<std::wstring> tempFiles;
    std::wstring errMsg;
    bool ok = true;

    for (size_t i = 0; i < job->catalog.files.size(); ++i) {
        if (InterlockedCompareExchange(&job->cancelled, 0, 0) != 0) { ok = false; break; }
        const vdict::CatalogFile& cf = job->catalog.files[i];
        std::wstring dest = staging + L"\\" + DictionaryService::utf8ToWide(cf.name);
        if (!downloadUrlToFile(job, cf.url, cf.sizeBytes, i, job->catalog.files.size(), dest, errMsg)) {
            ok = false;
            break;
        }
        tempFiles.push_back(dest);
    }

    if (ok && InterlockedCompareExchange(&job->cancelled, 0, 0) == 0) {
        EnterCriticalSection(&g_stateLock);
        job->progress = 0.93;
        job->statusText = L"Đang lập chỉ mục từ điển...";
        LeaveCriticalSection(&g_stateLock);
        postNotify();

        vdict::CompileMetadata meta;
        meta.dictId = job->catalog.id;
        meta.displayName = job->catalog.name;
        meta.shortName = job->catalog.shortName;
        meta.badge = job->catalog.badge;
        meta.sourceLang = job->catalog.sourceLang;
        meta.targetLang = job->catalog.targetLang;
        meta.author = job->catalog.author;
        meta.license = job->catalog.license;

        std::wstring vpath = safeVdictPath(job->dictId);
        std::string cppErr;
        if (tempFiles.size() == 1) {
            ok = vdict::compileLocalPathToFile(DictionaryService::wideToUtf8(tempFiles[0]), meta,
                                               DictionaryService::wideToUtf8(vpath), &cppErr);
        } else {
            ok = vdict::compileDirectoryToFile(DictionaryService::wideToUtf8(staging), meta,
                                               DictionaryService::wideToUtf8(vpath), &cppErr);
        }
        if (!ok)
            errMsg = cppErr.empty() ? L"Dữ liệu từ điển tải về không hợp lệ." : DictionaryService::utf8ToWide(cppErr);
    }

    for (size_t i = 0; i < tempFiles.size(); ++i)
        DeleteFileW(tempFiles[i].c_str());
    RemoveDirectoryW(staging.c_str());

    bool wasCancelled = InterlockedCompareExchange(&job->cancelled, 0, 0) != 0;
    if (ok && !wasCancelled) {
        vdict::VdictReader reader;
        uint32_t entries = 0;
        if (reader.openFile(DictionaryService::wideToUtf8(safeVdictPath(job->dictId))))
            entries = reader.info().entryCount;

        EnterCriticalSection(&g_stateLock);
        InstalledEntry ie;
        ie.id = job->catalog.id;
        ie.name = job->catalog.name;
        ie.shortName = job->catalog.shortName;
        ie.badge = job->catalog.badge;
        ie.priority = job->catalog.priority;
        ie.enabled = true;
        ie.entryCount = entries;
        ie.fileBytes = job->catalog.downloadBytes;
        ie.isCustom = false;
        g_installed[ie.id] = ie;
        g_lastErrors.erase(job->dictId);
        persistStateLocked();
        g_activeJobs.erase(job->dictId);
        LeaveCriticalSection(&g_stateLock);
        reloadEngine();
    } else {
        EnterCriticalSection(&g_stateLock);
        g_activeJobs.erase(job->dictId);
        if (!wasCancelled && !errMsg.empty())
            g_lastErrors[job->dictId] = errMsg;
        LeaveCriticalSection(&g_stateLock);
    }

    if (job->thread)
        CloseHandle(job->thread);
    delete job;
    postNotify();
    return 0;
}

struct ImportParams {
    std::wstring path;
    HWND notifyHwnd;
    UINT doneMsg;
};

DWORD WINAPI importWorker(LPVOID param) {
    ImportParams* p = (ImportParams*)param;
    std::wstring fname = p->path;
    size_t slash = fname.find_last_of(L"\\/");
    if (slash != std::wstring::npos) fname = fname.substr(slash + 1);
    size_t dot = fname.find_last_of(L'.');
    std::wstring stem = (dot != std::wstring::npos && dot > 0) ? fname.substr(0, dot) : fname;

    char idBuf[64];
    snprintf(idBuf, sizeof(idBuf), "custom-%lu", (unsigned long)GetTickCount());
    std::string dictId = idBuf;

    vdict::CompileMetadata meta;
    meta.dictId = dictId;
    meta.displayName = "";
    meta.shortName = DictionaryService::wideToUtf8(stem);
    meta.badge = "FILE";

    std::wstring outPath = safeVdictPath(dictId);
    std::string err;
    bool ok = vdict::compileLocalPathToFile(DictionaryService::wideToUtf8(p->path), meta,
                                            DictionaryService::wideToUtf8(outPath), &err);
    std::wstring statusText;
    if (ok) {
        vdict::VdictReader reader;
        uint32_t entryCount = 0;
        std::string finalName = meta.shortName;
        if (reader.openFile(DictionaryService::wideToUtf8(outPath))) {
            entryCount = reader.info().entryCount;
            if (!reader.info().displayName.empty() && reader.info().displayName != reader.info().dictId)
                finalName = reader.info().displayName;
        }
        WIN32_FILE_ATTRIBUTE_DATA fad;
        uint64_t fbytes = 0;
        if (GetFileAttributesExW(outPath.c_str(), GetFileExInfoStandard, &fad))
            fbytes = ((uint64_t)fad.nFileSizeHigh << 32) | fad.nFileSizeLow;

        EnterCriticalSection(&g_stateLock);
        InstalledEntry ie;
        ie.id = dictId;
        ie.name = finalName;
        ie.shortName = meta.shortName.size() <= 16 ? meta.shortName : meta.shortName.substr(0, 16);
        ie.badge = "FILE";
        ie.priority = 250;
        ie.enabled = true;
        ie.entryCount = entryCount;
        ie.fileBytes = fbytes;
        ie.isCustom = true;
        g_installed[dictId] = ie;
        persistStateLocked();
        LeaveCriticalSection(&g_stateLock);
        reloadEngine();
        statusText = L"Đã nhập \"" + DictionaryService::utf8ToWide(finalName) + L"\"";
    } else {
        statusText = err.empty()
            ? L"Không đọc được tệp hoặc thư mục từ điển StarDict."
            : DictionaryService::utf8ToWide(err);
    }

    if (p->notifyHwnd && p->doneMsg && IsWindow(p->notifyHwnd))
        PostMessageW(p->notifyHwnd, p->doneMsg, ok ? 1 : 0, (LPARAM)(new std::wstring(statusText)));
    postNotify();
    delete p;
    return 0;
}

} // namespace

namespace DictionaryService {

std::wstring utf8ToWide(const std::string& utf8) {
    if (utf8.empty()) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), (int)utf8.size(), NULL, 0);
    if (n <= 0) return std::wstring();
    std::wstring w((size_t)n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), (int)utf8.size(), &w[0], n);
    return w;
}

std::string wideToUtf8(const std::wstring& wide) {
    if (wide.empty()) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), (int)wide.size(), NULL, 0, NULL, NULL);
    if (n <= 0) return std::string();
    std::string u((size_t)n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), (int)wide.size(), &u[0], n, NULL, NULL);
    return u;
}

void start() {
    ensureLocks();
    if (g_started)
        return;
    g_started = true;
    std::string err;
    vdict::parseCatalog(FeatureStorage::resourceText(IDR_DICT_CATALOG), g_catalog, &err);
    EnterCriticalSection(&g_stateLock);
    loadStateLocked();
    LeaveCriticalSection(&g_stateLock);
    reloadEngine();
}

void stop() {
    if (!g_locksReady) return;
    std::vector<std::string> activeIds;
    EnterCriticalSection(&g_stateLock);
    for (std::map<std::string, ActiveJob*>::const_iterator it = g_activeJobs.begin(); it != g_activeJobs.end(); ++it)
        activeIds.push_back(it->first);
    LeaveCriticalSection(&g_stateLock);
    for (size_t i = 0; i < activeIds.size(); ++i)
        cancelDownload(activeIds[i]);
}

void registerNotifyWindow(HWND window, UINT message) {
    g_notifyHwnd = window;
    g_notifyMsg = message;
}

std::vector<CatalogStatusItem> allDictionaries() {
    start();
    std::vector<CatalogStatusItem> out;
    std::set<std::string> seen;

    EnterCriticalSection(&g_stateLock);
    for (size_t i = 0; i < g_catalog.size(); ++i) {
        const vdict::CatalogEntry& c = g_catalog[i];
        seen.insert(c.id);
        CatalogStatusItem item;
        item.dictId = c.id;
        item.name = utf8ToWide(c.name);
        item.shortName = utf8ToWide(c.shortName);
        item.badge = utf8ToWide(c.badge);
        item.sourceLang = c.sourceLang;
        item.targetLang = c.targetLang;
        item.author = utf8ToWide(c.author);
        item.license = utf8ToWide(c.license);
        item.description = utf8ToWide(c.description);
        item.priority = c.priority;
        item.recommended = c.recommended;
        item.isCustom = false;
        item.downloadBytes = c.downloadBytes;
        item.downloadSizeText = utf8ToWide(vdict::formatByteSize(c.downloadBytes));

        std::map<std::string, InstalledEntry>::const_iterator it = g_installed.find(c.id);
        item.installed = (it != g_installed.end()) && fileExists(safeVdictPath(c.id));
        item.enabled = item.installed && it->second.enabled;
        item.headwordCount = (item.installed && it->second.entryCount > 0) ? it->second.entryCount : c.headwordCount;

        std::map<std::string, ActiveJob*>::const_iterator jit = g_activeJobs.find(c.id);
        item.downloading = (jit != g_activeJobs.end() && InterlockedCompareExchange(&jit->second->cancelled, 0, 0) == 0);
        item.downloadProgress = item.downloading ? jit->second->progress : 0.0;
        std::map<std::string, std::wstring>::const_iterator eit = g_lastErrors.find(c.id);
        if (eit != g_lastErrors.end())
            item.errorText = eit->second;
        if (item.downloading)
            item.statusText = jit->second->statusText;
        else if (item.installed)
            item.statusText = item.enabled ? L"Đã cài & đang bật" : L"Đã cài (tạm tắt)";
        else
            item.statusText = L"Chưa tải";
        out.push_back(item);
    }

    for (std::map<std::string, InstalledEntry>::const_iterator it = g_installed.begin(); it != g_installed.end(); ++it) {
        if (seen.count(it->first) || !fileExists(safeVdictPath(it->first)))
            continue;
        const InstalledEntry& e = it->second;
        CatalogStatusItem item;
        item.dictId = e.id;
        item.name = utf8ToWide(e.name);
        item.shortName = utf8ToWide(e.shortName);
        item.badge = e.badge.empty() ? L"FILE" : utf8ToWide(e.badge);
        item.author = L"Từ điển nhập từ máy";
        item.license = L"Người dùng tự nhập";
        item.description = L"Từ điển StarDict hoặc FVDP đã nhập từ máy tính.";
        item.priority = e.priority;
        item.recommended = false;
        item.isCustom = true;
        item.headwordCount = e.entryCount;
        item.downloadBytes = e.fileBytes;
        item.downloadSizeText = e.fileBytes > 0 ? utf8ToWide(vdict::formatByteSize(e.fileBytes)) : L"Trên máy";
        item.installed = true;
        item.enabled = e.enabled;
        item.downloading = false;
        item.downloadProgress = 0.0;
        item.statusText = e.enabled ? L"Đã nhập & đang bật" : L"Đã nhập (tạm tắt)";
        out.push_back(item);
    }
    LeaveCriticalSection(&g_stateLock);
    return out;
}

std::vector<CatalogStatusItem> installedDictionaries() {
    std::vector<CatalogStatusItem> all = allDictionaries();
    std::vector<CatalogStatusItem> out;
    for (size_t i = 0; i < all.size(); ++i) {
        if (all[i].installed) out.push_back(all[i]);
    }
    return out;
}

bool hasInstalledDictionary() {
    start();
    EnterCriticalSection(&g_stateLock);
    bool any = !g_installed.empty();
    LeaveCriticalSection(&g_stateLock);
    return any;
}

bool hasActiveDownload() {
    if (!g_locksReady) return false;
    EnterCriticalSection(&g_stateLock);
    bool active = !g_activeJobs.empty();
    LeaveCriticalSection(&g_stateLock);
    return active;
}

void downloadDictionaries(const std::vector<std::string>& dictIds) {
    start();
    for (size_t i = 0; i < dictIds.size(); ++i) {
        const vdict::CatalogEntry* ce = vdict::findCatalogEntry(g_catalog, dictIds[i]);
        if (!ce) continue;
        EnterCriticalSection(&g_stateLock);
        if (g_activeJobs.find(ce->id) == g_activeJobs.end()) {
            ActiveJob* job = new ActiveJob();
            job->dictId = ce->id;
            job->catalog = *ce;
            job->cancelled = 0;
            job->progress = 0.0;
            job->statusText = L"Đang chuẩn bị tải...";
            job->thread = NULL;
            job->session = NULL;
            job->connect = NULL;
            job->request = NULL;
            g_lastErrors.erase(ce->id);
            g_activeJobs[ce->id] = job;
            job->thread = CreateThread(NULL, 0, downloadWorker, job, 0, NULL);
            if (!job->thread) {
                g_activeJobs.erase(ce->id);
                delete job;
            }
        }
        LeaveCriticalSection(&g_stateLock);
    }
    postNotify();
}

void cancelDownload(const std::string& dictId) {
    if (!g_locksReady) return;
    EnterCriticalSection(&g_stateLock);
    std::map<std::string, ActiveJob*>::iterator it = g_activeJobs.find(dictId);
    if (it != g_activeJobs.end()) {
        InterlockedExchange(&it->second->cancelled, 1);
        HINTERNET r = it->second->request;
        HINTERNET c = it->second->connect;
        HINTERNET s = it->second->session;
        if (r) WinHttpCloseHandle(r);
        if (c) WinHttpCloseHandle(c);
        if (s) WinHttpCloseHandle(s);
    }
    LeaveCriticalSection(&g_stateLock);
    postNotify();
}

void setDictionaryEnabled(const std::string& dictId, bool enabled) {
    start();
    EnterCriticalSection(&g_stateLock);
    std::map<std::string, InstalledEntry>::iterator it = g_installed.find(dictId);
    if (it != g_installed.end()) {
        it->second.enabled = enabled;
        persistStateLocked();
    }
    LeaveCriticalSection(&g_stateLock);
    reloadEngine();
    postNotify();
}

void removeDictionary(const std::string& dictId) {
    cancelDownload(dictId);
    DeleteFileW(safeVdictPath(dictId).c_str());
    EnterCriticalSection(&g_stateLock);
    g_installed.erase(dictId);
    g_lastErrors.erase(dictId);
    persistStateLocked();
    LeaveCriticalSection(&g_stateLock);
    reloadEngine();
    postNotify();
}

void importLocalPath(const std::wstring& path, HWND notifyHwnd, UINT doneMsg) {
    start();
    ImportParams* p = new ImportParams();
    p->path = path;
    p->notifyHwnd = notifyHwnd;
    p->doneMsg = doneMsg;
    HANDLE t = CreateThread(NULL, 0, importWorker, p, 0, NULL);
    if (t) CloseHandle(t);
    else delete p;
}

std::vector<vdict::SearchItem> search(const std::string& query,
                                      const std::string& filterDictId,
                                      size_t maxResults) {
    start();
    EnterCriticalSection(&g_engineLock);
    std::vector<vdict::SearchItem> res = g_engine.search(query, filterDictId, maxResults);
    LeaveCriticalSection(&g_engineLock);
    return res;
}

std::vector<vdict::DefinitionSection> loadDefinitions(const vdict::SearchItem& item,
                                                      const std::string& filterDictId) {
    start();
    EnterCriticalSection(&g_engineLock);
    std::vector<vdict::DefinitionSection> res = g_engine.loadDefinitions(item, filterDictId);
    LeaveCriticalSection(&g_engineLock);
    return res;
}

} // namespace DictionaryService
