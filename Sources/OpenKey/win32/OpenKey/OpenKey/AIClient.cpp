//
//  AIClient.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "AIClient.h"
#include "AIText.h"
#include <winhttp.h>
#include <map>

#pragma comment(lib, "winhttp.lib")

namespace {

//constants that older headers do not have
const DWORD kProtocolTls11 = 0x00000200;
const DWORD kProtocolTls12 = 0x00000800;
const DWORD kProtocolTls13 = 0x00002000;
const DWORD kDisableCookies = 0x00000001;
const DWORD kDisableAuthentication = 0x00000004;
const DWORD kDisableRedirects = 0x00000080;
const DWORD kMaxBodyBytes = 1u << 20;   //an error or a complete answer: whole, but not without limit

struct Job {
    unsigned id;
    bool listModels;
    vai::Config config;
    vai::HttpRequest request;
    HWND window;
    volatile LONG cancelled;
    HINTERNET request_handle;   //guarded by g_lock: closing it makes a blocked read return
    HINTERNET connection;
    HINTERNET session;
};

CRITICAL_SECTION g_lock;
bool g_lockReady = false;
std::map<unsigned, Job*> g_jobs;
unsigned g_nextId = 1;

void ensureLock() {
    if (!g_lockReady) {
        InitializeCriticalSection(&g_lock);
        g_lockReady = true;
    }
}

bool isCancelled(Job* job) {
    return InterlockedCompareExchange(&job->cancelled, 0, 0) != 0;
}

void post(Job* job, UINT message, LPARAM payload) {
    if (!job->window || isCancelled(job)) {
        //nobody takes it: free it here
        if (message == AIClient::kMessageText) delete (std::wstring*)payload;
        else if (message == AIClient::kMessageDone) delete (AIClient::Done*)payload;
        else if (message == AIClient::kMessageModels) delete (AIClient::Models*)payload;
        return;
    }
    if (!PostMessageW(job->window, message, (WPARAM)job->id, payload)) {
        if (message == AIClient::kMessageText) delete (std::wstring*)payload;
        else if (message == AIClient::kMessageDone) delete (AIClient::Done*)payload;
        else if (message == AIClient::kMessageModels) delete (AIClient::Models*)payload;
    }
}

void finish(Job* job, const vai::Error& error, const std::wstring& message) {
    AIClient::Done* done = new AIClient::Done();
    done->error = error;
    done->message = message;
    post(job, AIClient::kMessageDone, (LPARAM)done);
}

void finishModels(Job* job, const std::vector<std::string>& names, const vai::Error& error, const std::wstring& message) {
    AIClient::Models* models = new AIClient::Models();
    models->names = names;
    models->error = error;
    models->message = message;
    post(job, AIClient::kMessageModels, (LPARAM)models);
}

//what went wrong on the way, in words
vai::Error networkError(DWORD code, Job* job, std::wstring& message) {
    std::wstring host = utf8ToWideString(vai::parseUrl(job->request.url).host);
    if (host.empty())
        host = L"máy chủ";
    if (isCancelled(job)) {
        message = L"Đã dừng.";
        return vai::Error(vai::ErrorCode::Cancelled);
    }
    switch (code) {
    case ERROR_WINHTTP_TIMEOUT:
        message = L"Máy chủ không trả lời kịp. Thử lại, hoặc kiểm tra mạng.";
        break;
    case ERROR_WINHTTP_NAME_NOT_RESOLVED:
    case ERROR_WINHTTP_CANNOT_CONNECT:
    case ERROR_WINHTTP_CONNECTION_ERROR:
        if (job->config.provider.isLocal)
            message = L"Không kết nối được tới " + host + L". " + AIText::displayName(job->config.provider) + L" đã chạy chưa, và địa chỉ có đúng không?";
        else
            message = L"Không kết nối được tới " + host + L". Kiểm tra mạng và địa chỉ máy chủ.";
        break;
    case ERROR_WINHTTP_SECURE_FAILURE:
    case ERROR_WINHTTP_SECURE_CERT_DATE_INVALID:
    case ERROR_WINHTTP_SECURE_CERT_CN_INVALID:
    case ERROR_WINHTTP_SECURE_INVALID_CA:
    case ERROR_WINHTTP_SECURE_CERT_REV_FAILED:
    case ERROR_WINHTTP_SECURE_INVALID_CERT:
    case ERROR_WINHTTP_SECURE_CERT_REVOKED:
    case ERROR_WINHTTP_SECURE_CERT_WRONG_USAGE:
        message = L"Không thiết lập được kết nối an toàn tới " + host + L" (chứng chỉ không hợp lệ).";
        break;
    default:
        message = L"Lỗi mạng (mã " + std::to_wstring((unsigned long)code) + L"). Kiểm tra kết nối rồi thử lại.";
    }
    return vai::Error(vai::ErrorCode::Network, wideStringToUtf8(message));
}

bool queryNumber(HINTERNET request, DWORD what, DWORD& value) {
    DWORD size = sizeof(value);
    return WinHttpQueryHeaders(request, what | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX, &value, &size,
                               WINHTTP_NO_HEADER_INDEX) != FALSE;
}

std::wstring queryString(HINTERNET request, DWORD what) {
    DWORD size = 0;
    WinHttpQueryHeaders(request, what, WINHTTP_HEADER_NAME_BY_INDEX, NULL, &size, WINHTTP_NO_HEADER_INDEX);
    if (size == 0 || GetLastError() != ERROR_INSUFFICIENT_BUFFER)
        return L"";
    std::wstring text(size / sizeof(wchar_t), L'\0');
    if (!WinHttpQueryHeaders(request, what, WINHTTP_HEADER_NAME_BY_INDEX, &text[0], &size, WINHTTP_NO_HEADER_INDEX))
        return L"";
    text.resize(size / sizeof(wchar_t));
    return text;
}

void closeHandles(Job* job) {
    EnterCriticalSection(&g_lock);
    HINTERNET handles[3] = {job->request_handle, job->connection, job->session};
    job->request_handle = job->connection = job->session = NULL;
    LeaveCriticalSection(&g_lock);
    for (int i = 0; i < 3; i++) {
        if (handles[i])
            WinHttpCloseHandle(handles[i]);
    }
}

//Everything of one request, on its own thread
void run(Job* job) {
    vai::Url url = vai::parseUrl(job->request.url);
    std::wstring userAgent = L"VOpenKey AI/" + OpenKeyHelper::getVersionString();
    std::wstring done_message;

    HINTERNET session = WinHttpOpen(userAgent.c_str(), WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME,
                                    WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session) {
        std::wstring message;
        vai::Error error = networkError(GetLastError(), job, message);
        if (job->listModels) finishModels(job, std::vector<std::string>(), error, message); else finish(job, error, message);
        return;
    }
    //TLS 1.2 and 1.3 where the system knows them (older Windows 7 does not know all of them)
    DWORD protocols = kProtocolTls11 | kProtocolTls12 | kProtocolTls13;
    if (!WinHttpSetOption(session, WINHTTP_OPTION_SECURE_PROTOCOLS, &protocols, sizeof(protocols))) {
        protocols = kProtocolTls11 | kProtocolTls12;
        WinHttpSetOption(session, WINHTTP_OPTION_SECURE_PROTOCOLS, &protocols, sizeof(protocols));
    }
    //the time between two pieces of data, not for the whole answer
    WinHttpSetTimeouts(session, 10000, 15000, 30000, job->listModels ? 20000 : 45000);

    std::wstring host = utf8ToWideString(url.host);
    HINTERNET connection = WinHttpConnect(session, host.c_str(), (INTERNET_PORT)url.port, 0);
    HINTERNET request = NULL;
    if (connection) {
        std::wstring path = utf8ToWideString(url.pathAndQuery);
        //the address was written with its percent signs already: WinHTTP must not change it again
        request = WinHttpOpenRequest(connection, utf8ToWideString(job->request.method).c_str(), path.c_str(), NULL, WINHTTP_NO_REFERER,
                                     WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_ESCAPE_DISABLE | (url.scheme == "https" ? WINHTTP_FLAG_SECURE : 0));
    }
    EnterCriticalSection(&g_lock);
    job->session = session;
    job->connection = connection;
    job->request_handle = request;
    LeaveCriticalSection(&g_lock);

    auto fail = [&](DWORD code) {
        std::wstring message;
        vai::Error error = networkError(code, job, message);
        if (job->listModels) finishModels(job, std::vector<std::string>(), error, message); else finish(job, error, message);
        closeHandles(job);
    };
    if (!request) {
        fail(GetLastError());
        return;
    }
    DWORD disabled = kDisableRedirects | kDisableCookies | kDisableAuthentication;
    WinHttpSetOption(request, WINHTTP_OPTION_DISABLE_FEATURE, &disabled, sizeof(disabled));

    std::wstring headers;
    for (size_t i = 0; i < job->request.headers.size(); i++)
        headers += utf8ToWideString(job->request.headers[i].first) + L": " + utf8ToWideString(job->request.headers[i].second) + L"\r\n";
    const std::string& body = job->request.body;
    if (!WinHttpSendRequest(request, headers.c_str(), (DWORD)-1, body.empty() ? WINHTTP_NO_REQUEST_DATA : (LPVOID)body.data(),
                            (DWORD)body.size(), (DWORD)body.size(), 0) ||
        !WinHttpReceiveResponse(request, NULL)) {
        fail(GetLastError());
        return;
    }

    DWORD status = 0;
    queryNumber(request, WINHTTP_QUERY_STATUS_CODE, status);
    std::wstring type = queryString(request, WINHTTP_QUERY_CONTENT_TYPE);
    for (size_t i = 0; i < type.size(); i++)
        type[i] = (wchar_t)towlower(type[i]);
    bool ok = status >= 200 && status < 300;
    bool streaming = !job->listModels && ok && type.find(L"event-stream") != std::wstring::npos;

    vai::StreamParser parser(job->config.provider.protocol);
    vai::Error streamError;
    std::string collected;
    unsigned pieces = 0;
    char buffer[8192];
    while (!isCancelled(job)) {
        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(request, &available)) {
            DWORD code = GetLastError();
            if (isCancelled(job))
                break;
            fail(code);
            return;
        }
        if (available == 0)
            break; //the end of the answer
        DWORD got = 0;
        if (!WinHttpReadData(request, buffer, available < sizeof(buffer) ? available : (DWORD)sizeof(buffer), &got)) {
            DWORD code = GetLastError();
            if (isCancelled(job))
                break;
            fail(code);
            return;
        }
        if (got == 0)
            break;
        if (streaming) {
            std::vector<std::string> texts = parser.feed(std::string(buffer, got), streamError);
            for (size_t i = 0; i < texts.size(); i++) {
                pieces++;
                post(job, AIClient::kMessageText, (LPARAM) new std::wstring(utf8ToWideString(texts[i])));
            }
            if (!streamError.ok())
                break; //nothing more to read
        } else if (collected.size() < kMaxBodyBytes) {
            collected.append(buffer, got);
        }
    }

    if (isCancelled(job)) {
        closeHandles(job);
        return; //the caller asked to stop: it wants nothing more
    }
    closeHandles(job);

    if (job->listModels) {
        if (!ok) {
            vai::Error error = vai::errorForStatus((int)status, collected, job->config);
            finishModels(job, std::vector<std::string>(), error, AIText::forError(error, job->config));
            return;
        }
        std::vector<std::string> names = vai::modelNames(collected, job->config);
        if (names.empty()) {
            vai::Error error(vai::ErrorCode::Empty);
            finishModels(job, names, error, L"Máy chủ không trả về danh sách model nào. Bạn vẫn có thể nhập tên model bằng tay.");
            return;
        }
        finishModels(job, names, vai::Error(), L"");
        return;
    }

    if (!streamError.ok()) {
        std::string redacted = vai::redact(streamError.detail, job->config.key);
        streamError.detail = redacted;
        std::wstring message = streamError.code == vai::ErrorCode::Rejected
                                   ? AIText::forError(streamError, job->config)
                                   : L"AI báo lỗi: " + utf8ToWideString(redacted);
        finish(job, streamError, message);
        return;
    }
    if (!ok) {
        vai::Error error = vai::errorForStatus((int)status, collected, job->config);
        finish(job, error, AIText::forError(error, job->config));
        return;
    }
    if (streaming) {
        std::vector<std::string> rest = parser.flush(); //what was held back in case it was a tag
        for (size_t i = 0; i < rest.size(); i++) {
            pieces++;
            post(job, AIClient::kMessageText, (LPARAM) new std::wstring(utf8ToWideString(rest[i])));
        }
    } else { //the whole answer in one piece
        vai::Error problem;
        std::string text = vai::StreamParser::textOfCompleteAnswer(collected, job->config.provider.protocol, problem);
        if (!problem.ok()) {
            problem.detail = vai::redact(problem.detail, job->config.key);
            finish(job, problem, L"AI báo lỗi: " + utf8ToWideString(problem.detail));
            return;
        }
        if (!text.empty()) {
            pieces++;
            post(job, AIClient::kMessageText, (LPARAM) new std::wstring(utf8ToWideString(text)));
        }
    }
    if (pieces == 0) {
        vai::Error error(vai::ErrorCode::Empty);
        finish(job, error, AIText::forError(error, job->config));
        return;
    }
    finish(job, vai::Error(), L"");
}

DWORD WINAPI threadMain(LPVOID parameter) {
    Job* job = (Job*)parameter;
    run(job);
    closeHandles(job);
    EnterCriticalSection(&g_lock);
    g_jobs.erase(job->id);
    LeaveCriticalSection(&g_lock);
    delete job;
    return 0;
}

//Registers the job and runs it on a thread of its own. The job has its id already; it may be gone when this returns.
bool start(Job* job, std::wstring& reason) {
    EnterCriticalSection(&g_lock);
    g_jobs[job->id] = job;
    LeaveCriticalSection(&g_lock);
    HANDLE thread = CreateThread(NULL, 0, threadMain, job, 0, NULL);
    if (!thread) {
        EnterCriticalSection(&g_lock);
        g_jobs.erase(job->id);
        LeaveCriticalSection(&g_lock);
        delete job;
        reason = L"Không tạo được luồng để gửi yêu cầu.";
        return false;
    }
    CloseHandle(thread);
    return true;
}

unsigned allocateId() {
    ensureLock();
    EnterCriticalSection(&g_lock);
    unsigned id = g_nextId++;
    if (g_nextId == 0)
        g_nextId = 1;
    LeaveCriticalSection(&g_lock);
    return id;
}

} // namespace

namespace AIClient {

unsigned generate(const vai::Config& config, const std::string& prompt, HWND window, std::wstring& reason) {
    Job* job = new Job();
    job->listModels = false;
    job->config = config;
    job->window = window;
    job->cancelled = 0;
    job->request_handle = job->connection = job->session = NULL;
    vai::Error error;
    if (!vai::buildRequest(config, prompt, job->request, error)) {
        reason = AIText::forError(error, config);
        delete job;
        return 0;
    }
    unsigned id = allocateId();
    job->id = id;
    return start(job, reason) ? id : 0;
}

unsigned listModels(const vai::Config& config, HWND window, std::wstring& reason) {
    Job* job = new Job();
    job->listModels = true;
    job->config = config;
    job->window = window;
    job->cancelled = 0;
    job->request_handle = job->connection = job->session = NULL;
    vai::Error error;
    if (!vai::buildModelsRequest(config, job->request, error)) {
        reason = AIText::forError(error, config);
        delete job;
        return 0;
    }
    unsigned id = allocateId();
    job->id = id;
    return start(job, reason) ? id : 0;
}

void cancel(unsigned id) {
    if (!g_lockReady)
        return;
    EnterCriticalSection(&g_lock);
    std::map<unsigned, Job*>::iterator found = g_jobs.find(id);
    if (found != g_jobs.end()) {
        Job* job = found->second;
        InterlockedExchange(&job->cancelled, 1);
        //a read that waits for the server returns at once when its handle is closed
        HINTERNET handles[3] = {job->request_handle, job->connection, job->session};
        job->request_handle = job->connection = job->session = NULL;
        LeaveCriticalSection(&g_lock);
        for (int i = 0; i < 3; i++) {
            if (handles[i])
                WinHttpCloseHandle(handles[i]);
        }
        return;
    }
    LeaveCriticalSection(&g_lock);
}

} // namespace AIClient
