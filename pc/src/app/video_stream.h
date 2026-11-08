// One window or monitor going to the headset: its capture, the GPU conversion, the encoder and its stream
// connection, on a thread of its own (and the encoder's event thread). Ends by itself when the window closes, the
// headset closes the stream, or it cannot go on; the session then forgets it.
#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

#include "../core/json.h"
#include "../core/media.h"
#include "../core/protocol.h"
#include "../core/stats.h"
#include "tls.h"

namespace pcw {

// Where stream connections go and how they prove who they are.
struct Link {
    uint32_t address = 0;
    uint16_t port = kPort;
    std::string pin;
    std::string token;
};

using SendControl = std::function<void(const json::Value&)>;

// Dials a stream connection and sends its first line. Nothing on failure (with the reason in `error`).
std::unique_ptr<TlsClient> open_stream_connection(const Link& link, int stream, std::string& error);
// One packet: the PCW1 header and its payload.
bool send_packet(TlsClient& c, PacketKind kind, uint8_t flags, int64_t time_us, const uint8_t* data, size_t size);

struct StreamRequest {
    int stream = 1;
    std::string id;
    int max_w = 1920, max_h = 1080;
    int fps = 30;
    int kbps = 8000;
};

struct StreamStats {
    int stream = 0;
    std::string id;
    std::string codec;
    int w = 0, h = 0;
    double fps = 0, kbps = 0;  // measured over the last report period
    double captured_fps = 0;   // frames Windows delivered (more than sent when the window changes faster)
    double lat_p50_ms = 0, lat_p95_ms = 0, lat_max_ms = 0;  // capture to sent
    int requested_kbps = 0, requested_fps = 0;
    bool minimised = false;
};

class VideoStream {
public:
    VideoStream(StreamRequest req, Link link, std::optional<media::Codec> force_codec, SendControl control);
    ~VideoStream();
    VideoStream(const VideoStream&) = delete;
    VideoStream& operator=(const VideoStream&) = delete;

    void set_quality(int fps, int kbps);
    void stop();  // and wait for its threads
    bool finished() const { return finished_.load(); }
    int stream() const { return req_.stream; }
    const std::string& id() const { return req_.id; }
    // The size being sent (0 before the first picture): mouse positions come in these pixels.
    void size(int& w, int& h) const {
        w = size_w_;
        h = size_h_;
    }
    // Numbers since the last call (for the log every few seconds).
    StreamStats take_stats();

private:
    void run();
    void wake();

    StreamRequest req_;
    Link link_;
    std::optional<media::Codec> force_codec_;
    SendControl control_;
    std::atomic<int> fps_, kbps_;
    std::atomic<int> size_w_{0}, size_h_{0};
    std::atomic<bool> stop_{false};
    std::atomic<bool> finished_{false};
    std::mutex wake_lock_;
    std::condition_variable wake_cv_;
    bool woken_ = false;
    std::thread thread_;

    // Filled by the encoder's thread as frames are sent, read by take_stats().
    std::mutex stats_lock_;
    StreamStats stats_;
    Samples latency_ms_;
    int64_t period_start_us_ = 0;
    int64_t period_bytes_ = 0;
    int period_frames_ = 0;
    std::atomic<int> arrived_{0};
};

}  // namespace pcw
