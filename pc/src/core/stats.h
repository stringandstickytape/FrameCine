// Running numbers for the log: latencies per frame, bytes per second.
#pragma once

#include <algorithm>
#include <cstdint>
#include <vector>

namespace pcw {

// Keeps samples since the last report; percentiles are taken on a copy.
class Samples {
public:
    void add(double v) {
        if (v_.size() < 100000) v_.push_back(v);
    }
    size_t count() const { return v_.size(); }
    // p in 0..1, nearest rank; 0 when empty.
    double percentile(double p) const {
        if (v_.empty()) return 0;
        std::vector<double> s = v_;
        size_t k = static_cast<size_t>(p * static_cast<double>(s.size() - 1) + 0.5);
        k = std::min(k, s.size() - 1);
        std::nth_element(s.begin(), s.begin() + static_cast<ptrdiff_t>(k), s.end());
        return s[k];
    }
    void clear() { v_.clear(); }

private:
    std::vector<double> v_;
};

}  // namespace pcw
