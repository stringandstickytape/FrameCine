#include "json.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace pcw::json {

Value Value::boolean(bool b) {
    Value v;
    v.type_ = Type::Bool;
    v.b_ = b;
    return v;
}

Value Value::number(double d) {
    Value v;
    v.type_ = Type::Number;
    v.d_ = d;
    return v;
}

Value Value::string(std::string s) {
    Value v;
    v.type_ = Type::String;
    v.s_ = std::move(s);
    return v;
}

Value Value::array() {
    Value v;
    v.type_ = Type::Array;
    return v;
}

Value Value::object() {
    Value v;
    v.type_ = Type::Object;
    return v;
}

const Value* Value::get(std::string_view key) const {
    if (type_ != Type::Object) {
        return nullptr;
    }
    for (const auto& [k, v] : o_) {
        if (k == key) {
            return &v;
        }
    }
    return nullptr;
}

std::string Value::str(std::string_view key, std::string_view fallback) const {
    const Value* v = get(key);
    return v && v->is_string() ? v->s_ : std::string(fallback);
}

double Value::num(std::string_view key, double fallback) const {
    const Value* v = get(key);
    return v && v->is_number() && std::isfinite(v->d_) ? v->d_ : fallback;
}

int64_t Value::integer(std::string_view key, int64_t fallback) const {
    const Value* v = get(key);
    if (!v || !v->is_number() || !std::isfinite(v->d_) || std::fabs(v->d_) > 9.0e15) {
        return fallback;
    }
    return static_cast<int64_t>(std::llround(v->d_));
}

bool Value::flag(std::string_view key, bool fallback) const {
    const Value* v = get(key);
    return v && v->is_bool() ? v->b_ : fallback;
}

Value& Value::set(std::string key, Value v) {
    if (type_ != Type::Object) {
        *this = object();
    }
    for (auto& [k, old] : o_) {
        if (k == key) {
            old = std::move(v);
            return *this;
        }
    }
    o_.emplace_back(std::move(key), std::move(v));
    return *this;
}

Value& Value::push(Value v) {
    if (type_ != Type::Array) {
        *this = array();
    }
    a_.push_back(std::move(v));
    return *this;
}

static void quote_to(std::string& out, std::string_view s) {
    static const char* hex = "0123456789abcdef";
    out.push_back('"');
    for (size_t i = 0; i < s.size(); ++i) {
        const unsigned char c = static_cast<unsigned char>(s[i]);
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            default:
                if (c < 0x20 || c == 0x7f) {
                    out += "\\u00";
                    out.push_back(hex[c >> 4]);
                    out.push_back(hex[c & 15]);
                } else if (c == 0xE2 && i + 2 < s.size() && static_cast<unsigned char>(s[i + 1]) == 0x80 &&
                           (static_cast<unsigned char>(s[i + 2]) == 0xA8 ||
                            static_cast<unsigned char>(s[i + 2]) == 0xA9)) {
                    out += static_cast<unsigned char>(s[i + 2]) == 0xA8 ? "\\u2028" : "\\u2029";
                    i += 2;
                } else {
                    out.push_back(static_cast<char>(c));
                }
        }
    }
    out.push_back('"');
}

std::string quote(std::string_view s) {
    std::string out;
    quote_to(out, s);
    return out;
}

void Value::dump_to(std::string& out) const {
    switch (type_) {
        case Type::Null: out += "null"; break;
        case Type::Bool: out += b_ ? "true" : "false"; break;
        case Type::Number: {
            if (!std::isfinite(d_)) {
                out += "null";  // JSON has no NaN or infinity
            } else if (d_ == std::floor(d_) && std::fabs(d_) < 9.0e15) {
                out += std::to_string(static_cast<long long>(d_));
            } else {
                char buf[32];
                std::snprintf(buf, sizeof buf, "%.17g", d_);
                out += buf;
            }
            break;
        }
        case Type::String: quote_to(out, s_); break;
        case Type::Array: {
            out.push_back('[');
            for (size_t i = 0; i < a_.size(); ++i) {
                if (i) out.push_back(',');
                a_[i].dump_to(out);
            }
            out.push_back(']');
            break;
        }
        case Type::Object: {
            out.push_back('{');
            for (size_t i = 0; i < o_.size(); ++i) {
                if (i) out.push_back(',');
                quote_to(out, o_[i].first);
                out.push_back(':');
                o_[i].second.dump_to(out);
            }
            out.push_back('}');
            break;
        }
    }
}

std::string Value::dump() const {
    std::string out;
    dump_to(out);
    return out;
}

namespace {

class Parser {
public:
    explicit Parser(std::string_view t) : t_(t) {}

    std::optional<Value> run() {
        Value v;
        if (!value(v, 0)) return std::nullopt;
        ws();
        if (p_ != t_.size()) return std::nullopt;
        return v;
    }

private:
    void ws() {
        while (p_ < t_.size() && (t_[p_] == ' ' || t_[p_] == '\t' || t_[p_] == '\n' || t_[p_] == '\r')) ++p_;
    }

    bool lit(std::string_view w) {
        if (t_.substr(p_, w.size()) != w) return false;
        p_ += w.size();
        return true;
    }

    bool value(Value& out, int depth) {
        if (depth > 64) return false;
        ws();
        if (p_ >= t_.size()) return false;
        const char c = t_[p_];
        if (c == '{') return object(out, depth);
        if (c == '[') return array(out, depth);
        if (c == '"') {
            std::string s;
            if (!string(s)) return false;
            out = Value::string(std::move(s));
            return true;
        }
        if (c == 't') { if (!lit("true")) return false; out = Value::boolean(true); return true; }
        if (c == 'f') { if (!lit("false")) return false; out = Value::boolean(false); return true; }
        if (c == 'n') { if (!lit("null")) return false; out = Value(); return true; }
        return number(out);
    }

    bool number(Value& out) {
        const size_t start = p_;
        if (p_ < t_.size() && t_[p_] == '-') ++p_;
        if (p_ >= t_.size()) return false;
        if (t_[p_] == '0') {
            ++p_;
        } else if (t_[p_] >= '1' && t_[p_] <= '9') {
            while (p_ < t_.size() && t_[p_] >= '0' && t_[p_] <= '9') ++p_;
        } else {
            return false;
        }
        if (p_ < t_.size() && t_[p_] == '.') {
            ++p_;
            const size_t d = p_;
            while (p_ < t_.size() && t_[p_] >= '0' && t_[p_] <= '9') ++p_;
            if (p_ == d) return false;
        }
        if (p_ < t_.size() && (t_[p_] == 'e' || t_[p_] == 'E')) {
            ++p_;
            if (p_ < t_.size() && (t_[p_] == '+' || t_[p_] == '-')) ++p_;
            const size_t d = p_;
            while (p_ < t_.size() && t_[p_] >= '0' && t_[p_] <= '9') ++p_;
            if (p_ == d) return false;
        }
        const std::string text(t_.substr(start, p_ - start));
        out = Value::number(std::strtod(text.c_str(), nullptr));
        return true;
    }

    static void utf8(std::string& s, uint32_t cp) {
        if (cp < 0x80) {
            s.push_back(static_cast<char>(cp));
        } else if (cp < 0x800) {
            s.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            s.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else if (cp < 0x10000) {
            s.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            s.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            s.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else {
            s.push_back(static_cast<char>(0xF0 | (cp >> 18)));
            s.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
            s.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            s.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
    }

    bool hex4(uint32_t& v) {
        if (p_ + 4 > t_.size()) return false;
        v = 0;
        for (int i = 0; i < 4; ++i) {
            const char c = t_[p_++];
            v <<= 4;
            if (c >= '0' && c <= '9') v |= static_cast<uint32_t>(c - '0');
            else if (c >= 'a' && c <= 'f') v |= static_cast<uint32_t>(c - 'a' + 10);
            else if (c >= 'A' && c <= 'F') v |= static_cast<uint32_t>(c - 'A' + 10);
            else return false;
        }
        return true;
    }

    bool string(std::string& s) {
        ++p_;  // the opening quote
        while (p_ < t_.size()) {
            const unsigned char c = static_cast<unsigned char>(t_[p_++]);
            if (c == '"') return true;
            if (c < 0x20) return false;
            if (c != '\\') {
                s.push_back(static_cast<char>(c));
                continue;
            }
            if (p_ >= t_.size()) return false;
            const char e = t_[p_++];
            switch (e) {
                case '"': s.push_back('"'); break;
                case '\\': s.push_back('\\'); break;
                case '/': s.push_back('/'); break;
                case 'b': s.push_back('\b'); break;
                case 'f': s.push_back('\f'); break;
                case 'n': s.push_back('\n'); break;
                case 'r': s.push_back('\r'); break;
                case 't': s.push_back('\t'); break;
                case 'u': {
                    uint32_t cp;
                    if (!hex4(cp)) return false;
                    if (cp >= 0xD800 && cp <= 0xDBFF) {
                        // A high surrogate must be followed by an escaped low one.
                        uint32_t lo;
                        if (p_ + 2 > t_.size() || t_[p_] != '\\' || t_[p_ + 1] != 'u') return false;
                        p_ += 2;
                        if (!hex4(lo) || lo < 0xDC00 || lo > 0xDFFF) return false;
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                    } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
                        return false;
                    }
                    utf8(s, cp);
                    break;
                }
                default: return false;
            }
        }
        return false;
    }

    bool array(Value& out, int depth) {
        ++p_;
        out = Value::array();
        ws();
        if (p_ < t_.size() && t_[p_] == ']') { ++p_; return true; }
        for (;;) {
            Value v;
            if (!value(v, depth + 1)) return false;
            out.push(std::move(v));
            ws();
            if (p_ >= t_.size()) return false;
            if (t_[p_] == ',') { ++p_; continue; }
            if (t_[p_] == ']') { ++p_; return true; }
            return false;
        }
    }

    bool object(Value& out, int depth) {
        ++p_;
        out = Value::object();
        ws();
        if (p_ < t_.size() && t_[p_] == '}') { ++p_; return true; }
        for (;;) {
            ws();
            if (p_ >= t_.size() || t_[p_] != '"') return false;
            std::string key;
            if (!string(key)) return false;
            ws();
            if (p_ >= t_.size() || t_[p_] != ':') return false;
            ++p_;
            Value v;
            if (!value(v, depth + 1)) return false;
            out.set(std::move(key), std::move(v));
            ws();
            if (p_ >= t_.size()) return false;
            if (t_[p_] == ',') { ++p_; continue; }
            if (t_[p_] == '}') { ++p_; return true; }
            return false;
        }
    }

    std::string_view t_;
    size_t p_ = 0;
};

}  // namespace

std::optional<Value> parse(std::string_view text) {
    return Parser(text).run();
}

}  // namespace pcw::json
