//
//  DictStore.h
//  VOpenKey
//
//  Portable C++11 offline dictionary compiler, memory-mapped reader, multi-dictionary lookup engine,
//  and rich-text entry parser for StarDict (.ifo/.idx/.dict[.dz]/.syn[.dz]) and FVDP (.txt) datasets.
//  Plain ASCII source.
//
#ifndef DictStore_h
#define DictStore_h

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace vdict {

/// UTF-8 accent- and case-folded normalization (lowercases ASCII & Latin/Vietnamese, maps d/D->d,
/// strips combining marks & Vietnamese tone/shape, collapses spaces).
std::string foldForLookup(const std::string& utf8Text);

/// UTF-8 lowercase preserving accents/tones (for ranking exact accented hits above unaccented ones).
std::string lowercaseUtf8(const std::string& utf8Text);

/// Generates plausible English base forms when exact match misses (e.g., stopped->stop, studies->study).
void englishInflectionCandidates(const std::string& foldedWord, std::vector<std::string>& out);

/// Structured line blocks parsed from StarDict 'h' (HTML) or 'm' / FVDP markup.
enum class BlockKind : uint8_t {
    Headword = 0,
    Phonetic = 1,
    PartOfSpeech = 2,
    Sense = 3,
    SubSense = 4,
    Example = 5,
    Note = 6,
    Plain = 7
};

struct FormattedLine {
    BlockKind kind = BlockKind::Plain;
    std::string text;
    std::string secondary; // Optional translation/note (e.g. Vietnamese part of an example line)
    std::string marker;    // Optional bullet/number
};

/// Parses a raw dictionary entry (typeTag: 'h', 'm', 'x', 'g', 't') into clean display lines.
std::vector<FormattedLine> parseEntryRichText(const std::string& raw,
                                              uint8_t typeTag,
                                              const std::string& headword);

struct CompileMetadata {
    std::string dictId;
    std::string displayName;
    std::string shortName;
    std::string badge;
    std::string sourceLang;
    std::string targetLang;
    std::string author;
    std::string license;
};

struct StarDictMemoryInput {
    std::string ifoText;
    const uint8_t* idxData = NULL;
    size_t idxLen = 0;
    const uint8_t* dictData = NULL; // May already be decompressed or raw .dict.dz bytes
    size_t dictLen = 0;
    const uint8_t* synData = NULL;  // Optional .syn or .syn.dz bytes
    size_t synLen = 0;
};

/// Compiles StarDict buffers (auto-decompressing .dict.dz/.syn.dz if gzipped) into an atomic .vdict file.
bool compileStarDictToFile(const StarDictMemoryInput& input,
                           const CompileMetadata& meta,
                           const std::string& outVdictPath,
                           std::string* error = NULL);

/// Extracts StarDict files from a .zip buffer (even inside a nested folder) and compiles to .vdict.
bool compileZipBytesToFile(const uint8_t* zipData,
                           size_t zipLen,
                           const CompileMetadata& meta,
                           const std::string& outVdictPath,
                           std::string* error = NULL);

/// Compiles an FVDP plain-text dictionary (@headword /ipa/\n* pos\n- meaning) into a .vdict file.
bool compileFvdpTextToFile(const std::string& fvdpText,
                           const CompileMetadata& meta,
                           const std::string& outVdictPath,
                           std::string* error = NULL);

/// Scans a directory for matching StarDict (.ifo/.idx/.dict[.dz]/.syn[.dz]) files and compiles to .vdict.
bool compileDirectoryToFile(const std::string& utf8DirPath,
                            const CompileMetadata& meta,
                            const std::string& outVdictPath,
                            std::string* error = NULL);

/// Compiles from an arbitrary local file (.zip, .ifo in a folder, folder path, or FVDP .txt) into .vdict.
bool compileLocalPathToFile(const std::string& utf8Path,
                            const CompileMetadata& meta,
                            const std::string& outVdictPath,
                            std::string* error = NULL);

struct VdictHeaderInfo {
    std::string dictId;
    std::string displayName;
    std::string shortName;
    std::string badge;
    std::string sourceLang;
    std::string targetLang;
    std::string author;
    std::string license;
    uint32_t entryCount = 0;
    uint32_t keyCount = 0;
    uint32_t blockCount = 0;
};

struct RawKeyMatch {
    uint32_t entryIdx = 0;
    std::string displayWord;   // Matched key text (could be synonym)
    std::string headword;      // Canonical primary headword of entryIdx
    std::string foldedKey;
    bool isSynonym = false;
};

/// Fast memory-mapped read-only .vdict reader. Thread-safe once opened when block cache is not shared,
/// or externally synchronized.
class VdictReader {
public:
    VdictReader();
    ~VdictReader();
    VdictReader(const VdictReader&) = delete;
    VdictReader& operator=(const VdictReader&) = delete;

    bool openFile(const std::string& utf8Path, std::string* error = NULL);
    void close();
    bool isOpen() const;

    const VdictHeaderInfo& info() const { return info_; }

    /// Finds exact matches for `foldedQuery` (both headwords and synonyms).
    void findExact(const std::string& foldedQuery,
                   size_t maxResults,
                   std::vector<RawKeyMatch>& out) const;

    /// Finds prefix matches for `foldedPrefix` (sorted lexicographically by foldedKey).
    void findPrefix(const std::string& foldedPrefix,
                    size_t maxResults,
                    std::vector<RawKeyMatch>& out) const;

    /// Returns first `maxResults` primary headwords (for empty search state).
    void listSample(size_t maxResults, std::vector<RawKeyMatch>& out) const;

    /// Decodes a single entry payload (decompressing only its 32 KB block, cached in a small LRU).
    bool readEntry(uint32_t entryIdx,
                   std::string& outHeadword,
                   uint8_t& outTypeTag,
                   std::string& outRawText) const;

private:
    struct Impl;
    Impl* impl_;
    VdictHeaderInfo info_;
};

struct DictionarySpec {
    std::string vdictPath;
    std::string dictId;      // Overrides metadata if non-empty
    std::string displayName; // Overrides metadata if non-empty
    std::string shortName;
    std::string badge;
    int priority = 1000;
    bool enabled = true;
};

struct HitRef {
    std::string dictId;
    std::string dictName;
    std::string shortName;
    std::string badge;
    int priority = 1000;
    uint32_t entryIdx = 0;
    std::string matchedVia; // Non-empty when matched through synonym/inflection
    bool isSynonym = false;
};

struct SearchItem {
    std::string headword;
    std::string foldedHeadword;
    std::string subtitle;    // e.g. "<- stopped" or secondary matched dict summary
    bool isExact = false;
    int rankScore = 0;       // Higher = better match
    std::vector<HitRef> refs; // Ordered by dictionary priority (Anh-Viet, Viet-Anh first)
};

struct DefinitionSection {
    std::string dictId;
    std::string dictName;
    std::string shortName;
    std::string badge;
    std::string headword;
    std::string matchedVia;
    uint8_t typeTag = 'm';
    std::string rawText;
    std::vector<FormattedLine> lines;
};

struct LoadedDictionaryMeta {
    std::string dictId;
    std::string displayName;
    std::string shortName;
    std::string badge;
    std::string sourceLang;
    std::string targetLang;
    int priority = 1000;
    uint32_t entryCount = 0;
    uint32_t keyCount = 0;
    bool enabled = true;
};

/// Multi-dictionary coordinator that maps all enabled .vdict files and provides sub-millisecond search.
class DictEngine {
public:
    DictEngine();
    ~DictEngine();
    DictEngine(const DictEngine&) = delete;
    DictEngine& operator=(const DictEngine&) = delete;

    /// Replaces the loaded set of dictionaries, sorted by (priority, originalIndex).
    void setDictionaries(const std::vector<DictionarySpec>& specs);

    size_t loadedCount() const;
    std::vector<LoadedDictionaryMeta> loadedDictionaries() const;

    /// Multi-dictionary search. If `filterDictId` is non-empty, searches only that dictionary.
    /// Automatically merges headword matches across dictionaries and selects exact matches first.
    std::vector<SearchItem> search(const std::string& query,
                                   const std::string& filterDictId,
                                   size_t maxResults = 80) const;

    /// Loads & parses definitions for all refs in `item` (or filtered by `filterDictId`).
    std::vector<DefinitionSection> loadDefinitions(const SearchItem& item,
                                                   const std::string& filterDictId = "") const;

private:
    struct OpenDict {
        DictionarySpec spec;
        VdictHeaderInfo meta;
        std::unique_ptr<VdictReader> reader;
    };
    std::vector<std::unique_ptr<OpenDict> > dicts_;
};

} // namespace vdict

#endif /* DictStore_h */
