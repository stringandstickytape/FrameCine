#include "tls.h"

// SCH_CREDENTIALS (the structure that can do TLS 1.3) needs these before schannel.h.
#define SCHANNEL_USE_BLACKLISTS
#include <subauth.h>
#include <schannel.h>
#include <bcrypt.h>
#include <wincrypt.h>

#include <cstring>

#include "../core/protocol.h"
#include "log.h"
#include "net.h"
#include "util.h"

namespace pcw {

namespace {

constexpr DWORD kReqFlags = ISC_REQ_SEQUENCE_DETECT | ISC_REQ_REPLAY_DETECT | ISC_REQ_CONFIDENTIALITY |
                            ISC_REQ_ALLOCATE_MEMORY | ISC_REQ_STREAM | ISC_REQ_MANUAL_CRED_VALIDATION |
                            ISC_REQ_USE_SUPPLIED_CREDS;

std::string sec_text(SECURITY_STATUS s) {
    return hr_text(static_cast<HRESULT>(s));
}

// Sends Schannel's output token, if there is one, and frees it.
bool send_token(SOCKET sock, SecBuffer& b) {
    bool ok = true;
    if (b.cbBuffer && b.pvBuffer) {
        const char* p = static_cast<const char*>(b.pvBuffer);
        size_t left = b.cbBuffer;
        while (left && ok) {
            const int n = send(sock, p, static_cast<int>(std::min<size_t>(left, 1 << 20)), 0);
            ok = n > 0;
            if (ok) {
                p += n;
                left -= static_cast<size_t>(n);
            }
        }
    }
    if (b.pvBuffer) FreeContextBuffer(b.pvBuffer);
    b.pvBuffer = nullptr;
    b.cbBuffer = 0;
    return ok;
}

}  // namespace

TlsClient::~TlsClient() {
    close();
    free_context();
    if (sock_ != INVALID_SOCKET) closesocket(sock_);
}

void TlsClient::free_context() {
    if (have_ctx_) DeleteSecurityContext(&ctx_);
    if (have_cred_) FreeCredentialsHandle(&cred_);
    have_ctx_ = have_cred_ = false;
}

void TlsClient::close() {
    if (closed_.exchange(true)) return;
    if (sock_ != INVALID_SOCKET) shutdown(sock_, SD_BOTH);
}

bool TlsClient::connect(uint32_t address, uint16_t port, const std::string& pin, int timeout_ms, std::string& error) {
    if (pin.size() != 64) {
        error = "no pin for the headset";
        return false;
    }
    sock_ = net::connect_tcp(address, port, timeout_ms, error);
    if (sock_ == INVALID_SOCKET) return false;
    // The handshake gets the same time limit for each read (a headset that accepts and says nothing is not one).
    DWORD rcv = static_cast<DWORD>(timeout_ms);
    setsockopt(sock_, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&rcv), sizeof rcv);

    TLS_PARAMETERS tp{};
    tp.grbitDisabledProtocols = SP_PROT_SSL2_CLIENT | SP_PROT_SSL3_CLIENT | SP_PROT_TLS1_0_CLIENT |
                                SP_PROT_TLS1_1_CLIENT;
    SCH_CREDENTIALS sc{};
    sc.dwVersion = SCH_CREDENTIALS_VERSION;
    sc.dwFlags = SCH_CRED_MANUAL_CRED_VALIDATION | SCH_CRED_NO_DEFAULT_CREDS | SCH_USE_STRONG_CRYPTO;
    sc.cTlsParameters = 1;
    sc.pTlsParameters = &tp;
    TimeStamp expiry;
    SECURITY_STATUS s = AcquireCredentialsHandleW(nullptr, const_cast<wchar_t*>(UNISP_NAME_W), SECPKG_CRED_OUTBOUND,
                                                  nullptr, &sc, nullptr, nullptr, &cred_, &expiry);
    if (s != SEC_E_OK) {
        // Windows before SCH_CREDENTIALS: the old structure, TLS 1.2 only.
        SCHANNEL_CRED old{};
        old.dwVersion = SCHANNEL_CRED_VERSION;
        old.grbitEnabledProtocols = SP_PROT_TLS1_2_CLIENT;
        old.dwFlags = SCH_CRED_MANUAL_CRED_VALIDATION | SCH_CRED_NO_DEFAULT_CREDS;
        s = AcquireCredentialsHandleW(nullptr, const_cast<wchar_t*>(UNISP_NAME_W), SECPKG_CRED_OUTBOUND, nullptr,
                                      &old, nullptr, nullptr, &cred_, &expiry);
    }
    if (s != SEC_E_OK) {
        error = "TLS credentials: " + sec_text(s);
        return false;
    }
    have_cred_ = true;
    if (!handshake(error) || !check_pin(pin, error)) return false;
    rcv = 0;
    setsockopt(sock_, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&rcv), sizeof rcv);
    s = QueryContextAttributesW(&ctx_, SECPKG_ATTR_STREAM_SIZES, &sizes_);
    if (s != SEC_E_OK) {
        error = "TLS sizes: " + sec_text(s);
        return false;
    }
    SecPkgContext_ConnectionInfo ci{};
    if (QueryContextAttributesW(&ctx_, SECPKG_ATTR_CONNECTION_INFO, &ci) == SEC_E_OK) {
        version_ = (ci.dwProtocol & SP_PROT_TLS1_3_CLIENT) ? "TLS 1.3"
                   : (ci.dwProtocol & SP_PROT_TLS1_2_CLIENT) ? "TLS 1.2"
                                                             : "TLS (other)";
    }
    return true;
}

bool TlsClient::handshake(std::string& error) {
    SecBuffer out{0, SECBUFFER_TOKEN, nullptr};
    SecBufferDesc out_desc{SECBUFFER_VERSION, 1, &out};
    DWORD attrs = 0;
    SECURITY_STATUS s = InitializeSecurityContextW(&cred_, nullptr, nullptr, kReqFlags, 0, 0, nullptr, 0, &ctx_,
                                                   &out_desc, &attrs, nullptr);
    if (s != SEC_I_CONTINUE_NEEDED) {
        error = "TLS start: " + sec_text(s);
        return false;
    }
    have_ctx_ = true;
    if (!send_token(sock_, out)) {
        error = "TLS: send failed";
        return false;
    }
    in_.clear();
    std::vector<char> buf(64 * 1024);
    bool need_read = true;
    for (int rounds = 0; rounds < 64; ++rounds) {
        if (need_read) {
            const int n = recv(sock_, buf.data(), static_cast<int>(buf.size()), 0);
            if (n <= 0) {
                error = n == 0 ? "TLS: the headset closed during the handshake"
                               : "TLS: read failed (" + std::to_string(WSAGetLastError()) + ")";
                return false;
            }
            in_.insert(in_.end(), buf.data(), buf.data() + n);
        }
        SecBuffer inb[2] = {{static_cast<unsigned long>(in_.size()), SECBUFFER_TOKEN, in_.data()},
                            {0, SECBUFFER_EMPTY, nullptr}};
        SecBufferDesc in_desc{SECBUFFER_VERSION, 2, inb};
        out = {0, SECBUFFER_TOKEN, nullptr};
        s = InitializeSecurityContextW(&cred_, &ctx_, nullptr, kReqFlags, 0, 0, &in_desc, 0, nullptr, &out_desc,
                                       &attrs, nullptr);
        if (s == SEC_E_INCOMPLETE_MESSAGE) {
            need_read = true;
            continue;
        }
        if (!send_token(sock_, out)) {
            error = "TLS: send failed";
            return false;
        }
        if (s != SEC_E_OK && s != SEC_I_CONTINUE_NEEDED && s != SEC_I_INCOMPLETE_CREDENTIALS) {
            error = "TLS handshake: " + sec_text(s);
            return false;
        }
        if (inb[1].BufferType == SECBUFFER_EXTRA && inb[1].cbBuffer) {
            in_.erase(in_.begin(), in_.end() - static_cast<ptrdiff_t>(inb[1].cbBuffer));
            need_read = false;
        } else {
            in_.clear();
            need_read = true;
        }
        if (s == SEC_E_OK) return true;  // anything left in in_ is the first application data
        if (s == SEC_I_INCOMPLETE_CREDENTIALS) need_read = false;  // asked for a client certificate: we have none
    }
    error = "TLS handshake: too many rounds";
    return false;
}

bool TlsClient::check_pin(const std::string& pin, std::string& error) {
    PCCERT_CONTEXT cert = nullptr;
    SECURITY_STATUS s = QueryContextAttributesW(&ctx_, SECPKG_ATTR_REMOTE_CERT_CONTEXT, &cert);
    if (s != SEC_E_OK || !cert) {
        error = "TLS: no certificate from the headset";
        return false;
    }
    uint8_t digest[32];
    const NTSTATUS st = BCryptHash(BCRYPT_SHA256_ALG_HANDLE, nullptr, 0, cert->pbCertEncoded, cert->cbCertEncoded,
                                   digest, sizeof digest);
    CertFreeCertificateContext(cert);
    if (st != 0) {
        error = "TLS: could not hash the certificate";
        return false;
    }
    const std::string got = hex(digest);
    if (got != pin) {
        error = "TLS: the headset's certificate does not match its pin";
        return false;
    }
    return true;
}

bool TlsClient::send_raw(const void* data, size_t size) {
    const char* p = static_cast<const char*>(data);
    while (size) {
        const int n = send(sock_, p, static_cast<int>(std::min<size_t>(size, 1 << 20)), 0);
        if (n <= 0) return false;
        p += n;
        size -= static_cast<size_t>(n);
    }
    return true;
}

bool TlsClient::send_all(const void* data, size_t size) {
    if (closed_) return false;
    std::lock_guard send_guard(send_lock_);
    const char* p = static_cast<const char*>(data);
    const size_t max = sizes_.cbMaximumMessage ? sizes_.cbMaximumMessage : 16384;
    out_buf_.resize(sizes_.cbHeader + max + sizes_.cbTrailer);
    while (size) {
        const size_t chunk = std::min(size, max);
        std::memcpy(out_buf_.data() + sizes_.cbHeader, p, chunk);
        SecBuffer b[4] = {{sizes_.cbHeader, SECBUFFER_STREAM_HEADER, out_buf_.data()},
                          {static_cast<unsigned long>(chunk), SECBUFFER_DATA, out_buf_.data() + sizes_.cbHeader},
                          {sizes_.cbTrailer, SECBUFFER_STREAM_TRAILER, out_buf_.data() + sizes_.cbHeader + chunk},
                          {0, SECBUFFER_EMPTY, nullptr}};
        SecBufferDesc d{SECBUFFER_VERSION, 4, b};
        SECURITY_STATUS s;
        {
            std::lock_guard ctx_guard(ctx_lock_);
            s = EncryptMessage(&ctx_, 0, &d, 0);
        }
        if (s != SEC_E_OK) {
            logf("tls: encrypt failed: %s", sec_text(s).c_str());
            close();
            return false;
        }
        if (!send_raw(out_buf_.data(), b[0].cbBuffer + b[1].cbBuffer + b[2].cbBuffer)) {
            close();
            return false;
        }
        p += chunk;
        size -= chunk;
    }
    return true;
}

bool TlsClient::send_line(const std::string& line) {
    std::string l = line;
    l.push_back('\n');
    return send_all(l.data(), l.size());
}

int TlsClient::recv_some(std::string& out, int timeout_ms) {
    std::vector<char> buf(64 * 1024);
    for (;;) {
        if (closed_) return -1;
        bool need_read = true;
        if (reneg_ && !in_.empty()) {
            // TLS 1.3 sends handshake messages after the handshake (session tickets, key updates); Schannel hands
            // them back as SEC_I_RENEGOTIATE and wants them fed to InitializeSecurityContext. Its answer, if any,
            // must leave before any later record, so the writers wait.
            std::lock_guard send_guard(send_lock_);
            SecBuffer inb[2] = {{static_cast<unsigned long>(in_.size()), SECBUFFER_TOKEN, in_.data()},
                                {0, SECBUFFER_EMPTY, nullptr}};
            SecBufferDesc in_desc{SECBUFFER_VERSION, 2, inb};
            SecBuffer ob{0, SECBUFFER_TOKEN, nullptr};
            SecBufferDesc out_desc{SECBUFFER_VERSION, 1, &ob};
            DWORD attrs = 0;
            SECURITY_STATUS s;
            {
                std::lock_guard ctx_guard(ctx_lock_);
                s = InitializeSecurityContextW(&cred_, &ctx_, nullptr, kReqFlags, 0, 0, &in_desc, 0, nullptr,
                                               &out_desc, &attrs, nullptr);
            }
            if (s != SEC_E_INCOMPLETE_MESSAGE) {
                if (!send_token(sock_, ob)) return -1;
                if (s != SEC_E_OK && s != SEC_I_CONTINUE_NEEDED) {
                    logf("tls: post-handshake message refused: %s", sec_text(s).c_str());
                    return -1;
                }
                if (inb[1].BufferType == SECBUFFER_EXTRA && inb[1].cbBuffer) {
                    in_.erase(in_.begin(), in_.end() - static_cast<ptrdiff_t>(inb[1].cbBuffer));
                } else {
                    in_.clear();
                }
                reneg_ = s == SEC_I_CONTINUE_NEEDED;
                need_read = reneg_ && in_.empty();
            }
        } else if (!reneg_ && !in_.empty()) {
            SecBuffer b[4] = {{static_cast<unsigned long>(in_.size()), SECBUFFER_DATA, in_.data()},
                              {0, SECBUFFER_EMPTY, nullptr},
                              {0, SECBUFFER_EMPTY, nullptr},
                              {0, SECBUFFER_EMPTY, nullptr}};
            SecBufferDesc d{SECBUFFER_VERSION, 4, b};
            SECURITY_STATUS s;
            {
                std::lock_guard ctx_guard(ctx_lock_);
                s = DecryptMessage(&ctx_, &d, 0, nullptr);
            }
            if (s == SEC_E_OK || s == SEC_I_RENEGOTIATE) {
                size_t got = 0;
                const char* extra = nullptr;
                size_t extra_n = 0;
                for (auto& x : b) {
                    if (x.BufferType == SECBUFFER_DATA && x.cbBuffer) {
                        out.append(static_cast<const char*>(x.pvBuffer), x.cbBuffer);
                        got += x.cbBuffer;
                    } else if (x.BufferType == SECBUFFER_EXTRA && x.cbBuffer) {
                        extra = static_cast<const char*>(x.pvBuffer);
                        extra_n = x.cbBuffer;
                    }
                }
                if (extra) {
                    std::memmove(in_.data(), extra, extra_n);
                    in_.resize(extra_n);
                } else {
                    in_.clear();
                }
                reneg_ = s == SEC_I_RENEGOTIATE;
                if (got) return 1;
                need_read = in_.empty();
            } else if (s == SEC_I_CONTEXT_EXPIRED) {
                return 0;  // close_notify
            } else if (s != SEC_E_INCOMPLETE_MESSAGE) {
                logf("tls: decrypt failed: %s", sec_text(s).c_str());
                return -1;
            }
        }
        if (!need_read) continue;
        if (timeout_ms >= 0 && !net::wait_readable(sock_, timeout_ms)) return closed_ ? -1 : -2;
        const int n = recv(sock_, buf.data(), static_cast<int>(buf.size()), 0);
        if (n == 0) return 0;
        if (n < 0) return -1;
        in_.insert(in_.end(), buf.data(), buf.data() + n);
    }
}

}  // namespace pcw
