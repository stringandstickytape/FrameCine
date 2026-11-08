// The session with the headset: finding it, pairing, the control connection (JSON lines both ways), and the
// streams it asks for. Dials again by itself whenever the connection goes (headset off, Wi-Fi gone).
#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "../core/json.h"
#include "../core/media.h"
#include "audio_stream.h"
#include "discovery.h"
#include "store.h"
#include "tls.h"
#include "video_stream.h"
#include "window_list.h"

namespace pcw {

struct Options {
    uint16_t port = kPort;
    std::vector<uint32_t> headsets;            // asked directly as well as by broadcast (--headset)
    std::string code;                          // pair with the first headset that offers it (--code)
    std::optional<media::Codec> force_codec;   // --codec h264|hevc
    ListOptions list;                          // --only-titles, --no-monitors
    int stats_every_s = 5;
};

struct Status {
    bool found = false;        // a headset answered
    bool offers_pairing = false;
    bool paired = false;
    bool connected = false;
    std::string headset;       // its name
    std::string message;       // the latest thing worth saying (a refusal, an error)
    std::vector<std::wstring> sending;  // titles of what is being sent (shown on this PC only)
    std::wstring encoder;
    bool sound = false;
};

class Session {
public:
    explicit Session(Options options);
    ~Session();
    Session(const Session&) = delete;
    Session& operator=(const Session&) = delete;

    void stop();
    Status status();
    // The code the headset shows; used with the headset that offers pairing.
    void pair(std::string code);
    void forget();
    // Called (from any thread) when the status changed.
    void set_on_change(std::function<void()> f);
    // A line for the headset to show the viewer (sent as an `error`, which the headset shows; nothing when not
    // connected).
    void notice(const std::string& what);
    // Sending stopped at the PC (Ctrl+Alt+Shift+F12): every stream and the sound end, and the headset's `open` is
    // refused until it is allowed again.
    void set_sending(bool on);
    bool sending() const { return sending_.load(); }

private:
    std::atomic<bool> sending_{true};
    struct Found {
        uint32_t address = 0;
        HereMessage here;
        int64_t seen_us = 0;
    };

    void control_loop();
    void watch_loop();
    bool session_once(uint32_t address, uint16_t port, const std::string& pin, const std::string& name,
                      const std::string& code);
    void handle(const json::Value& m);
    void send(const json::Value& m);
    void send_windows();
    void stop_streams();
    void changed();
    Link link() const;

    Options opt_;
    std::string pc_name_;
    // The last connect failure logged, when, and how many like it since (session_once).
    std::string last_fail_;
    int64_t last_fail_logged_ = 0;
    int fails_unlogged_ = 0;
    std::atomic<bool> stop_{false};
    std::unique_ptr<Discovery> discovery_;

    mutable std::mutex lock_;  // guards the fields below
    std::optional<Pairing> pairing_;
    std::map<std::string, Found> found_;  // by pin
    std::string pending_code_;
    Status status_;
    std::function<void()> on_change_;

    std::mutex conn_lock_;
    std::shared_ptr<TlsClient> conn_;

    std::mutex streams_lock_;
    std::map<int, std::unique_ptr<VideoStream>> streams_;
    std::unique_ptr<AudioStream> audio_;

    std::atomic<bool> list_wanted_{false};
    std::mutex mouse_lock_;
    std::string mouse_id_;  // the window the mouse was last over, for its cursor shape

    std::mutex wake_lock_;
    std::condition_variable wake_cv_;
    std::thread control_thread_;
    std::thread watch_thread_;
};

}  // namespace pcw
