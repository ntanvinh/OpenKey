//
//  SnippetStore.cpp
//  VOpenKey
//
#include "SnippetStore.h"
#include "MiniJson.h"

#include <algorithm>

namespace vsnippet {

Store::Store() : needsSave_(false), unreadable_(false), indexStale_(true) {}

static Snippet snippetFromJson(const vjson::Value& v, bool& ok) {
    Snippet s;
    ok = false;
    if (!v.isObject() || !v["id"].isString() || v["id"].asString().empty())
        return s;
    s.id = v["id"].asString();
    s.title = v["title"].stringOr("");
    s.keywords = v["keywords"].stringOr("");
    s.content = v["content"].stringOr("");
    //a file edited by hand may hold anything: the numbers are kept inside what they mean before they become an int
    if (v["useCount"].isNumber()) {
        double count = v["useCount"].asNumber();
        s.useCount = count >= 1e9 ? 1000000000 : (count > 0 ? (int)count : 0);
    }
    if (v["lastUsed"].isNumber()) {
        double last = v["lastUsed"].asNumber();
        s.lastUsed = last > 0 && last < 1e12 ? last : 0;
    }
    ok = true;
    return s;
}

std::vector<Snippet> Store::readList(const std::string& text, bool builtInOnly) {
    std::vector<Snippet> list;
    vjson::Value root;
    if (!vjson::parse(text, root) || !root.isObject() || !root["snippets"].isArray())
        return list;
    for (size_t i = 0; i < root["snippets"].items().size(); i++) {
        bool ok;
        Snippet s = snippetFromJson(root["snippets"].items()[i], ok);
        if (ok && (!builtInOnly || s.isBuiltIn()))
            list.push_back(s);
    }
    return list;
}

void Store::load(const std::string& fileText, bool fileExists, const std::string& defaultsText) {
    snippets_.clear();
    seeded_.clear();
    unreadable_ = false;
    indexStale_ = true;

    vjson::Value root;
    bool readable = fileExists && vjson::parse(fileText, root) && root.isObject();
    if (fileExists && !readable)
        unreadable_ = true;

    std::set<std::string> known;
    if (readable) {
        std::vector<Snippet> fromFile = readList(fileText, false);
        for (size_t i = 0; i < fromFile.size(); i++) {
            if (known.insert(fromFile[i].id).second)
                snippets_.push_back(fromFile[i]);
        }
        if (root["seeded"].isArray()) {
            for (size_t i = 0; i < root["seeded"].items().size(); i++) {
                if (root["seeded"].items()[i].isString())
                    seeded_.insert(root["seeded"].items()[i].asString());
            }
        }
    }

    //ready-made snippets this list has never had: all of them on a new installation, only the new ones after an update
    bool added = false;
    std::vector<Snippet> defaults = readList(defaultsText, true);
    for (size_t i = 0; i < defaults.size(); i++) {
        if (seeded_.count(defaults[i].id))
            continue;
        seeded_.insert(defaults[i].id);
        if (!known.count(defaults[i].id))
            snippets_.push_back(defaults[i]);
        added = true;
    }
    needsSave_ = added || !fileExists || unreadable_;
}

std::string Store::serialize() const {
    vjson::Value root = vjson::Value::object();
    root.set("version", vjson::Value::number(1));
    vjson::Value seeded = vjson::Value::array();
    for (std::set<std::string>::const_iterator it = seeded_.begin(); it != seeded_.end(); ++it)
        seeded.push(vjson::Value::string(*it));
    root.set("seeded", seeded);
    vjson::Value list = vjson::Value::array();
    for (size_t i = 0; i < snippets_.size(); i++) {
        const Snippet& s = snippets_[i];
        vjson::Value item = vjson::Value::object();
        item.set("id", vjson::Value::string(s.id));
        item.set("title", vjson::Value::string(s.title));
        item.set("keywords", vjson::Value::string(s.keywords));
        item.set("content", vjson::Value::string(s.content));
        item.set("useCount", vjson::Value::number(s.useCount));
        item.set("lastUsed", vjson::Value::number(s.lastUsed));
        list.push(item);
    }
    root.set("snippets", list);
    return vjson::write(root, true);
}

void Store::changed() {
    indexStale_ = true;
    needsSave_ = true;
}

std::vector<size_t> Store::search(const std::string& query) {
    if (indexStale_ || !index_) {
        std::vector<Entry> entries;
        entries.reserve(snippets_.size());
        for (size_t i = 0; i < snippets_.size(); i++) {
            const Snippet& s = snippets_[i];
            entries.push_back(Entry(s.title, s.keywords, s.content, s.useCount, (long long)(s.lastUsed * 1000)));
        }
        index_.reset(new Index(entries));
        indexStale_ = false;
    }
    return index_->search(query);
}

int Store::indexOfId(const std::string& id) const {
    for (size_t i = 0; i < snippets_.size(); i++) {
        if (snippets_[i].id == id)
            return (int)i;
    }
    return -1;
}

size_t Store::add(const std::string& id, const std::string& title, const std::string& keywords, const std::string& content) {
    Snippet s;
    s.id = id;
    s.title = title;
    s.keywords = keywords;
    s.content = content;
    snippets_.push_back(s);
    changed();
    return snippets_.size() - 1;
}

void Store::update(size_t position, const std::string& title, const std::string& keywords, const std::string& content) {
    if (position >= snippets_.size())
        return;
    snippets_[position].title = title;
    snippets_[position].keywords = keywords;
    snippets_[position].content = content;
    changed();
}

void Store::remove(size_t position) {
    if (position >= snippets_.size())
        return;
    snippets_.erase(snippets_.begin() + (long)position);
    changed();
}

void Store::recordUse(size_t position, double now) {
    if (position >= snippets_.size())
        return;
    snippets_[position].useCount += 1;
    snippets_[position].lastUsed = now;
    indexStale_ = true;
    needsSave_ = true;
}

void Store::restoreDefaults(const std::string& defaultsText) {
    std::vector<Snippet> defaults = readList(defaultsText, true);
    for (size_t i = 0; i < defaults.size(); i++) {
        int at = indexOfId(defaults[i].id);
        if (at >= 0) {
            snippets_[(size_t)at].title = defaults[i].title;
            snippets_[(size_t)at].keywords = defaults[i].keywords;
            snippets_[(size_t)at].content = defaults[i].content;
        } else {
            snippets_.push_back(defaults[i]);
        }
        seeded_.insert(defaults[i].id);
    }
    changed();
}

} // namespace vsnippet
