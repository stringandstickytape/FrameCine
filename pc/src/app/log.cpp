#include "log.h"

#include <windows.h>

#include <cstdarg>
#include <cstdio>
#include <mutex>

namespace pcw {

static std::mutex g_lock;
static FILE* g_file = nullptr;

void log_open(const std::wstring& path) {
    std::lock_guard lock(g_lock);
    if (g_file) fclose(g_file);
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
    if (g_file) {
        fputs(line, g_file);
        fflush(g_file);
    }
}

}  // namespace pcw
