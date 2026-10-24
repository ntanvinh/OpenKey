//
//  SuggestionBar.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "SuggestionBar.h"
#include "SuggestionController.h"
#include "FeatureTheme.h"
#include <algorithm>

namespace {

const wchar_t kClassName[] = L"VOpenKeyAISuggestionBar";

//sizes in pixels at 96 dpi, the same as the bar of macOS
const int kItemRadius = 6;
const int kPadding = 4;
const int kItemHeight = 26;
const int kItemPadding = 10;   //left and right of the text inside an item
const int kItemGap = 2;
const int kLabelGap = 6;       //between the key hint and the word
const int kScreenMargin = 6;
const int kDistanceFromText = 4;
const int kHoverDelayMs = 1200; //give the user time to read before the bar yields to the pointer
const BYTE kHoverAlpha = 38;    //0.15: the pointer is over the bar, it is almost gone so the application behind can be read
const UINT_PTR kTimerPointer = 1;
const UINT_PTR kTimerSave = 2;

HWND g_window = NULL;
std::vector<std::wstring> g_words;
bool g_firstUsesTab = true;
std::vector<int> g_itemWidths;   //at the dpi of the last layout
int g_dpi = 96;
bool g_faded = false;
DWORD g_overSince = 0;           //GetTickCount when the pointer came over the bar, 0 when it is not over
HFONT g_wordFont = NULL;
HFONT g_hintFont = NULL;

int scaled(int value) {
    return MulDiv(value, g_dpi, 96);
}

void makeFonts() {
    if (g_wordFont) DeleteObject(g_wordFont);
    if (g_hintFont) DeleteObject(g_hintFont);
    g_wordFont = FeatureTheme::font(12, g_dpi);
    g_hintFont = FeatureTheme::font(9, g_dpi);
}

//Tab for the first one when it is allowed to, Alt+1... for the others
std::wstring hintAt(size_t index) {
    if (index == 0 && g_firstUsesTab)
        return L"Tab";
    return L"Alt+" + std::to_wstring(index + 1);
}

int textWidth(HDC dc, HFONT font, const std::wstring& text) {
    HGDIOBJ old = SelectObject(dc, font);
    SIZE size = {0, 0};
    GetTextExtentPoint32W(dc, text.c_str(), (int)text.size(), &size);
    SelectObject(dc, old);
    return size.cx;
}

SIZE layout(HDC dc) {
    g_itemWidths.clear();
    int width = scaled(kPadding);
    for (size_t i = 0; i < g_words.size(); i++) {
        int item = scaled(kItemPadding) + textWidth(dc, g_hintFont, hintAt(i)) + scaled(kLabelGap) +
                   textWidth(dc, g_wordFont, g_words[i]) + scaled(kItemPadding);
        g_itemWidths.push_back(item);
        width += item + (i > 0 ? scaled(kItemGap) : 0);
    }
    SIZE size = {width + scaled(kPadding), scaled(kItemHeight) + 2 * scaled(kPadding)};
    return size;
}

void paint(HWND window) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(window, &ps);
    RECT client;
    GetClientRect(window, &client);

    //all is drawn in memory first, so the bar does not flicker
    HDC memory = CreateCompatibleDC(dc);
    HBITMAP bitmap = CreateCompatibleBitmap(dc, client.right, client.bottom);
    HGDIOBJ oldBitmap = SelectObject(memory, bitmap);

    FeatureTheme::Colors theme = FeatureTheme::colors();
    COLORREF background = theme.background;
    COLORREF border = theme.border;
    COLORREF textColor = theme.text;
    COLORREF hintColor = theme.secondaryText;
    COLORREF accent = theme.chosen;         //the colours the system itself uses for a chosen item,
    COLORREF accentText = theme.chosenText; //so the text on it can be read

    HBRUSH backgroundBrush = CreateSolidBrush(background);
    HPEN borderPen = CreatePen(PS_SOLID, 1, border);
    HGDIOBJ oldBrush = SelectObject(memory, backgroundBrush);
    HGDIOBJ oldPen = SelectObject(memory, borderPen);
    int barRadius = scaled(kItemRadius + kPadding);
    RoundRect(memory, 0, 0, client.right, client.bottom, barRadius * 2, barRadius * 2);
    SelectObject(memory, oldPen);
    SelectObject(memory, oldBrush);
    DeleteObject(borderPen);
    DeleteObject(backgroundBrush);

    SetBkMode(memory, TRANSPARENT);
    int x = scaled(kPadding);
    int top = scaled(kPadding);
    for (size_t i = 0; i < g_words.size() && i < g_itemWidths.size(); i++) {
        bool chosen = i == 0;
        RECT item = {x, top, x + g_itemWidths[i], top + scaled(kItemHeight)};
        if (chosen) {
            HBRUSH accentBrush = CreateSolidBrush(accent);
            HPEN nullPen = (HPEN)GetStockObject(NULL_PEN);
            HGDIOBJ b = SelectObject(memory, accentBrush);
            HGDIOBJ p = SelectObject(memory, nullPen);
            int radius = scaled(kItemRadius) * 2;
            RoundRect(memory, item.left, item.top, item.right + 1, item.bottom + 1, radius, radius);
            SelectObject(memory, p);
            SelectObject(memory, b);
            DeleteObject(accentBrush);
        }
        std::wstring hint = hintAt(i);
        int left = item.left + scaled(kItemPadding);
        RECT hintRect = {left, item.top, left + textWidth(memory, g_hintFont, hint), item.bottom};
        HGDIOBJ oldFont = SelectObject(memory, g_hintFont);
        SetTextColor(memory, chosen ? accentText : hintColor);
        DrawTextW(memory, hint.c_str(), (int)hint.size(), &hintRect, DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOPREFIX);
        RECT wordRect = {hintRect.right + scaled(kLabelGap), item.top, item.right - scaled(kItemPadding), item.bottom};
        SelectObject(memory, g_wordFont);
        SetTextColor(memory, chosen ? accentText : textColor);
        DrawTextW(memory, g_words[i].c_str(), (int)g_words[i].size(), &wordRect,
                  DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOPREFIX);
        SelectObject(memory, oldFont);
        x += g_itemWidths[i] + scaled(kItemGap);
    }

    BitBlt(dc, 0, 0, client.right, client.bottom, memory, 0, 0, SRCCOPY);
    SelectObject(memory, oldBitmap);
    DeleteObject(bitmap);
    DeleteDC(memory);
    EndPaint(window, &ps);
}

void setAlpha(BYTE alpha) {
    SetLayeredWindowAttributes(g_window, 0, alpha, LWA_ALPHA);
}

//The bar ignores the mouse, so the pointer is looked at from time to time while the bar is up
void updateFadeForPointer() {
    POINT pointer;
    RECT bar;
    bool over = IsWindowVisible(g_window) && GetCursorPos(&pointer) && GetWindowRect(g_window, &bar) && PtInRect(&bar, pointer);
    if (!over) {
        g_overSince = 0;
        if (g_faded) {
            g_faded = false;
            setAlpha(255);
        }
        return;
    }
    if (g_faded)
        return;
    DWORD now = GetTickCount();
    if (g_overSince == 0)
        g_overSince = now;
    if (now - g_overSince >= (DWORD)kHoverDelayMs) {
        g_faded = true;
        setAlpha(kHoverAlpha);
    }
}

LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_PAINT:
        paint(window);
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_NCHITTEST:
        return HTTRANSPARENT;
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    case WM_TIMER:
        if (wParam == kTimerPointer)
            updateFadeForPointer();
        else if (wParam == kTimerSave)
            SuggestionController::saveLearning();

        return 0;
    case SuggestionBar::kMessageRefresh:
        SuggestionController::refresh();
        return 0;
    case SuggestionBar::kMessageCaret:
        SuggestionController::caretFound((unsigned)wParam);
        return 0;
    case WM_SETTINGCHANGE: //light or dark may have changed
        InvalidateRect(window, NULL, FALSE);
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

} // namespace

bool SuggestionBar::create(HINSTANCE instance) {
    if (g_window)
        return true;
    WNDCLASSEXW wc = {sizeof(wc)};
    wc.lpfnWndProc = windowProc;
    wc.hInstance = instance;
    wc.lpszClassName = kClassName;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;
    //never activated, never hit by the mouse, not in the taskbar or in Alt+Tab, always on top
    g_window = CreateWindowExW(WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_TRANSPARENT,
                               kClassName, L"VOpenKey AI suggestions", WS_POPUP, 0, 0, 10, 10, NULL, NULL, instance, NULL);
    if (!g_window)
        return false;
    setAlpha(255);
    SetTimer(g_window, kTimerSave, 60000, NULL);
    return true;
}

void SuggestionBar::destroy() {
    if (g_window) {
        DestroyWindow(g_window);
        g_window = NULL;
    }
    if (g_wordFont) DeleteObject(g_wordFont);
    if (g_hintFont) DeleteObject(g_hintFont);
    g_wordFont = g_hintFont = NULL;
}

HWND SuggestionBar::handle() {
    return g_window;
}

void SuggestionBar::setWords(const std::vector<std::wstring>& words, bool firstUsesTab) {
    if (!g_window)
        return;
    g_words = words;
    g_firstUsesTab = firstUsesTab;

    HDC screen = GetDC(NULL);
    g_dpi = GetDeviceCaps(screen, LOGPIXELSX);
    makeFonts();
    SIZE size = layout(screen);
    ReleaseDC(NULL, screen);

    //a screen reader reads the name of the window
    std::wstring name;
    for (size_t i = 0; i < words.size(); i++)
        name += (i > 0 ? L", " : L"") + words[i];
    SetWindowTextW(g_window, name.c_str());

    SetWindowPos(g_window, HWND_TOPMOST, 0, 0, size.cx, size.cy, SWP_NOMOVE | SWP_NOACTIVATE);
    int radius = scaled(kItemRadius + kPadding) * 2;
    SetWindowRgn(g_window, CreateRoundRectRgn(0, 0, size.cx + 1, size.cy + 1, radius, radius), TRUE);
    InvalidateRect(g_window, NULL, FALSE);
}

void SuggestionBar::showBelow(const RECT& line) {
    if (!g_window)
        return;
    RECT bar;
    GetWindowRect(g_window, &bar);
    int width = bar.right - bar.left, height = bar.bottom - bar.top;

    POINT corner = {line.left, line.top};
    MONITORINFO monitor = {sizeof(monitor)};
    GetMonitorInfoW(MonitorFromPoint(corner, MONITOR_DEFAULTTONEAREST), &monitor);
    RECT area = monitor.rcWork;

    //the first word starts where the typed word starts
    int x = (int)line.left - scaled(kPadding) - scaled(kItemPadding);
    int margin = scaled(kScreenMargin);
    x = (std::max)((int)area.left + margin, (std::min)(x, (int)area.right - width - margin));
    int y = (int)line.bottom + scaled(kDistanceFromText);
    if (y + height > (int)area.bottom - margin) //no room below: above the line
        y = (std::max)((int)area.top + margin, (int)line.top - height - scaled(kDistanceFromText));

    bool wasVisible = IsWindowVisible(g_window) != 0;
    SetWindowPos(g_window, HWND_TOPMOST, x, y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    if (!wasVisible) {
        g_faded = false;
        g_overSince = 0;
        setAlpha(255);
        SetTimer(g_window, kTimerPointer, 100, NULL);
    }
    updateFadeForPointer();
}

void SuggestionBar::hide() {
    if (!g_window)
        return;
    KillTimer(g_window, kTimerPointer);
    g_faded = false;
    g_overSince = 0;
    ShowWindow(g_window, SW_HIDE);
}

bool SuggestionBar::isVisible() {
    return g_window && IsWindowVisible(g_window);
}
