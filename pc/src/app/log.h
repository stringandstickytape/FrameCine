// The log: a text file (pc-windows.log in the config folder, or --log), started again each run.
// Privacy: window titles, thumbnails, the token and the pairing code never go in it; window ids and sizes do.
#pragma once

#include <string>

namespace pcw {

void log_open(const std::wstring& path);
void log_close();
// printf-style; adds the time and a newline.
void logf(const char* fmt, ...);

}  // namespace pcw
