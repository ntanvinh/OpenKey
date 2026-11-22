//
//  DictInflate.h
//  VOpenKey
//
//  Portable C++11 decompression (RFC 1951 DEFLATE, RFC 1952 gzip/dictzip, ZIP reader)
//  and fast LZ77 block codec for .vdict compiled dictionaries.
//  Plain ASCII source; zero external library dependencies (no zlib needed).
//
#ifndef DictInflate_h
#define DictInflate_h

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace vdict {

struct ZipEntry {
    std::string name;
    uint16_t method = 0;
    uint32_t crc32 = 0;
    uint64_t compSize = 0;
    uint64_t uncompSize = 0;
    uint64_t localHeaderOffset = 0;
    bool isDir = false;
};

uint32_t computeCrc32(const uint8_t* data, size_t len);

/// Decompress raw RFC 1951 DEFLATE stream. Returns false if malformed or exceeding maxOutBytes.
bool inflateDeflate(const uint8_t* src,
                    size_t srcLen,
                    std::vector<uint8_t>& out,
                    std::string* error = NULL,
                    size_t maxOutBytes = 512u * 1024u * 1024u);

/// Decompress RFC 1952 gzip or StarDict .dz (dictzip) buffer (single or multi-member).
bool decompressGzipOrDictzip(const uint8_t* src,
                             size_t srcLen,
                             std::vector<uint8_t>& out,
                             std::string* error = NULL,
                             size_t maxOutBytes = 512u * 1024u * 1024u);

/// Lists safe regular/dir entries from a ZIP buffer's central directory (rejects path traversal).
bool listZip(const uint8_t* zipData,
             size_t zipLen,
             std::vector<ZipEntry>& outEntries,
             std::string* error = NULL);

/// Extracts one ZIP entry (method 0 store or method 8 deflate) and verifies CRC-32.
bool extractZipEntry(const uint8_t* zipData,
                     size_t zipLen,
                     const ZipEntry& entry,
                     std::vector<uint8_t>& out,
                     std::string* error = NULL,
                     size_t maxOutBytes = 512u * 1024u * 1024u);

/// Fast byte-aligned LZ block compression for .vdict blocks (decode is bounds-checked & ~1 GB/s).
void compressBlockLZ(const uint8_t* src, size_t len, std::vector<uint8_t>& out);

/// Decompresses a block encoded by compressBlockLZ into `out` of exact `expectedOutLen` bytes.
bool decompressBlockLZ(const uint8_t* src,
                       size_t len,
                       size_t expectedOutLen,
                       std::vector<uint8_t>& out);

} // namespace vdict

#endif /* DictInflate_h */
