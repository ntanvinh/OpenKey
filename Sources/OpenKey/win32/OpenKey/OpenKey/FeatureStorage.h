//
//  FeatureStorage.h
//  VOpenKey AI, Windows
//
//  Where the features keep their files, and the few file and resource helpers they share.
//  Everything is UTF-8 std::string at this boundary, like the portable engine.
//
#pragma once
#include "stdafx.h"
#include "FeatureIds.h"

namespace FeatureStorage {

/// %APPDATA%\VOpenKey, created when it is missing (the same folder name as on macOS: the user's data stays where it is).
std::wstring dataFolder();
/// A folder inside dataFolder(), created when it is missing.
std::wstring subFolder(const wchar_t* name);

/// The whole file, empty when it cannot be read.
std::string readFile(const std::wstring& path);
/// Replaces the file in one step (written to a temporary file first). %APPDATA% belongs to this user, so the file does too.
bool writeFile(const std::wstring& path, const std::string& content);

/// Small settings in the registry, in the same place as the other settings of OpenKey (HKCU\SOFTWARE\TuyenMai\OpenKey).
/// Text is UTF-8 here and REG_SZ in the registry. A value that is missing gives `fallback`.
std::string getSettingText(const wchar_t* name, const std::string& fallback = std::string());
void setSettingText(const wchar_t* name, const std::string& value);
std::vector<unsigned char> getSettingBytes(const wchar_t* name);
void setSettingBytes(const wchar_t* name, const std::vector<unsigned char>& bytes);
void deleteSetting(const wchar_t* name);

/// The bytes of an RCDATA resource of the program (see Features.rc).
std::string resourceText(int id);

} // namespace FeatureStorage
