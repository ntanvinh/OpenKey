//
//  DictStore.cpp
//  VOpenKey
//
//  Offline dictionary compiler, memory-mapped reader, multi-dictionary lookup engine,
//  and rich-text parser. Plain ASCII source (C++11, macOS + Windows + Linux portable).
//
#include "DictStore.h"
#include "DictInflate.h"
#include "MiniJson.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <unordered_map>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <dirent.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace vdict {

namespace {

// ============================================================================================================
// Portable UTF-8 File & Mapping Helpers
// ============================================================================================================

#ifdef _WIN32
std::wstring utf8ToWide(const std::string& utf8) {
    if (utf8.empty()) return std::wstring();
    int needed = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), (int)utf8.size(), NULL, 0);
    if (needed <= 0) return std::wstring();
    std::wstring wide((size_t)needed, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), (int)utf8.size(), &wide[0], needed);
    return wide;
}

std::string wideToUtf8(const std::wstring& wide) {
    if (wide.empty()) return std::string();
    int needed = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), (int)wide.size(), NULL, 0, NULL, NULL);
    if (needed <= 0) return std::string();
    std::string out((size_t)needed, '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), (int)wide.size(), &out[0], needed, NULL, NULL);
    return out;
}
#endif

FILE* openFileUtf8(const std::string& path, const char* mode) {
#ifdef _WIN32
    std::wstring wp = utf8ToWide(path);
    std::wstring wm = utf8ToWide(mode);
    if (wp.empty() || wm.empty()) return NULL;
    return _wfopen(wp.c_str(), wm.c_str());
#else
    return fopen(path.c_str(), mode);
#endif
}

bool readFileBytesUtf8(const std::string& path, std::vector<uint8_t>& out) {
    out.clear();
    FILE* f = openFileUtf8(path, "rb");
    if (!f) return false;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return false; }
    long long sz =
#ifdef _WIN32
        _ftelli64(f);
#else
        (long long)ftell(f);
#endif
    if (sz < 0 || sz > 1024LL * 1024LL * 1024LL) { fclose(f); return false; }
#ifdef _WIN32
    _fseeki64(f, 0, SEEK_SET);
#else
    fseek(f, 0, SEEK_SET);
#endif
    out.resize((size_t)sz);
    size_t readTotal = 0;
    while (readTotal < out.size()) {
        size_t n = fread(&out[readTotal], 1, out.size() - readTotal, f);
        if (n == 0) break;
        readTotal += n;
    }
    fclose(f);
    return readTotal == out.size();
}

bool renameFileUtf8(const std::string& src, const std::string& dst) {
#ifdef _WIN32
    return MoveFileExW(utf8ToWide(src).c_str(), utf8ToWide(dst).c_str(),
                       MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
#else
    return rename(src.c_str(), dst.c_str()) == 0;
#endif
}

void removeFileUtf8(const std::string& path) {
#ifdef _WIN32
    DeleteFileW(utf8ToWide(path).c_str());
#else
    unlink(path.c_str());
#endif
}

std::string lowercaseAscii(std::string s) {
    for (size_t i = 0; i < s.size(); ++i)
        s[i] = (char)tolower((unsigned char)s[i]);
    return s;
}

bool endsWithIgnoreCase(const std::string& s, const std::string& suffix) {
    if (s.size() < suffix.size()) return false;
    std::string tail = lowercaseAscii(s.substr(s.size() - suffix.size()));
    return tail == lowercaseAscii(suffix);
}

std::string trimAscii(const std::string& s) {
    size_t a = 0;
    while (a < s.size() && ((unsigned char)s[a] <= ' ')) ++a;
    size_t b = s.size();
    while (b > a && ((unsigned char)s[b - 1] <= ' ')) --b;
    return s.substr(a, b - a);
}

// ============================================================================================================
// UTF-8 / Vietnamese Case & Accent Folding
// ============================================================================================================

uint32_t nextCodepoint(const std::string& s, size_t& i) {
    unsigned char b0 = (unsigned char)s[i++];
    if (b0 < 0x80) return b0;
    if ((b0 & 0xE0) == 0xC0 && i < s.size()) {
        uint32_t cp = ((uint32_t)(b0 & 0x1F) << 6) | ((uint32_t)((unsigned char)s[i++] & 0x3F));
        return cp;
    }
    if ((b0 & 0xF0) == 0xE0 && i + 1 < s.size()) {
        uint32_t cp = ((uint32_t)(b0 & 0x0F) << 12) |
                      ((uint32_t)((unsigned char)s[i] & 0x3F) << 6) |
                      ((uint32_t)((unsigned char)s[i + 1] & 0x3F));
        i += 2;
        return cp;
    }
    if ((b0 & 0xF8) == 0xF0 && i + 2 < s.size()) {
        uint32_t cp = ((uint32_t)(b0 & 0x07) << 18) |
                      ((uint32_t)((unsigned char)s[i] & 0x3F) << 12) |
                      ((uint32_t)((unsigned char)s[i + 1] & 0x3F) << 6) |
                      ((uint32_t)((unsigned char)s[i + 2] & 0x3F));
        i += 3;
        return cp;
    }
    return b0;
}

void appendUtf8(std::string& out, uint32_t cp) {
    if (cp < 0x80) {
        out.push_back((char)cp);
    } else if (cp < 0x800) {
        out.push_back((char)(0xC0 | (cp >> 6)));
        out.push_back((char)(0x80 | (cp & 0x3F)));
    } else if (cp < 0x10000) {
        out.push_back((char)(0xE0 | (cp >> 12)));
        out.push_back((char)(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back((char)(0x80 | (cp & 0x3F)));
    } else {
        out.push_back((char)(0xF0 | (cp >> 18)));
        out.push_back((char)(0x80 | ((cp >> 12) & 0x3F)));
        out.push_back((char)(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back((char)(0x80 | (cp & 0x3F)));
    }
}

struct VietGroup {
    uint32_t lower[6];
    uint32_t upper[6];
    char base;
};

const VietGroup kVietGroups[] = {
    {{0x0061, 0x00E0, 0x00E1, 0x1EA3, 0x00E3, 0x1EA1}, {0x0041, 0x00C0, 0x00C1, 0x1EA2, 0x00C3, 0x1EA0}, 'a'},
    {{0x0103, 0x1EB1, 0x1EAF, 0x1EB3, 0x1EB5, 0x1EB7}, {0x0102, 0x1EB0, 0x1EAE, 0x1EB2, 0x1EB4, 0x1EB6}, 'a'},
    {{0x00E2, 0x1EA7, 0x1EA5, 0x1EA9, 0x1EAB, 0x1EAD}, {0x00C2, 0x1EA6, 0x1EA4, 0x1EA8, 0x1EAA, 0x1EAC}, 'a'},
    {{0x0065, 0x00E8, 0x00E9, 0x1EBB, 0x1EBD, 0x1EB9}, {0x0045, 0x00C8, 0x00C9, 0x1EBA, 0x1EBC, 0x1EB8}, 'e'},
    {{0x00EA, 0x1EC1, 0x1EBF, 0x1EC3, 0x1EC5, 0x1EC7}, {0x00CA, 0x1EC0, 0x1EBE, 0x1EC2, 0x1EC4, 0x1EC6}, 'e'},
    {{0x0069, 0x00EC, 0x00ED, 0x1EC9, 0x0129, 0x1ECB}, {0x0049, 0x00CC, 0x00CD, 0x1EC8, 0x0128, 0x1ECA}, 'i'},
    {{0x006F, 0x00F2, 0x00F3, 0x1ECF, 0x00F5, 0x1ECD}, {0x004F, 0x00D2, 0x00D3, 0x1ECE, 0x00D5, 0x1ECC}, 'o'},
    {{0x00F4, 0x1ED3, 0x1ED1, 0x1ED5, 0x1ED7, 0x1ED9}, {0x00D4, 0x1ED2, 0x1ED0, 0x1ED4, 0x1ED6, 0x1ED8}, 'o'},
    {{0x01A1, 0x1EDD, 0x1EDB, 0x1EDF, 0x1EE1, 0x1EE3}, {0x01A0, 0x1EDC, 0x1EDA, 0x1EDE, 0x1EE0, 0x1EE2}, 'o'},
    {{0x0075, 0x00F9, 0x00FA, 0x1EE7, 0x0169, 0x1EE5}, {0x0055, 0x00D9, 0x00DA, 0x1EE6, 0x0168, 0x1EE4}, 'u'},
    {{0x01B0, 0x1EEB, 0x1EE9, 0x1EED, 0x1EEF, 0x1EF1}, {0x01AF, 0x1EEA, 0x1EE8, 0x1EEC, 0x1EEE, 0x1EF0}, 'u'},
    {{0x0079, 0x1EF3, 0x00FD, 0x1EF7, 0x1EF9, 0x1EF5}, {0x0059, 0x1EF2, 0x00DD, 0x1EF6, 0x1EF8, 0x1EF4}, 'y'},
};

struct FoldTables {
    std::unordered_map<uint32_t, char> foldedBase;
    std::unordered_map<uint32_t, uint32_t> lowerMap;

    FoldTables() {
        for (size_t g = 0; g < sizeof(kVietGroups) / sizeof(kVietGroups[0]); ++g) {
            for (int t = 0; t < 6; ++t) {
                foldedBase[kVietGroups[g].lower[t]] = kVietGroups[g].base;
                foldedBase[kVietGroups[g].upper[t]] = kVietGroups[g].base;
                lowerMap[kVietGroups[g].upper[t]] = kVietGroups[g].lower[t];
            }
        }
        foldedBase[0x0110] = 'd'; // D with stroke
        foldedBase[0x0111] = 'd';
        lowerMap[0x0110] = 0x0111;
        // Common European letters
        foldedBase[0x00E4] = 'a'; foldedBase[0x00C4] = 'a'; lowerMap[0x00C4] = 0x00E4;
        foldedBase[0x00E5] = 'a'; foldedBase[0x00C5] = 'a'; lowerMap[0x00C5] = 0x00E5;
        foldedBase[0x00E7] = 'c'; foldedBase[0x00C7] = 'c'; lowerMap[0x00C7] = 0x00E7;
        foldedBase[0x00EB] = 'e'; foldedBase[0x00CB] = 'e'; lowerMap[0x00CB] = 0x00EB;
        foldedBase[0x00EF] = 'i'; foldedBase[0x00CF] = 'i'; lowerMap[0x00CF] = 0x00EF;
        foldedBase[0x00F1] = 'n'; foldedBase[0x00D1] = 'n'; lowerMap[0x00D1] = 0x00F1;
        foldedBase[0x00F6] = 'o'; foldedBase[0x00D6] = 'o'; lowerMap[0x00D6] = 0x00F6;
        foldedBase[0x00FC] = 'u'; foldedBase[0x00DC] = 'u'; lowerMap[0x00DC] = 0x00FC;
    }
};

const FoldTables& foldTables() {
    static const FoldTables t;
    return t;
}

inline bool isCombiningMark(uint32_t cp) {
    return (cp >= 0x0300 && cp <= 0x036F) ||
           (cp >= 0x1AB0 && cp <= 0x1AFF) ||
           (cp >= 0x1DC0 && cp <= 0x1DFF);
}

// ============================================================================================================
// Binary .vdict Layout Constants & Little-Endian IO
// ============================================================================================================

const char kMagic[8] = {'V', 'O', 'K', 'D', 'I', 'C', 'T', '1'};
const uint32_t kFormatVersion = 1;
const size_t kHeaderSize = 96;
const size_t kKeyRecSize = 20;
const size_t kEntryRecSize = 16;
const size_t kBlockRecSize = 16;
const size_t kTargetRawBlockBytes = 32768u;

inline uint16_t getU16(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

inline uint32_t getU32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

inline uint64_t getU64(const uint8_t* p) {
    return (uint64_t)getU32(p) | ((uint64_t)getU32(p + 4) << 32);
}

inline uint32_t getU32BE(const uint8_t* p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

inline uint64_t getU64BE(const uint8_t* p) {
    return ((uint64_t)getU32BE(p) << 32) | (uint64_t)getU32BE(p + 4);
}

inline void putU16(uint8_t* p, uint16_t v) {
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
}

inline void putU32(uint8_t* p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
    p[2] = (uint8_t)((v >> 16) & 0xFF);
    p[3] = (uint8_t)((v >> 24) & 0xFF);
}

inline void putU64(uint8_t* p, uint64_t v) {
    putU32(p, (uint32_t)(v & 0xFFFFFFFFu));
    putU32(p + 4, (uint32_t)(v >> 32));
}

struct CompileEntry {
    std::string headword;
    std::string body;
    uint8_t typeTag;
};

struct CompileSyn {
    std::string word;
    uint32_t compiledEntryIdx;
};

struct CompileKey {
    std::string folded;
    std::string display;
    std::string lowerDisplay;
    uint32_t entryIdx;
    uint8_t isSyn;
};

struct BuiltBlock {
    std::vector<uint8_t> comp;
    uint32_t rawSize;
};

bool writeAll(FILE* f, const void* data, size_t len) {
    if (len == 0) return true;
    return fwrite(data, 1, len, f) == len;
}

// Writes compiled entries + synonyms + metadata to an atomic .vdict file.
bool writeVdictFromEntries(std::vector<CompileEntry>& entries,
                           const std::vector<CompileSyn>& syns,
                           const CompileMetadata& meta,
                           const std::string& outVdictPath,
                           std::string* error) {
    if (entries.empty()) {
        if (error) *error = "Dictionary contains no entries";
        return false;
    }

    // Build Key list (headwords + synonyms)
    std::vector<CompileKey> keys;
    keys.reserve(entries.size() + syns.size());
    for (uint32_t i = 0; i < (uint32_t)entries.size(); ++i) {
        std::string folded = foldForLookup(entries[i].headword);
        if (folded.empty()) continue;
        CompileKey k;
        k.folded = folded;
        k.display = entries[i].headword;
        k.lowerDisplay = lowercaseUtf8(k.display);
        k.entryIdx = i;
        k.isSyn = 0;
        keys.push_back(k);
    }
    for (size_t i = 0; i < syns.size(); ++i) {
        if (syns[i].compiledEntryIdx >= entries.size()) continue;
        std::string folded = foldForLookup(syns[i].word);
        if (folded.empty()) continue;
        if (syns[i].word == entries[syns[i].compiledEntryIdx].headword) continue;
        CompileKey k;
        k.folded = folded;
        k.display = syns[i].word;
        k.lowerDisplay = lowercaseUtf8(k.display);
        k.entryIdx = syns[i].compiledEntryIdx;
        k.isSyn = 1;
        keys.push_back(k);
    }
    if (keys.empty()) {
        if (error) *error = "Dictionary contains no searchable keys";
        return false;
    }

    std::sort(keys.begin(), keys.end(), [](const CompileKey& a, const CompileKey& b) {
        if (a.folded != b.folded) return a.folded < b.folded;
        if (a.isSyn != b.isSyn) return a.isSyn < b.isSyn;
        if (a.lowerDisplay != b.lowerDisplay) return a.lowerDisplay < b.lowerDisplay;
        if (a.display != b.display) return a.display < b.display;
        return a.entryIdx < b.entryIdx;
    });

    // Pack entries into 32 KB raw blocks (stored format per entry inside block:
    // [u16 hwLen][hw bytes][body bytes], referenced by entryRec[blockIdx, offInBlock, hwLen + 2 + bodyLen, typeTag])
    std::vector<BuiltBlock> blocks;
    std::vector<uint8_t> entryTable(entries.size() * kEntryRecSize, 0);
    std::vector<uint8_t> curRaw;
    curRaw.reserve(kTargetRawBlockBytes + 4096);

    auto flushBlock = [&]() {
        if (curRaw.empty()) return;
        BuiltBlock blk;
        blk.rawSize = (uint32_t)curRaw.size();
        compressBlockLZ(&curRaw[0], curRaw.size(), blk.comp);
        blocks.push_back(std::move(blk));
        curRaw.clear();
    };

    for (size_t i = 0; i < entries.size(); ++i) {
        const std::string& hw = entries[i].headword;
        const std::string& body = entries[i].body;
        uint16_t hwLen = (uint16_t)std::min<size_t>(hw.size(), 65535u);
        size_t recordBytes = 2u + hwLen + body.size();
        if (!curRaw.empty() && curRaw.size() + recordBytes > kTargetRawBlockBytes)
            flushBlock();

        uint32_t blkIdx = (uint32_t)blocks.size();
        uint32_t offInBlock = (uint32_t)curRaw.size();
        curRaw.push_back((uint8_t)(hwLen & 0xFF));
        curRaw.push_back((uint8_t)((hwLen >> 8) & 0xFF));
        curRaw.insert(curRaw.end(), hw.begin(), hw.begin() + hwLen);
        curRaw.insert(curRaw.end(), body.begin(), body.end());

        uint8_t* er = &entryTable[i * kEntryRecSize];
        putU32(er + 0, blkIdx);
        putU32(er + 4, offInBlock);
        putU32(er + 8, (uint32_t)recordBytes);
        er[12] = entries[i].typeTag;

        if (curRaw.size() >= kTargetRawBlockBytes)
            flushBlock();
    }
    flushBlock();

    // Build string pools & KeyRec table
    std::string foldedPool;
    std::string dispPool;
    foldedPool.reserve(keys.size() * 14);
    dispPool.reserve(keys.size() * 14);
    std::vector<uint8_t> keyTable(keys.size() * kKeyRecSize, 0);

    for (size_t i = 0; i < keys.size(); ++i) {
        const CompileKey& k = keys[i];
        uint32_t fOff = (uint32_t)foldedPool.size();
        uint16_t fLen = (uint16_t)std::min<size_t>(k.folded.size(), 65535u);
        uint32_t dOff = (uint32_t)dispPool.size();
        uint16_t dLen = (uint16_t)std::min<size_t>(k.display.size(), 65535u);

        // Avoid duplicating adjacent identical folded strings when foldedPool matches previous!
        if (i > 0 && keys[i - 1].folded == k.folded) {
            const uint8_t* prev = &keyTable[(i - 1) * kKeyRecSize];
            fOff = getU32(prev + 0);
        } else {
            foldedPool.append(k.folded, 0, fLen);
        }
        dispPool.append(k.display, 0, dLen);

        uint8_t* kr = &keyTable[i * kKeyRecSize];
        putU32(kr + 0, fOff);
        putU32(kr + 4, dOff);
        putU32(kr + 8, k.entryIdx);
        putU16(kr + 12, fLen);
        putU16(kr + 14, dLen);
        putU32(kr + 16, k.isSyn ? 1u : 0u);
    }

    // Metadata JSON
    vjson::Value mj = vjson::Value::object();
    mj.set("dictId", vjson::Value::string(meta.dictId));
    mj.set("displayName", vjson::Value::string(meta.displayName));
    mj.set("shortName", vjson::Value::string(meta.shortName));
    mj.set("badge", vjson::Value::string(meta.badge));
    mj.set("sourceLang", vjson::Value::string(meta.sourceLang));
    mj.set("targetLang", vjson::Value::string(meta.targetLang));
    mj.set("author", vjson::Value::string(meta.author));
    mj.set("license", vjson::Value::string(meta.license));
    std::string metaJson = vjson::write(mj, false);

    // Compute offsets
    uint64_t metaOff = kHeaderSize;
    uint64_t keyOff = metaOff + metaJson.size();
    uint64_t foldedOff = keyOff + keyTable.size();
    uint64_t dispOff = foldedOff + foldedPool.size();
    uint64_t entryOff = dispOff + dispPool.size();
    uint64_t blockOff = entryOff + entryTable.size();
    uint64_t dataOff = blockOff + (uint64_t)blocks.size() * kBlockRecSize;

    std::vector<uint8_t> blockTable(blocks.size() * kBlockRecSize, 0);
    uint64_t curCompOff = dataOff;
    for (size_t i = 0; i < blocks.size(); ++i) {
        uint8_t* br = &blockTable[i * kBlockRecSize];
        putU64(br + 0, curCompOff);
        putU32(br + 8, (uint32_t)blocks[i].comp.size());
        putU32(br + 12, blocks[i].rawSize);
        curCompOff += blocks[i].comp.size();
    }

    uint8_t hdr[kHeaderSize];
    memset(hdr, 0, sizeof(hdr));
    memcpy(hdr, kMagic, 8);
    putU32(hdr + 8, kFormatVersion);
    putU32(hdr + 12, (uint32_t)entries.size());
    putU32(hdr + 16, (uint32_t)keys.size());
    putU32(hdr + 20, (uint32_t)blocks.size());
    putU64(hdr + 24, metaOff);
    putU64(hdr + 32, metaJson.size());
    putU64(hdr + 40, keyOff);
    putU64(hdr + 48, foldedOff);
    putU64(hdr + 56, foldedPool.size());
    putU64(hdr + 64, dispOff);
    putU64(hdr + 72, dispPool.size());
    putU64(hdr + 80, entryOff);
    putU64(hdr + 88, blockOff);

    std::string tmpPath = outVdictPath + ".tmp";
    FILE* f = openFileUtf8(tmpPath, "wb");
    if (!f) {
        if (error) *error = "Cannot open output .vdict file for writing";
        return false;
    }

    bool ok = writeAll(f, hdr, sizeof(hdr)) &&
              writeAll(f, metaJson.data(), metaJson.size()) &&
              writeAll(f, keyTable.data(), keyTable.size()) &&
              writeAll(f, foldedPool.data(), foldedPool.size()) &&
              writeAll(f, dispPool.data(), dispPool.size()) &&
              writeAll(f, entryTable.data(), entryTable.size()) &&
              writeAll(f, blockTable.data(), blockTable.size());
    for (size_t i = 0; ok && i < blocks.size(); ++i)
        ok = writeAll(f, blocks[i].comp.data(), blocks[i].comp.size());

    if (fclose(f) != 0)
        ok = false;
    if (!ok || !renameFileUtf8(tmpPath, outVdictPath)) {
        removeFileUtf8(tmpPath);
        if (error) *error = "Failed writing or finalizing .vdict file";
        return false;
    }
    return true;
}

// ============================================================================================================
// HTML & OVDP Rich-Text Helper Utilities
// ============================================================================================================

std::string decodeHtmlEntities(const std::string& in) {
    std::string out;
    out.reserve(in.size());
    for (size_t i = 0; i < in.size(); ++i) {
        if (in[i] == '&') {
            size_t semi = in.find(';', i + 1);
            if (semi != std::string::npos && semi - i <= 8) {
                std::string ent = in.substr(i + 1, semi - i - 1);
                if (ent == "lt") { out.push_back('<'); i = semi; continue; }
                if (ent == "gt") { out.push_back('>'); i = semi; continue; }
                if (ent == "amp") { out.push_back('&'); i = semi; continue; }
                if (ent == "quot") { out.push_back('"'); i = semi; continue; }
                if (ent == "apos" || ent == "#39") { out.push_back('\''); i = semi; continue; }
                if (ent == "nbsp") { out.push_back(' '); i = semi; continue; }
                if (!ent.empty() && ent[0] == '#') {
                    unsigned long cp = 0;
                    if (ent.size() > 1 && (ent[1] == 'x' || ent[1] == 'X'))
                        cp = strtoul(ent.c_str() + 2, NULL, 16);
                    else
                        cp = strtoul(ent.c_str() + 1, NULL, 10);
                    if (cp > 0 && cp < 0x110000u) {
                        appendUtf8(out, (uint32_t)cp);
                        i = semi;
                        continue;
                    }
                }
            }
        }
        out.push_back(in[i]);
    }
    return out;
}

std::string stripAllTags(const std::string& html) {
    std::string out;
    out.reserve(html.size());
    bool inTag = false;
    for (size_t i = 0; i < html.size(); ++i) {
        char c = html[i];
        if (c == '<') { inTag = true; continue; }
        if (c == '>') { inTag = false; continue; }
        if (!inTag) out.push_back(c);
    }
    return trimAscii(decodeHtmlEntities(out));
}

bool tagHasAttrValue(const std::string& tagBody, const char* needle) {
    return lowercaseAscii(tagBody).find(needle) != std::string::npos;
}

void parseHtmlIntoLines(const std::string& html,
                        const std::string& headword,
                        std::vector<FormattedLine>& out) {
    // Simple block-aware HTML walk supporting div/p/li/br/h* plus class="hw"/"ipa"/"pos"/"ex"/"idiom"
    size_t i = 0;
    std::string buf;
    BlockKind curKind = BlockKind::Plain;
    std::string curPos;

    auto flush = [&]() {
        std::string txt = trimAscii(decodeHtmlEntities(buf));
        buf.clear();
        if (txt.empty()) return;
        // Skip duplicate top headword line if it only echoes headword
        if (curKind == BlockKind::Headword) {
            if (foldForLookup(txt) == foldForLookup(headword)) {
                curKind = BlockKind::Plain;
                return;
            }
        }
        FormattedLine ln;
        ln.kind = curKind;
        ln.text = txt;
        out.push_back(ln);
        curKind = BlockKind::Plain;
    };

    while (i < html.size()) {
        if (html[i] == '<') {
            size_t close = html.find('>', i + 1);
            if (close == std::string::npos) { buf += html[i++]; continue; }
            std::string tagRaw = html.substr(i + 1, close - i - 1);
            std::string tag = lowercaseAscii(tagRaw);
            bool closing = !tag.empty() && tag[0] == '/';
            std::string name;
            for (size_t k = closing ? 1 : 0; k < tag.size() && isalpha((unsigned char)tag[k]); ++k)
                name.push_back(tag[k]);

            if (name == "br" || name == "p" || name == "div" || name == "li" ||
                name == "ul" || name == "ol" || name == "tr" || name == "dt" || name == "dd" ||
                (name.size() == 2 && name[0] == 'h')) {
                flush();
                if (!closing && name == "li") curKind = BlockKind::Sense;
                else if (!closing && tagHasAttrValue(tag, "hw")) curKind = BlockKind::Headword;
                else if (!closing && tagHasAttrValue(tag, "ipa")) curKind = BlockKind::Phonetic;
                else if (!closing && tagHasAttrValue(tag, "pos")) curKind = BlockKind::PartOfSpeech;
                else if (!closing && tagHasAttrValue(tag, "ex")) curKind = BlockKind::Example;
            } else if (!closing && name == "span") {
                if (tagHasAttrValue(tag, "ipa") || tagHasAttrValue(tag, "phon") || tagHasAttrValue(tag, "pron")) {
                    flush();
                    curKind = BlockKind::Phonetic;
                } else if (tagHasAttrValue(tag, "pos") || tagHasAttrValue(tag, "gram")) {
                    flush();
                    curKind = BlockKind::PartOfSpeech;
                } else if (tagHasAttrValue(tag, "ex")) {
                    flush();
                    curKind = BlockKind::Example;
                }
            } else if (closing && name == "span" &&
                       (curKind == BlockKind::Phonetic || curKind == BlockKind::PartOfSpeech)) {
                flush();
            } else if (!buf.empty() && buf[buf.size() - 1] != ' ' && (name == "i" || name == "b" || name == "em" || name == "strong")) {
                if (!closing) buf.push_back(' ');
            }
            i = close + 1;
        } else if (html[i] == '\r' || html[i] == '\n') {
            if (!buf.empty() && buf[buf.size() - 1] != ' ')
                buf.push_back(' ');
            ++i;
        } else {
            buf.push_back(html[i++]);
        }
    }
    flush();

    if (out.empty()) {
        std::string plain = stripAllTags(html);
        if (!plain.empty()) {
            FormattedLine ln;
            ln.kind = BlockKind::Plain;
            ln.text = plain;
            out.push_back(ln);
        }
    }
}

void parseMarkupTextIntoLines(const std::string& raw,
                              const std::string& headword,
                              std::vector<FormattedLine>& out) {
    std::istringstream ss(raw);
    std::string line;
    std::string foldedHw = foldForLookup(headword);
    while (std::getline(ss, line)) {
        if (!line.empty() && line[line.size() - 1] == '\r')
            line.pop_back();
        std::string t = trimAscii(line);
        if (t.empty()) continue;

        if (t[0] == '@') {
            // OVDP header: "@headword /ipa/" or "@headword"
            std::string rest = trimAscii(t.substr(1));
            size_t slash = rest.find(" /");
            std::string hwPart = (slash != std::string::npos) ? trimAscii(rest.substr(0, slash)) : rest;
            std::string ipaPart = (slash != std::string::npos) ? trimAscii(rest.substr(slash + 1)) : "";
            if (foldForLookup(hwPart) != foldedHw && !hwPart.empty()) {
                FormattedLine ln;
                ln.kind = BlockKind::Headword;
                ln.text = hwPart;
                out.push_back(ln);
            }
            if (!ipaPart.empty()) {
                FormattedLine ln;
                ln.kind = BlockKind::Phonetic;
                ln.text = ipaPart;
                out.push_back(ln);
            }
        } else if (t[0] == '*') {
            FormattedLine ln;
            ln.kind = BlockKind::PartOfSpeech;
            ln.text = trimAscii(t.substr(1));
            if (!ln.text.empty()) out.push_back(ln);
        } else if (t[0] == '!') {
            FormattedLine ln;
            ln.kind = BlockKind::Note;
            ln.text = trimAscii(t.substr(1));
            if (!ln.text.empty()) out.push_back(ln);
        } else if (t[0] == '=') {
            std::string body = trimAscii(t.substr(1));
            size_t plus = body.find('+');
            FormattedLine ln;
            ln.kind = BlockKind::Example;
            if (plus != std::string::npos) {
                ln.text = trimAscii(body.substr(0, plus));
                ln.secondary = trimAscii(body.substr(plus + 1));
            } else {
                ln.text = body;
            }
            if (!ln.text.empty()) out.push_back(ln);
        } else if (t[0] == '-' || t[0] == '+') {
            FormattedLine ln;
            ln.kind = (t[0] == '-') ? BlockKind::Sense : BlockKind::SubSense;
            ln.text = trimAscii(t.substr(1));
            if (!ln.text.empty()) out.push_back(ln);
        } else if (t[0] == '/' && t.size() > 2 && t[t.size() - 1] == '/') {
            FormattedLine ln;
            ln.kind = BlockKind::Phonetic;
            ln.text = t;
            out.push_back(ln);
        } else {
            FormattedLine ln;
            ln.kind = BlockKind::Plain;
            ln.text = t;
            out.push_back(ln);
        }
    }
}

} // namespace

// ============================================================================================================
// Public Normalization & Rich-Text Entry Parsing
// ============================================================================================================

std::string foldForLookup(const std::string& utf8Text) {
    const FoldTables& ft = foldTables();
    std::string out;
    out.reserve(utf8Text.size());
    bool lastWasSpace = true;

    for (size_t i = 0; i < utf8Text.size(); ) {
        uint32_t cp = nextCodepoint(utf8Text, i);
        if (isCombiningMark(cp))
            continue;
        if (cp <= 0x20 || cp == 0xA0) {
            if (!lastWasSpace) {
                out.push_back(' ');
                lastWasSpace = true;
            }
            continue;
        }
        lastWasSpace = false;
        if (cp < 0x80) {
            out.push_back((char)tolower((unsigned char)cp));
            continue;
        }
        auto it = ft.foldedBase.find(cp);
        if (it != ft.foldedBase.end()) {
            out.push_back(it->second);
            continue;
        }
        appendUtf8(out, cp);
    }
    while (!out.empty() && out[out.size() - 1] == ' ')
        out.pop_back();
    return out;
}

std::string lowercaseUtf8(const std::string& utf8Text) {
    const FoldTables& ft = foldTables();
    std::string out;
    out.reserve(utf8Text.size());
    for (size_t i = 0; i < utf8Text.size(); ) {
        uint32_t cp = nextCodepoint(utf8Text, i);
        if (cp < 0x80) {
            out.push_back((char)tolower((unsigned char)cp));
        } else {
            auto it = ft.lowerMap.find(cp);
            appendUtf8(out, it != ft.lowerMap.end() ? it->second : cp);
        }
    }
    return trimAscii(out);
}

void englishInflectionCandidates(const std::string& foldedWord, std::vector<std::string>& out) {
    out.clear();
    if (foldedWord.size() < 4 || foldedWord.find(' ') != std::string::npos)
        return;
    for (size_t i = 0; i < foldedWord.size(); ++i) {
        if ((unsigned char)foldedWord[i] >= 0x80 || !isalpha((unsigned char)foldedWord[i]))
            return;
    }
    size_t n = foldedWord.size();
    auto pushUnique = [&](const std::string& c) {
        if (c.size() >= 2 && std::find(out.begin(), out.end(), c) == out.end())
            out.push_back(c);
    };
    if (n > 4 && foldedWord.compare(n - 3, 3, "ies") == 0)
        pushUnique(foldedWord.substr(0, n - 3) + "y");
    if (n > 4 && foldedWord.compare(n - 3, 3, "ied") == 0)
        pushUnique(foldedWord.substr(0, n - 3) + "y");
    if (n > 4 && (foldedWord.compare(n - 3, 3, "ses") == 0 || foldedWord.compare(n - 3, 3, "xes") == 0 ||
                  foldedWord.compare(n - 3, 3, "zes") == 0 || foldedWord.compare(n - 4, 4, "ches") == 0 ||
                  foldedWord.compare(n - 4, 4, "shes") == 0))
        pushUnique(foldedWord.substr(0, n - 2));
    if (n > 3 && foldedWord[n - 1] == 's' && foldedWord[n - 2] != 's')
        pushUnique(foldedWord.substr(0, n - 1));
    if (n > 4 && foldedWord.compare(n - 2, 2, "ed") == 0) {
        std::string stem = foldedWord.substr(0, n - 2);
        pushUnique(stem);
        pushUnique(stem + "e");
        if (stem.size() >= 3 && stem[stem.size() - 1] == stem[stem.size() - 2])
            pushUnique(stem.substr(0, stem.size() - 1)); // stopped -> stop
    }
    if (n > 5 && foldedWord.compare(n - 3, 3, "ing") == 0) {
        std::string stem = foldedWord.substr(0, n - 3);
        pushUnique(stem);
        pushUnique(stem + "e"); // loving -> love
        if (stem.size() >= 3 && stem[stem.size() - 1] == stem[stem.size() - 2])
            pushUnique(stem.substr(0, stem.size() - 1)); // running -> run
    }
    if (n > 4 && foldedWord.compare(n - 2, 2, "er") == 0) {
        std::string stem = foldedWord.substr(0, n - 2);
        pushUnique(stem);
        pushUnique(stem + "e");
    }
    if (n > 5 && foldedWord.compare(n - 3, 3, "est") == 0) {
        std::string stem = foldedWord.substr(0, n - 3);
        pushUnique(stem);
        pushUnique(stem + "e");
    }
}

std::vector<FormattedLine> parseEntryRichText(const std::string& raw,
                                              uint8_t typeTag,
                                              const std::string& headword) {
    std::vector<FormattedLine> lines;
    if (typeTag == 'h' || typeTag == 'g')
        parseHtmlIntoLines(raw, headword, lines);
    else
        parseMarkupTextIntoLines(raw, headword, lines);
    return lines;
}

// ============================================================================================================
// StarDict & FVDP Compilation
// ============================================================================================================

bool compileStarDictToFile(const StarDictMemoryInput& input,
                           const CompileMetadata& meta,
                           const std::string& outVdictPath,
                           std::string* error) {
    if (!input.idxData || input.idxLen == 0 || !input.dictData || input.dictLen == 0) {
        if (error) *error = "Missing StarDict .idx or .dict data";
        return false;
    }

    // Decompress .dict.dz if gzipped
    std::vector<uint8_t> dictOwned;
    const uint8_t* dictBuf = input.dictData;
    size_t dictSize = input.dictLen;
    if (dictSize >= 2 && dictBuf[0] == 0x1F && dictBuf[1] == 0x8B) {
        if (!decompressGzipOrDictzip(dictBuf, dictSize, dictOwned, error))
            return false;
        dictBuf = dictOwned.empty() ? NULL : &dictOwned[0];
        dictSize = dictOwned.size();
    }

    // Decompress .syn.dz if gzipped
    std::vector<uint8_t> synOwned;
    const uint8_t* synBuf = input.synData;
    size_t synSize = input.synLen;
    if (synBuf && synSize >= 2 && synBuf[0] == 0x1F && synBuf[1] == 0x8B) {
        if (!decompressGzipOrDictzip(synBuf, synSize, synOwned, error))
            return false;
        synBuf = synOwned.empty() ? NULL : &synOwned[0];
        synSize = synOwned.size();
    }

    // Parse .ifo metadata
    int offsetBits = 32;
    std::string sameTypeSeq;
    std::string ifoBookName;
    std::istringstream ifoStream(input.ifoText);
    std::string line;
    while (std::getline(ifoStream, line)) {
        if (!line.empty() && line[line.size() - 1] == '\r')
            line.pop_back();
        size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        std::string k = trimAscii(line.substr(0, eq));
        std::string v = trimAscii(line.substr(eq + 1));
        if (k == "idxoffsetbits" && v == "64") offsetBits = 64;
        else if (k == "sametypesequence") sameTypeSeq = v;
        else if (k == "bookname") ifoBookName = v;
    }

    CompileMetadata finalMeta = meta;
    if (finalMeta.displayName.empty())
        finalMeta.displayName = !ifoBookName.empty() ? ifoBookName : meta.dictId;
    if (finalMeta.shortName.empty())
        finalMeta.shortName = finalMeta.displayName;

    // Parse .idx entries while maintaining origIdx -> compiledIdx map for .syn resolution
    std::vector<CompileEntry> entries;
    std::vector<uint32_t> origToCompiled;
    entries.reserve(32768);
    origToCompiled.reserve(32768);

    size_t pos = 0;
    size_t offBytes = (offsetBits == 64) ? 8 : 4;
    while (pos < input.idxLen) {
        const void* nul = memchr(input.idxData + pos, '\0', input.idxLen - pos);
        if (!nul) break;
        size_t wordEnd = (const uint8_t*)nul - input.idxData;
        std::string word((const char*)(input.idxData + pos), wordEnd - pos);
        pos = wordEnd + 1;
        if (pos + offBytes + 4 > input.idxLen) break;

        uint64_t dataOff = (offsetBits == 64) ? getU64BE(input.idxData + pos) : getU32BE(input.idxData + pos);
        pos += offBytes;
        uint32_t dataSz = getU32BE(input.idxData + pos);
        pos += 4;

        uint32_t mapped = 0xFFFFFFFFu;
        if (!word.empty() && word.compare(0, 12, "00-database-") != 0 &&
            dataOff <= dictSize && dataSz <= dictSize - dataOff) {
            const char* rawPtr = (const char*)(dictBuf + dataOff);
            uint8_t typeTag = 'm';
            std::string body;

            if (sameTypeSeq.empty()) {
                // Per-entry tagged format (e.g. WordNet2.0: 1-byte type tag + payload)
                size_t p = 0;
                while (p < dataSz) {
                    char t = rawPtr[p++];
                    std::string chunk;
                    if (isupper((unsigned char)t)) {
                        if (p + 4 > dataSz) break;
                        uint32_t csz = getU32BE((const uint8_t*)(rawPtr + p));
                        p += 4;
                        if (csz > dataSz - p) break;
                        p += csz;
                        continue; // Skip binary resource field
                    } else {
                        const char* segEnd = (const char*)memchr(rawPtr + p, '\0', dataSz - p);
                        size_t segLen = segEnd ? (size_t)(segEnd - (rawPtr + p)) : (dataSz - p);
                        chunk.assign(rawPtr + p, segLen);
                        p += segLen + (segEnd ? 1 : 0);
                    }
                    if (!chunk.empty()) {
                        if (body.empty()) typeTag = (uint8_t)tolower((unsigned char)t);
                        else body.push_back('\n');
                        body += chunk;
                    }
                }
            } else if (sameTypeSeq.size() == 1) {
                typeTag = (uint8_t)tolower((unsigned char)sameTypeSeq[0]);
                body.assign(rawPtr, dataSz);
            } else {
                size_t p = 0;
                for (size_t fi = 0; fi < sameTypeSeq.size() && p < dataSz; ++fi) {
                    char t = sameTypeSeq[fi];
                    std::string chunk;
                    if (fi + 1 == sameTypeSeq.size()) {
                        chunk.assign(rawPtr + p, dataSz - p);
                        p = dataSz;
                    } else if (isupper((unsigned char)t)) {
                        if (p + 4 > dataSz) break;
                        uint32_t csz = getU32BE((const uint8_t*)(rawPtr + p));
                        p += 4;
                        if (csz > dataSz - p) break;
                        p += csz;
                    } else {
                        const char* segEnd = (const char*)memchr(rawPtr + p, '\0', dataSz - p);
                        size_t segLen = segEnd ? (size_t)(segEnd - (rawPtr + p)) : (dataSz - p);
                        chunk.assign(rawPtr + p, segLen);
                        p += segLen + (segEnd ? 1 : 0);
                    }
                    if (!chunk.empty()) {
                        if (body.empty()) typeTag = (uint8_t)tolower((unsigned char)t);
                        else body.push_back('\n');
                        body += chunk;
                    }
                }
            }

            if (!body.empty()) {
                mapped = (uint32_t)entries.size();
                CompileEntry ce;
                ce.headword = word;
                ce.body = std::move(body);
                ce.typeTag = typeTag;
                entries.push_back(std::move(ce));
            }
        }
        origToCompiled.push_back(mapped);
    }

    // Parse .syn if present
    std::vector<CompileSyn> syns;
    if (synBuf && synSize > 0) {
        size_t sp = 0;
        while (sp < synSize) {
            const void* nul = memchr(synBuf + sp, '\0', synSize - sp);
            if (!nul) break;
            size_t end = (const uint8_t*)nul - synBuf;
            std::string sword((const char*)(synBuf + sp), end - sp);
            sp = end + 1;
            if (sp + 4 > synSize) break;
            uint32_t origIdx = getU32BE(synBuf + sp);
            sp += 4;
            if (!sword.empty() && origIdx < origToCompiled.size() && origToCompiled[origIdx] != 0xFFFFFFFFu) {
                CompileSyn cs;
                cs.word = sword;
                cs.compiledEntryIdx = origToCompiled[origIdx];
                syns.push_back(cs);
            }
        }
    }

    return writeVdictFromEntries(entries, syns, finalMeta, outVdictPath, error);
}

bool compileZipBytesToFile(const uint8_t* zipData,
                           size_t zipLen,
                           const CompileMetadata& meta,
                           const std::string& outVdictPath,
                           std::string* error) {
    std::vector<ZipEntry> zentries;
    if (!listZip(zipData, zipLen, zentries, error))
        return false;

    const ZipEntry* ifoEnt = NULL;
    const ZipEntry* idxEnt = NULL;
    const ZipEntry* dictEnt = NULL;
    const ZipEntry* synEnt = NULL;
    const ZipEntry* txtEnt = NULL;

    for (size_t i = 0; i < zentries.size(); ++i) {
        const ZipEntry& ze = zentries[i];
        if (ze.isDir) continue;
        if (!ifoEnt && endsWithIgnoreCase(ze.name, ".ifo")) ifoEnt = &ze;
        else if (!idxEnt && (endsWithIgnoreCase(ze.name, ".idx") || endsWithIgnoreCase(ze.name, ".idx.gz"))) idxEnt = &ze;
        else if (!dictEnt && (endsWithIgnoreCase(ze.name, ".dict.dz") || endsWithIgnoreCase(ze.name, ".dict"))) dictEnt = &ze;
        else if (!synEnt && (endsWithIgnoreCase(ze.name, ".syn.dz") || endsWithIgnoreCase(ze.name, ".syn"))) synEnt = &ze;
        else if (!txtEnt && endsWithIgnoreCase(ze.name, ".txt")) txtEnt = &ze;
    }

    if (ifoEnt && idxEnt && dictEnt) {
        std::vector<uint8_t> ifoBuf, idxRaw, idxBuf, dictBuf, synBuf;
        if (!extractZipEntry(zipData, zipLen, *ifoEnt, ifoBuf, error) ||
            !extractZipEntry(zipData, zipLen, *idxEnt, idxRaw, error) ||
            !extractZipEntry(zipData, zipLen, *dictEnt, dictBuf, error))
            return false;

        if (endsWithIgnoreCase(idxEnt->name, ".idx.gz")) {
            if (!decompressGzipOrDictzip(idxRaw.data(), idxRaw.size(), idxBuf, error))
                return false;
        } else {
            idxBuf.swap(idxRaw);
        }
        if (synEnt)
            extractZipEntry(zipData, zipLen, *synEnt, synBuf, NULL); // optional

        StarDictMemoryInput in;
        in.ifoText.assign((const char*)ifoBuf.data(), ifoBuf.size());
        in.idxData = idxBuf.empty() ? NULL : &idxBuf[0];
        in.idxLen = idxBuf.size();
        in.dictData = dictBuf.empty() ? NULL : &dictBuf[0];
        in.dictLen = dictBuf.size();
        in.synData = synBuf.empty() ? NULL : &synBuf[0];
        in.synLen = synBuf.size();
        return compileStarDictToFile(in, meta, outVdictPath, error);
    }

    if (txtEnt) {
        std::vector<uint8_t> txtBuf;
        if (!extractZipEntry(zipData, zipLen, *txtEnt, txtBuf, error))
            return false;
        std::string txt((const char*)txtBuf.data(), txtBuf.size());
        return compileFvdpTextToFile(txt, meta, outVdictPath, error);
    }

    if (error) *error = "ZIP archive does not contain a valid StarDict (.ifo/.idx/.dict) or FVDP dictionary";
    return false;
}

bool compileFvdpTextToFile(const std::string& fvdpText,
                           const CompileMetadata& meta,
                           const std::string& outVdictPath,
                           std::string* error) {
    std::vector<CompileEntry> entries;
    std::istringstream ss(fvdpText);
    std::string line;
    std::string curHw;
    std::string curBody;

    auto flush = [&]() {
        if (!curHw.empty() && !curBody.empty()) {
            CompileEntry ce;
            ce.headword = curHw;
            ce.body = curBody;
            ce.typeTag = 'm';
            entries.push_back(std::move(ce));
        }
        curHw.clear();
        curBody.clear();
    };

    while (std::getline(ss, line)) {
        if (!line.empty() && line[line.size() - 1] == '\r')
            line.pop_back();
        if (!line.empty() && line[0] == '@') {
            flush();
            std::string rest = trimAscii(line.substr(1));
            size_t slash = rest.find(" /");
            if (slash != std::string::npos) {
                curHw = trimAscii(rest.substr(0, slash));
                curBody = trimAscii(rest.substr(slash + 1)) + "\n";
            } else {
                curHw = rest;
            }
        } else if (!curHw.empty() && !line.empty()) {
            curBody += line;
            curBody.push_back('\n');
        }
    }
    flush();

    CompileMetadata finalMeta = meta;
    if (finalMeta.displayName.empty())
        finalMeta.displayName = meta.dictId;
    if (finalMeta.shortName.empty())
        finalMeta.shortName = finalMeta.displayName;
    return writeVdictFromEntries(entries, std::vector<CompileSyn>(), finalMeta, outVdictPath, error);
}

bool compileDirectoryToFile(const std::string& utf8DirPath,
                            const CompileMetadata& meta,
                            const std::string& outVdictPath,
                            std::string* error) {
    std::vector<std::string> names;
#ifdef _WIN32
    WIN32_FIND_DATAW fd;
    std::wstring pat = utf8ToWide(utf8DirPath + "\\*");
    HANDLE h = FindFirstFileW(pat.c_str(), &fd);
    if (h == INVALID_HANDLE_VALUE) {
        if (error) *error = "Cannot open dictionary folder";
        return false;
    }
    do {
        if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY))
            names.push_back(wideToUtf8(fd.cFileName));
    } while (FindNextFileW(h, &fd));
    FindClose(h);
    char sep = '\\';
#else
    DIR* dir = opendir(utf8DirPath.c_str());
    if (!dir) {
        if (error) *error = "Cannot open dictionary folder";
        return false;
    }
    while (struct dirent* ent = readdir(dir)) {
        if (ent->d_name[0] == '.') continue;
        names.push_back(ent->d_name);
    }
    closedir(dir);
    char sep = '/';
#endif

    std::string ifoFile, idxFile, dictFile, synFile, txtFile;
    for (size_t i = 0; i < names.size(); ++i) {
        const std::string& n = names[i];
        if (ifoFile.empty() && endsWithIgnoreCase(n, ".ifo")) ifoFile = n;
        else if (idxFile.empty() && (endsWithIgnoreCase(n, ".idx") || endsWithIgnoreCase(n, ".idx.gz"))) idxFile = n;
        else if (dictFile.empty() && (endsWithIgnoreCase(n, ".dict.dz") || endsWithIgnoreCase(n, ".dict"))) dictFile = n;
        else if (synFile.empty() && (endsWithIgnoreCase(n, ".syn.dz") || endsWithIgnoreCase(n, ".syn"))) synFile = n;
        else if (txtFile.empty() && endsWithIgnoreCase(n, ".txt")) txtFile = n;
    }

    std::string base = utf8DirPath;
    if (!base.empty() && base[base.size() - 1] != '/' && base[base.size() - 1] != '\\')
        base.push_back(sep);

    if (!ifoFile.empty() && !idxFile.empty() && !dictFile.empty()) {
        std::vector<uint8_t> ifoBuf, idxRaw, idxBuf, dictBuf, synBuf;
        if (!readFileBytesUtf8(base + ifoFile, ifoBuf) ||
            !readFileBytesUtf8(base + idxFile, idxRaw) ||
            !readFileBytesUtf8(base + dictFile, dictBuf)) {
            if (error) *error = "Cannot read StarDict files in directory";
            return false;
        }
        if (endsWithIgnoreCase(idxFile, ".idx.gz")) {
            if (!decompressGzipOrDictzip(idxRaw.data(), idxRaw.size(), idxBuf, error))
                return false;
        } else {
            idxBuf.swap(idxRaw);
        }
        if (!synFile.empty())
            readFileBytesUtf8(base + synFile, synBuf);

        StarDictMemoryInput in;
        in.ifoText.assign((const char*)ifoBuf.data(), ifoBuf.size());
        in.idxData = idxBuf.empty() ? NULL : &idxBuf[0];
        in.idxLen = idxBuf.size();
        in.dictData = dictBuf.empty() ? NULL : &dictBuf[0];
        in.dictLen = dictBuf.size();
        in.synData = synBuf.empty() ? NULL : &synBuf[0];
        in.synLen = synBuf.size();
        return compileStarDictToFile(in, meta, outVdictPath, error);
    }

    if (!txtFile.empty()) {
        std::vector<uint8_t> txtBuf;
        if (!readFileBytesUtf8(base + txtFile, txtBuf)) {
            if (error) *error = "Cannot read FVDP text dictionary";
            return false;
        }
        return compileFvdpTextToFile(std::string((const char*)txtBuf.data(), txtBuf.size()), meta, outVdictPath, error);
    }

    if (error) *error = "No StarDict (.ifo/.idx/.dict) files found in folder";
    return false;
}

bool compileLocalPathToFile(const std::string& utf8Path,
                            const CompileMetadata& meta,
                            const std::string& outVdictPath,
                            std::string* error) {
    if (endsWithIgnoreCase(utf8Path, ".zip")) {
        std::vector<uint8_t> zipBytes;
        if (!readFileBytesUtf8(utf8Path, zipBytes)) {
            if (error) *error = "Cannot read ZIP file";
            return false;
        }
        return compileZipBytesToFile(zipBytes.empty() ? NULL : &zipBytes[0], zipBytes.size(), meta, outVdictPath, error);
    }
    if (endsWithIgnoreCase(utf8Path, ".ifo")) {
        size_t pos = utf8Path.find_last_of("/\\");
        std::string dir = (pos == std::string::npos) ? "." : utf8Path.substr(0, pos);
        return compileDirectoryToFile(dir, meta, outVdictPath, error);
    }
    if (endsWithIgnoreCase(utf8Path, ".txt")) {
        std::vector<uint8_t> txtBytes;
        if (!readFileBytesUtf8(utf8Path, txtBytes)) {
            if (error) *error = "Cannot read text dictionary file";
            return false;
        }
        return compileFvdpTextToFile(std::string((const char*)txtBytes.data(), txtBytes.size()), meta, outVdictPath, error);
    }
    return compileDirectoryToFile(utf8Path, meta, outVdictPath, error);
}

// ============================================================================================================
// Memory-Mapped .vdict Reader
// ============================================================================================================

struct VdictReader::Impl {
    const uint8_t* data = NULL;
    size_t fileSize = 0;

#ifdef _WIN32
    HANDLE hFile = INVALID_HANDLE_VALUE;
    HANDLE hMap = NULL;
#else
    int fd = -1;
#endif

    uint32_t entryCount = 0;
    uint32_t keyCount = 0;
    uint32_t blockCount = 0;
    uint64_t keyOff = 0;
    uint64_t foldedOff = 0;
    uint64_t foldedSize = 0;
    uint64_t dispOff = 0;
    uint64_t dispSize = 0;
    uint64_t entryOff = 0;
    uint64_t blockOff = 0;

    void release() {
#ifdef _WIN32
        if (data) { UnmapViewOfFile(data); data = NULL; }
        if (hMap) { CloseHandle(hMap); hMap = NULL; }
        if (hFile != INVALID_HANDLE_VALUE) { CloseHandle(hFile); hFile = INVALID_HANDLE_VALUE; }
#else
        if (data && fileSize > 0) { munmap((void*)data, fileSize); data = NULL; }
        if (fd >= 0) { ::close(fd); fd = -1; }
#endif
        fileSize = 0;
        entryCount = keyCount = blockCount = 0;
    }

    int compareKeyFolded(uint32_t idx, const std::string& target) const {
        const uint8_t* kr = data + keyOff + (size_t)idx * kKeyRecSize;
        uint32_t fOff = getU32(kr + 0);
        uint16_t fLen = getU16(kr + 12);
        const char* s = (const char*)(data + foldedOff + fOff);
        size_t minLen = std::min<size_t>(fLen, target.size());
        int cmp = memcmp(s, target.data(), minLen);
        if (cmp != 0) return cmp;
        if (fLen < target.size()) return -1;
        if (fLen > target.size()) return 1;
        return 0;
    }

    std::string keyFolded(uint32_t idx) const {
        const uint8_t* kr = data + keyOff + (size_t)idx * kKeyRecSize;
        uint32_t fOff = getU32(kr + 0);
        uint16_t fLen = getU16(kr + 12);
        return std::string((const char*)(data + foldedOff + fOff), fLen);
    }

    std::string keyDisplay(uint32_t idx) const {
        const uint8_t* kr = data + keyOff + (size_t)idx * kKeyRecSize;
        uint32_t dOff = getU32(kr + 4);
        uint16_t dLen = getU16(kr + 14);
        return std::string((const char*)(data + dispOff + dOff), dLen);
    }

    uint32_t keyEntryIdx(uint32_t idx) const {
        const uint8_t* kr = data + keyOff + (size_t)idx * kKeyRecSize;
        return getU32(kr + 8);
    }

    bool keyIsSyn(uint32_t idx) const {
        const uint8_t* kr = data + keyOff + (size_t)idx * kKeyRecSize;
        return (getU32(kr + 16) & 1u) != 0;
    }

    uint32_t lowerBound(const std::string& target) const {
        uint32_t lo = 0, hi = keyCount;
        while (lo < hi) {
            uint32_t mid = lo + (hi - lo) / 2;
            if (compareKeyFolded(mid, target) < 0)
                lo = mid + 1;
            else
                hi = mid;
        }
        return lo;
    }
};

VdictReader::VdictReader() : impl_(new Impl()) {}
VdictReader::~VdictReader() {
    close();
    delete impl_;
}

bool VdictReader::openFile(const std::string& utf8Path, std::string* error) {
    close();
#ifdef _WIN32
    std::wstring wp = utf8ToWide(utf8Path);
    impl_->hFile = CreateFileW(wp.c_str(), GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (impl_->hFile == INVALID_HANDLE_VALUE) {
        if (error) *error = "Cannot open .vdict file";
        return false;
    }
    LARGE_INTEGER szLi;
    if (!GetFileSizeEx(impl_->hFile, &szLi) || szLi.QuadPart < (LONGLONG)kHeaderSize) {
        close();
        if (error) *error = "Invalid .vdict file size";
        return false;
    }
    impl_->fileSize = (size_t)szLi.QuadPart;
    impl_->hMap = CreateFileMappingW(impl_->hFile, NULL, PAGE_READONLY, 0, 0, NULL);
    if (!impl_->hMap) { close(); if (error) *error = "Cannot create file mapping"; return false; }
    impl_->data = (const uint8_t*)MapViewOfFile(impl_->hMap, FILE_MAP_READ, 0, 0, 0);
    if (!impl_->data) { close(); if (error) *error = "Cannot map file view"; return false; }
#else
    impl_->fd = ::open(utf8Path.c_str(), O_RDONLY);
    if (impl_->fd < 0) {
        if (error) *error = "Cannot open .vdict file";
        return false;
    }
    struct stat st;
    if (fstat(impl_->fd, &st) != 0 || st.st_size < (off_t)kHeaderSize) {
        close();
        if (error) *error = "Invalid .vdict file size";
        return false;
    }
    impl_->fileSize = (size_t)st.st_size;
    void* mapped = mmap(NULL, impl_->fileSize, PROT_READ, MAP_SHARED, impl_->fd, 0);
    if (mapped == MAP_FAILED) {
        close();
        if (error) *error = "mmap failed";
        return false;
    }
    impl_->data = (const uint8_t*)mapped;
#endif

    const uint8_t* h = impl_->data;
    if (memcmp(h, kMagic, 8) != 0 || getU32(h + 8) != kFormatVersion) {
        close();
        if (error) *error = "Unrecognized .vdict header";
        return false;
    }
    impl_->entryCount = getU32(h + 12);
    impl_->keyCount = getU32(h + 16);
    impl_->blockCount = getU32(h + 20);
    uint64_t metaOff = getU64(h + 24);
    uint64_t metaSz = getU64(h + 32);
    impl_->keyOff = getU64(h + 40);
    impl_->foldedOff = getU64(h + 48);
    impl_->foldedSize = getU64(h + 56);
    impl_->dispOff = getU64(h + 64);
    impl_->dispSize = getU64(h + 72);
    impl_->entryOff = getU64(h + 80);
    impl_->blockOff = getU64(h + 88);

    // Validate all table bounds inside mapped file
    size_t fs = impl_->fileSize;
    if (metaOff + metaSz > fs ||
        impl_->keyOff + (uint64_t)impl_->keyCount * kKeyRecSize > fs ||
        impl_->foldedOff + impl_->foldedSize > fs ||
        impl_->dispOff + impl_->dispSize > fs ||
        impl_->entryOff + (uint64_t)impl_->entryCount * kEntryRecSize > fs ||
        impl_->blockOff + (uint64_t)impl_->blockCount * kBlockRecSize > fs) {
        close();
        if (error) *error = "Corrupt .vdict table offsets";
        return false;
    }

    // Read JSON metadata
    vjson::Value mj;
    if (metaSz > 0 && vjson::parse(std::string((const char*)(h + metaOff), (size_t)metaSz), mj) && mj.isObject()) {
        info_.dictId = mj["dictId"].stringOr("");
        info_.displayName = mj["displayName"].stringOr("");
        info_.shortName = mj["shortName"].stringOr(info_.displayName);
        info_.badge = mj["badge"].stringOr("");
        info_.sourceLang = mj["sourceLang"].stringOr("");
        info_.targetLang = mj["targetLang"].stringOr("");
        info_.author = mj["author"].stringOr("");
        info_.license = mj["license"].stringOr("");
    }
    info_.entryCount = impl_->entryCount;
    info_.keyCount = impl_->keyCount;
    info_.blockCount = impl_->blockCount;
    return true;
}

void VdictReader::close() {
    impl_->release();
    info_ = VdictHeaderInfo();
}

bool VdictReader::isOpen() const {
    return impl_->data != NULL;
}

bool VdictReader::readEntry(uint32_t entryIdx,
                            std::string& outHeadword,
                            uint8_t& outTypeTag,
                            std::string& outRawText) const {
    outHeadword.clear();
    outRawText.clear();
    outTypeTag = 'm';
    if (!impl_->data || entryIdx >= impl_->entryCount)
        return false;

    const uint8_t* er = impl_->data + impl_->entryOff + (size_t)entryIdx * kEntryRecSize;
    uint32_t blkIdx = getU32(er + 0);
    uint32_t offInBlock = getU32(er + 4);
    uint32_t recordBytes = getU32(er + 8);
    outTypeTag = er[12];

    if (blkIdx >= impl_->blockCount)
        return false;

    const uint8_t* br = impl_->data + impl_->blockOff + (size_t)blkIdx * kBlockRecSize;
    uint64_t compOff = getU64(br + 0);
    uint32_t compSz = getU32(br + 8);
    uint32_t rawSz = getU32(br + 12);
    if (compOff + compSz > impl_->fileSize || offInBlock + recordBytes > rawSz || recordBytes < 2)
        return false;

    std::vector<uint8_t> rawBlock;
    if (!decompressBlockLZ(impl_->data + compOff, compSz, rawSz, rawBlock))
        return false;

    const uint8_t* rec = rawBlock.data() + offInBlock;
    uint16_t hwLen = getU16(rec);
    if (2u + hwLen > recordBytes)
        return false;
    outHeadword.assign((const char*)(rec + 2), hwLen);
    outRawText.assign((const char*)(rec + 2 + hwLen), recordBytes - 2u - hwLen);
    return true;
}

void VdictReader::findExact(const std::string& foldedQuery,
                            size_t maxResults,
                            std::vector<RawKeyMatch>& out) const {
    out.clear();
    if (!impl_->data || foldedQuery.empty() || maxResults == 0)
        return;

    uint32_t pos = impl_->lowerBound(foldedQuery);
    while (pos < impl_->keyCount && out.size() < maxResults) {
        if (impl_->compareKeyFolded(pos, foldedQuery) != 0)
            break;
        RawKeyMatch m;
        m.entryIdx = impl_->keyEntryIdx(pos);
        m.displayWord = impl_->keyDisplay(pos);
        m.foldedKey = foldedQuery;
        m.isSynonym = impl_->keyIsSyn(pos);
        if (m.isSynonym) {
            uint8_t tag = 'm';
            std::string body;
            readEntry(m.entryIdx, m.headword, tag, body);
        } else {
            m.headword = m.displayWord;
        }
        out.push_back(m);
        ++pos;
    }
}

void VdictReader::findPrefix(const std::string& foldedPrefix,
                             size_t maxResults,
                             std::vector<RawKeyMatch>& out) const {
    out.clear();
    if (!impl_->data || foldedPrefix.empty() || maxResults == 0)
        return;

    uint32_t pos = impl_->lowerBound(foldedPrefix);
    while (pos < impl_->keyCount && out.size() < maxResults) {
        const uint8_t* kr = impl_->data + impl_->keyOff + (size_t)pos * kKeyRecSize;
        uint32_t fOff = getU32(kr + 0);
        uint16_t fLen = getU16(kr + 12);
        if (fLen < foldedPrefix.size() ||
            memcmp(impl_->data + impl_->foldedOff + fOff, foldedPrefix.data(), foldedPrefix.size()) != 0)
            break;

        RawKeyMatch m;
        m.entryIdx = getU32(kr + 8);
        m.displayWord = impl_->keyDisplay(pos);
        m.foldedKey.assign((const char*)(impl_->data + impl_->foldedOff + fOff), fLen);
        m.isSynonym = (getU32(kr + 16) & 1u) != 0;
        if (!m.isSynonym) {
            m.headword = m.displayWord;
            out.push_back(m);
        }
        ++pos;
    }
}

void VdictReader::listSample(size_t maxResults, std::vector<RawKeyMatch>& out) const {
    out.clear();
    if (!impl_->data || maxResults == 0)
        return;
    for (uint32_t i = 0; i < impl_->keyCount && out.size() < maxResults; ++i) {
        if (impl_->keyIsSyn(i)) continue;
        RawKeyMatch m;
        m.entryIdx = impl_->keyEntryIdx(i);
        m.displayWord = impl_->keyDisplay(i);
        m.headword = m.displayWord;
        m.foldedKey = impl_->keyFolded(i);
        m.isSynonym = false;
        out.push_back(m);
    }
}

// ============================================================================================================
// Multi-Dictionary DictEngine
// ============================================================================================================

DictEngine::DictEngine() {}
DictEngine::~DictEngine() {}

void DictEngine::setDictionaries(const std::vector<DictionarySpec>& specs) {
    dicts_.clear();
    std::vector<DictionarySpec> ordered = specs;
    std::stable_sort(ordered.begin(), ordered.end(), [](const DictionarySpec& a, const DictionarySpec& b) {
        return a.priority < b.priority;
    });

    for (size_t i = 0; i < ordered.size(); ++i) {
        if (!ordered[i].enabled || ordered[i].vdictPath.empty())
            continue;
        std::unique_ptr<VdictReader> reader(new VdictReader());
        if (!reader->openFile(ordered[i].vdictPath))
            continue;
        std::unique_ptr<OpenDict> od(new OpenDict());
        od->spec = ordered[i];
        od->meta = reader->info();
        if (!ordered[i].dictId.empty()) od->meta.dictId = ordered[i].dictId;
        if (!ordered[i].displayName.empty()) od->meta.displayName = ordered[i].displayName;
        if (!ordered[i].shortName.empty()) od->meta.shortName = ordered[i].shortName;
        if (!ordered[i].badge.empty()) od->meta.badge = ordered[i].badge;
        od->reader = std::move(reader);
        dicts_.push_back(std::move(od));
    }
}

size_t DictEngine::loadedCount() const {
    return dicts_.size();
}

std::vector<LoadedDictionaryMeta> DictEngine::loadedDictionaries() const {
    std::vector<LoadedDictionaryMeta> out;
    out.reserve(dicts_.size());
    for (size_t i = 0; i < dicts_.size(); ++i) {
        const OpenDict& d = *dicts_[i];
        LoadedDictionaryMeta m;
        m.dictId = d.meta.dictId;
        m.displayName = d.meta.displayName;
        m.shortName = d.meta.shortName;
        m.badge = d.meta.badge;
        m.sourceLang = d.meta.sourceLang;
        m.targetLang = d.meta.targetLang;
        m.priority = d.spec.priority;
        m.entryCount = d.meta.entryCount;
        m.keyCount = d.meta.keyCount;
        m.enabled = d.spec.enabled;
        out.push_back(m);
    }
    return out;
}

std::vector<SearchItem> DictEngine::search(const std::string& query,
                                           const std::string& filterDictId,
                                           size_t maxResults) const {
    std::vector<SearchItem> results;
    if (dicts_.empty() || maxResults == 0)
        return results;

    std::string folded = foldForLookup(query);
    std::string lowerQuery = lowercaseUtf8(query);

    // Map lowercased (accent-preserving) canonical headword -> index into results
    // so identical words across multiple dictionaries merge, while distinct Vietnamese words (ma vs ma') stay separate.
    std::unordered_map<std::string, size_t> groupIndex;

    auto appendRef = [&](const OpenDict& d, const RawKeyMatch& m, bool isExactMatch, int baseScore, const std::string& via) {
        std::string canonicalHw = m.headword.empty() ? m.displayWord : m.headword;
        std::string foldedHw = foldForLookup(canonicalHw);
        std::string groupKey = lowercaseUtf8(canonicalHw);
        if (groupKey.empty()) groupKey = m.foldedKey;

        int score = baseScore;
        if (isExactMatch) {
            if (groupKey == lowerQuery) score += 200;
            if (canonicalHw == query) score += 50;
            if (!m.isSynonym) score += 100;
        } else {
            // Shorter prefix hits rank above long compound phrases
            int lenPenalty = (int)std::min<size_t>(foldedHw.size(), 80u);
            score -= lenPenalty;
        }
        // Higher dictionary priority (lower number) gets a slight boost on tie
        score += std::max(0, 50 - d.spec.priority / 10);

        auto it = groupIndex.find(groupKey);
        if (it == groupIndex.end()) {
            SearchItem item;
            item.headword = canonicalHw;
            item.foldedHeadword = foldedHw;
            item.isExact = isExactMatch;
            item.rankScore = score;
            if (!via.empty())
                item.subtitle = "<- " + via;
            HitRef hr;
            hr.dictId = d.meta.dictId;
            hr.dictName = d.meta.displayName;
            hr.shortName = d.meta.shortName;
            hr.badge = d.meta.badge;
            hr.priority = d.spec.priority;
            hr.entryIdx = m.entryIdx;
            hr.matchedVia = via;
            hr.isSynonym = m.isSynonym || !via.empty();
            item.refs.push_back(hr);
            groupIndex[groupKey] = results.size();
            results.push_back(std::move(item));
        } else {
            SearchItem& item = results[it->second];
            if (isExactMatch) item.isExact = true;
            if (score > item.rankScore) {
                item.rankScore = score;
                if (!m.isSynonym && via.empty())
                    item.headword = canonicalHw; // Prefer exact accent/case headword
            }
            for (size_t r = 0; r < item.refs.size(); ++r) {
                if (item.refs[r].dictId == d.meta.dictId && item.refs[r].entryIdx == m.entryIdx)
                    return;
            }
            HitRef hr;
            hr.dictId = d.meta.dictId;
            hr.dictName = d.meta.displayName;
            hr.shortName = d.meta.shortName;
            hr.badge = d.meta.badge;
            hr.priority = d.spec.priority;
            hr.entryIdx = m.entryIdx;
            hr.matchedVia = via;
            hr.isSynonym = m.isSynonym || !via.empty();
            item.refs.push_back(hr);
        }
    };

    if (folded.empty()) {
        // Initial browse state: show a quick sample from the top enabled dictionary matching filter
        for (size_t di = 0; di < dicts_.size(); ++di) {
            const OpenDict& d = *dicts_[di];
            if (!filterDictId.empty() && d.meta.dictId != filterDictId) continue;
            std::vector<RawKeyMatch> sample;
            d.reader->listSample(maxResults, sample);
            for (size_t s = 0; s < sample.size(); ++s)
                appendRef(d, sample[s], false, 100 - (int)s, "");
            if (results.size() >= maxResults)
                break;
        }
        return results;
    }

    // Pass 1: Exact matches (both headword and .syn inflections) across all enabled dicts
    bool anyDirectExact = false;
    std::vector<RawKeyMatch> buf;
    for (size_t di = 0; di < dicts_.size(); ++di) {
        const OpenDict& d = *dicts_[di];
        if (!filterDictId.empty() && d.meta.dictId != filterDictId) continue;
        d.reader->findExact(folded, 32, buf);
        for (size_t m = 0; m < buf.size(); ++m) {
            anyDirectExact = true;
            std::string via = buf[m].isSynonym ? buf[m].displayWord : "";
            appendRef(d, buf[m], true, 1000, via);
        }
    }

    // Pass 2: If no direct exact match anywhere, try English stem inflection fallback (e.g. stopped -> stop)
    if (!anyDirectExact) {
        std::vector<std::string> stems;
        englishInflectionCandidates(folded, stems);
        for (size_t si = 0; si < stems.size(); ++si) {
            for (size_t di = 0; di < dicts_.size(); ++di) {
                const OpenDict& d = *dicts_[di];
                if (!filterDictId.empty() && d.meta.dictId != filterDictId) continue;
                d.reader->findExact(stems[si], 16, buf);
                for (size_t m = 0; m < buf.size(); ++m)
                    appendRef(d, buf[m], true, 850, query);
            }
        }
    }

    // Pass 3: Prefix matches across enabled dictionaries (bounded per dict for guaranteed speed)
    size_t perDictCap = std::max<size_t>(maxResults, 60);
    for (size_t di = 0; di < dicts_.size(); ++di) {
        const OpenDict& d = *dicts_[di];
        if (!filterDictId.empty() && d.meta.dictId != filterDictId) continue;
        d.reader->findPrefix(folded, perDictCap, buf);
        for (size_t m = 0; m < buf.size(); ++m) {
            bool exactLen = (buf[m].foldedKey.size() == folded.size());
            if (!exactLen)
                appendRef(d, buf[m], false, 400, "");
        }
    }

    // Sort results by rankScore descending, then dictionary priority, then folded string
    std::sort(results.begin(), results.end(), [](const SearchItem& a, const SearchItem& b) {
        if (a.isExact != b.isExact) return a.isExact;
        if (a.rankScore != b.rankScore) return a.rankScore > b.rankScore;
        if (a.foldedHeadword != b.foldedHeadword) return a.foldedHeadword < b.foldedHeadword;
        return a.headword < b.headword;
    });

    if (results.size() > maxResults)
        results.resize(maxResults);

    for (size_t i = 0; i < results.size(); ++i) {
        std::sort(results[i].refs.begin(), results[i].refs.end(), [](const HitRef& a, const HitRef& b) {
            if (a.priority != b.priority) return a.priority < b.priority;
            return a.isSynonym < b.isSynonym;
        });
    }

    return results;
}

std::vector<DefinitionSection> DictEngine::loadDefinitions(const SearchItem& item,
                                                           const std::string& filterDictId) const {
    std::vector<DefinitionSection> out;
    for (size_t r = 0; r < item.refs.size(); ++r) {
        const HitRef& hr = item.refs[r];
        if (!filterDictId.empty() && hr.dictId != filterDictId)
            continue;
        for (size_t di = 0; di < dicts_.size(); ++di) {
            const OpenDict& d = *dicts_[di];
            if (d.meta.dictId != hr.dictId) continue;
            std::string hw, raw;
            uint8_t tag = 'm';
            if (d.reader->readEntry(hr.entryIdx, hw, tag, raw)) {
                DefinitionSection sec;
                sec.dictId = d.meta.dictId;
                sec.dictName = d.meta.displayName;
                sec.shortName = d.meta.shortName;
                sec.badge = d.meta.badge;
                sec.headword = hw;
                sec.matchedVia = hr.matchedVia;
                sec.typeTag = tag;
                sec.rawText = raw;
                sec.lines = parseEntryRichText(raw, tag, hw);
                out.push_back(std::move(sec));
            }
            break;
        }
    }
    return out;
}

} // namespace vdict
