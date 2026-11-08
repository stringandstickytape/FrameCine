// The wire formats of docs/pc-windows.md that are pure data: the PCW1 packet framing, the discovery datagrams,
// the line splitter of the control connection, and small helpers (base64, hex, private addresses).
#pragma once

#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

#include "json.h"

namespace pcw {

constexpr uint16_t kPort = 47803;
constexpr int kProtocolVersion = 1;

// ---- PCW1 packets (stream connections) ----

enum class PacketKind : uint8_t { Video = 1, Sound = 2 };
constexpr uint8_t kFlagKeyFrame = 1;
constexpr uint8_t kFlagConfigChange = 2;
constexpr size_t kPacketHeaderSize = 20;

struct PacketHeader {
    PacketKind kind = PacketKind::Video;
    uint8_t flags = 0;
    int64_t time_us = 0;
    uint32_t length = 0;
};

// Writes the 20-byte header in front of a payload of `header.length` bytes.
void write_packet_header(const PacketHeader& header, uint8_t out[kPacketHeaderSize]);
// Reads a header; nothing when the magic is wrong or the reserved bytes are not 0.
std::optional<PacketHeader> read_packet_header(std::span<const uint8_t> bytes);

// ---- Discovery (UDP 47803) ----

std::string make_find_message(std::string_view pc_name);

struct HereMessage {
    std::string name;
    uint16_t port = kPort;
    std::string pin;  // lower-case hex SHA-256 of the certificate's DER
    bool pairing = false;
};

// Parses a headset's reply. Nothing unless it is a pcw_here of version 1 or later with a well-formed pin (64 hex
// digits) and a port in range; a newer version is read as far as it goes, as the protocol asks.
std::optional<HereMessage> parse_here_message(std::string_view datagram);

// ---- Control connection: JSON lines ----

// Collects bytes and gives back whole lines (without the \n; a \r before it is dropped too). A line longer than the
// limit is a protocol error: the caller closes the connection.
class LineSplitter {
public:
    explicit LineSplitter(size_t max_line = 4 * 1024 * 1024) : max_(max_line) {}
    // Appends; returns false when a line grew past the limit.
    bool feed(std::string_view bytes);
    std::optional<std::string> next();

private:
    std::string buf_;
    size_t scan_ = 0;
    size_t max_;
};

// ---- Helpers ----

std::string base64(std::span<const uint8_t> bytes);
std::string hex(std::span<const uint8_t> bytes);
// Lower-cases and checks a hex string of the given length (0: any even length).
std::optional<std::string> normalise_hex(std::string_view s, size_t length);

// RFC 1918, link-local and loopback IPv4 (loopback for tests on one PC). Address in host byte order.
bool is_private_ipv4(uint32_t address);
std::optional<uint32_t> parse_ipv4(std::string_view dotted);
std::string format_ipv4(uint32_t address);

}  // namespace pcw
