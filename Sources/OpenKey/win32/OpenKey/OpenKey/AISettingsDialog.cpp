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
#include <shellapi.h>

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
    kIdLabel            //the static labels, all with this id (no id needed)
};

HWND g_window = NULL;
HWND g_provider, g_note, g_address, g_model, g_loadModels, g_key, g_saveKey, g_removeKey, g_getKey, g_keyState, g_prompt, g_defaultPrompt,
     g_copySelection, g_enabled, g_shortcut, g_status;
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

//The fields show the service that is chosen
void showProvider() {
    const vai::Provider& provider = chosenProvider();
    g_filling = true;
    std::wstring note = AIText::noteForProvider(provider.id);
    SetWindowTextW(g_note, note.c_str());
    SetWindowTextW(g_address, utf8ToWideString(AISettings::baseUrlFor(provider)).c_str());
    SetWindowTextW(g_model, utf8ToWideString(AISettings::modelFor(provider)).c_str());
    SendMessageW(g_model, CB_RESETCONTENT, 0, 0);
    SetWindowTextW(g_key, L"");
    g_filling = false;
    showKeyState();
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
    if (!saveAddress())
        return;
    saveModel();
    //a key typed but not saved yet is used for this one request
    vai::Config config;
    std::wstring reason;
    if (!AISettings::configurationFor(provider, false, config, reason)) {
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
    setStatus(L"Đang tải danh sách model...");
    EnableWindow(g_loadModels, FALSE);
}

HWND child(const wchar_t* cls, const wchar_t* text, DWORD style, int x, int y, int w, int h, int id, DWORD exStyle = 0) {
    HWND control = CreateWindowExW(exStyle, cls, text, WS_CHILD | WS_VISIBLE | style, x, y, w, h, g_window, (HMENU)(INT_PTR)id,
                                   GetModuleHandleW(NULL), NULL);
    SendMessageW(control, WM_SETFONT, (WPARAM)g_font, TRUE);
    return control;
}

void build() {
    int width = px(600);
    int pad = px(16);
    int y = pad;
    int rowHeight = px(28);
    int fieldWidth = width - pad * 2;

    auto section = [&](const wchar_t* title) {
        HWND l = child(L"STATIC", title, 0, pad, y, fieldWidth, px(20), kIdLabel);
        SendMessageW(l, WM_SETFONT, (WPARAM)g_boldFont, TRUE);
        y += px(22);
    };

    section(L"Dịch vụ AI");
    g_provider = child(L"COMBOBOX", L"", WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWNLIST, pad, y, fieldWidth, px(300), kIdProvider);
    y += rowHeight + px(4);
    g_note = child(L"STATIC", L"", 0, pad, y, fieldWidth, px(36), kIdNote);
    y += px(42);

    section(L"Địa chỉ máy chủ");
    g_address = child(L"EDIT", L"", WS_TABSTOP | ES_AUTOHSCROLL, pad, y, fieldWidth, rowHeight, kIdAddress, WS_EX_CLIENTEDGE);
    y += rowHeight + px(10);

    section(L"Model");
    int loadWidth = px(140);
    g_model = child(L"COMBOBOX", L"", WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWN | CBS_AUTOHSCROLL, pad, y, fieldWidth - loadWidth - px(8), px(240), kIdModel);
    g_loadModels = child(L"BUTTON", L"Tải danh sách", WS_TABSTOP | BS_PUSHBUTTON, width - pad - loadWidth, y, loadWidth, rowHeight, kIdLoadModels);
    y += rowHeight + px(10);

    section(L"API key");
    int keyButton = px(96);
    g_key = child(L"EDIT", L"", WS_TABSTOP | ES_AUTOHSCROLL | ES_PASSWORD, pad, y, fieldWidth - keyButton * 2 - px(16), rowHeight, kIdKey, WS_EX_CLIENTEDGE);
    g_saveKey = child(L"BUTTON", L"Lưu key", WS_TABSTOP | BS_PUSHBUTTON, width - pad - keyButton * 2 - px(8), y, keyButton, rowHeight, kIdSaveKey);
    g_removeKey = child(L"BUTTON", L"Xoá key", WS_TABSTOP | BS_PUSHBUTTON, width - pad - keyButton, y, keyButton, rowHeight, kIdRemoveKey);
    y += rowHeight + px(4);
    g_keyState = child(L"STATIC", L"", 0, pad, y + px(4), fieldWidth - px(160), px(20), kIdKeyState);
    g_getKey = child(L"BUTTON", L"Lấy key...", WS_TABSTOP | BS_PUSHBUTTON, width - pad - px(150), y, px(150), rowHeight, kIdGetKey);
    y += rowHeight + px(10);

    section(L"Lời dặn gửi kèm mỗi yêu cầu");
    g_prompt = child(L"EDIT", L"", WS_TABSTOP | WS_VSCROLL | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN, pad, y, fieldWidth, px(76), kIdPrompt, WS_EX_CLIENTEDGE);
    y += px(80);
    g_defaultPrompt = child(L"BUTTON", L"Dùng lời dặn mặc định", WS_TABSTOP | BS_PUSHBUTTON, pad, y, px(190), rowHeight, kIdDefaultPrompt);
    y += rowHeight + px(10);

    section(L"Trợ lý AI");
    g_enabled = child(L"BUTTON", L"Bật phím tắt mở trợ lý AI", WS_TABSTOP | BS_AUTOCHECKBOX, pad, y, fieldWidth - px(220), px(24), kIdEnabled);
    g_shortcut = child(L"EDIT", L"", WS_TABSTOP | ES_READONLY | ES_CENTER, width - pad - px(200), y - px(2), px(200), rowHeight, kIdShortcut, WS_EX_CLIENTEDGE);
    y += rowHeight + px(2);
    g_copySelection = child(L"BUTTON", L"Tự lấy chữ đang chọn khi mở (bằng Ctrl+C, rồi trả lại clipboard)", WS_TABSTOP | BS_AUTOCHECKBOX, pad, y, fieldWidth, px(24), kIdCopySelection);
    y += px(30);
    g_status = child(L"STATIC", L"", 0, pad, y, fieldWidth, px(40), kIdStatus);
    y += px(46);

    RECT frame = {0, 0, width, y};
    AdjustWindowRect(&frame, WS_CAPTION | WS_SYSMENU, FALSE);
    SetWindowPos(g_window, NULL, 0, 0, frame.right - frame.left, frame.bottom - frame.top, SWP_NOMOVE | SWP_NOZORDER);
    ShortcutField::attach(g_shortcut, &vAIHotKey, L"vAIHotKey", setStatus);
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
        bool quiet = id == kIdNote || id == kIdKeyState || id == kIdStatus;
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
        } else if (id == kIdLoadModels) {
            loadModels();
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
                    setStatus(L"Đã tải " + std::to_wstring(models->names.size()) + L" model. Key và địa chỉ dùng được. Bấm mũi tên ở ô Model để chọn.");
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
