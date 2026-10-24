//
//  SnippetPalette.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "SnippetPalette.h"
#include "SnippetEditor.h"
#include "SnippetService.h"
#include "TextInserter.h"
#include "FeatureTheme.h"
#include <algorithm>
#include <ctime>

namespace {

const wchar_t kClassName[] = L"VOpenKeyAISnippetPalette";

//sizes at 96 dpi
const int kWidth = 560;
const int kPadding = 12;
const int kFieldHeight = 32;
const int kRowHeight = 46;
const int kVisibleRows = 6;
const int kPreviewHeight = 96;
const int kFooterHeight = 30;

const int kIdSearch = 101;
const int kIdList = 102;
const int kIdManage = 103;

HWND g_window = NULL;
HWND g_search = NULL;
HWND g_list = NULL;
HWND g_manage = NULL;
HWND g_target = NULL;                 //the program that had the keyboard when the palette opened
std::vector<size_t> g_results;        //positions in the store, best first
int g_dpi = 96;
HFONT g_titleFont = NULL, g_smallFont = NULL, g_fieldFont = NULL;
HBRUSH g_fieldBrush = NULL, g_backgroundBrush = NULL;
WNDPROC g_searchOriginalProc = NULL;
bool g_closing = false;

int px(int at96) {
    return FeatureTheme::scale(at96, g_dpi);
}

//one line of the text for the list: line breaks and runs of spaces made single spaces
std::wstring oneLine(const std::string& utf8) {
    std::wstring text = utf8ToWideString(utf8);
    std::wstring line;
    bool lastSpace = true;
    for (size_t i = 0; i < text.size(); i++) {
        wchar_t c = text[i];
        bool space = c == L' ' || c == L'\n' || c == L'\r' || c == L'\t';
        if (space) {
            if (!lastSpace)
                line += L' ';
            lastSpace = true;
        } else {
            line += c;
            lastSpace = false;
        }
    }
    return line;
}

const vsnippet::Snippet* resultAt(int row) {
    if (row < 0 || (size_t)row >= g_results.size())
        return NULL;
    const std::vector<vsnippet::Snippet>& all = SnippetService::store().snippets();
    return g_results[(size_t)row] < all.size() ? &all[g_results[(size_t)row]] : NULL;
}

void search() {
    wchar_t buffer[512];
    int length = GetWindowTextW(g_search, buffer, 512);
    std::string query = wideStringToUtf8(std::wstring(buffer, length > 0 ? (size_t)length : 0));
    g_results = SnippetService::store().search(query);
    SendMessageW(g_list, LB_SETCOUNT, g_results.size(), 0);
    if (!g_results.empty())
        SendMessageW(g_list, LB_SETCURSEL, 0, 0);
    InvalidateRect(g_window, NULL, FALSE);
}

void moveSelection(int delta) {
    int count = (int)g_results.size();
    if (count == 0)
        return;
    int current = (int)SendMessageW(g_list, LB_GETCURSEL, 0, 0);
    int next = std::max(0, std::min(count - 1, (current < 0 ? 0 : current) + delta));
    SendMessageW(g_list, LB_SETCURSEL, next, 0);
    InvalidateRect(g_window, NULL, FALSE);
}

void insertChosen() {
    int row = (int)SendMessageW(g_list, LB_GETCURSEL, 0, 0);
    const vsnippet::Snippet* snippet = resultAt(row);
    if (!snippet)
        return;
    std::string content = snippet->content;
    size_t position = g_results[(size_t)row];
    HWND target = g_target;
    SnippetPalette::close();
    SnippetService::store().recordUse(position, (double)time(NULL));
    SnippetService::changed();
    TextInserter::insertSnippetContent(content, target);
}

LRESULT CALLBACK searchProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_KEYDOWN) {
        switch (wParam) {
        case VK_DOWN: moveSelection(1); return 0;
        case VK_UP: moveSelection(-1); return 0;
        case VK_NEXT: moveSelection(kVisibleRows); return 0;
        case VK_PRIOR: moveSelection(-kVisibleRows); return 0;
        case VK_RETURN: insertChosen(); return 0;
        case VK_ESCAPE: SnippetPalette::close(); return 0;
        }
    }
    if (message == WM_CHAR && (wParam == VK_RETURN || wParam == VK_ESCAPE))
        return 0; //no beep
    return CallWindowProcW(g_searchOriginalProc, window, message, wParam, lParam);
}

void makeResources() {
    if (g_titleFont) DeleteObject(g_titleFont);
    if (g_smallFont) DeleteObject(g_smallFont);
    if (g_fieldFont) DeleteObject(g_fieldFont);
    if (g_fieldBrush) DeleteObject(g_fieldBrush);
    if (g_backgroundBrush) DeleteObject(g_backgroundBrush);
    FeatureTheme::Colors theme = FeatureTheme::colors();
    g_titleFont = FeatureTheme::font(11, g_dpi, true);
    g_smallFont = FeatureTheme::font(9, g_dpi);
    g_fieldFont = FeatureTheme::font(12, g_dpi);
    g_fieldBrush = CreateSolidBrush(theme.field);
    g_backgroundBrush = CreateSolidBrush(theme.background);
}

void layoutControls() {
    int width = px(kWidth);
    MoveWindow(g_search, px(kPadding), px(kPadding), width - 2 * px(kPadding), px(kFieldHeight), TRUE);
    int listTop = px(kPadding) + px(kFieldHeight) + px(8);
    MoveWindow(g_list, px(kPadding), listTop, width - 2 * px(kPadding), px(kRowHeight) * kVisibleRows, TRUE);
    int footerTop = listTop + px(kRowHeight) * kVisibleRows + px(8) + px(kPreviewHeight) + px(8);
    MoveWindow(g_manage, width - px(kPadding) - px(150), footerTop, px(150), px(kFooterHeight - 2), TRUE);
}

void drawRow(const DRAWITEMSTRUCT* item) {
    const vsnippet::Snippet* snippet = resultAt((int)item->itemID);
    if (!snippet)
        return;
    FeatureTheme::Colors theme = FeatureTheme::colors();
    bool chosen = (item->itemState & ODS_SELECTED) != 0;
    HDC dc = item->hDC;
    RECT row = item->rcItem;
    HBRUSH background = CreateSolidBrush(chosen ? theme.chosen : theme.field);
    FillRect(dc, &row, background);
    DeleteObject(background);
    SetBkMode(dc, TRANSPARENT);

    RECT titleRect = {row.left + px(10), row.top + px(5), row.right - px(10), row.top + px(25)};
    HGDIOBJ old = SelectObject(dc, g_titleFont);
    SetTextColor(dc, chosen ? theme.chosenText : theme.text);
    std::wstring title = utf8ToWideString(snippet->title);
    DrawTextW(dc, title.c_str(), (int)title.size(), &titleRect, DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);

    RECT detailRect = {row.left + px(10), row.top + px(25), row.right - px(10), row.bottom - px(4)};
    SelectObject(dc, g_smallFont);
    SetTextColor(dc, chosen ? theme.chosenText : theme.secondaryText);
    std::wstring detail = oneLine(snippet->content);
    DrawTextW(dc, detail.c_str(), (int)detail.size(), &detailRect, DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
    SelectObject(dc, old);
}

void paintPreview(HDC dc) {
    FeatureTheme::Colors theme = FeatureTheme::colors();
    int top = px(kPadding) + px(kFieldHeight) + px(8) + px(kRowHeight) * kVisibleRows + px(8);
    RECT area = {px(kPadding), top, px(kWidth) - px(kPadding), top + px(kPreviewHeight)};
    HBRUSH field = CreateSolidBrush(theme.field);
    FillRect(dc, &area, field);
    DeleteObject(field);
    FrameRect(dc, &area, (HBRUSH)GetStockObject(GRAY_BRUSH));
    InflateRect(&area, -px(8), -px(6));
    SetBkMode(dc, TRANSPARENT);
    HGDIOBJ old = SelectObject(dc, g_smallFont);
    const vsnippet::Snippet* snippet = resultAt((int)SendMessageW(g_list, LB_GETCURSEL, 0, 0));
    std::wstring text;
    if (snippet) {
        SetTextColor(dc, theme.text);
        text = utf8ToWideString(snippet->content);
    } else {
        //nothing found: say what to do next
        SetTextColor(dc, theme.secondaryText);
        text = g_results.empty() && SnippetService::store().snippets().empty()
                   ? L"Chưa có snippet nào. Bấm \"Quản lý snippet\" để thêm."
                   : L"Không có snippet nào khớp. Thử từ khoá khác, không cần gõ dấu.";
    }
    DrawTextW(dc, text.c_str(), (int)text.size(), &area, DT_WORDBREAK | DT_END_ELLIPSIS | DT_NOPREFIX);
    SelectObject(dc, old);
}

void paint(HWND window) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(window, &ps);
    RECT client;
    GetClientRect(window, &client);
    FeatureTheme::Colors theme = FeatureTheme::colors();
    HBRUSH background = CreateSolidBrush(theme.background);
    FillRect(dc, &client, background);
    DeleteObject(background);
    paintPreview(dc);

    int footerTop = px(kPadding) + px(kFieldHeight) + px(8) + px(kRowHeight) * kVisibleRows + px(8) + px(kPreviewHeight) + px(8);
    RECT hint = {px(kPadding), footerTop, px(kWidth) - px(kPadding) - px(160), footerTop + px(kFooterHeight)};
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, theme.secondaryText);
    HGDIOBJ old = SelectObject(dc, g_smallFont);
    const wchar_t* keys = L"↑↓ chọn   Enter chèn   Esc đóng";
    DrawTextW(dc, keys, -1, &hint, DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
    SelectObject(dc, old);
    EndPaint(window, &ps);
}

LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_PAINT:
        paint(window);
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_MEASUREITEM: {
        MEASUREITEMSTRUCT* measure = (MEASUREITEMSTRUCT*)lParam;
        if (measure->CtlID == kIdList) {
            measure->itemHeight = (UINT)px(kRowHeight);
            return TRUE;
        }
        break;
    }
    case WM_DRAWITEM: {
        DRAWITEMSTRUCT* item = (DRAWITEMSTRUCT*)lParam;
        if (item->CtlID == kIdList && item->itemID != (UINT)-1) {
            drawRow(item);
            return TRUE;
        }
        break;
    }
    case WM_CTLCOLOREDIT: {
        FeatureTheme::Colors theme = FeatureTheme::colors();
        SetTextColor((HDC)wParam, theme.text);
        SetBkColor((HDC)wParam, theme.field);
        return (LRESULT)g_fieldBrush;
    }
    case WM_COMMAND:
        if (LOWORD(wParam) == kIdSearch && HIWORD(wParam) == EN_CHANGE) {
            search();
        } else if (LOWORD(wParam) == kIdList && HIWORD(wParam) == LBN_DBLCLK) {
            insertChosen();
        } else if (LOWORD(wParam) == kIdList && HIWORD(wParam) == LBN_SELCHANGE) {
            InvalidateRect(window, NULL, FALSE);
        } else if (LOWORD(wParam) == kIdManage) {
            SnippetPalette::close();
            SnippetEditor::show();
        }
        return 0;
    case WM_ACTIVATE:
        //a click in another window closes the palette, like a menu
        if (LOWORD(wParam) == WA_INACTIVE && !g_closing && IsWindowVisible(window))
            SnippetPalette::close();
        return 0;
    case WM_CLOSE:
        SnippetPalette::close();
        return 0;
    case WM_DESTROY:
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
    makeResources();

    int width = px(kWidth);
    int height = px(kPadding) + px(kFieldHeight) + px(8) + px(kRowHeight) * kVisibleRows + px(8) + px(kPreviewHeight) +
                 px(8) + px(kFooterHeight) + px(kPadding) - px(8);
    g_window = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kClassName, L"Snippet - VOpenKey AI",
                               WS_POPUP | WS_BORDER, 0, 0, width, height, NULL, NULL, instance, NULL);
    if (!g_window)
        return false;

    g_search = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL, 0, 0, 10, 10,
                               g_window, (HMENU)(INT_PTR)kIdSearch, instance, NULL);
    SendMessageW(g_search, WM_SETFONT, (WPARAM)g_fieldFont, TRUE);
    SendMessageW(g_search, EM_SETCUEBANNER, TRUE, (LPARAM)L"Tìm snippet: tiêu đề, từ khoá hoặc nội dung");
    g_searchOriginalProc = (WNDPROC)SetWindowLongPtrW(g_search, GWLP_WNDPROC, (LONG_PTR)searchProc);

    g_list = CreateWindowExW(0, L"LISTBOX", L"", WS_CHILD | WS_VISIBLE | WS_VSCROLL | LBS_NOTIFY | LBS_OWNERDRAWFIXED | LBS_NODATA |
                                                     LBS_NOINTEGRALHEIGHT,
                             0, 0, 10, 10, g_window, (HMENU)(INT_PTR)kIdList, instance, NULL);
    g_manage = CreateWindowExW(0, L"BUTTON", L"Quản lý snippet...", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 10, 10,
                               g_window, (HMENU)(INT_PTR)kIdManage, instance, NULL);
    SendMessageW(g_manage, WM_SETFONT, (WPARAM)g_smallFont, TRUE);
    SetWindowTextW(g_list, L"Danh sách snippet");
    layoutControls();
    return true;
}

} // namespace

namespace SnippetPalette {

bool isVisible() {
    return g_window && IsWindowVisible(g_window);
}

HWND handle() {
    return g_window;
}

void close() {
    if (!g_window || g_closing)
        return;
    g_closing = true;
    ShowWindow(g_window, SW_HIDE);
    g_closing = false;
}

void toggle() {
    if (isVisible()) {
        close();
        return;
    }
    //the program that has the keyboard now is where the snippet goes
    g_target = GetForegroundWindow();
    if (!create())
        return;
    SetWindowTextW(g_search, L"");
    search();

    //in the middle of the screen the user is working on
    HMONITOR monitor = MonitorFromWindow(g_target ? g_target : GetDesktopWindow(), MONITOR_DEFAULTTONEAREST);
    MONITORINFO info = {sizeof(info)};
    GetMonitorInfoW(monitor, &info);
    RECT rect;
    GetWindowRect(g_window, &rect);
    int width = rect.right - rect.left, height = rect.bottom - rect.top;
    int x = info.rcWork.left + ((info.rcWork.right - info.rcWork.left) - width) / 2;
    int y = info.rcWork.top + ((info.rcWork.bottom - info.rcWork.top) - height) / 3;
    SetWindowPos(g_window, HWND_TOPMOST, x, y, 0, 0, SWP_NOSIZE | SWP_SHOWWINDOW);
    TextInserter::activateWindow(g_window);
    SetFocus(g_search);
}

} // namespace SnippetPalette
