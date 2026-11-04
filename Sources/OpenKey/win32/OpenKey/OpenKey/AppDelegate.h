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
#pragma once
#include "stdafx.h"
#include "MainControlDialog.h"
#include "AboutDialog.h"
#include "ConvertToolDialog.h"
#include "MacroDialog.h"

class BaseDialog;
class AppDelegate {
private:
	HINSTANCE hInstance;
	BaseDialog* mainDialog = NULL, *aboutDialog = NULL, *macroDialog = NULL, *convertDialog = NULL;
private:
	bool isDialogMsg(MSG &msg) const;
	void startUpdateChecks();
public:
	/// Posted by the thread that looks for a new version to the window of the tray: lParam is a `new string` with the version
	/// (the window deletes it).
	static const UINT kMessageUpdateFound = WM_APP + 70;

	AppDelegate();
	static AppDelegate* getInstance();
	int run(HINSTANCE hInstance);
	void createMainDialog();
	void closeDialog(BaseDialog* dialog);
public: //event
	void onInputMethodChangedFromHotKey();
	void onDefaultConfig();

	void onToggleVietnamese();
	void onToggleCheckSpelling();
	void onToggleUseSmartSwitchKey();
	void onToggleUseMacro();

	void onMacroTable();
	void onConvertTool();
	void onQuickConvert();

	void onInputType(const int& type);
	void onTableCode(const int& code);

	void onControlPanel();
	void onOpenKeyAbout();
	void onOpenKeyExit();

	/// Asks whether to update to `newVersion` and, when the answer is yes, starts the updater and closes this program. `parent`
	/// is the window the question belongs to (NULL: it comes up by itself).
	void offerUpdate(HWND parent, const string& newVersion);
	void onUpdateFound(const string& newVersion);
};