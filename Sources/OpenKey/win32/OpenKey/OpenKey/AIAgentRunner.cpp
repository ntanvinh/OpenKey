//
//  AIAgentRunner.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "AIAgentRunner.h"
#include "AIClient.h"
#include "AIText.h"
#include <objbase.h>
#include <shlwapi.h>
#include <cstdlib>
#include <algorithm>
#include <map>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shlwapi.lib")

namespace {

namespace agent = vai::agent;

const DWORD kTimeoutMs = 10 * 60 * 1000;        //a request that has not ended by then is stopped
const DWORD kListTimeoutMs = 20 * 1000;
const size_t kMaxOutput = 2u << 20;             //an answer of 2 MB is a program gone wrong
const size_t kMaxListing = 8u << 20;
const size_t kMaxErrorOutput = 64 * 1024;
const size_t kMaxCommandLine = 30000;           //CreateProcess takes 32767 characters

struct Run {
    unsigned id;
    HWND window;
    bool listing;
    bool image;          //a picture is asked for (Codex), not a text
    vai::Config config;
    const agent::Agent* program;
    std::string prompt;
    volatile LONG cancelled;
    HANDLE process;      //the program that runs, and its job: guarded by g_lock (cancel() reads them from another thread)
    HANDLE job;
};

CRITICAL_SECTION g_lock;
bool g_lockReady = false;
std::map<unsigned, Run*> g_runs;
std::map<int, std::vector<agent::Model> > g_models;   //by kind: what the programs said, kept for the run of this program

void ensureLock() {
    if (!g_lockReady) {
        InitializeCriticalSection(&g_lock);
        g_lockReady = true;
    }
}

bool isCancelled(Run* run) {
    return InterlockedCompareExchange(&run->cancelled, 0, 0) != 0;
}

// --- telling the window -------------------------------------------------------------------------------------------------

void postText(Run* run, const std::string& utf8) {
    if (utf8.empty() || isCancelled(run))
        return;
    std::wstring* text = new std::wstring(utf8ToWideString(utf8));
    if (!PostMessageW(run->window, AIClient::kMessageText, (WPARAM)run->id, (LPARAM)text))
        delete text;
}

void postDone(Run* run, const vai::Error& error) {
    if (isCancelled(run))
        return;
    AIClient::Done* done = new AIClient::Done();
    done->error = error;
    done->message = error.ok() ? std::wstring() : AIText::forError(error, run->config);
    if (!PostMessageW(run->window, AIClient::kMessageDone, (WPARAM)run->id, (LPARAM)done))
        delete done;
}

void postImage(Run* run, const std::wstring& path, const vai::Error& error) {
    if (isCancelled(run))
        return;
    AIClient::ImageDone* done = new AIClient::ImageDone();
    done->error = error;
    done->path = path;
    done->message = error.ok() ? std::wstring() : AIText::forError(error, run->config);
    if (!PostMessageW(run->window, AIClient::kMessageImage, (WPARAM)run->id, (LPARAM)done))
        delete done;
}

void postModels(Run* run, const std::vector<std::string>& names, const vai::Error& error) {
    if (isCancelled(run))
        return;
    AIClient::Models* models = new AIClient::Models();
    models->names = names;
    models->error = error;
    models->message = error.ok() ? std::wstring() : AIText::forError(error, run->config);
    if (!PostMessageW(run->window, AIClient::kMessageModels, (WPARAM)run->id, (LPARAM)models))
        delete models;
}

// --- finding the program ------------------------------------------------------------------------------------------------

std::wstring lowerCase(std::wstring text) {
    for (size_t i = 0; i < text.size(); i++) {
        if (text[i] >= L'A' && text[i] <= L'Z')
            text[i] = (wchar_t)(text[i] - L'A' + L'a');
    }
    return text;
}

std::wstring environmentValue(const wchar_t* name) {
    DWORD needed = GetEnvironmentVariableW(name, NULL, 0);
    if (needed == 0)
        return std::wstring();
    std::wstring value((size_t)needed, L'\0');
    DWORD got = GetEnvironmentVariableW(name, &value[0], needed);
    value.resize(got);
    return value;
}

std::wstring extensionOf(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    size_t dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash))
        return std::wstring();
    return lowerCase(path.substr(dot));
}

std::wstring folderOf(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? std::wstring() : path.substr(0, slash);
}

bool directoryExists(const std::wstring& path) {
    DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY);
}

//Where programs like these are usually installed. A program started at logon or from the tray has the PATH of the user, but not always the
//folder a package manager added later, so the usual ones are listed. Folders that do not exist are left out.
std::vector<std::wstring> searchDirectories() {
    std::vector<std::wstring> candidates;
    std::wstring profile = environmentValue(L"USERPROFILE");
    std::wstring roaming = environmentValue(L"APPDATA");
    std::wstring local = environmentValue(L"LOCALAPPDATA");
    std::wstring programs = environmentValue(L"ProgramFiles");
    if (!profile.empty()) {
        const wchar_t* relative[] = {L"\\.local\\bin", L"\\.claude\\local", L"\\.bun\\bin", L"\\.volta\\bin", L"\\.npm-global", L"\\.yarn\\bin",
                                     L"\\.cargo\\bin", L"\\scoop\\shims"};
        for (size_t i = 0; i < sizeof(relative) / sizeof(relative[0]); i++)
            candidates.push_back(profile + relative[i]);
    }
    if (!roaming.empty())
        candidates.push_back(roaming + L"\\npm");
    if (!local.empty()) {
        candidates.push_back(local + L"\\npm");
        candidates.push_back(local + L"\\Microsoft\\WinGet\\Links");
    }
    if (!programs.empty())
        candidates.push_back(programs + L"\\nodejs");
    //the folders of PATH
    std::wstring path = environmentValue(L"PATH");
    size_t start = 0;
    while (start <= path.size()) {
        size_t end = path.find(L';', start);
        if (end == std::wstring::npos)
            end = path.size();
        std::wstring entry = path.substr(start, end - start);
        if (entry.size() >= 2 && entry[0] == L'"' && entry[entry.size() - 1] == L'"')
            entry = entry.substr(1, entry.size() - 2);
        //a folder that is not written in full ("." or "tools") would be looked for where this program happens to be running: a program put
        //there would be taken for the one of the user
        if (!entry.empty() && !PathIsRelativeW(entry.c_str()))
            candidates.push_back(entry);
        start = end + 1;
    }
    std::vector<std::wstring> directories;
    for (size_t i = 0; i < candidates.size(); i++) {
        while (candidates[i].size() > 3 && (candidates[i][candidates[i].size() - 1] == L'\\' || candidates[i][candidates[i].size() - 1] == L'/'))
            candidates[i].erase(candidates[i].size() - 1);
        bool seen = false;
        for (size_t k = 0; k < directories.size(); k++)
            seen = seen || lowerCase(directories[k]) == lowerCase(candidates[i]);
        if (!seen && directoryExists(candidates[i]))
            directories.push_back(candidates[i]);
    }
    return directories;
}

// --- running it ---------------------------------------------------------------------------------------------------------

//the environment of the program: this program's, with a PATH that finds what a script needs (node sits next to a script of npm), and no colours
std::wstring environmentBlockFor(const std::wstring& executable) {
    std::wstring path = folderOf(executable);
    std::vector<std::wstring> directories = searchDirectories();
    for (size_t i = 0; i < directories.size(); i++) {
        if (lowerCase(directories[i]) != lowerCase(folderOf(executable)))
            path += (path.empty() ? L"" : L";") + directories[i];
    }
    std::wstring block;
    LPWCH own = GetEnvironmentStringsW();
    if (own) {
        for (LPWCH entry = own; *entry; entry += wcslen(entry) + 1) {
            std::wstring text(entry);
            std::wstring name = lowerCase(text.substr(0, text.find(L'=', 1)));
            if (name == L"path" || name == L"no_color" || name == L"term")
                continue;
            block += text;
            block.push_back(L'\0');
        }
        FreeEnvironmentStringsW(own);
    }
    block += L"Path=" + path;
    block.push_back(L'\0');
    block += L"NO_COLOR=1";
    block.push_back(L'\0');
    block += L"TERM=dumb";
    block.push_back(L'\0');
    block.push_back(L'\0');
    return block;
}

struct Child {
    HANDLE process;
    HANDLE job;
    HANDLE input;       //our end of its standard input
    HANDLE output;
    HANDLE errorOutput;
    Child() : process(NULL), job(NULL), input(NULL), output(NULL), errorOutput(NULL) {}
};

enum LaunchResult { Launched, Unsafe, TooLong, Failed };

void closeHandle(HANDLE& handle) {
    if (handle && handle != INVALID_HANDLE_VALUE)
        CloseHandle(handle);
    handle = NULL;
}

//Starts the program without a window, with the three standard handles on pipes and nothing else inherited, in a job that takes down
//everything it starts. A script goes through cmd.exe, but only when none of its arguments means something to cmd.exe.
LaunchResult launch(const std::wstring& executable, const std::vector<std::string>& args, const std::wstring& directory, Child& child, std::wstring& why) {
    std::wstring extension = extensionOf(executable);
    bool script = extension == L".cmd" || extension == L".bat";
    std::wstring application = executable;
    std::wstring line = utf8ToWideString(agent::commandLine(wideStringToUtf8(executable), args));
    if (script) {
        if (!agent::safeForCommandShell(args))
            return Unsafe;
        std::wstring shell = environmentValue(L"ComSpec");
        application = shell.empty() ? L"cmd.exe" : shell;
        //with /s the outer quotes are dropped and what is inside is run as it stands
        line = L"\"" + application + L"\" /d /s /c \"" + line + L"\"";
    }
    if (line.size() > kMaxCommandLine)
        return TooLong;

    SECURITY_ATTRIBUTES inheritable = {sizeof(inheritable), NULL, TRUE};
    HANDLE inRead = NULL, inWrite = NULL, outRead = NULL, outWrite = NULL, errRead = NULL, errWrite = NULL;
    if (!CreatePipe(&inRead, &inWrite, &inheritable, 0) || !CreatePipe(&outRead, &outWrite, &inheritable, 0) ||
        !CreatePipe(&errRead, &errWrite, &inheritable, 0)) {
        why = L"không tạo được đường ống";
        closeHandle(inRead); closeHandle(inWrite); closeHandle(outRead); closeHandle(outWrite); closeHandle(errRead); closeHandle(errWrite);
        return Failed;
    }
    //our ends are not for the program
    SetHandleInformation(inWrite, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(outRead, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(errRead, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOEXW startup;
    ZeroMemory(&startup, sizeof(startup));
    startup.StartupInfo.cb = sizeof(STARTUPINFOW);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    startup.StartupInfo.wShowWindow = SW_HIDE;
    startup.StartupInfo.hStdInput = inRead;
    startup.StartupInfo.hStdOutput = outWrite;
    startup.StartupInfo.hStdError = errWrite;
    //only these three handles are inherited (not the other pipes of requests that run at the same time)
    HANDLE inherited[3] = {inRead, outWrite, errWrite};
    std::vector<char> attributeBuffer;
    LPPROC_THREAD_ATTRIBUTE_LIST attributes = NULL;
    bool attributesReady = false;
    SIZE_T attributeSize = 0;
    InitializeProcThreadAttributeList(NULL, 1, 0, &attributeSize);
    if (attributeSize > 0) {
        attributeBuffer.resize(attributeSize);
        attributes = (LPPROC_THREAD_ATTRIBUTE_LIST)&attributeBuffer[0];
        attributesReady = InitializeProcThreadAttributeList(attributes, 1, 0, &attributeSize) != FALSE;
        if (attributesReady && !UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherited, sizeof(inherited), NULL, NULL)) {
            DeleteProcThreadAttributeList(attributes);
            attributesReady = false;
        }
    }
    DWORD flags = CREATE_NO_WINDOW | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_PROCESS_GROUP;
    if (attributesReady) {
        flags |= EXTENDED_STARTUPINFO_PRESENT;
        startup.StartupInfo.cb = sizeof(STARTUPINFOEXW);
        startup.lpAttributeList = attributes;
    }
    std::wstring environment = environmentBlockFor(executable);
    std::vector<wchar_t> command(line.begin(), line.end());
    command.push_back(L'\0');
    PROCESS_INFORMATION info;
    ZeroMemory(&info, sizeof(info));
    BOOL created = CreateProcessW(application.c_str(), &command[0], NULL, NULL, TRUE, flags, (LPVOID)environment.c_str(),
                                  directory.empty() ? NULL : directory.c_str(), &startup.StartupInfo, &info);
    DWORD failure = created ? 0 : GetLastError();
    if (attributesReady)
        DeleteProcThreadAttributeList(attributes);
    closeHandle(inRead);        //the program has them now
    closeHandle(outWrite);
    closeHandle(errWrite);
    if (!created) {
        closeHandle(inWrite);
        closeHandle(outRead);
        closeHandle(errRead);
        why = L"mã lỗi " + std::to_wstring((unsigned long)failure);
        return Failed;
    }
    //a job that ends everything with it; where the system does not allow a job (an older Windows inside a job of its own) the program alone
    HANDLE job = CreateJobObjectW(NULL, NULL);
    if (job) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
        ZeroMemory(&limits, sizeof(limits));
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits)) || !AssignProcessToJobObject(job, info.hProcess))
            closeHandle(job);
    }
    ResumeThread(info.hThread);
    CloseHandle(info.hThread);
    child.process = info.hProcess;
    child.job = job;
    child.input = inWrite;
    child.output = outRead;
    child.errorOutput = errRead;
    return Launched;
}

void killChild(HANDLE process, HANDLE job) {
    if (job)
        TerminateJobObject(job, 1);
    if (process)
        TerminateProcess(process, 1);
}

//what is read from one of the pipes of the program
struct Pump {
    HANDLE handle;
    Run* run;
    HANDLE process;
    HANDLE job;
    agent::OutputParser* parser;   //the answer: cut into pieces and sent to the window; NULL: the bytes are kept
    std::string captured;
    size_t capture;                //how many bytes are kept at most
    size_t limit;                  //more than this ends the request, 0 = no limit
    size_t total;
    volatile LONG tooMuch;
    volatile LONG hasText;
    volatile LONG abandoned;       //the request is over and this thread was left behind: it must not touch what belonged to the request
    bool silent;                   //the pieces are not sent to the window but kept in `spoken` (what Codex says while it makes a picture)
    std::string spoken;
};

DWORD WINAPI pumpThread(LPVOID parameter) {
    Pump* pump = (Pump*)parameter;
    char buffer[8192];
    DWORD got = 0;
    while (ReadFile(pump->handle, buffer, sizeof(buffer), &got, NULL) && got > 0) {
        if (InterlockedCompareExchange(&pump->abandoned, 0, 0))
            break;
        pump->total += got;
        if (pump->parser) {
            std::vector<std::string> pieces = pump->parser->feed(std::string(buffer, got));
            for (size_t i = 0; i < pieces.size(); i++) {
                for (size_t k = 0; k < pieces[i].size(); k++) {
                    if ((unsigned char)pieces[i][k] > ' ') {
                        InterlockedExchange(&pump->hasText, 1);
                        break;
                    }
                }
                if (pump->silent) {
                    if (pump->spoken.size() < 64 * 1024)
                        pump->spoken += pieces[i];
                } else {
                    postText(pump->run, pieces[i]);
                }
            }
        }
        if (pump->captured.size() < pump->capture)
            pump->captured.append(buffer, (std::min)((size_t)got, pump->capture - pump->captured.size()));
        if (pump->limit > 0 && pump->total > pump->limit && InterlockedExchange(&pump->tooMuch, 1) == 0)
            killChild(pump->process, pump->job);
    }
    return 0;
}

//the request, on the standard input, as fast as the program takes it: its own thread, a program that does not read must not hold anything up
struct Feed {
    HANDLE handle;
    std::string data;
};

DWORD WINAPI feedThread(LPVOID parameter) {
    Feed* feed = (Feed*)parameter;
    size_t done = 0;
    while (done < feed->data.size()) {
        DWORD wrote = 0;
        DWORD chunk = (DWORD)(std::min)((size_t)32768, feed->data.size() - done);
        if (!WriteFile(feed->handle, feed->data.data() + done, chunk, &wrote, NULL) || wrote == 0)
            break; //the program does not read any more (it has ended or does not want it)
        done += wrote;
    }
    CloseHandle(feed->handle);
    delete feed;
    return 0;
}

struct Outcome {
    LaunchResult launched;
    std::wstring why;
    DWORD exitCode;
    bool timedOut;
    bool tooMuch;
    bool hasText;
    std::string errorOutput;
    std::string output;      //when it was kept
    std::string spoken;      //what the program said, for a picture
    Outcome() : launched(Failed), exitCode(0), timedOut(false), tooMuch(false), hasText(false) {}
};

void removeFolder(const std::wstring& folder) {
    WIN32_FIND_DATAW found;
    HANDLE search = FindFirstFileW((folder + L"\\*").c_str(), &found);
    if (search != INVALID_HANDLE_VALUE) {
        do {
            std::wstring name = found.cFileName;
            if (name == L"." || name == L"..")
                continue;
            std::wstring path = folder + L"\\" + name;
            if (found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                if (!(found.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) //a link is taken away, never followed
                    removeFolder(path);
                else
                    RemoveDirectoryW(path.c_str());
            } else {
                SetFileAttributesW(path.c_str(), FILE_ATTRIBUTE_NORMAL);
                DeleteFileW(path.c_str());
            }
        } while (FindNextFileW(search, &found));
        FindClose(search);
    }
    RemoveDirectoryW(folder.c_str());
}

//a folder of its own, empty: what the program can see around it is nothing
std::wstring makeWorkFolder() {
    wchar_t temp[MAX_PATH];
    DWORD length = GetTempPathW(MAX_PATH, temp);
    if (length == 0 || length >= MAX_PATH)
        return std::wstring();
    GUID guid;
    wchar_t text[64] = {0};
    if (FAILED(CoCreateGuid(&guid)) || StringFromGUID2(guid, text, 64) == 0)
        return std::wstring();
    std::wstring folder = std::wstring(temp) + L"VOpenKey-agent-" + text;
    folder.erase(std::remove(folder.begin(), folder.end(), L'{'), folder.end());
    folder.erase(std::remove(folder.begin(), folder.end(), L'}'), folder.end());
    return CreateDirectoryW(folder.c_str(), NULL) ? folder : std::wstring();
}

//Starts the program, feeds it, reads it and waits until it has ended, or the time is up, or the request is cancelled.
Outcome execute(Run* run, const std::wstring& executable, const std::vector<std::string>& args, const std::string* input, const std::wstring& directory,
                agent::OutputParser* parser, DWORD timeoutMs, size_t outputLimit, bool keepOutput, bool silent = false) {
    Outcome outcome;
    Child child;
    outcome.launched = launch(executable, args, directory, child, outcome.why);
    if (outcome.launched != Launched)
        return outcome;
    EnterCriticalSection(&g_lock);
    run->process = child.process;
    run->job = child.job;
    LeaveCriticalSection(&g_lock);
    if (isCancelled(run))
        killChild(child.process, child.job);

    if (input) {
        Feed* feed = new Feed();
        feed->handle = child.input;
        feed->data = *input;
        child.input = NULL; //the thread closes it
        HANDLE thread = CreateThread(NULL, 0, feedThread, feed, 0, NULL);
        if (thread) {
            CloseHandle(thread);
        } else {
            CloseHandle(feed->handle);
            delete feed;
        }
    } else {
        closeHandle(child.input); //nothing to say: the program sees the end of its input at once
    }

    Pump* out = new Pump();
    out->handle = child.output; out->run = run; out->process = child.process; out->job = child.job; out->parser = parser;
    out->capture = keepOutput ? outputLimit : 0; out->limit = outputLimit; out->total = 0; out->tooMuch = 0; out->hasText = 0; out->abandoned = 0;
    out->silent = silent;
    Pump* err = new Pump();
    err->handle = child.errorOutput; err->run = run; err->process = child.process; err->job = child.job; err->parser = NULL;
    err->capture = kMaxErrorOutput; err->limit = 0; err->total = 0; err->tooMuch = 0; err->hasText = 0; err->abandoned = 0;
    err->silent = false;
    HANDLE readers[2] = {CreateThread(NULL, 0, pumpThread, out, 0, NULL), CreateThread(NULL, 0, pumpThread, err, 0, NULL)};
    if (!readers[0] || !readers[1]) { //no thread to read with: nothing can be done with this program
        killChild(child.process, child.job);
        InterlockedExchange(&out->abandoned, 1);
        InterlockedExchange(&err->abandoned, 1);
        EnterCriticalSection(&g_lock);
        run->process = NULL;
        run->job = NULL;
        LeaveCriticalSection(&g_lock);
        closeHandle(child.job);
        closeHandle(child.process);
        closeHandle(child.output);       //a reader that did start ends with its pipe (and is left to end, with what it uses)
        closeHandle(child.errorOutput);
        closeHandle(readers[0]);
        closeHandle(readers[1]);
        outcome.launched = Failed;
        outcome.why = L"không tạo được luồng đọc";
        return outcome;
    }

    DWORD started = GetTickCount();
    for (;;) {
        DWORD waited = WaitForSingleObject(child.process, 100);
        if (waited == WAIT_OBJECT_0)
            break;
        if (isCancelled(run) || out->tooMuch) {
            killChild(child.process, child.job);
            break;
        }
        if (GetTickCount() - started > timeoutMs) {
            outcome.timedOut = true;
            killChild(child.process, child.job);
            break;
        }
    }
    WaitForSingleObject(child.process, 5000);
    GetExitCodeProcess(child.process, &outcome.exitCode);

    //what the program printed last is still in the pipes; a program it started that keeps them open would hold the readers: the job is ended
    bool ended = WaitForMultipleObjects(2, readers, TRUE, 500) == WAIT_OBJECT_0;
    if (!ended) {
        killChild(NULL, child.job);
        ended = WaitForMultipleObjects(2, readers, TRUE, 3000) == WAIT_OBJECT_0;
    }
    if (!ended) {
        //a reader is stuck in a pipe that something else holds: it is left behind, with its own memory, and told to touch nothing of the request
        InterlockedExchange(&out->abandoned, 1);
        InterlockedExchange(&err->abandoned, 1);
        out->parser = NULL;
        out->process = out->job = err->process = err->job = NULL;
    }
    EnterCriticalSection(&g_lock);
    run->process = NULL;
    run->job = NULL;
    LeaveCriticalSection(&g_lock);
    closeHandle(child.job);
    closeHandle(child.process);
    closeHandle(readers[0]);
    closeHandle(readers[1]);
    if (ended) {
        closeHandle(child.output);
        closeHandle(child.errorOutput);
        outcome.tooMuch = out->tooMuch != 0;
        outcome.hasText = out->hasText != 0;
        outcome.errorOutput = err->captured;
        outcome.output = out->captured;
        outcome.spoken = out->spoken;
        delete out;
        delete err;
    }
    return outcome;
}

// --- the two kinds of run -----------------------------------------------------------------------------------------------

bool noText(const std::string& text) {
    for (size_t i = 0; i < text.size(); i++) {
        if ((unsigned char)text[i] > ' ')
            return false;
    }
    return true;
}

//Asks the program for its models and keeps them. Claude Code has no such command: its list is fixed.
bool loadModels(Run* run, const std::wstring& executable, std::vector<agent::Model>& models, vai::Error& error) {
    const agent::Agent& program = *run->program;
    if (program.kind == agent::Kind::Claude) {
        models = agent::claudeModels();
        return true;
    }
    std::vector<std::string> args;
    if (!agent::listModelsArguments(program, args)) {
        error = vai::Error(vai::ErrorCode::Empty);
        return false;
    }
    Outcome outcome = execute(run, executable, args, NULL, std::wstring(), NULL, kListTimeoutMs, kMaxListing, true);
    if (outcome.launched != Launched) {
        error = vai::Error(vai::ErrorCode::NoProgram, outcome.launched == Unsafe ? "script" : wideStringToUtf8(outcome.why));
        return false;
    }
    models = program.kind == agent::Kind::Codex ? agent::modelsFromCodexCatalog(outcome.output) : agent::modelsFromAntigravityList(outcome.output);
    if (models.empty()) {
        error = vai::Error(vai::ErrorCode::Empty, agent::gistOfErrorOutput(outcome.errorOutput));
        return false;
    }
    EnterCriticalSection(&g_lock);
    g_models[(int)program.kind] = models;
    LeaveCriticalSection(&g_lock);
    return true;
}

void doListing(Run* run) {
    std::vector<agent::Model> models;
    vai::Error error;
    std::wstring executable = utf8ToWideString(run->config.executable);
    if (!isCancelled(run) && loadModels(run, executable, models, error)) {
        std::vector<std::string> names;
        for (size_t i = 0; i < models.size(); i++)
            names.push_back(models[i].id);
        postModels(run, names, vai::Error());
    } else {
        postModels(run, std::vector<std::string>(), error);
    }
}

void doGenerate(Run* run) {
    const agent::Agent& program = *run->program;
    std::wstring executable = utf8ToWideString(run->config.executable);
    std::vector<agent::Model> models = AIAgentRunner::knownModels(program);
    //"choose for me" is a light model of the list, and a model of Antigravity stands for several (one by level): the list is asked of the program
    if (models.empty() && program.kind != agent::Kind::Claude) {
        vai::Error ignored;
        loadModels(run, executable, models, ignored); //it may fail: the program then uses its own default
        if (isCancelled(run))
            return;
    }
    std::string model, effort;
    agent::resolve(program, run->config.model, run->config.effort, models, model, effort);

    std::wstring folder = makeWorkFolder();
    if (folder.empty()) {
        postDone(run, vai::Error(vai::ErrorCode::NoProgram, wideStringToUtf8(L"không tạo được thư mục tạm")));
        return;
    }
    std::vector<std::string> args = agent::arguments(program, model, effort, run->config.systemPrompt, run->prompt, wideStringToUtf8(folder));
    std::string input;
    bool viaInput = agent::standardInput(program, run->prompt, run->config.systemPrompt, input);

    agent::OutputParser parser(program.output);
    Outcome outcome = execute(run, executable, args, viaInput ? &input : NULL, folder, &parser, kTimeoutMs, kMaxOutput, false);
    removeFolder(folder);
    if (isCancelled(run))
        return;
    if (outcome.launched == Unsafe) {
        postDone(run, vai::Error(vai::ErrorCode::NoProgram, "script"));
        return;
    }
    if (outcome.launched == TooLong) {
        postDone(run, vai::Error(vai::ErrorCode::TooMuch, "arguments"));
        return;
    }
    if (outcome.launched != Launched) {
        postDone(run, vai::Error(vai::ErrorCode::NoProgram, wideStringToUtf8(outcome.why)));
        return;
    }
    //what was held back in the parser (the end of the text, the result of stream-json)
    std::vector<std::string> rest = parser.finish();
    for (size_t i = 0; i < rest.size(); i++) {
        if (!noText(rest[i]))
            outcome.hasText = true;
        postText(run, rest[i]);
    }
    vai::Error error;
    if (outcome.timedOut) {
        error = vai::Error(vai::ErrorCode::Timeout);
    } else if (outcome.tooMuch) {
        error = vai::Error(vai::ErrorCode::TooMuch);
    } else if (!parser.errorMessage().empty()) {
        error = agent::errorForMessage(program, parser.errorMessage(), (int)outcome.exitCode, model, effort);
    } else if (outcome.exitCode != 0) {
        error = agent::errorForMessage(program, !outcome.errorOutput.empty() ? outcome.errorOutput : parser.leftover(), (int)outcome.exitCode, model, effort);
    } else if (!outcome.hasText) {
        error = vai::Error(vai::ErrorCode::Empty, agent::gistOfErrorOutput(outcome.errorOutput));
    }
    postDone(run, error);
}

//--- pictures ------------------------------------------------------------------------------------------------------------

//Where Codex keeps what it makes: $CODEX_HOME, or the folder .codex of the profile of the user
std::wstring codexHome() {
    std::string variable = wideStringToUtf8(environmentValue(L"CODEX_HOME"));
    std::string profile = wideStringToUtf8(environmentValue(L"USERPROFILE"));
    return utf8ToWideString(agent::codexHomeFolder(variable, profile, '\\'));
}

long long fileTimeNumber(const FILETIME& time) {
    return ((long long)time.dwHighDateTime << 32) | (long long)time.dwLowDateTime;
}

//The files in the folders under generated_images: those of one folder (the thread of a run), or of all of them. A link is never followed.
void listPictures(const std::wstring& generated, const std::wstring& onlyFolder, std::vector<agent::PictureEntry>& entries) {
    std::vector<std::wstring> folders;
    if (!onlyFolder.empty()) {
        folders.push_back(onlyFolder);
    } else {
        WIN32_FIND_DATAW found;
        HANDLE search = FindFirstFileW((generated + L"\\*").c_str(), &found);
        if (search != INVALID_HANDLE_VALUE) {
            do {
                std::wstring name = found.cFileName;
                if ((found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && !(found.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) &&
                    name != L"." && name != L"..")
                    folders.push_back(name);
            } while (FindNextFileW(search, &found));
            FindClose(search);
        }
    }
    for (size_t i = 0; i < folders.size(); i++) {
        WIN32_FIND_DATAW found;
        HANDLE search = FindFirstFileW((generated + L"\\" + folders[i] + L"\\*").c_str(), &found);
        if (search == INVALID_HANDLE_VALUE)
            continue;
        do {
            if (found.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))
                continue;
            agent::PictureEntry entry;
            entry.folder = wideStringToUtf8(folders[i]);
            entry.name = wideStringToUtf8(found.cFileName);
            entry.modified = fileTimeNumber(found.ftLastWriteTime);
            entries.push_back(entry);
        } while (FindNextFileW(search, &found));
        FindClose(search);
    }
}

//The picture a run made: in the folder of its thread, or else the newest one written since it started. Empty when there is none.
std::wstring findPicture(const std::string& threadId, const FILETIME& started) {
    std::wstring generated = codexHome() + L"\\generated_images";
    long long since = fileTimeNumber(started);
    std::vector<agent::PictureEntry> entries;
    if (agent::isSafeThreadId(threadId)) {
        listPictures(generated, utf8ToWideString(threadId), entries);
        int chosen = agent::choosePicture(threadId, entries, since, true);
        if (chosen >= 0)
            return generated + L"\\" + utf8ToWideString(entries[(size_t)chosen].folder) + L"\\" + utf8ToWideString(entries[(size_t)chosen].name);
        entries.clear();
    }
    listPictures(generated, std::wstring(), entries);
    int chosen = agent::choosePicture(std::string(), entries, since, true);
    if (chosen < 0)
        return std::wstring();
    return generated + L"\\" + utf8ToWideString(entries[(size_t)chosen].folder) + L"\\" + utf8ToWideString(entries[(size_t)chosen].name);
}

//the last words of what the program said, from the start of a letter
std::string lastWords(const std::string& said, size_t limit) {
    size_t start = 0;
    size_t first = said.find_first_not_of(" \t\r\n");
    size_t last = said.find_last_not_of(" \t\r\n");
    if (first == std::string::npos)
        return std::string();
    std::string text = said.substr(first, last - first + 1);
    if (text.size() > limit) {
        start = text.size() - limit;
        while (start < text.size() && ((unsigned char)text[start] & 0xC0) == 0x80)
            start++;
    }
    return text.substr(start);
}

void doImage(Run* run) {
    const agent::Agent& program = *run->program;
    std::wstring executable = utf8ToWideString(run->config.executable);
    std::vector<agent::Model> models = AIAgentRunner::knownModels(program);
    if (models.empty() && program.kind != agent::Kind::Claude) {
        vai::Error ignored;
        loadModels(run, executable, models, ignored);
        if (isCancelled(run))
            return;
    }
    std::string model, effort;
    agent::resolve(program, run->config.model, run->config.effort, models, model, effort); //the model and level of the window, as for a text

    std::wstring folder = makeWorkFolder();
    if (folder.empty()) {
        postImage(run, std::wstring(), vai::Error(vai::ErrorCode::NoProgram, wideStringToUtf8(L"không tạo được thư mục tạm")));
        return;
    }
    std::vector<std::string> args = agent::imageArguments(program, model, effort, wideStringToUtf8(folder));
    std::string input = agent::imageStandardInput(run->prompt);
    FILETIME started;
    GetSystemTimeAsFileTime(&started);
    agent::OutputParser parser(agent::Output::CodexJson);
    Outcome outcome = execute(run, executable, args, &input, folder, &parser, kTimeoutMs, kMaxOutput, false, true);
    removeFolder(folder);
    if (isCancelled(run))
        return;
    if (outcome.launched == Unsafe) {
        postImage(run, std::wstring(), vai::Error(vai::ErrorCode::NoProgram, "script"));
        return;
    }
    if (outcome.launched == TooLong) {
        postImage(run, std::wstring(), vai::Error(vai::ErrorCode::TooMuch, "arguments"));
        return;
    }
    if (outcome.launched != Launched) {
        postImage(run, std::wstring(), vai::Error(vai::ErrorCode::NoProgram, wideStringToUtf8(outcome.why)));
        return;
    }
    std::vector<std::string> rest = parser.finish();
    for (size_t i = 0; i < rest.size(); i++)
        outcome.spoken += rest[i];
    vai::Error error;
    if (outcome.timedOut) {
        error = vai::Error(vai::ErrorCode::Timeout);
    } else if (outcome.tooMuch) {
        error = vai::Error(vai::ErrorCode::TooMuch);
    } else if (!parser.errorMessage().empty()) {
        error = agent::errorForMessage(program, parser.errorMessage(), (int)outcome.exitCode, model, effort);
    } else if (outcome.exitCode != 0) {
        error = agent::errorForMessage(program, !outcome.errorOutput.empty() ? outcome.errorOutput : parser.leftover(), (int)outcome.exitCode, model, effort);
    }
    if (!error.ok()) {
        postImage(run, std::wstring(), error);
        return;
    }
    //the picture is a file that Codex saved in its folder: the one of the thread it ran in
    std::wstring picture = findPicture(parser.threadId(), started);
    if (picture.empty()) {
        postImage(run, std::wstring(), vai::Error(vai::ErrorCode::NoPicture, vai::redact(lastWords(outcome.spoken, 260), "")));
        return;
    }
    postImage(run, picture, vai::Error());
}

DWORD WINAPI runThread(LPVOID parameter) {
    Run* run = (Run*)parameter;
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (run->listing)
        doListing(run);
    else if (run->image)
        doImage(run);
    else
        doGenerate(run);
    CoUninitialize();
    EnterCriticalSection(&g_lock);
    g_runs.erase(run->id);
    LeaveCriticalSection(&g_lock);
    delete run;
    return 0;
}

unsigned begin(const vai::Config& config, const std::string& prompt, HWND window, int mode, std::wstring& reason) { //0 text, 1 models, 2 picture
    ensureLock();
    const agent::Agent* program = agent::find(config.provider.id);
    if (program == NULL) {
        reason = L"Dịch vụ này không phải là chương trình AI trên máy.";
        return 0;
    }
    if (mode == 2 && !program->canMakeImages) {
        reason = program->displayName.empty() ? std::wstring(L"Chương trình này không tạo được ảnh.")
                                              : utf8ToWideString(program->displayName) + L" không tạo được ảnh. Chỉ Codex CLI làm được việc này.";
        return 0;
    }
    std::wstring executable = utf8ToWideString(config.executable);
    if (!AIAgentRunner::isRunnable(executable)) {
        reason = AIText::forError(vai::Error(vai::ErrorCode::NoProgram, wideStringToUtf8(L"không còn ở chỗ đã tìm thấy")), config);
        return 0;
    }
    if (!config.model.empty() && !agent::isPlausibleModelName(config.model)) {
        reason = AIText::forError(vai::Error(vai::ErrorCode::Model, "invalid name"), config);
        return 0;
    }
    Run* run = new Run();
    run->id = AIClient::newRequestId();
    run->window = window;
    run->listing = mode == 1;
    run->image = mode == 2;
    run->config = config;
    run->program = program;
    run->prompt = prompt;
    run->cancelled = 0;
    run->process = NULL;
    run->job = NULL;
    unsigned id = run->id;
    EnterCriticalSection(&g_lock);
    g_runs[id] = run;
    LeaveCriticalSection(&g_lock);
    HANDLE thread = CreateThread(NULL, 0, runThread, run, 0, NULL);
    if (!thread) {
        EnterCriticalSection(&g_lock);
        g_runs.erase(id);
        LeaveCriticalSection(&g_lock);
        delete run;
        reason = L"Không tạo được luồng để chạy chương trình AI.";
        return 0;
    }
    CloseHandle(thread);
    return id;
}

} // namespace

namespace AIAgentRunner {

bool isRunnable(const std::wstring& path) {
    if (path.empty())
        return false;
    DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY))
        return false;
    std::wstring extension = extensionOf(path);
    return extension == L".exe" || extension == L".com" || extension == L".cmd" || extension == L".bat";
}

std::wstring findProgram(const agent::Agent& program, const std::wstring& chosen) {
    if (isRunnable(chosen))
        return chosen;
    std::wstring base = utf8ToWideString(program.command);
    const wchar_t* extensions[] = {L".exe", L".cmd", L".bat"};
    std::vector<std::wstring> directories = searchDirectories();
    for (size_t d = 0; d < directories.size(); d++) {
        for (size_t e = 0; e < sizeof(extensions) / sizeof(extensions[0]); e++) {
            std::wstring candidate = directories[d] + L"\\" + base + extensions[e];
            if (isRunnable(candidate))
                return candidate;
        }
    }
    return std::wstring();
}

std::vector<agent::Model> knownModels(const agent::Agent& program) {
    if (program.kind == agent::Kind::Claude)
        return agent::claudeModels();
    ensureLock();
    std::vector<agent::Model> models;
    EnterCriticalSection(&g_lock);
    std::map<int, std::vector<agent::Model> >::iterator found = g_models.find((int)program.kind);
    if (found != g_models.end())
        models = found->second;
    LeaveCriticalSection(&g_lock);
    return models;
}

unsigned generate(const vai::Config& config, const std::string& prompt, HWND window, std::wstring& reason) {
    return begin(config, prompt, window, 0, reason);
}

unsigned generateImage(const vai::Config& config, const std::string& request, HWND window, std::wstring& reason) {
    return begin(config, request, window, 2, reason);
}

unsigned listModels(const vai::Config& config, HWND window, std::wstring& reason) {
    return begin(config, std::string(), window, 1, reason);
}

void cancel(unsigned id) {
    if (!g_lockReady)
        return;
    EnterCriticalSection(&g_lock);
    std::map<unsigned, Run*>::iterator found = g_runs.find(id);
    if (found != g_runs.end()) {
        Run* run = found->second;
        InterlockedExchange(&run->cancelled, 1);
        killChild(run->process, run->job); //the run thread sees it and ends; the handles are its own, they are in use only under the lock
    }
    LeaveCriticalSection(&g_lock);
}

} // namespace AIAgentRunner
