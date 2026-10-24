//
//  CaseBar.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "CaseBar.h"
#include "CaseTransformWindows.h"
#include "FeatureTheme.h"
#include "SuggestionController.h"
#include "TextInserter.h"
#include <algorithm>

int vCaseBarHotKey = 0x343; //Ctrl+Alt+C

namespace {

const wchar_t kClassName[] = L"VOpenKeyAICaseBar";

const size_t kMaxLength = 100000;     //a longer text is not a thing to change the case of from a list
const size_t kPreviewLength = 2000;   //the previews and the choice of rows look at the start of the text only
const size_t kPreviewChars = 44;      //characters of the preview on a row
const UINT kEmptyHideMs = 2500;

//sizes at 96 dpi
const int kWidth = 420;
const int kPadding = 6;
const int kRowHeight = 42;
const int kRowGap = 2;
const int kRowRadius = 6;
const int kMessageHeight = 56;

const UINT_PTR kTimerHide = 1;
const UINT kMessageChoose = WM_APP + 51;   //posted by the keyboard hook: the work is done in the message loop, not in the hook

HWND g_window = NULL;
HWND g_target = NULL;
std::u16string g_text;                  //the whole selection
std::vector<vcase::Offer> g_offers;     //computed on the start of it
int g_chosen = 0;
bool g_message = false;                 //the window shows a message instead of rows
std::wstring g_messageText;
int g_dpi = 96;
HFONT g_nameFont = NULL, g_smallFont = NULL, g_hintFont = NULL;

int px(int at96) {
    return FeatureTheme::scale(at96, g_dpi);
}

//a preview is one line of a few characters
std::wstring previewOf(const std::u16string& text) {
    std::wstring wide = CaseTransformWindows::toWide(text);
    std::wstring line;
    bool lastSpace = true;
    for (size_t i = 0; i < wide.size() && line.size() < kPreviewChars + 1; i++) {
        wchar_t c = wide[i];
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
    if (line.size() > kPreviewChars || wide.size() > kPreviewChars * 2) {
        if (line.size() > kPreviewChars)
            line.resize(kPreviewChars);
        if (!line.empty() && line.back() >= 0xD800 && line.back() <= 0xDBFF)
            line.pop_back();
        line += L"…";
    }
    return line;
}

const wchar_t* hintOf(int row) {
    static const wchar_t* hints[10] = {L"Alt+1", L"Alt+2", L"Alt+3", L"Alt+4", L"Alt+5", L"Alt+6", L"Alt+7", L"Alt+8", L"Alt+9", L"Alt+0"};
    return row >= 0 && row < 10 ? hints[row] : L"";
}

void makeFonts() {
    if (g_nameFont) DeleteObject(g_nameFont);
    if (g_smallFont) DeleteObject(g_smallFont);
    if (g_hintFont) DeleteObject(g_hintFont);
    g_nameFont = FeatureTheme::font(11, g_dpi, true);
    g_smallFont = FeatureTheme::font(9, g_dpi);
    g_hintFont = FeatureTheme::font(8, g_dpi);
}

int rowAt(int y) {
    int top = px(kPadding);
    int step = px(kRowHeight) + px(kRowGap);
    if (y < top)
        return -1;
    int row = (y - top) / step;
    return row < (int)g_offers.size() && (y - top) % step < px(kRowHeight) ? row : -1;
}

void paint(HWND window) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(window, &ps);
    RECT client;
    GetClientRect(window, &client);
    FeatureTheme::Colors theme = FeatureTheme::colors();

    HBRUSH background = CreateSolidBrush(theme.background);
    HPEN border = CreatePen(PS_SOLID, 1, theme.border);
    HGDIOBJ oldBrush = SelectObject(dc, background);
    HGDIOBJ oldPen = SelectObject(dc, border);
    int radius = px(kRowRadius + kPadding) * 2;
    RoundRect(dc, 0, 0, client.right, client.bottom, radius, radius);
    SelectObject(dc, oldPen);
    SelectObject(dc, oldBrush);
    DeleteObject(border);
    DeleteObject(background);
    SetBkMode(dc, TRANSPARENT);

    if (g_message) {
        RECT area = {px(14), px(8), client.right - px(14), client.bottom - px(8)};
        HGDIOBJ old = SelectObject(dc, g_smallFont);
        SetTextColor(dc, theme.text);
        DrawTextW(dc, g_messageText.c_str(), (int)g_messageText.size(), &area, DT_WORDBREAK | DT_VCENTER | DT_NOPREFIX);
        SelectObject(dc, old);
        EndPaint(window, &ps);
        return;
    }

    int y = px(kPadding);
    for (size_t i = 0; i < g_offers.size(); i++) {
        bool chosen = (int)i == g_chosen;
        RECT row = {px(kPadding), y, client.right - px(kPadding), y + px(kRowHeight)};
        if (chosen) {
            HBRUSH accent = CreateSolidBrush(theme.chosen);
            HGDIOBJ b = SelectObject(dc, accent);
            HGDIOBJ p = SelectObject(dc, GetStockObject(NULL_PEN));
            int r = px(kRowRadius) * 2;
            RoundRect(dc, row.left, row.top, row.right + 1, row.bottom + 1, r, r);
            SelectObject(dc, p);
            SelectObject(dc, b);
            DeleteObject(accent);
        }
        COLORREF main = chosen ? theme.chosenText : theme.text;
        COLORREF quiet = chosen ? theme.chosenText : theme.secondaryText;

        RECT hint = {row.right - px(46), row.top, row.right - px(8), row.bottom};
        HGDIOBJ old = SelectObject(dc, g_hintFont);
        SetTextColor(dc, quiet);
        DrawTextW(dc, hintOf((int)i), -1, &hint, DT_SINGLELINE | DT_VCENTER | DT_RIGHT | DT_NOPREFIX);

        RECT name = {row.left + px(10), row.top + px(4), hint.left - px(6), row.top + px(22)};
        SelectObject(dc, g_nameFont);
        SetTextColor(dc, main);
        std::wstring nameText = utf8ToWideString(g_offers[i].name);
        DrawTextW(dc, nameText.c_str(), (int)nameText.size(), &name, DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);

        RECT preview = {row.left + px(10), row.top + px(22), hint.left - px(6), row.bottom - px(3)};
        SelectObject(dc, g_smallFont);
        SetTextColor(dc, quiet);
        std::wstring previewText = previewOf(g_offers[i].text);
        DrawTextW(dc, previewText.c_str(), (int)previewText.size(), &preview, DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
        SelectObject(dc, old);
        y += px(kRowHeight) + px(kRowGap);
    }
    EndPaint(window, &ps);
}

std::wstring g_pasteText;
HWND g_pasteTarget = NULL;

//the keys the user used to choose (Alt+3) may still be down: Ctrl+V sent now would be Ctrl+Alt+V
void pasteChosen() {
    TextInserter::insertText(g_pasteText, g_pasteTarget);
    g_pasteText.clear();
}

void choose(int row) {
    if (g_message || row < 0 || (size_t)row >= g_offers.size())
        return;
    vcase::Style style = g_offers[(size_t)row].style;
    std::u16string text = g_text;
    g_pasteTarget = g_target;
    CaseBar::hide();
    //the selection is still selected in the program, pasting replaces it
    g_pasteText = CaseTransformWindows::toWide(vcase::apply(CaseTransformWindows::unicode(), style, text));
    TextInserter::runWhenKeysReleased(pasteChosen);
}

LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_PAINT:
        paint(window);
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE; //a click never takes the keyboard from the program: its selection would go
    case WM_MOUSEMOVE: {
        int row = rowAt((short)HIWORD(lParam));
        if (!g_message && row >= 0 && row != g_chosen) {
            g_chosen = row;
            InvalidateRect(window, NULL, FALSE);
        }
        return 0;
    }
    case WM_LBUTTONUP:
        choose(rowAt((short)HIWORD(lParam)));
        return 0;
    case kMessageChoose:
        choose((int)wParam);
        return 0;
    case WM_TIMER:
        if (wParam == kTimerHide)
            CaseBar::hide();
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
    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;
    g_window = CreateWindowExW(WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, kClassName, L"Đổi chữ hoa thường - VOpenKey AI",
                               WS_POPUP, 0, 0, 10, 10, NULL, NULL, instance, NULL);
    return g_window != NULL;
}

//Shows the window with the size its content needs, under a line of text (screen coordinates)
void present(const RECT& line) {
    g_dpi = FeatureTheme::dpi();
    makeFonts();
    int height = g_message ? px(kMessageHeight)
                           : px(kPadding) * 2 + (int)g_offers.size() * px(kRowHeight) + ((int)g_offers.size() - 1) * px(kRowGap);
    int width = px(kWidth);

    POINT corner = {line.left, line.bottom};
    MONITORINFO monitor = {sizeof(monitor)};
    GetMonitorInfoW(MonitorFromPoint(corner, MONITOR_DEFAULTTONEAREST), &monitor);
    RECT area = monitor.rcWork;
    int margin = px(6);
    int x = (std::max)((int)area.left + margin, (std::min)((int)line.left, (int)area.right - width - margin));
    int y = (int)line.bottom + px(6);
    if (y + height > area.bottom - margin)
        y = (std::max)((int)area.top + margin, (int)line.top - height - px(6));

    SetWindowPos(g_window, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    int round = px(kRowRadius + kPadding) * 2;
    SetWindowRgn(g_window, CreateRoundRectRgn(0, 0, width + 1, height + 1, round, round), TRUE);
    InvalidateRect(g_window, NULL, FALSE);
    SetWindowTextW(g_window, g_message ? g_messageText.c_str() : L"Đổi chữ hoa thường");
}

void showMessage(const wchar_t* text, const RECT& line) {
    g_message = true;
    g_messageText = text;
    g_offers.clear();
    present(line);
    SetTimer(g_window, kTimerHide, kEmptyHideMs, NULL);
}

//The shortcut was pressed and its keys are up: look at what is selected
void openAfterRelease() {
    if (!create())
        return;
    g_target = GetForegroundWindow(); //after the tray menu is gone, this is the program the user was in
    RECT line;
    if (!SuggestionController::classicCaretLine(line)) {
        POINT pointer = {0, 0};
        GetCursorPos(&pointer);
        line.left = pointer.x;
        line.right = pointer.x;
        line.top = pointer.y;
        line.bottom = pointer.y + 20;
    }

    std::wstring selected;
    if (!TextInserter::copySelection(selected)) {
        showMessage(L"Chưa chọn chữ nào. Hãy bôi đen chữ cần đổi rồi nhấn lại phím tắt.", line);
        return;
    }
    if (selected.size() > kMaxLength) {
        showMessage(L"Đoạn chữ dài quá để đổi từ danh sách này (tối đa 100.000 ký tự).", line);
        return;
    }
    g_text = CaseTransformWindows::toU16(selected);
    //the rows depend on what the styles do to the start of the text: a style that changes nothing there is not offered
    std::u16string start = g_text.substr(0, kPreviewLength);
    if (start.size() == kPreviewLength && start[start.size() - 1] >= 0xD800 && start[start.size() - 1] <= 0xDBFF)
        start.resize(start.size() - 1);
    g_offers = vcase::offersForText(CaseTransformWindows::unicode(), start);
    if (g_offers.size() > 10)
        g_offers.resize(10);
    if (g_offers.empty()) {
        showMessage(L"Đoạn chữ này không có gì để đổi hoa thường.", line);
        return;
    }
    //the previews show the start of the whole selection, not of the part the rows were chosen on
    for (size_t i = 0; i < g_offers.size(); i++)
        g_offers[i].text = vcase::apply(CaseTransformWindows::unicode(), g_offers[i].style, g_text.substr(0, kPreviewChars * 4));
    g_message = false;
    g_chosen = 0;
    present(line);
}

} // namespace

namespace CaseBar {

bool isVisible() {
    return g_window && IsWindowVisible(g_window);
}

void hide() {
    if (!g_window)
        return;
    KillTimer(g_window, kTimerHide);
    ShowWindow(g_window, SW_HIDE);
    g_offers.clear();
    g_text.clear();
}

void toggle() {
    if (isVisible()) {
        hide();
        return;
    }
    TextInserter::runWhenKeysReleased(openAfterRelease);
}

bool keyDown(unsigned virtualKey, bool alt, bool control, bool shift, bool win) {
    if (!isVisible())
        return false;
    if (g_message) { //a message goes away with any key, and the key goes on to the program
        hide();
        return false;
    }
    if (!control && !shift && !win) {
        if (!alt) {
            if (virtualKey == VK_DOWN || virtualKey == VK_UP) {
                int count = (int)g_offers.size();
                g_chosen = (g_chosen + (virtualKey == VK_DOWN ? 1 : count - 1)) % count;
                InvalidateRect(g_window, NULL, FALSE);
                return true;
            }
            if (virtualKey == VK_RETURN) {
                PostMessageW(g_window, kMessageChoose, (WPARAM)g_chosen, 0);
                return true;
            }
            if (virtualKey == VK_ESCAPE) {
                hide();
                return true;
            }
        } else if (virtualKey >= '0' && virtualKey <= '9') {
            int row = virtualKey == '0' ? 9 : (int)(virtualKey - '1');
            if ((size_t)row < g_offers.size()) {
                PostMessageW(g_window, kMessageChoose, (WPARAM)row, 0);
                return true;
            }
        }
    }
    hide(); //any other key puts the list away and goes on to the program
    return false;
}

void mouseDown(POINT point) {
    if (!isVisible())
        return;
    RECT bar;
    if (GetWindowRect(g_window, &bar) && PtInRect(&bar, point))
        return;
    hide();
}

} // namespace CaseBar
