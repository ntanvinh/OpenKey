//
//  TextInserter.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "TextInserter.h"
#include <utility>

namespace {

const UINT kRestoreDelayMs = 700; //the program reads the clipboard a moment after Ctrl+V

struct Snapshot {
    std::vector<std::pair<UINT, std::vector<BYTE> > > formats;
    bool taken = false;
};

Snapshot g_waiting;               //what the clipboard held before our text was put on it
DWORD g_sequenceAfterOurs = 0;    //the clipboard as we left it: when it changed, someone copied something
bool g_restorePending = false;
UINT_PTR g_restoreTimer = 0;

bool openClipboard() {
    for (int attempt = 0; attempt < 10; attempt++) { //another program may hold it for a moment
        if (OpenClipboard(NULL))
            return true;
        Sleep(15);
    }
    return false;
}

//Formats whose data is a block of memory. The others (bitmaps, palettes, metafiles) are handles to GDI objects that Windows
//makes from the block formats (CF_DIB...) itself, so putting the blocks back brings them back as well.
bool isMemoryFormat(UINT format) {
    switch (format) {
    case CF_BITMAP: case CF_METAFILEPICT: case CF_PALETTE: case CF_ENHMETAFILE: case CF_OWNERDISPLAY:
    case CF_DSPTEXT: case CF_DSPBITMAP: case CF_DSPMETAFILEPICT: case CF_DSPENHMETAFILE:
        return false;
    }
    return !(format >= CF_GDIOBJFIRST && format <= CF_GDIOBJLAST) && !(format >= CF_PRIVATEFIRST && format <= CF_PRIVATELAST);
}

Snapshot takeSnapshot() {
    Snapshot snapshot;
    if (!openClipboard())
        return snapshot;
    for (UINT format = EnumClipboardFormats(0); format != 0; format = EnumClipboardFormats(format)) {
        if (!isMemoryFormat(format))
            continue;
        HANDLE handle = GetClipboardData(format);
        if (!handle)
            continue;
        SIZE_T size = GlobalSize(handle);
        const BYTE* bytes = size > 0 ? (const BYTE*)GlobalLock(handle) : NULL;
        if (!bytes)
            continue;
        snapshot.formats.push_back(std::make_pair(format, std::vector<BYTE>(bytes, bytes + size)));
        GlobalUnlock(handle);
    }
    CloseClipboard();
    snapshot.taken = true;
    return snapshot;
}

bool putFormat(UINT format, const BYTE* bytes, SIZE_T size) {
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, size > 0 ? size : 1);
    if (!memory)
        return false;
    void* destination = GlobalLock(memory);
    if (!destination) {
        GlobalFree(memory);
        return false;
    }
    if (size > 0)
        memcpy(destination, bytes, size);
    GlobalUnlock(memory);
    if (!SetClipboardData(format, memory)) {
        GlobalFree(memory);
        return false;
    }
    return true;
}

void restoreSnapshot(const Snapshot& snapshot) {
    if (!openClipboard())
        return;
    EmptyClipboard();
    for (size_t i = 0; i < snapshot.formats.size(); i++)
        putFormat(snapshot.formats[i].first, snapshot.formats[i].second.data(), snapshot.formats[i].second.size());
    CloseClipboard();
}

//The text goes on the clipboard, marked so that clipboard history and the cloud clipboard leave it alone
bool putTemporaryText(const std::wstring& text) {
    if (!openClipboard())
        return false;
    EmptyClipboard();
    bool ok = putFormat(CF_UNICODETEXT, (const BYTE*)text.c_str(), (text.size() + 1) * sizeof(wchar_t));
    DWORD zero = 0, one = 1;
    UINT history = RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");
    UINT cloud = RegisterClipboardFormatW(L"CanUploadToCloudClipboard");
    UINT monitors = RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing");
    putFormat(history, (const BYTE*)&zero, sizeof(zero));
    putFormat(cloud, (const BYTE*)&zero, sizeof(zero));
    putFormat(monitors, (const BYTE*)&one, sizeof(one));
    CloseClipboard();
    return ok;
}

void CALLBACK restoreTimerProc(HWND, UINT, UINT_PTR, DWORD) {
    TextInserter::restoreClipboardNow();
}

void sendKeys(const WORD* keys, size_t count) {
    std::vector<INPUT> events(count);
    for (size_t i = 0; i < count; i++) {
        memset(&events[i], 0, sizeof(INPUT));
        events[i].type = INPUT_KEYBOARD;
        events[i].ki.wVk = keys[i] & 0x7FFF;
        events[i].ki.dwFlags = (keys[i] & 0x8000) ? KEYEVENTF_KEYUP : 0;
        events[i].ki.dwExtraInfo = 1; //the keyboard hook of OpenKey leaves what carries 1 alone
    }
    SendInput((UINT)count, events.data(), sizeof(INPUT));
}

} // namespace

namespace TextInserter {

std::wstring clipboardText() {
    std::wstring text;
    if (!openClipboard())
        return text;
    HANDLE handle = GetClipboardData(CF_UNICODETEXT);
    if (handle) {
        const wchar_t* chars = (const wchar_t*)GlobalLock(handle);
        if (chars) {
            text = chars;
            GlobalUnlock(handle);
        }
    }
    CloseClipboard();
    return text;
}

void activateWindow(HWND window) {
    if (!window || !IsWindow(window) || GetForegroundWindow() == window)
        return;
    //Windows only lets the program that has the keyboard hand it over; joining its input queue for a moment is allowed
    DWORD foregroundThread = GetWindowThreadProcessId(GetForegroundWindow(), NULL);
    DWORD ourThread = GetCurrentThreadId();
    bool attached = foregroundThread != ourThread && AttachThreadInput(ourThread, foregroundThread, TRUE);
    if (IsIconic(window))
        ShowWindow(window, SW_RESTORE);
    SetForegroundWindow(window);
    if (attached)
        AttachThreadInput(ourThread, foregroundThread, FALSE);
    for (int i = 0; i < 20 && GetForegroundWindow() != window; i++)
        Sleep(10);
}

void restoreClipboardNow() {
    if (g_restoreTimer) {
        KillTimer(NULL, g_restoreTimer);
        g_restoreTimer = 0;
    }
    if (!g_restorePending)
        return;
    g_restorePending = false;
    //if the user or a program copied something since, that is worth more than what was there before
    if (GetClipboardSequenceNumber() == g_sequenceAfterOurs && g_waiting.taken)
        restoreSnapshot(g_waiting);
    g_waiting = Snapshot();
}

bool copySelection(std::wstring& text) {
    text.clear();
    restoreClipboardNow(); //an earlier text of ours would be taken for the selection
    Snapshot before = takeSnapshot();
    DWORD sequence = GetClipboardSequenceNumber();
    postControlKey('C');
    bool arrived = false;
    for (int i = 0; i < 40; i++) { //about 0.4 s
        Sleep(10);
        if (GetClipboardSequenceNumber() != sequence) {
            arrived = true;
            Sleep(10);
            break;
        }
    }
    if (arrived)
        text = clipboardText();
    if (arrived && before.taken)
        restoreSnapshot(before);
    return arrived && !text.empty();
}

namespace {
void (*g_afterRelease)() = NULL;
DWORD g_releaseStarted = 0;
UINT_PTR g_releaseTimer = 0;

bool modifiersDown() {
    return (GetAsyncKeyState(VK_CONTROL) & 0x8000) || (GetAsyncKeyState(VK_MENU) & 0x8000) ||
           (GetAsyncKeyState(VK_SHIFT) & 0x8000) || (GetAsyncKeyState(VK_LWIN) & 0x8000) || (GetAsyncKeyState(VK_RWIN) & 0x8000);
}

void CALLBACK releaseTimerProc(HWND, UINT, UINT_PTR, DWORD) {
    if (modifiersDown() && GetTickCount() - g_releaseStarted < 1500)
        return;
    KillTimer(NULL, g_releaseTimer);
    g_releaseTimer = 0;
    void (*action)() = g_afterRelease;
    g_afterRelease = NULL;
    if (action)
        action();
}
} // namespace

void runWhenKeysReleased(void (*action)()) {
    g_afterRelease = action;
    g_releaseStarted = GetTickCount();
    if (!g_releaseTimer)
        g_releaseTimer = SetTimer(NULL, 0, 20, releaseTimerProc);
}

void postControlKey(WORD virtualKey) {
    WORD keys[4] = {VK_CONTROL, virtualKey, (WORD)(virtualKey | 0x8000), (WORD)(VK_CONTROL | 0x8000)};
    sendKeys(keys, 4);
}

void insertText(const std::wstring& text, HWND target) {
    //an earlier text may still be waiting to give the clipboard back: that comes first
    restoreClipboardNow();

    Snapshot before = takeSnapshot();
    DWORD sequenceBefore = GetClipboardSequenceNumber();
    if (!putTemporaryText(text)) {
        //the clipboard may have been emptied before the text could be put on it: the user's own is given back
        if (GetClipboardSequenceNumber() != sequenceBefore && before.taken)
            restoreSnapshot(before);
        return;
    }
    g_sequenceAfterOurs = GetClipboardSequenceNumber();
    g_waiting = before;
    g_restorePending = true;

    if (target)
        activateWindow(target);
    postControlKey('V');

    g_restoreTimer = SetTimer(NULL, 0, kRestoreDelayMs, restoreTimerProc);
}

std::string expandedText(const std::string& text) {
    vsnippet::Values values;
    values.clipboard = wideStringToUtf8(clipboardText());
    SYSTEMTIME now;
    GetLocalTime(&now);
    wchar_t buffer[32];
    wsprintfW(buffer, L"%02d/%02d/%04d", now.wDay, now.wMonth, now.wYear);
    values.date = wideStringToUtf8(buffer);
    wsprintfW(buffer, L"%02d:%02d", now.wHour, now.wMinute);
    values.time = wideStringToUtf8(buffer);
    return vsnippet::expand(text, values);
}

void insertSnippetContent(const std::string& content, HWND target) {
    //an earlier text still on the clipboard would be {clipboard}: give the user's clipboard back first
    restoreClipboardNow();
    insertText(utf8ToWideString(expandedText(content)), target);
}

} // namespace TextInserter
