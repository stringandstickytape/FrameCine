// From a point in a stream's picture to the real screen, and on to SendInput's absolute units.
#pragma once

#include <cstdint>

namespace pcw::mapping {

struct Rect {
    int32_t left = 0, top = 0, right = 0, bottom = 0;
    int32_t width() const { return right - left; }
    int32_t height() const { return bottom - top; }
};

struct Point {
    int32_t x = 0, y = 0;
};

// (x, y) in the stream's pixels (0..stream_w, 0..stream_h, floats; a pixel's centre is +0.5) to a screen pixel in
// `captured`, the rectangle the captured picture shows (a window's extended frame bounds, or a monitor), in
// physical pixels. The stream may be scaled from the capture; each axis scales on its own. The result is kept
// inside the rectangle so a stray point never clicks another window.
Point stream_to_screen(double x, double y, int stream_w, int stream_h, const Rect& captured);

// A screen pixel to SendInput's absolute coordinates over the virtual desktop (MOUSEEVENTF_VIRTUALDESK): 0..65535
// on each axis, aimed at the pixel's middle so Windows' rounding lands on it.
Point to_absolute(Point screen, const Rect& virtual_desktop);

// What Windows does with an absolute coordinate (for the tests): the pixel it lands on.
Point from_absolute(Point absolute, const Rect& virtual_desktop);

// Fits (w, h) inside (max_w, max_h), keeping the aspect, never larger than it was, both even. Encoders refuse tiny
// pictures, so one smaller than min_w x min_h is scaled up (keeping its aspect) until it is not.
void fit_size(int w, int h, int max_w, int max_h, int min_w, int min_h, int& out_w, int& out_h);

}  // namespace pcw::mapping
