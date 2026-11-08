#include "window_list.h"

#include <dwmapi.h>
#include <shlwapi.h>
#include <wincodec.h>

#include <cstdio>

#include "../core/protocol.h"
#include "util.h"

namespace pcw {

namespace {

std::string hwnd_id(HWND h) {
    char buf[32];
    std::snprintf(buf, sizeof buf, "w:%llx", static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(h)));
    return buf;
}

std::string exe_name(HWND h) {
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!p) return {};
    wchar_t path[MAX_PATH * 2];
    DWORD n = MAX_PATH * 2;
    std::string out;
    if (QueryFullProcessImageNameW(p, 0, path, &n)) {
        std::wstring s(path, n);
        const size_t slash = s.find_last_of(L"\\/");
        out = to_utf8(slash == std::wstring::npos ? s : s.substr(slash + 1));
    }
    CloseHandle(p);
    return out;
}

bool cloaked(HWND h) {
    DWORD c = 0;
    return SUCCEEDED(DwmGetWindowAttribute(h, DWMWA_CLOAKED, &c, sizeof c)) && c != 0;
}

bool listable(HWND h) {
    if (!IsWindowVisible(h) || h == GetShellWindow()) return false;
    const LONG_PTR ex = GetWindowLongPtrW(h, GWL_EXSTYLE);
    if (ex & WS_EX_TOOLWINDOW) return false;
    if ((ex & WS_EX_NOACTIVATE) && !(ex & WS_EX_APPWINDOW)) return false;
    if (GetWindow(h, GW_OWNER) && !(ex & WS_EX_APPWINDOW)) return false;
    if (cloaked(h)) return false;
    if (GetWindowTextLengthW(h) == 0) return false;
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    return pid != GetCurrentProcessId();  // never our own window
}

struct MonitorList {
    std::vector<HMONITOR> mons;
};

BOOL CALLBACK monitor_proc(HMONITOR m, HDC, LPRECT, LPARAM p) {
    reinterpret_cast<MonitorList*>(p)->mons.push_back(m);
    return TRUE;
}

std::vector<HMONITOR> monitors() {
    MonitorList l;
    EnumDisplayMonitors(nullptr, nullptr, monitor_proc, reinterpret_cast<LPARAM>(&l));
    return l.mons;
}

struct EnumState {
    const ListOptions* opt;
    std::vector<WindowInfo>* out;
};

BOOL CALLBACK window_proc(HWND h, LPARAM p) {
    auto* st = reinterpret_cast<EnumState*>(p);
    if (!listable(h)) return TRUE;
    WindowInfo w;
    w.target.id = hwnd_id(h);
    w.target.hwnd = h;
    const int len = GetWindowTextLengthW(h);
    w.title.resize(static_cast<size_t>(len) + 1);
    w.title.resize(static_cast<size_t>(GetWindowTextW(h, w.title.data(), len + 1)));
    if (!st->opt->only_titles.empty() && w.title.rfind(st->opt->only_titles, 0) != 0) return TRUE;
    w.minimised = IsIconic(h) != FALSE;
    if (w.minimised) {
        WINDOWPLACEMENT wp{sizeof wp};
        GetWindowPlacement(h, &wp);
        w.w = wp.rcNormalPosition.right - wp.rcNormalPosition.left;
        w.h = wp.rcNormalPosition.bottom - wp.rcNormalPosition.top;
    } else if (auto r = captured_rect(w.target)) {
        w.w = r->width();
        w.h = r->height();
    }
    if (w.w <= 0 || w.h <= 0) return TRUE;
    w.app = exe_name(h);
    st->out->push_back(std::move(w));
    return TRUE;
}

// Scales a 32-bit top-down BGRA picture to fit `max_side` and encodes it as JPEG, with WIC.
std::string encode_jpeg(const uint8_t* bgra, int w, int h, int stride, int max_side) {
    ComPtr<IWICImagingFactory> f;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&f)))) return {};
    ComPtr<IWICBitmap> bmp;
    if (FAILED(f->CreateBitmapFromMemory(static_cast<UINT>(w), static_cast<UINT>(h), GUID_WICPixelFormat32bppBGR,
                                         static_cast<UINT>(stride), static_cast<UINT>(stride * h),
                                         const_cast<BYTE*>(bgra), &bmp))) {
        return {};
    }
    const double s = std::min(1.0, static_cast<double>(max_side) / std::max(w, h));
    const UINT tw = std::max(1u, static_cast<UINT>(w * s + 0.5)), th = std::max(1u, static_cast<UINT>(h * s + 0.5));
    ComPtr<IWICBitmapScaler> scaler;
    if (FAILED(f->CreateBitmapScaler(&scaler)) ||
        FAILED(scaler->Initialize(bmp.Get(), tw, th, WICBitmapInterpolationModeHighQualityCubic))) {
        return {};
    }
    ComPtr<IStream> stream;
    stream.Attach(SHCreateMemStream(nullptr, 0));
    ComPtr<IWICBitmapEncoder> enc;
    ComPtr<IWICBitmapFrameEncode> frame;
    ComPtr<IPropertyBag2> props;
    if (!stream || FAILED(f->CreateEncoder(GUID_ContainerFormatJpeg, nullptr, &enc)) ||
        FAILED(enc->Initialize(stream.Get(), WICBitmapEncoderNoCache)) ||
        FAILED(enc->CreateNewFrame(&frame, &props))) {
        return {};
    }
    PROPBAG2 opt{};
    opt.pstrName = const_cast<LPOLESTR>(L"ImageQuality");
    VARIANT q;
    VariantInit(&q);
    q.vt = VT_R4;
    q.fltVal = 0.8f;
    props->Write(1, &opt, &q);
    WICPixelFormatGUID fmt = GUID_WICPixelFormat24bppBGR;
    if (FAILED(frame->Initialize(props.Get())) || FAILED(frame->SetSize(tw, th)) ||
        FAILED(frame->SetPixelFormat(&fmt))) {
        return {};
    }
    ComPtr<IWICFormatConverter> conv;
    if (FAILED(f->CreateFormatConverter(&conv)) ||
        FAILED(conv->Initialize(scaler.Get(), fmt, WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom)) ||
        FAILED(frame->WriteSource(conv.Get(), nullptr)) || FAILED(frame->Commit()) || FAILED(enc->Commit())) {
        return {};
    }
    STATSTG st{};
    stream->Stat(&st, STATFLAG_NONAME);
    std::vector<uint8_t> bytes(static_cast<size_t>(st.cbSize.QuadPart));
    LARGE_INTEGER zero{};
    stream->Seek(zero, STREAM_SEEK_SET, nullptr);
    ULONG got = 0;
    stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &got);
    bytes.resize(got);
    return base64(bytes);
}

}  // namespace

std::vector<WindowInfo> list_windows(const ListOptions& opt) {
    std::vector<WindowInfo> out;
    EnumState st{&opt, &out};
    EnumWindows(window_proc, reinterpret_cast<LPARAM>(&st));
    if (opt.monitors) {
        const auto mons = monitors();
        for (size_t i = 0; i < mons.size(); ++i) {
            MONITORINFOEXW mi{};
            mi.cbSize = sizeof mi;
            if (!GetMonitorInfoW(mons[i], &mi)) continue;
            WindowInfo w;
            w.target.id = "m:" + std::to_string(i);
            w.target.monitor = true;
            w.target.hmon = mons[i];
            w.w = mi.rcMonitor.right - mi.rcMonitor.left;
            w.h = mi.rcMonitor.bottom - mi.rcMonitor.top;
            w.title = L"Monitor " + std::to_wstring(i + 1) + ((mi.dwFlags & MONITORINFOF_PRIMARY) ? L" (main)" : L"");
            w.app = "";
            out.push_back(std::move(w));
        }
    }
    return out;
}

std::optional<Target> find_target(const std::string& id) {
    Target t;
    t.id = id;
    if (id.rfind("w:", 0) == 0) {
        unsigned long long v = 0;
        if (sscanf_s(id.c_str() + 2, "%llx", &v) != 1) return std::nullopt;
        t.hwnd = reinterpret_cast<HWND>(static_cast<uintptr_t>(v));
        if (!IsWindow(t.hwnd)) return std::nullopt;
        return t;
    }
    if (id.rfind("m:", 0) == 0) {
        const int i = std::atoi(id.c_str() + 2);
        const auto mons = monitors();
        if (i < 0 || static_cast<size_t>(i) >= mons.size()) return std::nullopt;
        t.monitor = true;
        t.hmon = mons[static_cast<size_t>(i)];
        return t;
    }
    return std::nullopt;
}

std::optional<mapping::Rect> captured_rect(const Target& t) {
    if (t.monitor) {
        MONITORINFO mi{sizeof mi};
        if (!GetMonitorInfoW(t.hmon, &mi)) return std::nullopt;
        return mapping::Rect{mi.rcMonitor.left, mi.rcMonitor.top, mi.rcMonitor.right, mi.rcMonitor.bottom};
    }
    if (!IsWindow(t.hwnd)) return std::nullopt;
    RECT r{};
    if (FAILED(DwmGetWindowAttribute(t.hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &r, sizeof r)) && !GetWindowRect(t.hwnd, &r)) {
        return std::nullopt;
    }
    return mapping::Rect{r.left, r.top, r.right, r.bottom};
}

bool is_minimised(const Target& t) {
    return !t.monitor && IsIconic(t.hwnd);
}

std::string thumbnail_base64(const WindowInfo& w, int max_side, bool allow_monitor_capture) {
    if (w.minimised) return {};
    const auto rect = captured_rect(w.target);
    if (!rect || rect->width() <= 0 || rect->height() <= 0) return {};
    if (w.target.monitor && !allow_monitor_capture) return {};
    if (!w.target.monitor && IsHungAppWindow(w.target.hwnd)) return {};  // PrintWindow would wait on it
    HDC screen = GetDC(nullptr);
    HDC mem = CreateCompatibleDC(screen);
    std::string out;
    int cw = rect->width(), ch = rect->height(), ox = 0, oy = 0;
    if (!w.target.monitor) {
        // PrintWindow draws the whole window rectangle, invisible resize borders included; the picture the
        // headset gets is the extended frame inside it.
        RECT wr{};
        GetWindowRect(w.target.hwnd, &wr);
        ox = rect->left - wr.left;
        oy = rect->top - wr.top;
        cw = wr.right - wr.left;
        ch = wr.bottom - wr.top;
    }
    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof bi.bmiHeader;
    bi.bmiHeader.biWidth = cw;
    bi.bmiHeader.biHeight = -ch;  // top-down
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HBITMAP dib = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (dib && bits) {
        HGDIOBJ old = SelectObject(mem, dib);
        bool ok;
        if (w.target.monitor) {
            ok = BitBlt(mem, 0, 0, cw, ch, screen, rect->left, rect->top, SRCCOPY | CAPTUREBLT) != FALSE;
        } else {
            ok = PrintWindow(w.target.hwnd, mem, PW_RENDERFULLCONTENT) != FALSE;
        }
        GdiFlush();
        if (ok) {
            const int stride = cw * 4;
            const int vw = std::min(rect->width(), cw - ox), vh = std::min(rect->height(), ch - oy);
            if (vw > 0 && vh > 0 && ox >= 0 && oy >= 0) {
                const uint8_t* start = static_cast<const uint8_t*>(bits) + oy * stride + ox * 4;
                out = encode_jpeg(start, vw, vh, stride, max_side);
            }
        }
        SelectObject(mem, old);
    }
    if (dib) DeleteObject(dib);
    DeleteDC(mem);
    ReleaseDC(nullptr, screen);
    return out;
}

}  // namespace pcw
