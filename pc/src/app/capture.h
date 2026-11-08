// One Windows.Graphics.Capture session for a window or a monitor, by handle (no picker). Frames come only when
// the picture changed; the newest one waits here (older ones are dropped) until the stream's thread takes it.
#pragma once

#include <d3d11.h>

#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>

#include "util.h"
#include "window_list.h"

namespace pcw {

// Once at start-up: asks Windows to let capture go without the yellow border (Windows 11; harmless elsewhere).
void capture_init();
bool capture_supported();

class Capture {
public:
    Capture();
    ~Capture();
    Capture(const Capture&) = delete;
    Capture& operator=(const Capture&) = delete;

    // `wake` is called (from a capture thread) when a frame comes or the item closes.
    bool start(ID3D11Device* device, const Target& target, std::function<void()> wake, std::string& error);
    void stop();

    // Copies the newest frame's picture into `dst` (made again at the picture's size when that changed) and gives
    // its size, its time (when Windows composed it, the PC's clock in us; it can be a little ahead of now) and when
    // it reached us. False when no new frame came since the last call.
    // A frame smaller than half of `min_w` x `min_h` on both sides is dropped instead: Windows hands over a frame
    // or two at the taskbar button's size as a window is restored, which is not its picture.
    bool take(ID3D11DeviceContext* ctx, ComPtr<ID3D11Texture2D>& dst, int& w, int& h, int64_t& time_us,
              int64_t& arrived_us, int min_w = 0, int min_h = 0);

    // Drops the waiting frame (a minimised window's frames are not its picture).
    void discard();

    // The window was closed (or the monitor went).
    bool closed() const;

    // At most this many frames a second from Windows (Windows 11 24H2 and later; ignored before).
    void set_max_rate(int fps);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace pcw
