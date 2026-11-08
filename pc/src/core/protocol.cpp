#include "protocol.h"

#include <cstring>

namespace pcw {

void write_packet_header(const PacketHeader& h, uint8_t out[kPacketHeaderSize]) {
    out[0] = 'P';
    out[1] = 'C';
    out[2] = 'W';
    out[3] = '1';
    out[4] = static_cast<uint8_t>(h.kind);
    out[5] = h.flags;
    out[6] = 0;
    out[7] = 0;
    const uint64_t t = static_cast<uint64_t>(h.time_us);
    for (int i = 0; i < 8; ++i) out[8 + i] = static_cast<uint8_t>(t >> (8 * i));
    for (int i = 0; i < 4; ++i) out[16 + i] = static_cast<uint8_t>(h.length >> (8 * i));
}

std::optional<PacketHeader> read_packet_header(std::span<const uint8_t> b) {
    if (b.size() < kPacketHeaderSize || std::memcmp(b.data(), "PCW1", 4) != 0 || b[6] != 0 || b[7] != 0) {
        return std::nullopt;
    }
    PacketHeader h;
    h.kind = static_cast<PacketKind>(b[4]);
    h.flags = b[5];
    uint64_t t = 0;
    for (int i = 0; i < 8; ++i) t |= static_cast<uint64_t>(b[8 + i]) << (8 * i);
    h.time_us = static_cast<int64_t>(t);
    uint32_t n = 0;
    for (int i = 0; i < 4; ++i) n |= static_cast<uint32_t>(b[16 + i]) << (8 * i);
    h.length = n;
    return h;
}

std::string make_find_message(std::string_view pc_name) {
    json::Value v = json::Value::object();
    v.set("t", "pcw_find").set("v", kProtocolVersion).set("pc", std::string(pc_name));
    return v.dump();
}

std::optional<HereMessage> parse_here_message(std::string_view datagram) {
    auto v = json::parse(datagram);
    if (!v || !v->is_object() || v->str("t") != "pcw_here" || v->integer("v", 0) < 1) {
        return std::nullopt;
    }
    HereMessage m;
    m.name = v->str("name");
    const int64_t port = v->integer("port", kPort);
    if (port < 1 || port > 65535) return std::nullopt;
    m.port = static_cast<uint16_t>(port);
    auto pin = normalise_hex(v->str("pin"), 64);
    if (!pin) return std::nullopt;
    m.pin = *pin;
    m.pairing = v->flag("pairing", false);
    return m;
}

bool LineSplitter::feed(std::string_view bytes) {
    buf_.append(bytes);
    // A partial line longer than the limit can never finish well.
    const size_t nl = buf_.find('\n', scan_);
    if (nl == std::string::npos) {
        scan_ = buf_.size();
        return buf_.size() <= max_;
    }
    return nl <= max_;
}

std::optional<std::string> LineSplitter::next() {
    const size_t nl = buf_.find('\n');
    if (nl == std::string::npos) {
        scan_ = buf_.size();
        return std::nullopt;
    }
    std::string line = buf_.substr(0, nl);
    buf_.erase(0, nl + 1);
    scan_ = 0;
    if (!line.empty() && line.back() == '\r') line.pop_back();
    return line;
}

std::string base64(std::span<const uint8_t> b) {
    static const char* t = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    out.reserve((b.size() + 2) / 3 * 4);
    size_t i = 0;
    for (; i + 3 <= b.size(); i += 3) {
        const uint32_t n = (uint32_t{b[i]} << 16) | (uint32_t{b[i + 1]} << 8) | b[i + 2];
        out.push_back(t[n >> 18]);
        out.push_back(t[(n >> 12) & 63]);
        out.push_back(t[(n >> 6) & 63]);
        out.push_back(t[n & 63]);
    }
    if (b.size() - i == 1) {
        const uint32_t n = uint32_t{b[i]} << 16;
        out.push_back(t[n >> 18]);
        out.push_back(t[(n >> 12) & 63]);
        out += "==";
    } else if (b.size() - i == 2) {
        const uint32_t n = (uint32_t{b[i]} << 16) | (uint32_t{b[i + 1]} << 8);
        out.push_back(t[n >> 18]);
        out.push_back(t[(n >> 12) & 63]);
        out.push_back(t[(n >> 6) & 63]);
        out.push_back('=');
    }
    return out;
}

std::string hex(std::span<const uint8_t> b) {
    static const char* d = "0123456789abcdef";
    std::string out;
    out.reserve(b.size() * 2);
    for (uint8_t c : b) {
        out.push_back(d[c >> 4]);
        out.push_back(d[c & 15]);
    }
    return out;
}

std::optional<std::string> normalise_hex(std::string_view s, size_t length) {
    if ((length && s.size() != length) || s.empty() || s.size() % 2) return std::nullopt;
    std::string out(s);
    for (char& c : out) {
        if (c >= 'A' && c <= 'F') c = static_cast<char>(c - 'A' + 'a');
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return std::nullopt;
    }
    return out;
}

bool is_private_ipv4(uint32_t a) {
    const uint32_t b0 = a >> 24, b1 = (a >> 16) & 0xFF;
    return b0 == 10 || (b0 == 172 && b1 >= 16 && b1 <= 31) || (b0 == 192 && b1 == 168) || (b0 == 169 && b1 == 254) ||
           b0 == 127;
}

std::optional<uint32_t> parse_ipv4(std::string_view s) {
    uint32_t out = 0;
    int parts = 0;
    size_t i = 0;
    while (parts < 4) {
        if (i >= s.size() || s[i] < '0' || s[i] > '9') return std::nullopt;
        uint32_t n = 0;
        size_t digits = 0;
        while (i < s.size() && s[i] >= '0' && s[i] <= '9') {
            n = n * 10 + static_cast<uint32_t>(s[i] - '0');
            if (++digits > 3 || n > 255) return std::nullopt;
            ++i;
        }
        out = (out << 8) | n;
        ++parts;
        if (parts < 4) {
            if (i >= s.size() || s[i] != '.') return std::nullopt;
            ++i;
        }
    }
    if (i != s.size()) return std::nullopt;
    return out;
}

std::string format_ipv4(uint32_t a) {
    return std::to_string(a >> 24) + "." + std::to_string((a >> 16) & 0xFF) + "." + std::to_string((a >> 8) & 0xFF) +
           "." + std::to_string(a & 0xFF);
}

}  // namespace pcw
