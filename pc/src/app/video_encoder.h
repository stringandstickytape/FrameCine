// A GPU's own video encoder through Media Foundation (a hardware MFT: NVENC, AMF, Quick Sync), fed with Direct3D 11
// textures so the picture never leaves the GPU: BGRA from the capture -> NV12 (the GPU's video processor scales
// and converts, BT.709 limited range) -> the encoder -> Annex B access units.
#pragma once

#include <d3d11.h>
#include <mfidl.h>
#include <mftransform.h>
#include <strmif.h>

#include <atomic>
#include <cstdint>
#include <deque>
#include <functional>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "../core/media.h"
#include "util.h"

namespace pcw {

struct EncoderChoice {
    media::Codec codec = media::Codec::Hevc;
    std::wstring name;  // the MFT's friendly name, for the log and the window
    LUID adapter{};     // the GPU it runs on
    bool have_adapter = false;
};

// The first hardware encoder for the codec (Windows' own order: the best first), or nothing.
std::optional<EncoderChoice> find_hardware_encoder(media::Codec codec);
// For the tests: behave as on a PC whose GPU has no video encoder.
void pretend_no_hardware_encoder();
// HEVC if any GPU here has it, else H.264 (or what `force` asks for); nothing when there is no hardware encoder.
std::optional<EncoderChoice> choose_encoder(std::optional<media::Codec> force);
// A Direct3D 11 device on that GPU, safe to use from several threads (the MFT works on it from its own).
ComPtr<ID3D11Device> make_device(const EncoderChoice& choice, std::string& error);

// Scales and converts a BGRA texture into an NV12 one with the GPU's video processor.
class Converter {
public:
    bool convert(ID3D11Device* dev, ID3D11DeviceContext* ctx, ID3D11Texture2D* bgra, int in_w, int in_h,
                 ID3D11Texture2D* nv12, int out_w, int out_h);
    void reset();

private:
    ComPtr<ID3D11VideoDevice> vdev_;
    ComPtr<ID3D11VideoContext> vctx_;
    ComPtr<ID3D11VideoProcessorEnumerator> en_;
    ComPtr<ID3D11VideoProcessor> vp_;
    int in_w_ = 0, in_h_ = 0, out_w_ = 0, out_h_ = 0;
    ID3D11Texture2D* in_tex_ = nullptr;
    ComPtr<ID3D11VideoProcessorInputView> in_view_;
    std::map<ID3D11Texture2D*, ComPtr<ID3D11VideoProcessorOutputView>> out_views_;
};

struct EncodedFrame {
    std::vector<uint8_t> data;  // one access unit, Annex B, parameter sets in front of every key frame
    int64_t time_us = 0;
    int64_t capture_us = 0;  // when the capture had it, for the latency numbers
    bool key = false;
    uint32_t serial = 0;  // which configuration it belongs to (bumped by each open)
};

class VideoEncoder {
public:
    using Output = std::function<void(EncodedFrame&&)>;

    VideoEncoder() = default;
    ~VideoEncoder();
    VideoEncoder(const VideoEncoder&) = delete;
    VideoEncoder& operator=(const VideoEncoder&) = delete;

    // `wake` is called when the encoder can take a frame; `out` gets each access unit (on the encoder's thread).
    bool open(ID3D11Device* dev, IMFDXGIDeviceManager* manager, const EncoderChoice& choice, int w, int h, int fps,
              int kbps, uint32_t serial, Output out, std::function<void()> wake, std::string& error);
    void close();

    bool ready() const { return need_input_.load() > 0 || !async_; }
    // An NV12 sample from samples(): encoded as a key frame when `key`.
    bool encode(IMFSample* sample, int64_t time_us, int64_t capture_us, bool key);
    void set_bitrate(int kbps);

    // A pool of NV12 textures (with their samples) the encoder can read while we fill the next.
    ComPtr<IMFSample> new_sample(ComPtr<ID3D11Texture2D>& texture);

    int width() const { return w_; }
    int height() const { return h_; }
    bool failed() const { return failed_.load(); }

private:
    void events();
    bool drain_output();
    void set_u32(const GUID& api, UINT32 v, const char* what);

    ComPtr<IMFTransform> mft_;
    ComPtr<ICodecAPI> codec_api_;
    ComPtr<IMFMediaEventGenerator> gen_;
    ComPtr<IMFVideoSampleAllocatorEx> alloc_;
    ComPtr<IMFActivate> activate_;
    bool async_ = false;
    std::atomic<int> need_input_{0};
    std::atomic<bool> failed_{false};
    std::atomic<bool> closing_{false};
    std::thread thread_;
    Output out_;
    std::function<void()> wake_;
    media::Codec codec_ = media::Codec::Hevc;
    std::unique_ptr<media::ParameterSets> ps_;
    int w_ = 0, h_ = 0, fps_ = 60;
    uint32_t serial_ = 0;
    int64_t frames_in_ = 0;
    DWORD in_id_ = 0, out_id_ = 0;

    std::mutex pending_lock_;
    struct Pending {
        int64_t time_us, capture_us;
    };
    std::deque<Pending> pending_;
};

}  // namespace pcw
