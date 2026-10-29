//
//  DonationDialog.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "DonationDialog.h"
#include "FeatureIds.h"
#include "FeatureTheme.h"
#include "FeatureWindows.h"
#include "../../../engine/DonationInfo.h"
#include <algorithm>
#include <cstring>
#include <cwctype>

int vDonationAcknowledged = 0;

namespace {

const wchar_t kClassName[] = L"VOpenKeyAIDonation";

enum {
    kIdHeart = 601,
    kIdHeading,
    kIdIntro,
    kIdTabVietnam,
    kIdTabInternational,
    kIdQr,
    kIdQrError,
    kIdCaption,
    kIdRowLabel,                 //four of each, in this order: label, value, copy
    kIdRowValue = kIdRowLabel + 4,
    kIdRowCopy = kIdRowValue + 4,
    kIdPayPal = kIdRowCopy + 4,
    kIdHint,
    kIdNotice,
    kIdLine,
    kIdTrust,
    kIdClose,
    kIdConfirm,
    kIdThanksHeading,
    kIdThanksBody,
    kIdUndo,
    kIdDone
};

enum Page { Vietnam, International, Thanks };

const int kRows = 4;
const int kWidth = 600;          //of the client area, at 96 dpi
const int kPad = 24;

HWND g_window = NULL;
HWND g_heart, g_heading, g_intro, g_tabVietnam, g_tabInternational, g_qr, g_qrError, g_caption;
HWND g_label[kRows], g_value[kRows], g_copy[kRows];
HWND g_payPal, g_hint, g_notice, g_line, g_trust, g_close, g_confirm;
HWND g_thanksHeading, g_thanksBody, g_undo, g_done;
std::vector<HWND> g_all;
HFONT g_font = NULL, g_boldFont = NULL, g_titleFont = NULL, g_heartFont = NULL;
HBRUSH g_backgroundBrush = NULL;
HBITMAP g_qrBitmap = NULL;
int g_qrModules = 0;             //width of the picture in pixels: one per module and the margin
int g_dpi = 96;

Page g_page = Vietnam;
bool g_noticeIsError = false;
std::wstring g_copyNames[kRows], g_copyValues[kRows];

int px(int at96) {
    return FeatureTheme::scale(at96, g_dpi);
}

std::wstring ascii(const char* text) {
    return std::wstring(text, text + strlen(text));
}

Page defaultPage() {
    wchar_t name[LOCALE_NAME_MAX_LENGTH] = {0};
    if (GetUserDefaultLocaleName(name, LOCALE_NAME_MAX_LENGTH) > 0 && (name[0] == L'v' || name[0] == L'V') && (name[1] == L'i' || name[1] == L'I'))
        return Vietnam;
    return International;
}

HWND make(const wchar_t* cls, const wchar_t* text, DWORD style, int id, HFONT font, DWORD exStyle = 0) {
    HWND control = CreateWindowExW(exStyle, cls, text, WS_CHILD | style, 0, 0, 10, 10, g_window, (HMENU)(INT_PTR)id,
                                   GetModuleHandleW(NULL), NULL);
    SendMessageW(control, WM_SETFONT, (WPARAM)font, TRUE);
    g_all.push_back(control);
    return control;
}

//the height that `text` needs at `width` (in pixels) in `font`
int textHeight(const std::wstring& text, HFONT font, int width) {
    HDC dc = GetDC(g_window);
    HGDIOBJ old = SelectObject(dc, font);
    RECT area = {0, 0, width, 0};
    DrawTextW(dc, text.c_str(), -1, &area, DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX);
    SelectObject(dc, old);
    ReleaseDC(g_window, dc);
    return area.bottom;
}

//shows a control at a place; returns the bottom of it
int place(HWND control, int x, int y, int width, int height) {
    MoveWindow(control, x, y, width, height, TRUE);
    ShowWindow(control, SW_SHOWNA);
    return y + height;
}

//a text that wraps: given the height it needs
int placeText(HWND control, int x, int y, int width, HFONT font) {
    int length = GetWindowTextLengthW(control);
    std::wstring text((size_t)length + 1, L'\0');
    GetWindowTextW(control, &text[0], length + 1);
    text.resize((size_t)length);
    return place(control, x, y, width, textHeight(text, font, width) + px(2));
}

void setNotice(const std::wstring& text, bool error) {
    g_noticeIsError = error;
    SetWindowTextW(g_notice, text.c_str());
    InvalidateRect(g_notice, NULL, TRUE);
    //a screen reader does not read a label that changes by itself
    if (!text.empty())
        NotifyWinEvent(EVENT_OBJECT_NAMECHANGE, g_notice, OBJID_CLIENT, CHILDID_SELF);
}

void setRow(int index, const std::wstring& name, const std::wstring& value, bool copyable) {
    SetWindowTextW(g_label[index], name.c_str());
    SetWindowTextW(g_value[index], value.c_str());
    g_copyNames[index] = copyable ? name : std::wstring();
    g_copyValues[index] = copyable ? value : std::wstring();
}

//One row: the name over the value, "Sao chép" at the right when the value is something to copy. Returns the bottom.
int placeRow(int index, int x, int y, int width) {
    int buttonWidth = px(92);
    bool copyable = !g_copyValues[index].empty();
    int valueWidth = copyable ? width - buttonWidth - px(8) : width;
    int labelHeight = px(18), valueHeight = px(24);
    place(g_label[index], x, y, width, labelHeight);
    place(g_value[index], x, y + labelHeight, valueWidth, valueHeight);
    if (copyable)
        place(g_copy[index], x + width - buttonWidth, y + labelHeight - px(2), buttonWidth, px(28));
    return y + labelHeight + valueHeight + px(10);
}

void relayout() {
    for (size_t i = 0; i < g_all.size(); i++)
        ShowWindow(g_all[i], SW_HIDE);
    int width = px(kWidth), pad = px(kPad);
    int contentWidth = width - 2 * pad;
    int y = pad;

    if (g_page == Thanks) {
        SetWindowTextW(g_window, L"Cảm ơn bạn - VOpenKey AI");
        y = place(g_heart, pad, y, contentWidth, px(52)) + px(4);
        y = place(g_thanksHeading, pad, y, contentWidth, px(36)) + px(8);
        y = placeText(g_thanksBody, pad, y, contentWidth, g_font) + px(24);
        place(g_undo, pad, y, px(170), px(30));
        place(g_done, width - pad - px(100), y, px(100), px(30));
        y += px(30) + px(20);
        SendMessageW(g_done, BM_SETSTYLE, BS_DEFPUSHBUTTON, TRUE);
        SendMessageW(g_confirm, BM_SETSTYLE, BS_PUSHBUTTON, TRUE);
    } else {
        SetWindowTextW(g_window, L"Ủng hộ VOpenKey AI");
        place(g_heart, pad, y, px(36), px(36));
        place(g_heading, pad + px(40), y + px(2), contentWidth - px(40), px(32));
        y += px(40);
        y = placeText(g_intro, pad, y, contentWidth, g_font) + px(12);
        place(g_tabVietnam, pad, y, px(130), px(30));
        y = place(g_tabInternational, pad + px(130), y, px(130), px(30)) + px(16);
        //two buttons of which one is down (the check box that looks like a push button): the state is set here, a click only asks for the page
        SendMessageW(g_tabVietnam, BM_SETCHECK, g_page == Vietnam ? BST_CHECKED : BST_UNCHECKED, 0);
        SendMessageW(g_tabInternational, BM_SETCHECK, g_page == International ? BST_CHECKED : BST_UNCHECKED, 0);

        if (g_page == Vietnam) {
            setRow(0, L"Ngân hàng", ascii(VOK_DONATION_BANK_NAME), false);
            setRow(1, L"Số tài khoản", ascii(VOK_DONATION_ACCOUNT_NO), true);
            setRow(2, L"Người nhận", ascii(VOK_DONATION_ACCOUNT_NAME), false);
            setRow(3, L"Nội dung chuyển khoản", ascii(VOK_DONATION_NOTE), true);
            //the picture and what it says under it at the left, the account at the right: the window stays low enough for a small screen
            int unit = g_qrBitmap && g_qrModules > 0 ? (std::max)(1, px(190) / g_qrModules) : 0;
            int side = unit * g_qrModules;
            int leftWidth = g_qrBitmap ? side : px(200);
            int leftBottom;
            if (g_qrBitmap) {
                int top = place(g_qr, pad, y, side, side);
                leftBottom = placeText(g_caption, pad, top + px(6), leftWidth, g_font);
            } else {
                leftBottom = placeText(g_qrError, pad, y, leftWidth, g_font);
            }
            int rightX = pad + leftWidth + px(28);
            int rightWidth = width - pad - rightX;
            int rightY = y;
            for (int i = 0; i < kRows; i++)
                rightY = placeRow(i, rightX, rightY, rightWidth);
            y = (std::max)(leftBottom, rightY - px(10)) + px(8);
        } else {
            setRow(0, L"Người nhận (PayPal)", ascii(VOK_DONATION_PAYPAL_NAME), false);
            setRow(1, L"Liên kết thanh toán", ascii(VOK_DONATION_PAYPAL_URL), true);
            y = placeRow(0, pad, y, contentWidth);
            y = placeRow(1, pad, y, contentWidth);
            y = place(g_payPal, pad, y + px(2), px(130), px(30)) + px(8);
            y = placeText(g_hint, pad, y, contentWidth, g_font) + px(8);
        }
        y = place(g_notice, pad, y, contentWidth, px(20)) + px(6);
        y = place(g_line, pad, y, contentWidth, px(2)) + px(10);
        y = placeText(g_trust, pad, y, contentWidth, g_font) + px(14);
        place(g_close, width - pad - px(100) - px(8) - px(150), y, px(100), px(30));
        place(g_confirm, width - pad - px(150), y, px(150), px(30));
        y += px(30) + px(20);
        SendMessageW(g_confirm, BM_SETSTYLE, BS_DEFPUSHBUTTON, TRUE);
        SendMessageW(g_done, BM_SETSTYLE, BS_PUSHBUTTON, TRUE);
    }

    //the client area is as high as the content; the window is that and its frame, and stays where its top is
    RECT frame = {0, 0, width, y};
    AdjustWindowRect(&frame, WS_CAPTION | WS_SYSMENU, FALSE);
    RECT now;
    GetWindowRect(g_window, &now);
    SetWindowPos(g_window, NULL, now.left, now.top, frame.right - frame.left, frame.bottom - frame.top, SWP_NOZORDER | SWP_NOACTIVATE);
    InvalidateRect(g_window, NULL, TRUE);
}

void copyText(const std::wstring& name, const std::wstring& value) {
    bool ok = false;
    if (OpenClipboard(g_window)) {
        EmptyClipboard();
        size_t bytes = (value.size() + 1) * sizeof(wchar_t);
        HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
        if (memory) {
            void* destination = GlobalLock(memory);
            if (destination) {
                memcpy(destination, value.c_str(), bytes);
                GlobalUnlock(memory);
                ok = SetClipboardData(CF_UNICODETEXT, memory) != NULL;
            }
            if (!ok)
                GlobalFree(memory);
        }
        CloseClipboard();
    }
    std::wstring lower = name;
    for (size_t i = 0; i < lower.size(); i++)
        lower[i] = (wchar_t)towlower(lower[i]);
    if (ok)
        setNotice(L"Đã sao chép: " + lower + L".", false);
    else
        setNotice(L"Không sao chép được. Hãy chọn và sao chép thông tin ở trên.", true);
}

void openPayPal() {
    HINSTANCE result = ShellExecuteW(g_window, L"open", ascii(VOK_DONATION_PAYPAL_URL).c_str(), NULL, NULL, SW_SHOWNORMAL);
    if ((INT_PTR)result <= 32)
        setNotice(L"Không mở được PayPal. Hãy thử lại hoặc sao chép liên kết thanh toán.", true);
}

void choosePage(Page page) {
    if (g_page == Thanks || g_page == page)
        return;
    g_page = page;
    setNotice(L"", false);
    relayout();
}

//The picture of the QR code, one pixel per module, drawn at a whole number of pixels per module so that the edges stay sharp
void drawQr(const DRAWITEMSTRUCT* item) {
    RECT area = item->rcItem;
    FillRect(item->hDC, &area, (HBRUSH)GetStockObject(WHITE_BRUSH));
    if (!g_qrBitmap)
        return;
    HDC memory = CreateCompatibleDC(item->hDC);
    HGDIOBJ old = SelectObject(memory, g_qrBitmap);
    SetStretchBltMode(item->hDC, COLORONCOLOR);
    StretchBlt(item->hDC, 0, 0, area.right - area.left, area.bottom - area.top, memory, 0, 0, g_qrModules, g_qrModules, SRCCOPY);
    SelectObject(memory, old);
    DeleteDC(memory);
}

bool isQuiet(HWND control) {
    if (control == g_notice)
        return !g_noticeIsError;
    if (control == g_intro || control == g_caption || control == g_hint || control == g_trust || control == g_thanksBody)
        return true;
    for (int i = 0; i < kRows; i++)
        if (control == g_label[i])
            return true;
    return false;
}

LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_ERASEBKGND: {
        RECT client;
        GetClientRect(window, &client);
        FillRect((HDC)wParam, &client, g_backgroundBrush);
        return 1;
    }
    case WM_DRAWITEM:
        if (wParam == kIdQr) {
            drawQr((const DRAWITEMSTRUCT*)lParam);
            return TRUE;
        }
        break;
    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLORBTN: {            //a read-only text box asks for the colour of a label
        FeatureTheme::Colors theme = FeatureTheme::colors();
        HWND control = (HWND)lParam;
        COLORREF color = theme.text;
        if (control == g_heart)
            color = RGB(232, 52, 94);
        else if (control == g_notice && g_noticeIsError)
            color = RGB(200, 40, 40);
        else if (control == g_qrError)
            color = RGB(200, 40, 40);
        else if (isQuiet(control))
            color = theme.secondaryText;
        SetTextColor((HDC)wParam, color);
        SetBkColor((HDC)wParam, theme.background);
        return (LRESULT)g_backgroundBrush;
    }
    case WM_COMMAND: {
        int id = LOWORD(wParam);
        if (id >= kIdRowCopy && id < kIdRowCopy + kRows && HIWORD(wParam) == BN_CLICKED) {
            copyText(g_copyNames[id - kIdRowCopy], g_copyValues[id - kIdRowCopy]);
        } else if (id == kIdTabVietnam && HIWORD(wParam) == BN_CLICKED) {
            choosePage(Vietnam);
        } else if (id == kIdTabInternational && HIWORD(wParam) == BN_CLICKED) {
            choosePage(International);
        } else if (id == kIdPayPal) {
            openPayPal();
        } else if (id == kIdConfirm) {
            DonationDialog::setAcknowledged(true);
            g_page = Thanks;
            relayout();
            SetFocus(g_done);
        } else if (id == kIdUndo) {
            DonationDialog::setAcknowledged(false);
            g_page = defaultPage();
            setNotice(L"", false);
            relayout();
            SetFocus(g_confirm);
        } else if (id == kIdClose || id == kIdDone || id == IDCANCEL) {   //Esc is IDCANCEL
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
        g_all.clear();
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
    if (g_titleFont) DeleteObject(g_titleFont);
    if (g_heartFont) DeleteObject(g_heartFont);
    if (g_backgroundBrush) DeleteObject(g_backgroundBrush);
    g_font = FeatureTheme::font(10, g_dpi);
    g_boldFont = FeatureTheme::font(10, g_dpi, true);
    g_titleFont = FeatureTheme::font(16, g_dpi, true);
    g_heartFont = FeatureTheme::font(24, g_dpi, false);
    g_backgroundBrush = CreateSolidBrush(FeatureTheme::colors().background);

    if (g_qrBitmap) {
        DeleteObject(g_qrBitmap);
        g_qrBitmap = NULL;
    }
    g_qrModules = 0;
    g_qrBitmap = (HBITMAP)LoadImageW(instance, MAKEINTRESOURCEW(IDB_DONATION_QR), IMAGE_BITMAP, 0, 0, LR_CREATEDIBSECTION);
    if (g_qrBitmap) {
        BITMAP info = {0};
        GetObject(g_qrBitmap, sizeof(info), &info);
        if (info.bmWidth == info.bmHeight && info.bmWidth > 0)
            g_qrModules = info.bmWidth;
        else {
            DeleteObject(g_qrBitmap);
            g_qrBitmap = NULL;
        }
    }

    g_window = CreateWindowExW(0, kClassName, L"Ủng hộ VOpenKey AI", WS_CAPTION | WS_SYSMENU | WS_CLIPCHILDREN,
                               CW_USEDEFAULT, CW_USEDEFAULT, px(kWidth), px(520), NULL, NULL, instance, NULL);
    if (!g_window)
        return false;
    FeatureWindows::registerDialog(g_window);
    g_all.clear();
    //made in the order of the Tab key
    g_heart = make(L"STATIC", L"\x2665", SS_CENTER | SS_NOPREFIX, kIdHeart, g_heartFont);
    g_heading = make(L"STATIC", L"Một chút ủng hộ, thêm nhiều động lực.", SS_NOPREFIX, kIdHeading, g_titleFont);
    g_intro = make(L"STATIC", L"Nếu VOpenKey AI giúp bạn gõ và viết thuận tiện hơn, bạn có thể góp sức để app tiếp tục phát triển.", SS_NOPREFIX,
                   kIdIntro, g_font);
    g_tabVietnam = make(L"BUTTON", L"Việt Nam", WS_TABSTOP | BS_CHECKBOX | BS_PUSHLIKE, kIdTabVietnam, g_font);
    g_tabInternational = make(L"BUTTON", L"Quốc tế", WS_TABSTOP | BS_CHECKBOX | BS_PUSHLIKE, kIdTabInternational, g_font);
    g_qr = make(L"STATIC", L"Mã VietQR chuyển khoản ủng hộ VOpenKey AI: VPBank 0988181872, người nhận NGUYEN TAN VINH", SS_OWNERDRAW, kIdQr, g_font);
    g_qrError = make(L"STATIC", L"Không tạo được mã QR. Bạn vẫn có thể chuyển khoản theo thông tin bên cạnh.", SS_NOPREFIX, kIdQrError, g_font);
    g_caption = make(L"STATIC", L"Quét bằng app ngân hàng và nhập số tiền bạn muốn ủng hộ.", SS_NOPREFIX, kIdCaption, g_font);
    for (int i = 0; i < kRows; i++) {
        g_label[i] = make(L"STATIC", L"", SS_NOPREFIX, kIdRowLabel + i, g_font);
        g_value[i] = make(L"EDIT", L"", ES_READONLY | ES_AUTOHSCROLL | WS_TABSTOP, kIdRowValue + i, g_boldFont);
        g_copy[i] = make(L"BUTTON", L"Sao chép", WS_TABSTOP | BS_PUSHBUTTON, kIdRowCopy + i, g_font);
    }
    g_payPal = make(L"BUTTON", L"Mở PayPal", WS_TABSTOP | BS_PUSHBUTTON, kIdPayPal, g_font);
    g_hint = make(L"STATIC", L"Chọn số tiền tùy ý trên PayPal. Liên kết mở trong trình duyệt và cần có internet.", SS_NOPREFIX, kIdHint, g_font);
    g_notice = make(L"STATIC", L"", SS_NOPREFIX, kIdNotice, g_font);
    g_line = make(L"STATIC", L"", SS_ETCHEDHORZ, kIdLine, g_font);
    g_trust = make(L"STATIC", L"Sau khi ủng hộ, hãy xác nhận để ẩn mục Ủng hộ khỏi menu. App tin vào xác nhận của bạn và không đối soát giao dịch.",
                   SS_NOPREFIX, kIdTrust, g_font);
    g_close = make(L"BUTTON", L"Đóng", WS_TABSTOP | BS_PUSHBUTTON, kIdClose, g_font);
    g_confirm = make(L"BUTTON", L"Tôi đã ủng hộ", WS_TABSTOP | BS_DEFPUSHBUTTON, kIdConfirm, g_font);
    g_thanksHeading = make(L"STATIC", L"Cảm ơn bạn đã ủng hộ!", SS_NOPREFIX, kIdThanksHeading, g_titleFont);
    g_thanksBody = make(L"STATIC", L"Sự ủng hộ của bạn giúp VOpenKey AI tiếp tục phát triển. Mục Ủng hộ đã được ẩn khỏi menu của biểu tượng khay; "
                        L"bạn vẫn mở lại được ở \"Gợi ý, snippet và công cụ...\".", SS_NOPREFIX, kIdThanksBody, g_font);
    g_undo = make(L"BUTTON", L"Bấm nhầm? Hoàn tác", WS_TABSTOP | BS_PUSHBUTTON, kIdUndo, g_font);
    g_done = make(L"BUTTON", L"Xong", WS_TABSTOP | BS_PUSHBUTTON, kIdDone, g_font);
    return true;
}

//In the middle of the work area of the screen where the pointer is
void center() {
    POINT cursor;
    GetCursorPos(&cursor);
    MONITORINFO info = {sizeof(info)};
    GetMonitorInfoW(MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST), &info);
    RECT rect;
    GetWindowRect(g_window, &rect);
    int width = rect.right - rect.left, height = rect.bottom - rect.top;
    int x = info.rcWork.left + ((info.rcWork.right - info.rcWork.left) - width) / 2;
    int y = info.rcWork.top + ((info.rcWork.bottom - info.rcWork.top) - height) / 3;
    SetWindowPos(g_window, NULL, x, (std::max)((int)info.rcWork.top, y), 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

} // namespace

namespace DonationDialog {

bool isVisible() {
    return g_window && IsWindowVisible(g_window);
}

bool acknowledged() {
    return vDonationAcknowledged != 0;
}

void setAcknowledged(bool value) {
    if ((vDonationAcknowledged != 0) == value)
        return;
    APP_SET_DATA(vDonationAcknowledged, value ? 1 : 0);
}

void show() {
    if (!create())
        return;
    if (!IsWindowVisible(g_window)) {
        //opened again as the situation is now: the thanks when they already donated, the form when not
        g_page = acknowledged() ? Thanks : defaultPage();
        setNotice(L"", false);
        relayout();
        center();
    }
    ShowWindow(g_window, SW_SHOWNORMAL);
    SetForegroundWindow(g_window);
    SetFocus(g_page == Thanks ? g_done : g_confirm);
}

} // namespace DonationDialog
