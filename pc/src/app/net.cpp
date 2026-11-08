#include "net.h"

#include <iphlpapi.h>
#include <mstcpip.h>

#include "util.h"

namespace pcw::net {

bool startup() {
    WSADATA d;
    return WSAStartup(MAKEWORD(2, 2), &d) == 0;
}

SOCKET connect_tcp(uint32_t address, uint16_t port, int timeout_ms, std::string& error) {
    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET) {
        error = "socket: " + std::to_string(WSAGetLastError());
        return INVALID_SOCKET;
    }
    sockaddr_in sa{};
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    sa.sin_addr.s_addr = htonl(address);
    u_long nb = 1;
    ioctlsocket(s, FIONBIO, &nb);
    if (connect(s, reinterpret_cast<sockaddr*>(&sa), sizeof sa) == SOCKET_ERROR &&
        WSAGetLastError() != WSAEWOULDBLOCK) {
        error = "connect: " + std::to_string(WSAGetLastError());
        closesocket(s);
        return INVALID_SOCKET;
    }
    fd_set w, e;
    FD_ZERO(&w);
    FD_ZERO(&e);
    FD_SET(s, &w);
    FD_SET(s, &e);
    timeval tv{timeout_ms / 1000, (timeout_ms % 1000) * 1000};
    const int r = select(0, nullptr, &w, &e, &tv);
    if (r <= 0 || FD_ISSET(s, &e)) {
        int so = 0;
        int len = sizeof so;
        getsockopt(s, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&so), &len);
        error = r == 0 ? "connect: timed out" : "connect: " + std::to_string(so);
        closesocket(s);
        return INVALID_SOCKET;
    }
    nb = 0;
    ioctlsocket(s, FIONBIO, &nb);
    BOOL on = TRUE;
    setsockopt(s, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char*>(&on), sizeof on);
    setsockopt(s, SOL_SOCKET, SO_KEEPALIVE, reinterpret_cast<const char*>(&on), sizeof on);
    tcp_keepalive ka{1, 5000, 1000};
    DWORD got = 0;
    WSAIoctl(s, SIO_KEEPALIVE_VALS, &ka, sizeof ka, nullptr, 0, &got, nullptr, nullptr);
    // A send that cannot finish in 10 s means the headset is gone (Wi-Fi dropped, headset off): the connection is
    // closed and dialled again rather than left hanging.
    DWORD send_ms = 10000;
    setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, reinterpret_cast<const char*>(&send_ms), sizeof send_ms);
    return s;
}

bool wait_readable(SOCKET s, int timeout_ms) {
    fd_set r;
    FD_ZERO(&r);
    FD_SET(s, &r);
    timeval tv{timeout_ms / 1000, (timeout_ms % 1000) * 1000};
    return select(0, &r, nullptr, nullptr, &tv) > 0;
}

std::vector<uint32_t> interface_broadcasts() {
    std::vector<uint32_t> out;
    ULONG size = 16 * 1024;
    std::vector<uint8_t> buf;
    ULONG r = ERROR_BUFFER_OVERFLOW;
    for (int tries = 0; tries < 3 && r == ERROR_BUFFER_OVERFLOW; ++tries) {
        buf.resize(size);
        r = GetAdaptersAddresses(AF_INET,
                                 GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER, nullptr,
                                 reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buf.data()), &size);
    }
    if (r != NO_ERROR) return out;
    for (auto* a = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buf.data()); a; a = a->Next) {
        if (a->OperStatus != IfOperStatusUp || a->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
        for (auto* u = a->FirstUnicastAddress; u; u = u->Next) {
            if (u->Address.lpSockaddr->sa_family != AF_INET) continue;
            const uint32_t ip = ntohl(reinterpret_cast<sockaddr_in*>(u->Address.lpSockaddr)->sin_addr.s_addr);
            const ULONG bits = u->OnLinkPrefixLength;
            if (bits == 0 || bits >= 31) continue;
            const uint32_t mask = bits >= 32 ? 0xFFFFFFFFu : ~((1u << (32 - bits)) - 1);
            const uint32_t b = (ip & mask) | ~mask;
            bool seen = false;
            for (uint32_t x : out) seen = seen || x == b;
            if (!seen) out.push_back(b);
        }
    }
    return out;
}

}  // namespace pcw::net
