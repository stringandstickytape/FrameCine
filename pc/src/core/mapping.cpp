#include "mapping.h"

#include <algorithm>
#include <cmath>

namespace pcw::mapping {

Point stream_to_screen(double x, double y, int stream_w, int stream_h, const Rect& r) {
    const int w = std::max(1, r.width()), h = std::max(1, r.height());
    const double sx = stream_w > 0 ? static_cast<double>(w) / stream_w : 1.0;
    const double sy = stream_h > 0 ? static_cast<double>(h) / stream_h : 1.0;
    if (!std::isfinite(x)) x = 0;
    if (!std::isfinite(y)) y = 0;
    const double px = std::floor(x * sx), py = std::floor(y * sy);
    Point p;
    p.x = r.left + static_cast<int32_t>(std::clamp(px, 0.0, static_cast<double>(w - 1)));
    p.y = r.top + static_cast<int32_t>(std::clamp(py, 0.0, static_cast<double>(h - 1)));
    return p;
}

static int32_t axis_to_absolute(int32_t v, int32_t origin, int32_t size) {
    size = std::max(1, size);
    const int64_t rel = std::clamp<int64_t>(int64_t{v} - origin, 0, size - 1);
    const int64_t n = (rel * 65536 + 32768) / size;  // (rel + 0.5) of a pixel, in 1/65536ths of the desktop
    return static_cast<int32_t>(std::clamp<int64_t>(n, 0, 65535));
}

static int32_t axis_from_absolute(int32_t n, int32_t origin, int32_t size) {
    return origin + static_cast<int32_t>((int64_t{n} * std::max(1, size)) / 65536);
}

Point to_absolute(Point s, const Rect& vd) {
    return {axis_to_absolute(s.x, vd.left, vd.width()), axis_to_absolute(s.y, vd.top, vd.height())};
}

Point from_absolute(Point a, const Rect& vd) {
    return {axis_from_absolute(a.x, vd.left, vd.width()), axis_from_absolute(a.y, vd.top, vd.height())};
}

void fit_size(int w, int h, int max_w, int max_h, int min_w, int min_h, int& out_w, int& out_h) {
    w = std::max(1, w);
    h = std::max(1, h);
    if (max_w <= 0) max_w = w;
    if (max_h <= 0) max_h = h;
    double s = std::min({1.0, static_cast<double>(max_w) / w, static_cast<double>(max_h) / h});
    int ow = static_cast<int>(std::lround(w * s));
    int oh = static_cast<int>(std::lround(h * s));
    if (ow < min_w || oh < min_h) {
        // Too small for an encoder: larger, both axes alike so the pane keeps the window's shape, rounded up to
        // even so it stays at least the minimum.
        const double up = std::max(static_cast<double>(min_w) / ow, static_cast<double>(min_h) / oh);
        ow = static_cast<int>(std::ceil(ow * up - 1e-9));
        oh = static_cast<int>(std::ceil(oh * up - 1e-9));
        out_w = std::max(2, (ow + 1) & ~1);
        out_h = std::max(2, (oh + 1) & ~1);
    } else {
        // Rounded down to even, so it never passes the limit.
        out_w = std::max(2, ow & ~1);
        out_h = std::max(2, oh & ~1);
    }
}

}  // namespace pcw::mapping
