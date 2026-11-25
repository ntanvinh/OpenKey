//
//  AISettingsDialog.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "AISettingsDialog.h"
#include "AIClient.h"
#include "AIKeyStore.h"
#include "AISettings.h"
#include "AIText.h"
#include "FeatureActions.h"
#include "FeatureTheme.h"
#include "FeatureWindows.h"
#include "ShortcutField.h"
#include "AIAgentRunner.h"
#include "../../../engine/AIAgent.h"
#include <map>
#include <shellapi.h>
#include <commdlg.h>

#pragma comment(lib, "comdlg32.lib")

namespace {

const wchar_t kClassName[] = L"VOpenKeyAISettings";

enum {
    kIdProvider = 501,
    kIdNote,
    kIdAddress,
    kIdModel,
    kIdModelChoice,
    kIdKey,
    kIdSaveKey,
    kIdRemoveKey,
    kIdGetKey,
    kIdKeyState,
    kIdCopySelection,
    kIdEnabled,
    kIdShortcut,
    kIdStatus,
    kIdBrowse,
    kIdProgramState,
    kIdLoginState,
    kIdLoginGuide,
    kIdLoginCommand,
    kIdCopyCommand,
    kIdOpenTerminal,
    kIdEffort,
    kIdLabel            //the static labels, all with this id (no id needed)
};

HWND g_window = NULL;
HWND g_provider, g_note, g_address, g_model, g_modelChoice, g_key, g_saveKey, g_removeKey, g_getKey, g_keyState,
     g_copySelection, g_enabled, g_shortcut, g_status;
//the programs of the computer (Codex CLI...): found by themselves, so the file is only asked for when it was not found; and the thinking level
HWND g_browse, g_programState, g_effort;
HWND g_labelProvider, g_labelAddress, g_labelProgram, g_labelModel, g_labelEffort, g_labelKey, g_labelAssistant;
HWND g_labelLogin, g_loginState, g_loginGuide, g_loginCommand, g_copyCommand, g_openTerminal;   //signed in or not, and how to sign in
std::map<std::string, vai::agent::LoginStatus> g_logins;   //what each program said last
std::map<std::string, ULONGLONG> g_loginsAsked;
unsigned g_loginRequest = 0;
std::string g_loginRequestFor;
const UINT_PTR kTimerCopied = 1;
bool g_programFound = true;                 //the row of the program is only there when it was not found
std::vector<std::string> g_modelChoiceValues;   //what each row of the box of models of a program stands for: "" = choose for me, or a model
std::map<std::string, std::vector<std::string> > g_serviceModels;   //what each service answered, so the box is not empty between two asks
std::map<std::string, ULONGLONG> g_modelsAsked;   //when the list of each service was asked last: it is asked again by itself
std::vector<std::string> g_effortValues;   //what each row of the level box stands for: "" = choose for me, "default", or a level
HFONT g_font = NULL, g_boldFont = NULL;
HBRUSH g_fieldBrush = NULL, g_backgroundBrush = NULL;
int g_dpi = 96;
unsigned g_modelsRequest = 0;
std::string g_modelsRequestFor;             //the service the request in flight is for
bool g_filling = false;

int px(int at96) {
    return FeatureTheme::scale(at96, g_dpi);
}

std::wstring textOf(HWND control) {
    int length = GetWindowTextLengthW(control);
    std::wstring text((size_t)length + 1, L'\0');
    GetWindowTextW(control, &text[0], length + 1);
    text.resize((size_t)length);
    return text;
}

void setStatus(const std::wstring& text) {
    if (g_status)
        SetWindowTextW(g_status, text.c_str());
}

const vai::Provider& chosenProvider() {
    int row = (int)SendMessageW(g_provider, CB_GETCURSEL, 0, 0);
    const std::vector<vai::Provider>& all = vai::providers();
    return row >= 0 && (size_t)row < all.size() ? all[(size_t)row] : AISettings::provider();
}

std::string trimmed(const std::wstring& text) {
    std::string utf8 = wideStringToUtf8(text);
    size_t a = 0, b = utf8.size();
    while (a < b && (utf8[a] == ' ' || utf8[a] == '\t' || utf8[a] == '\r' || utf8[a] == '\n')) a++;
    while (b > a && (utf8[b - 1] == ' ' || utf8[b - 1] == '\t' || utf8[b - 1] == '\r' || utf8[b - 1] == '\n')) b--;
    return utf8.substr(a, b - a);
}

void showKeyState() {
    const vai::Provider& provider = chosenProvider();
    bool has = AIKeyStore::hasKeyForProvider(provider.id);
    if (!provider.needsKey)
        SetWindowTextW(g_keyState, has ? L"Đã lưu key (không bắt buộc với dịch vụ này)." : L"Không cần key. Chỉ nhập nếu máy chủ của bạn đòi.");
    else
        SetWindowTextW(g_keyState, has ? L"Đã lưu key trên máy này (mã hoá bằng tài khoản Windows)." : L"Chưa có key.");
    EnableWindow(g_removeKey, has);
    EnableWindow(g_getKey, !provider.keyPage.empty());
}

const vai::agent::Agent* chosenAgent() {
    return vai::agent::find(chosenProvider().id);
}

std::wstring nameOfEffort(const std::string& effort) {
    if (effort == "minimal") return L"Tối thiểu";
    if (effort == "low") return L"Thấp (nhanh nhất)";
    if (effort == "medium") return L"Vừa (chậm hơn nhiều)";
    if (effort == "high") return L"Cao (chậm)";
    if (effort == "xhigh") return L"Rất cao";
    if (effort == "max") return L"Tối đa";
    if (effort == "ultra") return L"Siêu cao";
    return utf8ToWideString(effort);
}

//The levels the chosen model takes (the common ones when it is not known), and the one that is saved
void fillEfforts() {
    const vai::agent::Agent* program = chosenAgent();
    if (program == NULL)
        return;
    const vai::Provider& provider = chosenProvider();
    std::vector<vai::agent::Model> models = AIAgentRunner::knownModels(*program);
    std::string model = vai::agent::modelToPass(*program, AISettings::modelFor(provider), models);
    const vai::agent::Model* known = model.empty() ? NULL : vai::agent::findModel(models, model);
    std::vector<std::string> levels = known != NULL && !known->efforts.empty() ? known->efforts : vai::agent::commonEfforts();
    g_filling = true;
    SendMessageW(g_effort, CB_RESETCONTENT, 0, 0);
    g_effortValues.clear();
    g_effortValues.push_back("");
    SendMessageW(g_effort, CB_ADDSTRING, 0, (LPARAM)L"Tự chọn (mức nhanh nhất)");
    g_effortValues.push_back(vai::agent::kEffortProgramDefault);
    SendMessageW(g_effort, CB_ADDSTRING, 0, (LPARAM)L"Mặc định của chương trình");
    for (size_t i = 0; i < levels.size(); i++) {
        g_effortValues.push_back(levels[i]);
        SendMessageW(g_effort, CB_ADDSTRING, 0, (LPARAM)nameOfEffort(levels[i]).c_str());
    }
    std::string saved = AISettings::effortFor(provider);
    int select = 0;
    for (size_t i = 0; i < g_effortValues.size(); i++) {
        if (g_effortValues[i] == saved)
            select = (int)i;
    }
    SendMessageW(g_effort, CB_SETCURSEL, select, 0);
    g_filling = false;
}

//Whether the program is there: the one the user chose, or the one found by its name. Its row is only shown when it was not found.
void showProgram() {
    const vai::agent::Agent* program = chosenAgent();
    if (program == NULL)
        return;
    const vai::Provider& provider = chosenProvider();
    std::wstring chosen = utf8ToWideString(AISettings::programFor(provider));
    g_programFound = !AIAgentRunner::findProgram(*program, chosen).empty();
    if (!g_programFound) {
        std::wstring name = utf8ToWideString(program->displayName);
        SetWindowTextW(g_programState, (L"Chưa tìm thấy " + name + L" trên máy này. Hãy cài " + name +
                                        L" rồi mở lại cửa sổ này, hoặc bấm \"Chọn...\" để chỉ tới chương trình.").c_str());
    }
}

//The box of models of a program: "automatic" and what the program has. A name saved earlier that the program does not list stays at the end.
void fillModelChoice() {
    const vai::agent::Agent* program = chosenAgent();
    if (program == NULL)
        return;
    std::string saved = AISettings::modelFor(chosenProvider());
    std::vector<vai::agent::Model> models = AIAgentRunner::knownModels(*program);
    g_filling = true;
    SendMessageW(g_modelChoice, CB_RESETCONTENT, 0, 0);
    g_modelChoiceValues.clear();
    g_modelChoiceValues.push_back("");
    SendMessageW(g_modelChoice, CB_ADDSTRING, 0, (LPARAM)L"Tự động (khuyên dùng)");
    size_t select = 0;
    for (size_t i = 0; i < models.size(); i++) {
        g_modelChoiceValues.push_back(models[i].id);
        SendMessageW(g_modelChoice, CB_ADDSTRING, 0, (LPARAM)utf8ToWideString(models[i].name.empty() ? models[i].id : models[i].name).c_str());
        if (!saved.empty() && models[i].id == saved)
            select = g_modelChoiceValues.size() - 1;
    }
    if (!saved.empty() && select == 0) {
        g_modelChoiceValues.push_back(saved);
        SendMessageW(g_modelChoice, CB_ADDSTRING, 0, (LPARAM)utf8ToWideString(saved).c_str());
        select = g_modelChoiceValues.size() - 1;
    }
    SendMessageW(g_modelChoice, CB_SETCURSEL, (WPARAM)select, 0);
    g_filling = false;
}

//The box of a service: what it answered the last time
void fillServiceModels() {
    SendMessageW(g_model, CB_RESETCONTENT, 0, 0);
    std::map<std::string, std::vector<std::string> >::const_iterator found = g_serviceModels.find(chosenProvider().id);
    if (found == g_serviceModels.end())
        return;
    for (size_t i = 0; i < found->second.size(); i++)
        SendMessageW(g_model, CB_ADDSTRING, 0, (LPARAM)utf8ToWideString(found->second[i]).c_str());
}

void layout();
void requestModels(bool force);
void requestLogin();
void showLogin();

//The fields show the service that is chosen
void showProvider() {
    const vai::Provider& provider = chosenProvider();
    const vai::agent::Agent* program = chosenAgent();
    g_filling = true;
    std::wstring note = AIText::noteForProvider(provider.id);
    SetWindowTextW(g_note, note.c_str());
    SetWindowTextW(g_address, utf8ToWideString(AISettings::baseUrlFor(provider)).c_str());
    fillServiceModels();
    SetWindowTextW(g_model, utf8ToWideString(AISettings::modelFor(provider)).c_str());      //after the list: emptying a list empties the text
    SetWindowTextW(g_key, L"");
    g_filling = false;
    showKeyState();
    if (program != NULL) {
        showProgram();
        fillModelChoice();
        fillEfforts();
        showLogin();
    }
    layout();
    setStatus(L"");
    requestModels(false);
    requestLogin();
}

void fillProviders() {
    SendMessageW(g_provider, CB_RESETCONTENT, 0, 0);
    const std::vector<vai::Provider>& all = vai::providers();
    std::string current = AISettings::providerId();
    int select = 0;
    for (size_t i = 0; i < all.size(); i++) {
        SendMessageW(g_provider, CB_ADDSTRING, 0, (LPARAM)AIText::displayName(all[i]).c_str());
        if (all[i].id == current)
            select = (int)i;
    }
    SendMessageW(g_provider, CB_SETCURSEL, select, 0);
}

//The address is saved when it is allowed; otherwise the reason is said and nothing changes
bool saveAddress() {
    const vai::Provider& provider = chosenProvider();
    std::string address = trimmed(textOf(g_address));
    if (address.empty() && !provider.baseUrl.empty()) {
        AISettings::setBaseUrl(provider, "");
        SetWindowTextW(g_address, utf8ToWideString(provider.baseUrl).c_str());
        return true;
    }
    vai::AddressProblem problem;
    std::string clean = vai::cleanBaseUrl(address, problem);
    if (clean.empty()) {
        setStatus(AIText::forAddressProblem(problem));
        return false;
    }
    AISettings::setBaseUrl(provider, clean);
    return true;
}

void saveModel() {
    if (chosenAgent() != NULL)
        return;                      //a program has its own box, which saves by itself
    AISettings::setModel(chosenProvider(), trimmed(textOf(g_model)));
}

void saveKey() {
    const vai::Provider& provider = chosenProvider();
    vai::KeyProblem problem;
    std::string key = vai::cleanKey(wideStringToUtf8(textOf(g_key)), problem);
    if (key.empty()) {
        setStatus(AIText::forKeyProblem(problem));
        return;
    }
    if (!AIKeyStore::setKeyForProvider(provider.id, key)) {
        setStatus(L"Không lưu được key. Thử lại.");
        return;
    }
    SecureZeroMemory(&key[0], key.size());
    SetWindowTextW(g_key, L""); //the key is not shown again
    showKeyState();
    setStatus(L"Đã lưu key.");
    requestModels(true);                      //the models of the service can be listed now
}

void removeKey() {
    const vai::Provider& provider = chosenProvider();
    std::wstring question = L"Xoá key của " + AIText::displayName(provider) + L" khỏi máy này?";
    //the destructive button is never the default
    if (MessageBoxW(g_window, question.c_str(), L"Xoá key", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES)
        return;
    AIKeyStore::setKeyForProvider(provider.id, "");
    showKeyState();
    setStatus(L"Đã xoá key.");
}

//The list of models is asked by itself, when the window opens or comes back and when the service changes; once in half a minute at most
//for each service unless `force`. Nothing is said when it fails (no key yet, no network): a name can be typed, and the test of the
//connection tells what is wrong.
void requestModels(bool force) {
    const vai::Provider& provider = chosenProvider();
    bool isProgram = chosenAgent() != NULL;
    ULONGLONG now = GetTickCount64();
    std::map<std::string, ULONGLONG>::const_iterator last = g_modelsAsked.find(provider.id);
    if (!force && last != g_modelsAsked.end() && now - last->second < 30000)
        return;
    vai::Config config;
    std::wstring reason;
    if (!AISettings::configurationFor(provider, false, config, reason)) {
        if (isProgram)
            return;
        //a key typed but not saved yet is used for this one request
        vai::KeyProblem problem;
        std::string typed = vai::cleanKey(wideStringToUtf8(textOf(g_key)), problem);
        if (typed.empty())
            return;
        vai::AddressProblem addressProblem;
        config.provider = provider;
        config.baseUrl = vai::cleanBaseUrl(AISettings::baseUrlFor(provider), addressProblem);
        config.model = AISettings::modelFor(provider);
        config.key = typed;
    }
    if (g_modelsRequest)
        AIClient::cancel(g_modelsRequest);
    g_modelsRequest = AIClient::listModels(config, g_window, reason);
    if (g_modelsRequest) {
        g_modelsRequestFor = provider.id;
        g_modelsAsked[provider.id] = now;
    }
}

// --- signed in or not ---------------------------------------------------------------------------------------------------

//Whether the program says it is signed in: nothing is known before it has answered, and Antigravity has no way to say
bool loginKnown(const vai::agent::Agent& program, vai::agent::LoginStatus& status) {
    std::map<std::string, vai::agent::LoginStatus>::const_iterator found = g_logins.find(program.providerId);
    if (found != g_logins.end()) {
        status = found->second;
        return true;
    }
    return false;
}

//The guide and the command are there unless the program is signed in (or the answer is still awaited)
bool loginNeedsGuide() {
    const vai::agent::Agent* program = chosenAgent();
    if (program == NULL || !g_programFound)
        return false;
    std::vector<std::string> args;
    vai::agent::LoginStatus status;
    bool hasCommand = vai::agent::loginStatusArguments(*program, args);
    if (!loginKnown(*program, status))
        return !hasCommand;
    return status.state != vai::agent::LoginState::SignedIn;
}

bool copyToClipboard(const std::wstring& text) {
    if (!OpenClipboard(g_window))
        return false;
    EmptyClipboard();
    size_t bytes = (text.size() + 1) * sizeof(wchar_t);
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (!memory) {
        CloseClipboard();
        return false;
    }
    memcpy(GlobalLock(memory), text.c_str(), bytes);
    GlobalUnlock(memory);
    if (!SetClipboardData(CF_UNICODETEXT, memory)) {
        GlobalFree(memory);
        CloseClipboard();
        return false;
    }
    CloseClipboard();
    return true;
}

void showLogin() {
    const vai::agent::Agent* program = chosenAgent();
    if (program == NULL || !g_loginState)
        return;
    std::wstring name = utf8ToWideString(program->displayName);
    std::vector<std::string> args;
    bool hasCommand = vai::agent::loginStatusArguments(*program, args);
    vai::agent::LoginStatus status;
    bool known = loginKnown(*program, status);
    std::wstring text;
    if (!known && hasCommand) {
        text = L"Đang kiểm tra...";
    } else if (known && status.state == vai::agent::LoginState::SignedIn) {
        std::wstring how = utf8ToWideString(status.method);
        if (how.find(L"API key") != std::wstring::npos)
            how = L"API key";
        text = !status.account.empty() ? L"\u2713 Đã đăng nhập: " + utf8ToWideString(status.account)
             : !how.empty() ? L"\u2713 Đã đăng nhập bằng " + how : std::wstring(L"\u2713 Đã đăng nhập");
    } else if (known && status.state == vai::agent::LoginState::SignedOut) {
        text = L"Chưa đăng nhập";
    } else if (hasCommand) {
        text = L"Chưa xác định được trạng thái đăng nhập.";
    } else {
        text = name + L" không báo trạng thái đăng nhập. Hãy đăng nhập theo hướng dẫn dưới đây, rồi thử \"Kiểm tra kết nối\" của trợ lý.";
    }
    SetWindowTextW(g_loginState, text.c_str());
    SetWindowTextW(g_loginGuide, (L"Đăng nhập một lần: bấm \"Mở PowerShell\", dán lệnh dưới đây (Ctrl+V) rồi nhấn Enter, làm theo hướng dẫn của " + name +
                                  L". Xong, quay lại cửa sổ này, trạng thái tự cập nhật.").c_str());
    SetWindowTextW(g_loginCommand, utf8ToWideString(program->loginHint).c_str());
    InvalidateRect(g_loginState, NULL, TRUE);
}

//Asks the program, always while nobody is signed in (the user may be doing it in the terminal now, and coming back to the window is what brings the
//answer), once in half a minute at most when somebody is.
void requestLogin() {
    const vai::agent::Agent* program = chosenAgent();
    if (program == NULL || !g_programFound)
        return;
    std::vector<std::string> args;
    if (!vai::agent::loginStatusArguments(*program, args))
        return;
    const vai::Provider& provider = chosenProvider();
    vai::agent::LoginStatus last;
    ULONGLONG now = GetTickCount64();
    std::map<std::string, ULONGLONG>::const_iterator asked = g_loginsAsked.find(provider.id);
    if (loginKnown(*program, last) && last.state == vai::agent::LoginState::SignedIn && asked != g_loginsAsked.end() && now - asked->second < 30000)
        return;
    if (g_loginRequest && g_loginRequestFor == provider.id)
        return;                                          //it is being asked
    vai::Config config;
    std::wstring reason;
    if (!AISettings::configurationFor(provider, false, config, reason))
        return;
    if (g_loginRequest)
        AIAgentRunner::cancel(g_loginRequest);
    g_loginRequest = AIAgentRunner::checkLogin(config, g_window, reason);
    if (g_loginRequest) {
        g_loginRequestFor = provider.id;
        g_loginsAsked[provider.id] = now;
    }
}

//The file of the program: chosen by the user
void browseProgram() {
    const vai::agent::Agent* program = chosenAgent();
    if (program == NULL)
        return;
    wchar_t file[MAX_PATH] = {0};
    static const wchar_t filter[] = L"Chương trình (*.exe;*.cmd;*.bat)\0*.exe;*.cmd;*.bat\0Tất cả các file\0*.*\0";
    OPENFILENAMEW ofn = {sizeof(ofn)};
    ofn.hwndOwner = g_window;
    ofn.lpstrFilter = filter;
    ofn.lpstrFile = file;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrTitle = L"Chọn chương trình";
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR | OFN_HIDEREADONLY;
    if (!GetOpenFileNameW(&ofn))
        return;
    if (!AIAgentRunner::isRunnable(file)) {
        setStatus(L"Tệp này không chạy được (cần .exe, .cmd hoặc .bat).");
        return;
    }
    AISettings::setProgram(chosenProvider(), wideStringToUtf8(file));
    showProgram();
    layout();
    setStatus(L"");
    requestModels(true);
}

HWND child(const wchar_t* cls, const wchar_t* text, DWORD style, int x, int y, int w, int h, int id, DWORD exStyle = 0) {
    HWND control = CreateWindowExW(exStyle, cls, text, WS_CHILD | WS_VISIBLE | style, x, y, w, h, g_window, (HMENU)(INT_PTR)id,
                                   GetModuleHandleW(NULL), NULL);
    SendMessageW(control, WM_SETFONT, (WPARAM)g_font, TRUE);
    return control;
}

HWND sectionLabel(const wchar_t* title) {
    HWND l = child(L"STATIC", title, 0, 0, 0, 10, 10, kIdLabel);
    SendMessageW(l, WM_SETFONT, (WPARAM)g_boldFont, TRUE);
    return l;
}

void build() {
    g_labelProvider = sectionLabel(L"Dịch vụ AI");
    g_provider = child(L"COMBOBOX", L"", WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWNLIST, 0, 0, 10, 10, kIdProvider);
    g_note = child(L"STATIC", L"", 0, 0, 0, 10, 10, kIdNote);

    g_labelAddress = sectionLabel(L"Địa chỉ máy chủ");
    g_address = child(L"EDIT", L"", WS_TABSTOP | ES_AUTOHSCROLL, 0, 0, 10, 10, kIdAddress, WS_EX_CLIENTEDGE);

    g_labelProgram = sectionLabel(L"Chương trình trên máy");
    g_browse = child(L"BUTTON", L"Chọn...", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdBrowse);
    g_programState = child(L"STATIC", L"", 0, 0, 0, 10, 10, kIdProgramState);

    g_labelLogin = sectionLabel(L"Tài khoản");
    g_loginState = child(L"STATIC", L"", 0, 0, 0, 10, 10, kIdLoginState);
    g_loginGuide = child(L"STATIC", L"", 0, 0, 0, 10, 10, kIdLoginGuide);
    g_loginCommand = child(L"EDIT", L"", WS_TABSTOP | ES_READONLY | ES_AUTOHSCROLL, 0, 0, 10, 10, kIdLoginCommand, WS_EX_CLIENTEDGE);
    g_copyCommand = child(L"BUTTON", L"Sao chép lệnh", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdCopyCommand);
    g_openTerminal = child(L"BUTTON", L"Mở PowerShell", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdOpenTerminal);

    g_labelModel = sectionLabel(L"Model");
    g_model = child(L"COMBOBOX", L"", WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWN | CBS_AUTOHSCROLL, 0, 0, 10, 10, kIdModel);
    g_modelChoice = child(L"COMBOBOX", L"", WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWNLIST, 0, 0, 10, 10, kIdModelChoice);

    g_labelEffort = sectionLabel(L"Mức suy nghĩ (càng cao càng chậm, có thể vài chục giây)");
    g_effort = child(L"COMBOBOX", L"", WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWNLIST, 0, 0, 10, 10, kIdEffort);

    g_labelKey = sectionLabel(L"API key");
    g_key = child(L"EDIT", L"", WS_TABSTOP | ES_AUTOHSCROLL | ES_PASSWORD, 0, 0, 10, 10, kIdKey, WS_EX_CLIENTEDGE);
    g_saveKey = child(L"BUTTON", L"Lưu key", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdSaveKey);
    g_removeKey = child(L"BUTTON", L"Xoá key", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdRemoveKey);
    g_keyState = child(L"STATIC", L"", 0, 0, 0, 10, 10, kIdKeyState);
    g_getKey = child(L"BUTTON", L"Lấy key...", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdGetKey);

    g_labelAssistant = sectionLabel(L"Trợ lý AI");
    g_enabled = child(L"BUTTON", L"Bật phím tắt mở trợ lý AI", WS_TABSTOP | BS_AUTOCHECKBOX, 0, 0, 10, 10, kIdEnabled);
    g_shortcut = child(L"EDIT", L"", WS_TABSTOP | ES_READONLY | ES_CENTER, 0, 0, 10, 10, kIdShortcut, WS_EX_CLIENTEDGE);
    g_copySelection = child(L"BUTTON", L"Tự lấy chữ đang chọn khi mở (bằng Ctrl+C, rồi trả lại clipboard)", WS_TABSTOP | BS_AUTOCHECKBOX, 0, 0, 10, 10, kIdCopySelection);
    g_status = child(L"STATIC", L"", 0, 0, 0, 10, 10, kIdStatus);
    ShortcutField::attach(g_shortcut, &vAIHotKey, L"vAIHotKey", setStatus);
    layout();
}

//Where everything goes. A server has an address and a key; a program of the computer has neither, it has a file and a thinking level:
//the window shows one or the other and is as high as what it shows.
void layout() {
    if (!g_labelProvider)
        return;
    bool isProgram = chosenAgent() != NULL;
    int width = px(600);
    int pad = px(16);
    int y = pad;
    int rowHeight = px(28);
    int fieldWidth = width - pad * 2;
    int keyButton = px(96);
    int smallButton = px(100);
    auto place = [&](HWND window, int x, int top, int w, int h, bool visible) {
        ShowWindow(window, visible ? SW_SHOW : SW_HIDE);
        if (visible)
            MoveWindow(window, x, top, w, h, TRUE);
    };

    place(g_labelProvider, pad, y, fieldWidth, px(20), true); y += px(22);
    place(g_provider, pad, y, fieldWidth, px(300), true); y += rowHeight + px(4);
    //a program has a longer note; its height follows the length of the text (about 85 characters to a line at this width)
    int noteLines = 2;
    if (isProgram) {
        int length = GetWindowTextLengthW(g_note);
        noteLines = (std::max)(2, length / 85 + 1);
    }
    int noteHeight = isProgram ? px(noteLines * 17 + 4) : px(36);
    place(g_note, pad, y, fieldWidth, noteHeight, true); y += noteHeight + px(6);

    place(g_labelAddress, pad, y, fieldWidth, px(20), !isProgram);
    if (!isProgram) y += px(22);
    place(g_address, pad, y, fieldWidth, rowHeight, !isProgram);
    if (!isProgram) y += rowHeight + px(10);

    //the row of the program is only there when it was not found: the program is found by itself
    bool programMissing = isProgram && !g_programFound;
    place(g_labelProgram, pad, y, fieldWidth, px(20), programMissing);
    if (programMissing) y += px(22);
    place(g_programState, pad, y, fieldWidth, px(40), programMissing);
    if (programMissing) y += px(44);
    place(g_browse, pad, y, smallButton, rowHeight, programMissing);
    if (programMissing) y += rowHeight + px(10);

    //who is signed in, once the program is found; the guide, the command to paste and the two buttons only while nobody is
    bool loginRow = isProgram && g_programFound;
    bool guide = loginNeedsGuide();
    place(g_labelLogin, pad, y, fieldWidth, px(20), loginRow);
    if (loginRow) y += px(22);
    place(g_loginState, pad, y, fieldWidth, px(36), loginRow);
    if (loginRow) y += px(38);
    place(g_loginGuide, pad, y, fieldWidth, px(52), loginRow && guide);
    if (loginRow && guide) y += px(56);
    place(g_loginCommand, pad, y, fieldWidth, rowHeight, loginRow && guide);
    if (loginRow && guide) y += rowHeight + px(6);
    place(g_copyCommand, pad, y, px(130), rowHeight, loginRow && guide);
    place(g_openTerminal, pad + px(138), y, px(130), rowHeight, loginRow && guide);
    if (loginRow && guide) y += rowHeight + px(10);
    else if (loginRow) y += px(6);

    //the model of a service is typed or chosen; that of a program is only chosen, and is "automatic" by default. The list is asked by itself
    place(g_labelModel, pad, y, fieldWidth, px(20), true); y += px(22);
    place(g_model, pad, y, fieldWidth, px(240), !isProgram);
    place(g_modelChoice, pad, y, fieldWidth, px(240), isProgram);
    y += rowHeight + px(10);

    place(g_labelEffort, pad, y, fieldWidth, px(20), isProgram);
    if (isProgram) y += px(22);
    place(g_effort, pad, y, fieldWidth, px(240), isProgram);
    if (isProgram) y += rowHeight + px(10);

    place(g_labelKey, pad, y, fieldWidth, px(20), !isProgram);
    if (!isProgram) y += px(22);
    place(g_key, pad, y, fieldWidth - keyButton * 2 - px(16), rowHeight, !isProgram);
    place(g_saveKey, width - pad - keyButton * 2 - px(8), y, keyButton, rowHeight, !isProgram);
    place(g_removeKey, width - pad - keyButton, y, keyButton, rowHeight, !isProgram);
    if (!isProgram) y += rowHeight + px(4);
    place(g_keyState, pad, y + px(4), fieldWidth - px(160), px(20), !isProgram);
    place(g_getKey, width - pad - px(150), y, px(150), rowHeight, !isProgram);
    if (!isProgram) y += rowHeight + px(10);

    place(g_labelAssistant, pad, y, fieldWidth, px(20), true); y += px(22);
    place(g_enabled, pad, y, fieldWidth - px(220), px(24), true);
    place(g_shortcut, width - pad - px(200), y - px(2), px(200), rowHeight, true);
    y += rowHeight + px(2);
    place(g_copySelection, pad, y, fieldWidth, px(24), true); y += px(30);
    place(g_status, pad, y, fieldWidth, px(40), true); y += px(46);

    RECT frame = {0, 0, width, y};
    AdjustWindowRect(&frame, WS_CAPTION | WS_SYSMENU, FALSE);
    SetWindowPos(g_window, NULL, 0, 0, frame.right - frame.left, frame.bottom - frame.top, SWP_NOMOVE | SWP_NOZORDER);
    InvalidateRect(g_window, NULL, TRUE);
}

LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_ERASEBKGND: {
        RECT client;
        GetClientRect(window, &client);
        FillRect((HDC)wParam, &client, g_backgroundBrush);
        return 1;
    }
    case WM_CTLCOLOREDIT:
    case WM_CTLCOLORLISTBOX: {
        FeatureTheme::Colors theme = FeatureTheme::colors();
        SetTextColor((HDC)wParam, theme.text);
        SetBkColor((HDC)wParam, theme.field);
        return (LRESULT)g_fieldBrush;
    }
    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLORBTN: {
        FeatureTheme::Colors theme = FeatureTheme::colors();
        int id = GetDlgCtrlID((HWND)lParam);
        bool quiet = id == kIdNote || id == kIdKeyState || id == kIdStatus || id == kIdLoginGuide;
        COLORREF color = quiet ? theme.secondaryText : theme.text;
        if (id == kIdLoginState) {
            vai::agent::LoginStatus status;
            const vai::agent::Agent* program = chosenAgent();
            if (program != NULL && loginKnown(*program, status))
                color = status.state == vai::agent::LoginState::SignedIn ? RGB(46, 160, 67)
                      : status.state == vai::agent::LoginState::SignedOut ? RGB(224, 131, 0) : theme.secondaryText;
        }
        SetTextColor((HDC)wParam, color);
        SetBkColor((HDC)wParam, theme.background);
        return (LRESULT)g_backgroundBrush;
    }
    case WM_COMMAND: {
        int id = LOWORD(wParam), code = HIWORD(wParam);
        if (id == kIdProvider && code == CBN_SELCHANGE) {
            AISettings::setProviderId(chosenProvider().id);
            showProvider();
        } else if (id == kIdAddress && code == EN_KILLFOCUS && !g_filling) {
            if (saveAddress())
                requestModels(true);          //another address, another list
        } else if (id == kIdModel && (code == CBN_KILLFOCUS || code == CBN_SELCHANGE || code == CBN_SELENDOK) && !g_filling) {
            if (code == CBN_SELCHANGE || code == CBN_SELENDOK) {
                //the chosen name is not yet in the text of the box at this moment
                int row = (int)SendMessageW(g_model, CB_GETCURSEL, 0, 0);
                if (row >= 0) {
                    wchar_t name[512] = {0};
                    SendMessageW(g_model, CB_GETLBTEXT, row, (LPARAM)name);
                    AISettings::setModel(chosenProvider(), wideStringToUtf8(name));
                }
            } else {
                saveModel();
            }
        } else if (id == kIdModelChoice && code == CBN_SELCHANGE && !g_filling) {
            int row = (int)SendMessageW(g_modelChoice, CB_GETCURSEL, 0, 0);
            if (row >= 0 && (size_t)row < g_modelChoiceValues.size()) {
                AISettings::setModel(chosenProvider(), g_modelChoiceValues[(size_t)row]);
                fillEfforts(); //the levels belong to the model
            }
        } else if (id == kIdBrowse) {
            browseProgram();
        } else if (id == kIdCopyCommand) {
            const vai::agent::Agent* program = chosenAgent();
            if (program != NULL && copyToClipboard(utf8ToWideString(program->loginHint))) {
                SetWindowTextW(g_copyCommand, L"Đã sao chép \u2713");
                SetTimer(g_window, kTimerCopied, 2000, NULL);
            }
        } else if (id == kIdOpenTerminal) {
            ShellExecuteW(NULL, L"open", L"powershell.exe", NULL, NULL, SW_SHOWNORMAL);
        } else if (id == kIdEffort && code == CBN_SELCHANGE && !g_filling) {
            int row = (int)SendMessageW(g_effort, CB_GETCURSEL, 0, 0);
            if (row >= 0 && (size_t)row < g_effortValues.size())
                AISettings::setEffort(chosenProvider(), g_effortValues[(size_t)row]);
        } else if (id == kIdSaveKey) {
            saveKey();
        } else if (id == kIdRemoveKey) {
            removeKey();
        } else if (id == kIdGetKey) {
            std::wstring page = utf8ToWideString(chosenProvider().keyPage);
            if (!page.empty())
                ShellExecuteW(NULL, L"open", page.c_str(), NULL, NULL, SW_SHOWNORMAL);
        } else if (id == kIdEnabled && code == BN_CLICKED) {
            vAIEnabled = SendMessageW(g_enabled, BM_GETCHECK, 0, 0) == BST_CHECKED ? 1 : 0;
            OpenKeyHelper::setRegInt(L"vAIEnabled", vAIEnabled);
        } else if (id == kIdCopySelection && code == BN_CLICKED) {
            vAICopySelection = SendMessageW(g_copySelection, BM_GETCHECK, 0, 0) == BST_CHECKED ? 1 : 0;
            OpenKeyHelper::setRegInt(L"vAICopySelection", vAICopySelection);
        } else if (id == IDCANCEL) {
            ShowWindow(window, SW_HIDE);
        }
        return 0;
    }
    case WM_TIMER:
        if (wParam == kTimerCopied) {
            KillTimer(window, kTimerCopied);
            SetWindowTextW(g_copyCommand, L"Sao chép lệnh");
        }
        return 0;
    case AIClient::kMessageLogin: {
        AIClient::Login* login = (AIClient::Login*)lParam;
        if (login) {
            if ((unsigned)wParam == g_loginRequest) {
                g_loginRequest = 0;
                g_logins[g_loginRequestFor] = login->status;
                if (g_loginRequestFor == chosenProvider().id) {
                    showLogin();
                    layout();                  //the guide comes or goes with the answer
                }
            }
            delete login;
        }
        return 0;
    }
    case AIClient::kMessageModels: {
        AIClient::Models* models = (AIClient::Models*)lParam;
        if (models) {
            if ((unsigned)wParam == g_modelsRequest) {
                g_modelsRequest = 0;
                //nothing is said when the list could not be had: a name can be typed, and the test of the connection tells what is wrong
                if (models->error.ok() && !models->names.empty() && g_modelsRequestFor == chosenProvider().id) {
                    if (chosenAgent() != NULL) {
                        fillModelChoice();   //the program has said what it offers (its models are known to AIAgentRunner now)
                        fillEfforts();
                    } else {
                        g_serviceModels[g_modelsRequestFor] = models->names;
                        std::wstring current = textOf(g_model);
                        fillServiceModels();
                        SetWindowTextW(g_model, current.c_str());
                    }
                }
            }
            delete models;
        }
        return 0;
    }
    case WM_ACTIVATE:
        //coming back to the window: the program may have been installed, and it may offer new models, in the meantime
        if (LOWORD(wParam) != WA_INACTIVE && g_provider && chosenAgent() != NULL) {
            bool found = g_programFound;
            showProgram();
            if (found != g_programFound)
                layout();
            requestModels(false);
            requestLogin();
        } else if (LOWORD(wParam) != WA_INACTIVE && g_provider) {
            requestModels(false);
        }
        break;
    case WM_CLOSE:
        ShowWindow(window, SW_HIDE);
        return 0;
    case WM_DESTROY:
        FeatureWindows::unregisterDialog(window);
        g_window = NULL;
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

bool create() {
    if (g_window)
        return true;
    HINSTANCE instance = GetModuleHandleW(NULL);
    WNDCLASSEXW wc = {sizeof(wc)};
    wc.lpfnWndProc = windowProc;
    wc.hInstance = instance;
    wc.lpszClassName = kClassName;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hIcon = LoadIcon(instance, MAKEINTRESOURCE(IDI_APP_ICON));
    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;
    g_dpi = FeatureTheme::dpi();
    if (g_font) DeleteObject(g_font);
    if (g_boldFont) DeleteObject(g_boldFont);
    if (g_fieldBrush) DeleteObject(g_fieldBrush);
    if (g_backgroundBrush) DeleteObject(g_backgroundBrush);
    FeatureTheme::Colors theme = FeatureTheme::colors();
    g_font = FeatureTheme::font(10, g_dpi);
    g_boldFont = FeatureTheme::font(10, g_dpi, true);
    g_fieldBrush = CreateSolidBrush(theme.field);
    g_backgroundBrush = CreateSolidBrush(theme.background);

    g_window = CreateWindowExW(0, kClassName, L"Cài đặt AI - VOpenKey AI", WS_CAPTION | WS_SYSMENU | WS_CLIPCHILDREN, CW_USEDEFAULT,
                               CW_USEDEFAULT, px(600), px(700), NULL, NULL, instance, NULL);
    if (!g_window)
        return false;
    FeatureWindows::registerDialog(g_window);
    build();
    return true;
}

} // namespace

namespace AISettingsDialog {

bool isVisible() {
    return g_window && IsWindowVisible(g_window);
}

bool isRecordingShortcut() {
    return ShortcutField::isRecording();
}

void show() {
    if (!create())
        return;
    g_filling = true;
    fillProviders();
    SendMessageW(g_enabled, BM_SETCHECK, vAIEnabled ? BST_CHECKED : BST_UNCHECKED, 0);
    SendMessageW(g_copySelection, BM_SETCHECK, vAICopySelection ? BST_CHECKED : BST_UNCHECKED, 0);
    g_filling = false;
    g_modelsAsked.clear();                       //the window was closed: the lists are asked again
    g_loginsAsked.clear();
    showProvider();
    ShortcutField::refresh();
    ShowWindow(g_window, SW_SHOWNORMAL);
    SetForegroundWindow(g_window);
}

} // namespace AISettingsDialog
