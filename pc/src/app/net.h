// Sockets: Winsock start-up, TCP connect with a time limit, the private-address rule, interface broadcasts.
#pragma once

#include <winsock2.h>
#include <ws2tcpip.h>

#include <cstdint>
#include <string>
#include <vector>

namespace pcw::net {

bool startup();

// A connected, blocking TCP socket with TCP_NODELAY, keep-alive probes every few seconds (so a headset that went
// off the network is noticed on a socket only written to) and a send time limit. INVALID_SOCKET on failure.
SOCKET connect_tcp(uint32_t address, uint16_t port, int timeout_ms, std::string& error);

// Waits until the socket can be read; false on time-out or error.
bool wait_readable(SOCKET s, int timeout_ms);

// The IPv4 broadcast address of every interface that is up (host byte order), for discovery: a send to
// 255.255.255.255 leaves by one interface only.
std::vector<uint32_t> interface_broadcasts();

}  // namespace pcw::net
