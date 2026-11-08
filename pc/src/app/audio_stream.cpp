#include "audio_stream.h"

#include <audioclient.h>
#include <mfapi.h>
#include <mferror.h>
#include <mftransform.h>
#include <mmdeviceapi.h>
#include <mmreg.h>
#include <wmcodecdsp.h>
#include <ks.h>
#include <ksmedia.h>

#include <cmath>
#include <deque>
#include <vector>

#include "../core/media.h"
#include "log.h"
#include "util.h"

namespace pcw {

namespace {

constexpr int kRate = 48000;
constexpr int kAacFrame = 1024;

// The default output device, captured as it plays (loopback). A silent stream is played on the same device beside
// it: loopback gives nothing at all while nothing plays, and a steady flow keeps the sound's clock unbroken.
struct Loopback {
    ComPtr<IMMDeviceEnumerator> devices;
    ComPtr<IMMDevice> dev;
    std::wstring dev_id;
    ComPtr<IAudioClient> cap_client;
    ComPtr<IAudioCaptureClient> cap;
    ComPtr<IAudioClient> ren_client;
    ComPtr<IAudioRenderClient> ren;
    UINT32 ren_size = 0;
    int channels = 2, rate = kRate, bits = 32;
    bool is_float = true;

    ~Loopback() { close(); }

    void close() {
        if (cap_client) cap_client->Stop();
        if (ren_client) ren_client->Stop();
        cap.Reset();
        cap_client.Reset();
        ren.Reset();
        ren_client.Reset();
        dev.Reset();
    }

    std::wstring default_id() {
        if (!devices && FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                                IID_PPV_ARGS(&devices)))) {
            return {};
        }
        ComPtr<IMMDevice> d;
        if (FAILED(devices->GetDefaultAudioEndpoint(eRender, eConsole, &d))) return {};
        LPWSTR id = nullptr;
        std::wstring out;
        if (SUCCEEDED(d->GetId(&id)) && id) {
            out = id;
            CoTaskMemFree(id);
        }
        return out;
    }

    bool open(std::string& err) {
        close();
        HRESULT hr = S_OK;
        if (!devices) {
            hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&devices));
            if (FAILED(hr)) {
                err = "audio devices: " + hr_text(hr);
                return false;
            }
        }
        hr = devices->GetDefaultAudioEndpoint(eRender, eConsole, &dev);
        if (FAILED(hr)) {
            err = "no output device: " + hr_text(hr);
            return false;
        }
        LPWSTR id = nullptr;
        if (SUCCEEDED(dev->GetId(&id)) && id) {
            dev_id = id;
            CoTaskMemFree(id);
        }
        // Ask Windows for 48 kHz stereo float whatever the device runs at; older Windows may refuse, and then the
        // device's own format is converted here.
        WAVEFORMATEXTENSIBLE want{};
        want.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
        want.Format.nChannels = 2;
        want.Format.nSamplesPerSec = kRate;
        want.Format.wBitsPerSample = 32;
        want.Format.nBlockAlign = 8;
        want.Format.nAvgBytesPerSec = kRate * 8;
        want.Format.cbSize = sizeof want - sizeof want.Format;
        want.Samples.wValidBitsPerSample = 32;
        want.dwChannelMask = SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT;
        want.SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
        hr = dev->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(cap_client.GetAddressOf()));
        if (FAILED(hr)) {
            err = "audio client: " + hr_text(hr);
            return false;
        }
        hr = cap_client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                    AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                                        AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                                    2'000'000, 0, &want.Format, nullptr);
        if (SUCCEEDED(hr)) {
            channels = 2;
            rate = kRate;
            bits = 32;
            is_float = true;
        } else {
            cap_client.Reset();
            hr = dev->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                               reinterpret_cast<void**>(cap_client.GetAddressOf()));
            WAVEFORMATEX* mix = nullptr;
            if (SUCCEEDED(hr)) hr = cap_client->GetMixFormat(&mix);
            if (FAILED(hr)) {
                err = "audio format: " + hr_text(hr);
                return false;
            }
            channels = mix->nChannels;
            rate = static_cast<int>(mix->nSamplesPerSec);
            bits = mix->wBitsPerSample;
            is_float = mix->wFormatTag == WAVE_FORMAT_IEEE_FLOAT;
            if (mix->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
                is_float = reinterpret_cast<WAVEFORMATEXTENSIBLE*>(mix)->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
            }
            hr = cap_client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 2'000'000, 0, mix,
                                        nullptr);
            CoTaskMemFree(mix);
            if (FAILED(hr)) {
                err = "loopback: " + hr_text(hr);
                return false;
            }
        }
        hr = cap_client->GetService(IID_PPV_ARGS(&cap));
        if (FAILED(hr)) {
            err = "loopback service: " + hr_text(hr);
            return false;
        }
        // The silent player. Not fatal: loopback still works while something else plays.
        if (SUCCEEDED(dev->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                    reinterpret_cast<void**>(ren_client.GetAddressOf())))) {
            WAVEFORMATEX* mix = nullptr;
            if (SUCCEEDED(ren_client->GetMixFormat(&mix)) &&
                SUCCEEDED(ren_client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 2'000'000, 0, mix, nullptr)) &&
                SUCCEEDED(ren_client->GetBufferSize(&ren_size)) && SUCCEEDED(ren_client->GetService(IID_PPV_ARGS(&ren)))) {
                feed_silence();
                ren_client->Start();
            } else {
                ren.Reset();
                ren_client.Reset();
            }
            if (mix) CoTaskMemFree(mix);
        }
        hr = cap_client->Start();
        if (FAILED(hr)) {
            err = "loopback start: " + hr_text(hr);
            return false;
        }
        logf("sound: loopback %d Hz, %d channels, %d-bit %s%s", rate, channels, bits, is_float ? "float" : "integer",
             rate == kRate && channels == 2 ? "" : " (converted here)");
        return true;
    }

    void feed_silence() {
        if (!ren) return;
        UINT32 pad = 0;
        if (FAILED(ren_client->GetCurrentPadding(&pad)) || pad >= ren_size) return;
        BYTE* p = nullptr;
        const UINT32 n = ren_size - pad;
        if (SUCCEEDED(ren->GetBuffer(n, &p))) ren->ReleaseBuffer(n, AUDCLNT_BUFFERFLAGS_SILENT);
    }
};

// Any sample format and channel count to stereo float; then any rate to 48 kHz, linearly (the device runs at 48 kHz
// almost always, and Windows converts for us when it can, so this is the rare path).
struct Converter {
    double pos = 0;  // where the next output sample falls, in input samples after `prev`
    float prev[2] = {0, 0};
    bool have_prev = false;

    static float sample(const BYTE* p, int bits, bool is_float) {
        if (is_float) return *reinterpret_cast<const float*>(p);
        switch (bits) {
            case 16: return *reinterpret_cast<const int16_t*>(p) / 32768.0f;
            case 24: {
                const int32_t v = (p[0] << 8) | (p[1] << 16) | (p[2] << 24);
                return static_cast<float>(v / 2147483648.0);
            }
            case 32: return static_cast<float>(*reinterpret_cast<const int32_t*>(p) / 2147483648.0);
            default: return 0;
        }
    }

    void run(const BYTE* data, UINT32 frames, bool silent, const Loopback& lb, std::vector<float>& out) {
        const int bps = lb.bits / 8;
        const int stride = bps * lb.channels;
        std::vector<float> st(static_cast<size_t>(frames) * 2);
        for (UINT32 i = 0; i < frames; ++i) {
            if (silent || !data) {
                st[i * 2] = st[i * 2 + 1] = 0;
                continue;
            }
            const BYTE* f = data + static_cast<size_t>(i) * stride;
            const float l = sample(f, lb.bits, lb.is_float);
            const float r = lb.channels > 1 ? sample(f + bps, lb.bits, lb.is_float) : l;
            st[i * 2] = l;
            st[i * 2 + 1] = r;
        }
        if (lb.rate == kRate) {
            out.insert(out.end(), st.begin(), st.end());
            return;
        }
        const double step = static_cast<double>(lb.rate) / kRate;
        for (UINT32 i = 0; i < frames; ++i) {
            if (!have_prev) {
                prev[0] = st[0];
                prev[1] = st[1];
                have_prev = true;
                continue;
            }
            while (pos < 1.0) {
                const float a = static_cast<float>(pos);
                out.push_back(prev[0] + (st[i * 2] - prev[0]) * a);
                out.push_back(prev[1] + (st[i * 2 + 1] - prev[1]) * a);
                pos += step;
            }
            pos -= 1.0;
            prev[0] = st[i * 2];
            prev[1] = st[i * 2 + 1];
        }
    }
};

// Windows' AAC encoder (a synchronous MFT that ships with Windows), raw AAC frames out.
struct Aac {
    ComPtr<IMFTransform> mft;
    std::vector<int16_t> pcm;  // waiting for a whole frame
    int64_t fed = 0;           // samples given to the encoder
    int64_t outputs = 0;       // frames it gave back

    bool open(std::string& err) {
        HRESULT hr = CoCreateInstance(CLSID_AACMFTEncoder, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&mft));
        if (FAILED(hr)) {
            err = "AAC encoder: " + hr_text(hr);
            return false;
        }
        ComPtr<IMFMediaType> in, out;
        MFCreateMediaType(&in);
        in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        in->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
        in->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        in->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kRate);
        in->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
        in->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 4);
        in->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, kRate * 4);
        hr = mft->SetInputType(0, in.Get(), 0);
        if (FAILED(hr)) {
            err = "AAC input: " + hr_text(hr);
            return false;
        }
        MFCreateMediaType(&out);
        out->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        out->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
        out->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
        out->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kRate);
        out->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 2);
        out->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 20000);  // 160 kbit/s
        out->SetUINT32(MF_MT_AAC_PAYLOAD_TYPE, 0);                 // raw: we write the ADTS headers
        out->SetUINT32(MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION, 0x29);
        hr = mft->SetOutputType(0, out.Get(), 0);
        if (FAILED(hr)) {
            err = "AAC output: " + hr_text(hr);
            return false;
        }
        mft->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
        mft->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
        return true;
    }

    // Takes stereo float at 48 kHz; calls `frame` with each raw AAC frame and its index.
    template <class F>
    bool push(const std::vector<float>& st, F&& frame) {
        for (float v : st) {
            const float c = std::clamp(v, -1.0f, 1.0f);
            pcm.push_back(static_cast<int16_t>(std::lrint(c * 32767.0f)));
        }
        while (pcm.size() >= kAacFrame * 2) {
            ComPtr<IMFSample> s;
            ComPtr<IMFMediaBuffer> b;
            const DWORD bytes = kAacFrame * 4;
            MFCreateSample(&s);
            MFCreateMemoryBuffer(bytes, &b);
            BYTE* p = nullptr;
            b->Lock(&p, nullptr, nullptr);
            std::memcpy(p, pcm.data(), bytes);
            b->Unlock();
            b->SetCurrentLength(bytes);
            s->AddBuffer(b.Get());
            s->SetSampleTime(fed * 10'000'000 / kRate);
            s->SetSampleDuration(kAacFrame * 10'000'000LL / kRate);
            pcm.erase(pcm.begin(), pcm.begin() + kAacFrame * 2);
            HRESULT hr = mft->ProcessInput(0, s.Get(), 0);
            if (FAILED(hr)) {
                logf("sound: AAC input failed (%s)", hr_text(hr).c_str());
                return false;
            }
            fed += kAacFrame;
            for (;;) {
                MFT_OUTPUT_STREAM_INFO info{};
                mft->GetOutputStreamInfo(0, &info);
                ComPtr<IMFSample> os;
                ComPtr<IMFMediaBuffer> ob;
                MFCreateSample(&os);
                MFCreateMemoryBuffer(std::max<DWORD>(info.cbSize, 8192), &ob);
                os->AddBuffer(ob.Get());
                MFT_OUTPUT_DATA_BUFFER od{};
                od.pSample = os.Get();
                DWORD status = 0;
                hr = mft->ProcessOutput(0, 1, &od, &status);
                if (od.pEvents) od.pEvents->Release();
                if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) break;
                if (FAILED(hr)) {
                    logf("sound: AAC output failed (%s)", hr_text(hr).c_str());
                    return false;
                }
                BYTE* q = nullptr;
                DWORD len = 0;
                ob->Lock(&q, nullptr, &len);
                std::vector<uint8_t> raw(q, q + len);
                ob->Unlock();
                if (!raw.empty() && !frame(raw, outputs++)) return false;
            }
        }
        return true;
    }
};

}  // namespace

AudioStream::AudioStream(Link link, SendControl control) : link_(std::move(link)), control_(std::move(control)) {
    since_ = now_us();
    thread_ = std::thread([this] { run(); });
}

AudioStream::~AudioStream() {
    stop();
}

void AudioStream::stop() {
    stop_ = true;
    if (thread_.joinable()) thread_.join();
}

void AudioStream::take_stats(double& kbps, int& frames) {
    std::lock_guard g(stats_lock_);
    const int64_t now = now_us();
    const double secs = std::max(0.001, (now - since_) / 1e6);
    kbps = bytes_ * 8 / 1000.0 / secs;
    frames = frames_;
    bytes_ = 0;
    frames_ = 0;
    since_ = now;
}

void AudioStream::run() {
    name_thread(L"pcw sound");
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    auto error = [&](const char* what) {
        json::Value e = json::Value::object();
        e.set("t", "error").set("what", what);
        control_(e);
    };
    std::string err;
    std::unique_ptr<TlsClient> conn;
    auto connect = [&]() -> bool {
        for (int attempt = 0; attempt < 4 && !stop_; ++attempt) {
            if (attempt) Sleep(500u << attempt);
            conn = open_stream_connection(link_, 0, err);
            if (conn) return true;
            logf("sound: connection failed (%s)", err.c_str());
        }
        return false;
    };
    if (!connect()) {
        error("stream connection");
        finished_ = true;
        CoUninitialize();
        return;
    }

    while (!stop_) {
        Loopback lb;
        Aac aac;
        Converter conv;
        if (!lb.open(err) || !aac.open(err)) {
            logf("sound: %s; trying again", err.c_str());
            for (int i = 0; i < 20 && !stop_; ++i) Sleep(100);
            continue;
        }
        // Where each 48 kHz sample index falls on the PC's clock, from the device's own times for its packets, so
        // the sound's times never drift from the pictures' however long it runs.
        std::deque<std::pair<int64_t, int64_t>> anchors;  // (sample index, us)
        int64_t produced = 0;
        int64_t next_device_check = now_us() + 1'000'000;
        bool reopen = false;
        auto time_of = [&](int64_t index) -> int64_t {
            while (anchors.size() > 2 && anchors[1].first <= index) anchors.pop_front();
            if (anchors.empty()) return now_us();
            return anchors.front().second + (index - anchors.front().first) * 1'000'000 / kRate;
        };
        auto send_frame = [&](const std::vector<uint8_t>& raw, int64_t index) -> bool {
            std::vector<uint8_t> f(7 + raw.size());
            media::adts_header(f.data(), raw.size(), kRate, 2);
            std::memcpy(f.data() + 7, raw.data(), raw.size());
            const int64_t t = time_of(index * kAacFrame);
            if (!send_packet(*conn, PacketKind::Sound, 0, t, f.data(), f.size())) return false;
            std::lock_guard g(stats_lock_);
            bytes_ += static_cast<int64_t>(f.size());
            ++frames_;
            return true;
        };
        while (!stop_ && !reopen) {
            Sleep(10);
            lb.feed_silence();
            UINT32 n = 0;
            HRESULT hr;
            while (SUCCEEDED(hr = lb.cap->GetNextPacketSize(&n)) && n) {
                BYTE* data = nullptr;
                UINT32 frames = 0;
                DWORD flags = 0;
                UINT64 devpos = 0, qpc = 0;
                hr = lb.cap->GetBuffer(&data, &frames, &flags, &devpos, &qpc);
                if (FAILED(hr)) break;
                anchors.emplace_back(produced, static_cast<int64_t>(qpc / 10));
                std::vector<float> st;
                conv.run(data, frames, (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0, lb, st);
                lb.cap->ReleaseBuffer(frames);
                produced += static_cast<int64_t>(st.size() / 2);
                if (!aac.push(st, send_frame)) {
                    if (conn->closed() || !connect()) {
                        error("stream connection");
                        stop_ = true;
                    }
                    reopen = true;
                    break;
                }
            }
            if (FAILED(hr)) {
                logf("sound: the device went (%s); opening the default one again", hr_text(hr).c_str());
                reopen = true;
            }
            if (now_us() >= next_device_check) {
                next_device_check = now_us() + 1'000'000;
                if (lb.default_id() != lb.dev_id) {
                    logf("sound: the default output device changed");
                    reopen = true;
                }
            }
        }
    }
    if (conn) conn->close();
    finished_ = true;
    CoUninitialize();
}

}  // namespace pcw
