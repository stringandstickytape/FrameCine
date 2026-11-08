// The test window of the end-to-end test (tools/pc_windows_fake_headset.py): a known moving pattern to capture, and
// a record of the input it gets, so the test never captures or types into the PC's real windows.
//
//   pcw-testwin.exe --title T [--size WxH] [--pos X,Y] [--popup] [--fps N | --vsync] [--events FILE] [--busy]
//                   [--resize-at S --resize-to WxH] [--minimise-at S --restore-at S] [--close-at S] [--tone]
//
// The pattern, in the client area: the top half red | green, the bottom half blue | grey, and a white bar 64 px wide
// moving across a band in the middle (8 px a frame). --size is the client area; with --popup there is no frame, so
// the captured picture is exactly that size.
// FILE gets JSON lines: {"e":"ready",...} with the window's handle, client offset and sizes; then each input event.
#include <windows.h>
#include <dwmapi.h>
#include <mmsystem.h>
#include <shellapi.h>

#include <atomic>
#include <cmath>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>

namespace {

std::wstring g_title = L"pcw-test";
int g_w = 640, g_h = 360, g_x = 100, g_y = 100, g_fps = 60;
bool g_popup = false, g_tone = false, g_busy = false, g_vsync = false;
double g_resize_at = -1, g_minimise_at = -1, g_restore_at = -1, g_close_at = -1;
int g_resize_w = 0, g_resize_h = 0;
FILE* g_events = nullptr;
HWND g_wnd = nullptr;
std::atomic<long> g_frame{0};
ULONGLONG g_start_ms = GetTickCount64();
std::atomic<bool> g_quit{false};
constexpr UINT kTick = WM_APP + 1;

void event(const char* fmt, ...) {
    if (!g_events) return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(g_events, fmt, ap);
    va_end(ap);
    fputc('\n', g_events);
    fflush(g_events);
}

void report_ready(const char* what) {
    RECT fr{}, cr{};
    DwmGetWindowAttribute(g_wnd, DWMWA_EXTENDED_FRAME_BOUNDS, &fr, sizeof fr);
    GetClientRect(g_wnd, &cr);
    POINT origin{0, 0};
    ClientToScreen(g_wnd, &origin);
    event("{\"e\":\"%s\",\"id\":\"w:%llx\",\"pid\":%lu,\"client_offset\":[%ld,%ld],\"client\":[%ld,%ld],"
          "\"frame\":[%ld,%ld],\"frame_origin\":[%ld,%ld],\"dpi\":%u}",
          what, static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(g_wnd)), GetCurrentProcessId(),
          origin.x - fr.left, origin.y - fr.top, cr.right, cr.bottom, fr.right - fr.left, fr.bottom - fr.top, fr.left,
          fr.top, GetDpiForWindow(g_wnd));
}

void draw(HDC dc, int w, int h, long frame) {
    auto fill = [&](int l, int t, int r, int b, COLORREF c) {
        RECT rc{l, t, r, b};
        HBRUSH br = CreateSolidBrush(c);
        FillRect(dc, &rc, br);
        DeleteObject(br);
    };
    fill(0, 0, w / 2, h / 2, RGB(255, 0, 0));
    fill(w / 2, 0, w, h / 2, RGB(0, 255, 0));
    fill(0, h / 2, w / 2, h, RGB(0, 0, 255));
    fill(w / 2, h / 2, w, h, RGB(128, 128, 128));
    const int band_t = h * 45 / 100, band_b = h * 55 / 100;
    fill(0, band_t, w, band_b, RGB(0, 0, 0));
    const int x = static_cast<int>((frame * 8) % std::max(1, w + 64)) - 64;
    fill(x, band_t, x + 64, band_b, RGB(255, 255, 255));
    wchar_t text[64];
    swprintf_s(text, L"frame %ld", frame);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(255, 255, 255));
    TextOutW(dc, 8, 8, text, static_cast<int>(wcslen(text)));
}

// With --busy the grey quarter is new noise every frame instead: pictures no encoder can shrink, so a bitrate test
// reaches the rate asked for.
void noise(uint32_t* px, int stride_px, int x0, int y0, int x1, int y1) {
    static uint32_t s = 0x12345678u;
    for (int y = y0; y < y1; ++y) {
        uint32_t* row = px + static_cast<size_t>(y) * stride_px;
        for (int x = x0; x < x1; ++x) {
            s ^= s << 13;
            s ^= s >> 17;
            s ^= s << 5;
            row[x] = s & 0x00FFFFFFu;
        }
    }
}

void paint_now() {
    RECT cr;
    GetClientRect(g_wnd, &cr);
    const int w = cr.right, h = cr.bottom;
    if (w <= 0 || h <= 0) return;
    HDC wdc = GetDC(g_wnd);
    HDC mem = CreateCompatibleDC(wdc);
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof bi.bmiHeader;
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    void* bits = nullptr;
    HBITMAP bmp = CreateDIBSection(wdc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    HGDIOBJ old = SelectObject(mem, bmp);
    draw(mem, w, h, g_frame.load());
    if (g_busy && bits) {
        GdiFlush();
        noise(static_cast<uint32_t*>(bits), w, w / 2, h * 55 / 100, w, h);
    }
    BitBlt(wdc, 0, 0, w, h, mem, 0, 0, SRCCOPY);
    SelectObject(mem, old);
    DeleteObject(bmp);
    DeleteDC(mem);
    ReleaseDC(g_wnd, wdc);
}

void ticker() {
    if (g_vsync) {
        // A new picture for every composition of the desktop: as many frames as the display shows.
        while (!g_quit) {
            if (FAILED(DwmFlush())) Sleep(16);
            PostMessageW(g_wnd, kTick, 0, 0);
        }
        return;
    }
    timeBeginPeriod(1);
    HANDLE t = CreateWaitableTimerExW(nullptr, nullptr, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
    LARGE_INTEGER due;
    due.QuadPart = -static_cast<LONGLONG>(10'000'000 / g_fps);
    SetWaitableTimer(t, &due, std::max(1, 1000 / g_fps), nullptr, nullptr, FALSE);
    LARGE_INTEGER f, start, now;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&start);
    long ticks = 0;
    while (!g_quit) {
        WaitForSingleObject(t, 100);
        QueryPerformanceCounter(&now);
        // Frames by the clock, so a late tick does not slow the pattern down.
        const long want = static_cast<long>((now.QuadPart - start.QuadPart) * g_fps / f.QuadPart);
        if (want > ticks) {
            ticks = want;
            PostMessageW(g_wnd, kTick, 0, 0);
        }
    }
    CloseHandle(t);
    timeEndPeriod(1);
}

void play_tone() {
    // 1 kHz at -40 dBFS, 48 kHz stereo, looped: quiet, but loud enough to find in the sound stream.
    const int rate = 48000, n = rate;
    static std::vector<uint8_t> wav;
    wav.resize(44 + n * 4);
    auto put32 = [&](size_t at, uint32_t v) { memcpy(&wav[at], &v, 4); };
    auto put16 = [&](size_t at, uint16_t v) { memcpy(&wav[at], &v, 2); };
    memcpy(&wav[0], "RIFF", 4);
    put32(4, static_cast<uint32_t>(36 + n * 4));
    memcpy(&wav[8], "WAVEfmt ", 8);
    put32(16, 16);
    put16(20, 1);
    put16(22, 2);
    put32(24, rate);
    put32(28, rate * 4);
    put16(32, 4);
    put16(34, 16);
    memcpy(&wav[36], "data", 4);
    put32(40, static_cast<uint32_t>(n * 4));
    for (int i = 0; i < n; ++i) {
        const int16_t s = static_cast<int16_t>(std::lround(327.0 * std::sin(2 * 3.14159265358979 * 1000.0 * i / rate)));
        put16(44 + static_cast<size_t>(i) * 4, static_cast<uint16_t>(s));
        put16(46 + static_cast<size_t>(i) * 4, static_cast<uint16_t>(s));
    }
    PlaySoundW(reinterpret_cast<LPCWSTR>(wav.data()), nullptr, SND_MEMORY | SND_ASYNC | SND_LOOP);
}

const char* button_name(UINT msg, WPARAM wp) {
    switch (msg) {
        case WM_LBUTTONDOWN: case WM_LBUTTONUP: return "left";
        case WM_RBUTTONDOWN: case WM_RBUTTONUP: return "right";
        case WM_MBUTTONDOWN: case WM_MBUTTONUP: return "middle";
        default: return GET_XBUTTON_WPARAM(wp) == XBUTTON1 ? "x1" : "x2";
    }
}

LRESULT CALLBACK proc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case kTick:
            ++g_frame;
            paint_now();
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT ps;
            BeginPaint(h, &ps);
            EndPaint(h, &ps);
            paint_now();
            return 0;
        }
        case WM_ERASEBKGND: return 1;
        case WM_LBUTTONDOWN: case WM_RBUTTONDOWN: case WM_MBUTTONDOWN: case WM_XBUTTONDOWN:
        case WM_LBUTTONUP: case WM_RBUTTONUP: case WM_MBUTTONUP: case WM_XBUTTONUP: {
            const bool down = msg == WM_LBUTTONDOWN || msg == WM_RBUTTONDOWN || msg == WM_MBUTTONDOWN ||
                              msg == WM_XBUTTONDOWN;
            event("{\"e\":\"mouse\",\"msg\":\"%s\",\"button\":\"%s\",\"x\":%d,\"y\":%d}", down ? "down" : "up",
                  button_name(msg, wp), static_cast<short>(LOWORD(lp)), static_cast<short>(HIWORD(lp)));
            if (msg == WM_XBUTTONDOWN || msg == WM_XBUTTONUP) return TRUE;
            return 0;
        }
        case WM_MOUSEWHEEL: case WM_MOUSEHWHEEL: {
            POINT p{static_cast<short>(LOWORD(lp)), static_cast<short>(HIWORD(lp))};
            ScreenToClient(h, &p);
            event("{\"e\":\"wheel\",\"h\":%s,\"delta\":%d,\"x\":%ld,\"y\":%ld}", msg == WM_MOUSEHWHEEL ? "true" : "false",
                  GET_WHEEL_DELTA_WPARAM(wp), p.x, p.y);
            return 0;
        }
        case WM_KEYDOWN: case WM_KEYUP: case WM_SYSKEYDOWN: case WM_SYSKEYUP: {
            const bool down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
            event("{\"e\":\"key\",\"vk\":%u,\"scan\":%u,\"ext\":%s,\"down\":%s}", static_cast<unsigned>(wp),
                  static_cast<unsigned>((lp >> 16) & 0xFF), (lp & (1 << 24)) ? "true" : "false",
                  down ? "true" : "false");
            if (msg == WM_SYSKEYDOWN || msg == WM_SYSKEYUP) return 0;  // no menu from Alt
            return 0;
        }
        case WM_CHAR:
            event("{\"e\":\"char\",\"c\":%u}", static_cast<unsigned>(wp));
            return 0;
        case WM_SETFOCUS: event("{\"e\":\"focus\"}"); return 0;
        case WM_SIZE:
            if (wp != SIZE_MINIMIZED) report_ready("size");
            return 0;
        case WM_TIMER:
            if (wp == 1) {  // resize
                KillTimer(h, 1);
                RECT r{0, 0, g_resize_w, g_resize_h};
                AdjustWindowRectExForDpi(&r, static_cast<DWORD>(GetWindowLongPtrW(h, GWL_STYLE)), FALSE, 0,
                                         GetDpiForWindow(h));
                SetWindowPos(h, nullptr, 0, 0, r.right - r.left, r.bottom - r.top, SWP_NOMOVE | SWP_NOZORDER |
                             SWP_NOACTIVATE);
                report_ready("resized");
            } else if (wp == 2) {
                KillTimer(h, 2);
                ShowWindow(h, SW_MINIMIZE);
                event("{\"e\":\"minimised\"}");
            } else if (wp == 3) {
                KillTimer(h, 3);
                ShowWindow(h, SW_RESTORE);
                event("{\"e\":\"restored\"}");
            } else if (wp == 4) {
                KillTimer(h, 4);
                DestroyWindow(h);
            }
            return 0;
        case WM_DESTROY:
            g_quit = true;
            event("{\"e\":\"closed\",\"frames\":%ld,\"seconds\":%.3f}", g_frame.load(),
                  static_cast<double>(GetTickCount64() - g_start_ms) / 1000.0);
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR, int) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    for (int i = 1; i < argc; ++i) {
        const std::wstring a = argv[i];
        const bool more = i + 1 < argc;
        if (a == L"--title" && more) g_title = argv[++i];
        else if (a == L"--size" && more) swscanf_s(argv[++i], L"%dx%d", &g_w, &g_h);
        else if (a == L"--pos" && more) swscanf_s(argv[++i], L"%d,%d", &g_x, &g_y);
        else if (a == L"--fps" && more) g_fps = std::max(1, _wtoi(argv[++i]));
        else if (a == L"--popup") g_popup = true;
        else if (a == L"--tone") g_tone = true;
        else if (a == L"--busy") g_busy = true;
        else if (a == L"--vsync") g_vsync = true;
        else if (a == L"--events" && more) g_events = _wfsopen(argv[++i], L"w", _SH_DENYWR);
        else if (a == L"--resize-at" && more) g_resize_at = _wtof(argv[++i]);
        else if (a == L"--resize-to" && more) swscanf_s(argv[++i], L"%dx%d", &g_resize_w, &g_resize_h);
        else if (a == L"--minimise-at" && more) g_minimise_at = _wtof(argv[++i]);
        else if (a == L"--restore-at" && more) g_restore_at = _wtof(argv[++i]);
        else if (a == L"--close-at" && more) g_close_at = _wtof(argv[++i]);
    }
    LocalFree(argv);

    WNDCLASSW wc{};
    wc.lpfnWndProc = proc;
    wc.hInstance = inst;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = L"pcw-testwin";
    RegisterClassW(&wc);
    const DWORD style = g_popup ? WS_POPUP : WS_OVERLAPPEDWINDOW;
    RECT r{0, 0, g_w, g_h};
    // The size asked for is the client area, at the DPI of the monitor the window opens on.
    const HMONITOR mon = MonitorFromPoint({g_x, g_y}, MONITOR_DEFAULTTONEAREST);
    UINT dpi_x = 96, dpi_y = 96;
    using GetDpiForMonitorFn = HRESULT(WINAPI*)(HMONITOR, int, UINT*, UINT*);
    if (HMODULE shcore = LoadLibraryW(L"shcore.dll")) {
        if (auto fn = reinterpret_cast<GetDpiForMonitorFn>(GetProcAddress(shcore, "GetDpiForMonitor"))) {
            fn(mon, 0, &dpi_x, &dpi_y);
        }
    }
    AdjustWindowRectExForDpi(&r, style, FALSE, 0, dpi_x);
    g_wnd = CreateWindowExW(0, wc.lpszClassName, g_title.c_str(), style, g_x, g_y, r.right - r.left,
                            r.bottom - r.top, nullptr, nullptr, inst, nullptr);
    if (!g_wnd) return 1;
    ShowWindow(g_wnd, SW_SHOWNOACTIVATE);
    UpdateWindow(g_wnd);
    report_ready("ready");
    if (g_resize_at >= 0 && g_resize_w > 0) SetTimer(g_wnd, 1, static_cast<UINT>(g_resize_at * 1000), nullptr);
    if (g_minimise_at >= 0) SetTimer(g_wnd, 2, static_cast<UINT>(g_minimise_at * 1000), nullptr);
    if (g_restore_at >= 0) SetTimer(g_wnd, 3, static_cast<UINT>(g_restore_at * 1000), nullptr);
    if (g_close_at >= 0) SetTimer(g_wnd, 4, static_cast<UINT>(g_close_at * 1000), nullptr);
    if (g_tone) play_tone();
    std::thread tick(ticker);
    MSG m;
    while (GetMessageW(&m, nullptr, 0, 0) > 0) {
        TranslateMessage(&m);
        DispatchMessageW(&m);
    }
    g_quit = true;
    tick.join();
    if (g_tone) PlaySoundW(nullptr, nullptr, 0);
    if (g_events) fclose(g_events);
    return 0;
}
