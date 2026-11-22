//
//  dict_test.cpp
//  VOpenKey
//
//  Portable C++11 unit + benchmark tests for DictInflate, DictCatalog, and DictStore.
//  Plain ASCII source.
//
#include "DictCatalog.h"
#include "DictInflate.h"
#include "DictStore.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#ifdef _WIN32
#include <direct.h>
#else
#include <sys/stat.h>
#include <unistd.h>
#endif

static int gFailures = 0;
#define CHECK(cond) do { \
    if (!(cond)) { \
        printf("FAIL line %d: %s\n", __LINE__, #cond); \
        gFailures++; \
    } \
} while (0)

namespace {

std::string readFileText(const char* path) {
    std::ifstream f(path, std::ios::binary);
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

void writeU16LE(std::vector<uint8_t>& out, uint16_t v) {
    out.push_back((uint8_t)(v & 0xFF));
    out.push_back((uint8_t)((v >> 8) & 0xFF));
}

void writeU32LE(std::vector<uint8_t>& out, uint32_t v) {
    out.push_back((uint8_t)(v & 0xFF));
    out.push_back((uint8_t)((v >> 8) & 0xFF));
    out.push_back((uint8_t)((v >> 16) & 0xFF));
    out.push_back((uint8_t)((v >> 24) & 0xFF));
}

void writeU32BE(std::vector<uint8_t>& out, uint32_t v) {
    out.push_back((uint8_t)((v >> 24) & 0xFF));
    out.push_back((uint8_t)((v >> 16) & 0xFF));
    out.push_back((uint8_t)((v >> 8) & 0xFF));
    out.push_back((uint8_t)(v & 0xFF));
}

// Wraps raw bytes into an RFC 1951 stored deflate stream (blocks up to 65535 bytes).
std::vector<uint8_t> makeStoredDeflate(const uint8_t* data, size_t len) {
    std::vector<uint8_t> out;
    size_t offset = 0;
    do {
        size_t chunk = len - offset;
        if (chunk > 65535u) chunk = 65535u;
        bool last = (offset + chunk) == len;
        out.push_back(last ? 0x01 : 0x00);
        uint16_t ulen = (uint16_t)chunk;
        uint16_t nlen = (uint16_t)(~ulen);
        writeU16LE(out, ulen);
        writeU16LE(out, nlen);
        out.insert(out.end(), data + offset, data + offset + chunk);
        offset += chunk;
    } while (offset < len);
    return out;
}

// Wraps raw bytes into a valid gzip stream (optionally with dictzip RA extra header + FNAME).
std::vector<uint8_t> makeGzip(const uint8_t* data, size_t len, bool withExtraAndName) {
    std::vector<uint8_t> gz;
    gz.push_back(0x1f);
    gz.push_back(0x8b);
    gz.push_back(0x08); // deflate
    gz.push_back(withExtraAndName ? 0x0C : 0x00); // FEXTRA (4) + FNAME (8)
    writeU32LE(gz, 0); // MTIME
    gz.push_back(0x00); // XFL
    gz.push_back(0x03); // OS Unix
    if (withExtraAndName) {
        // 6-byte RA extra subfield header stub (len=6)
        writeU16LE(gz, 6);
        gz.push_back('R'); gz.push_back('A');
        writeU16LE(gz, 2);
        writeU16LE(gz, 0);
        const char* fn = "test.dict";
        gz.insert(gz.end(), fn, fn + strlen(fn) + 1);
    }
    std::vector<uint8_t> def = makeStoredDeflate(data, len);
    gz.insert(gz.end(), def.begin(), def.end());
    uint32_t crc = vdict::computeCrc32(data, len);
    writeU32LE(gz, crc);
    writeU32LE(gz, (uint32_t)(len & 0xFFFFFFFFu));
    return gz;
}

struct ZipInputFile {
    std::string name;
    std::vector<uint8_t> data;
    uint16_t method; // 0 = store, 8 = deflate (stored deflate)
};

// Minimal valid ZIP builder (supports both stored and deflated entries).
std::vector<uint8_t> buildZip(const std::vector<ZipInputFile>& files) {
    std::vector<uint8_t> zip;
    struct CdRec {
        std::string name;
        uint16_t method;
        uint32_t crc;
        uint32_t compSize;
        uint32_t uncompSize;
        uint32_t localOffset;
    };
    std::vector<CdRec> cds;
    for (size_t i = 0; i < files.size(); ++i) {
        const ZipInputFile& f = files[i];
        uint32_t offset = (uint32_t)zip.size();
        uint32_t crc = vdict::computeCrc32(f.data.empty() ? NULL : &f.data[0], f.data.size());
        std::vector<uint8_t> payload = (f.method == 8)
            ? makeStoredDeflate(f.data.empty() ? NULL : &f.data[0], f.data.size())
            : f.data;
        // Local file header
        writeU32LE(zip, 0x04034b50u);
        writeU16LE(zip, 20);
        writeU16LE(zip, 0x0800); // UTF-8
        writeU16LE(zip, f.method);
        writeU16LE(zip, 0); writeU16LE(zip, 0);
        writeU32LE(zip, crc);
        writeU32LE(zip, (uint32_t)payload.size());
        writeU32LE(zip, (uint32_t)f.data.size());
        writeU16LE(zip, (uint16_t)f.name.size());
        writeU16LE(zip, 0);
        zip.insert(zip.end(), f.name.begin(), f.name.end());
        zip.insert(zip.end(), payload.begin(), payload.end());
        CdRec cd;
        cd.name = f.name;
        cd.method = f.method;
        cd.crc = crc;
        cd.compSize = (uint32_t)payload.size();
        cd.uncompSize = (uint32_t)f.data.size();
        cd.localOffset = offset;
        cds.push_back(cd);
    }
    uint32_t cdStart = (uint32_t)zip.size();
    for (size_t i = 0; i < cds.size(); ++i) {
        const CdRec& cd = cds[i];
        writeU32LE(zip, 0x02014b50u);
        writeU16LE(zip, 20); writeU16LE(zip, 20);
        writeU16LE(zip, 0x0800);
        writeU16LE(zip, cd.method);
        writeU16LE(zip, 0); writeU16LE(zip, 0);
        writeU32LE(zip, cd.crc);
        writeU32LE(zip, cd.compSize);
        writeU32LE(zip, cd.uncompSize);
        writeU16LE(zip, (uint16_t)cd.name.size());
        writeU16LE(zip, 0); writeU16LE(zip, 0);
        writeU16LE(zip, 0); writeU16LE(zip, 0);
        writeU32LE(zip, 0);
        writeU32LE(zip, cd.localOffset);
        zip.insert(zip.end(), cd.name.begin(), cd.name.end());
    }
    uint32_t cdSize = (uint32_t)zip.size() - cdStart;
    writeU32LE(zip, 0x06054b50u);
    writeU16LE(zip, 0); writeU16LE(zip, 0);
    writeU16LE(zip, (uint16_t)cds.size());
    writeU16LE(zip, (uint16_t)cds.size());
    writeU32LE(zip, cdSize);
    writeU32LE(zip, cdStart);
    writeU16LE(zip, 0);
    return zip;
}

struct StarEntryRaw {
    std::string word;
    std::string body;
};

struct StarSynRaw {
    std::string syn;
    uint32_t entryIndex; // Index into StarEntryRaw sorted order!
};

void buildStarDictBuffers(const std::vector<StarEntryRaw>& entriesSorted,
                          const std::vector<StarSynRaw>& synsSorted,
                          const std::string& sameTypeSeq,
                          std::string& outIfo,
                          std::vector<uint8_t>& outIdx,
                          std::vector<uint8_t>& outDict,
                          std::vector<uint8_t>& outSyn) {
    outIdx.clear();
    outDict.clear();
    outSyn.clear();
    for (size_t i = 0; i < entriesSorted.size(); ++i) {
        uint32_t off = (uint32_t)outDict.size();
        const std::string& b = entriesSorted[i].body;
        outDict.insert(outDict.end(), b.begin(), b.end());
        uint32_t sz = (uint32_t)b.size();
        const std::string& w = entriesSorted[i].word;
        outIdx.insert(outIdx.end(), w.begin(), w.end());
        outIdx.push_back('\0');
        writeU32BE(outIdx, off);
        writeU32BE(outIdx, sz);
    }
    for (size_t i = 0; i < synsSorted.size(); ++i) {
        const std::string& s = synsSorted[i].syn;
        outSyn.insert(outSyn.end(), s.begin(), s.end());
        outSyn.push_back('\0');
        writeU32BE(outSyn, synsSorted[i].entryIndex);
    }
    std::ostringstream ifo;
    ifo << "StarDict's dict ifo file\n"
        << "version=2.4.2\n"
        << "bookname=Test Dictionary\n"
        << "wordcount=" << entriesSorted.size() << "\n"
        << "idxfilesize=" << outIdx.size() << "\n";
    if (!sameTypeSeq.empty())
        ifo << "sametypesequence=" << sameTypeSeq << "\n";
    if (!synsSorted.empty())
        ifo << "synwordcount=" << synsSorted.size() << "\n";
    outIfo = ifo.str();
}

std::string makeTempDir() {
#ifdef _WIN32
    char buf[512];
    snprintf(buf, sizeof(buf), "vok_dict_test_%d", (int)rand());
    _mkdir(buf);
    return buf;
#else
    char tmpl[] = "/tmp/vok_dict_test_XXXXXX";
    char* res = mkdtemp(tmpl);
    return res ? res : "/tmp";
#endif
}

} // namespace

static void testCatalog() {
    printf("-- testCatalog\n");
    std::string realJson = readFileText("../dictionaries/catalog.json");
    CHECK(!realJson.empty());
    std::vector<vdict::CatalogEntry> entries;
    std::string err;
    CHECK(vdict::parseCatalog(realJson, entries, &err));
    CHECK(entries.size() >= 20);
    // Top 3 must be Anh-Viet and Viet-Anh
    CHECK(vdict::isPrimaryEnglishVietnamese(entries[0]));
    CHECK(vdict::isPrimaryEnglishVietnamese(entries[1]));
    CHECK(vdict::isPrimaryEnglishVietnamese(entries[2]));
    CHECK(entries[0].sourceLang == "en" && entries[0].targetLang == "vi");
    CHECK(entries[1].sourceLang == "vi" && entries[1].targetLang == "en");
    CHECK(entries[2].sourceLang == "en" && entries[2].targetLang == "vi");
    // Priority ordering ascending
    for (size_t i = 1; i < entries.size(); ++i)
        CHECK(entries[i - 1].priority <= entries[i].priority);
    CHECK(vdict::findCatalogEntry(entries, "en-vi-thichhoc") != NULL);
    CHECK(vdict::findCatalogEntry(entries, "vi-en-ovdp") != NULL);
    CHECK(vdict::findCatalogEntry(entries, "nonexistent") == NULL);

    // Out-of-order catalog gets sorted with Anh-Viet & Viet-Anh first
    const char* unsorted =
        "{\"version\":1,\"dictionaries\":["
        "{\"id\":\"ja-vi\",\"name\":\"JV\",\"shortName\":\"JV\",\"badge\":\"JA->VI\","
        "\"sourceLang\":\"ja\",\"targetLang\":\"vi\",\"author\":\"a\",\"license\":\"GPL\","
        "\"description\":\"d\",\"format\":\"stardict-zip\",\"priority\":10,\"downloadBytes\":100,"
        "\"files\":[{\"name\":\"a.zip\",\"url\":\"https://example.com/a.zip\",\"sizeBytes\":100}]},"
        "{\"id\":\"vi-en\",\"name\":\"VA\",\"shortName\":\"VA\",\"badge\":\"VI->EN\","
        "\"sourceLang\":\"vi\",\"targetLang\":\"en\",\"author\":\"a\",\"license\":\"GPL\","
        "\"description\":\"d\",\"format\":\"stardict-zip\",\"priority\":20,\"downloadBytes\":100,"
        "\"files\":[{\"name\":\"b.zip\",\"url\":\"https://example.com/b.zip\",\"sizeBytes\":100}]},"
        "{\"id\":\"en-vi\",\"name\":\"AV\",\"shortName\":\"AV\",\"badge\":\"EN->VI\","
        "\"sourceLang\":\"en\",\"targetLang\":\"vi\",\"author\":\"a\",\"license\":\"GPL\","
        "\"description\":\"d\",\"format\":\"stardict-zip\",\"priority\":15,\"downloadBytes\":100,"
        "\"files\":[{\"name\":\"c.zip\",\"url\":\"https://example.com/c.zip\",\"sizeBytes\":100}]}"
        "]}";
    std::vector<vdict::CatalogEntry> sorted;
    CHECK(vdict::parseCatalog(unsorted, sorted, &err));
    CHECK(sorted.size() == 3);
    CHECK(sorted[0].id == "en-vi");
    CHECK(sorted[1].id == "vi-en");
    CHECK(sorted[2].id == "ja-vi");

    // Reject invalid HTTP URL & empty files
    std::vector<vdict::CatalogEntry> bad;
    CHECK(!vdict::parseCatalog("{\"version\":1,\"dictionaries\":[{\"id\":\"x\",\"name\":\"x\",\"sourceLang\":\"en\",\"targetLang\":\"vi\",\"format\":\"stardict-zip\",\"downloadBytes\":1,\"files\":[{\"name\":\"a\",\"url\":\"http://insecure.com/a.zip\",\"sizeBytes\":1}]}]}", bad));
    CHECK(!vdict::formatByteSize(6650022).empty());
}

static void testInflateAndZip() {
    printf("-- testInflateAndZip\n");
    const uint8_t vec[] = "123456789";
    CHECK(vdict::computeCrc32(vec, 9) == 0xCBF43926u);

    // Gzip with FEXTRA (dictzip RA) + FNAME roundtrip
    std::string payload;
    for (int i = 0; i < 200; ++i) payload += "Hello VOpenKey AI dictionary! ";
    std::vector<uint8_t> gz = makeGzip((const uint8_t*)payload.data(), payload.size(), true);
    std::vector<uint8_t> out;
    std::string err;
    CHECK(vdict::decompressGzipOrDictzip(&gz[0], gz.size(), out, &err));
    CHECK(out.size() == payload.size());
    CHECK(memcmp(&out[0], payload.data(), payload.size()) == 0);

    // Corrupt CRC must fail
    std::vector<uint8_t> badGz = gz;
    badGz[badGz.size() - 6] ^= 0xFF;
    CHECK(!vdict::decompressGzipOrDictzip(&badGz[0], badGz.size(), out, &err));

    // Fixed Huffman deflate test vector: zlib/deflate output of "hello hello hello!"
    // Compressed via raw deflate fixed Huffman: "hello " + (len=6, dist=6) + "hello!"
    // Let's also verify a real fixed-Huffman stream generated for "ababababab" -> 0x4b,0x4c,0x4a,0x4c,0x42,0x00 (or Python-independent stored+fixed check).
    // Verify precomputed raw deflate (fixed Huffman, BTYPE=01) for "Hello dictionary! Hello dictionary!":
    // Precomputed in standard RFC1951: we can verify gzip + fixed Huffman using known valid bytes for "ABCABCABC":
    // 'A'=65 (0b01110001 rev8 -> Fixed codes 00110000+65 = 01110001), let's test real gzip+deflate in ZIP below as well.
    // Path traversal inside ZIP must be skipped/rejected safely:
    std::vector<ZipInputFile> files;
    ZipInputFile f1; f1.name = "sub/hello.txt"; f1.method = 0;
    f1.data.assign(payload.begin(), payload.begin() + 64);
    ZipInputFile f2; f2.name = "sub/world.ifo"; f2.method = 8;
    f2.data.assign(payload.begin(), payload.end());
    ZipInputFile evil; evil.name = "../escape.txt"; evil.method = 0;
    evil.data.push_back('x');
    files.push_back(f1);
    files.push_back(f2);
    files.push_back(evil);
    std::vector<uint8_t> zip = buildZip(files);
    std::vector<vdict::ZipEntry> entries;
    CHECK(vdict::listZip(&zip[0], zip.size(), entries, &err));
    CHECK(entries.size() == 2); // evil entry excluded!
    std::vector<uint8_t> ex1, ex2;
    CHECK(vdict::extractZipEntry(&zip[0], zip.size(), entries[0], ex1, &err));
    CHECK(ex1 == f1.data);
    CHECK(vdict::extractZipEntry(&zip[0], zip.size(), entries[1], ex2, &err));
    CHECK(ex2 == f2.data);

    // LZ block codec roundtrip on repetitive, binary, and small inputs
    std::vector<uint8_t> comp, decomp;
    vdict::compressBlockLZ((const uint8_t*)payload.data(), payload.size(), comp);
    CHECK(comp.size() < payload.size());
    CHECK(vdict::decompressBlockLZ(&comp[0], comp.size(), payload.size(), decomp));
    CHECK(decomp.size() == payload.size());
    CHECK(memcmp(&decomp[0], payload.data(), payload.size()) == 0);

    // Incompressible data roundtrip
    std::vector<uint8_t> raw(1024);
    uint32_t s = 12345;
    for (size_t i = 0; i < raw.size(); ++i) { s = s * 1664525u + 1013904223u; raw[i] = (uint8_t)(s >> 24); }
    vdict::compressBlockLZ(&raw[0], raw.size(), comp);
    CHECK(vdict::decompressBlockLZ(&comp[0], comp.size(), raw.size(), decomp));
    CHECK(decomp == raw);
    // Truncated compressed stream must fail safely
    if (comp.size() > 2)
        CHECK(!vdict::decompressBlockLZ(&comp[0], comp.size() - 2, raw.size(), decomp));
}

static void testFoldingAndFormatting() {
    printf("-- testFoldingAndFormatting\n");
    // "Từ Điển" precomposed & uppercase
    CHECK(vdict::foldForLookup("  T\xE1\xBB\xAA   \xC4\x90i\xE1\xBB\x83n  ") == "tu dien");
    // "từ điển" NFD decomposed ("tu" + horn U+031B + grave U+0300, d-stroke, "ie" + circumflex U+0302 + hook U+0309 + "n")
    CHECK(vdict::foldForLookup("tu\xCC\x9B\xCC\x80 \xC4\x91ie\xCC\x82\xCC\x89n") == "tu dien");
    CHECK(vdict::lowercaseUtf8("T\xE1\xBB\xAA \xC4\x90I\xE1\xBB\x82N") == "t\xE1\xBB\xAB \xC4\x91i\xE1\xBB\x83n");

    std::vector<std::string> stems;
    vdict::englishInflectionCandidates("stopped", stems);
    bool hasStop = false;
    for (size_t i = 0; i < stems.size(); ++i) if (stems[i] == "stop") hasStop = true;
    CHECK(hasStop);

    // HTML rich-text parsing (thichhoc style)
    std::string html = "<div class=\"hw\">hello <span class=\"ipa\">/h\xC9\x99\xCB\x88lo\xCA\x8A/</span></div>"
                       "<span class=\"pos\">th\xC3\xA1n t\xE1\xBB\xAB</span>"
                       "<ol><li><span class=\"sn\">1.</span> xin ch\xC3\xA0o</li></ol>"
                       "<div class=\"ex\">Hello world! <i>Xin ch\xC3\xA0o th\xE1\xBA\xBF gi\xE1\xBB\x9Bi!</i></div>";
    std::vector<vdict::FormattedLine> htmlLines = vdict::parseEntryRichText(html, 'h', "hello");
    CHECK(htmlLines.size() >= 3);
    bool sawIpa = false, sawPos = false, sawSense = false;
    for (size_t i = 0; i < htmlLines.size(); ++i) {
        if (htmlLines[i].kind == vdict::BlockKind::Phonetic && htmlLines[i].text.find("/h") != std::string::npos) sawIpa = true;
        if (htmlLines[i].kind == vdict::BlockKind::PartOfSpeech && htmlLines[i].text.find("th\xC3\xA1n") != std::string::npos) sawPos = true;
        if (htmlLines[i].kind == vdict::BlockKind::Sense && htmlLines[i].text.find("xin ch") != std::string::npos) sawSense = true;
    }
    CHECK(sawIpa && sawPos && sawSense);

    // OVDP plain-text 'm' parsing
    std::string ovdp = "@hello /he'lou/\n* danh t\xE1\xBB\xAB\n- l\xE1\xBB\x9Di ch\xC3\xA0o\n=say hello+ n\xC3\xB3i l\xE1\xBB\x9Di ch\xC3\xA0o";
    std::vector<vdict::FormattedLine> mLines = vdict::parseEntryRichText(ovdp, 'm', "hello");
    CHECK(mLines.size() >= 4);
    CHECK(mLines[0].kind == vdict::BlockKind::Phonetic && mLines[0].text == "/he'lou/");
    CHECK(mLines[1].kind == vdict::BlockKind::PartOfSpeech);
    CHECK(mLines[2].kind == vdict::BlockKind::Sense && mLines[2].text.find("ch\xC3\xA0o") != std::string::npos);
    CHECK(mLines[3].kind == vdict::BlockKind::Example && mLines[3].text == "say hello" && mLines[3].secondary.find("ch\xC3\xA0o") != std::string::npos);
}

static void testMultiDictAndCompile() {
    printf("-- testMultiDictAndCompile\n");
    std::string dir = makeTempDir();

    // 1. StarDict ZIP with HTML 'h' + .dict.dz + .syn (en-vi priority 10)
    std::vector<StarEntryRaw> enViEntries = {
        {"apple", "<div class=\"hw\">apple <span class=\"ipa\">/\xCB\x88\xC3\xA6p\xC9\x99l/</span></div><span class=\"pos\">noun</span><li>qu\xE1\xBA\xA3 t\xC3\xA1o</li>"},
        {"hello", "<span class=\"pos\">exclamation</span><li>xin ch\xC3\xA0o</li>"},
        {"longword", std::string(45000, 'Z')}, // >32 KB block boundary entry
        {"stop", "<span class=\"pos\">verb</span><li>d\xE1\xBB\xABng l\xE1\xBA\xA1i</li>"}
    };
    std::vector<StarSynRaw> enViSyns = {
        {"stopped", 3},
        {"stopping", 3}
    };
    std::string ifo1;
    std::vector<uint8_t> idx1, dict1, syn1;
    buildStarDictBuffers(enViEntries, enViSyns, "h", ifo1, idx1, dict1, syn1);
    std::vector<uint8_t> dictDz1 = makeGzip(&dict1[0], dict1.size(), true);
    std::vector<uint8_t> synDz1 = makeGzip(&syn1[0], syn1.size(), false);
    std::vector<ZipInputFile> zfiles = {
        {"dict/en_vi.ifo", std::vector<uint8_t>(ifo1.begin(), ifo1.end()), 0},
        {"dict/en_vi.idx", idx1, 0},
        {"dict/en_vi.dict.dz", dictDz1, 0},
        {"dict/en_vi.syn.dz", synDz1, 0}
    };
    std::vector<uint8_t> zipBytes = buildZip(zfiles);

    vdict::CompileMetadata m1;
    m1.dictId = "en-vi-test"; m1.displayName = "Anh - Vi\xE1\xBB\x87t Test";
    m1.shortName = "Anh-Vi\xE1\xBB\x87t"; m1.badge = "EN->VI";
    m1.sourceLang = "en"; m1.targetLang = "vi";
    std::string p1 = dir + "/en-vi.vdict";
    std::string err;
    CHECK(vdict::compileZipBytesToFile(&zipBytes[0], zipBytes.size(), m1, p1, &err));

    // 2. WordNet-style (NO sametypesequence: each entry has 1-byte type tag + payload + optional \0) (en-en priority 50)
    std::string wnBody = "m(n) a greeting";
    wnBody.push_back('\0');
    std::vector<StarEntryRaw> wnEntries = { {"hello", wnBody} };
    std::string ifo2;
    std::vector<uint8_t> idx2, dict2, syn2;
    buildStarDictBuffers(wnEntries, std::vector<StarSynRaw>(), "", ifo2, idx2, dict2, syn2);
    vdict::StarDictMemoryInput in2;
    in2.ifoText = ifo2; in2.idxData = &idx2[0]; in2.idxLen = idx2.size();
    in2.dictData = &dict2[0]; in2.dictLen = dict2.size();
    vdict::CompileMetadata m2;
    m2.dictId = "en-en-wn"; m2.displayName = "WordNet Test";
    m2.shortName = "Anh-Anh"; m2.badge = "EN->EN";
    m2.sourceLang = "en"; m2.targetLang = "en";
    std::string p2 = dir + "/en-en.vdict";
    CHECK(vdict::compileStarDictToFile(in2, m2, p2, &err));

    // 3. FVDP Viet-Anh text (vi-en priority 20)
    std::string fvdp =
        "@xin ch\xC3\xA0o\n* th\xC3\xA1n t\xE1\xBB\xAB\n- hello, hi\n"
        "@ma\n* danh t\xE1\xBB\xAB\n- ghost\n"
        "@m\xC3\xA1\n* danh t\xE1\xBB\xAB\n- cheek / mother\n";
    vdict::CompileMetadata m3;
    m3.dictId = "vi-en-test"; m3.displayName = "Vi\xE1\xBB\x87t - Anh Test";
    m3.shortName = "Vi\xE1\xBB\x87t-Anh"; m3.badge = "VI->EN";
    m3.sourceLang = "vi"; m3.targetLang = "en";
    std::string p3 = dir + "/vi-en.vdict";
    CHECK(vdict::compileFvdpTextToFile(fvdp, m3, p3, &err));

    // Load intentionally unsorted specs -> DictEngine sorts by priority (10, 20, 50)
    vdict::DictEngine engine;
    vdict::DictionarySpec s2; s2.vdictPath = p2; s2.dictId = "en-en-wn"; s2.priority = 50; s2.enabled = true;
    vdict::DictionarySpec s3; s3.vdictPath = p3; s3.dictId = "vi-en-test"; s3.priority = 20; s3.enabled = true;
    vdict::DictionarySpec s1; s1.vdictPath = p1; s1.dictId = "en-vi-test"; s1.priority = 10; s1.enabled = true;
    std::vector<vdict::DictionarySpec> specs;
    specs.push_back(s2); specs.push_back(s3); specs.push_back(s1);
    engine.setDictionaries(specs);
    CHECK(engine.loadedCount() == 3);
    std::vector<vdict::LoadedDictionaryMeta> metas = engine.loadedDictionaries();
    CHECK(metas[0].dictId == "en-vi-test");
    CHECK(metas[1].dictId == "vi-en-test");
    CHECK(metas[2].dictId == "en-en-wn");

    // Multi-dictionary match for "hello": single top hit with refs from en-vi-test then en-en-wn
    std::vector<vdict::SearchItem> hits = engine.search("hello", "", 20);
    CHECK(!hits.empty());
    CHECK(hits[0].headword == "hello" && hits[0].isExact);
    CHECK(hits[0].refs.size() == 2);
    CHECK(hits[0].refs[0].dictId == "en-vi-test");
    CHECK(hits[0].refs[1].dictId == "en-en-wn");
    std::vector<vdict::DefinitionSection> defs = engine.loadDefinitions(hits[0]);
    CHECK(defs.size() == 2);
    CHECK(defs[0].dictId == "en-vi-test");
    CHECK(defs[1].dictId == "en-en-wn" && defs[1].rawText == "(n) a greeting");

    // Synonym lookup: "stopped" -> "stop"
    hits = engine.search("stopped", "", 20);
    CHECK(!hits.empty());
    CHECK(hits[0].headword == "stop");
    CHECK(!hits[0].refs.empty() && hits[0].refs[0].isSynonym);

    // Filter to WordNet only
    hits = engine.search("hello", "en-en-wn", 20);
    CHECK(hits.size() == 1 && hits[0].refs.size() == 1 && hits[0].refs[0].dictId == "en-en-wn");
    CHECK(engine.search("apple", "en-en-wn", 20).empty());

    // Vietnamese folded lookup: "xin chao" finds "xin ch\xC3\xA0o"
    hits = engine.search("xin chao", "", 20);
    CHECK(!hits.empty() && hits[0].headword == "xin ch\xC3\xA0o" && hits[0].isExact);

    // Accent preference: "ma" ranks "ma" before "m\xC3\xA1"; "m\xC3\xA1" ranks "m\xC3\xA1" before "ma"
    hits = engine.search("ma", "", 20);
    CHECK(hits.size() >= 2 && hits[0].headword == "ma");
    hits = engine.search("m\xC3\xA1", "", 20);
    CHECK(hits.size() >= 2 && hits[0].headword == "m\xC3\xA1");

    // Long >32 KB entry across compressed blocks
    hits = engine.search("longword", "", 5);
    CHECK(!hits.empty());
    defs = engine.loadDefinitions(hits[0]);
    CHECK(defs.size() == 1 && defs[0].rawText.size() == 45000 && defs[0].rawText[44999] == 'Z');
}

static void testLargePerformanceBenchmark() {
    printf("-- testLargePerformanceBenchmark (100,000 entries)\n");
    std::string dir = makeTempDir();
    std::vector<StarEntryRaw> entries;
    entries.reserve(100000);
    char wbuf[32];
    char bbuf[128];
    for (int i = 0; i < 100000; ++i) {
        // Zero-padded lexicographic keys: w00000 .. w99999
        snprintf(wbuf, sizeof(wbuf), "word%06d", i);
        snprintf(bbuf, sizeof(bbuf), "@%s /w%d/\n* danh t\xE1\xBB\xAB\n- ngh\xC4\xA9" "a ti\xE1\xBA\xBFng vi\xE1\xBB\x87t s\xE1\xBB\x91 %d", wbuf, i, i);
        entries.push_back({wbuf, bbuf});
    }
    std::string ifo;
    std::vector<uint8_t> idx, dict, syn;
    buildStarDictBuffers(entries, std::vector<StarSynRaw>(), "m", ifo, idx, dict, syn);
    vdict::StarDictMemoryInput in;
    in.ifoText = ifo; in.idxData = &idx[0]; in.idxLen = idx.size();
    in.dictData = &dict[0]; in.dictLen = dict.size();
    vdict::CompileMetadata meta;
    meta.dictId = "bench-100k"; meta.displayName = "Bench 100k";
    meta.shortName = "Bench"; meta.badge = "EN->VI";
    std::string vpath = dir + "/bench100k.vdict";
    std::string err;

    auto t0 = std::chrono::steady_clock::now();
    CHECK(vdict::compileStarDictToFile(in, meta, vpath, &err));
    auto t1 = std::chrono::steady_clock::now();
    double compileMs = std::chrono::duration<double, std::milli>(t1 - t0).count();

    vdict::DictEngine engine;
    vdict::DictionarySpec sb; sb.vdictPath = vpath; sb.dictId = "bench-100k"; sb.priority = 10; sb.enabled = true;
    std::vector<vdict::DictionarySpec> benchSpecs;
    benchSpecs.push_back(sb);
    auto t2 = std::chrono::steady_clock::now();
    engine.setDictionaries(benchSpecs);
    auto t3 = std::chrono::steady_clock::now();
    double openMs = std::chrono::duration<double, std::milli>(t3 - t2).count();
    CHECK(engine.loadedCount() == 1);
    CHECK(engine.loadedDictionaries()[0].entryCount == 100000);
    printf("   compile 100k=%.1f ms, mmap open=%.2f ms\n", compileMs, openMs);
    CHECK(openMs < 100.0);

    auto t4 = std::chrono::steady_clock::now();
    for (int k = 0; k < 100; ++k) {
        snprintf(wbuf, sizeof(wbuf), "word%06d", (k * 997) % 100000);
        std::vector<vdict::SearchItem> res = engine.search(wbuf, "", 50);
        CHECK(!res.empty() && res[0].headword == wbuf && res[0].isExact);
        if (k == 0) {
            std::vector<vdict::DefinitionSection> d = engine.loadDefinitions(res[0]);
            CHECK(d.size() == 1 && d[0].lines.size() >= 3);
        }
    }
    // Also prefix search "word0123"
    std::vector<vdict::SearchItem> pref = engine.search("word0123", "", 50);
    CHECK(pref.size() == 50);
    auto t5 = std::chrono::steady_clock::now();
    double avgSearchMs = std::chrono::duration<double, std::milli>(t5 - t4).count() / 101.0;
    printf("   avg search (100k entries)=%.3f ms\n", avgSearchMs);
    CHECK(avgSearchMs < 25.0);
}

int main() {
    testCatalog();
    testInflateAndZip();
    testFoldingAndFormatting();
    testMultiDictAndCompile();
    testLargePerformanceBenchmark();
    printf("%s\n", gFailures == 0 ? "ALL OK" : "FAILED");
    return gFailures == 0 ? 0 : 1;
}
