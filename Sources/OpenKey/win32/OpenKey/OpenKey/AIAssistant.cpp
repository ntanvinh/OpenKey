//
//  AIAssistant.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "AIAssistant.h"
#include "AIClient.h"
#include "AISettings.h"
#include "AISettingsDialog.h"
#include "AIText.h"
#include "../../../engine/AIPresets.h"
#include "FeatureIds.h"
#include "FeatureStorage.h"
#include "FeatureTheme.h"
#include "FeatureWindows.h"
#include "TextInserter.h"
#include <ctime>

namespace {

const wchar_t kClassName[] = L"VOpenKeyAIAssistant";

enum {
    kIdProvider = 401,
    kIdModel,
    kIdSettings,
    kIdContext,
    kIdInput,
    kIdAsk,
    kIdStatus,
    kIdOutput,
    kIdInsert,
    kIdCopy,
    kIdLabelInput,
    kIdLabelOutput,
    kIdPresetCaption,
    kIdPresetFirst = 450         //one button for each ready-made conversion, in the order of engine/ai/ai-presets.json
};

enum State { Idle, Generating, Done, Failed };

const UINT_PTR kTimerSeconds = 1;
const UINT_PTR kTimerCopied = 2;

HWND g_window = NULL;
HWND g_provider, g_model, g_settings, g_context, g_input, g_ask, g_status, g_output, g_insert, g_copy, g_labelInput, g_labelOutput;
HFONT g_font = NULL, g_boldFont = NULL;
HBRUSH g_fieldBrush = NULL, g_backgroundBrush = NULL;
int g_dpi = 96;

HWND g_target = NULL;                 //the program that had the keyboard when the window opened
bool g_hadSelection = false;
State g_state = Idle;
unsigned g_request = 0;
std::wstring g_result;                //what the service wrote, line breaks as LF
std::wstring g_failure;
time_t g_started = 0;
bool g_pendingOpen = false;

//the ready-made conversions (engine/AIPresets.h): a row of buttons under the box
vpreset::Presets g_presets;
HWND g_presetCaption = NULL;
std::vector<HWND> g_presetButtons;
std::vector<int> g_presetWidths;
std::vector<std::wstring> g_presetTips;
int g_presetCaptionWidth = 0;
int g_activePreset = -1;              //the one that the next "Tạo" applies; -1 none. Cleared when the text is edited and when the window opens.
bool g_poemRequest = false;           //the request that is going on is for a poem: its rhymes and syllables are the AI's word, not checked here
bool g_hintShown = false;             //the status line asks for a text: it goes as soon as one is typed

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

//the edit boxes of Windows want CR LF, the services and the clipboard LF
std::wstring fromEdit(const std::wstring& text) {
    std::wstring result;
    for (size_t i = 0; i < text.size(); i++) {
        if (text[i] == L'\r' && i + 1 < text.size() && text[i + 1] == L'\n')
            continue;
        result += text[i];
    }
    return result;
}

std::wstring toEdit(const std::wstring& text) {
    std::wstring result;
    for (size_t i = 0; i < text.size(); i++) {
        if (text[i] == L'\n' && (i == 0 || text[i - 1] != L'\r'))
            result += L'\r';
        result += text[i];
    }
    return result;
}

void appendOutput(const std::wstring& piece) {
    std::wstring edit = toEdit(piece);
    SendMessageW(g_output, EM_SETSEL, (WPARAM)-1, (LPARAM)-1);
    SendMessageW(g_output, EM_REPLACESEL, FALSE, (LPARAM)edit.c_str());
}

const vai::Provider& chosenProvider() {
    int row = (int)SendMessageW(g_provider, CB_GETCURSEL, 0, 0);
    const std::vector<vai::Provider>& all = vai::providers();
    return row >= 0 && (size_t)row < all.size() ? all[(size_t)row] : AISettings::provider();
}

void fillProviders() {
    SendMessageW(g_provider, CB_RESETCONTENT, 0, 0);
    const std::vector<vai::Provider>& all = vai::providers();
    std::string current = AISettings::providerId();
    int select = 0;
    for (size_t i = 0; i < all.size(); i++) {
        std::wstring name = AIText::displayName(all[i]);
        if (!AISettings::isReady(all[i]))
            name += L" - chưa cài đặt";
        SendMessageW(g_provider, CB_ADDSTRING, 0, (LPARAM)name.c_str());
        if (all[i].id == current)
            select = (int)i;
    }
    SendMessageW(g_provider, CB_SETCURSEL, select, 0);
}

void showModel() {
    const vai::Provider& provider = chosenProvider();
    std::wstring model = utf8ToWideString(AISettings::modelFor(provider));
    SetWindowTextW(g_model, model.empty() ? L"" : (L"Model: " + model).c_str());
}

void setStatus(const std::wstring& text) {
    g_hintShown = false;
    SetWindowTextW(g_status, text.c_str());
}

//the window asks for a text: the line is taken back when the user types one, so that it does not stay under a box that is no longer empty
void setHint(const std::wstring& text) {
    setStatus(text);
    g_hintShown = true;
}

//a request of only blanks asks for nothing
bool hasText() {
    std::wstring text = textOf(g_input);
    for (size_t i = 0; i < text.size(); i++) {
        if (!(text[i] == L' ' || text[i] == L'\n' || text[i] == L'\t' || text[i] == L'\r'))
            return true;
    }
    return false;
}

//a button of a conversion is down while it is the one that applies, and works when there is a text to convert and no answer on its way
void updatePresetButtons() {
    bool enabled = hasText() && g_state != Generating;
    for (size_t i = 0; i < g_presetButtons.size(); i++) {
        EnableWindow(g_presetButtons[i], enabled);
        SendMessageW(g_presetButtons[i], BM_SETCHECK, (int)i == g_activePreset ? BST_CHECKED : BST_UNCHECKED, 0);
    }
}

void updateButtons() {
    bool generating = g_state == Generating;
    SetWindowTextW(g_ask, generating ? L"Dừng (Esc)" : L"Tạo (Ctrl+Enter)");
    bool haveResult = !g_result.empty();
    EnableWindow(g_insert, haveResult && !generating);
    EnableWindow(g_copy, haveResult && !generating);
    EnableWindow(g_provider, !generating);
    updatePresetButtons();
}

void showFailure(const std::wstring& message) {
    g_state = Failed;
    g_failure = message;
    setStatus(message);
    updateButtons();
}

void tickSeconds() {
    if (g_state != Generating)
        return;
    int seconds = (int)(time(NULL) - g_started);
    setStatus(seconds < 2 ? L"Đang tạo..." : L"Đang tạo... " + std::to_wstring(seconds) + L" giây");
}

void clearTexts() {
    g_result.clear();
    g_failure.clear();
    if (g_window) {
        SetWindowTextW(g_input, L"");
        SetWindowTextW(g_output, L"");
    }
}

void stopRequest() {
    if (g_request) {
        AIClient::cancel(g_request);
        g_request = 0;
    }
    KillTimer(g_window, kTimerSeconds);
}

void ask() {
    if (g_state == Generating)
        return;
    std::wstring prompt = fromEdit(textOf(g_input));
    if (!hasText()) {
        setHint(g_activePreset >= 0 ? L"Hãy nhập hoặc dán đoạn văn cần chuyển đổi trước."
                                    : L"Hãy gõ yêu cầu trước, ví dụ \"Viết email xin nghỉ phép\".");
        SetFocus(g_input);
        return;
    }
    const vai::Provider& provider = chosenProvider();
    AISettings::setProviderId(provider.id);
    vai::Config config;
    std::wstring reason;
    if (!AISettings::configurationFor(provider, true, config, reason)) {
        showFailure(reason);
        return;
    }
    g_result.clear();
    SetWindowTextW(g_output, L"");
    g_started = time(NULL);
    //a conversion that was chosen goes in front of the text; it is not written in the box, the button that is down says which one it is
    std::string request = wideStringToUtf8(prompt);
    g_poemRequest = false;
    if (g_activePreset >= 0 && (size_t)g_activePreset < g_presets.list.size()) {
        const vpreset::Preset& preset = g_presets.list[(size_t)g_activePreset];
        request = vpreset::buildPrompt(g_presets, preset, request);
        g_poemRequest = preset.poem;
    }
    unsigned id = AIClient::generate(config, request, g_window, reason);
    if (id == 0) {
        showFailure(reason);
        return;
    }
    g_request = id;
    g_state = Generating;
    setStatus(L"Đang tạo...");
    updateButtons();
    SetTimer(g_window, kTimerSeconds, 1000, NULL);
}

void stop() {
    if (g_state != Generating)
        return;
    stopRequest();
    g_state = g_result.empty() ? Idle : Done;
    setStatus(g_result.empty() ? L"Đã dừng." : L"Đã dừng. Phần đã viết được giữ lại.");
    updateButtons();
}

//A click on a conversion: chooses it and asks at once. Nothing happens while an answer is on its way.
void applyPreset(int index) {
    if (g_state == Generating || index < 0 || (size_t)index >= g_presets.list.size())
        return;
    if (!hasText()) {
        setHint(L"Hãy nhập hoặc dán đoạn văn cần chuyển đổi trước.");
        SetFocus(g_input);
        return;
    }
    g_activePreset = index;
    updatePresetButtons();
    SetFocus(g_input);          //the button that was clicked is about to be turned off while the answer comes, and Esc must still stop it
    ask();
}

std::wstring g_pasteText;
HWND g_pasteTarget = NULL;

//the keys of the shortcut (Ctrl+Shift+Enter) may still be down: Ctrl+V sent now would be Ctrl+Shift+V
void pasteResult() {
    TextInserter::insertText(g_pasteText, g_pasteTarget);
    g_pasteText.clear();
}

void insertResult() {
    if (g_result.empty() || g_state == Generating)
        return;
    g_pasteText = g_result;
    g_pasteTarget = g_target;
    AIAssistant::hide(); //the text of the window is gone, the copy above is what is pasted
    TextInserter::runWhenKeysReleased(pasteResult);
}

void copyResult() {
    if (g_result.empty())
        return;
    if (!OpenClipboard(g_window))
        return;
    EmptyClipboard();
    size_t bytes = (g_result.size() + 1) * sizeof(wchar_t);
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (memory) {
        void* destination = GlobalLock(memory);
        if (destination) {
            memcpy(destination, g_result.c_str(), bytes);
            GlobalUnlock(memory);
            if (!SetClipboardData(CF_UNICODETEXT, memory))
                GlobalFree(memory);
        } else {
            GlobalFree(memory);
        }
    }
    CloseClipboard();
    setStatus(L"Đã sao chép.");
    SetTimer(g_window, kTimerCopied, 2000, NULL);
}

//The ready-made conversions: buttons in rows that break where the width of the window ends (a row of controls does not wrap by itself).
//With `move` false it only measures. Returns the height the rows need.
int layoutPresets(int x, int y, int width, bool move) {
    if (g_presetButtons.empty())
        return 0;
    int gap = px(6), rowHeight = px(26);
    int rowY = y, cx = x + g_presetCaptionWidth + gap, rowStart = cx;
    if (move)
        MoveWindow(g_presetCaption, x, rowY + px(4), g_presetCaptionWidth, px(20), TRUE);
    for (size_t i = 0; i < g_presetButtons.size(); i++) {
        int w = g_presetWidths[i];
        if (cx > rowStart && cx + w > x + width) {      //it does not fit: the next row, from the left edge
            rowY += rowHeight + px(4);
            cx = rowStart = x;
        }
        if (move)
            MoveWindow(g_presetButtons[i], cx, rowY, w, rowHeight, TRUE);
        cx += w + gap;
    }
    return rowY + rowHeight - y;
}

void layout() {
    RECT client;
    GetClientRect(g_window, &client);
    int width = client.right, height = client.bottom;
    int pad = px(14), gap = px(8);
    int y = pad;
    int rowHeight = px(28);

    int comboWidth = px(240), settingsWidth = px(120);
    MoveWindow(g_provider, pad, y, comboWidth, px(300), TRUE);
    MoveWindow(g_settings, width - pad - settingsWidth, y, settingsWidth, rowHeight, TRUE);
    MoveWindow(g_model, pad + comboWidth + gap, y + px(5), width - pad * 2 - comboWidth - settingsWidth - gap * 2, px(20), TRUE);
    y += rowHeight + gap;

    MoveWindow(g_context, pad, y, width - pad * 2, px(38), TRUE);
    y += px(38) + gap;

    MoveWindow(g_labelInput, pad, y, width - pad * 2, px(20), TRUE);
    y += px(20);
    int stripHeight = layoutPresets(pad, 0, width - pad * 2, false);
    int inputHeight = (std::max)(px(90), (height - y - px(190) - (stripHeight > 0 ? stripHeight + gap : 0)) / 2);
    MoveWindow(g_input, pad, y, width - pad * 2, inputHeight, TRUE);
    y += inputHeight + gap;
    if (stripHeight > 0) {
        layoutPresets(pad, y, width - pad * 2, true);
        y += stripHeight + gap;
    }

    int askWidth = px(150);
    MoveWindow(g_ask, pad, y, askWidth, rowHeight + px(4), TRUE);
    MoveWindow(g_status, pad + askWidth + gap, y + px(4), width - pad * 2 - askWidth - gap, px(36), TRUE);
    y += rowHeight + px(4) + gap;

    MoveWindow(g_labelOutput, pad, y, width - pad * 2, px(20), TRUE);
    y += px(20);
    int bottom = height - pad - rowHeight - gap;
    MoveWindow(g_output, pad, y, width - pad * 2, (std::max)(px(60), bottom - y), TRUE);
    int buttonsTop = height - pad - rowHeight;
    MoveWindow(g_insert, pad, buttonsTop, px(290), rowHeight, TRUE);
    MoveWindow(g_copy, pad + px(290) + gap, buttonsTop, px(220), rowHeight, TRUE);
}

HWND child(const wchar_t* cls, const wchar_t* text, DWORD style, int id, DWORD exStyle = 0) {
    HWND control = CreateWindowExW(exStyle, cls, text, WS_CHILD | WS_VISIBLE | style, 0, 0, 10, 10, g_window, (HMENU)(INT_PTR)id,
                                   GetModuleHandleW(NULL), NULL);
    SendMessageW(control, WM_SETFONT, (WPARAM)g_font, TRUE);
    return control;
}

//the keys of the assistant, read in both text boxes (the answer box is read only but can have the keyboard)
LRESULT CALLBACK editProc(HWND edit, UINT message, WPARAM wParam, LPARAM lParam) {
    WNDPROC original = (WNDPROC)GetWindowLongPtrW(edit, GWLP_USERDATA);
    //with Ctrl held, Enter is ours: the dialog manager would press the default button ("Tạo") instead. Without Ctrl, Tab and Esc
    //keep moving and closing as in any dialog.
    if (message == WM_GETDLGCODE && GetKeyState(VK_CONTROL) < 0)
        return DLGC_WANTALLKEYS | (LRESULT)CallWindowProcW(original, edit, message, wParam, lParam);
    if (message == WM_KEYDOWN) {
        bool control = GetKeyState(VK_CONTROL) < 0, shift = GetKeyState(VK_SHIFT) < 0;
        if (wParam == VK_RETURN && control && !shift && edit == g_input) {
            ask();
            return 0;
        }
        if (wParam == VK_RETURN && control && shift) {
            insertResult();
            return 0;
        }
        if (wParam == 'C' && control && shift) {
            copyResult();
            return 0;
        }
    }
    if (message == WM_CHAR && wParam == '\n' && GetKeyState(VK_CONTROL) < 0)
        return 0; //Ctrl+Enter is not a character of the request
    return CallWindowProcW(original, edit, message, wParam, lParam);
}

LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_SIZE:
        if (g_ask)
            layout();
        return 0;
    case WM_GETMINMAXINFO: {
        MINMAXINFO* info = (MINMAXINFO*)lParam;
        info->ptMinTrackSize.x = px(600);      //wide enough for the conversions to fit in three rows
        info->ptMinTrackSize.y = px(580);
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
    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLORBTN: {
        FeatureTheme::Colors theme = FeatureTheme::colors();
        int id = GetDlgCtrlID((HWND)lParam);
        bool quiet = id == kIdContext || id == kIdModel || id == kIdStatus;
        bool error = id == kIdStatus && g_state == Failed;
        SetTextColor((HDC)wParam, error ? RGB(200, 40, 40) : (quiet ? theme.secondaryText : theme.text));
        SetBkColor((HDC)wParam, theme.background);
        return (LRESULT)g_backgroundBrush;
    }
    case WM_COMMAND: {
        int id = LOWORD(wParam);
        if (id == kIdAsk) {
            if (g_state == Generating) stop(); else ask();
        } else if (id == kIdInsert) {
            insertResult();
        } else if (id == kIdCopy) {
            copyResult();
        } else if (id >= kIdPresetFirst && id < kIdPresetFirst + (int)g_presetButtons.size() && HIWORD(wParam) == BN_CLICKED) {
            applyPreset(id - kIdPresetFirst);
        } else if (id == kIdInput && HIWORD(wParam) == EN_CHANGE) {
            //the text is no longer the one the conversion was chosen for: what is typed now is a request of its own
            g_activePreset = -1;
            updatePresetButtons();
            if (g_hintShown && g_state == Idle)
                setStatus(L"");
        } else if (id == kIdSettings) {
            AISettingsDialog::show();
        } else if (id == kIdProvider && HIWORD(wParam) == CBN_SELCHANGE) {
            AISettings::setProviderId(chosenProvider().id);
            showModel();
            setStatus(L"");
        } else if (id == IDCANCEL) { //Esc: stops what is going on, otherwise closes
            if (g_state == Generating) stop(); else AIAssistant::hide();
        }
        return 0;
    }
    case WM_TIMER:
        if (wParam == kTimerSeconds) {
            tickSeconds();
        } else if (wParam == kTimerCopied) {
            KillTimer(window, kTimerCopied);
            if (g_state != Generating && g_state != Failed)
                setStatus(L"");
        }
        return 0;
    case AIClient::kMessageText: {
        std::wstring* piece = (std::wstring*)lParam;
        if (piece) {
            if ((unsigned)wParam == g_request && g_state == Generating) {
                g_result += *piece;
                appendOutput(*piece);
            }
            delete piece;
        }
        return 0;
    }
    case AIClient::kMessageDone: {
        AIClient::Done* done = (AIClient::Done*)lParam;
        if (done) {
            if ((unsigned)wParam == g_request && g_state == Generating) {
                g_request = 0;
                KillTimer(window, kTimerSeconds);
                if (done->error.ok()) {
                    g_state = Done;
                    //the rhymes and the number of syllables of a poem are the AI's word: the window does not count them
                    setStatus(g_poemRequest ? L"Xong. Số tiếng và vần của thơ chưa được kiểm tra, hãy đọc lại. Ctrl+Shift+Enter để chèn, Ctrl+Shift+C để sao chép."
                                            : L"Xong. Ctrl+Shift+Enter để chèn vào chỗ đang gõ, Ctrl+Shift+C để sao chép.");
                    updateButtons();
                } else {
                    //what came before the error stays readable
                    showFailure(done->message);
                }
            }
            delete done;
        }
        return 0;
    }
    case WM_CLOSE:
        AIAssistant::hide();
        return 0;
    case WM_DESTROY:
        FeatureWindows::unregisterDialog(window);
        g_window = NULL;
        g_presetButtons.clear();
        g_presetWidths.clear();
        g_presetTips.clear();
        g_presetCaption = NULL;
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

//The row of ready-made conversions, from the file of the program; without a usable file there is no row and the window is what it was.
void buildPresets() {
    g_presetButtons.clear();
    g_presetWidths.clear();
    g_presetTips.clear();
    g_presetCaption = NULL;
    g_activePreset = -1;
    if (!vpreset::parse(FeatureStorage::resourceText(IDR_AI_PRESETS), g_presets) || g_presets.list.empty())
        return;
    g_presetCaption = child(L"STATIC", L"Chuyển đổi nhanh:", SS_NOPREFIX, kIdPresetCaption);
    HDC dc = GetDC(g_window);
    HGDIOBJ old = SelectObject(dc, g_font);
    SIZE size = {0, 0};
    GetTextExtentPoint32W(dc, L"Chuyển đổi nhanh:", 17, &size);
    g_presetCaptionWidth = size.cx + px(6);
    for (size_t i = 0; i < g_presets.list.size(); i++) {
        std::wstring title = utf8ToWideString(g_presets.list[i].title);
        HWND button = child(L"BUTTON", title.c_str(), WS_TABSTOP | BS_CHECKBOX | BS_PUSHLIKE, kIdPresetFirst + (int)i);
        GetTextExtentPoint32W(dc, title.c_str(), (int)title.size(), &size);
        g_presetButtons.push_back(button);
        g_presetWidths.push_back(size.cx + px(24));
        g_presetTips.push_back(utf8ToWideString(g_presets.list[i].summary));
    }
    SelectObject(dc, old);
    ReleaseDC(g_window, dc);
    //what each does, as a tip (the list of the tips is complete before the first is given out: it must not move)
    HWND tip = CreateWindowExW(0, TOOLTIPS_CLASSW, NULL, WS_POPUP | TTS_ALWAYSTIP, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT,
                               g_window, NULL, GetModuleHandleW(NULL), NULL);
    if (!tip)
        return;
    SendMessageW(tip, TTM_SETMAXTIPWIDTH, 0, px(320));
    for (size_t i = 0; i < g_presetButtons.size(); i++) {
        TOOLINFOW info = {0};
        info.cbSize = sizeof(info);
        info.hwnd = g_window;
        info.uFlags = TTF_IDISHWND | TTF_SUBCLASS;
        info.uId = (UINT_PTR)g_presetButtons[i];
        info.lpszText = const_cast<wchar_t*>(g_presetTips[i].c_str());
        SendMessageW(tip, TTM_ADDTOOLW, 0, (LPARAM)&info);
    }
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
    if (g_fieldBrush) DeleteObject(g_fieldBrush);
    if (g_backgroundBrush) DeleteObject(g_backgroundBrush);
    FeatureTheme::Colors theme = FeatureTheme::colors();
    g_font = FeatureTheme::font(10, g_dpi);
    g_boldFont = FeatureTheme::font(10, g_dpi, true);
    g_fieldBrush = CreateSolidBrush(theme.field);
    g_backgroundBrush = CreateSolidBrush(theme.background);

    g_window = CreateWindowExW(WS_EX_TOPMOST, kClassName, L"Trợ lý AI - VOpenKey AI", WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
                               CW_USEDEFAULT, CW_USEDEFAULT, px(700), px(700), NULL, NULL, instance, NULL);
    if (!g_window)
        return false;
    FeatureWindows::registerDialog(g_window);
    g_provider = child(L"COMBOBOX", L"", WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWNLIST, kIdProvider);
    g_model = child(L"STATIC", L"", SS_ENDELLIPSIS, kIdModel);
    g_settings = child(L"BUTTON", L"Cài đặt AI...", WS_TABSTOP | BS_PUSHBUTTON, kIdSettings);
    g_context = child(L"STATIC", L"", 0, kIdContext);
    g_labelInput = child(L"STATIC", L"Yêu cầu của bạn", 0, kIdLabelInput);
    SendMessageW(g_labelInput, WM_SETFONT, (WPARAM)g_boldFont, TRUE);
    g_input = child(L"EDIT", L"", WS_TABSTOP | WS_VSCROLL | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN, kIdInput, WS_EX_CLIENTEDGE);
    SendMessageW(g_input, EM_SETLIMITTEXT, 200000, 0);
    SetWindowLongPtrW(g_input, GWLP_USERDATA, SetWindowLongPtrW(g_input, GWLP_WNDPROC, (LONG_PTR)editProc));
    buildPresets();
    g_ask = child(L"BUTTON", L"Tạo (Ctrl+Enter)", WS_TABSTOP | BS_DEFPUSHBUTTON, kIdAsk);
    g_status = child(L"STATIC", L"", 0, kIdStatus);
    g_labelOutput = child(L"STATIC", L"Kết quả", 0, kIdLabelOutput);
    SendMessageW(g_labelOutput, WM_SETFONT, (WPARAM)g_boldFont, TRUE);
    g_output = child(L"EDIT", L"", WS_TABSTOP | WS_VSCROLL | ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL, kIdOutput, WS_EX_CLIENTEDGE);
    SendMessageW(g_output, EM_SETLIMITTEXT, 0, 0);
    SetWindowLongPtrW(g_output, GWLP_USERDATA, SetWindowLongPtrW(g_output, GWLP_WNDPROC, (LONG_PTR)editProc));
    g_insert = child(L"BUTTON", L"Chèn vào ứng dụng (Ctrl+Shift+Enter)", WS_TABSTOP | BS_PUSHBUTTON, kIdInsert);
    g_copy = child(L"BUTTON", L"Sao chép (Ctrl+Shift+C)", WS_TABSTOP | BS_PUSHBUTTON, kIdCopy);
    layout();
    return true;
}

//The shortcut was pressed and its keys are up: look at what is selected, then open
void openAfterRelease() {
    g_pendingOpen = false;
    //the program in front now is where the answer goes
    HWND target = GetForegroundWindow();
    std::wstring selection;
    if (vAICopySelection)
        TextInserter::copySelection(selection);
    if (!create())
        return;
    g_target = target;
    g_hadSelection = !selection.empty();

    stopRequest();
    g_state = Idle;
    g_activePreset = -1;
    g_result.clear();
    g_failure.clear();
    fillProviders();
    showModel();
    SetWindowTextW(g_output, L"");
    SetWindowTextW(g_input, toEdit(selection).c_str());
    setStatus(L"");
    if (g_hadSelection) {
        SetWindowTextW(g_context, (L"Đang chọn " + std::to_wstring(selection.size()) +
                                   L" ký tự. Gõ yêu cầu ở dòng đầu, ví dụ \"Dịch sang tiếng Anh\", hoặc bấm một kiểu chuyển đổi. Câu trả lời sẽ thay chữ đã chọn.").c_str());
        SendMessageW(g_input, EM_SETSEL, 0, 0); //the cursor in front of the selection, to write the instruction
        //a line of its own for the instruction
        SendMessageW(g_input, EM_REPLACESEL, FALSE, (LPARAM)L"\r\n");
        SendMessageW(g_input, EM_SETSEL, 0, 0);
    } else {
        SetWindowTextW(g_context, L"Gõ điều bạn muốn viết, hoặc dán một đoạn văn rồi bấm một kiểu chuyển đổi. Câu trả lời sẽ được chèn vào chỗ bạn đang gõ.");
    }
    updateButtons();

    const vai::Provider& provider = AISettings::provider();
    if (!AISettings::isReady(provider)) {
        std::wstring name = AIText::displayName(provider);
        g_state = Failed;
        setStatus(provider.needsKey ? L"Chưa có API key của " + name + L". Bấm \"Cài đặt AI...\" để nhập."
                                    : L"Chưa cài đặt xong " + name + L". Bấm \"Cài đặt AI...\".");
    }

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
    SetFocus(g_input);
}

} // namespace

namespace AIAssistant {

bool isVisible() {
    return g_window && IsWindowVisible(g_window);
}

void hide() {
    if (!g_window)
        return;
    stopRequest();
    g_state = Idle;
    g_activePreset = -1;
    ShowWindow(g_window, SW_HIDE);
    clearTexts(); //nothing typed or received is kept
}

void toggle() {
    if (isVisible()) {
        hide();
        return;
    }
    if (g_pendingOpen)
        return;
    g_pendingOpen = true;
    TextInserter::runWhenKeysReleased(openAfterRelease);
}

} // namespace AIAssistant
