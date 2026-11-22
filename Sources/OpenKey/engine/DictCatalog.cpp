//
//  DictCatalog.cpp
//  VOpenKey
//
//  See DictCatalog.h. Plain ASCII source.
//
#include "DictCatalog.h"
#include "MiniJson.h"

#include <algorithm>
#include <cstdio>

namespace vdict {

namespace {

bool isSafeId(const std::string& s) {
    if (s.empty() || s.size() > 64)
        return false;
    for (size_t i = 0; i < s.size(); ++i) {
        char c = s[i];
        bool ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_';
        if (!ok)
            return false;
    }
    return true;
}

bool isValidFormat(const std::string& f) {
    return f == "stardict-zip" || f == "stardict-files" || f == "fvdp-txt";
}

bool isAllowedDownloadUrl(const std::string& url) {
    if (url.compare(0, 8, "https://") == 0)
        return url.size() > 8;
    if (url.compare(0, 17, "http://127.0.0.1:") == 0 || url.compare(0, 17, "http://127.0.0.1/") == 0)
        return true;
    if (url.compare(0, 17, "http://localhost:") == 0 || url.compare(0, 17, "http://localhost/") == 0)
        return true;
    return false;
}

} // namespace

bool isPrimaryEnglishVietnamese(const CatalogEntry& entry) {
    return (entry.sourceLang == "en" && entry.targetLang == "vi") ||
           (entry.sourceLang == "vi" && entry.targetLang == "en");
}

bool parseCatalog(const std::string& jsonText,
                  std::vector<CatalogEntry>& out,
                  std::string* error) {
    out.clear();
    vjson::Value root;
    if (!vjson::parse(jsonText, root) || !root.isObject()) {
        if (error) *error = "Invalid catalog JSON";
        return false;
    }
    if (root.has("version") && (int)root["version"].asNumber(0) != 1) {
        if (error) *error = "Unsupported catalog version";
        return false;
    }
    const vjson::Value& dicts = root["dictionaries"];
    if (!dicts.isArray() || dicts.items().empty()) {
        if (error) *error = "Missing dictionaries array";
        return false;
    }

    std::vector<CatalogEntry> parsed;
    parsed.reserve(dicts.items().size());
    for (size_t i = 0; i < dicts.items().size(); ++i) {
        const vjson::Value& item = dicts.items()[i];
        if (!item.isObject()) {
            if (error) *error = "Catalog entry is not an object";
            return false;
        }
        CatalogEntry e;
        e.id = item["id"].stringOr("");
        e.name = item["name"].stringOr("");
        e.shortName = item["shortName"].stringOr(e.name);
        e.badge = item["badge"].stringOr("");
        e.sourceLang = item["sourceLang"].stringOr("");
        e.targetLang = item["targetLang"].stringOr("");
        e.author = item["author"].stringOr("");
        e.license = item["license"].stringOr("");
        e.description = item["description"].stringOr("");
        e.format = item["format"].stringOr("");
        e.priority = (int)item["priority"].asNumber(1000);
        e.recommended = item["recommended"].asBool(false);
        double hw = item["headwordCount"].asNumber(0);
        double dl = item["downloadBytes"].asNumber(0);
        e.headwordCount = hw > 0 ? (uint64_t)hw : 0;
        e.downloadBytes = dl > 0 ? (uint64_t)dl : 0;

        if (!isSafeId(e.id) || e.name.empty() || !isValidFormat(e.format) || e.downloadBytes == 0) {
            if (error) *error = "Invalid dictionary metadata for: " + e.id;
            return false;
        }
        for (size_t j = 0; j < parsed.size(); ++j) {
            if (parsed[j].id == e.id) {
                if (error) *error = "Duplicate catalog id: " + e.id;
                return false;
            }
        }
        const vjson::Value& files = item["files"];
        if (!files.isArray() || files.items().empty()) {
            if (error) *error = "Missing files for: " + e.id;
            return false;
        }
        for (size_t f = 0; f < files.items().size(); ++f) {
            const vjson::Value& fv = files.items()[f];
            CatalogFile cf;
            cf.name = fv["name"].stringOr("");
            cf.url = fv["url"].stringOr("");
            double sb = fv["sizeBytes"].asNumber(0);
            cf.sizeBytes = sb > 0 ? (uint64_t)sb : 0;
            if (cf.name.empty() || !isAllowedDownloadUrl(cf.url) || cf.sizeBytes == 0) {
                if (error) *error = "Invalid file entry in: " + e.id;
                return false;
            }
            e.files.push_back(cf);
        }
        parsed.push_back(e);
    }

    std::stable_sort(parsed.begin(), parsed.end(), [](const CatalogEntry& a, const CatalogEntry& b) {
        bool pa = isPrimaryEnglishVietnamese(a);
        bool pb = isPrimaryEnglishVietnamese(b);
        if (pa != pb)
            return pa;
        return a.priority < b.priority;
    });

    out.swap(parsed);
    return true;
}

const CatalogEntry* findCatalogEntry(const std::vector<CatalogEntry>& catalog,
                                     const std::string& id) {
    for (size_t i = 0; i < catalog.size(); ++i) {
        if (catalog[i].id == id)
            return &catalog[i];
    }
    return NULL;
}

std::string formatByteSize(uint64_t bytes) {
    char buf[64];
    if (bytes < 1024u) {
        snprintf(buf, sizeof(buf), "%llu B", (unsigned long long)bytes);
    } else if (bytes < 1024u * 1024u) {
        double kb = (double)bytes / 1024.0;
        snprintf(buf, sizeof(buf), "%.0f KB", kb);
    } else if (bytes < 1024ULL * 1024ULL * 1024ULL) {
        double mb = (double)bytes / (1024.0 * 1024.0);
        snprintf(buf, sizeof(buf), "%.1f MB", mb);
    } else {
        double gb = (double)bytes / (1024.0 * 1024.0 * 1024.0);
        snprintf(buf, sizeof(buf), "%.2f GB", gb);
    }
    return buf;
}

} // namespace vdict
