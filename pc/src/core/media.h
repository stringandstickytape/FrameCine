// Byte-level media helpers: Annex B access units (the encoders' output) and ADTS headers for AAC.
#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace pcw::media {

enum class Codec { Hevc, H264 };

struct Nal {
    size_t offset;  // of the start code
    size_t size;    // start code included
};

// The NAL units of an Annex B buffer, start codes of 3 or 4 bytes.
std::vector<Nal> split_annexb(std::span<const uint8_t> au);

// Whether the access unit holds a random access picture (HEVC IRAP 16..21, H.264 IDR 5).
bool is_key_frame(Codec codec, std::span<const uint8_t> au);

// Keeps the latest parameter sets (VPS/SPS/PPS, or SPS/PPS) seen and makes sure every key frame carries them
// before its picture, as docs/pc-windows.md asks: some encoders put them only on the first one.
class ParameterSets {
public:
    explicit ParameterSets(Codec codec) : codec_(codec) {}
    // Returns the access unit to send: as it was, or with the kept parameter sets in front.
    std::vector<uint8_t> fix_key_frame(std::span<const uint8_t> au);
    // Parameter sets from the encoder's media type (MF_MT_MPEG_SEQUENCE_HEADER), Annex B.
    void remember(std::span<const uint8_t> annexb);
    bool complete() const;

private:
    bool is_parameter_set(int type) const;
    Codec codec_;
    std::vector<uint8_t> vps_, sps_, pps_;
};

// The 7-byte ADTS header (no CRC) for one AAC-LC frame of `payload` bytes.
void adts_header(uint8_t out[7], size_t payload, int sample_rate, int channels);

// Reads frame_length from an ADTS header; 0 when it isn't one.
size_t adts_frame_length(std::span<const uint8_t> b);

}  // namespace pcw::media
