//
//  PictureFile.cpp
//  VOpenKey AI, Windows
//
#include "stdafx.h"
#include "PictureFile.h"
#include <wincodec.h>
#include <shlobj.h>
#include <shellapi.h>
#include <algorithm>

#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "gdi32.lib")

namespace {

const UINT kMaxSide = 16384;                    //a picture wider than this is not one Codex makes
const unsigned long long kMaxPixels = 36ull * 1000 * 1000;   //6000 x 6000: decoded and kept twice, that is about 250 MB at the most
const DWORD kMaxPngBytes = 30u * 1000 * 1000;

template <class T> void release(T*& pointer) {
    if (pointer) {
        pointer->Release();
        pointer = NULL;
    }
}

std::wstring extensionOf(const std::wstring& path) {
    size_t slash = path.find_last_of(L"\\/");
    size_t dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash))
        return std::wstring();
    std::wstring extension = path.substr(dot);
    for (size_t i = 0; i < extension.size(); i++) {
        if (extension[i] >= L'A' && extension[i] <= L'Z')
            extension[i] = (wchar_t)(extension[i] - L'A' + L'a');
    }
    return extension;
}

bool readFile(const std::wstring& path, std::vector<BYTE>& bytes, DWORD limit) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE)
        return false;
    LARGE_INTEGER size;
    bool ok = GetFileSizeEx(file, &size) && size.QuadPart > 0 && size.QuadPart <= (LONGLONG)limit;
    if (ok) {
        bytes.resize((size_t)size.QuadPart);
        DWORD got = 0;
        ok = ReadFile(file, &bytes[0], (DWORD)bytes.size(), &got, NULL) && got == bytes.size();
    }
    CloseHandle(file);
    if (!ok)
        bytes.clear();
    return ok;
}

} // namespace

namespace PictureFile {

bool load(const std::wstring& path, Picture& out) {
    out = Picture();
    HRESULT com = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED); //S_FALSE or a different mode: COM is there already, it is used as it is
    bool ok = false;
    IWICImagingFactory* factory = NULL;
    IWICBitmapDecoder* decoder = NULL;
    IWICBitmapFrameDecode* frame = NULL;
    IWICFormatConverter* converter = NULL;
    if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory))) &&
        SUCCEEDED(factory->CreateDecoderFromFilename(path.c_str(), NULL, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder)) &&
        SUCCEEDED(decoder->GetFrame(0, &frame))) {
        UINT width = 0, height = 0;
        if (SUCCEEDED(frame->GetSize(&width, &height)) && width > 0 && height > 0 && width <= kMaxSide && height <= kMaxSide &&
            (unsigned long long)width * height <= kMaxPixels &&
            SUCCEEDED(factory->CreateFormatConverter(&converter)) &&
            SUCCEEDED(converter->Initialize(frame, GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone, NULL, 0.0, WICBitmapPaletteTypeCustom))) {
            std::vector<BYTE> source((size_t)width * height * 4);
            if (SUCCEEDED(converter->CopyPixels(NULL, width * 4, (UINT)source.size(), &source[0]))) {
                //24 bit pixels, the bottom row first, laid on white: pixels are premultiplied, so what shows is colour + (255 - alpha)
                size_t stride = ((size_t)width * 3 + 3) & ~(size_t)3;
                out.dib.assign(sizeof(BITMAPINFOHEADER) + stride * height, 0);
                BITMAPINFOHEADER* header = (BITMAPINFOHEADER*)&out.dib[0];
                header->biSize = sizeof(BITMAPINFOHEADER);
                header->biWidth = (LONG)width;
                header->biHeight = (LONG)height;
                header->biPlanes = 1;
                header->biBitCount = 24;
                header->biCompression = BI_RGB;
                header->biSizeImage = (DWORD)(stride * height);
                BYTE* pixels = &out.dib[sizeof(BITMAPINFOHEADER)];
                for (UINT y = 0; y < height; y++) {
                    const BYTE* from = &source[(size_t)y * width * 4];
                    BYTE* to = pixels + (size_t)(height - 1 - y) * stride;
                    for (UINT x = 0; x < width; x++) {
                        BYTE alpha = from[x * 4 + 3];
                        for (int c = 0; c < 3; c++) {
                            int value = from[x * 4 + c] + (255 - alpha);
                            to[x * 3 + c] = (BYTE)(value > 255 ? 255 : value);
                        }
                    }
                }
                out.width = (int)width;
                out.height = (int)height;
                out.path = path;
                ok = true;
            }
        }
    }
    release(converter);
    release(frame);
    release(decoder);
    release(factory);
    if (SUCCEEDED(com))
        CoUninitialize();
    if (!ok) {
        out = Picture();
        return false;
    }
    if (extensionOf(path) == L".png")
        readFile(path, out.png, kMaxPngBytes);
    return true;
}

void draw(HDC dc, const RECT& area, const Picture& picture, COLORREF background) {
    HBRUSH brush = CreateSolidBrush(background);
    FillRect(dc, &area, brush);
    DeleteObject(brush);
    if (picture.empty())
        return;
    int availableWidth = area.right - area.left, availableHeight = area.bottom - area.top;
    if (availableWidth <= 0 || availableHeight <= 0)
        return;
    //as large as fits, never larger than it is (a small picture is not blown up)
    double scale = (std::min)((double)availableWidth / picture.width, (double)availableHeight / picture.height);
    if (scale > 1.0)
        scale = 1.0;
    int width = (std::max)(1, (int)(picture.width * scale));
    int height = (std::max)(1, (int)(picture.height * scale));
    int x = area.left + (availableWidth - width) / 2;
    int y = area.top + (availableHeight - height) / 2;
    const BITMAPINFO* info = (const BITMAPINFO*)&picture.dib[0];
    const BYTE* pixels = &picture.dib[sizeof(BITMAPINFOHEADER)];
    int oldMode = SetStretchBltMode(dc, HALFTONE);
    SetBrushOrgEx(dc, 0, 0, NULL);
    StretchDIBits(dc, x, y, width, height, 0, 0, picture.width, picture.height, pixels, info, DIB_RGB_COLORS, SRCCOPY);
    SetStretchBltMode(dc, oldMode);
}

static bool setClipboardBlock(UINT format, const std::vector<BYTE>& bytes) {
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
    if (!memory)
        return false;
    void* destination = GlobalLock(memory);
    if (!destination) {
        GlobalFree(memory);
        return false;
    }
    memcpy(destination, &bytes[0], bytes.size());
    GlobalUnlock(memory);
    if (!SetClipboardData(format, memory)) {
        GlobalFree(memory);
        return false;
    }
    return true;
}

bool copyToClipboard(HWND owner, const Picture& picture) {
    if (picture.empty())
        return false;
    bool opened = false;
    for (int attempt = 0; attempt < 10 && !opened; attempt++) { //another program may hold it for a moment
        opened = OpenClipboard(owner) != FALSE;
        if (!opened)
            Sleep(15);
    }
    if (!opened)
        return false;
    EmptyClipboard();
    bool ok = setClipboardBlock(CF_DIB, picture.dib);
    if (ok && !picture.png.empty())
        setClipboardBlock(RegisterClipboardFormatW(L"PNG"), picture.png); //programs that know it keep the transparency
    CloseClipboard();
    return ok;
}

std::wstring downloadsFolder() {
    PWSTR known = NULL;
    std::wstring folder;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Downloads, 0, NULL, &known)) && known) {
        folder = known;
        CoTaskMemFree(known);
    }
    if (folder.empty()) {
        wchar_t profile[MAX_PATH];
        DWORD length = GetEnvironmentVariableW(L"USERPROFILE", profile, MAX_PATH);
        if (length > 0 && length < MAX_PATH)
            folder = std::wstring(profile) + L"\\Downloads";
    }
    return folder;
}

std::wstring saveCopy(const std::wstring& source, const std::wstring& folder) {
    if (source.empty() || folder.empty())
        return std::wstring();
    CreateDirectoryW(folder.c_str(), NULL); //Downloads may not exist yet
    std::wstring extension = extensionOf(source);
    if (extension.empty())
        extension = L".png";
    SYSTEMTIME now;
    GetLocalTime(&now);
    wchar_t stamp[32];
    wsprintfW(stamp, L"%04d%02d%02d-%02d%02d%02d", now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond);
    for (int number = 1; number < 100; number++) {
        std::wstring name = L"VOpenKey AI " + std::wstring(stamp) + (number > 1 ? L" (" + std::to_wstring(number) + L")" : std::wstring()) + extension;
        std::wstring target = folder + L"\\" + name;
        if (CopyFileW(source.c_str(), target.c_str(), TRUE)) //TRUE: never over a file that is there
            return target;
        if (GetLastError() != ERROR_FILE_EXISTS && GetLastError() != ERROR_ALREADY_EXISTS)
            break;
    }
    return std::wstring();
}

void showInExplorer(const std::wstring& path) {
    if (path.empty())
        return;
    std::wstring arguments = L"/select,\"" + path + L"\"";
    ShellExecuteW(NULL, L"open", L"explorer.exe", arguments.c_str(), NULL, SW_SHOWNORMAL);
}

void openWithDefaultProgram(const std::wstring& path) {
    if (!path.empty())
        ShellExecuteW(NULL, L"open", path.c_str(), NULL, NULL, SW_SHOWNORMAL);
}

} // namespace PictureFile
