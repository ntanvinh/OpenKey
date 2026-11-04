//
//  SuggestionOptionsDialog.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "SuggestionOptionsDialog.h"
#include "SuggestionController.h"
#include "FeatureTheme.h"
#include "FeatureWindows.h"
#include "../../../engine/AppExclusions.h"
#include "../../../engine/SuggestAppearance.h"
#include <commctrl.h>
#include <commdlg.h>
#include <algorithm>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "comdlg32.lib")

namespace {

namespace appearance = vsuggest::appearance;

const wchar_t kClassName[] = L"VOpenKeyAISuggestionOptions";

enum {
    kIdSlider = 401,
    kIdHoverSlider = 402,
    kIdSliderValue = 403,
    kIdHoverValue = 404,
    kIdEnabled = 405,
    kIdList = 406,
    kIdName = 407,
    kIdAdd = 408,
    kIdBrowse = 409,
    kIdRemove = 410,
    kIdDefaults = 411,
    kIdHint = 412,
    kIdClose = 413
};

const wchar_t kExplanation[] =
    L"Tên là file của chương trình, ví dụ cmd.exe. Mặc định có các cửa sổ dòng lệnh phổ biến, nơi phím Tab dành cho chương trình. "
    L"Tắt công tắc thì danh sách vẫn được giữ.";

HWND g_window = NULL;
HWND g_slider = NULL, g_hoverSlider = NULL, g_sliderValue = NULL, g_hoverValue = NULL;
HWND g_enabled = NULL, g_list = NULL, g_name = NULL, g_add = NULL, g_browse = NULL, g_remove = NULL, g_defaults = NULL, g_hint = NULL;
HFONT g_font = NULL, g_boldFont = NULL;
HBRUSH g_backgroundBrush = NULL, g_fieldBrush = NULL;
int g_dpi = 96;

int px(int at96) {
    return FeatureTheme::scale(at96, g_dpi);
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

std::wstring percent(int value) {
    return std::to_wstring(value) + L"%";
}

void setHint(const std::wstring& text) {
    SetWindowTextW(g_hint, text.c_str());
}

//The hover slider can only go above the normal one: its range follows
void showSliders(bool setNormalSlider = true) {
    if (setNormalSlider) //not while the user drags it
        SendMessageW(g_slider, TBM_SETPOS, TRUE, vSuggestTransparency);
    SendMessageW(g_hoverSlider, TBM_SETRANGE, TRUE, MAKELONG(vSuggestTransparency + 1, appearance::kMaxHoverTransparency));
    SendMessageW(g_hoverSlider, TBM_SETPOS, TRUE, vSuggestHoverTransparency);
    SetWindowTextW(g_sliderValue, percent(vSuggestTransparency).c_str());
    SetWindowTextW(g_hoverValue, percent(vSuggestHoverTransparency).c_str());
}

void fillList(int select) {
    SendMessageW(g_list, LB_RESETCONTENT, 0, 0);
    std::vector<std::string> apps = SuggestionController::excludedApps();
    for (size_t i = 0; i < apps.size(); i++)
        SendMessageW(g_list, LB_ADDSTRING, 0, (LPARAM)utf8ToWideString(apps[i]).c_str());
    if (select >= 0 && (size_t)select < apps.size())
        SendMessageW(g_list, LB_SETCURSEL, select, 0);
    EnableWindow(g_remove, select >= 0 && (size_t)select < apps.size());
}

void refresh() {
    showSliders();
    SendMessageW(g_enabled, BM_SETCHECK, vSuggestExclusionsEnabled ? BST_CHECKED : BST_UNCHECKED, 0);
    fillList(-1);
    setHint(kExplanation);
}

std::wstring textOf(HWND window) {
    int length = GetWindowTextLengthW(window);
    std::wstring text((size_t)length + 1, L'\0');
    GetWindowTextW(window, &text[0], length + 1);
    text.resize((size_t)length);
    return text;
}

//Adds a program by the name the user typed or picked ("putty", "C:\\x\\PuTTY.exe"). False when it is not a name.
bool addProgram(const std::wstring& typed) {
    std::string name = vsuggest::appexclusions::normalizeName(wideStringToUtf8(typed));
    if (name.empty()) {
        setHint(L"Đây không phải tên chương trình. Hãy gõ tên file, ví dụ putty.exe.");
        return false;
    }
    std::vector<std::string> apps = SuggestionController::excludedApps();
    std::vector<std::string>::iterator found = std::find(apps.begin(), apps.end(), name);
    if (found != apps.end()) {
        fillList((int)(found - apps.begin()));
        setHint(utf8ToWideString(name) + L" đã có trong danh sách.");
        return true;
    }
    apps.push_back(name);
    SuggestionController::setExcludedApps(apps);
    fillList((int)apps.size() - 1);
    setHint(L"Đã thêm " + utf8ToWideString(name) + L". Gợi ý sẽ tắt khi bạn chuyển sang chương trình đó.");
    return true;
}

void addTyped() {
    std::wstring typed = textOf(g_name);
    if (addProgram(typed))
        SetWindowTextW(g_name, L"");
    SetFocus(g_name);
}

void browse() {
    wchar_t file[MAX_PATH] = {0};
    //pairs of a description and a pattern, each ended by a zero, and a last zero
    static const wchar_t filter[] = L"Chương trình (*.exe)\0*.exe\0Tất cả các file\0*.*\0";
    OPENFILENAMEW ofn = {sizeof(ofn)};
    ofn.hwndOwner = g_window;
    ofn.lpstrFilter = filter;
    ofn.lpstrFile = file;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrTitle = L"Chọn chương trình cần tắt gợi ý";
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR | OFN_HIDEREADONLY;
    if (GetOpenFileNameW(&ofn))
        addProgram(file);
}

void removeSelected() {
    int row = (int)SendMessageW(g_list, LB_GETCURSEL, 0, 0);
    std::vector<std::string> apps = SuggestionController::excludedApps();
    if (row < 0 || (size_t)row >= apps.size())
        return;
    std::string name = apps[(size_t)row];
    apps.erase(apps.begin() + row);
    SuggestionController::setExcludedApps(apps);
    fillList(apps.empty() ? -1 : (std::min)(row, (int)apps.size() - 1));
    setHint(L"Đã bỏ " + utf8ToWideString(name) + L" khỏi danh sách.");
}

void restoreDefaults() {
    if (MessageBoxW(g_window, L"Đưa danh sách về như lúc mới cài? Các chương trình bạn đã thêm sẽ bị bỏ khỏi danh sách.",
                    L"Khôi phục mặc định", MB_OKCANCEL | MB_ICONQUESTION | MB_DEFBUTTON2) != IDOK)
        return;
    SuggestionController::setExcludedApps(SuggestionController::defaultExcludedApps());
    fillList(-1);
    setHint(L"Đã khôi phục danh sách mặc định.");
}

void build() {
    int width = px(540);
    int y = px(12);
    int labelWidth = px(200), sliderLeft = px(228), sliderWidth = px(230), valueLeft = sliderLeft + sliderWidth + px(8);

    INITCOMMONCONTROLSEX init = {sizeof(init), ICC_BAR_CLASSES};
    InitCommonControlsEx(&init);

    section(L"Độ trong suốt của thanh gợi ý", y, width);
    control(L"STATIC", L"Mặc định", 0, px(24), y + px(4), labelWidth, px(22), 0);
    g_slider = control(TRACKBAR_CLASSW, L"", WS_TABSTOP | TBS_HORZ | TBS_NOTICKS, sliderLeft, y, sliderWidth, px(30), kIdSlider);
    g_sliderValue = control(L"STATIC", L"", SS_RIGHT, valueLeft, y + px(4), width - valueLeft - px(16), px(22), kIdSliderValue);
    y += px(34);
    control(L"STATIC", L"Khi con trỏ nằm trên thanh", 0, px(24), y + px(4), labelWidth, px(22), 0);
    g_hoverSlider = control(TRACKBAR_CLASSW, L"", WS_TABSTOP | TBS_HORZ | TBS_NOTICKS, sliderLeft, y, sliderWidth, px(30), kIdHoverSlider);
    g_hoverValue = control(L"STATIC", L"", SS_RIGHT, valueLeft, y + px(4), width - valueLeft - px(16), px(22), kIdHoverValue);
    y += px(34);
    SendMessageW(g_slider, TBM_SETRANGE, TRUE, MAKELONG(0, appearance::kMaxTransparency));
    SendMessageW(g_slider, TBM_SETPAGESIZE, 0, 5);
    SendMessageW(g_hoverSlider, TBM_SETPAGESIZE, 0, 5);

    section(L"Tự tắt gợi ý trong một số chương trình", y, width);
    g_enabled = control(L"BUTTON", L"Tự tắt gợi ý khi chuyển sang các chương trình trong danh sách", WS_TABSTOP | BS_AUTOCHECKBOX,
                        px(24), y, width - px(40), px(24), kIdEnabled);
    y += px(30);
    g_list = control(L"LISTBOX", L"", WS_VSCROLL | WS_TABSTOP | LBS_NOTIFY | LBS_NOINTEGRALHEIGHT, px(24), y, width - px(48), px(130),
                     kIdList, WS_EX_CLIENTEDGE);
    y += px(138);
    g_name = control(L"EDIT", L"", WS_TABSTOP | ES_AUTOHSCROLL, px(24), y, px(230), px(28), kIdName, WS_EX_CLIENTEDGE);
    SendMessageW(g_name, EM_SETCUEBANNER, FALSE, (LPARAM)L"Tên chương trình, ví dụ putty.exe");
    g_add = control(L"BUTTON", L"Thêm", WS_TABSTOP | BS_DEFPUSHBUTTON, px(262), y, px(80), px(28), kIdAdd);
    g_browse = control(L"BUTTON", L"Chọn chương trình...", WS_TABSTOP | BS_PUSHBUTTON, px(350), y, px(166), px(28), kIdBrowse);
    y += px(36);
    g_remove = control(L"BUTTON", L"Bỏ khỏi danh sách", WS_TABSTOP | BS_PUSHBUTTON, px(24), y, px(166), px(28), kIdRemove);
    g_defaults = control(L"BUTTON", L"Khôi phục mặc định", WS_TABSTOP | BS_PUSHBUTTON, px(198), y, px(166), px(28), kIdDefaults);
    y += px(38);
    g_hint = control(L"STATIC", L"", 0, px(16), y, width - px(32), px(54), kIdHint);
    y += px(58);
    control(L"BUTTON", L"Đóng", WS_TABSTOP | BS_PUSHBUTTON, width - px(16) - px(100), y, px(100), px(30), kIdClose);
    y += px(46);

    RECT frame = {0, 0, width, y};
    AdjustWindowRect(&frame, WS_CAPTION | WS_SYSMENU, FALSE);
    SetWindowPos(g_window, NULL, 0, 0, frame.right - frame.left, frame.bottom - frame.top, SWP_NOMOVE | SWP_NOZORDER);
}

void sliderMoved(HWND slider) {
    int position = (int)SendMessageW(slider, TBM_GETPOS, 0, 0);
    if (slider == g_slider) {
        SuggestionController::setTransparency(position); //may lift the hover level, which the other slider then shows
        showSliders(false);
    } else {
        SuggestionController::setHoverTransparency(position);
        //only the number: the slider that is being dragged is not set again under the hand of the user
        SetWindowTextW(g_hoverValue, percent(vSuggestHoverTransparency).c_str());
    }
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
        SetTextColor((HDC)wParam, GetDlgCtrlID((HWND)lParam) == kIdHint ? theme.secondaryText : theme.text);
        SetBkColor((HDC)wParam, theme.background);
        return (LRESULT)g_backgroundBrush;
    }
    case WM_CTLCOLOREDIT:
    case WM_CTLCOLORLISTBOX: {
        FeatureTheme::Colors theme = FeatureTheme::colors();
        SetTextColor((HDC)wParam, theme.text);
        SetBkColor((HDC)wParam, theme.field);
        return (LRESULT)g_fieldBrush;
    }
    case WM_HSCROLL:
        if ((HWND)lParam == g_slider || (HWND)lParam == g_hoverSlider)
            sliderMoved((HWND)lParam);
        return 0;
    case WM_COMMAND: {
        int id = LOWORD(wParam);
        if (id == kIdEnabled && HIWORD(wParam) == BN_CLICKED) {
            SuggestionController::setExclusionsEnabled(SendMessageW(g_enabled, BM_GETCHECK, 0, 0) == BST_CHECKED);
        } else if (id == kIdList && HIWORD(wParam) == LBN_SELCHANGE) {
            EnableWindow(g_remove, SendMessageW(g_list, LB_GETCURSEL, 0, 0) >= 0);
        } else if (id == kIdAdd) {
            addTyped();
        } else if (id == kIdBrowse) {
            browse();
        } else if (id == kIdRemove) {
            removeSelected();
        } else if (id == kIdDefaults) {
            restoreDefaults();
        } else if (id == kIdClose || id == IDCANCEL) {
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
    if (g_fieldBrush) DeleteObject(g_fieldBrush);
    FeatureTheme::Colors theme = FeatureTheme::colors();
    g_font = FeatureTheme::font(10, g_dpi);
    g_boldFont = FeatureTheme::font(10, g_dpi, true);
    g_backgroundBrush = CreateSolidBrush(theme.background);
    g_fieldBrush = CreateSolidBrush(theme.field);

    g_window = CreateWindowExW(0, kClassName, L"Thanh gợi ý: độ trong suốt và chương trình tự tắt - VOpenKey AI",
                               WS_CAPTION | WS_SYSMENU | WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, px(540), px(560),
                               NULL, NULL, instance, NULL);
    if (!g_window)
        return false;
    FeatureWindows::registerDialog(g_window);
    build();
    return true;
}

} // namespace

namespace SuggestionOptionsDialog {

bool isVisible() {
    return g_window && IsWindowVisible(g_window);
}

void show() {
    if (!create())
        return;
    refresh();
    ShowWindow(g_window, SW_SHOWNORMAL);
    SetForegroundWindow(g_window);
    SetFocus(g_slider);
}

} // namespace SuggestionOptionsDialog
