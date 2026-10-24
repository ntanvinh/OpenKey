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
    kIdLabelOutput
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
    SetWindowTextW(g_status, text.c_str());
}

void updateButtons() {
    bool generating = g_state == Generating;
    SetWindowTextW(g_ask, generating ? L"Dừng (Esc)" : L"Tạo (Ctrl+Enter)");
    bool haveResult = !g_result.empty();
    EnableWindow(g_insert, haveResult && !generating);
    EnableWindow(g_copy, haveResult && !generating);
    EnableWindow(g_provider, !generating);
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
    //a request of only blanks asks for nothing
    bool anything = false;
    for (size_t i = 0; i < prompt.size(); i++)
        anything = anything || !(prompt[i] == L' ' || prompt[i] == L'\n' || prompt[i] == L'\t' || prompt[i] == L'\r');
    if (!anything) {
        setStatus(L"Hãy gõ yêu cầu trước, ví dụ \"Viết email xin nghỉ phép\".");
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
    unsigned id = AIClient::generate(config, wideStringToUtf8(prompt), g_window, reason);
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
    int inputHeight = (std::max)(px(90), (height - y - px(190)) / 2);
    MoveWindow(g_input, pad, y, width - pad * 2, inputHeight, TRUE);
    y += inputHeight + gap;

    int askWidth = px(150);
    MoveWindow(g_ask, pad, y, askWidth, rowHeight + px(4), TRUE);
    MoveWindow(g_status, pad + askWidth + gap, y + px(4), width - pad * 2 - askWidth - gap, px(36), TRUE);
    y += rowHeight + px(4) + gap;

    MoveWindow(g_labelOutput, pad, y, width - pad * 2, px(20), TRUE);
    y += px(20);
    int bottom = height - pad - rowHeight - gap;
    MoveWindow(g_output, pad, y, width - pad * 2, (std::max)(px(60), bottom - y), TRUE);
    int buttonsTop = height - pad - rowHeight;
    MoveWindow(g_insert, pad, buttonsTop, px(210), rowHeight, TRUE);
    MoveWindow(g_copy, pad + px(210) + gap, buttonsTop, px(190), rowHeight, TRUE);
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
        info->ptMinTrackSize.x = px(520);
        info->ptMinTrackSize.y = px(480);
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
                    setStatus(L"Xong. Ctrl+Shift+Enter để chèn vào chỗ đang gõ, Ctrl+Shift+C để sao chép.");
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
    if (g_fieldBrush) DeleteObject(g_fieldBrush);
    if (g_backgroundBrush) DeleteObject(g_backgroundBrush);
    FeatureTheme::Colors theme = FeatureTheme::colors();
    g_font = FeatureTheme::font(10, g_dpi);
    g_boldFont = FeatureTheme::font(10, g_dpi, true);
    g_fieldBrush = CreateSolidBrush(theme.field);
    g_backgroundBrush = CreateSolidBrush(theme.background);

    g_window = CreateWindowExW(WS_EX_TOPMOST, kClassName, L"Trợ lý AI - VOpenKey AI", WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
                               CW_USEDEFAULT, CW_USEDEFAULT, px(680), px(620), NULL, NULL, instance, NULL);
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
    g_result.clear();
    g_failure.clear();
    fillProviders();
    showModel();
    SetWindowTextW(g_output, L"");
    SetWindowTextW(g_input, toEdit(selection).c_str());
    setStatus(L"");
    if (g_hadSelection) {
        SetWindowTextW(g_context, (L"Đang chọn " + std::to_wstring(selection.size()) +
                                   L" ký tự. Gõ yêu cầu ở dòng đầu, ví dụ \"Dịch sang tiếng Anh\". Câu trả lời sẽ thay chữ đã chọn.").c_str());
        SendMessageW(g_input, EM_SETSEL, 0, 0); //the cursor in front of the selection, to write the instruction
        //a line of its own for the instruction
        SendMessageW(g_input, EM_REPLACESEL, FALSE, (LPARAM)L"\r\n");
        SendMessageW(g_input, EM_SETSEL, 0, 0);
    } else {
        SetWindowTextW(g_context, L"Gõ điều bạn muốn viết. Câu trả lời sẽ được chèn vào chỗ bạn đang gõ.");
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
