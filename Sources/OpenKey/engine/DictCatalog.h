//
//  DictCatalog.h
//  VOpenKey
//
//  Portable C++11 reader and validator for the open-source dictionary catalog (dictionaries/catalog.json).
//  Plain ASCII source (UTF-8 strings come from catalog.json or \u escapes).
//
#ifndef DictCatalog_h
#define DictCatalog_h

#include <cstdint>
#include <string>
#include <vector>

namespace vdict {

struct CatalogFile {
    std::string name;
    std::string url;
    uint64_t sizeBytes = 0;
};

struct CatalogEntry {
    std::string id;
    std::string name;
    std::string shortName;
    std::string badge;
    std::string sourceLang;
    std::string targetLang;
    std::string author;
    std::string license;
    std::string description;
    std::string format; // "stardict-zip", "stardict-files", "fvdp-txt"
    int priority = 1000;
    bool recommended = false;
    uint64_t headwordCount = 0;
    uint64_t downloadBytes = 0;
    std::vector<CatalogFile> files;
};

/// True for Anh-Viet and Viet-Anh pairs prioritized at the top of the list.
bool isPrimaryEnglishVietnamese(const CatalogEntry& entry);

/// Parses catalog JSON and stably sorts entries so Anh-Viet / Viet-Anh and lower priority come first.
bool parseCatalog(const std::string& jsonText,
                  std::vector<CatalogEntry>& out,
                  std::string* error = NULL);

/// Finds an entry by ID in `catalog`, or NULL if missing.
const CatalogEntry* findCatalogEntry(const std::vector<CatalogEntry>& catalog,
                                     const std::string& id);

/// Formats byte counts cleanly for display (e.g., "6,7 MB", "370 KB").
std::string formatByteSize(uint64_t bytes);

} // namespace vdict

#endif /* DictCatalog_h */
