//
//  FeaturesDialog.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "FeaturesDialog.h"
#include "CaseBar.h"
#include "FeatureActions.h"
#include "FeatureTheme.h"
#include "FeatureWindows.h"
#include "FeatureStorage.h"
#include "../../../engine/Macro.h"
#include "../../../engine/MacroPresets.h"
#include "ShortcutField.h"
#include "AISettingsDialog.h"
#include "SnippetEditor.h"
#include "SnippetService.h"
#include "SuggestionController.h"

namespace {

const wchar_t kClassName[] = L"VOpenKeyAIFeatures";

enum {
    kIdCheckFirst = 300,     //check boxes: 300 + index in kChecks
    kIdShortcutFirst = 340,  //shortcut fields: 340 + index in kShortcuts
    kIdDictionaryFolder = 360,
    kIdReloadDictionary = 361,
    kIdForgetLearned = 362,
    kIdSnippetEditor = 363,
    kIdStatus = 364,
    kIdAISettings = 365,
    kIdMacroPresets = 366
};

struct CheckSpec {
    const wchar_t* text;
    const wchar_t* tip;
    int* variable;
    const wchar_t* registryName;
    bool child;              //drawn indented, belongs to the check box above
};

//the registry name of a setting is the name of its variable, as everywhere in OpenKey (APP_SET_DATA)
const CheckSpec kChecks[] = {
    {L"Hiện thanh gợi ý từ khi gõ", L"Gợi ý từ đang gõ dở và từ tiếp theo; Tab chọn gợi ý đầu, Alt+1 đến Alt+5 chọn gợi ý khác.", &vSuggestEnabled, L"vSuggestEnabled", false},
    {L"Đoán từ tiếp theo sau dấu cách", NULL, &vSuggestNextWord, L"vSuggestNextWord", true},
    {L"Học các từ bạn hay gõ (lưu trên máy này)", NULL, &vSuggestLearn, L"vSuggestLearn", true},
    {L"Gợi ý cả từ ghép (gõ \"thietke\" ra \"thiết kế\")", NULL, &vSuggestCompounds, L"vSuggestCompounds", true},
    {L"Phím Tab chọn gợi ý đầu tiên", L"Tắt đi thì Tab là phím Tab bình thường; vẫn có thể chọn bằng Alt+1 đến Alt+5. Esc tắt thanh gợi ý.", &vSuggestTabAccepts, L"vSuggestTabAccepts", true},
    {L"Gõ tắt: chờ bạn chọn trên thanh gợi ý rồi mới thay", L"Gõ \"vn\" ở cuối \"example.com.vn\" sẽ không bị đổi thành chữ gõ tắt. Chỉ áp dụng với bảng mã Unicode.", &vMacroConfirm, L"vMacroConfirm", false},
    {L"Bật snippet", L"Mở bảng snippet bằng phím tắt, chọn rồi dán vào chỗ đang gõ.", &vSnippetsEnabled, L"vSnippetsEnabled", false},
};
const int kCheckCount = sizeof(kChecks) / sizeof(kChecks[0]);

struct ShortcutSpec {
    const wchar_t* label;
    int* variable;
    const wchar_t* registryName;
};

const ShortcutSpec kShortcuts[] = {
    {L"Phím tắt mở snippet", &vSnippetHotKey, L"vSnippetHotKey"},
    {L"Phím tắt đổi chữ hoa thường cho đoạn đang chọn", &vCaseBarHotKey, L"vCaseBarHotKey"},
    {L"Phím tắt khôi phục từ đang gõ", &vRestoreHotKey, L"vRestoreHotKey"},
};
const int kShortcutCount = sizeof(kShortcuts) / sizeof(kShortcuts[0]);

HWND g_window = NULL;
HWND g_checks[16];
HWND g_fields[8];
HWND g_status = NULL;
HWND g_aiShortcut = NULL;
HFONT g_font = NULL, g_boldFont = NULL;
HBRUSH g_backgroundBrush = NULL;
int g_dpi = 96;

int px(int at96) {
    return FeatureTheme::scale(at96, g_dpi);
}

void setStatus(const std::wstring& text) {
    SetWindowTextW(g_status, text.c_str());
}

void refreshFields() {
    ShortcutField::refresh();
}

void refreshEnabled() {
    //the options of the bar only matter while the bar is on
    for (int i = 0; i < kCheckCount; i++) {
        if (kChecks[i].child)
            EnableWindow(g_checks[i], vSuggestEnabled != 0);
    }
}

void refreshChecks() {
    for (int i = 0; i < kCheckCount; i++)
        SendMessageW(g_checks[i], BM_SETCHECK, *kChecks[i].variable ? BST_CHECKED : BST_UNCHECKED, 0);
    refreshEnabled();
}

HWND control(const wchar_t* cls, const wchar_t* text, DWORD style, int x, int y, int w, int h, int id, DWORD exStyle = 0) {
    HWND c = CreateWindowExW(exStyle, cls, text, WS_CHILD | WS_VISIBLE | style, x, y, w, h, g_window, (HMENU)(INT_PTR)id,
                             GetModuleHandleW(NULL), NULL);
    SendMessageW(c, WM_SETFONT, (WPARAM)g_font, TRUE);
    return c;
}

void section(const wchar_t* title, int& y, int width) {
    y += px(8);
    HWND label = control(L"STATIC", title, 0, px(16), y, width - px(32), px(22), 0);
    SendMessageW(label, WM_SETFONT, (WPARAM)g_boldFont, TRUE);
    y += px(26);
}

void build() {
    int width = px(560);
    int y = px(12);
    int check = 0;

    section(L"Gợi ý từ khi gõ", y, width);
    for (; check < 6; check++) {
        int indent = kChecks[check].child ? px(40) : px(24);
        g_checks[check] = control(L"BUTTON", kChecks[check].text, WS_TABSTOP | BS_AUTOCHECKBOX, indent, y, width - indent - px(16),
                                  px(24), kIdCheckFirst + check);
        y += px(26);
    }
    int buttonWidth = px(170);
    control(L"BUTTON", L"Mở thư mục từ điển", WS_TABSTOP | BS_PUSHBUTTON, px(24), y + px(4), buttonWidth, px(28), kIdDictionaryFolder);
    control(L"BUTTON", L"Tải lại từ điển", WS_TABSTOP | BS_PUSHBUTTON, px(24) + buttonWidth + px(8), y + px(4), px(130), px(28), kIdReloadDictionary);
    control(L"BUTTON", L"Xoá từ đã học", WS_TABSTOP | BS_PUSHBUTTON, px(24) + buttonWidth + px(146), y + px(4), px(130), px(28), kIdForgetLearned);
    y += px(40);
    control(L"BUTTON", L"Thêm gõ tắt phổ biến (ko, dc, vs...)", WS_TABSTOP | BS_PUSHBUTTON, px(24), y, px(300), px(28), kIdMacroPresets);
    y += px(40);

    section(L"Snippet", y, width);
    g_checks[check] = control(L"BUTTON", kChecks[check].text, WS_TABSTOP | BS_AUTOCHECKBOX, px(24), y, width - px(40), px(24), kIdCheckFirst + check);
    check++;
    y += px(28);
    int fieldWidth = px(190);
    control(L"STATIC", kShortcuts[0].label, 0, px(24), y + px(4), width - fieldWidth - px(56), px(22), 0);
    g_fields[0] = control(L"EDIT", L"", WS_TABSTOP | ES_READONLY | ES_CENTER, width - fieldWidth - px(16), y, fieldWidth, px(28), kIdShortcutFirst, WS_EX_CLIENTEDGE);
    y += px(36);
    control(L"BUTTON", L"Quản lý snippet...", WS_TABSTOP | BS_PUSHBUTTON, px(24), y, px(170), px(28), kIdSnippetEditor);
    y += px(40);

    section(L"Công cụ khi gõ và trợ lý AI", y, width);
    for (int i = 1; i < kShortcutCount; i++) {
        control(L"STATIC", kShortcuts[i].label, 0, px(24), y + px(4), width - fieldWidth - px(56), px(22), 0);
        g_fields[i] = control(L"EDIT", L"", WS_TABSTOP | ES_READONLY | ES_CENTER, width - fieldWidth - px(16), y, fieldWidth, px(28),
                              kIdShortcutFirst + i, WS_EX_CLIENTEDGE);
        y += px(36);
    }
    for (int i = 0; i < kShortcutCount; i++)
        ShortcutField::attach(g_fields[i], kShortcuts[i].variable, kShortcuts[i].registryName, setStatus);
    control(L"STATIC", L"Phím tắt mở trợ lý AI (Cài đặt AI)", 0, px(24), y + px(4), width - fieldWidth - px(56), px(22), 0);
    g_aiShortcut = control(L"EDIT", L"", WS_TABSTOP | ES_READONLY | ES_CENTER, width - fieldWidth - px(16), y, fieldWidth, px(28), kIdShortcutFirst + 6, WS_EX_CLIENTEDGE);
    ShortcutField::attach(g_aiShortcut, &vAIHotKey, L"vAIHotKey", setStatus);
    y += px(36);
    control(L"BUTTON", L"Cài đặt AI...", WS_TABSTOP | BS_PUSHBUTTON, px(24), y, px(170), px(28), kIdAISettings);
    y += px(40);
    //the check box of a setting that is the last of the list (snippet) is built above, the one of macros sits with the bar
    g_status = control(L"STATIC", L"", 0, px(16), y + px(4), width - px(32), px(40), kIdStatus);
    y += px(52);

    RECT frame = {0, 0, width, y};
    AdjustWindowRect(&frame, WS_CAPTION | WS_SYSMENU, FALSE);
    SetWindowPos(g_window, NULL, 0, 0, frame.right - frame.left, frame.bottom - frame.top, SWP_NOMOVE | SWP_NOZORDER);
}

//Adds the common abbreviations the user does not have yet; the ones the user has are never replaced
void addMacroPresets() {
    std::vector<vmacro::Preset> presets = vmacro::parsePresets(FeatureStorage::resourceText(IDR_MACRO_PRESETS));
    size_t added = 0;
    for (size_t i = 0; i < presets.size(); i++) {
        if (!hasMacro(presets[i].text) && addMacro(presets[i].text, presets[i].content))
            added++;
    }
    if (added > 0) {
        std::vector<Byte> data;
        getMacroSaveData(data);
        OpenKeyHelper::setRegBinary(_T("macroData"), data.data(), (int)data.size());
        setStatus(L"Đã thêm " + std::to_wstring(added) + L" gõ tắt. Xem và sửa ở \"Cấu hình gõ tắt...\" trong menu của biểu tượng khay.");
    } else {
        setStatus(L"Bạn đã có đủ các gõ tắt phổ biến rồi.");
    }
}

void changeCheck(int index) {
    const CheckSpec& spec = kChecks[index];
    int value = SendMessageW(g_checks[index], BM_GETCHECK, 0, 0) == BST_CHECKED ? 1 : 0;
    *spec.variable = value;
    OpenKeyHelper::setRegInt(spec.registryName, value);
    refreshEnabled();
    SuggestionController::applySettings();
}

LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_ERASEBKGND: {
        RECT client;
        GetClientRect(window, &client);
        FillRect((HDC)wParam, &client, g_backgroundBrush);
        return 1;
    }
    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLORBTN: {
        FeatureTheme::Colors theme = FeatureTheme::colors();
        SetTextColor((HDC)wParam, GetDlgCtrlID((HWND)lParam) == kIdStatus ? theme.secondaryText : theme.text);
        SetBkColor((HDC)wParam, theme.background);
        return (LRESULT)g_backgroundBrush;
    }
    case WM_CTLCOLOREDIT: {
        FeatureTheme::Colors theme = FeatureTheme::colors();
        SetTextColor((HDC)wParam, theme.text);
        SetBkColor((HDC)wParam, theme.field);
        static HBRUSH field = NULL;
        if (field) DeleteObject(field);
        field = CreateSolidBrush(theme.field);
        return (LRESULT)field;
    }
    case WM_COMMAND: {
        int id = LOWORD(wParam);
        if (id >= kIdCheckFirst && id < kIdCheckFirst + kCheckCount && HIWORD(wParam) == BN_CLICKED) {
            changeCheck(id - kIdCheckFirst);
        } else if (id == kIdDictionaryFolder) {
            SuggestionController::openDictionaryFolder();
        } else if (id == kIdReloadDictionary) {
            SuggestionController::reloadDictionaries();
            setStatus(L"Đã tải lại từ điển.");
        } else if (id == kIdForgetLearned) {
            if (MessageBoxW(window, L"Xoá hết các từ VOpenKey AI đã học từ cách bạn gõ? Việc này không hoàn tác được.",
                            L"Xoá từ đã học", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) == IDYES) {
                SuggestionController::forgetLearnedWords();
                setStatus(L"Đã xoá các từ đã học.");
            }
        } else if (id == kIdMacroPresets) {
            addMacroPresets();
        } else if (id == kIdAISettings) {
            AISettingsDialog::show();
        } else if (id == kIdSnippetEditor) {
            SnippetEditor::show();
        } else if (id == IDCANCEL) {
            ShowWindow(window, SW_HIDE);
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
    if (g_backgroundBrush) DeleteObject(g_backgroundBrush);
    g_font = FeatureTheme::font(10, g_dpi);
    g_boldFont = FeatureTheme::font(10, g_dpi, true);
    g_backgroundBrush = CreateSolidBrush(FeatureTheme::colors().background);

    g_window = CreateWindowExW(0, kClassName, L"Gợi ý, snippet và công cụ - VOpenKey AI", WS_CAPTION | WS_SYSMENU | WS_CLIPCHILDREN,
                               CW_USEDEFAULT, CW_USEDEFAULT, px(560), px(600), NULL, NULL, instance, NULL);
    if (!g_window)
        return false;
    FeatureWindows::registerDialog(g_window);
    build();
    return true;
}

} // namespace

namespace FeaturesDialog {

bool isVisible() {
    return g_window && IsWindowVisible(g_window);
}

bool isRecordingShortcut() {
    return ShortcutField::isRecording();
}

void show() {
    if (!create())
        return;
    refreshChecks();
    refreshFields();
    setStatus(L"");
    ShowWindow(g_window, SW_SHOWNORMAL);
    SetForegroundWindow(g_window);
}

} // namespace FeaturesDialog
