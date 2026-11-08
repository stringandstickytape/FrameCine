// Finding the headset: a pcw_find datagram every 2 s (to 255.255.255.255, each interface's broadcast address and
// any address we already know), and the pcw_here replies. Only replies from private addresses count.
#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "../core/protocol.h"

namespace pcw {

class Discovery {
public:
    using Found = std::function<void(uint32_t address, const HereMessage&)>;

    Discovery(std::string pc_name, uint16_t port, Found on_found);
    ~Discovery();

    void set_active(bool active) { active_ = active; }
    // Addresses asked directly as well (the paired headset's last address, --headset): some networks drop
    // broadcasts but pass unicast.
    void set_unicast(std::vector<uint32_t> addresses);

private:
    void run();

    std::string pc_name_;
    uint16_t port_;
    Found on_found_;
    std::atomic<bool> active_{true};
    std::atomic<bool> stop_{false};
    std::mutex lock_;
    std::vector<uint32_t> unicast_;
    std::thread thread_;
};

}  // namespace pcw
