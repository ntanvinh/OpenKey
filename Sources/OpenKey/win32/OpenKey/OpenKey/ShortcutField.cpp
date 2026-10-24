//
//  ShortcutField.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "ShortcutField.h"
#include "FeatureActions.h"
#include <map>

namespace {

struct Entry {
    int* variable;
    const wchar_t* registryName;
    void (*message)(const std::wstring&);
    WNDPROC original;
};

std::map<HWND, Entry> g_fields;
HWND g_recording = NULL;

void show(HWND field, const Entry& entry) {
    SetWindowTextW(field, FeatureActions::describeShortcut(*entry.variable).c_str());
}

LRESULT CALLBACK fieldProc(HWND field, UINT message, WPARAM wParam, LPARAM lParam) {
    std::map<HWND, Entry>::iterator found = g_fields.find(field);
    if (found == g_fields.end())
        return DefWindowProcW(field, message, wParam, lParam);
    Entry& entry = found->second;
    switch (message) {
    case WM_SETFOCUS:
        g_recording = field;
        SetWindowTextW(field, L"Nhấn phím tắt...");
        entry.message(L"Nhấn tổ hợp phím (có Ctrl, Alt hoặc Win). Backspace xoá phím tắt, Esc giữ như cũ.");
        break;
    case WM_KILLFOCUS:
        if (g_recording == field)
            g_recording = NULL;
        show(field, entry);
        entry.message(L"");
        break;
    case WM_GETDLGCODE:
        return DLGC_WANTALLKEYS | DLGC_WANTCHARS;
    case WM_CHAR:
    case WM_SYSCHAR:
        return 0;
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN: {
        unsigned key = (unsigned)wParam;
        if (key == VK_SHIFT || key == VK_CONTROL || key == VK_MENU || key == VK_LWIN || key == VK_RWIN)
            return 0;
        if (key == VK_ESCAPE) {
            SetFocus(GetParent(field));
            return 0;
        }
        int value;
        if (key == VK_BACK || key == VK_DELETE) {
            value = (int)VOK_SHORTCUT_NONE;
        } else {
            bool control = GetKeyState(VK_CONTROL) < 0, alt = GetKeyState(VK_MENU) < 0;
            bool win = GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0, shift = GetKeyState(VK_SHIFT) < 0;
            if (!control && !alt && !win) {
                //a plain letter as a shortcut would be typed text
                entry.message(L"Phím tắt cần kèm Ctrl, Alt hoặc Win.");
                return 0;
            }
            value = (int)key | (control ? 0x100 : 0) | (alt ? 0x200 : 0) | (win ? 0x400 : 0) | (shift ? 0x800 : 0) | (int)(key << 24);
            std::wstring conflict = FeatureActions::conflictOf(value, entry.variable);
            if (!conflict.empty()) {
                entry.message(L"Phím này đang dùng để " + conflict + L". Chọn phím khác.");
                return 0;
            }
        }
        FeatureActions::saveHotKey(entry.variable, entry.registryName, value);
        SetFocus(GetParent(field));
        return 0;
    }
    case WM_NCDESTROY: {
        WNDPROC original = entry.original;
        g_fields.erase(found);
        return CallWindowProcW(original, field, message, wParam, lParam);
    }
    }
    return CallWindowProcW(entry.original, field, message, wParam, lParam);
}

} // namespace

namespace ShortcutField {

void attach(HWND field, int* variable, const wchar_t* registryName, void (*message)(const std::wstring& text)) {
    Entry entry = {variable, registryName, message, NULL};
    entry.original = (WNDPROC)SetWindowLongPtrW(field, GWLP_WNDPROC, (LONG_PTR)fieldProc);
    g_fields[field] = entry;
    show(field, g_fields[field]);
}

void refresh() {
    for (std::map<HWND, Entry>::iterator it = g_fields.begin(); it != g_fields.end(); ++it)
        show(it->first, it->second);
}

bool isRecording() {
    return g_recording != NULL;
}

} // namespace ShortcutField
