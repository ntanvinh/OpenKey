//
//  FeatureTheme.h
//  VOpenKey AI, Windows
//
//  The colours, fonts and sizes of the windows of the VOpenKey AI features (suggestion bar, snippets, case bar, AI). One
//  place, so that they look alike and follow "light" or "dark" of Windows. Where the system has a colour for a thing
//  (the chosen item, its text) that colour is used, so contrast and high contrast themes are right without more work.
//
#pragma once
#include "stdafx.h"

namespace FeatureTheme {

struct Colors {
    COLORREF background;
    COLORREF border;
    COLORREF text;
    COLORREF secondaryText;   //hints, previews
    COLORREF chosen;          //background of the chosen item
    COLORREF chosenText;
    COLORREF field;           //background of a text box
};

inline bool usesLightTheme() {
    DWORD value = 1, size = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                     L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL, &value, &size) != ERROR_SUCCESS)
        return true;
    return value != 0;
}

inline Colors colors() {
    Colors c;
    bool light = usesLightTheme();
    c.background = light ? RGB(249, 249, 249) : RGB(44, 44, 44);
    c.border = light ? RGB(204, 204, 204) : RGB(78, 78, 78);
    c.text = light ? RGB(27, 27, 27) : RGB(255, 255, 255);
    c.secondaryText = light ? RGB(96, 96, 96) : RGB(176, 176, 176);
    c.chosen = GetSysColor(COLOR_HIGHLIGHT);
    c.chosenText = GetSysColor(COLOR_HIGHLIGHTTEXT);
    c.field = light ? RGB(255, 255, 255) : RGB(32, 32, 32);
    return c;
}

/// The dpi of the main screen. The program declares itself DPI aware (DeclareDPIAware.manifest).
inline int dpi() {
    HDC screen = GetDC(NULL);
    int value = GetDeviceCaps(screen, LOGPIXELSX);
    ReleaseDC(NULL, screen);
    return value > 0 ? value : 96;
}

inline int scale(int pixelsAt96, int currentDpi) {
    return MulDiv(pixelsAt96, currentDpi, 96);
}

/// Segoe UI of a size in points. The caller deletes it.
inline HFONT font(int points, int currentDpi, bool bold = false) {
    return CreateFontW(-MulDiv(points, currentDpi, 72), 0, 0, 0, bold ? FW_SEMIBOLD : FW_NORMAL, FALSE, FALSE, FALSE,
                       DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                       DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
}

} // namespace FeatureTheme
