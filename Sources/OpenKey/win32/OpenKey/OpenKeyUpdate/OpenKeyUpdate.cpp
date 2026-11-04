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

#include "framework.h"
#include "OpenKeyUpdate.h"
#include <Urlmon.h>
#include <wincrypt.h>
#include <shellapi.h>
#include <fstream>
#include <sstream>
#include <string>
#pragma comment(lib, "Urlmon.lib")
#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Shell32.lib")

using namespace std;

//The SHA-256 of a file as 64 lower case hex digits; empty when it cannot be worked out (Windows CryptoAPI, no extra library).
static string Sha256OfFile(const WCHAR* path) {
	string result;
	HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (file == INVALID_HANDLE_VALUE)
		return result;
	HCRYPTPROV provider = 0;
	HCRYPTHASH hash = 0;
	if (CryptAcquireContextW(&provider, NULL, NULL, PROV_RSA_AES, CRYPT_VERIFYCONTEXT) && CryptCreateHash(provider, CALG_SHA_256, 0, 0, &hash)) {
		static BYTE buffer[64 * 1024];
		bool complete = false, failed = false;
		while (!complete && !failed) {
			DWORD read = 0;
			if (!ReadFile(file, buffer, sizeof(buffer), &read, NULL))
				failed = true;
			else if (read == 0)
				complete = true;
			else if (!CryptHashData(hash, buffer, read, 0))
				failed = true;
		}
		BYTE digest[32];
		DWORD size = sizeof(digest);
		if (complete && CryptGetHashParam(hash, HP_HASHVAL, digest, &size, 0) && size == sizeof(digest)) {
			static const char hex[] = "0123456789abcdef";
			for (DWORD i = 0; i < size; i++) {
				result += hex[digest[i] >> 4];
				result += hex[digest[i] & 15];
			}
		}
	}
	if (hash) CryptDestroyHash(hash);
	if (provider) CryptReleaseContext(provider, 0);
	CloseHandle(file);
	return result;
}

//The first word of a small text file, in lower case ("<sha256>  <name of the file>" is what the release carries), empty when there is none
static string FirstWordOfFile(const WCHAR* path) {
	string word;
	HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (file == INVALID_HANDLE_VALUE)
		return word;
	char buffer[512];
	DWORD read = 0;
	if (ReadFile(file, buffer, sizeof(buffer), &read, NULL)) {
		DWORD i = 0;
		if (read >= 3 && (unsigned char)buffer[0] == 0xEF && (unsigned char)buffer[1] == 0xBB && (unsigned char)buffer[2] == 0xBF)
			i = 3; //a byte order mark
		for (; i < read && (buffer[i] == ' ' || buffer[i] == '\t' || buffer[i] == '\r' || buffer[i] == '\n'); i++) {}
		for (; i < read && buffer[i] != ' ' && buffer[i] != '\t' && buffer[i] != '\r' && buffer[i] != '\n'; i++)
			word += (char)((buffer[i] >= 'A' && buffer[i] <= 'Z') ? buffer[i] - 'A' + 'a' : buffer[i]);
	}
	CloseHandle(file);
	return word;
}

INT_PTR CALLBACK MainDialogProcess(HWND, UINT, WPARAM, LPARAM);
void StartUpdate();
HWND hDlg;
int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
                     _In_opt_ HINSTANCE hPrevInstance,
                     _In_ LPWSTR    lpCmdLine,
                     _In_ int       nCmdShow)
{
    UNREFERENCED_PARAMETER(hPrevInstance);
    UNREFERENCED_PARAMETER(lpCmdLine);

	hDlg = CreateDialogParam(hInstance, MAKEINTRESOURCE(IDD_DIALOG_UPDATER), 0, MainDialogProcess, 0);
	ShowWindow(hDlg, SW_SHOWNORMAL);
 
	MSG msg;
	// Main message loop:
	while (GetMessage(&msg, nullptr, 0, 0)) {
		if (!IsDialogMessage(hDlg, &msg)) {
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
	}
	return 0;
}

// Message handler for about box.
INT_PTR CALLBACK MainDialogProcess(HWND hDlg, UINT message, WPARAM wParam, LPARAM lParam)
{
    UNREFERENCED_PARAMETER(lParam);
	switch (message) {
	case WM_INITDIALOG:{
		HICON hIcon = LoadIcon(GetModuleHandle(NULL), MAKEINTRESOURCE(IDI_OPENKEYUPDATE));
		if (hIcon) {
			SendMessage(hDlg, WM_SETICON, ICON_BIG, (LPARAM)hIcon);
		}
		StartUpdate();
		return (INT_PTR)TRUE;
	}
    case WM_COMMAND:
        if (LOWORD(wParam) == IDOK || LOWORD(wParam) == IDCANCEL)
        {
            EndDialog(hDlg, LOWORD(wParam));
            return (INT_PTR)TRUE;
        }
        break;
    }
    return (INT_PTR)FALSE;
}

DWORD WINAPI UpdateThreadFunction(LPVOID lpParam) {
	WCHAR path[MAX_PATH];
	WCHAR currentDir[MAX_PATH];
	GetCurrentDirectory(MAX_PATH, currentDir);
	wsprintf(path, TEXT("%s\\_OpenKey.tempf"), currentDir);
	HRESULT res = URLDownloadToFile(NULL, L"https://raw.githubusercontent.com/ntanvinh/OpenKey/master/version.json", path, 0, NULL);

	wstring data;
	if (res == S_OK) {
		std::wifstream t(path);
		std::wstringstream buffer;
		buffer << t.rdbuf();
		t.close();
		DeleteFile(path);
		data = buffer.str();
	} else {
		MessageBox(hDlg, _T("Có lỗi trong quá trình cập nhật, vui lòng thử lại sau!"), _T("VOpenKey AI Update"), MB_OK);
		ExitProcess(0);
		return 0;
	}

	//simple parse
	data = data.substr(data.find(L"latestWinVersion"));
	data = data.substr(data.find(L"\"versionName\":"));
	data = data.substr(14);
	data = data.substr(data.find(L"\""));
	data = data.substr(1);
	wstring versionName = data.substr(0, data.find(L"\""));
	
	//download zip file
	WCHAR updateUrl[MAX_PATH];
	wsprintf(updateUrl, TEXT("https://github.com/ntanvinh/OpenKey/releases/download/v%s/VOpenKey-%s-Windows.zip"),
		versionName.c_str(),
		versionName.c_str());
	wsprintf(path, TEXT("%s\\_OpenKeyUpdate.zip"), currentDir);
	res = URLDownloadToFile(NULL, updateUrl, path, 0, NULL);

	if (res == S_OK) {
		//the zip has to be the file that was published: the release carries its SHA-256 beside it. A file that is cut, damaged or not
		//the one the release has is never opened.
		bool genuine = false, hashKnown = false;
		{
			WCHAR hashUrl[MAX_PATH], hashPath[MAX_PATH];
			wsprintf(hashUrl, TEXT("%s.sha256"), updateUrl);
			wsprintf(hashPath, TEXT("%s\\_OpenKeyUpdate.zip.sha256"), currentDir);
			if (URLDownloadToFile(NULL, hashUrl, hashPath, 0, NULL) == S_OK) {
				string expected = FirstWordOfFile(hashPath);
				hashKnown = expected.size() == 64;
				string actual = Sha256OfFile(path);
				genuine = hashKnown && expected == actual;
			}
			DeleteFile(hashPath);
		}
		if (!genuine) {
			DeleteFile(path);
			if (!hashKnown)
				MessageBox(hDlg, _T("Không lấy được mã kiểm tra (SHA-256) của bản cập nhật trên GitHub, nên không cài. Chương trình cũ vẫn như trước, hãy thử lại sau!"), _T("VOpenKey AI Update"), MB_OK);
			else
				MessageBox(hDlg, _T("Tệp tải về không khớp mã kiểm tra (SHA-256) mà GitHub công bố, nên không được cài. Chương trình cũ vẫn như trước, hãy thử lại sau!"), _T("VOpenKey AI Update"), MB_OK);
			ExitProcess(0);
			return 0;
		}

		//the program of this folder is the 64 bit one, the 32 bit one (a 32 bit Windows) or both: each gets its new file
		bool has64 = GetFileAttributes(L"OpenKey64.exe") != INVALID_FILE_ATTRIBUTES;
		bool has32 = GetFileAttributes(L"OpenKey32.exe") != INVALID_FILE_ATTRIBUTES;
		if (!has64 && !has32)
			has64 = true;

		//1. extract, and wait until it is finished: nothing of the program is touched before the new files are known to be there
		STARTUPINFO startup = { sizeof(startup) };
		PROCESS_INFORMATION process = { 0 };
		WCHAR command[] = L"powershell.exe -NoP -NonI -Command \"Expand-Archive -Force '.\\_OpenKeyUpdate.zip' '.\\_OpenKeyUpdate'\"";
		bool extracted = false;
		if (CreateProcess(NULL, command, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &startup, &process)) {
			DWORD waited = WaitForSingleObject(process.hProcess, 180000);
			DWORD exitCode = 1;
			GetExitCodeProcess(process.hProcess, &exitCode);
			CloseHandle(process.hThread);
			CloseHandle(process.hProcess);
			extracted = waited == WAIT_OBJECT_0 && exitCode == 0;
		}
		bool complete = extracted &&
			(!has64 || GetFileAttributes(L"_OpenKeyUpdate\\OpenKey64.exe") != INVALID_FILE_ATTRIBUTES) &&
			(!has32 || GetFileAttributes(L"_OpenKeyUpdate\\OpenKey32.exe") != INVALID_FILE_ATTRIBUTES);

		//2. replace: the old file is put aside first and comes back if the new one cannot take its place
		bool replaced = complete;
		const WCHAR* names[2] = { L"OpenKey64.exe", L"OpenKey32.exe" };
		bool wanted[2] = { has64, has32 };
		for (int k = 0; k < 2 && replaced; k++) {
			if (!wanted[k])
				continue;
			WCHAR aside[MAX_PATH], fresh[MAX_PATH];
			wsprintf(aside, TEXT("%s.old"), names[k]);
			wsprintf(fresh, TEXT("_OpenKeyUpdate\\%s"), names[k]);
			DeleteFile(aside);
			if (!MoveFile(names[k], aside)) {
				replaced = false;
			} else if (!MoveFile(fresh, names[k])) {
				MoveFile(aside, names[k]);
				replaced = false;
			}
		}
		if (replaced) {
			DeleteFile(L"OpenKey64.exe.old");
			DeleteFile(L"OpenKey32.exe.old");
		}

		//3. clean up
		DeleteFile(path);
		DeleteFile(L"_OpenKeyUpdate\\OpenKeyUpdate.exe");
		DeleteFile(L"_OpenKeyUpdate\\OpenKey64.exe");
		DeleteFile(L"_OpenKeyUpdate\\OpenKey32.exe");
		DeleteFile(L"_OpenKeyUpdate\\LICENSE");
		RemoveDirectory(L".\\_OpenKeyUpdate");
		if (replaced) {
			MessageBox(hDlg, _T("Bạn đã cập nhật VOpenKey AI bản mới nhất thành công!"), _T("VOpenKey AI Update"), MB_OK);
			//the program was closed to be updated: it comes back, as the macOS one does
			ShellExecuteW(NULL, L"open", has64 ? L"OpenKey64.exe" : L"OpenKey32.exe", NULL, currentDir, SW_SHOWNORMAL);
		} else {
			MessageBox(hDlg, _T("Không cập nhật được: tệp tải về không đủ hoặc không thay được chương trình cũ. Chương trình cũ vẫn như trước, hãy thử lại sau!"), _T("VOpenKey AI Update"), MB_OK);
		}
		ExitProcess(0);
	} else {
		MessageBox(hDlg, _T("Có lỗi trong quá trình cập nhật, vui lòng thử lại sau!"), _T("VOpenKey AI Update"), MB_OK);
		ExitProcess(0);
	}
	return 0;
}

void StartUpdate() {
	DWORD hThread;
	HANDLE t = CreateThread(
							NULL,                   // default security attributes
							0,                      // use default stack size  
							UpdateThreadFunction,       // thread function name
							0,          // argument to thread function 
							0,                      // use default creation flags 
							&hThread);   // returns the thread identifier 
}