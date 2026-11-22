//
//  DictionaryPalette.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "DictionaryPalette.h"
#include "DictionaryService.h"
#include "FeatureTheme.h"
#include "FeatureWindows.h"
#include "TextInserter.h"
#include "CaseTransformWindows.h"
#include "WordSpeaker.h"
#include "../../../engine/WordSpeech.h"
#include <commdlg.h>
#include <richedit.h>
#include <set>

#pragma comment(lib, "comdlg32.lib")

namespace {

const wchar_t kClassName[] = L"VOpenKeyAIDictPalette";
const int kWidthAt96 = 760;
const int kHeightAt96 = 500;
const int kLeftColAt96 = 258;

enum {
    kIdSearch = 101,
    kIdClear = 102,
    kIdToggleMgr = 103,
    kIdClose = 104,
    kIdResults = 105,
    kIdCopyDef = 106,
    kIdDefView = 107,
    kIdDownloadSelected = 108,
    kIdImportLocal = 109,
    kIdBackLookup = 110,
    kIdCatalogList = 111,
    kIdRowDownload = 112,
    kIdRowToggle = 113,
    kIdRowRemove = 114,
    kIdEmptyBtn = 115,
    kIdSpeak = 116,
    kIdFilterFirst = 200 // up to 215
};

const UINT kMsgServiceUpdated = WM_APP + 61;
const UINT kMsgImportDone = WM_APP + 62;
const UINT_PTR kTimerSearch = 1;
const UINT_PTR kTimerCopyReset = 2;

HWND g_window = NULL;
HWND g_search = NULL;
HWND g_clearBtn = NULL;
HWND g_mgrBtn = NULL;
HWND g_closeBtn = NULL;
HWND g_results = NULL;
HWND g_defHeader = NULL;
HWND g_copyDefBtn = NULL;
HWND g_speakBtn = NULL;
HWND g_defView = NULL;
HWND g_emptyBtn = NULL;

HWND g_mgrBanner = NULL;
HWND g_backBtn = NULL;
HWND g_downloadSelBtn = NULL;
HWND g_importBtn = NULL;
HWND g_catalogList = NULL;
HWND g_rowDlBtn = NULL;
HWND g_rowToggleBtn = NULL;
HWND g_rowRemoveBtn = NULL;

HWND g_footerLeft = NULL;
HWND g_footerRight = NULL;

std::vector<HWND> g_filterButtons;
std::vector<std::string> g_filterIds; // index 0 = "" (all)

WNDPROC g_origSearchProc = NULL;
HFONT g_font = NULL;
HFONT g_boldFont = NULL;
HFONT g_smallFont = NULL;
HFONT g_titleFont = NULL;
HBRUSH g_bgBrush = NULL;
HBRUSH g_fieldBrush = NULL;
HMODULE g_richEditDll = NULL;
bool g_useRichEdit = false;
int g_dpi = 96;

bool g_showingManager = false;
bool g_openingDialog = false;
std::string g_selectedFilterId;
std::vector<vdict::SearchItem> g_hits;
std::vector<DictionaryService::CatalogStatusItem> g_catalog;
std::set<std::string> g_checkedIds;
bool g_defaultsSeeded = false;
std::wstring g_renderedPlainText;
std::wstring g_customStatusBanner;
std::wstring g_speakText;       // what the speaker button reads for the word on show; empty when it is not an English word

int px(int at96) {
    return FeatureTheme::scale(at96, g_dpi);
}

void recreateResources() {
    FeatureTheme::Colors c = FeatureTheme::colors();
    if (g_bgBrush) DeleteObject(g_bgBrush);
    if (g_fieldBrush) DeleteObject(g_fieldBrush);
    if (g_font) DeleteObject(g_font);
    if (g_boldFont) DeleteObject(g_boldFont);
    if (g_smallFont) DeleteObject(g_smallFont);
    if (g_titleFont) DeleteObject(g_titleFont);

    g_bgBrush = CreateSolidBrush(c.background);
    g_fieldBrush = CreateSolidBrush(c.field);
    g_font = FeatureTheme::font(10, g_dpi, false);
    g_boldFont = FeatureTheme::font(10, g_dpi, true);
    g_smallFont = FeatureTheme::font(9, g_dpi, false);
    g_titleFont = FeatureTheme::font(13, g_dpi, true);
}

HWND makeCtrl(const wchar_t* cls, const wchar_t* text, DWORD style, int x, int y, int w, int h, int id, DWORD exStyle = 0) {
    HWND ctrl = CreateWindowExW(exStyle, cls, text, WS_CHILD | WS_VISIBLE | style, x, y, w, h,
                                g_window, (HMENU)(INT_PTR)id, GetModuleHandleW(NULL), NULL);
    SendMessageW(ctrl, WM_SETFONT, (WPARAM)g_font, TRUE);
    return ctrl;
}

void seedDefaultsIfNeeded() {
    if (g_defaultsSeeded) return;
    g_defaultsSeeded = true;
    for (size_t i = 0; i < g_catalog.size(); ++i) {
        if (!g_catalog[i].installed && g_catalog[i].recommended)
            g_checkedIds.insert(g_catalog[i].dictId);
    }
}

void setRichOrPlainText(const std::wstring& plainText, const std::vector<vdict::DefinitionSection>* secs, const std::wstring& headword, const std::wstring& subtitle) {
    g_renderedPlainText = plainText;
    if (!g_defView) return;

    if (!g_useRichEdit || !secs) {
        SetWindowTextW(g_defView, plainText.c_str());
        return;
    }

    FeatureTheme::Colors theme = FeatureTheme::colors();
    bool light = FeatureTheme::usesLightTheme();
    COLORREF accentBlue = light ? RGB(0, 95, 195) : RGB(100, 175, 255);
    COLORREF accentTeal = light ? RGB(10, 125, 130) : RGB(80, 210, 200);

    SendMessageW(g_defView, WM_SETREDRAW, FALSE, 0);
    SendMessageW(g_defView, EM_SETBKGNDCOLOR, 0, (LPARAM)theme.field);
    SetWindowTextW(g_defView, L"");

    auto appendFormatted = [&](const std::wstring& chunk, int pts, bool bold, bool italic, COLORREF color, const wchar_t* face) {
        CHARRANGE cr;
        cr.cpMin = -1; cr.cpMax = -1;
        SendMessageW(g_defView, EM_EXSETSEL, 0, (LPARAM)&cr);
        CHARFORMAT2W cf;
        ZeroMemory(&cf, sizeof(cf));
        cf.cbSize = sizeof(cf);
        cf.dwMask = CFM_COLOR | CFM_SIZE | CFM_BOLD | CFM_ITALIC | CFM_FACE;
        cf.crTextColor = color;
        cf.yHeight = pts * 20;
        cf.dwEffects = (bold ? CFE_BOLD : 0) | (italic ? CFE_ITALIC : 0);
        wcsncpy(cf.szFaceName, face ? face : L"Segoe UI", LF_FACESIZE - 1);
        SendMessageW(g_defView, EM_SETCHARFORMAT, SCF_SELECTION, (LPARAM)&cf);
        SendMessageW(g_defView, EM_REPLACESEL, FALSE, (LPARAM)chunk.c_str());
    };

    appendFormatted(headword + L"\r\n", 15, true, false, theme.text, L"Segoe UI");
    if (!subtitle.empty())
        appendFormatted(subtitle + L"\r\n", 9, false, false, theme.secondaryText, L"Segoe UI");

    for (size_t i = 0; i < secs->size(); ++i) {
        const vdict::DefinitionSection& s = (*secs)[i];
        std::wstring hdr = L"\r\n[" + DictionaryService::utf8ToWide(s.badge) + L"] " + DictionaryService::utf8ToWide(s.dictName);
        if (!s.matchedVia.empty())
            hdr += L" (qua \"" + DictionaryService::utf8ToWide(s.matchedVia) + L"\")";
        hdr += L"\r\n";
        appendFormatted(hdr, 9, true, false, accentBlue, L"Segoe UI");

        for (size_t li = 0; li < s.lines.size(); ++li) {
            const vdict::FormattedLine& ln = s.lines[li];
            std::wstring txt = DictionaryService::utf8ToWide(ln.text);
            std::wstring sec = DictionaryService::utf8ToWide(ln.secondary);
            switch (ln.kind) {
            case vdict::BlockKind::Headword:
                appendFormatted(txt + L"\r\n", 11, true, false, theme.text, L"Segoe UI");
                break;
            case vdict::BlockKind::Phonetic:
                appendFormatted(txt + L"\r\n", 10, false, false, theme.secondaryText, L"Consolas");
                break;
            case vdict::BlockKind::PartOfSpeech:
                appendFormatted(txt + L"\r\n", 9, true, false, accentTeal, L"Segoe UI");
                break;
            case vdict::BlockKind::Sense:
                appendFormatted(L"  \u2022 " + txt + L"\r\n", 10, false, false, theme.text, L"Segoe UI");
                break;
            case vdict::BlockKind::SubSense:
                appendFormatted(L"      \u25E6 " + txt + L"\r\n", 10, false, false, theme.text, L"Segoe UI");
                break;
            case vdict::BlockKind::Example:
                appendFormatted(L"    \u201C" + txt + L"\u201D", 10, false, true, theme.text, L"Segoe UI");
                if (!sec.empty())
                    appendFormatted(L" \u2014 " + sec, 10, false, false, theme.secondaryText, L"Segoe UI");
                appendFormatted(L"\r\n", 10, false, false, theme.text, L"Segoe UI");
                break;
            default:
                appendFormatted(txt + L"\r\n", 10, false, false, ln.kind == vdict::BlockKind::Note ? theme.secondaryText : theme.text, L"Segoe UI");
                break;
            }
        }
    }

    CHARRANGE top = {0, 0};
    SendMessageW(g_defView, EM_EXSETSEL, 0, (LPARAM)&top);
    SendMessageW(g_defView, EM_SCROLLCARET, 0, 0);
    SendMessageW(g_defView, WM_SETREDRAW, TRUE, 0);
    InvalidateRect(g_defView, NULL, TRUE);
}

void updateFooter() {
    if (!g_footerLeft) return;
    if (!g_customStatusBanner.empty()) {
        SetWindowTextW(g_footerLeft, g_customStatusBanner.c_str());
        return;
    }
    int active = 0;
    uint64_t words = 0;
    std::wstring dlText;
    for (size_t i = 0; i < g_catalog.size(); ++i) {
        if (g_catalog[i].downloading && dlText.empty())
            dlText = g_catalog[i].shortName + L": " + g_catalog[i].statusText;
        if (g_catalog[i].installed && g_catalog[i].enabled) {
            active++;
            words += g_catalog[i].headwordCount;
        }
    }
    if (!dlText.empty())
        SetWindowTextW(g_footerLeft, dlText.c_str());
    else if (active == 0)
        SetWindowTextW(g_footerLeft, L"Chưa bật bộ từ điển nào — hãy tải hoặc nhập file.");
    else
        SetWindowTextW(g_footerLeft, (std::to_wstring(active) + L" bộ từ điển đang bật (" + std::to_wstring(words) + L" mục từ)").c_str());
}

void rebuildFilterStrip() {
    for (size_t i = 0; i < g_filterButtons.size(); ++i)
        DestroyWindow(g_filterButtons[i]);
    g_filterButtons.clear();
    g_filterIds.clear();

    if (g_showingManager || !g_window)
        return;

    int x = px(12);
    int y = px(48);
    int h = px(24);
    int maxX = px(kWidthAt96 - 12);

    auto addPill = [&](const std::wstring& label, const std::string& dictId) {
        int id = kIdFilterFirst + (int)g_filterIds.size();
        if (id >= kIdFilterFirst + 14) return;
        bool active = (g_selectedFilterId == dictId);
        int w = px(20) + (int)label.size() * px(7);
        if (w < px(64)) w = px(64);
        if (w > px(150)) w = px(150);
        if (x + w > maxX) return;
        std::wstring title = active ? (L"\u2713 " + label) : label;
        HWND btn = makeCtrl(L"BUTTON", title.c_str(), BS_PUSHBUTTON | WS_TABSTOP, x, y, w, h, id);
        SendMessageW(btn, WM_SETFONT, (WPARAM)(active ? g_boldFont : g_smallFont), TRUE);
        g_filterButtons.push_back(btn);
        g_filterIds.push_back(dictId);
        x += w + px(6);
    };

    addPill(L"Tất cả", "");
    bool foundFilter = g_selectedFilterId.empty();
    for (size_t i = 0; i < g_catalog.size(); ++i) {
        if (!g_catalog[i].installed || !g_catalog[i].enabled) continue;
        if (g_catalog[i].dictId == g_selectedFilterId) foundFilter = true;
        addPill(g_catalog[i].shortName, g_catalog[i].dictId);
    }
    if (!foundFilter) {
        g_selectedFilterId.clear();
        rebuildFilterStrip();
    }
}

// The speaker is for the headword when a dictionary that has it is English (or has no language): "hello" from an English-Vietnamese
// dictionary, not "ba" from a Vietnamese-English one. What was being read belongs to the word that is no longer shown.
void clearSpeaker() {
    WordSpeaker::stop();
    g_speakText.clear();
    ShowWindow(g_speakBtn, SW_HIDE);
}

void updateSpeaker(const vdict::SearchItem& item, const std::vector<vdict::DefinitionSection>& secs) {
    WordSpeaker::stop();
    std::vector<DictionaryService::CatalogStatusItem> installed = DictionaryService::installedDictionaries();
    std::vector<std::string> langs;
    for (size_t i = 0; i < secs.size(); ++i) {
        std::string lang;
        for (size_t k = 0; k < installed.size(); ++k) {
            if (installed[k].dictId == secs[i].dictId) {
                lang = installed[k].sourceLang;
                break;
            }
        }
        langs.push_back(lang);
    }
    g_speakText = DictionaryService::utf8ToWide(vspeech::TextToSpeak(item.headword, langs));
    ShowWindow(g_speakBtn, (!g_showingManager && !g_speakText.empty()) ? SW_SHOW : SW_HIDE);
}

// Reads the headword that is shown, when it is an English word. A PC without an English voice says so in the footer.
void speakCurrentWord() {
    if (g_speakText.empty() || g_showingManager)
        return;
    if (!WordSpeaker::speak(g_speakText))
        SetWindowTextW(g_footerLeft, L"Chưa có giọng đọc tiếng Anh · Cài ở Cài đặt › Giọng nói");
}

void displayHit(int row) {
    if (row < 0 || (size_t)row >= g_hits.size()) {
        SetWindowTextW(g_defHeader, L"");
        EnableWindow(g_copyDefBtn, FALSE);
        clearSpeaker();
        bool hasDict = DictionaryService::hasInstalledDictionary();
        ShowWindow(g_emptyBtn, hasDict ? SW_HIDE : SW_SHOW);
        setRichOrPlainText(hasDict
            ? L"Không tìm thấy từ khớp.\r\n\r\nThử kiểm tra chính tả, gõ không dấu hoặc mở Bộ từ điển để tải thêm ngôn ngữ."
            : L"Chưa có bộ từ điển nào.\r\n\r\nBấm nút \"Bộ từ điển\" phía trên để tải từ điển Anh–Việt, Việt–Anh miễn phí hoặc nhập file StarDict.",
            NULL, L"", L"");
        return;
    }

    ShowWindow(g_emptyBtn, SW_HIDE);
    const vdict::SearchItem& item = g_hits[(size_t)row];
    std::vector<vdict::DefinitionSection> secs = DictionaryService::loadDefinitions(item, g_selectedFilterId);
    if (secs.empty()) {
        SetWindowTextW(g_defHeader, L"");
        EnableWindow(g_copyDefBtn, FALSE);
        clearSpeaker();
        setRichOrPlainText(L"Không đọc được nội dung mục từ này.", NULL, L"", L"");
        return;
    }

    EnableWindow(g_copyDefBtn, TRUE);
    updateSpeaker(item, secs);
    SetWindowTextW(g_defHeader, secs.size() == 1
        ? DictionaryService::utf8ToWide(secs[0].dictName).c_str()
        : (L"Khớp ở " + std::to_wstring(secs.size()) + L" bộ từ điển").c_str());

    std::wstring hw = DictionaryService::utf8ToWide(item.headword);
    std::wstring sub = item.subtitle.empty() ? L"" : L"Từ gốc cho dạng: " + DictionaryService::utf8ToWide(item.subtitle.substr(item.subtitle.find(' ') + 1));

    std::wstring plain = hw + L"\r\n";
    if (!sub.empty()) plain += sub + L"\r\n";
    for (size_t i = 0; i < secs.size(); ++i) {
        plain += L"\r\n[" + DictionaryService::utf8ToWide(secs[i].badge) + L"] " + DictionaryService::utf8ToWide(secs[i].dictName) + L"\r\n";
        for (size_t li = 0; li < secs[i].lines.size(); ++li) {
            plain += L"  " + DictionaryService::utf8ToWide(secs[i].lines[li].text);
            if (!secs[i].lines[li].secondary.empty())
                plain += L" — " + DictionaryService::utf8ToWide(secs[i].lines[li].secondary);
            plain += L"\r\n";
        }
    }

    setRichOrPlainText(plain, &secs, hw, sub);
}

void reloadSearch(bool selectFirst) {
    if (!g_results) return;
    wchar_t buf[256] = {};
    if (g_search)
        GetWindowTextW(g_search, buf, 255);
    std::string query = DictionaryService::wideToUtf8(buf);

    if (!DictionaryService::hasInstalledDictionary()) {
        g_hits.clear();
        SendMessageW(g_results, LB_RESETCONTENT, 0, 0);
        displayHit(-1);
        return;
    }

    g_hits = DictionaryService::search(query, g_selectedFilterId, 80);
    SendMessageW(g_results, WM_SETREDRAW, FALSE, 0);
    SendMessageW(g_results, LB_RESETCONTENT, 0, 0);
    for (size_t i = 0; i < g_hits.size(); ++i)
        SendMessageW(g_results, LB_ADDSTRING, 0, (LPARAM)L"");
    SendMessageW(g_results, WM_SETREDRAW, TRUE, 0);

    if (!g_hits.empty()) {
        int sel = selectFirst ? 0 : (int)SendMessageW(g_results, LB_GETCURSEL, 0, 0);
        if (sel < 0 || sel >= (int)g_hits.size()) sel = 0;
        SendMessageW(g_results, LB_SETCURSEL, sel, 0);
        displayHit(sel);
    } else {
        displayHit(-1);
    }
}

void updateCatalogActionButtons() {
    if (!g_catalogList || !g_showingManager) return;
    int sel = (int)SendMessageW(g_catalogList, LB_GETCURSEL, 0, 0);
    bool valid = (sel >= 0 && (size_t)sel < g_catalog.size());

    size_t checkedCount = 0;
    for (size_t i = 0; i < g_catalog.size(); ++i) {
        if (!g_catalog[i].installed && !g_catalog[i].downloading && g_checkedIds.count(g_catalog[i].dictId))
            checkedCount++;
    }
    EnableWindow(g_downloadSelBtn, checkedCount > 0);
    SetWindowTextW(g_downloadSelBtn, checkedCount > 0
        ? (L"Tải " + std::to_wstring(checkedCount) + L" bộ đã chọn").c_str()
        : L"Chọn bộ để tải");

    if (!valid) {
        EnableWindow(g_rowDlBtn, FALSE);
        EnableWindow(g_rowToggleBtn, FALSE);
        EnableWindow(g_rowRemoveBtn, FALSE);
        return;
    }

    const DictionaryService::CatalogStatusItem& item = g_catalog[(size_t)sel];
    EnableWindow(g_rowDlBtn, TRUE);
    SetWindowTextW(g_rowDlBtn, item.downloading ? L"Hủy tải" : (item.installed ? L"Đã cài" : L"Tải bộ này"));
    EnableWindow(g_rowDlBtn, !item.installed || item.downloading);
    EnableWindow(g_rowToggleBtn, item.installed);
    SetWindowTextW(g_rowToggleBtn, item.enabled ? L"Tạm tắt" : L"Bật lại");
    EnableWindow(g_rowRemoveBtn, item.installed && !item.downloading);
}

void refreshCatalogList(bool keepSel) {
    int prev = keepSel ? (int)SendMessageW(g_catalogList, LB_GETCURSEL, 0, 0) : 0;
    g_catalog = DictionaryService::allDictionaries();
    seedDefaultsIfNeeded();

    SendMessageW(g_catalogList, WM_SETREDRAW, FALSE, 0);
    SendMessageW(g_catalogList, LB_RESETCONTENT, 0, 0);
    for (size_t i = 0; i < g_catalog.size(); ++i)
        SendMessageW(g_catalogList, LB_ADDSTRING, 0, (LPARAM)L"");
    if (!g_catalog.empty()) {
        if (prev < 0 || prev >= (int)g_catalog.size()) prev = 0;
        SendMessageW(g_catalogList, LB_SETCURSEL, prev, 0);
    }
    SendMessageW(g_catalogList, WM_SETREDRAW, TRUE, 0);
    updateCatalogActionButtons();
    updateFooter();
}

void syncModeVisibility() {
    bool hasDict = DictionaryService::hasInstalledDictionary();
    int lShow = g_showingManager ? SW_HIDE : SW_SHOW;
    int mShow = g_showingManager ? SW_SHOW : SW_HIDE;

    ShowWindow(g_search, lShow);
    ShowWindow(g_clearBtn, lShow);
    ShowWindow(g_results, lShow);
    ShowWindow(g_defHeader, lShow);
    ShowWindow(g_copyDefBtn, lShow);
    ShowWindow(g_speakBtn, (!g_showingManager && !g_speakText.empty()) ? SW_SHOW : SW_HIDE);
    ShowWindow(g_defView, lShow);
    if (g_showingManager) ShowWindow(g_emptyBtn, SW_HIDE);

    ShowWindow(g_mgrBanner, mShow);
    ShowWindow(g_backBtn, (g_showingManager && hasDict) ? SW_SHOW : SW_HIDE);
    ShowWindow(g_downloadSelBtn, mShow);
    ShowWindow(g_importBtn, mShow);
    ShowWindow(g_catalogList, mShow);
    ShowWindow(g_rowDlBtn, mShow);
    ShowWindow(g_rowToggleBtn, mShow);
    ShowWindow(g_rowRemoveBtn, mShow);

    SetWindowTextW(g_mgrBtn, g_showingManager ? L"Tra cứu" : L"Bộ từ điển");
    SetWindowTextW(g_footerRight, g_showingManager
        ? L"Space Chọn · Hỗ trợ StarDict .zip/.ifo · Esc Đóng"
        : L"\u2191\u2193 Chọn từ · Ctrl+P Phát âm · Enter Chép nghĩa · Esc Đóng");

    rebuildFilterStrip();
    if (g_showingManager) {
        refreshCatalogList(true);
    } else {
        reloadSearch(false);
        updateFooter();
        SetFocus(g_search);
    }
    InvalidateRect(g_window, NULL, TRUE);
}

void setMode(bool manager) {
    g_showingManager = manager;
    syncModeVisibility();
}

void copyDefinitionToClipboard() {
    if (g_renderedPlainText.empty() || !OpenClipboard(g_window))
        return;
    EmptyClipboard();
    size_t bytes = (g_renderedPlainText.size() + 1) * sizeof(wchar_t);
    HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (mem) {
        void* ptr = GlobalLock(mem);
        if (ptr) {
            memcpy(ptr, g_renderedPlainText.c_str(), bytes);
            GlobalUnlock(mem);
            SetClipboardData(CF_UNICODETEXT, mem);
        } else {
            GlobalFree(mem);
        }
    }
    CloseClipboard();
    SetWindowTextW(g_copyDefBtn, L"Đã chép");
    SetTimer(g_window, kTimerCopyReset, 1400, NULL);
}

void runImportFileDialog() {
    wchar_t fileBuf[MAX_PATH] = {};
    OPENFILENAMEW ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = g_window;
    ofn.lpstrFilter = L"Bộ từ điển (*.zip;*.ifo;*.txt)\0*.zip;*.ifo;*.txt\0Tất cả tệp (*.*)\0*.*\0";
    ofn.lpstrFile = fileBuf;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrTitle = L"Chọn tệp từ điển StarDict (.zip, .ifo) hoặc FVDP (.txt)";
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;

    g_openingDialog = true;
    BOOL picked = GetOpenFileNameW(&ofn);
    g_openingDialog = false;
    SetForegroundWindow(g_window);
    if (!picked) return;

    g_customStatusBanner = L"Đang nhập & lập chỉ mục từ điển từ máy...";
    updateFooter();
    DictionaryService::importLocalPath(fileBuf, g_window, kMsgImportDone);
}

LRESULT CALLBACK searchSubclassProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (msg == WM_KEYDOWN) {
        if (wParam == VK_DOWN || wParam == VK_UP) {
            int count = (int)SendMessageW(g_results, LB_GETCOUNT, 0, 0);
            if (count > 0) {
                int cur = (int)SendMessageW(g_results, LB_GETCURSEL, 0, 0);
                if (cur < 0) cur = 0;
                int next = (wParam == VK_DOWN) ? min(count - 1, cur + 1) : max(0, cur - 1);
                SendMessageW(g_results, LB_SETCURSEL, next, 0);
                displayHit(next);
            }
            return 0;
        }
        if (wParam == VK_ESCAPE) {
            PostMessageW(g_window, WM_CLOSE, 0, 0);
            return 0;
        }
        if (wParam == VK_RETURN) {
            copyDefinitionToClipboard();
            return 0;
        }
        if (wParam == 'P' && (GetKeyState(VK_CONTROL) & 0x8000) && !(GetKeyState(VK_SHIFT) & 0x8000) && !(GetKeyState(VK_MENU) & 0x8000)) {
            speakCurrentWord();
            return 0;
        }
    }
    return CallWindowProcW(g_origSearchProc, hwnd, msg, wParam, lParam);
}

void paintOwnerDrawResult(DRAWITEMSTRUCT* dis) {
    int idx = (int)dis->itemID;
    if (idx < 0 || (size_t)idx >= g_hits.size()) return;
    const vdict::SearchItem& hit = g_hits[(size_t)idx];
    FeatureTheme::Colors c = FeatureTheme::colors();
    bool sel = (dis->itemState & ODS_SELECTED) != 0;

    HDC dc = dis->hDC;
    RECT rc = dis->rcItem;
    HBRUSH bg = CreateSolidBrush(sel ? c.chosen : c.background);
    FillRect(dc, &rc, bg);
    DeleteObject(bg);

    SetBkMode(dc, TRANSPARENT);
    int badgeW = px(56);
    std::wstring badge = hit.refs.empty() ? L"" : DictionaryService::utf8ToWide(hit.refs[0].badge);
    if (hit.refs.size() > 1)
        badge += L"+" + std::to_wstring(hit.refs.size() - 1);

    if (!badge.empty()) {
        RECT brc = {rc.right - badgeW - px(8), rc.top + px(10), rc.right - px(8), rc.top + px(28)};
        SetTextColor(dc, sel ? c.chosenText : c.secondaryText);
        SelectObject(dc, g_smallFont);
        DrawTextW(dc, badge.c_str(), -1, &brc, DT_RIGHT | DT_VCENTER | DT_SINGLELINE);
    }

    RECT trc = {rc.left + px(10), rc.top + px(5), rc.right - badgeW - px(12), rc.top + px(26)};
    SetTextColor(dc, sel ? c.chosenText : c.text);
    SelectObject(dc, hit.isExact ? g_boldFont : g_font);
    std::wstring hw = DictionaryService::utf8ToWide(hit.headword);
    DrawTextW(dc, hw.c_str(), -1, &trc, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

    if (!hit.subtitle.empty()) {
        RECT src = {rc.left + px(10), rc.top + px(25), rc.right - px(10), rc.bottom - px(3)};
        SetTextColor(dc, sel ? c.chosenText : c.secondaryText);
        SelectObject(dc, g_smallFont);
        std::wstring sub = DictionaryService::utf8ToWide(hit.subtitle);
        DrawTextW(dc, sub.c_str(), -1, &src, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    }
}

void paintOwnerDrawCatalog(DRAWITEMSTRUCT* dis) {
    int idx = (int)dis->itemID;
    if (idx < 0 || (size_t)idx >= g_catalog.size()) return;
    const DictionaryService::CatalogStatusItem& item = g_catalog[(size_t)idx];
    FeatureTheme::Colors c = FeatureTheme::colors();
    bool sel = (dis->itemState & ODS_SELECTED) != 0;

    HDC dc = dis->hDC;
    RECT rc = dis->rcItem;
    HBRUSH bg = CreateSolidBrush(sel ? c.field : c.background);
    FillRect(dc, &rc, bg);
    DeleteObject(bg);
    SetBkMode(dc, TRANSPARENT);

    // Checkbox / Switch glyph in first 36 px
    std::wstring mark = item.installed ? (item.enabled ? L"[B\u1EADt]" : L"[T\u1EAFt]") : (g_checkedIds.count(item.dictId) ? L"[\u2713]" : L"[ ]");
    RECT mrc = {rc.left + px(8), rc.top + px(10), rc.left + px(52), rc.top + px(34)};
    SetTextColor(dc, item.installed ? (item.enabled ? RGB(20, 145, 70) : c.secondaryText) : c.text);
    SelectObject(dc, g_boldFont);
    DrawTextW(dc, mark.c_str(), -1, &mrc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

    // Badge
    RECT brc = {rc.left + px(56), rc.top + px(10), rc.left + px(114), rc.top + px(32)};
    SetTextColor(dc, item.priority <= 30 ? RGB(0, 102, 204) : c.secondaryText);
    SelectObject(dc, g_smallFont);
    DrawTextW(dc, item.badge.c_str(), -1, &brc, DT_LEFT | DT_VCENTER | DT_SINGLELINE);

    // Status on right
    RECT sr = {rc.right - px(160), rc.top + px(10), rc.right - px(12), rc.top + px(32)};
    SetTextColor(dc, item.errorText.empty() ? c.secondaryText : RGB(210, 45, 45));
    DrawTextW(dc, item.statusText.c_str(), -1, &sr, DT_RIGHT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

    // Title
    RECT tr = {rc.left + px(118), rc.top + px(8), rc.right - px(168), rc.top + px(32)};
    SetTextColor(dc, c.text);
    SelectObject(dc, g_boldFont);
    std::wstring title = item.name + (item.recommended ? L"  \u2605" : L"");
    DrawTextW(dc, title.c_str(), -1, &tr, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

    // Second line: description / progress / error
    RECT dr = {rc.left + px(56), rc.top + px(36), rc.right - px(12), rc.bottom - px(6)};
    SetTextColor(dc, item.errorText.empty() ? c.secondaryText : RGB(210, 45, 45));
    SelectObject(dc, g_smallFont);
    std::wstring sub = !item.errorText.empty()
        ? item.errorText
        : (item.downloadSizeText + L" \u00B7 " + item.license + L" \u00B7 " + item.description);
    DrawTextW(dc, sub.c_str(), -1, &dr, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

    HPEN pen = CreatePen(PS_SOLID, 1, c.border);
    HGDIOBJ oldPen = SelectObject(dc, pen);
    MoveToEx(dc, rc.left + px(12), rc.bottom - 1, NULL);
    LineTo(dc, rc.right - px(12), rc.bottom - 1);
    SelectObject(dc, oldPen);
    DeleteObject(pen);
}

LRESULT CALLBACK windowProc(HWND window, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_ERASEBKGND: {
        RECT cr;
        GetClientRect(window, &cr);
        FillRect((HDC)wParam, &cr, g_bgBrush);
        FeatureTheme::Colors c = FeatureTheme::colors();
        HPEN pen = CreatePen(PS_SOLID, 1, c.border);
        HGDIOBJ oldPen = SelectObject((HDC)wParam, pen);
        HGDIOBJ oldBr = SelectObject((HDC)wParam, GetStockObject(NULL_BRUSH));
        Rectangle((HDC)wParam, 0, 0, cr.right, cr.bottom);
        SelectObject((HDC)wParam, oldBr);
        SelectObject((HDC)wParam, oldPen);
        DeleteObject(pen);
        return 1;
    }
    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLORBTN: {
        FeatureTheme::Colors c = FeatureTheme::colors();
        SetTextColor((HDC)wParam, c.text);
        SetBkColor((HDC)wParam, c.background);
        return (LRESULT)g_bgBrush;
    }
    case WM_CTLCOLOREDIT:
    case WM_CTLCOLORLISTBOX: {
        FeatureTheme::Colors c = FeatureTheme::colors();
        SetTextColor((HDC)wParam, c.text);
        SetBkColor((HDC)wParam, c.field);
        return (LRESULT)g_fieldBrush;
    }
    case WM_MEASUREITEM: {
        MEASUREITEMSTRUCT* mis = (MEASUREITEMSTRUCT*)lParam;
        if (mis->CtlID == kIdResults) mis->itemHeight = px(44);
        else if (mis->CtlID == kIdCatalogList) mis->itemHeight = px(64);
        return TRUE;
    }
    case WM_DRAWITEM: {
        DRAWITEMSTRUCT* dis = (DRAWITEMSTRUCT*)lParam;
        if (dis->CtlID == kIdResults) paintOwnerDrawResult(dis);
        else if (dis->CtlID == kIdCatalogList) paintOwnerDrawCatalog(dis);
        return TRUE;
    }
    case WM_NCHITTEST: {
        LRESULT hit = DefWindowProcW(window, msg, wParam, lParam);
        if (hit == HTCLIENT) {
            POINT pt = {(short)LOWORD(lParam), (short)HIWORD(lParam)};
            ScreenToClient(window, &pt);
            if (pt.y < px(10)) return HTCAPTION;
        }
        return hit;
    }
    case WM_TIMER:
        if (wParam == kTimerSearch) {
            KillTimer(window, kTimerSearch);
            reloadSearch(true);
        } else if (wParam == kTimerCopyReset) {
            KillTimer(window, kTimerCopyReset);
            SetWindowTextW(g_copyDefBtn, L"Sao chép nghĩa");
        }
        return 0;
    case kMsgServiceUpdated:
        g_catalog = DictionaryService::allDictionaries();
        rebuildFilterStrip();
        if (g_showingManager) {
            refreshCatalogList(true);
            ShowWindow(g_backBtn, DictionaryService::hasInstalledDictionary() ? SW_SHOW : SW_HIDE);
        } else {
            reloadSearch(false);
            updateFooter();
        }
        return 0;
    case kMsgImportDone: {
        std::wstring* msgPtr = (std::wstring*)lParam;
        if (msgPtr) {
            g_customStatusBanner = *msgPtr;
            delete msgPtr;
        }
        refreshCatalogList(true);
        if (wParam == 1)
            ShowWindow(g_backBtn, SW_SHOW);
        return 0;
    }
    case WM_SHOWWINDOW:
        if (!wParam)
            WordSpeaker::stop();    // the window is hidden by Esc, the close button or losing the focus: stop reading
        break;
    case WM_ACTIVATE:
        if (LOWORD(wParam) == WA_INACTIVE && !g_openingDialog) {
            ShowWindow(window, SW_HIDE);
        }
        return 0;
    case WM_CLOSE:
        if (!g_showingManager) {
            wchar_t cur[4] = {};
            GetWindowTextW(g_search, cur, 3);
            if (cur[0] != 0) {
                SetWindowTextW(g_search, L"");
                reloadSearch(true);
                return 0;
            }
        }
        ShowWindow(window, SW_HIDE);
        return 0;
    case WM_COMMAND: {
        int id = LOWORD(wParam);
        int code = HIWORD(wParam);
        if (id == kIdSearch && code == EN_CHANGE) {
            SetTimer(window, kTimerSearch, 30, NULL);
        } else if (id == kIdClear) {
            SetWindowTextW(g_search, L"");
            reloadSearch(true);
            SetFocus(g_search);
        } else if (id == kIdClose) {
            ShowWindow(window, SW_HIDE);
        } else if (id == kIdToggleMgr || id == kIdBackLookup) {
            setMode(!g_showingManager);
        } else if (id == kIdEmptyBtn) {
            setMode(true);
        } else if (id == kIdResults && code == LBN_SELCHANGE) {
            displayHit((int)SendMessageW(g_results, LB_GETCURSEL, 0, 0));
        } else if (id == kIdCopyDef) {
            copyDefinitionToClipboard();
        } else if (id == kIdSpeak) {
            speakCurrentWord();
        } else if (id >= kIdFilterFirst && id < kIdFilterFirst + (int)g_filterIds.size()) {
            g_selectedFilterId = g_filterIds[(size_t)(id - kIdFilterFirst)];
            rebuildFilterStrip();
            reloadSearch(true);
        } else if (id == kIdDownloadSelected) {
            std::vector<std::string> ids;
            for (size_t i = 0; i < g_catalog.size(); ++i) {
                if (!g_catalog[i].installed && !g_catalog[i].downloading && g_checkedIds.count(g_catalog[i].dictId))
                    ids.push_back(g_catalog[i].dictId);
            }
            if (!ids.empty())
                DictionaryService::downloadDictionaries(ids);
        } else if (id == kIdImportLocal) {
            runImportFileDialog();
        } else if (id == kIdCatalogList) {
            if (code == LBN_SELCHANGE) {
                updateCatalogActionButtons();
            } else if (code == LBN_DBLCLK) {
                int sel = (int)SendMessageW(g_catalogList, LB_GETCURSEL, 0, 0);
                if (sel >= 0 && (size_t)sel < g_catalog.size()) {
                    const DictionaryService::CatalogStatusItem& item = g_catalog[(size_t)sel];
                    if (item.installed) {
                        DictionaryService::setDictionaryEnabled(item.dictId, !item.enabled);
                    } else if (!item.downloading) {
                        if (g_checkedIds.count(item.dictId)) g_checkedIds.erase(item.dictId);
                        else g_checkedIds.insert(item.dictId);
                        InvalidateRect(g_catalogList, NULL, FALSE);
                        updateCatalogActionButtons();
                    }
                }
            }
        } else if (id == kIdRowDownload) {
            int sel = (int)SendMessageW(g_catalogList, LB_GETCURSEL, 0, 0);
            if (sel >= 0 && (size_t)sel < g_catalog.size()) {
                const DictionaryService::CatalogStatusItem& item = g_catalog[(size_t)sel];
                if (item.downloading) DictionaryService::cancelDownload(item.dictId);
                else if (!item.installed) DictionaryService::downloadDictionaries(std::vector<std::string>(1, item.dictId));
            }
        } else if (id == kIdRowToggle) {
            int sel = (int)SendMessageW(g_catalogList, LB_GETCURSEL, 0, 0);
            if (sel >= 0 && (size_t)sel < g_catalog.size() && g_catalog[(size_t)sel].installed)
                DictionaryService::setDictionaryEnabled(g_catalog[(size_t)sel].dictId, !g_catalog[(size_t)sel].enabled);
        } else if (id == kIdRowRemove) {
            int sel = (int)SendMessageW(g_catalogList, LB_GETCURSEL, 0, 0);
            if (sel >= 0 && (size_t)sel < g_catalog.size() && g_catalog[(size_t)sel].installed)
                DictionaryService::removeDictionary(g_catalog[(size_t)sel].dictId);
        }
        return 0;
    }
    }
    return DefWindowProcW(window, msg, wParam, lParam);
}

void ensureCreated() {
    if (g_window) return;
    DictionaryService::start();
    g_dpi = FeatureTheme::dpi();
    recreateResources();

    WNDCLASSEXW wc = {sizeof(wc)};
    wc.lpfnWndProc = windowProc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = kClassName;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassExW(&wc);

    int w = px(kWidthAt96);
    int h = px(kHeightAt96);
    g_window = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kClassName, L"Từ điển VOpenKey AI",
                               WS_POPUP, 0, 0, w, h, NULL, NULL, GetModuleHandleW(NULL), NULL);
    if (!g_window) return;
    FeatureWindows::registerDialog(g_window);
    DictionaryService::registerNotifyWindow(g_window, kMsgServiceUpdated);

    // Header
    g_search = makeCtrl(L"EDIT", L"", WS_TABSTOP | ES_AUTOHSCROLL | WS_BORDER, px(14), px(12), px(500), px(28), kIdSearch);
    g_origSearchProc = (WNDPROC)SetWindowLongPtrW(g_search, GWLP_WNDPROC, (LONG_PTR)searchSubclassProc);
    g_clearBtn = makeCtrl(L"BUTTON", L"Xóa", BS_PUSHBUTTON | WS_TABSTOP, px(520), px(12), px(50), px(28), kIdClear);
    g_mgrBtn = makeCtrl(L"BUTTON", L"Bộ từ điển", BS_PUSHBUTTON | WS_TABSTOP, px(576), px(12), px(116), px(28), kIdToggleMgr);
    g_closeBtn = makeCtrl(L"BUTTON", L"Đóng", BS_PUSHBUTTON | WS_TABSTOP, px(698), px(12), px(48), px(28), kIdClose);

    // Lookup pane
    int bodyTop = px(80);
    int bodyH = h - bodyTop - px(34);
    int leftW = px(kLeftColAt96);
    g_results = makeCtrl(L"LISTBOX", L"", LBS_OWNERDRAWFIXED | LBS_NOTIFY | LBS_NOINTEGRALHEIGHT | WS_VSCROLL | WS_BORDER | WS_TABSTOP,
                         px(12), bodyTop, leftW, bodyH, kIdResults);
    int rx = leftW + px(22);
    int rw = w - rx - px(12);
    g_defHeader = makeCtrl(L"STATIC", L"", SS_LEFT | SS_NOPREFIX, rx, bodyTop + px(4), rw - px(136) - px(92), px(20), 0);
    g_copyDefBtn = makeCtrl(L"BUTTON", L"Sao chép nghĩa", BS_PUSHBUTTON | WS_TABSTOP, rx + rw - px(130), bodyTop, px(130), px(24), kIdCopyDef);
    // shown only for an English word (see updateSpeaker), left of the copy button
    g_speakBtn = makeCtrl(L"BUTTON", L"Phát âm", BS_PUSHBUTTON | WS_TABSTOP, rx + rw - px(130) - px(6) - px(84), bodyTop, px(84), px(24), kIdSpeak);
    ShowWindow(g_speakBtn, SW_HIDE);
    g_emptyBtn = makeCtrl(L"BUTTON", L"Mở Bộ từ điển", BS_PUSHBUTTON | WS_TABSTOP, rx + px(120), bodyTop + px(140), px(150), px(30), kIdEmptyBtn);

    if (!g_richEditDll)
        g_richEditDll = LoadLibraryW(L"msftedit.dll");
    const wchar_t* defCls = g_richEditDll ? MSFTEDIT_CLASS : L"EDIT";
    DWORD defStyle = ES_MULTILINE | ES_READONLY | WS_VSCROLL | WS_BORDER | WS_TABSTOP;
    g_defView = CreateWindowExW(0, defCls, L"", WS_CHILD | WS_VISIBLE | defStyle,
                                rx, bodyTop + px(30), rw, bodyH - px(30),
                                g_window, (HMENU)(INT_PTR)kIdDefView, GetModuleHandleW(NULL), NULL);
    g_useRichEdit = (g_richEditDll != NULL && g_defView != NULL);
    if (!g_defView) {
        g_useRichEdit = false;
        g_defView = makeCtrl(L"EDIT", L"", defStyle, rx, bodyTop + px(30), rw, bodyH - px(30), kIdDefView);
    } else if (!g_useRichEdit) {
        SendMessageW(g_defView, WM_SETFONT, (WPARAM)g_font, TRUE);
    }

    // Manager pane
    int mTop = px(50);
    g_mgrBanner = makeCtrl(L"STATIC", L"Chọn từ điển mở (ưu tiên Anh-Việt, Việt-Anh) hoặc nhập file StarDict:",
                           SS_LEFT, px(14), mTop + px(4), px(390), px(24), 0);
    g_backBtn = makeCtrl(L"BUTTON", L"Quay lại", BS_PUSHBUTTON | WS_TABSTOP, px(410), mTop, px(90), px(28), kIdBackLookup);
    g_importBtn = makeCtrl(L"BUTTON", L"Thêm từ máy...", BS_PUSHBUTTON | WS_TABSTOP, px(506), mTop, px(112), px(28), kIdImportLocal);
    g_downloadSelBtn = makeCtrl(L"BUTTON", L"Tải đã chọn", BS_PUSHBUTTON | WS_TABSTOP, px(624), mTop, px(122), px(28), kIdDownloadSelected);

    g_catalogList = makeCtrl(L"LISTBOX", L"", LBS_OWNERDRAWFIXED | LBS_NOTIFY | LBS_NOINTEGRALHEIGHT | WS_VSCROLL | WS_BORDER | WS_TABSTOP,
                             px(12), mTop + px(36), w - px(24), h - (mTop + px(36)) - px(68), kIdCatalogList);
    int ay = h - px(62);
    g_rowDlBtn = makeCtrl(L"BUTTON", L"Tải bộ này", BS_PUSHBUTTON | WS_TABSTOP, px(14), ay, px(110), px(24), kIdRowDownload);
    g_rowToggleBtn = makeCtrl(L"BUTTON", L"Bật / Tắt", BS_PUSHBUTTON | WS_TABSTOP, px(130), ay, px(90), px(24), kIdRowToggle);
    g_rowRemoveBtn = makeCtrl(L"BUTTON", L"Xóa", BS_PUSHBUTTON | WS_TABSTOP, px(226), ay, px(70), px(24), kIdRowRemove);

    // Footer
    g_footerLeft = makeCtrl(L"STATIC", L"", SS_LEFT | SS_NOPREFIX, px(14), h - px(26), px(420), px(18), 0);
    SendMessageW(g_footerLeft, WM_SETFONT, (WPARAM)g_smallFont, TRUE);
    g_footerRight = makeCtrl(L"STATIC", L"", SS_RIGHT | SS_NOPREFIX, px(440), h - px(26), w - px(454), px(18), 0);
    SendMessageW(g_footerRight, WM_SETFONT, (WPARAM)g_smallFont, TRUE);
}

void positionAndPresent() {
    POINT cur = {0, 0};
    GetCursorPos(&cur);
    HMONITOR mon = MonitorFromPoint(cur, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi = {sizeof(mi)};
    GetMonitorInfoW(mon, &mi);
    int w = px(kWidthAt96);
    int h = px(kHeightAt96);
    int x = mi.rcWork.left + ((mi.rcWork.right - mi.rcWork.left) - w) / 2;
    int y = mi.rcWork.top + ((mi.rcWork.bottom - mi.rcWork.top) - h) / 2;
    SetWindowPos(g_window, HWND_TOPMOST, x, y, w, h, SWP_SHOWWINDOW);
    SetForegroundWindow(g_window);
}

} // namespace

namespace DictionaryPalette {

void showWithText(const std::u16string& text) {
    ensureCreated();
    if (!g_window) return;
    g_customStatusBanner.clear();
    g_catalog = DictionaryService::allDictionaries();
    seedDefaultsIfNeeded();

    std::string utf8 = vcase::toUtf8(text);
    std::wstring wquery = DictionaryService::utf8ToWide(utf8);
    // Single-line trimmed head
    size_t nl = wquery.find_first_of(L"\r\n");
    if (nl != std::wstring::npos) wquery.resize(nl);
    while (!wquery.empty() && wquery.front() <= L' ') wquery.erase(wquery.begin());
    while (!wquery.empty() && wquery.back() <= L' ') wquery.pop_back();
    if (wquery.size() > 80) wquery.resize(80);

    if (!wquery.empty()) {
        SetWindowTextW(g_search, wquery.c_str());
        g_showingManager = false;
    } else {
        g_showingManager = !DictionaryService::hasInstalledDictionary();
    }
    syncModeVisibility();
    positionAndPresent();
    if (!g_showingManager) {
        SetFocus(g_search);
        SendMessageW(g_search, EM_SETSEL, 0, -1);
    }
}

void show() {
    std::wstring selected;
    if (DictionaryService::hasInstalledDictionary())
        TextInserter::copySelection(selected);
    std::u16string u16(selected.begin(), selected.end());
    showWithText(u16);
}

void showManager() {
    ensureCreated();
    if (!g_window) return;
    g_customStatusBanner.clear();
    g_showingManager = true;
    syncModeVisibility();
    positionAndPresent();
}

void toggle() {
    if (isVisible()) hide();
    else show();
}

void hide() {
    if (g_window) ShowWindow(g_window, SW_HIDE);
}

bool isVisible() {
    return g_window != NULL && IsWindowVisible(g_window) != FALSE;
}

} // namespace DictionaryPalette
