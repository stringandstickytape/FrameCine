#include "discovery.h"

#include "net.h"  // Winsock first: mstcpip.h needs it

#include <mstcpip.h>

#ifndef SIO_UDP_CONNRESET
#define SIO_UDP_CONNRESET _WSAIOW(IOC_VENDOR, 12)
#endif

#include "log.h"
#include "util.h"

namespace pcw {

Discovery::Discovery(std::string pc_name, uint16_t port, Found on_found)
    : pc_name_(std::move(pc_name)), port_(port), on_found_(std::move(on_found)) {
    thread_ = std::thread([this] { run(); });
}

Discovery::~Discovery() {
    stop_ = true;
    if (thread_.joinable()) thread_.join();
}

void Discovery::set_unicast(std::vector<uint32_t> addresses) {
    std::lock_guard lock(lock_);
    unicast_ = std::move(addresses);
}

void Discovery::run() {
    name_thread(L"pcw discovery");
    SOCKET s = INVALID_SOCKET;
    const std::string msg = make_find_message(pc_name_);
    int64_t next_send = 0;
    int64_t next_iface = 0;
    std::vector<uint32_t> targets;
    while (!stop_) {
        if (s == INVALID_SOCKET) {
            s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
            if (s == INVALID_SOCKET) {
                Sleep(1000);
                continue;
            }
            BOOL on = TRUE;
            setsockopt(s, SOL_SOCKET, SO_BROADCAST, reinterpret_cast<const char*>(&on), sizeof on);
            // Windows would report an ICMP "port unreachable" from an earlier send as an error on the next read.
            BOOL report = FALSE;
            DWORD got = 0;
            WSAIoctl(s, SIO_UDP_CONNRESET, &report, sizeof report, nullptr, 0, &got, nullptr, nullptr);
            sockaddr_in any{};
            any.sin_family = AF_INET;
            bind(s, reinterpret_cast<sockaddr*>(&any), sizeof any);
        }
        const int64_t now = now_us();
        if (active_ && now >= next_send) {
            next_send = now + 2'000'000;
            if (now >= next_iface) {
                // Interfaces come and go (Wi-Fi, the headset's own access point): looked up again every 10 s.
                next_iface = now + 10'000'000;
                targets = net::interface_broadcasts();
                targets.push_back(0xFFFFFFFFu);
            }
            std::vector<uint32_t> all = targets;
            {
                std::lock_guard lock(lock_);
                all.insert(all.end(), unicast_.begin(), unicast_.end());
            }
            for (uint32_t a : all) {
                sockaddr_in to{};
                to.sin_family = AF_INET;
                to.sin_port = htons(port_);
                to.sin_addr.s_addr = htonl(a);
                sendto(s, msg.data(), static_cast<int>(msg.size()), 0, reinterpret_cast<sockaddr*>(&to), sizeof to);
            }
        }
        if (!net::wait_readable(s, 200)) continue;
        char buf[2048];
        sockaddr_in from{};
        int from_len = sizeof from;
        const int n = recvfrom(s, buf, sizeof buf, 0, reinterpret_cast<sockaddr*>(&from), &from_len);
        if (n <= 0) {
            if (WSAGetLastError() == WSAECONNRESET || WSAGetLastError() == WSAEMSGSIZE) continue;
            closesocket(s);
            s = INVALID_SOCKET;
            continue;
        }
        const uint32_t addr = ntohl(from.sin_addr.s_addr);
        if (!is_private_ipv4(addr)) continue;
        auto here = parse_here_message(std::string_view(buf, static_cast<size_t>(n)));
        if (!here) continue;
        if (active_) on_found_(addr, *here);
    }
    if (s != INVALID_SOCKET) closesocket(s);
}

}  // namespace pcw
