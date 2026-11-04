//
//  PictureFile.h
//  VOpenKey AI, Windows
//
//  The picture that Codex made for the AI assistant: read from its file, drawn in the window, put on the clipboard, saved in Downloads,
//  shown in Explorer. Decoding is done by Windows itself (the Windows Imaging Component), so a PNG, a JPEG or a GIF that Codex writes
//  all read; a picture with transparent parts is laid on white (the clipboard and the window have no alpha to show it with). Nothing here
//  runs a program or opens anything from the picture: only its pixels are read.
//
#pragma once
#include "stdafx.h"

namespace PictureFile {

struct Picture {
    int width;
    int height;
    std::vector<BYTE> dib;     //a device independent bitmap as the clipboard takes it (CF_DIB): the header, then the 24 bit pixels, bottom row first
    std::vector<BYTE> png;     //the file as it is when it is a PNG (the "PNG" clipboard format keeps what a DIB would lose); empty for the others
    std::wstring path;         //the file it was read from
    Picture() : width(0), height(0) {}
    bool empty() const { return dib.empty(); }
};

/// Reads the picture of a file. False when it cannot be read (not a picture, too big, no decoder). `png` is kept only for a PNG up to 30 MB.
bool load(const std::wstring& path, Picture& out);

/// Draws the picture as large as fits in `area`, with its proportions, centred; the rest of `area` is `background`.
void draw(HDC dc, const RECT& area, const Picture& picture, COLORREF background);

/// Puts the picture on the clipboard (a bitmap, and a PNG when there is one), as the user's copy: it stays there. False when the clipboard
/// could not be opened (another program holds it).
bool copyToClipboard(HWND owner, const Picture& picture);

/// The folder of downloads of the user ("Downloads").
std::wstring downloadsFolder();

/// Copies the file of the picture to `folder` under a name of its own ("VOpenKey AI 20261104-101500.png") that never replaces a file.
/// Returns the path of the copy, empty when it did not work.
std::wstring saveCopy(const std::wstring& source, const std::wstring& folder);

/// Opens Explorer on the folder of the file with the file chosen.
void showInExplorer(const std::wstring& path);

/// Opens the file with the program the user has for it (to see the picture large).
void openWithDefaultProgram(const std::wstring& path);

} // namespace PictureFile
