// A small JSON reader and writer for the control connection's lines (docs/pc-windows.md). Only what the protocol
// needs: objects, arrays, strings, numbers, booleans and null. Strings are UTF-8 in and out.
#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace pcw::json {

class Value {
public:
    enum class Type { Null, Bool, Number, String, Array, Object };

    Value() = default;
    static Value boolean(bool b);
    static Value number(double d);
    static Value string(std::string s);
    static Value array();
    static Value object();

    Type type() const { return type_; }
    bool is_null() const { return type_ == Type::Null; }
    bool is_object() const { return type_ == Type::Object; }
    bool is_array() const { return type_ == Type::Array; }
    bool is_string() const { return type_ == Type::String; }
    bool is_number() const { return type_ == Type::Number; }
    bool is_bool() const { return type_ == Type::Bool; }

    // Lenient getters: a missing field or the wrong type gives the fallback, so a newer peer's message still reads.
    std::string str(std::string_view key, std::string_view fallback = {}) const;
    double num(std::string_view key, double fallback = 0) const;
    int64_t integer(std::string_view key, int64_t fallback = 0) const;
    bool flag(std::string_view key, bool fallback = false) const;
    const Value* get(std::string_view key) const;
    bool has(std::string_view key) const { return get(key) != nullptr; }

    bool as_bool() const { return b_; }
    double as_number() const { return d_; }
    const std::string& as_string() const { return s_; }
    const std::vector<Value>& items() const { return a_; }
    const std::vector<std::pair<std::string, Value>>& fields() const { return o_; }

    // Building.
    Value& set(std::string key, Value v);
    Value& set(std::string key, const char* s) { return set(std::move(key), string(s)); }
    Value& set(std::string key, std::string s) { return set(std::move(key), string(std::move(s))); }
    Value& set(std::string key, double d) { return set(std::move(key), number(d)); }
    Value& set(std::string key, int i) { return set(std::move(key), number(i)); }
    Value& set(std::string key, int64_t i) { return set(std::move(key), number(static_cast<double>(i))); }
    Value& set(std::string key, bool b) { return set(std::move(key), boolean(b)); }
    Value& push(Value v);

    // One line, no spaces, no newline at the end. Non-ASCII stays UTF-8; control characters, quotes and
    // backslashes are escaped, and so are U+2028/U+2029 (some readers treat them as line ends).
    std::string dump() const;

private:
    void dump_to(std::string& out) const;
    Type type_ = Type::Null;
    bool b_ = false;
    double d_ = 0;
    std::string s_;
    std::vector<Value> a_;
    std::vector<std::pair<std::string, Value>> o_;  // in insertion order, so lines read the way they were built
};

// Parses one JSON text. Returns nothing on any error (bad syntax, bad UTF-8 escapes, trailing junk, nesting deeper
// than 64). Never throws.
std::optional<Value> parse(std::string_view text);

// Escapes a string as a JSON string literal, quotes included.
std::string quote(std::string_view s);

}  // namespace pcw::json
