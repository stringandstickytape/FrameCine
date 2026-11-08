#include "capture.h"

#include <dxgi1_2.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Metadata.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Security.Authorization.AppCapabilityAccess.h>

#include <atomic>

#include "log.h"

namespace wgc = winrt::Windows::Graphics::Capture;
namespace wgd = winrt::Windows::Graphics::DirectX;
namespace wd3d = winrt::Windows::Graphics::DirectX::Direct3D11;

namespace pcw {

// One buffer waits here for the stream's thread, one is being copied, one is free for Windows to fill. (Two were
// not shown to lose frames; the frame rate here was set by MinUpdateInterval, below.)
constexpr int kBuffers = 3;

void capture_init() {
    try {
        if (winrt::Windows::Foundation::Metadata::ApiInformation::IsMethodPresent(
                L"Windows.Graphics.Capture.GraphicsCaptureAccess", L"RequestAccessAsync")) {
            const auto r = wgc::GraphicsCaptureAccess::RequestAccessAsync(wgc::GraphicsCaptureAccessKind::Borderless)
                               .get();
            logf("capture: borderless access %s",
                 r == winrt::Windows::Security::Authorization::AppCapabilityAccess::AppCapabilityAccessStatus::Allowed
                     ? "allowed"
                     : "not allowed (Windows draws its yellow border)");
        }
    } catch (const winrt::hresult_error& e) {
        logf("capture: borderless access not asked (%s)", hr_text(e.code()).c_str());
    }
}

bool capture_supported() {
    try {
        return wgc::GraphicsCaptureSession::IsSupported();
    } catch (...) {
        return false;
    }
}

struct Capture::Impl {
    wd3d::IDirect3DDevice device{nullptr};
    wgc::GraphicsCaptureItem item{nullptr};
    wgc::Direct3D11CaptureFramePool pool{nullptr};
    wgc::GraphicsCaptureSession session{nullptr};
    wgc::Direct3D11CaptureFramePool::FrameArrived_revoker arrived;
    wgc::GraphicsCaptureItem::Closed_revoker closed_revoker;
    std::function<void()> wake;

    std::mutex lock;
    wgc::Direct3D11CaptureFrame latest{nullptr};
    int64_t arrived_us = 0;
    winrt::Windows::Graphics::SizeInt32 pool_size{0, 0};
    std::atomic<bool> closed{false};
    std::atomic<int> busy{0};  // handlers running now: stop() waits for them before the Impl can go

    void on_frame() {
        struct Busy {
            std::atomic<int>& n;
            explicit Busy(std::atomic<int>& b) : n(b) { ++n; }
            ~Busy() { --n; }
        } busy_guard(busy);
        wgc::Direct3D11CaptureFrame f{nullptr};
        try {
            f = pool.TryGetNextFrame();
        } catch (...) {
            return;
        }
        if (!f) return;
        const auto size = f.ContentSize();
        {
            std::lock_guard g(lock);
            if (latest) latest.Close();  // superseded before it was sent: give its buffer back
            latest = f;
            arrived_us = now_us();
            // The pool's buffers follow the picture's size; this frame is clipped to the old size, the next is whole.
            if (size.Width != pool_size.Width || size.Height != pool_size.Height) {
                pool_size = size;
                try {
                    pool.Recreate(device, wgd::DirectXPixelFormat::B8G8R8A8UIntNormalized, kBuffers, size);
                } catch (...) {
                }
            }
        }
        if (wake) wake();
    }
};

Capture::Capture() : impl_(std::make_unique<Impl>()) {}

Capture::~Capture() {
    stop();
}

bool Capture::start(ID3D11Device* d3d, const Target& t, std::function<void()> wake, std::string& error) {
    Impl& m = *impl_;
    m.wake = std::move(wake);
    try {
        ComPtr<IDXGIDevice> dxgi;
        d3d->QueryInterface(IID_PPV_ARGS(&dxgi));
        winrt::com_ptr<::IInspectable> insp;
        winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.Get(), insp.put()));
        m.device = insp.as<wd3d::IDirect3DDevice>();

        auto interop = winrt::get_activation_factory<wgc::GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
        if (t.monitor) {
            winrt::check_hresult(interop->CreateForMonitor(
                t.hmon, winrt::guid_of<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>(),
                winrt::put_abi(m.item)));
        } else {
            winrt::check_hresult(interop->CreateForWindow(
                t.hwnd, winrt::guid_of<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>(),
                winrt::put_abi(m.item)));
        }
        m.pool_size = m.item.Size();
        if (m.pool_size.Width <= 0 || m.pool_size.Height <= 0) m.pool_size = {64, 64};  // minimised: grows later
        // Free-threaded: frames arrive on a thread of Windows' pool, not a dispatcher queue we would have to pump.
        m.pool = wgc::Direct3D11CaptureFramePool::CreateFreeThreaded(
            m.device, wgd::DirectXPixelFormat::B8G8R8A8UIntNormalized, kBuffers, m.pool_size);
        m.session = m.pool.CreateCaptureSession(m.item);
        // The headset draws its own cursor in the shape we tell it, with no lag; a captured one would trail.
        try {
            m.session.IsCursorCaptureEnabled(false);
        } catch (...) {
        }
        try {
            m.session.IsBorderRequired(false);
        } catch (...) {
        }
        // A window's menus, drop-down lists and dialogs are windows of their own; without this they would open on
        // the PC but never show in the pane (Windows 11 and later).
        try {
            if (!t.monitor && winrt::Windows::Foundation::Metadata::ApiInformation::IsPropertyPresent(
                                  L"Windows.Graphics.Capture.GraphicsCaptureSession", L"IncludeSecondaryWindows")) {
                m.session.IncludeSecondaryWindows(true);
            }
        } catch (...) {
        }
        m.arrived = m.pool.FrameArrived(winrt::auto_revoke, [&m](auto&&, auto&&) { m.on_frame(); });
        m.closed_revoker = m.item.Closed(winrt::auto_revoke, [&m](auto&&, auto&&) {
            m.closed = true;
            if (m.wake) m.wake();
        });
        m.session.StartCapture();
    } catch (const winrt::hresult_error& e) {
        error = "capture: " + hr_text(e.code());
        stop();
        return false;
    }
    return true;
}

void Capture::stop() {
    Impl& m = *impl_;
    m.arrived.revoke();
    m.closed_revoker.revoke();
    while (m.busy.load()) Sleep(1);
    try {
        if (m.session) m.session.Close();
        if (m.pool) m.pool.Close();
    } catch (...) {
    }
    std::lock_guard g(m.lock);
    if (m.latest) m.latest.Close();
    m.latest = nullptr;
    m.session = nullptr;
    m.pool = nullptr;
    m.item = nullptr;
}

bool Capture::closed() const {
    return impl_->closed.load();
}

void Capture::set_max_rate(int fps) {
    Impl& m = *impl_;
    if (!m.session || fps <= 0) return;
    try {
        if (winrt::Windows::Foundation::Metadata::ApiInformation::IsPropertyPresent(
                L"Windows.Graphics.Capture.GraphicsCaptureSession", L"MinUpdateInterval")) {
            // `fps` (the headset's own refresh rate for the pane in focus) caps what Windows hands over: on a 144 Hz
            // desktop at 72 it gives every other composed frame, evenly; on a 60 Hz one simply 60. Three quarters of
            // the frame time, not nearly all of it: composition times jitter, and at 0.9 or 0.95 a 60 Hz desktop gave
            // only 54-55 frames a second here (0.75 still leaves out a 144 Hz desktop's next frame at 72). The
            // stream's own pacing keeps the average at `fps`. Always set: Windows 11 24H2 holds a session that never
            // sets it to about 50-60 frames a second. Never under 1 ms.
            m.session.MinUpdateInterval(std::chrono::microseconds(std::max(1000, 750'000 / fps)));
        }
    } catch (...) {
    }
}

void Capture::discard() {
    Impl& m = *impl_;
    std::lock_guard g(m.lock);
    if (m.latest) m.latest.Close();
    m.latest = nullptr;
}

bool Capture::take(ID3D11DeviceContext* ctx, ComPtr<ID3D11Texture2D>& dst, int& w, int& h, int64_t& time_us,
                   int64_t& arrived_us, int min_w, int min_h) {
    Impl& m = *impl_;
    wgc::Direct3D11CaptureFrame f{nullptr};
    {
        std::lock_guard g(m.lock);
        f = m.latest;
        m.latest = nullptr;
        arrived_us = m.arrived_us;
    }
    if (!f) return false;
    bool ok = false;
    try {
        const auto size = f.ContentSize();
        auto access = f.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
        ComPtr<ID3D11Texture2D> src;
        winrt::check_hresult(access->GetInterface(IID_PPV_ARGS(&src)));
        D3D11_TEXTURE2D_DESC sd;
        src->GetDesc(&sd);
        const int cw = std::min<int>(size.Width, static_cast<int>(sd.Width));
        const int ch = std::min<int>(size.Height, static_cast<int>(sd.Height));
        const bool shrunk = cw * 2 < min_w && ch * 2 < min_h;
        if (cw > 0 && ch > 0 && !shrunk) {
            D3D11_TEXTURE2D_DESC dd{};
            if (dst) dst->GetDesc(&dd);
            if (!dst || static_cast<int>(dd.Width) != cw || static_cast<int>(dd.Height) != ch) {
                ComPtr<ID3D11Device> dev;
                ctx->GetDevice(&dev);
                D3D11_TEXTURE2D_DESC nd{};
                nd.Width = static_cast<UINT>(cw);
                nd.Height = static_cast<UINT>(ch);
                nd.MipLevels = 1;
                nd.ArraySize = 1;
                nd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
                nd.SampleDesc.Count = 1;
                nd.Usage = D3D11_USAGE_DEFAULT;
                nd.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
                dst.Reset();
                winrt::check_hresult(dev->CreateTexture2D(&nd, nullptr, &dst));
            }
            const D3D11_BOX box{0, 0, 0, static_cast<UINT>(cw), static_cast<UINT>(ch), 1};
            ctx->CopySubresourceRegion(dst.Get(), 0, 0, 0, 0, src.Get(), 0, &box);
            w = cw;
            h = ch;
            time_us = hns_to_us(f.SystemRelativeTime().count());
            ok = true;
        }
    } catch (const winrt::hresult_error& e) {
        logf("capture: frame lost (%s)", hr_text(e.code()).c_str());
    }
    try {
        f.Close();
    } catch (...) {
    }
    return ok;
}

}  // namespace pcw
