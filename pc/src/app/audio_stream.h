// The PC's sound to the headset (stream 0): WASAPI loopback of the default output device, 48 kHz stereo, encoded
// by Windows' own AAC encoder (AAC-LC, 160 kbit/s), each frame with an ADTS header and the PC's clock.
#pragma once

#include <atomic>
#include <mutex>
#include <string>
#include <thread>

#include "video_stream.h"

namespace pcw {

class AudioStream {
public:
    AudioStream(Link link, SendControl control);
    ~AudioStream();
    AudioStream(const AudioStream&) = delete;
    AudioStream& operator=(const AudioStream&) = delete;

    void stop();
    bool finished() const { return finished_.load(); }
    // kbit/s and frames since the last call.
    void take_stats(double& kbps, int& frames);

private:
    void run();

    Link link_;
    SendControl control_;
    std::atomic<bool> stop_{false};
    std::atomic<bool> finished_{false};
    std::thread thread_;
    std::mutex stats_lock_;
    int64_t bytes_ = 0;
    int frames_ = 0;
    int64_t since_ = 0;
};

}  // namespace pcw
