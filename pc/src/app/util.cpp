#include "util.h"

#include <shlobj.h>

#include <cstdio>
#include <mutex>

namespace pcw {

std::string to_utf8(std::wstring_view w) {
    if (w.empty()) return {};
    const int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
    std::string s(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), s.data(), n, nullptr, nullptr);
    return s;
}

std::wstring to_wide(std::string_view s) {
    if (s.empty()) return {};
    const int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
    std::wstring w(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), w.data(), n);
    return w;
}

int64_t now_us() {
    static const int64_t freq = [] {
        LARGE_INTEGER f;
        QueryPerformanceFrequency(&f);
        return f.QuadPart;
    }();
    LARGE_INTEGER c;
    QueryPerformanceCounter(&c);
    // Split so a long uptime cannot overflow the multiplication.
    return (c.QuadPart / freq) * 1000000 + (c.QuadPart % freq) * 1000000 / freq;
}

std::string hr_text(HRESULT hr) {
    char code[16];
    std::snprintf(code, sizeof code, "0x%08lx", static_cast<unsigned long>(hr));
    wchar_t* msg = nullptr;
    FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, nullptr,
                   static_cast<DWORD>(hr), 0, reinterpret_cast<wchar_t*>(&msg), 0, nullptr);
    std::string out = code;
    if (msg) {
        std::wstring m = msg;
        LocalFree(msg);
        while (!m.empty() && (m.back() == L'\n' || m.back() == L'\r' || m.back() == L' ' || m.back() == L'.')) {
            m.pop_back();
        }
        out += " (" + to_utf8(m) + ")";
    }
    return out;
}

std::string pc_name() {
    wchar_t buf[256];
    DWORD n = 256;
    if (GetComputerNameExW(ComputerNamePhysicalDnsHostname, buf, &n) && n) return to_utf8({buf, n});
    n = 256;
    if (GetComputerNameW(buf, &n) && n) return to_utf8({buf, n});
    return "PC";
}

static std::mutex g_dir_lock;
static std::wstring g_dir;

void set_config_dir(std::wstring dir) {
    std::lock_guard lock(g_dir_lock);
    g_dir = std::move(dir);
}

std::wstring config_dir() {
    std::lock_guard lock(g_dir_lock);
    if (g_dir.empty()) {
        PWSTR p = nullptr;
        if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, KF_FLAG_CREATE, nullptr, &p))) {
            g_dir = std::wstring(p) + L"\\pc-windows";
            CoTaskMemFree(p);
        } else {
            g_dir = L".\\pc-windows";
        }
    }
    CreateDirectoryW(g_dir.c_str(), nullptr);
    return g_dir;
}

void name_thread(const wchar_t* name) {
    SetThreadDescription(GetCurrentThread(), name);
}

}  // namespace pcw
