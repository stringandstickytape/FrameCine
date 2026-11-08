#include "video_stream.h"

#include <mfapi.h>
#include <timeapi.h>

#include "../core/mapping.h"
#include "capture.h"
#include "log.h"
#include "util.h"
#include "video_encoder.h"
#include "window_list.h"

namespace pcw {

namespace {

constexpr int64_t kKeyEvery = 2'000'000;    // a key frame at least this often (us)
constexpr int64_t kRefreshEvery = 2'000'000; // a frame at least this often, changed or not
constexpr int64_t kSettleAfter = 250'000;   // the same picture again once it stops changing, for sharper text
constexpr int kMinW = 256, kMinH = 128;     // encoders refuse smaller pictures

json::Value msg(const char* type) {
    json::Value v = json::Value::object();
    v.set("t", type);
    return v;
}

}  // namespace

std::unique_ptr<TlsClient> open_stream_connection(const Link& link, int stream, std::string& error) {
    auto c = std::make_unique<TlsClient>();
    if (!c->connect(link.address, link.port, link.pin, 5000, error)) return nullptr;
    json::Value first = msg("stream");
    first.set("v", kProtocolVersion).set("token", link.token).set("stream", stream);
    if (!c->send_line(first.dump())) {
        error = "stream connection closed at once";
        return nullptr;
    }
    return c;
}

bool send_packet(TlsClient& c, PacketKind kind, uint8_t flags, int64_t time_us, const uint8_t* data, size_t size) {
    // One buffer for header and payload: one write, and no small TLS record for the header alone.
    std::vector<uint8_t> b(kPacketHeaderSize + size);
    PacketHeader h;
    h.kind = kind;
    h.flags = flags;
    h.time_us = time_us;
    h.length = static_cast<uint32_t>(size);
    write_packet_header(h, b.data());
    if (size) std::memcpy(b.data() + kPacketHeaderSize, data, size);
    return c.send_all(b.data(), b.size());
}

VideoStream::VideoStream(StreamRequest req, Link link, std::optional<media::Codec> force_codec, SendControl control)
    : req_(std::move(req)),
      link_(std::move(link)),
      force_codec_(force_codec),
      control_(std::move(control)),
      fps_(std::clamp(req_.fps, 1, 240)),
      kbps_(std::clamp(req_.kbps, 100, 500000)) {
    stats_.stream = req_.stream;
    stats_.id = req_.id;
    period_start_us_ = now_us();
    thread_ = std::thread([this] { run(); });
}

VideoStream::~VideoStream() {
    stop();
}

void VideoStream::stop() {
    stop_ = true;
    wake();
    if (thread_.joinable()) thread_.join();
}

void VideoStream::wake() {
    {
        std::lock_guard g(wake_lock_);
        woken_ = true;
    }
    wake_cv_.notify_one();
}

void VideoStream::set_quality(int fps, int kbps) {
    if (fps > 0) fps_ = std::clamp(fps, 1, 240);
    if (kbps > 0) kbps_ = std::clamp(kbps, 100, 500000);
    wake();
}

StreamStats VideoStream::take_stats() {
    std::lock_guard g(stats_lock_);
    const int64_t now = now_us();
    const double secs = std::max(0.001, (now - period_start_us_) / 1e6);
    StreamStats s = stats_;
    s.fps = period_frames_ / secs;
    s.kbps = period_bytes_ * 8 / 1000.0 / secs;
    s.lat_p50_ms = latency_ms_.percentile(0.5);
    s.lat_p95_ms = latency_ms_.percentile(0.95);
    s.lat_max_ms = latency_ms_.percentile(1.0);
    s.requested_fps = fps_;
    s.requested_kbps = kbps_;
    s.captured_fps = arrived_.exchange(0) / secs;
    latency_ms_.clear();
    period_frames_ = 0;
    period_bytes_ = 0;
    period_start_us_ = now;
    return s;
}

void VideoStream::run() {
    name_thread(L"pcw stream");
    // Waits for the next frame's turn are a few ms; Windows' default timer (15.6 ms) would add up to a frame of
    // delay. The finer timer is asked for only while a stream runs.
    struct FineTimer {
        FineTimer() { timeBeginPeriod(1); }
        ~FineTimer() { timeEndPeriod(1); }
    } fine_timer;
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const std::string& id = req_.id;
    auto error = [&](const char* what) {
        json::Value e = msg("error");
        e.set("what", what).set("id", id);
        control_(e);
    };

    std::string err;
    std::optional<Target> target = find_target(id);
    if (!target) {
        logf("stream %d: %s is not there", req_.stream, id.c_str());
        json::Value c = msg("closed");
        c.set("id", id);
        control_(c);
        finished_ = true;
        CoUninitialize();
        return;
    }
    const std::optional<EncoderChoice> choice = choose_encoder(force_codec_);
    if (!choice) {
        logf("stream %d: no hardware video encoder on this PC", req_.stream);
        error("no encoder");
        finished_ = true;
        CoUninitialize();
        return;
    }
    const char* codec_name = choice->codec == media::Codec::Hevc ? "hevc" : "h264";
    ComPtr<ID3D11Device> device = make_device(*choice, err);
    ComPtr<ID3D11DeviceContext> ctx;
    ComPtr<IMFDXGIDeviceManager> manager;
    UINT reset_token = 0;
    if (device) {
        device->GetImmediateContext(&ctx);
        if (FAILED(MFCreateDXGIDeviceManager(&reset_token, &manager)) ||
            FAILED(manager->ResetDevice(device.Get(), reset_token))) {
            manager.Reset();
        }
    }
    if (!device || !manager) {
        logf("stream %d: no GPU device (%s)", req_.stream, err.c_str());
        error("no encoder");
        finished_ = true;
        CoUninitialize();
        return;
    }

    Capture cap;
    if (!cap.start(device.Get(), *target, [this] {
            ++arrived_;
            wake();
        }, err)) {
        logf("stream %d: %s", req_.stream, err.c_str());
        error("capture");
        finished_ = true;
        CoUninitialize();
        return;
    }
    int applied_fps = fps_, applied_kbps = kbps_;
    int enc_fps = applied_fps;  // the frame rate the encoder was opened with
    cap.set_max_rate(applied_fps);

    // The stream connection: the encoder's thread writes to it, this thread replaces it when it breaks.
    std::mutex conn_lock;
    std::shared_ptr<TlsClient> conn;
    std::atomic<bool> conn_lost{false};
    std::atomic<bool> wire_needs_key{true};       // after (re)connecting, nothing until a key frame
    std::atomic<uint32_t> config_pending{0};      // the serial whose first key frame carries "config change"
    VideoEncoder enc;
    Converter conv;
    uint32_t serial = 0;
    int enc_w = 0, enc_h = 0;
    bool need_key = true;
    bool announced = false;  // `stream` sent for this connection

    auto on_output = [&](EncodedFrame&& f) {
        std::shared_ptr<TlsClient> c;
        {
            std::lock_guard g(conn_lock);
            c = conn;
        }
        if (!c || c->closed()) return;
        if (wire_needs_key && !f.key) return;  // the decoder could not use it
        uint8_t flags = f.key ? kFlagKeyFrame : 0;
        if (f.key && config_pending.load() == f.serial) {
            flags |= kFlagConfigChange;
            config_pending = 0;
        }
        if (!send_packet(*c, PacketKind::Video, flags, f.time_us, f.data.data(), f.data.size())) {
            conn_lost = true;
            wake();
            return;
        }
        if (f.key) wire_needs_key = false;
        const double lat = (now_us() - f.capture_us) / 1000.0;
        std::lock_guard g(stats_lock_);
        latency_ms_.add(lat);
        period_bytes_ += static_cast<int64_t>(f.data.size());
        ++period_frames_;
    };

    auto announce = [&] {
        json::Value s = msg("stream");
        s.set("stream", req_.stream).set("id", id).set("codec", codec_name).set("bits", 8).set("w", enc_w).set("h",
                                                                                                             enc_h);
        control_(s);
        announced = true;
    };

    auto connect = [&]() -> bool {
        {
            std::lock_guard g(conn_lock);
            if (conn) conn->close();
            conn.reset();
        }
        for (int attempt = 0; attempt < 4 && !stop_; ++attempt) {
            if (attempt) Sleep(500u << attempt);
            auto c = open_stream_connection(link_, req_.stream, err);
            if (c) {
                logf("stream %d: connected (%s)", req_.stream, c->tls_version().c_str());
                wire_needs_key = true;
                config_pending = serial;
                need_key = true;
                conn_lost = false;
                announced = false;
                std::lock_guard g(conn_lock);
                conn = std::move(c);
                return true;
            }
            logf("stream %d: connection failed (%s)", req_.stream, err.c_str());
        }
        return false;
    };

    auto open_encoder = [&](int w, int h) -> bool {
        enc.close();
        conv.reset();
        ++serial;
        if (!enc.open(device.Get(), manager.Get(), *choice, w, h, applied_fps, applied_kbps, serial, on_output,
                      [this] { wake(); }, err)) {
            logf("stream %d: %s", req_.stream, err.c_str());
            return false;
        }
        enc_fps = applied_fps;
        enc_w = w;
        enc_h = h;
        size_w_ = w;
        size_h_ = h;
        config_pending = serial;
        need_key = true;
        {
            std::lock_guard g(stats_lock_);
            stats_.w = w;
            stats_.h = h;
            stats_.codec = codec_name;
        }
        logf("stream %d: %s %s %dx%d, %d fps, %d kbit/s", req_.stream, codec_name, to_utf8(choice->name).c_str(), w, h,
             applied_fps, applied_kbps);
        return true;
    };

    if (!connect()) {
        error("stream connection");
        cap.stop();
        finished_ = true;
        CoUninitialize();
        return;
    }

    ComPtr<ID3D11Texture2D> last;  // the newest picture, kept: sent again while nothing changes or when minimised
    int cw = 0, ch = 0;
    bool have_picture = false, fresh = false, minimised = false;
    int64_t pic_time = 0, pic_arrived = 0, last_encode = 0, last_key = 0, settle_at = 0, last_time = 0;
    // The frame rate is kept by a token bucket: `fps` tokens a second, at most two saved up, one per frame sent.
    // Frames that come with jitter (a 60 Hz window on a 60 Hz desktop) are all sent, and never more than `fps` a
    // second on average.
    double tokens = 1;
    int64_t tokens_at = now_us();
    auto refill = [&](int64_t now) {
        tokens = std::min(2.0, tokens + static_cast<double>(now - tokens_at) * applied_fps / 1e6);
        tokens_at = now;
    };
    int encoder_failures = 0;
    bool blocked = false;  // a frame was due but the encoder had no room: wait for it to say so

    while (!stop_) {
        // Sleep until something happens or the next frame is due.
        {
            int64_t wait_us = 100'000;
            const int64_t now = now_us();
            refill(now);
            if (fresh) wait_us = std::min(wait_us, static_cast<int64_t>((1.0 - tokens) * 1e6 / std::max(1, applied_fps)));
            if (have_picture) {
                wait_us = std::min({wait_us, last_encode + kRefreshEvery - now, last_key + kKeyEvery - 100'000 - now});
            }
            if (settle_at) wait_us = std::min(wait_us, settle_at - now);
            if (blocked) wait_us = std::max<int64_t>(wait_us, 2'000);
            blocked = false;
            if (wait_us > 0) {
                std::unique_lock g(wake_lock_);
                wake_cv_.wait_for(g, std::chrono::microseconds(wait_us), [&] { return woken_; });
                woken_ = false;
            }
        }
        if (stop_) break;
        if (cap.closed() || (!target->monitor && !IsWindow(target->hwnd))) {
            logf("stream %d: the window closed", req_.stream);
            json::Value c = msg("closed");
            c.set("id", id);
            control_(c);
            break;
        }
        if (conn_lost) {
            logf("stream %d: connection lost; dialling again", req_.stream);
            if (!connect()) {
                error("stream connection");
                break;
            }
        }
        if (enc.failed()) {
            logf("stream %d: the encoder failed; starting it again", req_.stream);
            if (++encoder_failures > 3 || !open_encoder(enc_w, enc_h)) {
                error("no encoder");
                break;
            }
        }
        const bool now_min = is_minimised(*target);
        if (now_min != minimised) {
            minimised = now_min;
            logf("stream %d: %s", req_.stream, minimised ? "minimised (the last picture stays)" : "restored");
            if (minimised) error("minimised");
            std::lock_guard g(stats_lock_);
            stats_.minimised = minimised;
        }
        // Rate changes from `quality`, live: no new encoder, no new key frame. The encoder budgets each frame as
        // bitrate / the frame rate it was opened with, so at another rate it is given the bitrate scaled to match,
        // and the stream comes out at the kbit/s asked for.
        if (kbps_ != applied_kbps || fps_ != applied_fps) {
            const bool fps_changed = fps_ != applied_fps;
            applied_kbps = kbps_;
            applied_fps = fps_;
            const int64_t scaled = static_cast<int64_t>(applied_kbps) * enc_fps / std::max(1, applied_fps);
            enc.set_bitrate(static_cast<int>(std::clamp<int64_t>(scaled, 100, 400'000)));
            if (fps_changed) cap.set_max_rate(applied_fps);
        }

        int w = 0, h = 0;
        int64_t t = 0, arrived = 0;
        int expect_w = 0, expect_h = 0;
        if (!target->monitor) {
            if (auto r = captured_rect(*target)) {
                expect_w = r->width();
                expect_h = r->height();
            }
        }
        if (minimised) {
            // Windows may still hand over a frame or two as the window shrinks to the taskbar: not its picture.
            cap.discard();
        } else if (cap.take(ctx.Get(), last, w, h, t, arrived, expect_w, expect_h)) {
            have_picture = true;
            fresh = true;
            pic_time = t;
            pic_arrived = arrived;
            if (w != cw || h != ch) {
                cw = w;
                ch = h;
                int ew, eh;
                mapping::fit_size(cw, ch, req_.max_w, req_.max_h, kMinW, kMinH, ew, eh);
                if (ew != enc_w || eh != enc_h) {
                    const bool was_open = enc_w != 0;
                    if (!open_encoder(ew, eh)) {
                        error("no encoder");
                        break;
                    }
                    if (was_open && announced) {
                        json::Value r = msg("resized");
                        r.set("id", id).set("w", enc_w).set("h", enc_h);
                        control_(r);
                    }
                }
            }
            if (!announced && enc_w) announce();
        }
        if (!have_picture || !enc_w) continue;
        if (!announced) announce();

        const int64_t now = now_us();
        refill(now);
        bool due = false;
        if (fresh && tokens >= 1.0) {
            due = true;
        } else if (now - last_encode >= kRefreshEvery || now - last_key >= kKeyEvery - 100'000) {
            // Nothing changed: the same picture, so the headset knows we are here, and a key frame on time even
            // when the window went still just after one.
            due = true;
        } else if (settle_at && now >= settle_at) {
            due = true;
        }
        if (!due) continue;
        if (!enc.ready()) {
            blocked = true;
            continue;
        }
        ComPtr<ID3D11Texture2D> nv12;
        ComPtr<IMFSample> sample = enc.new_sample(nv12);
        if (!sample) {
            blocked = true;  // every texture is still in the encoder: this frame waits
            continue;
        }
        if (!conv.convert(device.Get(), ctx.Get(), last.Get(), cw, ch, nv12.Get(), enc_w, enc_h)) {
            if (++encoder_failures > 3) {
                error("no encoder");
                break;
            }
            continue;
        }
        // A little early rather than late: a repeat due at 2 s would otherwise just miss it and wait 2 s more.
        const bool key = need_key || now - last_key >= kKeyEvery - 100'000;
        // The capture's own time for a new picture; now for a repeat. Always rising, as the encoder needs.
        int64_t time = fresh ? pic_time : now;
        if (time <= last_time) time = last_time + 1;
        // Latency is counted from when the frame reached us (Windows' own time for it is when it was composed,
        // which can be ahead of now).
        const int64_t capture_us = fresh ? pic_arrived : now;
        if (!enc.encode(sample.Get(), time, capture_us, key)) {
            blocked = true;
            continue;
        }
        last_time = time;
        last_encode = now;
        tokens = std::max(-1.0, tokens - 1.0);
        if (key) {
            last_key = now;
            need_key = false;
        }
        settle_at = fresh ? now + kSettleAfter : 0;
        fresh = false;
    }

    enc.close();
    cap.stop();
    {
        std::lock_guard g(conn_lock);
        if (conn) conn->close();
        conn.reset();
    }
    finished_ = true;
    CoUninitialize();
}

}  // namespace pcw
