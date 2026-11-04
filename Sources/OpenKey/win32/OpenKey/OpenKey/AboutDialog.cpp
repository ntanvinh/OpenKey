/*----------------------------------------------------------
OpenKey - The Cross platform Open source Vietnamese Keyboard application.

Copyright (C) 2019 Mai Vu Tuyen
Contact: maivutuyen.91@gmail.com
Github: https://github.com/tuyenvm/OpenKey
Fanpage: https://www.facebook.com/OpenKeyVN

This file is belong to the OpenKey project, Win32 version
which is released under GPL license.
You can fork, modify, improve this program. If you
redistribute your new version, it MUST be open source.
-----------------------------------------------------------*/
#include "stdafx.h"
#include "AboutDialog.h"
#include "AppDelegate.h"
#include <commctrl.h>

//Who made this version, as in the About window of macOS (OpenKey.rc is left alone: Visual Studio rewrites it, these two lines are
//made here in code, in the free space under the version, on the same grid as the lines of the links)
static const int kIdCompanySite = 2101;
static const int kIdCompanyEmail = 2102;

static void addCompanyLine(HWND dialog, int topUnits, const wchar_t* label, const wchar_t* link, int linkId) {
	HFONT font = (HFONT)SendMessage(dialog, WM_GETFONT, 0, 0);
	RECT labelBox = {45, topUnits, 45 + 58, topUnits + 8};
	RECT linkBox = {105, topUnits, 105 + 175, topUnits + 8};
	MapDialogRect(dialog, &labelBox);
	MapDialogRect(dialog, &linkBox);
	HWND text = CreateWindowExW(0, L"STATIC", label, WS_CHILD | WS_VISIBLE, labelBox.left, labelBox.top, labelBox.right - labelBox.left,
		labelBox.bottom - labelBox.top, dialog, NULL, GetModuleHandle(NULL), NULL);
	HWND url = CreateWindowExW(0, L"SysLink", link, WS_CHILD | WS_VISIBLE | WS_TABSTOP, linkBox.left, linkBox.top,
		linkBox.right - linkBox.left, linkBox.bottom - linkBox.top, dialog, (HMENU)(INT_PTR)linkId, GetModuleHandle(NULL), NULL);
	if (text) SendMessage(text, WM_SETFONT, (WPARAM)font, TRUE);
	if (url) SendMessage(url, WM_SETFONT, (WPARAM)font, TRUE);
}

AboutDialog::AboutDialog(const HINSTANCE & hInstance, const int & resourceId)
	: BaseDialog(hInstance, resourceId) {
}

AboutDialog::~AboutDialog() {
}

void AboutDialog::fillData() {
}

INT_PTR AboutDialog::eventProc(HWND hDlg, UINT uMsg, WPARAM wParam, LPARAM lParam) {
	switch (uMsg) {
	case WM_INITDIALOG:
		this->hDlg = hDlg;
		initDialog();
		return TRUE;
	case WM_COMMAND: {
		int wmId = LOWORD(wParam);
		switch (wmId) {
		case IDM_EXIT:
		case IDBUTTON_OK:
			AppDelegate::getInstance()->closeDialog(this);
			break;
		case IDC_BUTTON_CHECK_VERSION:
			onUpdateButton();
			break;
		}
		break;
	}
	case WM_NOTIFY:
		switch (((LPNMHDR)lParam)->code) {
		case NM_CLICK:
		case NM_RETURN: {
			PNMLINK link = (PNMLINK)lParam;
			if (link->hdr.idFrom == IDC_SYSLINK_HOME_PAGE)
				ShellExecute(NULL, _T("open"), _T("https://github.com/ntanvinh/OpenKey"), NULL, NULL, SW_SHOWNORMAL);
			else if (link->hdr.idFrom == IDC_SYSLINK_NEW_VERSION)
				ShellExecute(NULL, _T("open"), _T("https://github.com/ntanvinh/OpenKey/releases"), NULL, NULL, SW_SHOWNORMAL);
			else if (link->hdr.idFrom == IDC_SYSLINK_FANPAGE)
				ShellExecute(NULL, _T("open"), _T("https://www.facebook.com/OpenKeyVN"), NULL, NULL, SW_SHOWNORMAL);
			else if (link->hdr.idFrom == kIdCompanySite || link->hdr.idFrom == kIdCompanyEmail)
				ShellExecuteW(NULL, L"open", link->item.szUrl, NULL, NULL, SW_SHOWNORMAL);
		}
		break;
		}
	}
	return FALSE;
}

void AboutDialog::initDialog() {
	//dialog icon
	SET_DIALOG_ICON(IDI_APP_ICON);
	
	hUpdateButton = GetDlgItem(hDlg, IDC_BUTTON_CHECK_VERSION);

	addCompanyLine(hDlg, 62, L"Phát triển bởi:", L"<a href=\"https://lssoft.io.vn\">LSSoft - lssoft.io.vn</a>", kIdCompanySite);
	addCompanyLine(hDlg, 71, L"Liên hệ:", L"<a href=\"mailto:lssoft.adm@gmail.com\">lssoft.adm@gmail.com</a>", kIdCompanyEmail);

	HFONT hFont = CreateFont(48, 0, 0, 0, FW_THIN, FALSE, FALSE, FALSE,
		ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, 
		DEFAULT_PITCH | FF_SWISS | FF_MODERN, _T("Segoe UI"));
	SendDlgItemMessage(hDlg, IDC_STATIC_APP_TITLE, WM_SETFONT, WPARAM(hFont), TRUE);

	wchar_t buffer[256];
	wsprintfW(buffer, _T("Phiên bản %s cho Windows - Ngày cập nhật: %s"), OpenKeyHelper::getVersionString().c_str(), _T(__DATE__));
	SendDlgItemMessage(hDlg, IDC_STATIC_APP_VERSION, WM_SETTEXT, 0, LPARAM(buffer));

	hFont = CreateFont(20, 0, 0, 0, FW_DONTCARE, FALSE, FALSE, FALSE,
		ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
		DEFAULT_PITCH | FF_SWISS | FF_MODERN, _T("Arial"));
	SendDlgItemMessage(hDlg, IDC_STATIC_APP_SUB_TITLE, WM_SETFONT, WPARAM(hFont), TRUE);
}

void AboutDialog::onUpdateButton() {
	EnableWindow(hUpdateButton, false);
	string newVersion;
	bool answered = false;
	if (OpenKeyManager::checkUpdate(newVersion, &answered)) {
		AppDelegate::getInstance()->offerUpdate(hDlg, newVersion);
	} else if (!answered) {
		MessageBox(hDlg, _T("Không kiểm tra được phiên bản mới. Hãy kiểm tra kết nối mạng rồi thử lại."), _T("VOpenKey AI Update"), MB_ICONWARNING | MB_OK);
	} else {
		MessageBox(hDlg, _T("Bạn đang dùng phiên bản mới nhất!"), _T("VOpenKey AI Update"), MB_OK);
	}
	EnableWindow(hUpdateButton, true);
}