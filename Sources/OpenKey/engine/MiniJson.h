//
//  MiniJson.h
//  VOpenKey
//
//  A small JSON reader and writer for the settings files of the features (snippets, AI providers). Portable on purpose:
//  plain C++11, UTF-8 std::string, no platform code, ASCII source. Not a general purpose library: numbers are doubles,
//  objects keep the order of their keys, and nothing is streamed.
//
#ifndef MiniJson_h
#define MiniJson_h

#include <string>
#include <utility>
#include <vector>

namespace vjson {

class Value {
public:
    enum class Type { Null, Bool, Number, String, Array, Object };

    Value() : type_(Type::Null), bool_(false), number_(0) {}
    static Value boolean(bool b) { Value v; v.type_ = Type::Bool; v.bool_ = b; return v; }
    static Value number(double n) { Value v; v.type_ = Type::Number; v.number_ = n; return v; }
    static Value string(const std::string& s) { Value v; v.type_ = Type::String; v.string_ = s; return v; }
    static Value array() { Value v; v.type_ = Type::Array; return v; }
    static Value object() { Value v; v.type_ = Type::Object; return v; }

    Type type() const { return type_; }
    bool isNull() const { return type_ == Type::Null; }
    bool isBool() const { return type_ == Type::Bool; }
    bool isNumber() const { return type_ == Type::Number; }
    bool isString() const { return type_ == Type::String; }
    bool isArray() const { return type_ == Type::Array; }
    bool isObject() const { return type_ == Type::Object; }

    bool asBool(bool fallback = false) const { return isBool() ? bool_ : fallback; }
    double asNumber(double fallback = 0) const { return isNumber() ? number_ : fallback; }
    const std::string& asString() const { return string_; } //empty when it is no string
    std::string stringOr(const std::string& fallback) const { return isString() ? string_ : fallback; }

    // arrays
    const std::vector<Value>& items() const { return items_; }
    void push(const Value& v) { items_.push_back(v); }

    // objects: a key that is missing gives a null value
    const Value& operator[](const std::string& key) const;
    bool has(const std::string& key) const;
    void set(const std::string& key, const Value& v);
    const std::vector<std::pair<std::string, Value> >& members() const { return members_; }

private:
    Type type_;
    bool bool_;
    double number_;
    std::string string_;
    std::vector<Value> items_;
    std::vector<std::pair<std::string, Value> > members_;
};

/// Reads a JSON text. Returns false (and leaves `out` null) when it is not valid. A byte order mark is skipped.
bool parse(const std::string& text, Value& out);

/// Writes a value. `pretty` indents with two spaces. Non ASCII text stays UTF-8, "/" is not escaped.
std::string write(const Value& value, bool pretty = true);

} // namespace vjson

#endif /* MiniJson_h */
