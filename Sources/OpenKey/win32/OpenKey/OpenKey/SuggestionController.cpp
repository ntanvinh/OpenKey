//
//  SuggestionController.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "SuggestionController.h"
#include "SuggestionBar.h"
#include "FeatureStorage.h"
#include <oleacc.h>
#include <shellapi.h>
#include <algorithm>
#include <memory>

#pragma comment(lib, "oleacc.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

extern int vMacroNeedsConfirm; //Engine.cpp

int vSuggestEnabled = 0;
int vSuggestNextWord = 1;
int vSuggestLearn = 1;
int vSuggestCompounds = 1;
int vSuggestTabAccepts = 1;
int vMacroConfirm = 1;

namespace {

//Tab completes shell commands and moves between fields, these programs would lose that
const char* const kExcludedApps[] = {
    "cmd.exe", "powershell.exe", "pwsh.exe", "windowsterminal.exe", "wt.exe", "conhost.exe", "openconsole.exe",
    "mintty.exe", "alacritty.exe", "wezterm-gui.exe", "kitty.exe", "conemu.exe", "conemu64.exe", "hyper.exe", "putty.exe"
};

std::unique_ptr<vsuggest::Engine> g_engine;
std::unique_ptr<vsuggest::Session> g_session;
bool g_started = false;
bool g_appExcluded = false;
bool g_refreshPosted = false;

std::vector<std::wstring> g_lastWords;
std::string g_lastTyped;
RECT g_lastLine = {0, 0, 0, 0};  //the line of the caret the bar is under, screen coordinates
bool g_anchorValid = false;
bool g_locating = false;         //a worker is asking the application where the caret is
bool g_locateAgain = false;      //the word changed meanwhile
unsigned g_generation = 0;       //changes every time the bar is hidden, so late answers are ignored

//the answer of the worker
CRITICAL_SECTION g_answerLock;
bool g_answerFound = false;
RECT g_answerLine = {0, 0, 0, 0};

class BarHost : public vsuggest::Host {
public:
    void showCandidates(const std::vector<vsuggest::Candidate>& candidates, const std::string& typed) override;
    void hideCandidates() override;
};
BarHost g_host;

//A word fits the bar, the full text of an abbreviation may be a paragraph: one line, not too long (what is typed is the full text)
std::wstring barText(const std::string& utf8) {
    const size_t kMaxLength = 36;
    std::wstring line = utf8ToWideString(utf8);
    for (size_t i = 0; i < line.size(); i++) {
        if (line[i] == L'\n' || line[i] == L'\t')
            line[i] = L' ';
    }
    line.erase(std::remove(line.begin(), line.end(), L'\r'), line.end());
    if (line.size() <= kMaxLength)
        return line;
    size_t cut = kMaxLength - 1;
    if (line[cut - 1] >= 0xD800 && line[cut - 1] <= 0xDBFF) //do not cut a surrogate pair in two
        cut--;
    return line.substr(0, cut) + L"…";
}

std::wstring learnedFile() {
    return FeatureStorage::dataFolder() + L"\\learned.txt";
}

std::wstring dictionaryFolder() {
    return FeatureStorage::subFolder(L"Dictionaries");
}

void prepareFolders() {
    std::wstring folder = dictionaryFolder();
    if (folder.empty())
        return;
    std::wstring readme = folder + L"\\README.txt";
    if (GetFileAttributesW(readme.c_str()) != INVALID_FILE_ATTRIBUTES)
        return;
    //a wide literal, because the compiler reads a narrow one in the code page of the machine
    const std::wstring body =
        L"VOpenKey AI - Từ điển gợi ý\r\n\r\n"
        L"Thả các file .txt vào thư mục này rồi bấm \"Tải lại từ điển\" trong cài đặt (hoặc mở lại VOpenKey AI).\r\n"
        L"Mỗi dòng một mục, dùng phím Tab để ngăn cách chữ và số lần dùng:\r\n\r\n"
        L"    xin chào<TAB>3000          một từ và số lần dùng (có thể bỏ số)\r\n"
        L"    xin chào các bạn<TAB>20    nhiều từ: VOpenKey AI học từ nào hay đi sau từ nào\r\n"
        L"    # dòng bắt đầu bằng # là ghi chú\r\n\r\n"
        L"    thiết_kế<TAB>900           từ ghép (nối các âm tiết bằng dấu _): gõ liền \"thietke\" ra \"thiết kế\"\r\n"
        L"    #!compounds                từ dòng này trở xuống, nhiều từ trên một dòng là MỘT từ ghép;\r\n"
        L"                               #!context để quay lại như cũ\r\n\r\n"
        L"\"Từ\" ở đây là một âm tiết giữa hai dấu cách. Không cần gõ đúng dấu: gõ \"hoc\" vẫn tìm ra \"học\".\r\n"
        L"Từ bạn gõ được học và lưu ở file learned.txt trong thư mục cha; xoá file đó để quên hết.\r\n";
    FeatureStorage::writeFile(readme, wideStringToUtf8(body));
}

void loadDictionaries() {
    g_engine->clear(vsuggest::Target::Base);
    g_engine->clear(vsuggest::Target::User);

    //shipped inside the program: a small list with real word counts, then the words of the Vietnamese Wiktionary
    g_engine->loadText(FeatureStorage::resourceText(IDR_DICT_BASE), vsuggest::Target::Base);
    g_engine->loadText(FeatureStorage::resourceText(IDR_DICT_WIKTIONARY), vsuggest::Target::Base);

    //the user's own, in alphabetical order
    std::wstring folder = dictionaryFolder();
    if (!folder.empty()) {
        std::vector<std::wstring> names;
        WIN32_FIND_DATAW found;
        HANDLE search = FindFirstFileW((folder + L"\\*.txt").c_str(), &found);
        if (search != INVALID_HANDLE_VALUE) {
            do {
                if (!(found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && _wcsicmp(found.cFileName, L"README.txt") != 0)
                    names.push_back(found.cFileName);
            } while (FindNextFileW(search, &found));
            FindClose(search);
        }
        std::sort(names.begin(), names.end());
        for (size_t i = 0; i < names.size(); i++)
            g_engine->loadText(FeatureStorage::readFile(folder + L"\\" + names[i]), vsuggest::Target::Base);
    }
    g_engine->loadText(FeatureStorage::readFile(learnedFile()), vsuggest::Target::User);
}

void hideBar() {
    g_generation++;
    g_anchorValid = false;
    g_locateAgain = false;
    g_lastWords.clear();
    SuggestionBar::hide();
}

//--- where the caret is ----------------------------------------------------------------------------------------

//Programs that draw their own caret (Notepad, Word, browsers...) say where it is through accessibility. The question can
//take long when the program is busy, so it is asked on a worker thread, never in the keyboard hook or in the message loop.
DWORD WINAPI caretThread(LPVOID parameter) {
    unsigned generation = (unsigned)(ULONG_PTR)parameter;
    bool found = false;
    RECT line = {0, 0, 0, 0};

    HRESULT com = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    HWND foreground = GetForegroundWindow();
    GUITHREADINFO info = {sizeof(info)};
    HWND target = foreground;
    if (foreground && GetGUIThreadInfo(GetWindowThreadProcessId(foreground, NULL), &info) && info.hwndFocus)
        target = info.hwndFocus;
    if (target) {
        IAccessible* caret = NULL;
        if (SUCCEEDED(AccessibleObjectFromWindow(target, (DWORD)OBJID_CARET, IID_IAccessible, (void**)&caret)) && caret) {
            long left = 0, top = 0, width = 0, height = 0;
            VARIANT self;
            VariantInit(&self);
            self.vt = VT_I4;
            self.lVal = CHILDID_SELF;
            if (SUCCEEDED(caret->accLocation(&left, &top, &width, &height, self)) && (width != 0 || height != 0) &&
                (left != 0 || top != 0)) {
                line.left = left;
                line.top = top;
                line.right = left + width;
                line.bottom = top + (height > 0 ? height : 20);
                found = true;
            }
            caret->Release();
        }
    }
    if (SUCCEEDED(com))
        CoUninitialize();

    EnterCriticalSection(&g_answerLock);
    g_answerFound = found;
    g_answerLine = line;
    LeaveCriticalSection(&g_answerLock);
    HWND bar = SuggestionBar::handle();
    if (bar)
        PostMessageW(bar, SuggestionBar::kMessageCaret, (WPARAM)generation, 0);
    return 0;
}

//The classic caret of a program (edit boxes, many older programs): quick, in the thread of the program
bool classicCaret(RECT& line) {
    HWND foreground = GetForegroundWindow();
    if (!foreground)
        return false;
    GUITHREADINFO info = {sizeof(info)};
    if (!GetGUIThreadInfo(GetWindowThreadProcessId(foreground, NULL), &info) || !info.hwndCaret)
        return false;
    if (info.rcCaret.right == info.rcCaret.left && info.rcCaret.bottom == info.rcCaret.top)
        return false;
    POINT topLeft = {info.rcCaret.left, info.rcCaret.top};
    POINT bottomRight = {info.rcCaret.right, info.rcCaret.bottom};
    if (!ClientToScreen(info.hwndCaret, &topLeft) || !ClientToScreen(info.hwndCaret, &bottomRight))
        return false;
    line.left = topLeft.x;
    line.top = topLeft.y;
    line.right = bottomRight.x;
    line.bottom = bottomRight.y;
    return true;
}

} // namespace

namespace SuggestionController {
bool classicCaretLine(RECT& line) {
    return classicCaret(line);
}
} // namespace SuggestionController

namespace {

void placeBar(const RECT& line) {
    g_lastLine = line;
    g_anchorValid = true;
    SuggestionBar::showBelow(line);
}

//no position for the caret: under the mouse pointer, which at least is where the user is looking
void placeNearPointer() {
    POINT pointer = {0, 0};
    GetCursorPos(&pointer);
    RECT line = {pointer.x, pointer.y, pointer.x, pointer.y + 22};
    SuggestionBar::showBelow(line);
}

void requestLocation() {
    RECT line;
    if (classicCaret(line)) {
        placeBar(line);
        return;
    }
    if (g_locating) {
        g_locateAgain = true;
        return;
    }
    g_locating = true;
    g_locateAgain = false;
    HANDLE thread = CreateThread(NULL, 0, caretThread, (LPVOID)(ULONG_PTR)g_generation, 0, NULL);
    if (thread) {
        CloseHandle(thread);
    } else {
        g_locating = false;
        if (!g_anchorValid)
            placeNearPointer();
    }
}

void showBar(const std::vector<std::wstring>& words, const std::string& typed) {
    g_lastWords = words;
    g_lastTyped = typed;
    SuggestionBar::setWords(words, vSuggestTabAccepts != 0);
    if (g_anchorValid) //where it was, until the application says where the line is now
        SuggestionBar::showBelow(g_lastLine);
    requestLocation();
}

} // namespace

void BarHost::showCandidates(const std::vector<vsuggest::Candidate>& candidates, const std::string& typed) {
    std::vector<std::wstring> words;
    for (size_t i = 0; i < candidates.size(); i++)
        words.push_back(barText(candidates[i].text));
    showBar(words, typed);
}

void BarHost::hideCandidates() {
    hideBar();
}

namespace SuggestionController {

bool isExcludedApplication(const std::string& exeName) {
    std::string lower = exeName;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return (char)tolower(c); });
    for (size_t i = 0; i < sizeof(kExcludedApps) / sizeof(kExcludedApps[0]); i++) {
        if (lower == kExcludedApps[i])
            return true;
    }
    return false;
}

void start(HINSTANCE instance) {
    if (g_started)
        return;
    g_started = true;
    static bool lockReady = false; //the program may stop and start the typing engine again
    if (!lockReady) {
        InitializeCriticalSection(&g_answerLock);
        lockReady = true;
    }

    APP_GET_DATA(vSuggestEnabled, 0);
    APP_GET_DATA(vSuggestNextWord, 1);
    APP_GET_DATA(vSuggestLearn, 1);
    APP_GET_DATA(vSuggestCompounds, 1);
    APP_GET_DATA(vSuggestTabAccepts, 1);
    APP_GET_DATA(vMacroConfirm, 1);

    SuggestionBar::create(instance);
    g_engine.reset(new vsuggest::Engine());
    g_session.reset(new vsuggest::Session(*g_engine, g_host));
    prepareFolders();
    loadDictionaries();

    g_appExcluded = isExcludedApplication(OpenKeyHelper::getFrontMostAppExecuteName());
    applySettings();
}

void stop() {
    if (!g_started)
        return;
    saveLearning();
    hideBar();
    SuggestionBar::destroy();
    vMacroNeedsConfirm = 0;
    g_started = false;
}

void applySettings() {
    if (!g_started)
        return;
    vsuggest::Settings settings;
    //Words and the Unicode table go together: only then does the typing engine know the word on screen. Where the bar cannot be
    //(terminals) abbreviations are replaced at once, as before.
    bool unicode = vCodeTable == 0;
    bool askAboutMacros = vUseMacro && vMacroConfirm && !g_appExcluded && unicode;
    settings.words = vSuggestEnabled && !g_appExcluded && unicode;
    settings.enabled = settings.words || askAboutMacros;
    settings.nextWord = vSuggestNextWord != 0;
    settings.learn = vSuggestLearn != 0;
    settings.compounds = vSuggestCompounds != 0;
    g_session->setSettings(settings);
    vMacroNeedsConfirm = askAboutMacros;
    if (!settings.enabled)
        reset();
}

bool isActive() {
    return g_started && g_session && g_session->settings().enabled;
}

bool isShowing() {
    return g_started && g_session && g_session->isShowing();
}

void reset() {
    if (!g_started)
        return;
    g_session->reset();
    hideBar();
}

void keyProcessed(vsuggest::KeyKind kind, const std::string& word, const std::string& raw, const std::string& macro) {
    if (!g_started || !g_session->settings().enabled)
        return;
    g_session->keyProcessed(kind, word, raw, macro);
    //the suggestions are worked out after the key has been let through, so typing is never held up by them
    HWND bar = SuggestionBar::handle();
    if (bar && !g_refreshPosted) {
        g_refreshPosted = true;
        PostMessageW(bar, SuggestionBar::kMessageRefresh, 0, 0);
    }
}

void refresh() {
    g_refreshPosted = false;
    if (g_started && g_session)
        g_session->refresh();
}

bool accept(int slot, const std::string& currentWord, std::wstring& text, size_t& eraseCount) {
    if (!g_started || slot < 0)
        return false;
    vsuggest::Acceptance acceptance;
    if (!g_session->accept((size_t)slot, currentWord, acceptance))
        return false;
    text = utf8ToWideString(acceptance.text);
    eraseCount = acceptance.eraseCount;
    HWND bar = SuggestionBar::handle();
    if (bar && !g_refreshPosted) {
        g_refreshPosted = true;
        PostMessageW(bar, SuggestionBar::kMessageRefresh, 0, 0);
    }
    return true;
}

void caretFound(unsigned generation) {
    g_locating = false;
    if (!g_started || !g_session->isShowing() || generation != g_generation) {
        //the bar was hidden meanwhile: the answer is for something else, but a bar that is up now needs its own
        if (g_started && g_session->isShowing() && !g_lastWords.empty())
            requestLocation();
        return;
    }
    bool found;
    RECT line;
    EnterCriticalSection(&g_answerLock);
    found = g_answerFound;
    line = g_answerLine;
    LeaveCriticalSection(&g_answerLock);
    if (found)
        placeBar(line);
    else if (!g_anchorValid)
        placeNearPointer();
    if (g_locateAgain)
        requestLocation();
}

void applicationActivated(const std::string& exeName) {
    if (!g_started)
        return;
    g_appExcluded = isExcludedApplication(exeName);
    reset();
    applySettings();
    saveLearning();
}

void saveLearning() {
    if (!g_started || !g_engine || !g_engine->hasUnsavedLearning())
        return;
    FeatureStorage::writeFile(learnedFile(), g_engine->serializeUser());
}

void reloadDictionaries() {
    if (!g_started)
        return;
    saveLearning();
    reset();
    prepareFolders();
    loadDictionaries();
}

void forgetLearnedWords() {
    DeleteFileW(learnedFile().c_str());
    if (!g_started)
        return;
    g_engine->clear(vsuggest::Target::User);
    reset();
}

void openDictionaryFolder() {
    prepareFolders();
    std::wstring folder = dictionaryFolder();
    if (!folder.empty())
        ShellExecuteW(NULL, L"open", folder.c_str(), NULL, NULL, SW_SHOWNORMAL);
}

} // namespace SuggestionController
