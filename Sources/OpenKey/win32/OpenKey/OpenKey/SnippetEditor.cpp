//
//  SnippetEditor.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "SnippetEditor.h"
#include "SnippetService.h"
#include "FeatureTheme.h"
#include "FeatureWindows.h"
#include <algorithm>

namespace {

const wchar_t kClassName[] = L"VOpenKeyAISnippetEditor";

const int kIdList = 201;
const int kIdTitle = 202;
const int kIdKeywords = 203;
const int kIdContent = 204;
const int kIdAdd = 205;
const int kIdDelete = 206;
const int kIdRestore = 207;
const int kIdHint = 208;

HWND g_window = NULL;
HWND g_list, g_title, g_keywords, g_content, g_add, g_delete, g_restore;
HWND g_labelTitle, g_labelKeywords, g_labelContent, g_hint;
HFONT g_font = NULL;
HBRUSH g_fieldBrush = NULL, g_backgroundBrush = NULL;
int g_dpi = 96;
bool g_filling = false;       //the fields are being filled from the list: that is not an edit by the user
int g_selected = -1;          //position in the store of the snippet in the fields

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

//A multi line edit box gives its line breaks as CR LF; the snippets keep LF
std::string fromEdit(HWND control) {
    std::string text = wideStringToUtf8(textOf(control));
    std::string result;
    for (size_t i = 0; i < text.size(); i++) {
        if (text[i] == '\r' && i + 1 < text.size() && text[i + 1] == '\n')
            continue;
        result += text[i];
    }
    return result;
}

std::wstring toEdit(const std::string& utf8) {
    std::wstring text = utf8ToWideString(utf8);
    std::wstring result;
    for (size_t i = 0; i < text.size(); i++) {
        if (text[i] == L'\n' && (i == 0 || text[i - 1] != L'\r'))
            result += L'\r';
        result += text[i];
    }
    return result;
}

void fillList(int selectPosition) {
    SendMessageW(g_list, LB_RESETCONTENT, 0, 0);
    const std::vector<vsnippet::Snippet>& all = SnippetService::store().snippets();
    for (size_t i = 0; i < all.size(); i++) {
        std::wstring title = utf8ToWideString(all[i].title);
        if (title.empty())
            title = L"(chưa đặt tên)";
        SendMessageW(g_list, LB_ADDSTRING, 0, (LPARAM)title.c_str());
    }
    if (selectPosition >= 0 && (size_t)selectPosition < all.size())
        SendMessageW(g_list, LB_SETCURSEL, selectPosition, 0);
}

void showSelected() {
    int row = (int)SendMessageW(g_list, LB_GETCURSEL, 0, 0);
    const std::vector<vsnippet::Snippet>& all = SnippetService::store().snippets();
    bool valid = row >= 0 && (size_t)row < all.size();
    g_selected = valid ? row : -1;
    g_filling = true;
    SetWindowTextW(g_title, valid ? utf8ToWideString(all[(size_t)row].title).c_str() : L"");
    SetWindowTextW(g_keywords, valid ? utf8ToWideString(all[(size_t)row].keywords).c_str() : L"");
    SetWindowTextW(g_content, valid ? toEdit(all[(size_t)row].content).c_str() : L"");
    g_filling = false;
    EnableWindow(g_title, valid);
    EnableWindow(g_keywords, valid);
    EnableWindow(g_content, valid);
    EnableWindow(g_delete, valid);
    SetWindowTextW(g_hint, valid ? L"{clipboard}, {date} và {time} trong nội dung được thay khi chèn."
                                 : L"Chọn một snippet ở bên trái, hoặc bấm \"Thêm\" để tạo snippet mới.");
}

void editedByUser() {
    if (g_filling || g_selected < 0)
        return;
    SnippetService::store().update((size_t)g_selected, fromEdit(g_title), fromEdit(g_keywords), fromEdit(g_content));
    SnippetService::changed();
    //the title in the list follows what is typed
    std::wstring title = textOf(g_title);
    if (title.empty())
        title = L"(chưa đặt tên)";
    SendMessageW(g_list, LB_DELETESTRING, g_selected, 0);
    SendMessageW(g_list, LB_INSERTSTRING, g_selected, (LPARAM)title.c_str());
    SendMessageW(g_list, LB_SETCURSEL, g_selected, 0);
}

void addSnippet() {
    size_t position = SnippetService::store().add(SnippetService::newIdentifier(), "Snippet mới", "", "");
    SnippetService::changed();
    fillList((int)position);
    showSelected();
    SetFocus(g_title);
    SendMessageW(g_title, EM_SETSEL, 0, -1);
}

void deleteSnippet() {
    if (g_selected < 0)
        return;
    const vsnippet::Snippet& snippet = SnippetService::store().snippets()[(size_t)g_selected];
    std::wstring name = utf8ToWideString(snippet.title);
    std::wstring question = L"Xoá snippet \"" + name + L"\"?";
    if (snippet.isBuiltIn())
        question += L"\n\nĐây là snippet có sẵn. Muốn lấy lại, bấm \"Khôi phục mẫu\".";
    //the destructive button is never the default
    if (MessageBoxW(g_window, question.c_str(), L"Xoá snippet", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES)
        return;
    int position = g_selected;
    SnippetService::store().remove((size_t)position);
    SnippetService::changed();
    int count = (int)SnippetService::store().snippets().size();
    fillList((std::min)(position, count - 1));
    showSelected();
}

void restoreDefaults() {
    if (MessageBoxW(g_window, L"Lấy lại các snippet có sẵn: snippet đã xoá sẽ quay lại, snippet đã sửa trở về bản gốc.\n"
                              L"Snippet của bạn không bị ảnh hưởng.",
                    L"Khôi phục mẫu", MB_OKCANCEL | MB_ICONQUESTION | MB_DEFBUTTON2) != IDOK)
        return;
    SnippetService::store().restoreDefaults(SnippetService::defaultsText());
    SnippetService::changed();
    fillList(g_selected);
    showSelected();
}

void layout() {
    RECT client;
    GetClientRect(g_window, &client);
    int width = client.right, height = client.bottom;
    int pad = px(12), listWidth = (std::max)(px(180), width / 3);
    int buttonHeight = px(30), buttonsTop = height - pad - buttonHeight;

    MoveWindow(g_list, pad, pad, listWidth, buttonsTop - pad * 2, TRUE);
    int buttonWidth = (listWidth - px(8)) / 2;
    MoveWindow(g_add, pad, buttonsTop, buttonWidth, buttonHeight, TRUE);
    MoveWindow(g_delete, pad + buttonWidth + px(8), buttonsTop, buttonWidth, buttonHeight, TRUE);

    int left = pad * 2 + listWidth, right = width - pad;
    int labelHeight = px(20), fieldHeight = px(28);
    int y = pad;
    MoveWindow(g_labelTitle, left, y, right - left, labelHeight, TRUE); y += labelHeight;
    MoveWindow(g_title, left, y, right - left, fieldHeight, TRUE); y += fieldHeight + px(8);
    MoveWindow(g_labelKeywords, left, y, right - left, labelHeight, TRUE); y += labelHeight;
    MoveWindow(g_keywords, left, y, right - left, fieldHeight, TRUE); y += fieldHeight + px(8);
    MoveWindow(g_labelContent, left, y, right - left, labelHeight, TRUE); y += labelHeight;
    int contentBottom = buttonsTop - px(34);
    MoveWindow(g_content, left, y, right - left, (std::max)(px(60), contentBottom - y), TRUE);
    MoveWindow(g_hint, left, contentBottom + px(6), right - left, px(22), TRUE);
    MoveWindow(g_restore, right - px(150), buttonsTop, px(150), buttonHeight, TRUE);
}

HWND child(const wchar_t* cls, const wchar_t* text, DWORD style, int id, DWORD exStyle = 0) {
    HWND control = CreateWindowExW(exStyle, cls, text, WS_CHILD | WS_VISIBLE | style, 0, 0, 10, 10, g_window,
                                   (HMENU)(INT_PTR)id, GetModuleHandleW(NULL), NULL);
    SendMessageW(control, WM_SETFONT, (WPARAM)g_font, TRUE);
    return control;
}

LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_SIZE:
        if (g_list)
            layout();
        return 0;
    case WM_GETMINMAXINFO: {
        MINMAXINFO* info = (MINMAXINFO*)lParam;
        info->ptMinTrackSize.x = px(560);
        info->ptMinTrackSize.y = px(380);
        return 0;
    }
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
    case WM_CTLCOLORSTATIC: {
        FeatureTheme::Colors theme = FeatureTheme::colors();
        SetTextColor((HDC)wParam, GetDlgCtrlID((HWND)lParam) == kIdHint ? theme.secondaryText : theme.text);
        SetBkColor((HDC)wParam, theme.background);
        return (LRESULT)g_backgroundBrush;
    }
    case WM_COMMAND:
        switch (LOWORD(wParam)) {
        case kIdList:
            if (HIWORD(wParam) == LBN_SELCHANGE)
                showSelected();
            break;
        case kIdTitle:
        case kIdKeywords:
        case kIdContent:
            if (HIWORD(wParam) == EN_CHANGE)
                editedByUser();
            break;
        case kIdAdd: addSnippet(); break;
        case kIdDelete: deleteSnippet(); break;
        case kIdRestore: restoreDefaults(); break;
        case IDCANCEL: //Esc
            SnippetService::flush();
            ShowWindow(window, SW_HIDE);
            break;
        }
        return 0;
    case WM_CLOSE:
        SnippetService::flush();
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
    if (g_fieldBrush) DeleteObject(g_fieldBrush);
    if (g_backgroundBrush) DeleteObject(g_backgroundBrush);
    FeatureTheme::Colors theme = FeatureTheme::colors();
    g_font = FeatureTheme::font(10, g_dpi);
    g_fieldBrush = CreateSolidBrush(theme.field);
    g_backgroundBrush = CreateSolidBrush(theme.background);

    g_window = CreateWindowExW(0, kClassName, L"Snippet - VOpenKey AI", WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN, CW_USEDEFAULT,
                               CW_USEDEFAULT, px(760), px(520), NULL, NULL, instance, NULL);
    if (!g_window)
        return false;
    FeatureWindows::registerDialog(g_window);
    g_list = child(L"LISTBOX", L"", WS_VSCROLL | WS_TABSTOP | LBS_NOTIFY | LBS_NOINTEGRALHEIGHT, kIdList, WS_EX_CLIENTEDGE);
    g_labelTitle = child(L"STATIC", L"Tiêu đề", 0, 0);
    g_title = child(L"EDIT", L"", WS_TABSTOP | ES_AUTOHSCROLL, kIdTitle, WS_EX_CLIENTEDGE);
    g_labelKeywords = child(L"STATIC", L"Từ khoá (để tìm, không cần dấu)", 0, 0);
    g_keywords = child(L"EDIT", L"", WS_TABSTOP | ES_AUTOHSCROLL, kIdKeywords, WS_EX_CLIENTEDGE);
    g_labelContent = child(L"STATIC", L"Nội dung", 0, 0);
    g_content = child(L"EDIT", L"", WS_TABSTOP | WS_VSCROLL | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN, kIdContent, WS_EX_CLIENTEDGE);
    g_hint = child(L"STATIC", L"", 0, kIdHint);
    g_add = child(L"BUTTON", L"Thêm", WS_TABSTOP | BS_PUSHBUTTON, kIdAdd);
    g_delete = child(L"BUTTON", L"Xoá", WS_TABSTOP | BS_PUSHBUTTON, kIdDelete);
    g_restore = child(L"BUTTON", L"Khôi phục mẫu", WS_TABSTOP | BS_PUSHBUTTON, kIdRestore);
    SendMessageW(g_content, EM_SETLIMITTEXT, 0, 0); //as long as the user wants
    layout();
    return true;
}

} // namespace

namespace SnippetEditor {

bool isVisible() {
    return g_window && IsWindowVisible(g_window);
}

void show() {
    if (!create())
        return;
    fillList(0);
    showSelected();
    ShowWindow(g_window, SW_SHOWNORMAL);
    SetForegroundWindow(g_window);
    SetFocus(g_list);
}

} // namespace SnippetEditor
