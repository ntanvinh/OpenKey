//
//  FeatureActions.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "FeatureActions.h"
#include "CaseBar.h"
#include "SnippetEditor.h"
#include "SnippetPalette.h"
#include "SnippetService.h"
#include "SuggestionController.h"
#include "FeaturesDialog.h"
#include "AIAssistant.h"
#include "AISettings.h"
#include "AISettingsDialog.h"
#include "DonationDialog.h"

extern int convertToolHotKey;

int vRestoreHotKey = 0x352; //Ctrl+Alt+R
int vAIHotKey = 0x341;      //Ctrl+Alt+A
int vAIEnabled = 1;

namespace {

bool (*g_restoreHandler)() = NULL;

const wchar_t kActionWindowClass[] = L"VOpenKeyAIActions";
const UINT kMessageAction = WM_APP + 43;        //posted by the keyboard hook: do an Action in the message loop
const UINT_PTR kTimerBase = 1000;               //timers from here on are postDelayed
HWND g_actionWindow = NULL;

LRESULT CALLBACK actionWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == kMessageAction) {
        FeatureActions::run((FeatureActions::Action)wParam);
        return 0;
    }
    if (message == WM_TIMER && wParam >= kTimerBase) {
        KillTimer(window, wParam);
        FeatureActions::run((FeatureActions::Action)(wParam - kTimerBase));
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

std::vector<FeatureActions::HotKey> makeHotKeys() {
    std::vector<FeatureActions::HotKey> keys;
    FeatureActions::HotKey snippets = {&vSnippetHotKey, &vSnippetsEnabled, FeatureActions::OpenSnippets, L"mở snippet"};
    FeatureActions::HotKey caseBar = {&vCaseBarHotKey, NULL, FeatureActions::ToggleCaseBar, L"đổi chữ hoa thường"};
    FeatureActions::HotKey restore = {&vRestoreHotKey, NULL, FeatureActions::RestoreWord, L"khôi phục từ đang gõ"};
    FeatureActions::HotKey ai = {&vAIHotKey, &vAIEnabled, FeatureActions::OpenAIAssistant, L"mở trợ lý AI"};
    keys.push_back(snippets);
    keys.push_back(caseBar);
    keys.push_back(restore);
    keys.push_back(ai);
    return keys;
}

} // namespace

namespace FeatureActions {

const std::vector<HotKey>& hotKeys() {
    static const std::vector<HotKey> keys = makeHotKeys();
    return keys;
}

bool start(HINSTANCE instance) {
    if (g_actionWindow)
        return true;
    WNDCLASSEXW wc = {sizeof(wc)};
    wc.lpfnWndProc = actionWindowProc;
    wc.hInstance = instance;
    wc.lpszClassName = kActionWindowClass;
    if (!RegisterClassExW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;
    //a window that only receives messages: not on the screen, not in the task bar, not found by programs that list windows
    g_actionWindow = CreateWindowExW(0, kActionWindowClass, L"VOpenKey AI", 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, instance, NULL);
    return g_actionWindow != NULL;
}

void stop() {
    if (g_actionWindow) {
        DestroyWindow(g_actionWindow);
        g_actionWindow = NULL;
    }
}

bool post(Action action) {
    return g_actionWindow && PostMessageW(g_actionWindow, kMessageAction, (WPARAM)action, 0);
}

bool postDelayed(Action action, unsigned milliseconds) {
    return g_actionWindow && SetTimer(g_actionWindow, kTimerBase + (UINT_PTR)action, milliseconds, NULL) != 0;
}

void run(Action action) {
    switch (action) {
    case OpenSnippets: SnippetPalette::toggle(); break;
    case OpenSnippetEditor: SnippetEditor::show(); break;
    case ToggleCaseBar: CaseBar::toggle(); break;
    case OpenFeatureSettings: FeaturesDialog::show(); break;
    case RestoreWord: restoreWord(); break;
    case OpenAIAssistant: AIAssistant::toggle(); break;
    case OpenAISettings: AISettingsDialog::show(); break;
    case OpenDonation: DonationDialog::show(); break;
    case None: break;
    }
}

void setRestoreHandler(bool (*handler)()) {
    g_restoreHandler = handler;
}

bool restoreWord() {
    return g_restoreHandler ? g_restoreHandler() : false;
}

void loadSettings() {
    APP_GET_DATA(vSnippetsEnabled, 1);
    APP_GET_DATA(vSnippetHotKey, 0x353);
    APP_GET_DATA(vCaseBarHotKey, 0x343);
    APP_GET_DATA(vRestoreHotKey, 0x352);
    APP_GET_DATA(vAIEnabled, 1);
    APP_GET_DATA(vAIHotKey, 0x341);
    APP_GET_DATA(vDonationAcknowledged, 0);
    AISettings::load();
    //a shortcut saved as 0 is "none" for the engine of macOS: here too
    int* all[] = {&vSnippetHotKey, &vCaseBarHotKey, &vRestoreHotKey, &vAIHotKey};
    for (size_t i = 0; i < sizeof(all) / sizeof(all[0]); i++) {
        if (*all[i] == 0)
            *all[i] = (int)VOK_SHORTCUT_NONE;
    }
}

void saveHotKey(int* variable, const wchar_t* registryName, int value) {
    *variable = value;
    OpenKeyHelper::setRegInt(registryName, value);
}

std::wstring describeShortcut(int shortcut) {
    if ((shortcut & (~0x8000)) == (int)VOK_SHORTCUT_NONE || (shortcut & 0xFF) == 0xFE) {
        //only modifiers are a shortcut too (for the language switch), but the features here need a key
        bool anyModifier = (shortcut & 0xF00) != 0;
        if (!anyModifier)
            return L"Chưa đặt";
    }
    std::wstring text;
    if (shortcut & 0x100) text += L"Ctrl + ";
    if (shortcut & 0x200) text += L"Alt + ";
    if (shortcut & 0x400) text += L"Win + ";
    if (shortcut & 0x800) text += L"Shift + ";
    int key = shortcut & 0xFF;
    if (key == 0xFE) {
        if (text.size() >= 3)
            text.erase(text.size() - 3);
        return text;
    }
    if (key == VK_SPACE) text += L"Space";
    else if (key == VK_TAB) text += L"Tab";
    else if (key == VK_RETURN) text += L"Enter";
    else if (key >= VK_F1 && key <= VK_F24) text += L"F" + std::to_wstring(key - VK_F1 + 1);
    else if ((key >= '0' && key <= '9') || (key >= 'A' && key <= 'Z')) text += (wchar_t)key;
    else {
        wchar_t name[64] = {0};
        UINT scan = MapVirtualKeyW((UINT)key, MAPVK_VK_TO_VSC);
        if (GetKeyNameTextW((LONG)(scan << 16), name, 64) > 0)
            text += name;
        else
            text += L"#" + std::to_wstring(key);
    }
    return text;
}

static bool sameShortcut(int a, int b) {
    if ((a & 0xFF) == 0xFE && (b & 0xFF) == 0xFE)
        return (a & 0xF00) == (b & 0xF00);
    return (a & 0xFFF) == (b & 0xFFF);
}

std::wstring conflictOf(int shortcut, const int* ownVariable) {
    if ((shortcut & (~0x8000)) == (int)VOK_SHORTCUT_NONE)
        return L"";
    if (ownVariable != &vSwitchKeyStatus && sameShortcut(shortcut, vSwitchKeyStatus))
        return L"chuyển Anh - Việt";
    if (ownVariable != &convertToolHotKey && sameShortcut(shortcut, convertToolHotKey))
        return L"chuyển mã nhanh";
    const std::vector<HotKey>& keys = hotKeys();
    for (size_t i = 0; i < keys.size(); i++) {
        if (keys[i].shortcut == ownVariable)
            continue;
        if (keys[i].enabled && !*keys[i].enabled)
            continue;
        if (sameShortcut(shortcut, *keys[i].shortcut))
            return keys[i].name;
    }
    return L"";
}

} // namespace FeatureActions
