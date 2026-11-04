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
    kIdLoadModels,
    kIdKey,
    kIdSaveKey,
    kIdRemoveKey,
    kIdGetKey,
    kIdKeyState,
    kIdPrompt,
    kIdDefaultPrompt,
    kIdCopySelection,
    kIdEnabled,
    kIdShortcut,
    kIdStatus,
    kIdProgram,
    kIdBrowse,
    kIdFindAgain,
    kIdProgramState,
    kIdEffort,
    kIdImagePrompt,
    kIdDefaultImagePrompt,
    kIdLabel            //the static labels, all with this id (no id needed)
};

HWND g_window = NULL;
HWND g_provider, g_note, g_address, g_model, g_loadModels, g_key, g_saveKey, g_removeKey, g_getKey, g_keyState, g_prompt, g_defaultPrompt,
     g_copySelection, g_enabled, g_shortcut, g_status;
//the programs of the computer (Codex CLI...): where the program is, and the thinking level
HWND g_program, g_browse, g_findAgain, g_programState, g_effort;
HWND g_labelImagePrompt, g_imagePrompt, g_defaultImagePrompt;   //Codex only: the sentence said to it to make a picture
HWND g_labelProvider, g_labelAddress, g_labelProgram, g_labelModel, g_labelEffort, g_labelKey, g_labelPrompt, g_labelAssistant;
std::vector<std::string> g_effortValues;   //what each row of the level box stands for: "" = choose for me, "default", or a level
HFONT g_font = NULL, g_boldFont = NULL;
HBRUSH g_fieldBrush = NULL, g_backgroundBrush = NULL;
int g_dpi = 96;
unsigned g_modelsRequest = 0;
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

//the edit boxes of Windows want CR LF, the settings keep LF
std::wstring toEditText(const std::wstring& text) {
    std::wstring result;
    for (size_t i = 0; i < text.size(); i++) {
        if (text[i] == L'\n' && (i == 0 || text[i - 1] != L'\r'))
            result += L'\r';
        result += text[i];
    }
    return result;
}

std::string fromEditText(const std::wstring& text) {
    std::string utf8 = wideStringToUtf8(text);
    std::string clean;
    for (size_t i = 0; i < utf8.size(); i++) {
        if (utf8[i] == '\r' && i + 1 < utf8.size() && utf8[i + 1] == '\n')
            continue;
        clean += utf8[i];
    }
    return clean;
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

//Where the program is: the one the user chose, or the one found by its name
void showProgram() {
    const vai::agent::Agent* program = chosenAgent();
    if (program == NULL)
        return;
    const vai::Provider& provider = chosenProvider();
    std::wstring chosen = utf8ToWideString(AISettings::programFor(provider));
    std::wstring found = AIAgentRunner::findProgram(*program, chosen);
    SetWindowTextW(g_program, found.c_str());
    if (!found.empty()) {
        SetWindowTextW(g_programState, (!chosen.empty() && found == chosen ? L"Đang dùng tệp bạn đã chọn." : L"Đã tìm thấy trên máy này.") );
    } else {
        std::wstring install = program->installHint.empty() ? std::wstring() : L" Cài bằng: " + utf8ToWideString(program->installHint) + L".";
        SetWindowTextW(g_programState, (L"Không tìm thấy chương trình \"" + utf8ToWideString(program->command) + L"\" trên máy." + install +
                                        L" Hoặc bấm \"Chọn...\" để chỉ tệp.").c_str());
    }
}

void layout();

//The fields show the service that is chosen
void showProvider() {
    const vai::Provider& provider = chosenProvider();
    const vai::agent::Agent* program = chosenAgent();
    g_filling = true;
    std::wstring note = AIText::noteForProvider(provider.id);
    SetWindowTextW(g_note, note.c_str());
    SetWindowTextW(g_address, utf8ToWideString(AISettings::baseUrlFor(provider)).c_str());
    SetWindowTextW(g_model, utf8ToWideString(AISettings::modelFor(provider)).c_str());
    SendMessageW(g_model, CB_RESETCONTENT, 0, 0);
    if (program != NULL) {
        //what the program offers, when it has said already (Claude Code has a list of its own)
        std::vector<vai::agent::Model> models = AIAgentRunner::knownModels(*program);
        for (size_t i = 0; i < models.size(); i++)
            SendMessageW(g_model, CB_ADDSTRING, 0, (LPARAM)utf8ToWideString(models[i].id).c_str());
    }
    SetWindowTextW(g_key, L"");
    g_filling = false;
    showKeyState();
    if (program != NULL) {
        showProgram();
        fillEfforts();
        if (program->canMakeImages)
            SetWindowTextW(g_imagePrompt, toEditText(utf8ToWideString(AISettings::imagePrompt())).c_str());
    }
    layout();
    setStatus(L"");
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

void loadModels() {
    const vai::Provider& provider = chosenProvider();
    bool isProgram = chosenAgent() != NULL;
    if (!isProgram && !saveAddress())
        return;
    saveModel();
    //a key typed but not saved yet is used for this one request
    vai::Config config;
    std::wstring reason;
    if (isProgram) {
        if (!AISettings::configurationFor(provider, false, config, reason)) {
            setStatus(reason);
            return;
        }
    } else if (!AISettings::configurationFor(provider, false, config, reason)) {
        vai::KeyProblem problem;
        std::string typed = vai::cleanKey(wideStringToUtf8(textOf(g_key)), problem);
        if (typed.empty()) {
            setStatus(reason);
            return;
        }
        vai::AddressProblem addressProblem;
        config.provider = provider;
        config.baseUrl = vai::cleanBaseUrl(AISettings::baseUrlFor(provider), addressProblem);
        config.model = AISettings::modelFor(provider);
        config.key = typed;
    } else {
        vai::KeyProblem problem;
        std::string typed = vai::cleanKey(wideStringToUtf8(textOf(g_key)), problem);
        if (!typed.empty())
            config.key = typed;
    }
    if (g_modelsRequest)
        AIClient::cancel(g_modelsRequest);
    g_modelsRequest = AIClient::listModels(config, g_window, reason);
    if (!g_modelsRequest) {
        setStatus(reason);
        return;
    }
    setStatus(isProgram ? L"Đang hỏi chương trình danh sách model (có thể vài giây)..." : L"Đang tải danh sách model...");
    EnableWindow(g_loadModels, FALSE);
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
    setStatus(L"");
}

void findProgramAgain() {
    AISettings::setProgram(chosenProvider(), "");
    showProgram();
    setStatus(L"");
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
    g_program = child(L"EDIT", L"", WS_TABSTOP | ES_READONLY | ES_AUTOHSCROLL, 0, 0, 10, 10, kIdProgram, WS_EX_CLIENTEDGE);
    g_browse = child(L"BUTTON", L"Chọn...", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdBrowse);
    g_findAgain = child(L"BUTTON", L"Tìm lại", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdFindAgain);
    g_programState = child(L"STATIC", L"", 0, 0, 0, 10, 10, kIdProgramState);

    g_labelModel = sectionLabel(L"Model");
    g_model = child(L"COMBOBOX", L"", WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWN | CBS_AUTOHSCROLL, 0, 0, 10, 10, kIdModel);
    g_loadModels = child(L"BUTTON", L"Tải danh sách", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdLoadModels);

    g_labelEffort = sectionLabel(L"Mức suy nghĩ (càng cao càng chậm, có thể vài chục giây)");
    g_effort = child(L"COMBOBOX", L"", WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWNLIST, 0, 0, 10, 10, kIdEffort);

    g_labelImagePrompt = sectionLabel(L"Lệnh tạo ảnh ({prompt} là mô tả của bạn)");
    g_imagePrompt = child(L"EDIT", L"", WS_TABSTOP | WS_VSCROLL | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN, 0, 0, 10, 10, kIdImagePrompt, WS_EX_CLIENTEDGE);
    g_defaultImagePrompt = child(L"BUTTON", L"Dùng lệnh mặc định", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdDefaultImagePrompt);

    g_labelKey = sectionLabel(L"API key");
    g_key = child(L"EDIT", L"", WS_TABSTOP | ES_AUTOHSCROLL | ES_PASSWORD, 0, 0, 10, 10, kIdKey, WS_EX_CLIENTEDGE);
    g_saveKey = child(L"BUTTON", L"Lưu key", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdSaveKey);
    g_removeKey = child(L"BUTTON", L"Xoá key", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdRemoveKey);
    g_keyState = child(L"STATIC", L"", 0, 0, 0, 10, 10, kIdKeyState);
    g_getKey = child(L"BUTTON", L"Lấy key...", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdGetKey);

    g_labelPrompt = sectionLabel(L"Lời dặn gửi kèm mỗi yêu cầu");
    g_prompt = child(L"EDIT", L"", WS_TABSTOP | WS_VSCROLL | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN, 0, 0, 10, 10, kIdPrompt, WS_EX_CLIENTEDGE);
    g_defaultPrompt = child(L"BUTTON", L"Dùng lời dặn mặc định", WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10, kIdDefaultPrompt);

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
    int loadWidth = px(140);
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

    place(g_labelProgram, pad, y, fieldWidth, px(20), isProgram);
    if (isProgram) y += px(22);
    place(g_program, pad, y, fieldWidth - smallButton * 2 - px(16), rowHeight, isProgram);
    place(g_browse, width - pad - smallButton * 2 - px(8), y, smallButton, rowHeight, isProgram);
    place(g_findAgain, width - pad - smallButton, y, smallButton, rowHeight, isProgram);
    if (isProgram) y += rowHeight + px(4);
    place(g_programState, pad, y, fieldWidth, px(40), isProgram);
    if (isProgram) y += px(44);

    place(g_labelModel, pad, y, fieldWidth, px(20), true); y += px(22);
    place(g_model, pad, y, fieldWidth - loadWidth - px(8), px(240), true);
    place(g_loadModels, width - pad - loadWidth, y, loadWidth, rowHeight, true);
    y += rowHeight + px(10);

    place(g_labelEffort, pad, y, fieldWidth, px(20), isProgram);
    if (isProgram) y += px(22);
    place(g_effort, pad, y, fieldWidth, px(240), isProgram);
    if (isProgram) y += rowHeight + px(10);

    //Codex makes pictures: the sentence it is given, with the button that brings the default back on the line of its title
    bool imageRow = chosenAgent() != NULL && chosenAgent()->canMakeImages;
    place(g_labelImagePrompt, pad, y, fieldWidth - px(190), px(20), imageRow);
    place(g_defaultImagePrompt, width - pad - px(180), y - px(3), px(180), px(26), imageRow);
    if (imageRow) y += px(24);
    place(g_imagePrompt, pad, y, fieldWidth, px(50), imageRow);
    if (imageRow) y += px(58);

    place(g_labelKey, pad, y, fieldWidth, px(20), !isProgram);
    if (!isProgram) y += px(22);
    place(g_key, pad, y, fieldWidth - keyButton * 2 - px(16), rowHeight, !isProgram);
    place(g_saveKey, width - pad - keyButton * 2 - px(8), y, keyButton, rowHeight, !isProgram);
    place(g_removeKey, width - pad - keyButton, y, keyButton, rowHeight, !isProgram);
    if (!isProgram) y += rowHeight + px(4);
    place(g_keyState, pad, y + px(4), fieldWidth - px(160), px(20), !isProgram);
    place(g_getKey, width - pad - px(150), y, px(150), rowHeight, !isProgram);
    if (!isProgram) y += rowHeight + px(10);

    place(g_labelPrompt, pad, y, fieldWidth, px(20), true); y += px(22);
    place(g_prompt, pad, y, fieldWidth, px(76), true); y += px(80);
    place(g_defaultPrompt, pad, y, px(190), rowHeight, true); y += rowHeight + px(10);

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
        bool quiet = id == kIdNote || id == kIdKeyState || id == kIdStatus || id == kIdProgramState;
        SetTextColor((HDC)wParam, quiet ? theme.secondaryText : theme.text);
        SetBkColor((HDC)wParam, theme.background);
        return (LRESULT)g_backgroundBrush;
    }
    case WM_COMMAND: {
        int id = LOWORD(wParam), code = HIWORD(wParam);
        if (id == kIdProvider && code == CBN_SELCHANGE) {
            AISettings::setProviderId(chosenProvider().id);
            showProvider();
        } else if (id == kIdAddress && code == EN_KILLFOCUS && !g_filling) {
            saveAddress();
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
            if (chosenAgent() != NULL)
                fillEfforts(); //the levels belong to the model
        } else if (id == kIdLoadModels) {
            loadModels();
        } else if (id == kIdImagePrompt && code == EN_KILLFOCUS) {
            AISettings::setImagePrompt(fromEditText(textOf(g_imagePrompt)));
        } else if (id == kIdDefaultImagePrompt) {
            AISettings::setImagePrompt("");
            SetWindowTextW(g_imagePrompt, toEditText(utf8ToWideString(AISettings::defaultImagePrompt())).c_str());
            setStatus(L"Đã dùng lệnh tạo ảnh mặc định.");
        } else if (id == kIdBrowse) {
            browseProgram();
        } else if (id == kIdFindAgain) {
            findProgramAgain();
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
        } else if (id == kIdPrompt && code == EN_KILLFOCUS) {
            //the line breaks of the box are CR LF; the instruction keeps LF
            std::string prompt = trimmed(textOf(g_prompt));
            std::string clean;
            for (size_t i = 0; i < prompt.size(); i++) {
                if (prompt[i] == '\r' && i + 1 < prompt.size() && prompt[i + 1] == '\n')
                    continue;
                clean += prompt[i];
            }
            AISettings::setSystemPrompt(clean);
        } else if (id == kIdDefaultPrompt) {
            AISettings::setSystemPrompt("");
            std::wstring text = utf8ToWideString(AISettings::defaultSystemPrompt());
            std::wstring edit;
            for (size_t i = 0; i < text.size(); i++) {
                if (text[i] == L'\n') edit += L'\r';
                edit += text[i];
            }
            SetWindowTextW(g_prompt, edit.c_str());
            setStatus(L"Đã dùng lời dặn mặc định.");
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
    case AIClient::kMessageModels: {
        AIClient::Models* models = (AIClient::Models*)lParam;
        if (models) {
            if ((unsigned)wParam == g_modelsRequest) {
                g_modelsRequest = 0;
                EnableWindow(g_loadModels, TRUE);
                if (models->error.ok()) {
                    std::wstring current = textOf(g_model);
                    SendMessageW(g_model, CB_RESETCONTENT, 0, 0);
                    for (size_t i = 0; i < models->names.size(); i++)
                        SendMessageW(g_model, CB_ADDSTRING, 0, (LPARAM)utf8ToWideString(models->names[i]).c_str());
                    SetWindowTextW(g_model, current.c_str());
                    if (chosenAgent() != NULL) {
                        fillEfforts(); //the levels of the models are known now
                        setStatus(L"Đã tải " + std::to_wstring(models->names.size()) + L" model từ chương trình. Bấm mũi tên ở ô Model để chọn; để trống là dùng model nhẹ.");
                    } else {
                        setStatus(L"Đã tải " + std::to_wstring(models->names.size()) + L" model. Key và địa chỉ dùng được. Bấm mũi tên ở ô Model để chọn.");
                    }
                } else {
                    setStatus(models->message);
                }
            }
            delete models;
        }
        return 0;
    }
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
    std::wstring prompt = utf8ToWideString(AISettings::systemPrompt());
    std::wstring edit;
    for (size_t i = 0; i < prompt.size(); i++) {
        if (prompt[i] == L'\n') edit += L'\r';
        edit += prompt[i];
    }
    SetWindowTextW(g_prompt, edit.c_str());
    SendMessageW(g_enabled, BM_SETCHECK, vAIEnabled ? BST_CHECKED : BST_UNCHECKED, 0);
    SendMessageW(g_copySelection, BM_SETCHECK, vAICopySelection ? BST_CHECKED : BST_UNCHECKED, 0);
    g_filling = false;
    showProvider();
    ShortcutField::refresh();
    ShowWindow(g_window, SW_SHOWNORMAL);
    SetForegroundWindow(g_window);
}

} // namespace AISettingsDialog
