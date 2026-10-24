//
//  MiniJson.cpp
//  VOpenKey
//
#include "MiniJson.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace vjson {

static const Value kNull;

const Value& Value::operator[](const std::string& key) const {
    for (size_t i = 0; i < members_.size(); i++) {
        if (members_[i].first == key)
            return members_[i].second;
    }
    return kNull;
}

bool Value::has(const std::string& key) const {
    for (size_t i = 0; i < members_.size(); i++) {
        if (members_[i].first == key)
            return true;
    }
    return false;
}

void Value::set(const std::string& key, const Value& v) {
    for (size_t i = 0; i < members_.size(); i++) {
        if (members_[i].first == key) {
            members_[i].second = v;
            return;
        }
    }
    members_.push_back(std::make_pair(key, v));
}

namespace {

const int kMaxDepth = 64;

class Parser {
public:
    explicit Parser(const std::string& text) : s_(text), pos_(0) {}

    bool run(Value& out) {
        if (s_.compare(0, 3, "\xEF\xBB\xBF") == 0)
            pos_ = 3;
        skip();
        if (!value(out, 0))
            return false;
        skip();
        return pos_ == s_.size();
    }

private:
    const std::string& s_;
    size_t pos_;

    void skip() {
        while (pos_ < s_.size() && (s_[pos_] == ' ' || s_[pos_] == '\t' || s_[pos_] == '\n' || s_[pos_] == '\r'))
            pos_++;
    }

    bool literal(const char* word) {
        size_t n = 0;
        while (word[n])
            n++;
        if (s_.compare(pos_, n, word) != 0)
            return false;
        pos_ += n;
        return true;
    }

    bool value(Value& out, int depth) {
        if (depth > kMaxDepth || pos_ >= s_.size())
            return false;
        char c = s_[pos_];
        if (c == '{')
            return object(out, depth);
        if (c == '[')
            return array(out, depth);
        if (c == '"') {
            std::string text;
            if (!str(text))
                return false;
            out = Value::string(text);
            return true;
        }
        if (c == 't') { if (!literal("true")) return false; out = Value::boolean(true); return true; }
        if (c == 'f') { if (!literal("false")) return false; out = Value::boolean(false); return true; }
        if (c == 'n') { if (!literal("null")) return false; out = Value(); return true; }
        return num(out);
    }

    //-?(0|[1-9][0-9]*)(.[0-9]+)?([eE][+-]?[0-9]+)? and nothing else: "1-2" or "1e+" is not a number
    bool num(Value& out) {
        size_t start = pos_;
        size_t i = pos_;
        if (i < s_.size() && s_[i] == '-')
            i++;
        if (i >= s_.size() || s_[i] < '0' || s_[i] > '9')
            return false;
        if (s_[i] == '0') {
            i++;
        } else {
            while (i < s_.size() && s_[i] >= '0' && s_[i] <= '9')
                i++;
        }
        if (i < s_.size() && s_[i] == '.') {
            i++;
            size_t digits = 0;
            while (i < s_.size() && s_[i] >= '0' && s_[i] <= '9') { i++; digits++; }
            if (digits == 0)
                return false;
        }
        if (i < s_.size() && (s_[i] == 'e' || s_[i] == 'E')) {
            i++;
            if (i < s_.size() && (s_[i] == '+' || s_[i] == '-'))
                i++;
            size_t digits = 0;
            while (i < s_.size() && s_[i] >= '0' && s_[i] <= '9') { i++; digits++; }
            if (digits == 0)
                return false;
        }
        pos_ = i;
        out = Value::number(std::strtod(s_.substr(start, pos_ - start).c_str(), NULL));
        return true;
    }

    static void appendUtf8(std::string& out, unsigned long cp) {
        if (cp < 0x80) {
            out += (char)cp;
        } else if (cp < 0x800) {
            out += (char)(0xC0 | (cp >> 6));
            out += (char)(0x80 | (cp & 0x3F));
        } else if (cp < 0x10000) {
            out += (char)(0xE0 | (cp >> 12));
            out += (char)(0x80 | ((cp >> 6) & 0x3F));
            out += (char)(0x80 | (cp & 0x3F));
        } else {
            out += (char)(0xF0 | (cp >> 18));
            out += (char)(0x80 | ((cp >> 12) & 0x3F));
            out += (char)(0x80 | ((cp >> 6) & 0x3F));
            out += (char)(0x80 | (cp & 0x3F));
        }
    }

    bool hex4(unsigned long& code) {
        if (pos_ + 4 > s_.size())
            return false;
        code = 0;
        for (int i = 0; i < 4; i++) {
            char c = s_[pos_ + i];
            code <<= 4;
            if (c >= '0' && c <= '9') code |= (unsigned long)(c - '0');
            else if (c >= 'a' && c <= 'f') code |= (unsigned long)(c - 'a' + 10);
            else if (c >= 'A' && c <= 'F') code |= (unsigned long)(c - 'A' + 10);
            else return false;
        }
        pos_ += 4;
        return true;
    }

    bool str(std::string& out) {
        pos_++; // the opening quote
        while (pos_ < s_.size()) {
            unsigned char c = (unsigned char)s_[pos_++];
            if (c == '"')
                return true;
            if (c < 0x20)
                return false; // a raw line break is not allowed in a string
            if (c != '\\') {
                out += (char)c;
                continue;
            }
            if (pos_ >= s_.size())
                return false;
            char e = s_[pos_++];
            switch (e) {
                case '"': out += '"'; break;
                case '\\': out += '\\'; break;
                case '/': out += '/'; break;
                case 'b': out += '\b'; break;
                case 'f': out += '\f'; break;
                case 'n': out += '\n'; break;
                case 'r': out += '\r'; break;
                case 't': out += '\t'; break;
                case 'u': {
                    unsigned long code;
                    if (!hex4(code))
                        return false;
                    if (code >= 0xD800 && code <= 0xDBFF) { // the first half of a pair
                        unsigned long low;
                        if (s_.compare(pos_, 2, "\\u") != 0)
                            return false;
                        pos_ += 2;
                        if (!hex4(low) || low < 0xDC00 || low > 0xDFFF)
                            return false;
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                    } else if (code >= 0xDC00 && code <= 0xDFFF) {
                        return false;
                    }
                    appendUtf8(out, code);
                    break;
                }
                default:
                    return false;
            }
        }
        return false;
    }

    bool array(Value& out, int depth) {
        pos_++;
        out = Value::array();
        skip();
        if (pos_ < s_.size() && s_[pos_] == ']') {
            pos_++;
            return true;
        }
        while (true) {
            skip();
            Value item;
            if (!value(item, depth + 1))
                return false;
            out.push(item);
            skip();
            if (pos_ >= s_.size())
                return false;
            if (s_[pos_] == ',') { pos_++; continue; }
            if (s_[pos_] == ']') { pos_++; return true; }
            return false;
        }
    }

    bool object(Value& out, int depth) {
        pos_++;
        out = Value::object();
        skip();
        if (pos_ < s_.size() && s_[pos_] == '}') {
            pos_++;
            return true;
        }
        while (true) {
            skip();
            if (pos_ >= s_.size() || s_[pos_] != '"')
                return false;
            std::string key;
            if (!str(key))
                return false;
            skip();
            if (pos_ >= s_.size() || s_[pos_] != ':')
                return false;
            pos_++;
            skip();
            Value item;
            if (!value(item, depth + 1))
                return false;
            out.set(key, item);
            skip();
            if (pos_ >= s_.size())
                return false;
            if (s_[pos_] == ',') { pos_++; continue; }
            if (s_[pos_] == '}') { pos_++; return true; }
            return false;
        }
    }
};

void writeString(std::string& out, const std::string& text) {
    out += '"';
    for (size_t i = 0; i < text.size(); i++) {
        unsigned char c = (unsigned char)text[i];
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            default:
                if (c < 0x20) {
                    char buffer[8];
                    std::snprintf(buffer, sizeof(buffer), "\\u%04x", c);
                    out += buffer;
                } else {
                    out += (char)c;
                }
        }
    }
    out += '"';
}

void writeValue(std::string& out, const Value& v, bool pretty, int level) {
    std::string inner(pretty ? (size_t)(level + 1) * 2 : 0, ' ');
    std::string outer(pretty ? (size_t)level * 2 : 0, ' ');
    const char* newline = pretty ? "\n" : "";
    switch (v.type()) {
        case Value::Type::Null: out += "null"; break;
        case Value::Type::Bool: out += v.asBool() ? "true" : "false"; break;
        case Value::Type::Number: {
            double n = v.asNumber();
            char buffer[40];
            if (std::floor(n) == n && std::fabs(n) < 1e15)
                std::snprintf(buffer, sizeof(buffer), "%lld", (long long)n);
            else
                std::snprintf(buffer, sizeof(buffer), "%.17g", n);
            out += buffer;
            break;
        }
        case Value::Type::String: writeString(out, v.asString()); break;
        case Value::Type::Array: {
            if (v.items().empty()) { out += "[]"; break; }
            out += "[";
            out += newline;
            for (size_t i = 0; i < v.items().size(); i++) {
                out += inner;
                writeValue(out, v.items()[i], pretty, level + 1);
                out += (i + 1 < v.items().size() ? "," : "");
                out += newline;
            }
            out += outer + "]";
            break;
        }
        case Value::Type::Object: {
            if (v.members().empty()) { out += "{}"; break; }
            out += "{";
            out += newline;
            for (size_t i = 0; i < v.members().size(); i++) {
                out += inner;
                writeString(out, v.members()[i].first);
                out += pretty ? ": " : ":";
                writeValue(out, v.members()[i].second, pretty, level + 1);
                out += (i + 1 < v.members().size() ? "," : "");
                out += newline;
            }
            out += outer + "}";
            break;
        }
    }
}

} // namespace

bool parse(const std::string& text, Value& out) {
    Parser parser(text);
    Value result;
    if (!parser.run(result)) {
        out = Value();
        return false;
    }
    out = result;
    return true;
}

std::string write(const Value& value, bool pretty) {
    std::string out;
    writeValue(out, value, pretty, 0);
    if (pretty)
        out += "\n";
    return out;
}

} // namespace vjson
