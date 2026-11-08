// Small things every part of the app uses: strings, the clock, HRESULT checks.
#pragma once

#include <windows.h>
#include <wrl/client.h>

#include <cstdint>
#include <string>
#include <string_view>

namespace pcw {

using Microsoft::WRL::ComPtr;

std::string to_utf8(std::wstring_view w);
std::wstring to_wide(std::string_view s);

// The one clock of the protocol (QueryPerformanceCounter), in microseconds.
int64_t now_us();
// QPC ticks in 100 ns units (what Windows.Graphics.Capture's SystemRelativeTime and WASAPI's QPC position use) to us.
inline int64_t hns_to_us(int64_t hns) { return hns / 10; }

// "0x80070005" and Windows' own words for it.
std::string hr_text(HRESULT hr);

// This PC's name as the headset shows it.
std::string pc_name();

// %APPDATA%\pc-windows unless --config-dir changed it; made on first use.
std::wstring config_dir();
void set_config_dir(std::wstring dir);

// Names a thread in the debugger and in crash dumps.
void name_thread(const wchar_t* name);

}  // namespace pcw
