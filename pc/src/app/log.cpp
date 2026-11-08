#include "log.h"

#include <windows.h>

#include <cstdarg>
#include <cstdio>
#include <mutex>

namespace pcw {

static std::mutex g_lock;
static FILE* g_file = nullptr;
static std::wstring g_path;
// A run of weeks in the tray must not fill the disc: past this the log starts again (2026-11-09: about 2 MB a day
// before the idle lines were thinned).
constexpr long kMaxBytes = 8L * 1024 * 1024;

void log_open(const std::wstring& path) {
    std::lock_guard lock(g_lock);
    if (g_file) fclose(g_file);
    g_path = path;
    g_file = _wfsopen(path.c_str(), L"w", _SH_DENYWR);
}

void log_close() {
    std::lock_guard lock(g_lock);
    if (g_file) fclose(g_file);
    g_file = nullptr;
}

void logf(const char* fmt, ...) {
    char msg[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof msg, fmt, ap);
    va_end(ap);
    SYSTEMTIME t;
    GetLocalTime(&t);
    char line[2100];
    snprintf(line, sizeof line, "%02u:%02u:%02u.%03u %s\n", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds, msg);
    OutputDebugStringA(line);
    std::lock_guard lock(g_lock);
    if (g_file && ftell(g_file) > kMaxBytes) {
        fclose(g_file);
        g_file = _wfsopen(g_path.c_str(), L"w", _SH_DENYWR);
        if (g_file) fputs("(the log grew past 8 MB and started again)\n", g_file);
    }
    if (g_file) {
        fputs(line, g_file);
        fflush(g_file);
    }
}

}  // namespace pcw
