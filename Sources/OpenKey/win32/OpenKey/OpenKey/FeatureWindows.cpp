//
//  FeatureWindows.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "FeatureWindows.h"
#include <algorithm>

namespace {
std::vector<HWND> g_dialogs;
}

namespace FeatureWindows {

void registerDialog(HWND window) {
    if (std::find(g_dialogs.begin(), g_dialogs.end(), window) == g_dialogs.end())
        g_dialogs.push_back(window);
}

void unregisterDialog(HWND window) {
    g_dialogs.erase(std::remove(g_dialogs.begin(), g_dialogs.end(), window), g_dialogs.end());
}

bool handleDialogMessage(MSG& msg) {
    for (size_t i = 0; i < g_dialogs.size(); i++) {
        if (IsWindowVisible(g_dialogs[i]) && IsDialogMessageW(g_dialogs[i], &msg))
            return true;
    }
    return false;
}

} // namespace FeatureWindows
