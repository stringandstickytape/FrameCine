// Unit tests of the pure parts (pc/src/core): run by ctest. No test framework: each CHECK that fails prints its
// line, and the exit code is the number of failures.
#include <cstdio>
#include <cstring>
#include <set>
#include <string>
#include <vector>

#include "../src/core/json.h"
#include "../src/core/keys.h"
#include "../src/core/mapping.h"
#include "../src/core/media.h"
#include "../src/core/protocol.h"
#include "../src/core/stats.h"

static int g_failures = 0;
static int g_checks = 0;

// The condition is not printed: MSVC cannot stringify raw string literals in a macro argument.
static void check(bool ok, int line) {
    ++g_checks;
    if (!ok) {
        ++g_failures;
        std::printf("FAIL unit_tests.cpp:%d\n", line);
    }
}
#define CHECK(cond) check(static_cast<bool>(cond), __LINE__)

using namespace pcw;

static void test_packet_framing() {
    PacketHeader h;
    h.kind = PacketKind::Video;
    h.flags = kFlagKeyFrame | kFlagConfigChange;
    h.time_us = 0x0102030405060708LL;
    h.length = 0xA0B0C0D0u;
    uint8_t b[kPacketHeaderSize];
    write_packet_header(h, b);
    const uint8_t expect[kPacketHeaderSize] = {'P', 'C', 'W', '1', 1, 3, 0, 0, 0x08, 0x07, 0x06, 0x05,
                                               0x04, 0x03, 0x02, 0x01, 0xD0, 0xC0, 0xB0, 0xA0};
    CHECK(std::memcmp(b, expect, sizeof b) == 0);
    auto r = read_packet_header(b);
    CHECK(r && r->kind == PacketKind::Video && r->flags == 3 && r->time_us == h.time_us && r->length == h.length);

    // A negative time (signed, little-endian) survives.
    h.kind = PacketKind::Sound;
    h.flags = 0;
    h.time_us = -5;
    h.length = 7;
    write_packet_header(h, b);
    CHECK(b[4] == 2 && b[8] == 0xFB && b[15] == 0xFF);
    r = read_packet_header(b);
    CHECK(r && r->time_us == -5 && r->kind == PacketKind::Sound && r->length == 7);

    // Wrong magic, non-zero reserved bytes, too short.
    b[0] = 'X';
    CHECK(!read_packet_header(b));
    b[0] = 'P';
    b[6] = 1;
    CHECK(!read_packet_header(b));
    b[6] = 0;
    CHECK(!read_packet_header(std::span<const uint8_t>(b, 19)));
}

static void test_json() {
    auto v = json::parse(R"({"t":"open","id":"w:1a2b","stream":3,"max":[1920,1080],"fps":60,"kbps":20000.5})");
    CHECK(v && v->is_object());
    CHECK(v->str("t") == "open" && v->str("id") == "w:1a2b");
    CHECK(v->integer("stream") == 3 && v->num("kbps") == 20000.5);
    const json::Value* m = v->get("max");
    CHECK(m && m->is_array() && m->items().size() == 2 && m->items()[1].as_number() == 1080);
    CHECK(v->str("missing", "x") == "x" && v->integer("t", 9) == 9);  // wrong type gives the fallback

    // Escapes in and out, Unicode by escape (with a surrogate pair) and raw UTF-8.
    v = json::parse(R"({"text":"a\"b\\c\n\t\u00e9\ud83d\ude00/\/","raw":"h\u00e9llo ✓"})");
    CHECK(v && v->str("text") == "a\"b\\c\n\t\xC3\xA9\xF0\x9F\x98\x80//");
    CHECK(v->str("raw") == "h\xC3\xA9llo \xE2\x9C\x93");
    json::Value o = json::Value::object();
    o.set("t", "text").set("s", std::string("q\"\\\n\x01\xC3\xA9\xE2\x80\xA8"));
    CHECK(o.dump() == "{\"t\":\"text\",\"s\":\"q\\\"\\\\\\n\\u0001\xC3\xA9\\u2028\"}");
    auto back = json::parse(o.dump());
    CHECK(back && back->str("s") == "q\"\\\n\x01\xC3\xA9\xE2\x80\xA8");

    // Numbers and literals.
    v = json::parse(R"([0,-1,2.5e3,true,false,null,{}])");
    CHECK(v && v->items().size() == 7 && v->items()[2].as_number() == 2500 && v->items()[3].as_bool() &&
          v->items()[5].is_null() && v->items()[6].is_object());
    json::Value n = json::Value::object();
    n.set("a", 3).set("b", 0.25).set("c", true).set("d", int64_t{1234567890123});
    CHECK(n.dump() == R"({"a":3,"b":0.25,"c":true,"d":1234567890123})");

    // Malformed input is refused, never thrown.
    for (const char* bad : {"", "{", "{\"a\":}", "{\"a\" 1}", "[1,]", "{\"a\":1,}", "01", "1.", "-", "\"\\x\"",
                            "\"\\ud800\"", "\"\\udc00\"", "\"a\nb\"", "{} x", "tru", "{\"a\":\"b\"", "nan"}) {
        CHECK(!json::parse(bad));
    }
    std::string deep(100, '[');
    deep += std::string(100, ']');
    CHECK(!json::parse(deep));
    // Unknown fields are kept but never get in the way.
    v = json::parse(R"({"t":"ping","n":4,"future":{"x":[1,2,{"y":null}]}})");
    CHECK(v && v->str("t") == "ping" && v->integer("n") == 4);
}

static void test_lines() {
    LineSplitter s(16);
    CHECK(s.feed("{\"t\":1}\n{\"t\""));
    auto a = s.next();
    CHECK(a && *a == "{\"t\":1}");
    CHECK(!s.next());
    CHECK(s.feed(":2}\r\n\n"));
    auto b = s.next();
    CHECK(b && *b == "{\"t\":2}");
    auto c = s.next();
    CHECK(c && c->empty());
    CHECK(!s.next());
    CHECK(!s.feed(std::string(40, 'x')));  // a line past the limit
}

static void test_discovery() {
    const std::string find = make_find_message("Desk \"PC\"");
    auto f = json::parse(find);
    CHECK(f && f->str("t") == "pcw_find" && f->integer("v") == 1 && f->str("pc") == "Desk \"PC\"");

    const std::string pin(64, 'A');
    auto h = parse_here_message(R"({"t":"pcw_here","v":1,"name":"Frame","port":47803,"pin":")" + pin +
                                R"(","pairing":true})");
    CHECK(h && h->name == "Frame" && h->port == 47803 && h->pin == std::string(64, 'a') && h->pairing);
    // A newer version with more fields still reads.
    h = parse_here_message(R"({"t":"pcw_here","v":2,"name":"F","port":5000,"pin":")" + pin + R"(","x":1})");
    CHECK(h && h->port == 5000 && !h->pairing);
    // Wrong type, version, pin or port.
    CHECK(!parse_here_message(R"({"t":"pcw_find","v":1,"pc":"x"})"));
    CHECK(!parse_here_message(R"({"t":"pcw_here","v":0,"name":"F","pin":")" + pin + "\"}"));
    CHECK(!parse_here_message(R"({"t":"pcw_here","v":1,"name":"F","pin":"abc"})"));
    CHECK(!parse_here_message(R"({"t":"pcw_here","v":1,"name":"F","pin":")" + std::string(64, 'g') + "\"}"));
    CHECK(!parse_here_message(R"({"t":"pcw_here","v":1,"port":70000,"pin":")" + pin + "\"}"));
    CHECK(!parse_here_message("not json"));
    CHECK(!parse_here_message(std::string("\xFF\xFE", 2)));
}

static void test_addresses() {
    CHECK(is_private_ipv4(*parse_ipv4("10.1.2.3")));
    CHECK(is_private_ipv4(*parse_ipv4("172.16.0.1")) && is_private_ipv4(*parse_ipv4("172.31.255.255")));  // privacy-check: allow (the range's edge)
    CHECK(!is_private_ipv4(*parse_ipv4("172.32.0.1")) && !is_private_ipv4(*parse_ipv4("172.15.0.1")));
    CHECK(is_private_ipv4(*parse_ipv4("192.168.1.20")) && !is_private_ipv4(*parse_ipv4("192.169.1.1")));
    CHECK(is_private_ipv4(*parse_ipv4("127.0.0.1")) && is_private_ipv4(*parse_ipv4("169.254.3.4")));
    CHECK(!is_private_ipv4(*parse_ipv4("8.8.8.8")) && !is_private_ipv4(*parse_ipv4("100.64.0.1")));
    CHECK(!parse_ipv4("1.2.3") && !parse_ipv4("1.2.3.256") && !parse_ipv4("1.2.3.4.5") && !parse_ipv4("a.b.c.d") &&
          !parse_ipv4("1..2.3") && !parse_ipv4("1.2.3.4 "));
    CHECK(format_ipv4(*parse_ipv4("192.168.0.5")) == "192.168.0.5");
}

static void test_base64_hex() {
    const uint8_t a[] = {'M', 'a', 'n'};
    CHECK(base64(a) == "TWFu");
    CHECK(base64(std::span<const uint8_t>(a, 2)) == "TWE=");
    CHECK(base64(std::span<const uint8_t>(a, 1)) == "TQ==");
    CHECK(base64({}).empty());
    const uint8_t h[] = {0x00, 0xAB, 0xFF};
    CHECK(hex(h) == "00abff");
    CHECK(normalise_hex("00ABff", 6) == std::optional<std::string>("00abff"));
    CHECK(!normalise_hex("00ABf", 0) && !normalise_hex("zz", 2) && !normalise_hex("aa", 4));
}

static void test_keys() {
    // Every name Godot's table has: mapped, except the ones no PC keyboard has.
    const std::set<std::string> unmapped = {"F25", "F26", "F27", "F28", "F29", "F30", "F31", "F32", "F33",
                                            "F34", "F35", "Hyper", "MediaRecord", "OpenURL", "Launch2",
                                            "Launch3", "Launch4", "Launch5", "Launch6", "Launch7", "Launch8",
                                            "Launch9", "LaunchA", "LaunchB", "LaunchC", "LaunchD", "LaunchE",
                                            "LaunchF", "Globe", "On-screen keyboard", "Unknown"};
    for (size_t i = 0; i < keys::kGodotNameCount; ++i) {
        const std::string name = keys::kGodotNames[i];
        const auto k = keys::lookup(name);
        if (unmapped.count(name)) {
            CHECK(!k);
        } else {
            if (!k) std::printf("  unmapped: %s\n", name.c_str());
            CHECK(k && (k->scan || k->vk));
        }
    }
    // Places on the keyboard, and the extended flag where Windows wants it.
    auto k = keys::lookup("A");
    CHECK(k && k->scan == 0x1E && !k->extended);
    k = keys::lookup("Ctrl");
    CHECK(k && k->scan == 0x1D && !k->extended);
    k = keys::lookup("Left");
    CHECK(k && k->scan == 0x4B && k->extended);
    k = keys::lookup("Kp 4");
    CHECK(k && k->scan == 0x4B && !k->extended);  // same scan as Left, but not extended
    k = keys::lookup("Kp Enter");
    CHECK(k && k->scan == 0x1C && k->extended);
    k = keys::lookup("Enter");
    CHECK(k && k->scan == 0x1C && !k->extended);
    k = keys::lookup("Kp Divide");
    CHECK(k && k->scan == 0x35 && k->extended);
    k = keys::lookup("Delete");
    CHECK(k && k->scan == 0x53 && k->extended);
    k = keys::lookup("Meta");
    CHECK(k && k->scan == 0x5B && k->extended);
    k = keys::lookup("Shift", 2);
    CHECK(k && k->scan == 0x36 && !k->extended);
    k = keys::lookup("Ctrl", 2);
    CHECK(k && k->scan == 0x1D && k->extended);
    k = keys::lookup("Alt", 2);
    CHECK(k && k->scan == 0x38 && k->extended);
    k = keys::lookup("Meta", 2);
    CHECK(k && k->scan == 0x5C && k->extended);
    k = keys::lookup("Shift", 1);
    CHECK(k && k->scan == 0x2A && !k->extended);
    k = keys::lookup("Ctrl", 1);
    CHECK(k && k->scan == 0x1D && !k->extended);
    k = keys::lookup("Alt", 1);
    CHECK(k && k->scan == 0x38 && !k->extended);
    k = keys::lookup("Meta", 1);
    CHECK(k && k->scan == 0x5B && k->extended);
    k = keys::lookup("Print");
    CHECK(k && k->scan == 0x37 && k->extended);
    k = keys::lookup("F12");
    CHECK(k && k->scan == 0x58);
    k = keys::lookup("Pause");
    CHECK(k && !k->scan && k->vk == 0x13);
    k = keys::lookup("VolumeUp");
    CHECK(k && !k->scan && k->vk == 0xAF);
    k = keys::lookup("QuoteLeft");
    CHECK(k && k->scan == 0x29);
    CHECK(keys::lookup("kp 1") && keys::lookup("CTRL") && keys::lookup("Windows") && keys::lookup("Command"));
    CHECK(!keys::lookup("") && !keys::lookup("Ctrl+A") && !keys::lookup("NoSuchKey"));
    // No two different Godot names give the same scan code unless one is a shifted or alternate spelling: check
    // the main block's letters and digits are all different.
    std::set<int> seen;
    for (const char* n : {"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R",
                          "S", "T", "U", "V", "W", "X", "Y", "Z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}) {
        seen.insert(keys::lookup(n)->scan);
    }
    CHECK(seen.size() == 36);
}

static void test_mapping() {
    using namespace mapping;
    // A window at (100, 50) of 800x600 captured whole; the stream unscaled.
    Rect win{100, 50, 900, 650};
    Point p = stream_to_screen(0.5, 0.5, 800, 600, win);
    CHECK(p.x == 100 && p.y == 50);
    p = stream_to_screen(799.9, 599.9, 800, 600, win);
    CHECK(p.x == 899 && p.y == 649);
    p = stream_to_screen(400.0, 300.0, 800, 600, win);
    CHECK(p.x == 500 && p.y == 350);
    // Outside the picture: kept on the window's edge.
    p = stream_to_screen(-10, 5000, 800, 600, win);
    CHECK(p.x == 100 && p.y == 649);
    // Scaled stream: a 2560x1440 window sent at 1280x720.
    Rect big{-2560, 0, 0, 1440};
    p = stream_to_screen(640.5, 360.5, 1280, 720, big);
    CHECK(p.x == -2560 + 1281 && p.y == 721);

    // Absolute units: every pixel of some virtual desktops comes back to itself.
    for (Rect vd : {Rect{0, 0, 1920, 1080}, Rect{-2560, -300, 3840, 2160}, Rect{0, 0, 7680, 4320},
                    Rect{-1080, 0, 1920, 1920}, Rect{0, 0, 3, 2}}) {
        bool ok = true;
        for (int x = vd.left; x < vd.right && ok; ++x) {
            const Point a = to_absolute({x, vd.top}, vd);
            const Point b = from_absolute(a, vd);
            ok = b.x == x && a.x >= 0 && a.x <= 65535;
        }
        for (int y = vd.top; y < vd.bottom && ok; ++y) {
            const Point a = to_absolute({vd.left, y}, vd);
            ok = from_absolute(a, vd).y == y;
        }
        CHECK(ok);
    }

    int w, h;
    fit_size(1920, 1080, 1920, 1080, 64, 64, w, h);
    CHECK(w == 1920 && h == 1080);
    fit_size(3840, 2160, 1920, 1080, 64, 64, w, h);
    CHECK(w == 1920 && h == 1080);
    fit_size(1001, 701, 4096, 4096, 64, 64, w, h);
    CHECK(w == 1000 && h == 700);
    fit_size(2000, 500, 1000, 1000, 64, 64, w, h);
    CHECK(w == 1000 && h == 250);
    fit_size(30, 20, 1920, 1080, 128, 64, w, h);  // scaled up 4.27 times, its shape kept
    CHECK(w == 128 && h == 86);
    fit_size(200, 100, 1920, 1080, 256, 128, w, h);
    CHECK(w == 256 && h == 128);
    fit_size(1921, 1081, 1920, 1080, 64, 64, w, h);  // rounding to even never passes the limit
    CHECK(w <= 1920 && h <= 1080 && w % 2 == 0 && h % 2 == 0);
}

static void test_media() {
    using namespace media;
    // HEVC: AUD, then an IDR slice with no parameter sets; the kept ones go after the AUD.
    const std::vector<uint8_t> ps = {0, 0, 0, 1, 0x40, 0x01, 0xAA,  // VPS (32)
                                     0, 0, 0, 1, 0x42, 0x01, 0xBB,  // SPS (33)
                                     0, 0, 1, 0x44, 0x01, 0xCC};    // PPS (34), 3-byte start code
    const std::vector<uint8_t> idr = {0, 0, 0, 1, 0x46, 0x01, 0x50,   // AUD (35)
                                      0, 0, 0, 1, 0x26, 0x01, 0x11};  // IDR_W_RADL (19)
    const std::vector<uint8_t> trail = {0, 0, 0, 1, 0x02, 0x01, 0x22};  // TRAIL_R (1)
    CHECK(split_annexb(ps).size() == 3);
    CHECK(is_key_frame(Codec::Hevc, idr) && !is_key_frame(Codec::Hevc, trail));
    ParameterSets kept(Codec::Hevc);
    std::vector<uint8_t> first = ps;
    first.insert(first.end(), idr.begin() + 7, idr.end());
    CHECK(kept.fix_key_frame(first) == first);  // already has them: unchanged, and remembered
    CHECK(kept.complete());
    const auto fixed = kept.fix_key_frame(idr);
    std::vector<uint8_t> expect(idr.begin(), idr.begin() + 7);
    expect.insert(expect.end(), ps.begin(), ps.end());
    expect.insert(expect.end(), idr.begin() + 7, idr.end());
    CHECK(fixed == expect);
    CHECK(kept.fix_key_frame(trail) == trail);

    // H.264: SPS 7, PPS 8, IDR 5.
    ParameterSets h264(Codec::H264);
    const std::vector<uint8_t> sps_pps = {0, 0, 0, 1, 0x67, 0x64, 0, 0, 0, 1, 0x68, 0xEE};
    h264.remember(sps_pps);
    const std::vector<uint8_t> idr264 = {0, 0, 0, 1, 0x65, 0x88};
    CHECK(is_key_frame(Codec::H264, idr264));
    std::vector<uint8_t> e264 = sps_pps;
    e264.insert(e264.end(), idr264.begin(), idr264.end());
    CHECK(h264.fix_key_frame(idr264) == e264);

    // ADTS: 48 kHz stereo LC, a 371-byte payload.
    uint8_t a[7];
    adts_header(a, 371, 48000, 2);
    CHECK(a[0] == 0xFF && a[1] == 0xF1);
    CHECK(((a[2] >> 6) & 3) == 1);       // profile LC
    CHECK(((a[2] >> 2) & 15) == 3);      // 48000
    CHECK((((a[2] & 1) << 2) | (a[3] >> 6)) == 2);  // stereo
    CHECK(adts_frame_length(a) == 378);
}

static void test_samples() {
    Samples s;
    for (int i = 1; i <= 100; ++i) s.add(i);
    CHECK(s.percentile(0.5) == 51 || s.percentile(0.5) == 50);
    CHECK(s.percentile(0.95) == 95 || s.percentile(0.95) == 96);
    CHECK(s.percentile(0) == 1 && s.percentile(1) == 100);
    s.clear();
    CHECK(s.percentile(0.5) == 0);
}

int main() {
    test_packet_framing();
    test_json();
    test_lines();
    test_discovery();
    test_addresses();
    test_base64_hex();
    test_keys();
    test_mapping();
    test_media();
    test_samples();
    std::printf("%d checks, %d failed\n", g_checks, g_failures);
    return g_failures;
}
