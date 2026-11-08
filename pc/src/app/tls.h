// A TLS client over one TCP socket, with Windows' own Schannel. The headset's certificate is self-signed: it is
// checked by its pin (SHA-256 of the DER certificate, hex) and nothing else. TLS 1.2 or 1.3.
//
// One thread may read while others write: writes are kept whole and in order by one lock, and every Schannel call
// on the context is made under another (Schannel does not promise a context is safe across threads).
#pragma once

#define SECURITY_WIN32
#include <winsock2.h>
#include <windows.h>
#include <sspi.h>

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace pcw {

class TlsClient {
public:
    TlsClient() = default;
    ~TlsClient();
    TlsClient(const TlsClient&) = delete;
    TlsClient& operator=(const TlsClient&) = delete;

    // Dials, shakes hands and checks the pin. An empty pin is refused (there is always one from discovery).
    bool connect(uint32_t address, uint16_t port, const std::string& pin, int timeout_ms, std::string& error);

    // Sends all of it; false when the connection is gone.
    bool send_all(const void* data, size_t size);
    bool send_line(const std::string& line);  // adds the \n

    // Reads some plain bytes into `out` (appended). 1: got some, 0: closed by the peer, -1: error, -2: time-out.
    int recv_some(std::string& out, int timeout_ms);

    // Unblocks every other thread using the connection (their calls fail); safe to call more than once and from
    // any thread. The socket itself is freed in the destructor, so no thread can see its handle reused.
    void close();
    bool closed() const { return closed_.load(); }

    std::string tls_version() const { return version_; }

private:
    bool handshake(std::string& error);
    bool check_pin(const std::string& pin, std::string& error);
    bool send_raw(const void* data, size_t size);
    void free_context();

    SOCKET sock_ = INVALID_SOCKET;
    CredHandle cred_{};
    CtxtHandle ctx_{};
    bool have_cred_ = false;
    bool have_ctx_ = false;
    SecPkgContext_StreamSizes sizes_{};
    std::string version_;

    std::mutex send_lock_;
    std::mutex ctx_lock_;
    std::atomic<bool> closed_{false};

    std::vector<char> in_;      // encrypted bytes not yet decrypted, the first ones from the handshake's end
    bool reneg_ = false;        // a post-handshake message is being fed to Schannel (reader only)
    std::vector<char> out_buf_; // writer only
};

}  // namespace pcw
