// The windows and monitors the headset may open: the top-level windows Alt+Tab would show (visible, titled, not
// tool windows, not cloaked) and each monitor. Sizes are physical pixels: the process is per-monitor-v2 DPI aware.
#pragma once

#include <windows.h>

#include <optional>
#include <string>
#include <vector>

#include "../core/mapping.h"

namespace pcw {

struct Target {
    std::string id;  // "w:<handle, hex>" or "m:<monitor index>"
    bool monitor = false;
    HWND hwnd = nullptr;
    HMONITOR hmon = nullptr;
};

struct WindowInfo {
    Target target;
    std::wstring title;  // stays on this PC except in the `windows` message to the paired headset; never logged
    std::string app;     // the exe's name
    int w = 0, h = 0;    // the captured picture's size
    bool minimised = false;
};

struct ListOptions {
    bool monitors = true;
    // Test-only: list only windows whose title starts with this, and monitors without thumbnails, so the
    // end-to-end test never sees the PC's real windows.
    std::wstring only_titles;
};

std::vector<WindowInfo> list_windows(const ListOptions& options);

// Parses an id and checks the window or monitor is still there.
std::optional<Target> find_target(const std::string& id);

// The rectangle the captured picture shows, on the virtual desktop, in physical pixels: the window's extended
// frame bounds (what Windows.Graphics.Capture captures: the frame without the invisible resize borders), or the
// monitor. Nothing when the window has gone.
std::optional<mapping::Rect> captured_rect(const Target& t);

bool is_minimised(const Target& t);

// A JPEG of at most `max_side` pixels on its long side, base64; empty when the window cannot be drawn (minimised,
// hung, gone).
std::string thumbnail_base64(const WindowInfo& w, int max_side, bool allow_monitor_capture);

}  // namespace pcw
