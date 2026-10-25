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
#include "AppDelegate.h"
#include <algorithm>
#include "SuggestionController.h"
#include "SuggestionKeys.h"
#include "FeatureActions.h"
#include "ShortcutField.h"
#include "CaseBar.h"

#pragma comment(lib, "imm32")
#define IMC_GETOPENSTATUS 0x0005

#define MASK_SHIFT				0x01
#define MASK_CONTROL			0x02
#define MASK_ALT				0x04
#define MASK_CAPITAL			0x08
#define MASK_NUMLOCK			0x10
#define MASK_WIN				0x20
#define MASK_SCROLL				0x40

#define OTHER_CONTROL_KEY (_flag & MASK_ALT) || (_flag & MASK_CONTROL)
#define DYNA_DATA(macro, pos) (macro ? pData->macroData[pos] : pData->charData[pos])
#define EMPTY_HOTKEY 0xFE0000FE

static vector<string> _chromiumBrowser = {
	"chrome.exe", "brave.exe", "msedge.exe"
};

extern int vSendKeyStepByStep;
extern int vUseGrayIcon;
extern int vShowOnStartUp;
extern int vRunWithWindows;

static HHOOK hKeyboardHook;
static HHOOK hMouseHook;
static HWINEVENTHOOK hSystemEvent;
static KBDLLHOOKSTRUCT* keyboardData;
static MSLLHOOKSTRUCT* mouseData;
static vKeyHookState* pData;
static vector<Uint16> _syncKey;
static Uint32 _flag = 0, _lastFlag = 0, _privateFlag;
static bool _flagChanged = false, _isFlagKey;
static Uint16 _keycode;
static Uint16 _newChar, _newCharHi;

static vector<Uint16> _newCharString;
static Uint16 _newCharSize;
static bool _willSendControlKey = false;

static Uint16 _uniChar[2];
static int _i, _j, _k;
static Uint32 _tempChar;

static string macroText, macroContent;
static int _languageTemp = 0; //use for smart switch key
static vector<Byte> savedSmartSwitchKeyData; ////use for smart switch key

static bool _hasJustUsedHotKey = false;
static DWORD _swallowedKey = 0; //a key that chose a suggestion: its repeats and its key up are not for the application

static INPUT backspaceEvent[2];
static INPUT keyEvent[2];

static bool restoreTypingWord();
LRESULT CALLBACK keyboardHookProcess(int nCode, WPARAM wParam, LPARAM lParam);
LRESULT CALLBACK mouseHookProcess(int nCode, WPARAM wParam, LPARAM lParam);
VOID CALLBACK winEventProcCallback(HWINEVENTHOOK hWinEventHook, DWORD dwEvent, HWND hwnd, LONG idObject, LONG idChild, DWORD dwEventThread, DWORD dwmsEventTime);

void OpenKeyFree() {
	SuggestionController::stop();
	FeatureActions::stop();
	UnhookWindowsHookEx(hMouseHook);
	UnhookWindowsHookEx(hKeyboardHook);
	UnhookWinEvent(hSystemEvent);
}

void OpenKeyInit() {
	APP_GET_DATA(vLanguage, 1);
	APP_GET_DATA(vInputType, 0);
	vFreeMark = 0;
	APP_GET_DATA(vCodeTable, 0);
	APP_GET_DATA(vCheckSpelling, 1);
	APP_GET_DATA(vUseModernOrthography, 0);
	APP_GET_DATA(vQuickTelex, 0);
	APP_GET_DATA(vSwitchKeyStatus, 0x7A000206);
	APP_GET_DATA(vRestoreIfWrongSpelling, 1);
	APP_GET_DATA(vFixRecommendBrowser, 1);
	APP_GET_DATA(vUseMacro, 1);
	APP_GET_DATA(vUseMacroInEnglishMode, 0);
	APP_GET_DATA(vAutoCapsMacro, 0);
	APP_GET_DATA(vSendKeyStepByStep, 1);
	APP_GET_DATA(vUseGrayIcon, 0);
	APP_GET_DATA(vShowOnStartUp, 1);
	APP_GET_DATA(vRunWithWindows, 1);
	OpenKeyHelper::registerRunOnStartup(vRunWithWindows);
	APP_GET_DATA(vUseSmartSwitchKey, 1);
	APP_GET_DATA(vUpperCaseFirstChar, 0);
	APP_GET_DATA(vAllowConsonantZFWJ, 0);
	APP_GET_DATA(vTempOffSpelling, 0);
	APP_GET_DATA(vQuickStartConsonant, 0);
	APP_GET_DATA(vQuickEndConsonant, 0);
	APP_GET_DATA(vSupportMetroApp, 0);
	APP_GET_DATA(vRunAsAdmin, 0);
	APP_GET_DATA(vCreateDesktopShortcut, 0);
	APP_GET_DATA(vCheckNewVersion, 0);
	APP_GET_DATA(vRememberCode, 1);
	APP_GET_DATA(vOtherLanguage, 1);
	APP_GET_DATA(vTempOffOpenKey, 0);
	APP_GET_DATA(vFixChromiumBrowser, 0);

	//init convert tool
	APP_GET_DATA(convertToolDontAlertWhenCompleted, 0);
	APP_GET_DATA(convertToolToAllCaps, 0);
	APP_GET_DATA(convertToolToAllNonCaps, 0);
	APP_GET_DATA(convertToolToCapsFirstLetter, 0);
	APP_GET_DATA(convertToolToCapsEachWord, 0);
	APP_GET_DATA(convertToolRemoveMark, 0);
	APP_GET_DATA(convertToolFromCode, 0);
	APP_GET_DATA(convertToolToCode, 0);
	APP_GET_DATA(convertToolHotKey, EMPTY_HOTKEY);
	if (convertToolHotKey == 0) {
		convertToolHotKey = EMPTY_HOTKEY;
	}

	pData = (vKeyHookState*)vKeyInit();

	//pre-create back key
	backspaceEvent[0].type = INPUT_KEYBOARD;
	backspaceEvent[0].ki.dwFlags = 0;
	backspaceEvent[0].ki.wVk = VK_BACK;
	backspaceEvent[0].ki.wScan = 0;
	backspaceEvent[0].ki.time = 0;
	backspaceEvent[0].ki.dwExtraInfo = 1;

	backspaceEvent[1].type = INPUT_KEYBOARD;
	backspaceEvent[1].ki.dwFlags = KEYEVENTF_KEYUP;
	backspaceEvent[1].ki.wVk = VK_BACK;
	backspaceEvent[1].ki.wScan = 0;
	backspaceEvent[1].ki.time = 0;
	backspaceEvent[1].ki.dwExtraInfo = 1;

	//get key state
	_flag = 0;
	if (GetKeyState(VK_LSHIFT) < 0 || GetKeyState(VK_RSHIFT) < 0) _flag |= MASK_SHIFT;
	if (GetKeyState(VK_LCONTROL) < 0 || GetKeyState(VK_RCONTROL) < 0) _flag |= MASK_CONTROL;
	if (GetKeyState(VK_LMENU) < 0 || GetKeyState(VK_RMENU) < 0) _flag |= MASK_ALT;
	if (GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0) _flag |= MASK_WIN;
	if (GetKeyState(VK_NUMLOCK) < 0) _flag |= MASK_NUMLOCK;
	if (GetKeyState(VK_CAPITAL) == 1) _flag |= MASK_CAPITAL;
	if (GetKeyState(VK_SCROLL) < 0) _flag |= MASK_SCROLL;

	//init and load macro data
	DWORD macroDataSize;
	BYTE* macroData = OpenKeyHelper::getRegBinary(_T("macroData"), macroDataSize);
	initMacroMap((Byte*)macroData, (int)macroDataSize);

	//init and load smart switch key data
	DWORD smartSwitchKeySize;
	BYTE* data = OpenKeyHelper::getRegBinary(_T("smartSwitchKey"), smartSwitchKeySize);
	initSmartSwitchKey((Byte*)data, (int)smartSwitchKeySize);

	//init hook
	HINSTANCE hInstance = GetModuleHandle(NULL);

	//before the hooks: loading the dictionaries takes a moment, and a keyboard hook that is installed but not answering costs the user keys
	//suggestion bar, snippets and the other features of VOpenKey AI
	FeatureActions::loadSettings();
	FeatureActions::setRestoreHandler(restoreTypingWord);
	FeatureActions::start(hInstance);
	SuggestionController::start(hInstance);

	hKeyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, keyboardHookProcess, hInstance, 0);
	hMouseHook = SetWindowsHookEx(WH_MOUSE_LL, mouseHookProcess, hInstance, 0);
	hSystemEvent = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, NULL, winEventProcCallback, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
}

void saveSmartSwitchKeyData() {
	getSmartSwitchKeySaveData(savedSmartSwitchKeyData);
	OpenKeyHelper::setRegBinary(_T("smartSwitchKey"), savedSmartSwitchKeyData.data(), (int)savedSmartSwitchKeyData.size());
}

static void InsertKeyLength(const Uint8& len) {
	_syncKey.push_back(len);
}

static inline void prepareKeyEvent(INPUT& input, const Uint16& keycode, const bool& isPress, const DWORD& flag=0) {
	input.type = INPUT_KEYBOARD;
	input.ki.dwFlags = isPress ? flag : flag|KEYEVENTF_KEYUP;
	input.ki.wVk = keycode;
	input.ki.wScan = 0;
	input.ki.time = 0;
	input.ki.dwExtraInfo = 1;
}

static inline void prepareUnicodeEvent(INPUT& input, const Uint16& unicode, const bool& isPress) {
	input.type = INPUT_KEYBOARD;
	input.ki.wVk = 0;
	input.ki.wScan = unicode;
	input.ki.time = 0;
	input.ki.dwFlags = (isPress ? 0 : KEYEVENTF_KEYUP) | KEYEVENTF_UNICODE;
	input.ki.dwExtraInfo = 1;
}

static void SendCombineKey(const Uint16& key1, const Uint16& key2, const DWORD& flagKey1=0, const DWORD& flagKey2 = 0) {
	prepareKeyEvent(keyEvent[0], key1, true, flagKey1);
	SendInput(1, keyEvent, sizeof(INPUT));

	prepareKeyEvent(keyEvent[0], key2, true, flagKey2);
	prepareKeyEvent(keyEvent[1], key2, false, flagKey2);
	SendInput(2, keyEvent, sizeof(INPUT));

	prepareKeyEvent(keyEvent[0], key1, false, flagKey1);
	SendInput(1, keyEvent, sizeof(INPUT));
}

static void SendKeyCode(Uint32 data) {
	_newChar = (Uint16)data;
	if (!(data & CHAR_CODE_MASK)) {
		if (IS_DOUBLE_CODE(vCodeTable)) //VNI
			InsertKeyLength(1);

		_newChar = keyCodeToCharacter(data);
		if (_newChar == 0) {
			_newChar = (Uint16)data;
			prepareKeyEvent(keyEvent[0], _newChar, true);
			prepareKeyEvent(keyEvent[1], _newChar, false);
			SendInput(2, keyEvent, sizeof(INPUT));
		} else {
			prepareUnicodeEvent(keyEvent[0], _newChar, true);
			prepareUnicodeEvent(keyEvent[1], _newChar, false);
			SendInput(2, keyEvent, sizeof(INPUT));
		}
	} else {
		if (vCodeTable == 0) { //unicode 2 bytes code
			prepareUnicodeEvent(keyEvent[0], _newChar, true);
			prepareUnicodeEvent(keyEvent[1], _newChar, false);
			SendInput(2, keyEvent, sizeof(INPUT));
		} else if (vCodeTable == 1 || vCodeTable == 2 || vCodeTable == 4) { //others such as VNI Windows, TCVN3: 1 byte code
			_newCharHi = HIBYTE(_newChar);
			_newChar = LOBYTE(_newChar);

			prepareUnicodeEvent(keyEvent[0], _newChar, true);
			prepareUnicodeEvent(keyEvent[1], _newChar, false);
			SendInput(2, keyEvent, sizeof(INPUT));

			if (_newCharHi > 32) {
				if (vCodeTable == 2) //VNI
					InsertKeyLength(2);
				prepareUnicodeEvent(keyEvent[0], _newCharHi, true);
				prepareUnicodeEvent(keyEvent[1], _newCharHi, false);
				SendInput(2, keyEvent, sizeof(INPUT));
			} else {
				if (vCodeTable == 2) //VNI
					InsertKeyLength(1);
			}
		} else if (vCodeTable == 3) { //Unicode Compound
			_newCharHi = (_newChar >> 13);
			_newChar &= 0x1FFF;
			_uniChar[0] = _newChar;
			_uniChar[1] = _newCharHi > 0 ? (_unicodeCompoundMark[_newCharHi - 1]) : 0;
			InsertKeyLength(_newCharHi > 0 ? 2 : 1);
			prepareUnicodeEvent(keyEvent[0], _uniChar[0], true);
			prepareUnicodeEvent(keyEvent[1], _uniChar[0], false);
			SendInput(2, keyEvent, sizeof(INPUT));
			if (_newCharHi > 0) {
				prepareUnicodeEvent(keyEvent[0], _uniChar[1], true);
				prepareUnicodeEvent(keyEvent[1], _uniChar[1], false);
				SendInput(2, keyEvent, sizeof(INPUT));
			}
		}
	}
}

static void SendBackspace() {
	SendInput(2, backspaceEvent, sizeof(INPUT));
	if (vSupportMetroApp && OpenKeyHelper::getLastAppExecuteName().compare("ApplicationFrameHost.exe") == 0) {//Metro App
		SendMessage(HWND_BROADCAST, WM_CHAR, VK_BACK, 0L);
		SendMessage(HWND_BROADCAST, WM_CHAR, VK_BACK, 0L);
	}
	if (IS_DOUBLE_CODE(vCodeTable)) { //VNI or Unicode Compound
		if (_syncKey.back() > 1) {
			/*if (!(vCodeTable == 3 && containUnicodeCompoundApp(FRONT_APP))) {
				SendInput(2, backspaceEvent, sizeof(INPUT));
			}*/
			SendInput(2, backspaceEvent, sizeof(INPUT));
			if (vSupportMetroApp && OpenKeyHelper::getLastAppExecuteName().compare("ApplicationFrameHost.exe") == 0) {//Metro App
				SendMessage(HWND_BROADCAST, WM_CHAR, VK_BACK, 0L);
				SendMessage(HWND_BROADCAST, WM_CHAR, VK_BACK, 0L);
			}
		}
		_syncKey.pop_back();
	}
}

static void SendEmptyCharacter() {
	if (IS_DOUBLE_CODE(vCodeTable)) //VNI or Unicode Compound
		InsertKeyLength(1);

	_newChar = 0x202F; //empty char

	prepareUnicodeEvent(keyEvent[0], _newChar, true);
	prepareUnicodeEvent(keyEvent[1], _newChar, false);
	SendInput(2, keyEvent, sizeof(INPUT));
}

static void SendNewCharString(const bool& dataFromMacro = false) {
	_j = 0;
	_newCharSize = dataFromMacro ? (Uint16)pData->macroData.size() : pData->newCharCount;
	if (_newCharString.size() < _newCharSize) {
		_newCharString.resize(_newCharSize);
	}
	_willSendControlKey = false;
	
	if (_newCharSize > 0) {
		for (_k = dataFromMacro ? 0 : pData->newCharCount - 1;
			dataFromMacro ? _k < pData->macroData.size() : _k >= 0;
			dataFromMacro ? _k++ : _k--) {

			_tempChar = DYNA_DATA(dataFromMacro, _k);
			if (_tempChar & PURE_CHARACTER_MASK) {
				_newCharString[_j++] = _tempChar;
				if (IS_DOUBLE_CODE(vCodeTable)) {
					InsertKeyLength(1);
				}
			} else if (!(_tempChar & CHAR_CODE_MASK)) {
				if (IS_DOUBLE_CODE(vCodeTable)) //VNI
					InsertKeyLength(1);
				_newCharString[_j++] = keyCodeToCharacter(_tempChar);
			} else {
				_newChar = _tempChar;
				if (vCodeTable == 0) {  //unicode 2 bytes code
					_newCharString[_j++] = _newChar;
				} else if (vCodeTable == 1 || vCodeTable == 2 || vCodeTable == 4) { //others such as VNI Windows, TCVN3: 1 byte code
					_newCharHi = HIBYTE(_newChar);
					_newChar = LOBYTE(_newChar);
					_newCharString[_j++] = _newChar;

					if (_newCharHi > 32) {
						if (vCodeTable == 2) //VNI
							InsertKeyLength(2);
						_newCharString[_j++] = _newCharHi;
						_newCharSize++;
					}
					else {
						if (vCodeTable == 2) //VNI
							InsertKeyLength(1);
					}
				} else if (vCodeTable == 3) { //Unicode Compound
					_newCharHi = (_newChar >> 13);
					_newChar &= 0x1FFF;

					InsertKeyLength(_newCharHi > 0 ? 2 : 1);
					_newCharString[_j++] = _newChar;
					if (_newCharHi > 0) {
						_newCharSize++;
						_newCharString[_j++] = _unicodeCompoundMark[_newCharHi - 1];
					}

				}
			}
		}//end for
	}

	if (pData->code == vRestore || pData->code == vRestoreAndStartNewSession) { //if is restore
		if (keyCodeToCharacter(_keycode) != 0) {
			_newCharSize++;
			_newCharString[_j++] = keyCodeToCharacter(_keycode | ((_flag & MASK_SHIFT) || (_flag & MASK_CAPITAL) ? CAPS_MASK : 0));
		} else {
			_willSendControlKey = true;
		}
	}
	if (pData->code == vRestoreAndStartNewSession) {
		startNewSession();
	}

	OpenKeyHelper::setClipboardText((LPCTSTR)_newCharString.data(), _newCharSize + 1, CF_UNICODETEXT);

	//Send shift + insert
	SendCombineKey(KEY_LEFT_SHIFT, VK_INSERT, 0, KEYEVENTF_EXTENDEDKEY);
	
	//the case when hCode is vRestore or vRestoreAndStartNewSession,
	//the word is invalid and last key is control key such as TAB, LEFT ARROW, RIGHT ARROW,...
	if (_willSendControlKey) {
		SendKeyCode(_keycode);
	}
}

bool checkHotKey(int hotKeyData, bool checkKeyCode = true) {
	if ((hotKeyData & (~0x8000)) == EMPTY_HOTKEY)
		return false;
	if (HAS_CONTROL(hotKeyData) ^ GET_BOOL(_lastFlag & MASK_CONTROL))
		return false;
	if (HAS_OPTION(hotKeyData) ^ GET_BOOL(_lastFlag & MASK_ALT))
		return false;
	if (HAS_COMMAND(hotKeyData) ^ GET_BOOL(_lastFlag & MASK_WIN))
		return false;
	if (HAS_SHIFT(hotKeyData) ^ GET_BOOL(_lastFlag & MASK_SHIFT))
		return false;
	if (checkKeyCode) {
		if (GET_SWITCH_KEY(hotKeyData) != _keycode)
			return false;
	}
	return true;
}

void switchLanguage() {
	if (vLanguage == 0)
		vLanguage = 1;
	else
		vLanguage = 0;
	if (HAS_BEEP(vSwitchKeyStatus))
		MessageBeep(MB_OK);
	AppDelegate::getInstance()->onInputMethodChangedFromHotKey();
	if (vUseSmartSwitchKey) {
		setAppInputMethodStatus(OpenKeyHelper::getFrontMostAppExecuteName(), vLanguage | (vCodeTable << 1));
		saveSmartSwitchKeyData();
	}
	startNewSession();
	SuggestionController::reset();
}

static void SendPureCharacter(const Uint16& ch) {
	if (ch < 128)
		SendKeyCode(ch);
	else {
		prepareUnicodeEvent(keyEvent[0], ch, true);
		prepareUnicodeEvent(keyEvent[1], ch, false);
		SendInput(2, keyEvent, sizeof(INPUT));
		if (IS_DOUBLE_CODE(vCodeTable)) {
			InsertKeyLength(1);
		}
	}
}

static void handleMacro() {
	//fix autocomplete
	if (vFixRecommendBrowser) {
		SendEmptyCharacter();
		pData->backspaceCount++;
	}

	//send backspace
	if (pData->backspaceCount > 0) {
		for (int i = 0; i < pData->backspaceCount; i++) {
			SendBackspace();
		}
	}
	//send real data
	if (!vSendKeyStepByStep) {
		SendNewCharString(true);
	} else {
		for (int i = 0; i < pData->macroData.size(); i++) {
			if (pData->macroData[i] & PURE_CHARACTER_MASK) {
				SendPureCharacter(pData->macroData[i]);
			} else {
				SendKeyCode(pData->macroData[i]);
			}
		}
	}
	SendKeyCode(_keycode | (_flag & MASK_SHIFT ? CAPS_MASK : 0));
}

//The address bar of a browser, or a cell of Excel, may have added a proposal after what was typed: the first backspace would
//remove that instead of a letter. `count` is the number of characters about to be deleted, it is changed to what must be sent.
template <typename Count>
static void fixRecommendation(Count& count) {
	if (vFixChromiumBrowser &&
		std::find(_chromiumBrowser.begin(), _chromiumBrowser.end(), OpenKeyHelper::getLastAppExecuteName()) != _chromiumBrowser.end()) {
		SendCombineKey(KEY_LEFT_SHIFT, KEY_LEFT, 0, KEYEVENTF_EXTENDEDKEY);
		if (count == 1)
			count--;
	} else {
		SendEmptyCharacter();
		count++;
	}
}

//The word being typed, as the typing engine has it, UTF-8 (empty if none). Only meaningful with the Unicode table.
static string currentTypingWord() {
	Uint16 buffer[MAX_BUFF];
	int length = vGetTypingWord(buffer, MAX_BUFF);
	return length > 0 ? wideStringToUtf8(wstring((const wchar_t*)buffer, length)) : string();
}

//The keys pressed for the word being typed, before Telex/VNI changed them
static string currentRawTypingWord() {
	Uint16 buffer[MAX_BUFF];
	int length = vGetTypingRawWord(buffer, MAX_BUFF);
	return length > 0 ? wideStringToUtf8(wstring((const wchar_t*)buffer, length)) : string();
}

//The full text of the abbreviation being typed, when the user has to confirm it (empty when it is none, or replaced at once)
static string currentMacroOffer() {
	if (!vMacroNeedsConfirm || !vUseMacro)
		return string();
	static Uint16 buffer[65536]; //a macro is at most 65535 bytes long
	int length = vPeekMacro(buffer, 65536);
	return length > 0 ? wideStringToUtf8(wstring((const wchar_t*)buffer, length)) : string();
}

//A shortcut like Alt+2 or Ctrl+Alt+R has its keys still down while the program types the result of it. Backspace sent then
//would be Alt+Backspace (undo) or Ctrl+Backspace (delete a word). So the modifiers the user holds are let go first, and put
//back afterwards, so that the user can go on holding them.
struct HeldModifiers {
	WORD keys[8];
	int count;
};

static bool isExtendedModifier(WORD key) {
	return key == VK_RCONTROL || key == VK_RMENU || key == VK_LWIN || key == VK_RWIN;
}

static HeldModifiers releaseHeldModifiers() {
	static const WORD all[] = { VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN };
	HeldModifiers held;
	held.count = 0;
	for (int i = 0; i < 8; i++) {
		if (!(GetAsyncKeyState(all[i]) & 0x8000))
			continue;
		INPUT up;
		prepareKeyEvent(up, all[i], false, isExtendedModifier(all[i]) ? KEYEVENTF_EXTENDEDKEY : 0);
		SendInput(1, &up, sizeof(INPUT));
		held.keys[held.count++] = all[i];
	}
	return held;
}

static void restoreHeldModifiers(const HeldModifiers& held) {
	bool needsMask = false;
	for (int i = 0; i < held.count; i++) {
		INPUT down;
		prepareKeyEvent(down, held.keys[i], true, isExtendedModifier(held.keys[i]) ? KEYEVENTF_EXTENDEDKEY : 0);
		SendInput(1, &down, sizeof(INPUT));
		if (held.keys[i] == VK_LMENU || held.keys[i] == VK_RMENU || held.keys[i] == VK_LWIN || held.keys[i] == VK_RWIN)
			needsMask = true;
	}
	if (needsMask) {
		//Alt or Windows let go on their own would open the menu of the program or the Start menu: a key that means nothing
		//in between prevents that
		INPUT mask[2];
		prepareKeyEvent(mask[0], 0xE8, true);
		prepareKeyEvent(mask[1], 0xE8, false);
		SendInput(2, mask, sizeof(INPUT));
	}
}

//Replaces the word that was typed with the chosen suggestion
static void sendSuggestionText(const wstring& text, size_t eraseCount) {
	//the same preparation as for a word the engine replaces
	if (eraseCount > 0 && vFixRecommendBrowser)
		fixRecommendation(eraseCount);
	for (size_t i = 0; i < eraseCount; i++) {
		SendInput(2, backspaceEvent, sizeof(INPUT));
	}
	//the text goes in as Unicode characters, a few at a time
	vector<INPUT> events;
	events.reserve(text.size() * 2);
	for (size_t i = 0; i < text.size(); i++) {
		INPUT down, up;
		prepareUnicodeEvent(down, text[i], true);
		prepareUnicodeEvent(up, text[i], false);
		events.push_back(down);
		events.push_back(up);
	}
	for (size_t start = 0; start < events.size(); start += 32) {
		UINT count = (UINT)min((size_t)32, events.size() - start);
		SendInput(count, &events[start], sizeof(INPUT));
	}
}

static bool SetModifierMask(const Uint16& vkCode) {
	// For caps lock case, toggling the flag isn't enough. We need to check the actual state, which should be done before each key press.
	// Example: the caps lock state can be changed without the key being pressed, or the key toggle is made with admin privilege, making the app not able to detect the change.
	if (GetKeyState(VK_CAPITAL) == 1) _flag |= MASK_CAPITAL;
	else _flag &= ~MASK_CAPITAL;

	if (vkCode == VK_LSHIFT || vkCode == VK_RSHIFT) _flag |= MASK_SHIFT;
	else if (vkCode == VK_LCONTROL || vkCode == VK_RCONTROL) _flag |= MASK_CONTROL;
	else if (vkCode == VK_LMENU || vkCode == VK_RMENU) _flag |= MASK_ALT;
	else if (vkCode == VK_LWIN || vkCode == VK_RWIN) _flag |= MASK_WIN;
	else if (vkCode == VK_NUMLOCK) _flag |= MASK_NUMLOCK;
	else if (vkCode == VK_SCROLL) _flag |= MASK_SCROLL;
	else { 
		_isFlagKey = false;
		return false; 
	}
	_isFlagKey = true;
	return true;
}

static bool UnsetModifierMask(const Uint16& vkCode) {
	if (vkCode == VK_LSHIFT || vkCode == VK_RSHIFT) _flag &= ~MASK_SHIFT;
	else if (vkCode == VK_LCONTROL || vkCode == VK_RCONTROL) _flag &= ~MASK_CONTROL;
	else if (vkCode == VK_LMENU || vkCode == VK_RMENU) _flag &= ~MASK_ALT;
	else if (vkCode == VK_LWIN || vkCode == VK_RWIN) _flag &= ~MASK_WIN;
	else if (vkCode == VK_NUMLOCK) _flag &= ~MASK_NUMLOCK;
	else if (vkCode == VK_SCROLL) _flag &= ~MASK_SCROLL;
	else { 
		_isFlagKey = false;
		return false; 
	}
	_isFlagKey = true;
	return true;
}

//Types what the engine has worked out for the key: delete the characters of the word, then type the new ones
static void sendEngineResult() {
	//fix autocomplete
	if (vFixRecommendBrowser && pData->extCode != 4) {
		fixRecommendation(pData->backspaceCount);
	}
	
	//send backspace
	if (pData->backspaceCount > 0 && pData->backspaceCount < MAX_BUFF) {
		for (_i = 0; _i < pData->backspaceCount; _i++) {
			SendBackspace();
		}
	}

	//send new character
	if (!vSendKeyStepByStep) {
		SendNewCharString();
	} else {
		if (pData->newCharCount > 0 && pData->newCharCount <= MAX_BUFF) {
			for (int i = pData->newCharCount - 1; i >= 0; i--) {
				SendKeyCode(pData->charData[i]);
			}
		}
		if (pData->code == vRestore || pData->code == vRestoreAndStartNewSession) {
			SendKeyCode(_keycode | ((_flag & MASK_CAPITAL) || (_flag & MASK_SHIFT) ? CAPS_MASK : 0));
		}
		if (pData->code == vRestoreAndStartNewSession) {
			startNewSession();
		}
	}
}

//The restore shortcut: gives back the keys typed for the word on screen ("r\u00e9t\u1ecfe" -> "restore"). False when there is
//nothing to give back, then the key is left for the program.
static bool restoreTypingWord() {
	if (!vRestoreWord())
		return false;
	HeldModifiers held = releaseHeldModifiers();
	sendEngineResult();
	restoreHeldModifiers(held);
	SuggestionController::reset(); //the word is no longer what the suggestion bar was looking at
	return true;
}

//A shortcut of the features was pressed: true when it did something (then the key is not for the program). The restore needs
//the state of this file, the other ones are done from the message loop.
static bool runFeatureHotKey(const FeatureActions::HotKey& key) {
	if (key.action == FeatureActions::RestoreWord)
		return vLanguage != 0 && restoreTypingWord(); //nothing to give back: the key goes to the program
	return FeatureActions::post(key.action);
}

//Our own windows (snippets, settings...) have the keyboard: what is typed there is not text to suggest words for
static bool ownWindowHasKeyboard() {
	DWORD process = 0;
	GetWindowThreadProcessId(GetForegroundWindow(), &process);
	return process == GetCurrentProcessId();
}

LRESULT CALLBACK keyboardHookProcess(int nCode, WPARAM wParam, LPARAM lParam) {
	keyboardData = (KBDLLHOOKSTRUCT *)lParam;
	//ignore my event
	if (keyboardData->dwExtraInfo != 0) {
		return CallNextHookEx(hKeyboardHook, nCode, wParam, lParam);
	}
	
	//a key that was used for a shortcut, a suggestion or the case list: the repeats of it and its key up are not for the program
	//either. It is looked at before anything that can return early, or the key up could be missed and the next press eaten.
	if (_swallowedKey != 0 && keyboardData->vkCode == _swallowedKey) {
		if (wParam == WM_KEYUP || wParam == WM_SYSKEYUP)
			_swallowedKey = 0;
		return -1;
	}

	//ignore if IME pad is open when typing Japanese/Chinese...
	HWND hWnd = GetForegroundWindow();
	HWND hIME = ImmGetDefaultIMEWnd(hWnd);
	LRESULT isImeON = SendMessage(hIME, WM_IME_CONTROL, IMC_GETOPENSTATUS, 0);
	if (isImeON) {
		return CallNextHookEx(hKeyboardHook, nCode, wParam, lParam);
	}
	
	//check modifier key
	if (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) {
		//LOG(L"Key down: %d\n", keyboardData->vkCode);
		SetModifierMask((Uint16)keyboardData->vkCode);
	} else if (wParam == WM_KEYUP || wParam == WM_SYSKEYUP) {
		//LOG(L"Key up: %d\n", keyboardData->vkCode);
		UnsetModifierMask((Uint16)keyboardData->vkCode);
	}
	if (!_isFlagKey && wParam != WM_KEYUP && wParam != WM_SYSKEYUP)
		_keycode = (Uint16)keyboardData->vkCode;

	//a field of the settings waits for the user to press a shortcut: the keys are for it (the modifiers were followed above)
	if (ShortcutField::isRecording()) {
		return CallNextHookEx(hKeyboardHook, nCode, wParam, lParam);
	}

	//the list that changes the case of the selection uses some keys (arrows, Enter, Esc, Alt+digits)
	if ((wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) && !_isFlagKey && CaseBar::isVisible() &&
		GET_SWITCH_KEY(vCaseBarHotKey) != _keycode) {
		if (CaseBar::keyDown(_keycode, (_flag & MASK_ALT) != 0, (_flag & MASK_CONTROL) != 0, (_flag & MASK_SHIFT) != 0, (_flag & MASK_WIN) != 0)) {
			_swallowedKey = _keycode; //its key up and repeats too
			return -1;
		}
	}

	//switch language shortcut; convert hotkey; the shortcuts of the features
	if ((wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) && !_isFlagKey && _keycode != 0) {
		const vector<FeatureActions::HotKey>& featureKeys = FeatureActions::hotKeys();
		bool isFeatureKey = false;
		for (size_t i = 0; i < featureKeys.size(); i++) {
			if ((!featureKeys[i].enabled || *featureKeys[i].enabled) && GET_SWITCH_KEY(*featureKeys[i].shortcut) == _keycode)
				isFeatureKey = true;
		}
		if (GET_SWITCH_KEY(vSwitchKeyStatus) != _keycode && GET_SWITCH_KEY(convertToolHotKey) != _keycode && !isFeatureKey) {
			_lastFlag = 0;
		} else {
			for (size_t i = 0; i < featureKeys.size(); i++) {
				const FeatureActions::HotKey& key = featureKeys[i];
				if (key.enabled && !*key.enabled)
					continue;
				if (GET_SWITCH_KEY(*key.shortcut) != _keycode || !checkHotKey(*key.shortcut))
					continue;
				if (runFeatureHotKey(key)) {
					_hasJustUsedHotKey = true;
					_swallowedKey = _keycode;
					_keycode = 0;
					return -1;
				}
			}
			if (GET_SWITCH_KEY(vSwitchKeyStatus) == _keycode && checkHotKey(vSwitchKeyStatus, GET_SWITCH_KEY(vSwitchKeyStatus) != 0xFE)) {
				switchLanguage();
				_hasJustUsedHotKey = true;
				_keycode = 0;
				return -1;
			}
			if (GET_SWITCH_KEY(convertToolHotKey) == _keycode && checkHotKey(convertToolHotKey, GET_SWITCH_KEY(convertToolHotKey) != 0xFE)) {
				AppDelegate::getInstance()->onQuickConvert();
				_hasJustUsedHotKey = true;
				_keycode = 0;
				return -1;
			}
		}
		_hasJustUsedHotKey = _lastFlag != 0;
	} else if (_isFlagKey) {
		if (_lastFlag == 0 || _lastFlag < _flag)
			_lastFlag = _flag;
		else if (_lastFlag > _flag) {
			//check switch
			if (checkHotKey(vSwitchKeyStatus, GET_SWITCH_KEY(vSwitchKeyStatus) != 0xFE)) {
				switchLanguage();
				_hasJustUsedHotKey = true;
			}
			if (checkHotKey(convertToolHotKey, GET_SWITCH_KEY(convertToolHotKey) != 0xFE)) {
				AppDelegate::getInstance()->onQuickConvert();
				_hasJustUsedHotKey = true;
			}
			//check temporarily turn off spell checking
			if (vTempOffSpelling && !_hasJustUsedHotKey && _lastFlag & MASK_CONTROL) {
				vTempOffSpellChecking();
			}
			if (vTempOffOpenKey && !_hasJustUsedHotKey && _lastFlag & MASK_ALT) {
				vTempOffEngine();
			}
			_lastFlag = _flag;
			_hasJustUsedHotKey = false;
		}
		_keycode = 0;
		return CallNextHookEx(hKeyboardHook, nCode, wParam, lParam);
	}

	//if is in english mode
	if (vLanguage == 0) {
		if (SuggestionController::isShowing())
			SuggestionController::reset();
		if (vUseMacro && vUseMacroInEnglishMode && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) {
			vEnglishMode(((wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) ? vKeyEventState::KeyDown : vKeyEventState::MouseDown),
				_keycode,
				(_flag & MASK_SHIFT) || (_flag & MASK_CAPITAL),
				OTHER_CONTROL_KEY);

			if (pData->code == vReplaceMaro) { //handle macro in english mode
				handleMacro();
				return NULL;
			}
		}
		return CallNextHookEx(hKeyboardHook, nCode, wParam, lParam);
	}

	//handle keyboard
	if (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) {
		//Tab or Alt+1-5 chooses a suggestion from the bar; Esc puts it away (and goes on to the application)
		bool suggesting = !ownWindowHasKeyboard();
		if (suggesting && SuggestionController::isShowing()) {
			if (_keycode == vsuggestkeys::kEscape) {
				SuggestionController::reset();
			} else {
				vsuggestkeys::Modifiers modifiers = {(_flag & MASK_SHIFT) != 0, (_flag & MASK_CONTROL) != 0,
													 (_flag & MASK_ALT) != 0, (_flag & MASK_WIN) != 0};
				int slot = vsuggestkeys::slotForKey(_keycode, modifiers, vSuggestTabAccepts != 0);
				wstring suggestion;
				size_t eraseCount = 0;
				if (slot >= 0 && SuggestionController::accept(slot, currentTypingWord(), suggestion, eraseCount)) {
					HeldModifiers held = releaseHeldModifiers();
					sendSuggestionText(suggestion, eraseCount);
					restoreHeldModifiers(held);
					startNewSession(); //the word on screen is no longer what the typing engine has
					_syncKey.clear();
					_swallowedKey = _keycode;
					return -1;
				}
			}
		}

		//send event signal to Engine
		vKeyHandleEvent(vKeyEvent::Keyboard,
						vKeyEventState::KeyDown,
						_keycode,
						(_flag & MASK_SHIFT && _flag & MASK_CAPITAL) ? 0 : (_flag & MASK_SHIFT ? 1 : (_flag & MASK_CAPITAL ? 2 : 0)),
						OTHER_CONTROL_KEY);
		{
			vsuggest::KeyKind kind = vsuggest::KeyKind::Other;
			if (_keycode == KEY_SPACE && !(OTHER_CONTROL_KEY) && pData->code == vDoNothing)
				kind = vsuggest::KeyKind::Space;
			else if (_keycode == KEY_DELETE)
				kind = vsuggest::KeyKind::Delete;
			if (suggesting && SuggestionController::isActive())
				SuggestionController::keyProcessed(kind, currentTypingWord(), currentRawTypingWord(), currentMacroOffer());
		}
		if (pData->code == vDoNothing) { //do nothing
			if (IS_DOUBLE_CODE(vCodeTable)) { //VNI
				if (pData->extCode == 1) { //break key
					_syncKey.clear();
				} else if (pData->extCode == 2) { //delete key
					if (_syncKey.size() > 0) {
						if (_syncKey.back() > 1 && (vCodeTable == 2 || vCodeTable == 3)) {
							//send one more backspace
							SendInput(2, backspaceEvent, sizeof(INPUT));
						}
						_syncKey.pop_back();
					}
				} else if (pData->extCode == 3) { //normal key
					InsertKeyLength(1);
				}
			}
			return CallNextHookEx(hKeyboardHook, nCode, wParam, lParam);
		} else if (pData->code == vWillProcess || pData->code == vRestore || pData->code == vRestoreAndStartNewSession) { //handle result signal
			sendEngineResult();
		} else if (pData->code == vReplaceMaro) { //MACRO
			handleMacro();
		}
		return -1; //consume event
	}
	return CallNextHookEx(hKeyboardHook, nCode, wParam, lParam);
}

LRESULT CALLBACK mouseHookProcess(int nCode, WPARAM wParam, LPARAM lParam) {
	mouseData = (MSLLHOOKSTRUCT *)lParam;
	switch (wParam) {
	case WM_LBUTTONDOWN:
	
	case WM_RBUTTONDOWN:
	case WM_MBUTTONDOWN:
	case WM_XBUTTONDOWN:
	case WM_NCXBUTTONDOWN:
	case WM_LBUTTONUP:
	case WM_RBUTTONUP:
	case WM_MBUTTONUP:
	case WM_XBUTTONUP:
	case WM_NCXBUTTONUP:
		//send event signal to Engine
		vKeyHandleEvent(vKeyEvent::Mouse, vKeyEventState::MouseDown, 0);
		SuggestionController::reset();
		if (wParam != WM_LBUTTONUP && wParam != WM_RBUTTONUP && wParam != WM_MBUTTONUP && wParam != WM_XBUTTONUP && wParam != WM_NCXBUTTONUP)
			CaseBar::mouseDown(mouseData->pt);
		if (IS_DOUBLE_CODE(vCodeTable)) { //VNI
			_syncKey.clear();
		}
		break;
	}
	return CallNextHookEx(hMouseHook, nCode, wParam, lParam);
}

VOID CALLBACK winEventProcCallback(HWINEVENTHOOK hWinEventHook, DWORD dwEvent, HWND hwnd, LONG idObject, LONG idChild, DWORD dwEventThread, DWORD dwmsEventTime) {
	//the suggestion bar: another program, another word
	SuggestionController::applicationActivated(string(OpenKeyHelper::getFrontMostAppExecuteName()));
	CaseBar::hide();

	//smart switch key
	if (vUseSmartSwitchKey || vRememberCode) {
		string& exe = OpenKeyHelper::getFrontMostAppExecuteName();
		if (exe.compare("explorer.exe") == 0) //dont apply with windows explorer
			return;
		_languageTemp = getAppInputMethodStatus(exe, vLanguage | (vCodeTable << 1));
		vTempOffEngine(false);
		if (vUseSmartSwitchKey && (_languageTemp & 0x01) != vLanguage) {
			if (_languageTemp != -1) {
				vLanguage = _languageTemp;
				AppDelegate::getInstance()->onInputMethodChangedFromHotKey();
			} else {
				saveSmartSwitchKeyData();
			}
		}
		startNewSession();
		if (vRememberCode && (_languageTemp >> 1) != vCodeTable) { //for remember table code feature
			if (_languageTemp != -1) {
				AppDelegate::getInstance()->onTableCode(_languageTemp >> 1);
			} else {
				saveSmartSwitchKeyData();
			}
		}
		if (vSupportMetroApp && exe.compare("ApplicationFrameHost.exe") == 0) {//Metro App
			SendMessage(HWND_BROADCAST, WM_CHAR, VK_BACK, 0L);
			SendMessage(HWND_BROADCAST, WM_CHAR, VK_BACK, 0L);
		}
	}
}
