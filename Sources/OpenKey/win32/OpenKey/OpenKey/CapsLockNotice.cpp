//
//  CapsLockNotice.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "CapsLockNotice.h"
#include "FeatureTheme.h"
#include "../../../engine/CapsLockIcon.h"
#include <vector>

int vCapsLockToast = 1;

namespace CapsLockNotice {

namespace {

const wchar_t kClassName[] = L"VOpenKeyAICapsLockToast";

const UINT_PTR kTimerHide = 1;
const UINT_PTR kTimerFade = 2;
const UINT kStayMs = 1400;
const UINT kFadeInMs = 120;       //it has to be there as the key goes down: short
const UINT kFadeOutMs = 200;
const UINT kFrameMs = 15;

//sizes at 96 dpi
const int kHeight = 48;
const int kRadius = 14;
const int kPaddingLeading = 16;
const int kPaddingTrailing = 20;
const int kIconSize = 22;
const int kGap = 10;
const int kBottomOffset = 88;     //above the taskbar

HWND g_window = NULL;
bool g_on = false;
int g_dpi = 96;
int g_textWidth = 0;
int g_alpha = 255;
int g_fadeDirection = 0;          //1 coming in, -1 going out, 0 none
DWORD g_fadeStart = 0;
bool g_classRegistered = false;

int px(int at96) {
    return FeatureTheme::scale(at96, g_dpi);
}

//the person asked Windows for no animations (Settings, Accessibility, Visual effects)
bool animationsOn() {
    BOOL on = TRUE;
    SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &on, 0);
    return on != FALSE;
}

void setAlpha(int alpha) {
    g_alpha = alpha < 0 ? 0 : (alpha > 255 ? 255 : alpha);
    SetLayeredWindowAttributes(g_window, 0, (BYTE)g_alpha, LWA_ALPHA);
}

void startFade(int direction) {
    g_fadeDirection = direction;
    g_fadeStart = GetTickCount();
    SetTimer(g_window, kTimerFade, kFrameMs, NULL);
}

void stopFade() {
    g_fadeDirection = 0;
    KillTimer(g_window, kTimerFade);
}

void hideNow() {
    if (g_window == NULL)
        return;
    KillTimer(g_window, kTimerHide);
    stopFade();
    ShowWindow(g_window, SW_HIDE);
}

//the arrow of the Caps Lock key and the bar under it, in a box of 24 units
void arrowPoints(POINT* points, int left, int top, int size) {
    static const double shape[7][2] = {{12, 2}, {22, 12}, {16, 12}, {16, 16.5}, {8, 16.5}, {8, 12}, {2, 12}};
    for (int i = 0; i < 7; i++) {
        points[i].x = left + (int)(shape[i][0] * size / 24.0 + 0.5);
        points[i].y = top + (int)(shape[i][1] * size / 24.0 + 0.5);
    }
}

void paint(HWND window, HDC target, const RECT& client) {
    FeatureTheme::Colors colors = FeatureTheme::colors();
    int width = client.right - client.left, height = client.bottom - client.top;

    HDC dc = CreateCompatibleDC(target);
    HBITMAP bitmap = CreateCompatibleBitmap(target, width, height);
    HGDIOBJ oldBitmap = SelectObject(dc, bitmap);

    HBRUSH background = CreateSolidBrush(colors.background);
    FillRect(dc, &client, background);
    DeleteObject(background);
    //a hairline at the edge, like the other windows of the features
    HPEN borderPen = CreatePen(PS_SOLID, 1, colors.border);
    HGDIOBJ oldPen = SelectObject(dc, borderPen);
    HGDIOBJ oldBrush = SelectObject(dc, GetStockObject(NULL_BRUSH));
    RoundRect(dc, 0, 0, width, height, px(kRadius) * 2, px(kRadius) * 2);
    SelectObject(dc, oldBrush);
    SelectObject(dc, oldPen);
    DeleteObject(borderPen);

    //the key: red and filled while it is on (the colour of the icon in the tray), an outline in the colour of hints while off
    int icon = px(kIconSize);
    int iconLeft = px(kPaddingLeading), iconTop = (height - icon) / 2;
    POINT arrow[7];
    arrowPoints(arrow, iconLeft, iconTop, icon);
    RECT bar = {iconLeft + (int)(8 * icon / 24.0 + 0.5), iconTop + (int)(19 * icon / 24.0 + 0.5),
                iconLeft + (int)(16 * icon / 24.0 + 0.5), iconTop + (int)(22 * icon / 24.0 + 0.5)};
    if (g_on) {
        COLORREF red = FeatureTheme::usesLightTheme() ? RGB(215, 0, 21) : RGB(255, 69, 58);
        HBRUSH fill = CreateSolidBrush(red);
        HPEN none = CreatePen(PS_NULL, 0, 0);
        HGDIOBJ previousBrush = SelectObject(dc, fill);
        HGDIOBJ previousPen = SelectObject(dc, none);
        Polygon(dc, arrow, 7);
        Rectangle(dc, bar.left, bar.top, bar.right + 1, bar.bottom + 1);
        SelectObject(dc, previousBrush);
        SelectObject(dc, previousPen);
        DeleteObject(fill);
        DeleteObject(none);
    } else {
        HPEN outline = CreatePen(PS_SOLID, (std::max)(1, px(2)), colors.secondaryText);
        HGDIOBJ previousPen = SelectObject(dc, outline);
        HGDIOBJ previousBrush = SelectObject(dc, GetStockObject(NULL_BRUSH));
        Polygon(dc, arrow, 7);
        Rectangle(dc, bar.left, bar.top, bar.right + 1, bar.bottom + 1);
        SelectObject(dc, previousBrush);
        SelectObject(dc, previousPen);
        DeleteObject(outline);
    }

    HFONT font = FeatureTheme::font(11, g_dpi, true);
    HGDIOBJ oldFont = SelectObject(dc, font);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, colors.text);
    RECT text = {px(kPaddingLeading + kIconSize + kGap), 0, width, height};
    DrawTextW(dc, messageFor(g_on), -1, &text, DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOPREFIX | DT_NOCLIP);
    SelectObject(dc, oldFont);
    DeleteObject(font);

    BitBlt(target, 0, 0, width, height, dc, 0, 0, SRCCOPY);
    SelectObject(dc, oldBitmap);
    DeleteObject(bitmap);
    DeleteDC(dc);
    (void)window;
}

LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC dc = BeginPaint(window, &ps);
        RECT client;
        GetClientRect(window, &client);
        paint(window, dc, client);
        EndPaint(window, &ps);
        return 0;
    }
    case WM_ERASEBKGND:
        return 1;
    case WM_NCHITTEST:
        return HTTRANSPARENT;           //a click goes to what is under it
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    case WM_TIMER:
        if (wParam == kTimerHide) {
            KillTimer(window, kTimerHide);
            if (animationsOn())
                startFade(-1);
            else
                hideNow();
        } else if (wParam == kTimerFade) {
            UINT duration = g_fadeDirection > 0 ? kFadeInMs : kFadeOutMs;
            double progress = (double)(GetTickCount() - g_fadeStart) / duration;
            if (progress >= 1.0) {
                if (g_fadeDirection > 0) {
                    setAlpha(255);
                    stopFade();
                } else {
                    hideNow();
                }
            } else {
                double eased = 1.0 - (1.0 - progress) * (1.0 - progress) * (1.0 - progress);   //ease-out: quick at first
                setAlpha((int)((g_fadeDirection > 0 ? eased : 1.0 - eased) * 255));
            }
        }
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

bool ensureWindow() {
    if (g_window != NULL)
        return true;
    if (!g_classRegistered) {
        WNDCLASSEXW wc = {sizeof(wc)};
        wc.lpfnWndProc = windowProc;
        wc.hInstance = GetModuleHandleW(NULL);
        wc.hCursor = LoadCursor(NULL, IDC_ARROW);
        wc.lpszClassName = kClassName;
        if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
            return false;
        g_classRegistered = true;
    }
    g_window = CreateWindowExW(WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT | WS_EX_LAYERED,
                               kClassName, L"VOpenKey AI - Caps Lock", WS_POPUP, 0, 0, 10, 10, NULL, NULL, GetModuleHandleW(NULL), NULL);
    return g_window != NULL;
}

//the width of the message in the font of the toast
int measureMessage(bool on) {
    HDC dc = GetDC(g_window);
    HFONT font = FeatureTheme::font(11, g_dpi, true);
    HGDIOBJ old = SelectObject(dc, font);
    SIZE size = {0, 0};
    const wchar_t* text = messageFor(on);
    GetTextExtentPoint32W(dc, text, (int)wcslen(text), &size);
    SelectObject(dc, old);
    DeleteObject(font);
    ReleaseDC(g_window, dc);
    return size.cx;
}

} // namespace

const wchar_t* messageFor(bool on) {
    return on ? L"Caps Lock đang bật" : L"Caps Lock đã tắt";
}

bool isOn() {
    return (GetKeyState(VK_CAPITAL) & 1) != 0;
}

void showToast(bool on) {
    if (!ensureWindow())
        return;
    //still on the screen, even if it was going out: it comes back whole at once, without a new fade in
    bool alreadyThere = IsWindowVisible(g_window) && g_alpha > 0;
    g_on = on;
    g_dpi = FeatureTheme::dpi();
    g_textWidth = measureMessage(on);
    SetWindowTextW(g_window, messageFor(on));

    int width = px(kPaddingLeading) + px(kIconSize) + px(kGap) + g_textWidth + px(kPaddingTrailing);
    int height = px(kHeight);
    //the screen the pointer is on, above its taskbar
    POINT pointer = {0, 0};
    GetCursorPos(&pointer);
    MONITORINFO monitor = {sizeof(monitor)};
    GetMonitorInfoW(MonitorFromPoint(pointer, MONITOR_DEFAULTTONEAREST), &monitor);
    RECT area = monitor.rcWork;
    int x = area.left + ((area.right - area.left) - width) / 2;
    int y = area.bottom - height - px(kBottomOffset);

    bool animate = animationsOn();
    if (alreadyThere || !animate) {
        stopFade();
        setAlpha(255);
    } else {
        setAlpha(0);
    }
    SetWindowPos(g_window, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    int round = px(kRadius) * 2;
    SetWindowRgn(g_window, CreateRoundRectRgn(0, 0, width + 1, height + 1, round, round), TRUE);
    InvalidateRect(g_window, NULL, FALSE);
    if (!alreadyThere && animate)
        startFade(1);
    //it stays for the full time from the last press (a timer with the same id is restarted)
    SetTimer(g_window, kTimerHide, kStayMs, NULL);
    //Narrator does not look at a window that never has the focus: an alert says it is there
    NotifyWinEvent(EVENT_SYSTEM_ALERT, g_window, OBJID_CLIENT, CHILDID_SELF);
}

void hideToast() {
    hideNow();
}

void destroy() {
    if (g_window != NULL) {
        hideNow();
        DestroyWindow(g_window);
        g_window = NULL;
    }
}

HICON makeRedIcon(HICON base, bool vietnamese) {
    ICONINFO info = {};
    if (base == NULL || !GetIconInfo(base, &info))
        return NULL;
    HICON result = NULL;
    BITMAP bitmap = {};
    if (info.hbmColor != NULL && GetObjectW(info.hbmColor, sizeof(bitmap), &bitmap) && bitmap.bmWidth >= 4 && bitmap.bmHeight >= 4 &&
        bitmap.bmWidth <= 512 && bitmap.bmHeight <= 512) {
        int w = bitmap.bmWidth, h = bitmap.bmHeight;
        std::vector<uint32_t> color((size_t)w * h, 0), mask((size_t)w * h, 0), out((size_t)w * h, 0);
        BITMAPINFO bi = {};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = w;
        bi.bmiHeader.biHeight = -h;                //top down
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        HDC screen = GetDC(NULL);
        bool haveColor = GetDIBits(screen, info.hbmColor, 0, h, color.data(), &bi, DIB_RGB_COLORS) == h;
        bool haveMask = info.hbmMask != NULL && GetDIBits(screen, info.hbmMask, 0, h, mask.data(), &bi, DIB_RGB_COLORS) == h;
        if (haveColor) {
            //an icon of the old kind has no alpha in its colours: the shape is in the mask (a set bit is transparent)
            bool hasAlpha = false;
            for (size_t i = 0; i < color.size() && !hasAlpha; i++)
                hasAlpha = (color[i] >> 24) != 0;
            for (size_t i = 0; i < color.size(); i++) {
                uint32_t alpha = hasAlpha ? (color[i] >> 24) : ((haveMask && (mask[i] & 0xFFFFFF) != 0) ? 0 : 255);
                color[i] = (alpha << 24) | (color[i] & 0xFFFFFF);
            }
            if (vietnamese)
                vcaps::vietnamFlagIcon(w, h, out.data());
            else
                vcaps::redTileIcon(color.data(), w, h, out.data());

            BITMAPINFO bi32 = bi;
            void* bits = NULL;
            HBITMAP colorBitmap = CreateDIBSection(screen, &bi32, DIB_RGB_COLORS, &bits, NULL, 0);
            //the mask of the old kind, for a system that ignores the alpha: a set bit where nothing is drawn
            int rowBytes = ((w + 15) / 16) * 2;
            std::vector<BYTE> maskBits((size_t)rowBytes * h, 0);
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    if ((out[(size_t)y * w + x] >> 24) < 128)
                        maskBits[(size_t)y * rowBytes + x / 8] |= (BYTE)(0x80 >> (x % 8));
            HBITMAP maskBitmap = CreateBitmap(w, h, 1, 1, maskBits.data());
            if (colorBitmap != NULL && bits != NULL && maskBitmap != NULL) {
                memcpy(bits, out.data(), out.size() * sizeof(uint32_t));
                ICONINFO made = {};
                made.fIcon = TRUE;
                made.hbmColor = colorBitmap;
                made.hbmMask = maskBitmap;
                result = CreateIconIndirect(&made);
            }
            if (colorBitmap != NULL)
                DeleteObject(colorBitmap);
            if (maskBitmap != NULL)
                DeleteObject(maskBitmap);
        }
        ReleaseDC(NULL, screen);
    }
    if (info.hbmColor != NULL)
        DeleteObject(info.hbmColor);
    if (info.hbmMask != NULL)
        DeleteObject(info.hbmMask);
    return result;
}

} // namespace CapsLockNotice
