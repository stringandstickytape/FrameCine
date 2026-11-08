#include "store.h"

#include <windows.h>
#include <dpapi.h>

#include <vector>

#include "../core/json.h"
#include "../core/protocol.h"
#include "log.h"
#include "util.h"

namespace pcw {

static std::wstring path() {
    return config_dir() + L"\\pairing.dat";
}

std::optional<Pairing> load_pairing() {
    HANDLE f = CreateFileW(path().c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (f == INVALID_HANDLE_VALUE) return std::nullopt;
    std::vector<uint8_t> data(64 * 1024);
    DWORD n = 0;
    const BOOL ok = ReadFile(f, data.data(), static_cast<DWORD>(data.size()), &n, nullptr);
    CloseHandle(f);
    if (!ok || n == 0) return std::nullopt;
    DATA_BLOB in{n, data.data()}, out{};
    if (!CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &out)) {
        logf("store: the pairing could not be read (another user's, or damaged); pair again");
        return std::nullopt;
    }
    std::string text(reinterpret_cast<const char*>(out.pbData), out.cbData);
    SecureZeroMemory(out.pbData, out.cbData);
    LocalFree(out.pbData);
    auto v = json::parse(text);
    SecureZeroMemory(text.data(), text.size());
    if (!v || !v->is_object()) return std::nullopt;
    Pairing p;
    p.headset = v->str("headset");
    p.address = parse_ipv4(v->str("address")).value_or(0);
    p.port = static_cast<uint16_t>(v->integer("port", kPort));
    p.pin = normalise_hex(v->str("pin"), 64).value_or("");
    p.token = v->str("token");
    if (p.pin.empty() || p.token.empty()) return std::nullopt;
    return p;
}

bool save_pairing(const Pairing& p) {
    json::Value v = json::Value::object();
    v.set("headset", p.headset)
        .set("address", format_ipv4(p.address))
        .set("port", static_cast<int>(p.port))
        .set("pin", p.pin)
        .set("token", p.token);
    std::string text = v.dump();
    DATA_BLOB in{static_cast<DWORD>(text.size()), reinterpret_cast<BYTE*>(text.data())}, out{};
    const BOOL ok = CryptProtectData(&in, L"pc-windows pairing", nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN,
                                     &out);
    SecureZeroMemory(text.data(), text.size());
    if (!ok) {
        logf("store: could not encrypt the pairing (%lu)", GetLastError());
        return false;
    }
    // Written beside and moved over the old one, so a crash never leaves half a file.
    const std::wstring final_path = path(), tmp = final_path + L".new";
    HANDLE f = CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    bool written = false;
    if (f != INVALID_HANDLE_VALUE) {
        DWORD n = 0;
        written = WriteFile(f, out.pbData, out.cbData, &n, nullptr) && n == out.cbData && FlushFileBuffers(f);
        CloseHandle(f);
    }
    LocalFree(out.pbData);
    if (!written || !MoveFileExW(tmp.c_str(), final_path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(tmp.c_str());
        logf("store: could not write the pairing (%lu)", GetLastError());
        return false;
    }
    return true;
}

void forget_pairing() {
    DeleteFileW(path().c_str());
}

}  // namespace pcw
