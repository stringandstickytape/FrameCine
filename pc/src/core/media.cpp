#include "media.h"

namespace pcw::media {

std::vector<Nal> split_annexb(std::span<const uint8_t> b) {
    std::vector<Nal> out;
    const size_t n = b.size();
    size_t i = 0;
    auto start_code_at = [&](size_t p) -> size_t {  // its length, 0 when none
        if (p + 3 <= n && b[p] == 0 && b[p + 1] == 0 && b[p + 2] == 1) return 3;
        if (p + 4 <= n && b[p] == 0 && b[p + 1] == 0 && b[p + 2] == 0 && b[p + 3] == 1) return 4;
        return 0;
    };
    while (i < n && !start_code_at(i)) ++i;
    while (i < n) {
        const size_t sc = start_code_at(i);
        const size_t body = i + sc;
        size_t j = body;
        while (j < n && !start_code_at(j)) ++j;
        if (body < n) out.push_back({i, j - i});
        i = j;
    }
    return out;
}

static int nal_type(Codec c, std::span<const uint8_t> b, const Nal& u) {
    size_t p = u.offset;
    while (p < u.offset + u.size && b[p] == 0) ++p;
    ++p;  // the 1 of the start code
    if (p >= u.offset + u.size) return -1;
    return c == Codec::Hevc ? (b[p] >> 1) & 0x3F : b[p] & 0x1F;
}

bool is_key_frame(Codec codec, std::span<const uint8_t> au) {
    for (const Nal& u : split_annexb(au)) {
        const int t = nal_type(codec, au, u);
        if (codec == Codec::Hevc ? (t >= 16 && t <= 21) : t == 5) return true;
    }
    return false;
}

bool ParameterSets::is_parameter_set(int t) const {
    return codec_ == Codec::Hevc ? (t >= 32 && t <= 34) : (t == 7 || t == 8);
}

bool ParameterSets::complete() const {
    return !sps_.empty() && !pps_.empty() && (codec_ == Codec::H264 || !vps_.empty());
}

void ParameterSets::remember(std::span<const uint8_t> b) {
    for (const Nal& u : split_annexb(b)) {
        const int t = nal_type(codec_, b, u);
        std::vector<uint8_t>* slot = nullptr;
        if (codec_ == Codec::Hevc) {
            slot = t == 32 ? &vps_ : t == 33 ? &sps_ : t == 34 ? &pps_ : nullptr;
        } else {
            slot = t == 7 ? &sps_ : t == 8 ? &pps_ : nullptr;
        }
        if (slot) slot->assign(b.begin() + static_cast<ptrdiff_t>(u.offset),
                               b.begin() + static_cast<ptrdiff_t>(u.offset + u.size));
    }
}

std::vector<uint8_t> ParameterSets::fix_key_frame(std::span<const uint8_t> au) {
    const auto units = split_annexb(au);
    bool has_ps = false, key = false;
    for (const Nal& u : units) {
        const int t = nal_type(codec_, au, u);
        has_ps = has_ps || is_parameter_set(t);
        key = key || (codec_ == Codec::Hevc ? (t >= 16 && t <= 21) : t == 5);
    }
    if (has_ps) remember(au);
    if (!key || has_ps || !complete()) return {au.begin(), au.end()};
    // Parameter sets go after any access unit delimiter (HEVC 35, H.264 9) and before everything else.
    std::vector<uint8_t> out;
    out.reserve(au.size() + vps_.size() + sps_.size() + pps_.size());
    size_t rest = 0;
    if (!units.empty()) {
        const int t0 = nal_type(codec_, au, units[0]);
        if ((codec_ == Codec::Hevc && t0 == 35) || (codec_ == Codec::H264 && t0 == 9)) {
            rest = units[0].offset + units[0].size;
            out.insert(out.end(), au.begin(), au.begin() + static_cast<ptrdiff_t>(rest));
        }
    }
    out.insert(out.end(), vps_.begin(), vps_.end());
    out.insert(out.end(), sps_.begin(), sps_.end());
    out.insert(out.end(), pps_.begin(), pps_.end());
    out.insert(out.end(), au.begin() + static_cast<ptrdiff_t>(rest), au.end());
    return out;
}

void adts_header(uint8_t h[7], size_t payload, int sample_rate, int channels) {
    static const int rates[] = {96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350};
    int index = 3;
    for (int i = 0; i < 13; ++i) {
        if (rates[i] == sample_rate) index = i;
    }
    const size_t len = payload + 7;
    const int profile = 1;  // AAC LC: object type 2, written as 2 - 1
    h[0] = 0xFF;
    h[1] = 0xF1;  // MPEG-4, layer 0, no CRC
    h[2] = static_cast<uint8_t>((profile << 6) | (index << 2) | ((channels >> 2) & 1));
    h[3] = static_cast<uint8_t>(((channels & 3) << 6) | ((len >> 11) & 3));
    h[4] = static_cast<uint8_t>((len >> 3) & 0xFF);
    h[5] = static_cast<uint8_t>(((len & 7) << 5) | 0x1F);  // buffer fullness 0x7FF: variable rate
    h[6] = 0xFC;
}

size_t adts_frame_length(std::span<const uint8_t> b) {
    if (b.size() < 7 || b[0] != 0xFF || (b[1] & 0xF6) != 0xF0) return 0;
    return (static_cast<size_t>(b[3] & 3) << 11) | (static_cast<size_t>(b[4]) << 3) | (b[5] >> 5);
}

}  // namespace pcw::media
