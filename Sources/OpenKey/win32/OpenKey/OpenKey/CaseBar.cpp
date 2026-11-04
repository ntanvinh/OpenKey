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
#include "../../../engine/AppExclusions.h"
#include "../../../engine/SensitiveField.h"
#include <uiautomation.h>
#include <oleauto.h>
#include <algorithm>
#include <cstdlib>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

int vCaseBarHotKey = 0x343; //Ctrl+Alt+C
int vCaseBarAuto = 1;       //the list comes up by itself when text is selected (like macOS)

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
const UINT_PTR kTimerLook = 2;
const UINT kMessageChoose = WM_APP + 51;   //posted by the keyboard hook: the work is done in the message loop, not in the hook
const UINT kMessageSelection = WM_APP + 52; //posted by the worker that read the selection of the program in front
const UINT kMouseWaitMs = 150;             //the program updates its selection a moment after the button comes up
const UINT kKeyWaitMs = 350;               //Shift+arrow repeats: wait until the selection stopped moving
const UINT kAutoLifetimeMs = 20000;        //a list nobody used goes away by itself

HWND g_window = NULL;
HWND g_target = NULL;
std::u16string g_text;                  //the whole selection
std::vector<vcase::Offer> g_offers;     //computed on the start of it
int g_chosen = 0;
bool g_message = false;                 //the window shows a message instead of rows
std::wstring g_messageText;
bool g_explicit = true;                 //the user asked (shortcut): the list takes the arrows, Enter and Esc too. The one that came up by itself takes Alt+digits only
unsigned g_generation = 0;              //every input and every new list: a look that was asked before is stale
bool g_looking = false;                 //a worker is reading a selection
bool g_lookAgain = false;               //the selection changed while it was
DWORD g_lookStarted = 0;                //when it started: a program that never answers (busy, hung) must not keep the list from ever coming up again
POINT g_downPoint = {0, 0};             //where the left button went down, when, and how many times in a row
DWORD g_downTime = 0;
int g_clicks = 0;
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

bool windowVisible() {
    return g_window && IsWindowVisible(g_window);
}

//the list that comes up by itself, further down
void startLook();
void selectionArrived(LPARAM found);

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
        if (wParam == kTimerHide) {
            CaseBar::hide();
        } else if (wParam == kTimerLook) {
            KillTimer(window, kTimerLook);
            startLook();
        }
        return 0;
    case kMessageSelection:
        selectionArrived(lParam);
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

//Our own windows (snippets, settings, the AI window) have the keyboard: their text is not for this list
bool ownWindowHasKeyboard() {
    DWORD process = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &process);
    return process == GetCurrentProcessId();
}

//Fills the rows for g_text. False when there is nothing to offer; when the user asked (`announce`) a message under `line` says why.
bool buildOffers(const RECT& line, bool announce) {
    if (g_text.size() > kMaxLength) {
        if (announce)
            showMessage(L"Đoạn chữ dài quá để đổi từ danh sách này (tối đa 100.000 ký tự).", line);
        return false;
    }
    //the rows depend on what the styles do to the start of the text: a style that changes nothing there is not offered
    std::u16string start = g_text.substr(0, kPreviewLength);
    if (start.size() == kPreviewLength && start[start.size() - 1] >= 0xD800 && start[start.size() - 1] <= 0xDBFF)
        start.resize(start.size() - 1);
    g_offers = vcase::offersForText(CaseTransformWindows::unicode(), start);
    if (g_offers.size() > 10)
        g_offers.resize(10);
    if (g_offers.empty()) {
        if (announce)
            showMessage(L"Đoạn chữ này không có gì để đổi hoa thường.", line);
        return false;
    }
    //the previews show the start of the whole selection, not of the part the rows were chosen on
    for (size_t i = 0; i < g_offers.size(); i++)
        g_offers[i].text = vcase::apply(CaseTransformWindows::unicode(), g_offers[i].style, g_text.substr(0, kPreviewChars * 4));
    return true;
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
    g_text = CaseTransformWindows::toU16(selected);
    if (!buildOffers(line, true))
        return;
    g_explicit = true;
    g_message = false;
    g_chosen = 0;
    present(line);
}

//--- the list that comes up by itself -------------------------------------------------------------------------------------

//What the worker found out about the selection of the program in front
struct Found {
    unsigned generation;
    HWND foreground;
    std::wstring text;
    RECT line;
    bool hasLine;
};

//Programs say their selection through UI Automation (the text pattern): Notepad, Word, browsers... The question can take long
//when the program is busy, so it is asked on a worker thread, never in a hook or the message loop. The clipboard is never used here:
//a program that does not say its selection simply gets no list (the shortcut still works there).
DWORD WINAPI selectionThread(LPVOID parameter) {
    Found* found = (Found*)parameter;
    HRESULT com = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    IUIAutomation* automation = NULL;
    if (SUCCEEDED(CoCreateInstance(__uuidof(CUIAutomation), NULL, CLSCTX_INPROC_SERVER, __uuidof(IUIAutomation), (void**)&automation)) &&
        automation) {
        IUIAutomationElement* element = NULL;
        if (SUCCEEDED(automation->GetFocusedElement(&element)) && element) {
            //never the text of a password field, nor of a field that is called like one
            BOOL secret = FALSE;
            if (FAILED(element->get_CurrentIsPassword(&secret)))
                secret = FALSE;
            if (!secret) {
                BSTR names[3] = {NULL, NULL, NULL};
                element->get_CurrentName(&names[0]);
                element->get_CurrentHelpText(&names[1]);
                element->get_CurrentAutomationId(&names[2]);
                for (int i = 0; i < 3; i++) {
                    if (!secret && names[i] && SysStringLen(names[i]) > 0 &&
                        vsuggest::namesASecret(wideStringToUtf8(std::wstring(names[i], SysStringLen(names[i])))))
                        secret = TRUE;
                    SysFreeString(names[i]);
                }
            }
            IUIAutomationTextPattern* pattern = NULL;
            if (!secret && SUCCEEDED(element->GetCurrentPatternAs(UIA_TextPatternId, __uuidof(IUIAutomationTextPattern), (void**)&pattern)) &&
                pattern) {
                IUIAutomationTextRangeArray* ranges = NULL;
                int count = 0;
                if (SUCCEEDED(pattern->GetSelection(&ranges)) && ranges && SUCCEEDED(ranges->get_Length(&count)) && count == 1) {
                    IUIAutomationTextRange* range = NULL;
                    if (SUCCEEDED(ranges->GetElement(0, &range)) && range) {
                        BSTR text = NULL;
                        if (SUCCEEDED(range->GetText((int)kMaxLength + 1, &text)) && text) {
                            found->text.assign(text, SysStringLen(text));
                            SysFreeString(text);
                        }
                        SAFEARRAY* rectangles = NULL;
                        //four numbers (left, top, width, height) for each line the selection covers: the list goes under the last one
                        if (!found->text.empty() && SUCCEEDED(range->GetBoundingRectangles(&rectangles)) && rectangles) {
                            LONG lower = 0, upper = -1;
                            double* data = NULL;
                            if (SUCCEEDED(SafeArrayGetLBound(rectangles, 1, &lower)) && SUCCEEDED(SafeArrayGetUBound(rectangles, 1, &upper)) &&
                                upper - lower + 1 >= 4 && SUCCEEDED(SafeArrayAccessData(rectangles, (void**)&data)) && data) {
                                LONG last = ((upper - lower + 1) / 4 - 1) * 4;
                                found->line.left = (LONG)data[last];
                                found->line.top = (LONG)data[last + 1];
                                found->line.right = (LONG)(data[last] + data[last + 2]);
                                found->line.bottom = (LONG)(data[last + 1] + data[last + 3]);
                                found->hasLine = found->line.bottom > found->line.top;
                                SafeArrayUnaccessData(rectangles);
                            }
                            SafeArrayDestroy(rectangles);
                        }
                        range->Release();
                    }
                }
                if (ranges)
                    ranges->Release();
                pattern->Release();
            }
            element->Release();
        }
        automation->Release();
    }
    if (SUCCEEDED(com))
        CoUninitialize();
    if (!g_window || !PostMessageW(g_window, kMessageSelection, 0, (LPARAM)found))
        delete found; //nobody to take it (the program is closing)
    return 0;
}

//A selection was made (a drag, a double click, Shift+arrows...) and has settled: look at what it is
void startLook() {
    if (!vCaseBarAuto || !g_window || ownWindowHasKeyboard())
        return;
    //where Tab belongs to the program (terminals) a selection is a copy in the making, not a text to change
    std::string exe = OpenKeyHelper::getFrontMostAppExecuteName();
    if (vsuggest::appexclusions::contains(SuggestionController::defaultExcludedApps(), exe))
        return;
    if (g_looking && GetTickCount() - g_lookStarted < 8000) {
        g_lookAgain = true;
        return;
    }
    Found* found = new Found();
    found->generation = g_generation;
    found->foreground = GetForegroundWindow();
    found->hasLine = false;
    found->line.left = found->line.top = found->line.right = found->line.bottom = 0;
    g_looking = true;
    g_lookStarted = GetTickCount();
    HANDLE thread = CreateThread(NULL, 0, selectionThread, found, 0, NULL);
    if (thread) {
        CloseHandle(thread);
    } else {
        g_looking = false;
        delete found;
    }
}

//Asks for a look after `milliseconds` of quiet: each new input moves it on
void scheduleLook(UINT milliseconds) {
    if (!vCaseBarAuto || !create())
        return;
    g_generation++;
    SetTimer(g_window, kTimerLook, milliseconds, NULL);
}

//The worker is back. The list is shown only when nothing happened meanwhile and the same program is in front.
void presentFound(const Found& found) {
    if (found.generation != g_generation || found.foreground != GetForegroundWindow() || ownWindowHasKeyboard())
        return;
    g_text = CaseTransformWindows::toU16(found.text);
    RECT line = found.line;
    if (!found.hasLine) { //the program does not say where: under the pointer
        POINT pointer = {0, 0};
        GetCursorPos(&pointer);
        line.left = line.right = pointer.x;
        line.top = pointer.y;
        line.bottom = pointer.y + 20;
    }
    if (!buildOffers(line, false))
        return;
    g_target = found.foreground;
    g_explicit = false;
    g_message = false;
    g_chosen = -1; //nothing is lit: no key but Alt+digits is for the list
    present(line);
    SetTimer(g_window, kTimerHide, kAutoLifetimeMs, NULL);
}

//Shift with an arrow, Home, End, Page Up/Down extends the selection; Ctrl+A selects all
bool isSelectionKey(unsigned virtualKey, bool alt, bool control, bool shift, bool win) {
    if (alt || win)
        return false;
    if (shift)
        return virtualKey == VK_LEFT || virtualKey == VK_RIGHT || virtualKey == VK_UP || virtualKey == VK_DOWN || virtualKey == VK_HOME ||
               virtualKey == VK_END || virtualKey == VK_PRIOR || virtualKey == VK_NEXT;
    return control && virtualKey == 'A';
}

bool pointerIsOnList() {
    RECT bar;
    POINT pointer;
    return windowVisible() && GetCursorPos(&pointer) && GetWindowRect(g_window, &bar) && PtInRect(&bar, pointer);
}

void selectionArrived(LPARAM parameter) {
    Found* found = (Found*)parameter;
    g_looking = false;
    bool again = g_lookAgain;
    g_lookAgain = false;
    if (found) {
        if (vCaseBarAuto && !found->text.empty())
            presentFound(*found);
        delete found;
    }
    if (again)
        scheduleLook(kMouseWaitMs);
}

} // namespace

namespace CaseBar {

void prepare() {
    if (vCaseBarAuto)
        create();
}

bool isVisible() {
    return windowVisible();
}

void hide() {
    g_generation++; //a look that was waiting is off
    if (!g_window)
        return;
    KillTimer(g_window, kTimerHide);
    KillTimer(g_window, kTimerLook);
    ShowWindow(g_window, SW_HIDE);
    g_offers.clear();
    g_text.clear();
}

void toggle() {
    if (isVisible()) {
        if (g_explicit || g_message) {
            hide();
        } else {
            //the list came up by itself: the shortcut hands it the keys (arrows, Enter, Esc)
            g_explicit = true;
            g_chosen = 0;
            KillTimer(g_window, kTimerHide);
            InvalidateRect(g_window, NULL, FALSE);
        }
        return;
    }
    TextInserter::runWhenKeysReleased(openAfterRelease);
}

bool keyDown(unsigned virtualKey, bool alt, bool control, bool shift, bool win) {
    bool selects = vCaseBarAuto && isSelectionKey(virtualKey, alt, control, shift, win);
    if (!isVisible()) {
        if (selects)
            scheduleLook(kKeyWaitMs);
        else if (vCaseBarAuto)
            g_generation++; //a look that was waiting for the selection to settle is off: the user went on
        return false;
    }
    if (g_message) { //a message goes away with any key, and the key goes on to the program
        hide();
        return false;
    }
    if (!control && !shift && !win) {
        if (!alt) {
            if (g_explicit) {
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
            }
        } else if (virtualKey >= '0' && virtualKey <= '9') {
            int row = virtualKey == '0' ? 9 : (int)(virtualKey - '1');
            if ((size_t)row < g_offers.size()) {
                PostMessageW(g_window, kMessageChoose, (WPARAM)row, 0);
                return true;
            }
        }
    }
    hide(); //any other key puts the list away and goes on to the program (a letter typed replaces the selection)
    if (selects)
        scheduleLook(kKeyWaitMs);
    return false;
}

void mouseDown(POINT point, bool leftButton) {
    if (leftButton) {
        //how many presses in a row, as Windows counts a double click
        DWORD now = GetTickCount();
        bool closeBy = std::abs(point.x - g_downPoint.x) <= GetSystemMetrics(SM_CXDOUBLECLK) / 2 &&
                    std::abs(point.y - g_downPoint.y) <= GetSystemMetrics(SM_CYDOUBLECLK) / 2;
        g_clicks = (g_clicks > 0 && closeBy && now - g_downTime <= GetDoubleClickTime()) ? g_clicks + 1 : 1;
        g_downTime = now;
        g_downPoint = point;
    }
    if (!isVisible()) {
        if (vCaseBarAuto)
            g_generation++; //a look that was waiting is off
        return;
    }
    RECT bar;
    if (GetWindowRect(g_window, &bar) && PtInRect(&bar, point))
        return; //a click on a row is for the row
    hide();
}

void mouseUp(POINT point, bool shiftHeld) {
    if (!vCaseBarAuto || pointerIsOnList())
        return;
    bool dragged = std::abs(point.x - g_downPoint.x) >= GetSystemMetrics(SM_CXDRAG) || std::abs(point.y - g_downPoint.y) >= GetSystemMetrics(SM_CYDRAG);
    //a drag, a double or triple click and Shift+click make a selection
    if (dragged || g_clicks >= 2 || shiftHeld)
        scheduleLook(kMouseWaitMs);
}

void scrolled() {
    if (isVisible())
        hide();
    else if (vCaseBarAuto)
        g_generation++;
}

} // namespace CaseBar
