//
//  DictInflate.cpp
//  VOpenKey
//
//  Pure C++11 RFC 1951 DEFLATE, RFC 1952 gzip/dictzip, ZIP reader, and fast LZ block codec.
//  Plain ASCII source.
//
#include "DictInflate.h"

#include <algorithm>
#include <cstring>

namespace vdict {

namespace {

uint16_t readU16LE(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

uint32_t readU32LE(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

uint64_t readU64LE(const uint8_t* p) {
    return (uint64_t)readU32LE(p) | ((uint64_t)readU32LE(p + 4) << 32);
}

// ============================================================================================================
// RFC 1951 DEFLATE Decompressor (adapted canonically; handles stored, fixed, and dynamic Huffman blocks)
// ============================================================================================================

struct BitReader {
    const uint8_t* data;
    size_t len;
    size_t pos;
    uint32_t bitBuf;
    int bitCount;

    BitReader(const uint8_t* d, size_t l, size_t start = 0)
        : data(d), len(l), pos(start), bitBuf(0), bitCount(0) {}

    bool readBits(int n, uint32_t& out) {
        while (bitCount < n) {
            if (pos >= len)
                return false;
            bitBuf |= ((uint32_t)data[pos++]) << bitCount;
            bitCount += 8;
        }
        out = bitBuf & ((1u << n) - 1u);
        bitBuf >>= n;
        bitCount -= n;
        return true;
    }

    void alignByte() {
        int drop = bitCount & 7;
        bitBuf >>= drop;
        bitCount -= drop;
    }

    bool readAlignedBytes(uint8_t* dst, size_t n) {
        alignByte();
        while (n > 0 && bitCount >= 8) {
            *dst++ = (uint8_t)(bitBuf & 0xFF);
            bitBuf >>= 8;
            bitCount -= 8;
            --n;
        }
        if (n > 0) {
            if (pos + n > len)
                return false;
            memcpy(dst, data + pos, n);
            pos += n;
        }
        return true;
    }

    size_t alignedBytePos() const {
        return pos - (size_t)(bitCount / 8);
    }
};

static const int kMaxBits = 15;

struct HuffmanTable {
    uint16_t count[kMaxBits + 1];
    uint16_t symbol[320];

    bool build(const int* lengths, int numSyms) {
        for (int b = 0; b <= kMaxBits; ++b)
            count[b] = 0;
        for (int i = 0; i < numSyms; ++i) {
            if (lengths[i] < 0 || lengths[i] > kMaxBits)
                return false;
            count[lengths[i]]++;
        }
        if (count[0] == numSyms)
            return true;
        int left = 1;
        for (int len = 1; len <= kMaxBits; ++len) {
            left <<= 1;
            left -= count[len];
            if (left < 0)
                return false;
        }
        uint16_t offs[kMaxBits + 1];
        offs[1] = 0;
        for (int len = 1; len < kMaxBits; ++len)
            offs[len + 1] = offs[len] + count[len];
        for (int sym = 0; sym < numSyms; ++sym) {
            if (lengths[sym] != 0)
                symbol[offs[lengths[sym]]++] = (uint16_t)sym;
        }
        return true;
    }

    bool decode(BitReader& br, int& outSym) const {
        int code = 0;
        int first = 0;
        int index = 0;
        for (int len = 1; len <= kMaxBits; ++len) {
            uint32_t bit = 0;
            if (!br.readBits(1, bit))
                return false;
            code |= (int)bit;
            int cnt = count[len];
            if (code - cnt < first) {
                outSym = symbol[index + (code - first)];
                return true;
            }
            index += cnt;
            first += cnt;
            first <<= 1;
            code <<= 1;
        }
        return false;
    }
};

void buildFixedTables(HuffmanTable& litLen, HuffmanTable& dist) {
    int lengths[288];
    int i = 0;
    for (; i < 144; ++i) lengths[i] = 8;
    for (; i < 256; ++i) lengths[i] = 9;
    for (; i < 280; ++i) lengths[i] = 7;
    for (; i < 288; ++i) lengths[i] = 8;
    litLen.build(lengths, 288);
    int dlen[32];
    for (i = 0; i < 32; ++i) dlen[i] = 5;
    dist.build(dlen, 32);
}

bool decodeHuffmanBlock(BitReader& br,
                        const HuffmanTable& litLen,
                        const HuffmanTable& dist,
                        std::vector<uint8_t>& out,
                        size_t maxOutBytes,
                        std::string* error) {
    static const uint16_t kLenBase[29] = {
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
    };
    static const uint8_t kLenExtra[29] = {
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
    };
    static const uint16_t kDistBase[30] = {
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
    };
    static const uint8_t kDistExtra[30] = {
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
    };

    for (;;) {
        int sym = 0;
        if (!litLen.decode(br, sym)) {
            if (error) *error = "Truncated deflate symbol";
            return false;
        }
        if (sym < 256) {
            if (out.size() >= maxOutBytes) {
                if (error) *error = "Decompressed size exceeds limit";
                return false;
            }
            out.push_back((uint8_t)sym);
        } else if (sym == 256) {
            return true;
        } else {
            int lidx = sym - 257;
            if (lidx < 0 || lidx >= 29) {
                if (error) *error = "Invalid deflate length code";
                return false;
            }
            uint32_t extra = 0;
            if (kLenExtra[lidx] > 0 && !br.readBits(kLenExtra[lidx], extra)) {
                if (error) *error = "Truncated deflate length extra bits";
                return false;
            }
            size_t matchLen = kLenBase[lidx] + extra;

            int dsym = 0;
            if (!dist.decode(br, dsym) || dsym < 0 || dsym >= 30) {
                if (error) *error = "Invalid deflate distance code";
                return false;
            }
            uint32_t dextra = 0;
            if (kDistExtra[dsym] > 0 && !br.readBits(kDistExtra[dsym], dextra)) {
                if (error) *error = "Truncated deflate distance extra bits";
                return false;
            }
            size_t matchDist = kDistBase[dsym] + dextra;
            if (matchDist == 0 || matchDist > out.size()) {
                if (error) *error = "Invalid deflate back-reference distance";
                return false;
            }
            if (out.size() + matchLen > maxOutBytes) {
                if (error) *error = "Decompressed size exceeds limit";
                return false;
            }
            size_t copyPos = out.size() - matchDist;
            out.reserve(out.size() + matchLen);
            for (size_t i = 0; i < matchLen; ++i)
                out.push_back(out[copyPos + i]);
        }
    }
}

bool decodeDynamicTables(BitReader& br, HuffmanTable& litLen, HuffmanTable& dist, std::string* error) {
    static const uint8_t kCodeOrder[19] = {
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
    };
    uint32_t hlit = 0, hdist = 0, hclen = 0;
    if (!br.readBits(5, hlit) || !br.readBits(5, hdist) || !br.readBits(4, hclen)) {
        if (error) *error = "Truncated dynamic Huffman header";
        return false;
    }
    int nLit = (int)hlit + 257;
    int nDist = (int)hdist + 1;
    int nCode = (int)hclen + 4;
    if (nLit > 286 || nDist > 30) {
        if (error) *error = "Invalid dynamic Huffman counts";
        return false;
    }
    int clens[19];
    for (int i = 0; i < 19; ++i) clens[i] = 0;
    for (int i = 0; i < nCode; ++i) {
        uint32_t v = 0;
        if (!br.readBits(3, v)) {
            if (error) *error = "Truncated dynamic Huffman code lengths";
            return false;
        }
        clens[kCodeOrder[i]] = (int)v;
    }
    HuffmanTable clTable;
    if (!clTable.build(clens, 19)) {
        if (error) *error = "Invalid dynamic code-length table";
        return false;
    }
    int lengths[320];
    int total = nLit + nDist;
    int idx = 0;
    while (idx < total) {
        int sym = 0;
        if (!clTable.decode(br, sym)) {
            if (error) *error = "Truncated dynamic Huffman lengths";
            return false;
        }
        if (sym < 16) {
            lengths[idx++] = sym;
        } else {
            int len = 0;
            uint32_t rep = 0;
            if (sym == 16) {
                if (idx == 0) { if (error) *error = "Bad repeat in dynamic header"; return false; }
                len = lengths[idx - 1];
                if (!br.readBits(2, rep)) return false;
                rep += 3;
            } else if (sym == 17) {
                if (!br.readBits(3, rep)) return false;
                rep += 3;
            } else {
                if (!br.readBits(7, rep)) return false;
                rep += 11;
            }
            if (idx + (int)rep > total) {
                if (error) *error = "Overflow in dynamic Huffman lengths";
                return false;
            }
            while (rep-- > 0)
                lengths[idx++] = len;
        }
    }
    if (lengths[256] == 0) {
        if (error) *error = "Missing end-of-block symbol";
        return false;
    }
    if (!litLen.build(lengths, nLit) || !dist.build(lengths + nLit, nDist)) {
        if (error) *error = "Invalid dynamic Huffman tables";
        return false;
    }
    return true;
}

bool inflateAtOffset(const uint8_t* src,
                     size_t srcLen,
                     size_t startOffset,
                     std::vector<uint8_t>& out,
                     size_t& outConsumed,
                     std::string* error,
                     size_t maxOutBytes) {
    BitReader br(src, srcLen, startOffset);
    HuffmanTable fixedLit, fixedDist;
    bool builtFixed = false;

    for (;;) {
        uint32_t bfinal = 0, btype = 0;
        if (!br.readBits(1, bfinal) || !br.readBits(2, btype)) {
            if (error) *error = "Unexpected end of deflate stream";
            return false;
        }
        if (btype == 0) {
            uint8_t hdr[4];
            if (!br.readAlignedBytes(hdr, 4)) {
                if (error) *error = "Truncated stored deflate block header";
                return false;
            }
            uint16_t ulen = readU16LE(hdr);
            uint16_t nlen = readU16LE(hdr + 2);
            if ((uint16_t)(~ulen) != nlen) {
                if (error) *error = "Corrupt stored deflate block length";
                return false;
            }
            if (out.size() + ulen > maxOutBytes) {
                if (error) *error = "Decompressed size exceeds limit";
                return false;
            }
            size_t oldSz = out.size();
            out.resize(oldSz + ulen);
            if (ulen > 0 && !br.readAlignedBytes(&out[oldSz], ulen)) {
                if (error) *error = "Truncated stored deflate block body";
                return false;
            }
        } else if (btype == 1) {
            if (!builtFixed) {
                buildFixedTables(fixedLit, fixedDist);
                builtFixed = true;
            }
            if (!decodeHuffmanBlock(br, fixedLit, fixedDist, out, maxOutBytes, error))
                return false;
        } else if (btype == 2) {
            HuffmanTable dynLit, dynDist;
            if (!decodeDynamicTables(br, dynLit, dynDist, error))
                return false;
            if (!decodeHuffmanBlock(br, dynLit, dynDist, out, maxOutBytes, error))
                return false;
        } else {
            if (error) *error = "Reserved deflate block type";
            return false;
        }
        if (bfinal)
            break;
    }
    br.alignByte();
    outConsumed = br.alignedBytePos() - startOffset;
    return true;
}

bool isSafeRelativePath(std::string& name) {
    if (name.empty())
        return false;
    for (size_t i = 0; i < name.size(); ++i) {
        if (name[i] == '\0')
            return false;
        if (name[i] == '\\')
            name[i] = '/';
    }
    if (name[0] == '/')
        return false;
    if (name.size() >= 2 && name[1] == ':')
        return false;
    // Reject macOS metadata noise and any ".." path segment
    if (name.compare(0, 9, "__MACOSX/") == 0)
        return false;
    size_t start = 0;
    while (start <= name.size()) {
        size_t slash = name.find('/', start);
        size_t len = (slash == std::string::npos) ? (name.size() - start) : (slash - start);
        if (len == 2 && name[start] == '.' && name[start + 1] == '.')
            return false;
        if (len >= 2 && name[start] == '.' && name[start + 1] == '_')
            return false;
        if (slash == std::string::npos)
            break;
        start = slash + 1;
    }
    return true;
}

} // namespace

uint32_t computeCrc32(const uint8_t* data, size_t len) {
    struct CrcTable {
        uint32_t entries[256];
        CrcTable() {
            for (uint32_t i = 0; i < 256; ++i) {
                uint32_t c = i;
                for (int k = 0; k < 8; ++k)
                    c = (c & 1u) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
                entries[i] = c;
            }
        }
    };
    static const CrcTable table;
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; ++i)
        crc = table.entries[(crc ^ data[i]) & 0xFFu] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}

bool inflateDeflate(const uint8_t* src,
                    size_t srcLen,
                    std::vector<uint8_t>& out,
                    std::string* error,
                    size_t maxOutBytes) {
    out.clear();
    if (!src && srcLen > 0) {
        if (error) *error = "Null input";
        return false;
    }
    size_t consumed = 0;
    return inflateAtOffset(src, srcLen, 0, out, consumed, error, maxOutBytes);
}

bool decompressGzipOrDictzip(const uint8_t* src,
                             size_t srcLen,
                             std::vector<uint8_t>& out,
                             std::string* error,
                             size_t maxOutBytes) {
    out.clear();
    if (!src || srcLen < 18) {
        if (error) *error = "Truncated gzip stream";
        return false;
    }
    size_t pos = 0;
    while (pos < srcLen) {
        if (pos + 10 > srcLen) {
            if (error) *error = "Truncated gzip header";
            return false;
        }
        if (src[pos] != 0x1F || src[pos + 1] != 0x8B || src[pos + 2] != 0x08) {
            if (error) *error = "Invalid gzip magic or method";
            return false;
        }
        uint8_t flg = src[pos + 3];
        if ((flg & 0xE0u) != 0) {
            if (error) *error = "Unsupported gzip flags";
            return false;
        }
        pos += 10;
        if (flg & 0x04u) { // FEXTRA (used by dictzip RA chunk header)
            if (pos + 2 > srcLen) { if (error) *error = "Truncated gzip FEXTRA"; return false; }
            uint16_t xlen = readU16LE(src + pos);
            pos += 2;
            if (pos + xlen > srcLen) { if (error) *error = "Truncated gzip FEXTRA payload"; return false; }
            pos += xlen;
        }
        if (flg & 0x08u) { // FNAME
            while (pos < srcLen && src[pos] != 0) ++pos;
            if (pos >= srcLen) { if (error) *error = "Truncated gzip FNAME"; return false; }
            ++pos;
        }
        if (flg & 0x10u) { // FCOMMENT
            while (pos < srcLen && src[pos] != 0) ++pos;
            if (pos >= srcLen) { if (error) *error = "Truncated gzip FCOMMENT"; return false; }
            ++pos;
        }
        if (flg & 0x02u) { // FHCRC
            if (pos + 2 > srcLen) { if (error) *error = "Truncated gzip FHCRC"; return false; }
            pos += 2;
        }

        size_t memberOutStart = out.size();
        size_t consumed = 0;
        if (!inflateAtOffset(src, srcLen, pos, out, consumed, error, maxOutBytes))
            return false;
        pos += consumed;
        if (pos + 8 > srcLen) {
            if (error) *error = "Truncated gzip trailer";
            return false;
        }
        uint32_t expectedCrc = readU32LE(src + pos);
        uint32_t expectedSize = readU32LE(src + pos + 4);
        pos += 8;

        size_t memberLen = out.size() - memberOutStart;
        uint32_t actualCrc = computeCrc32(memberLen > 0 ? &out[memberOutStart] : NULL, memberLen);
        if (actualCrc != expectedCrc || (uint32_t)(memberLen & 0xFFFFFFFFu) != expectedSize) {
            if (error) *error = "Gzip CRC or size mismatch";
            return false;
        }
    }
    return true;
}

bool listZip(const uint8_t* zipData,
             size_t zipLen,
             std::vector<ZipEntry>& outEntries,
             std::string* error) {
    outEntries.clear();
    if (!zipData || zipLen < 22) {
        if (error) *error = "File is too small to be a ZIP archive";
        return false;
    }
    size_t maxBack = zipLen < (65535u + 22u) ? zipLen : (65535u + 22u);
    size_t eocdPos = (size_t)-1;
    for (size_t off = 22; off <= maxBack; ++off) {
        size_t p = zipLen - off;
        if (readU32LE(zipData + p) == 0x06054b50u) {
            uint16_t commentLen = readU16LE(zipData + p + 20);
            if (p + 22u + commentLen == zipLen) {
                eocdPos = p;
                break;
            }
        }
    }
    if (eocdPos == (size_t)-1) {
        if (error) *error = "ZIP end-of-central-directory not found";
        return false;
    }

    uint64_t cdCount = readU16LE(zipData + eocdPos + 10);
    uint64_t cdSize = readU32LE(zipData + eocdPos + 12);
    uint64_t cdOffset = readU32LE(zipData + eocdPos + 16);

    // Check ZIP64 EOCD locator (20 bytes immediately preceding EOCD)
    if (eocdPos >= 20 && readU32LE(zipData + eocdPos - 20) == 0x07064b50u) {
        uint64_t z64Off = readU64LE(zipData + eocdPos - 12);
        if (z64Off + 56 <= eocdPos && readU32LE(zipData + z64Off) == 0x06064b50u) {
            cdCount = readU64LE(zipData + z64Off + 32);
            cdSize = readU64LE(zipData + z64Off + 40);
            cdOffset = readU64LE(zipData + z64Off + 48);
        }
    }

    if (cdOffset + cdSize > eocdPos) {
        if (error) *error = "ZIP central directory out of bounds";
        return false;
    }

    size_t pos = (size_t)cdOffset;
    size_t end = (size_t)(cdOffset + cdSize);
    for (uint64_t i = 0; i < cdCount && pos + 46 <= end; ++i) {
        if (readU32LE(zipData + pos) != 0x02014b50u) {
            if (error) *error = "Corrupt ZIP central directory record";
            return false;
        }
        uint16_t method = readU16LE(zipData + pos + 10);
        uint32_t crc = readU32LE(zipData + pos + 16);
        uint64_t comp = readU32LE(zipData + pos + 20);
        uint64_t uncomp = readU32LE(zipData + pos + 24);
        uint16_t fnLen = readU16LE(zipData + pos + 28);
        uint16_t exLen = readU16LE(zipData + pos + 30);
        uint16_t cmLen = readU16LE(zipData + pos + 32);
        uint64_t localOff = readU32LE(zipData + pos + 42);
        if (pos + 46 + fnLen + exLen + cmLen > end) {
            if (error) *error = "Truncated ZIP central directory name";
            return false;
        }
        std::string name((const char*)(zipData + pos + 46), fnLen);

        // Parse ZIP64 extra field if needed
        const uint8_t* ex = zipData + pos + 46 + fnLen;
        size_t exPos = 0;
        while (exPos + 4 <= exLen) {
            uint16_t tag = readU16LE(ex + exPos);
            uint16_t sz = readU16LE(ex + exPos + 2);
            exPos += 4;
            if (exPos + sz > exLen) break;
            if (tag == 0x0001u) {
                size_t p64 = 0;
                if (uncomp == 0xFFFFFFFFu && p64 + 8 <= sz) { uncomp = readU64LE(ex + exPos + p64); p64 += 8; }
                if (comp == 0xFFFFFFFFu && p64 + 8 <= sz) { comp = readU64LE(ex + exPos + p64); p64 += 8; }
                if (localOff == 0xFFFFFFFFu && p64 + 8 <= sz) { localOff = readU64LE(ex + exPos + p64); }
            }
            exPos += sz;
        }

        pos += 46 + fnLen + exLen + cmLen;

        if (!isSafeRelativePath(name))
            continue; // Safely skip unsafe or hidden AppleDouble entries

        ZipEntry ze;
        ze.name = name;
        ze.method = method;
        ze.crc32 = crc;
        ze.compSize = comp;
        ze.uncompSize = uncomp;
        ze.localHeaderOffset = localOff;
        ze.isDir = !name.empty() && name[name.size() - 1] == '/';
        outEntries.push_back(ze);
    }
    return true;
}

bool extractZipEntry(const uint8_t* zipData,
                     size_t zipLen,
                     const ZipEntry& entry,
                     std::vector<uint8_t>& out,
                     std::string* error,
                     size_t maxOutBytes) {
    out.clear();
    if (entry.isDir)
        return true;
    if (!zipData || entry.localHeaderOffset + 30 > zipLen) {
        if (error) *error = "ZIP entry offset out of bounds";
        return false;
    }
    if (entry.uncompSize > maxOutBytes) {
        if (error) *error = "ZIP entry exceeds maximum output limit";
        return false;
    }
    const uint8_t* lfh = zipData + entry.localHeaderOffset;
    if (readU32LE(lfh) != 0x04034b50u) {
        if (error) *error = "Invalid ZIP local file header";
        return false;
    }
    uint16_t fnLen = readU16LE(lfh + 26);
    uint16_t exLen = readU16LE(lfh + 28);
    uint64_t dataOff = entry.localHeaderOffset + 30u + fnLen + exLen;
    if (dataOff + entry.compSize > zipLen) {
        if (error) *error = "ZIP entry payload out of bounds";
        return false;
    }
    const uint8_t* payload = zipData + dataOff;
    if (entry.method == 0) {
        if (entry.compSize > maxOutBytes) {
            if (error) *error = "ZIP stored entry exceeds limit";
            return false;
        }
        out.assign(payload, payload + entry.compSize);
    } else if (entry.method == 8) {
        out.reserve(entry.uncompSize > 0 ? (size_t)entry.uncompSize : (size_t)entry.compSize);
        if (!inflateDeflate(payload, (size_t)entry.compSize, out, error, maxOutBytes))
            return false;
    } else {
        if (error) *error = "Unsupported ZIP compression method";
        return false;
    }
    uint32_t actualCrc = computeCrc32(out.empty() ? NULL : &out[0], out.size());
    if (actualCrc != entry.crc32 || out.size() != entry.uncompSize) {
        out.clear();
        if (error) *error = "ZIP entry CRC or size mismatch";
        return false;
    }
    return true;
}

// ============================================================================================================
// Fast Byte-Aligned LZ77 Block Codec for .vdict Blocks
// ============================================================================================================

namespace {

inline uint32_t hash4(const uint8_t* p) {
    uint32_t v = (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
    return (v * 2654435761u) >> 19; // 13-bit index (8192 entries)
}

void appendExtendedLen(std::vector<uint8_t>& out, size_t extra) {
    while (extra >= 255) {
        out.push_back(255);
        extra -= 255;
    }
    out.push_back((uint8_t)extra);
}

} // namespace

void compressBlockLZ(const uint8_t* src, size_t len, std::vector<uint8_t>& out) {
    out.clear();
    if (len == 0)
        return;

    out.reserve(len + 16);
    static const size_t kHashSize = 8192;
    uint32_t hashTable[kHashSize];
    memset(hashTable, 0xFF, sizeof(hashTable));

    size_t anchor = 0;
    size_t ip = 0;
    size_t limit = (len >= 12) ? (len - 8) : 0;

    while (ip < limit) {
        uint32_t h = hash4(src + ip);
        uint32_t ref = hashTable[h];
        hashTable[h] = (uint32_t)ip;

        size_t dist = (ref != 0xFFFFFFFFu && ip > ref) ? (ip - ref) : 0;
        if (dist >= 1 && dist <= 65535 && memcmp(src + ref, src + ip, 4) == 0) {
            // Emit token + pending literals + match
            size_t matchLen = 4;
            while (ip + matchLen < len && src[ref + matchLen] == src[ip + matchLen])
                ++matchLen;

            size_t litLen = ip - anchor;
            size_t mlCode = matchLen - 4;
            uint8_t tok = (uint8_t)((std::min<size_t>(litLen, 15) << 4) | std::min<size_t>(mlCode, 15));
            out.push_back(tok);
            if (litLen >= 15)
                appendExtendedLen(out, litLen - 15);
            if (litLen > 0)
                out.insert(out.end(), src + anchor, src + ip);

            out.push_back((uint8_t)(dist & 0xFF));
            out.push_back((uint8_t)((dist >> 8) & 0xFF));
            if (mlCode >= 15)
                appendExtendedLen(out, mlCode - 15);

            ip += matchLen;
            anchor = ip;
        } else {
            ++ip;
        }
    }

    // Final literals sequence (no trailing match)
    size_t lastLit = len - anchor;
    uint8_t tok = (uint8_t)(std::min<size_t>(lastLit, 15) << 4);
    out.push_back(tok);
    if (lastLit >= 15)
        appendExtendedLen(out, lastLit - 15);
    if (lastLit > 0)
        out.insert(out.end(), src + anchor, src + len);
}

bool decompressBlockLZ(const uint8_t* src,
                       size_t len,
                       size_t expectedOutLen,
                       std::vector<uint8_t>& out) {
    out.clear();
    if (expectedOutLen == 0)
        return len == 0;
    if (!src || len == 0)
        return false;

    out.reserve(expectedOutLen);
    size_t ip = 0;

    while (ip < len) {
        uint8_t tok = src[ip++];
        size_t litLen = (tok >> 4) & 0x0Fu;
        if (litLen == 15) {
            uint8_t b = 255;
            while (b == 255) {
                if (ip >= len) return false;
                b = src[ip++];
                litLen += b;
            }
        }
        if (ip + litLen > len || out.size() + litLen > expectedOutLen)
            return false;
        if (litLen > 0) {
            out.insert(out.end(), src + ip, src + ip + litLen);
            ip += litLen;
        }
        if (ip == len)
            break; // End of compressed stream cleanly after final literals

        if (ip + 2 > len)
            return false;
        size_t dist = (size_t)src[ip] | ((size_t)src[ip + 1] << 8);
        ip += 2;
        if (dist == 0 || dist > out.size())
            return false;

        size_t matchLen = tok & 0x0Fu;
        if (matchLen == 15) {
            uint8_t b = 255;
            while (b == 255) {
                if (ip >= len) return false;
                b = src[ip++];
                matchLen += b;
            }
        }
        matchLen += 4;
        if (out.size() + matchLen > expectedOutLen)
            return false;

        size_t matchPos = out.size() - dist;
        for (size_t i = 0; i < matchLen; ++i)
            out.push_back(out[matchPos + i]);
    }

    return out.size() == expectedOutLen;
}

} // namespace vdict
