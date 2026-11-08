#include "video_encoder.h"

#include <codecapi.h>
#include <d3d11_1.h>
#include <dxgi1_4.h>
#include <mfapi.h>
#include <mferror.h>

#include "log.h"

namespace pcw {

namespace {

GUID subtype(media::Codec c) {
    return c == media::Codec::Hevc ? MFVideoFormat_HEVC : MFVideoFormat_H264;
}

// The hardware encoder MFTs for a codec, best first; the caller releases them.
std::vector<ComPtr<IMFActivate>> enum_encoders(media::Codec codec) {
    MFT_REGISTER_TYPE_INFO in{MFMediaType_Video, MFVideoFormat_NV12};
    MFT_REGISTER_TYPE_INFO out{MFMediaType_Video, subtype(codec)};
    IMFActivate** acts = nullptr;
    UINT32 n = 0;
    std::vector<ComPtr<IMFActivate>> list;
    if (SUCCEEDED(MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER, MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER, &in,
                            &out, &acts, &n))) {
        for (UINT32 i = 0; i < n; ++i) {
            list.emplace_back(acts[i]);
            acts[i]->Release();
        }
        CoTaskMemFree(acts);
    }
    return list;
}

bool adapter_of(IMFActivate* a, LUID& luid) {
    UINT32 got = 0;
    if (SUCCEEDED(a->GetBlob(MFT_ENUM_ADAPTER_LUID, reinterpret_cast<UINT8*>(&luid), sizeof luid, &got)) &&
        got == sizeof luid) {
        return true;
    }
    UINT64 v = 0;
    if (SUCCEEDED(a->GetUINT64(MFT_ENUM_ADAPTER_LUID, &v))) {
        luid.LowPart = static_cast<DWORD>(v);
        luid.HighPart = static_cast<LONG>(v >> 32);
        return true;
    }
    return false;
}

std::wstring name_of(IMFActivate* a) {
    wchar_t* s = nullptr;
    UINT32 len = 0;
    std::wstring out = L"(unnamed encoder)";
    if (SUCCEEDED(a->GetAllocatedString(MFT_FRIENDLY_NAME_Attribute, &s, &len)) && s) {
        out.assign(s, len);
        CoTaskMemFree(s);
    }
    return out;
}

bool g_pretend_none = false;

}  // namespace

void pretend_no_hardware_encoder() {
    g_pretend_none = true;
}

std::optional<EncoderChoice> find_hardware_encoder(media::Codec codec) {
    if (g_pretend_none) return std::nullopt;
    for (auto& a : enum_encoders(codec)) {
        EncoderChoice c;
        c.codec = codec;
        c.name = name_of(a.Get());
        c.have_adapter = adapter_of(a.Get(), c.adapter);
        return c;
    }
    return std::nullopt;
}

std::optional<EncoderChoice> choose_encoder(std::optional<media::Codec> force) {
    if (force) return find_hardware_encoder(*force);
    if (auto c = find_hardware_encoder(media::Codec::Hevc)) return c;
    return find_hardware_encoder(media::Codec::H264);
}

ComPtr<ID3D11Device> make_device(const EncoderChoice& choice, std::string& error) {
    ComPtr<IDXGIAdapter1> adapter;
    if (choice.have_adapter) {
        ComPtr<IDXGIFactory4> f;
        if (SUCCEEDED(CreateDXGIFactory1(IID_PPV_ARGS(&f)))) f->EnumAdapterByLuid(choice.adapter, IID_PPV_ARGS(&adapter));
    }
    const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0};
    ComPtr<ID3D11Device> dev;
    const HRESULT hr = D3D11CreateDevice(adapter.Get(), adapter ? D3D_DRIVER_TYPE_UNKNOWN : D3D_DRIVER_TYPE_HARDWARE,
                                         nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
                                         levels, 2, D3D11_SDK_VERSION, &dev, nullptr, nullptr);
    if (FAILED(hr)) {
        error = "Direct3D 11: " + hr_text(hr);
        return nullptr;
    }
    ComPtr<ID3D10Multithread> mt;
    if (SUCCEEDED(dev.As(&mt))) mt->SetMultithreadProtected(TRUE);
    return dev;
}

// ---- Converter ----

void Converter::reset() {
    out_views_.clear();
    in_view_.Reset();
    in_tex_ = nullptr;
    vp_.Reset();
    en_.Reset();
    in_w_ = in_h_ = out_w_ = out_h_ = 0;
}

bool Converter::convert(ID3D11Device* dev, ID3D11DeviceContext* ctx, ID3D11Texture2D* bgra, int in_w, int in_h,
                        ID3D11Texture2D* nv12, int out_w, int out_h) {
    if (!vdev_ && (FAILED(dev->QueryInterface(IID_PPV_ARGS(&vdev_))) ||
                   FAILED(ctx->QueryInterface(IID_PPV_ARGS(&vctx_))))) {
        logf("convert: no video processor on this device");
        return false;
    }
    if (in_w != in_w_ || in_h != in_h_ || out_w != out_w_ || out_h != out_h_) reset();
    if (!vp_) {
        D3D11_VIDEO_PROCESSOR_CONTENT_DESC cd{};
        cd.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
        cd.InputFrameRate = {60, 1};
        cd.InputWidth = static_cast<UINT>(in_w);
        cd.InputHeight = static_cast<UINT>(in_h);
        cd.OutputFrameRate = {60, 1};
        cd.OutputWidth = static_cast<UINT>(out_w);
        cd.OutputHeight = static_cast<UINT>(out_h);
        cd.Usage = D3D11_VIDEO_USAGE_OPTIMAL_QUALITY;
        HRESULT hr = vdev_->CreateVideoProcessorEnumerator(&cd, &en_);
        if (SUCCEEDED(hr)) hr = vdev_->CreateVideoProcessor(en_.Get(), 0, &vp_);
        if (FAILED(hr)) {
            logf("convert: video processor %dx%d -> %dx%d: %s", in_w, in_h, out_w, out_h, hr_text(hr).c_str());
            reset();
            return false;
        }
        in_w_ = in_w;
        in_h_ = in_h;
        out_w_ = out_w;
        out_h_ = out_h;
        // Desktop pictures are full-range sRGB; video is BT.709 limited range, which the encoder's VUI says too.
        ComPtr<ID3D11VideoContext1> v1;
        if (SUCCEEDED(vctx_.As(&v1))) {
            v1->VideoProcessorSetStreamColorSpace1(vp_.Get(), 0, DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709);
            v1->VideoProcessorSetOutputColorSpace1(vp_.Get(), DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709);
        } else {
            D3D11_VIDEO_PROCESSOR_COLOR_SPACE in_cs{};
            in_cs.RGB_Range = 0;  // full
            D3D11_VIDEO_PROCESSOR_COLOR_SPACE out_cs{};
            out_cs.YCbCr_Matrix = 1;  // BT.709
            out_cs.Nominal_Range = D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_16_235;
            vctx_->VideoProcessorSetStreamColorSpace(vp_.Get(), 0, &in_cs);
            vctx_->VideoProcessorSetOutputColorSpace(vp_.Get(), &out_cs);
        }
        vctx_->VideoProcessorSetStreamFrameFormat(vp_.Get(), 0, D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);
        vctx_->VideoProcessorSetStreamAutoProcessingMode(vp_.Get(), 0, FALSE);
        const RECT src{0, 0, in_w, in_h}, dst{0, 0, out_w, out_h};
        vctx_->VideoProcessorSetStreamSourceRect(vp_.Get(), 0, TRUE, &src);
        vctx_->VideoProcessorSetStreamDestRect(vp_.Get(), 0, TRUE, &dst);
        vctx_->VideoProcessorSetOutputTargetRect(vp_.Get(), TRUE, &dst);
    }
    if (in_tex_ != bgra) {
        // The view holds the texture, so its address cannot be reused by another while we keep it.
        in_view_.Reset();
        D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC iv{};
        iv.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
        const HRESULT hr = vdev_->CreateVideoProcessorInputView(bgra, en_.Get(), &iv, &in_view_);
        if (FAILED(hr)) {
            logf("convert: input view: %s", hr_text(hr).c_str());
            return false;
        }
        in_tex_ = bgra;
    }
    auto it = out_views_.find(nv12);
    if (it == out_views_.end()) {
        D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC ov{};
        ov.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
        ComPtr<ID3D11VideoProcessorOutputView> view;
        const HRESULT hr = vdev_->CreateVideoProcessorOutputView(nv12, en_.Get(), &ov, &view);
        if (FAILED(hr)) {
            logf("convert: output view: %s", hr_text(hr).c_str());
            return false;
        }
        it = out_views_.emplace(nv12, view).first;
    }
    D3D11_VIDEO_PROCESSOR_STREAM st{};
    st.Enable = TRUE;
    st.pInputSurface = in_view_.Get();
    const HRESULT hr = vctx_->VideoProcessorBlt(vp_.Get(), it->second.Get(), 0, 1, &st);
    if (FAILED(hr)) {
        logf("convert: blt: %s", hr_text(hr).c_str());
        return false;
    }
    return true;
}

// ---- VideoEncoder ----

VideoEncoder::~VideoEncoder() {
    close();
}

void VideoEncoder::set_u32(const GUID& api, UINT32 v, const char* what) {
    if (!codec_api_) return;
    VARIANT var;
    VariantInit(&var);
    var.vt = VT_UI4;
    var.ulVal = v;
    const HRESULT hr = codec_api_->SetValue(&api, &var);
    if (FAILED(hr) && what) logf("encoder: %s not taken (%s)", what, hr_text(hr).c_str());
}

bool VideoEncoder::open(ID3D11Device* /*dev*/, IMFDXGIDeviceManager* manager, const EncoderChoice& choice, int w,
                        int h, int fps, int kbps, uint32_t serial, Output out, std::function<void()> wake,
                        std::string& error) {
    close();
    closing_ = false;
    failed_ = false;
    need_input_ = 0;
    frames_in_ = 0;
    codec_ = choice.codec;
    ps_ = std::make_unique<media::ParameterSets>(codec_);
    w_ = w;
    h_ = h;
    fps_ = std::max(1, fps);
    serial_ = serial;
    out_ = std::move(out);
    wake_ = std::move(wake);
    {
        std::lock_guard g(pending_lock_);
        pending_.clear();
    }

    for (auto& a : enum_encoders(codec_)) {
        LUID l{};
        if (choice.have_adapter && adapter_of(a.Get(), l) &&
            (l.LowPart != choice.adapter.LowPart || l.HighPart != choice.adapter.HighPart)) {
            continue;  // an encoder on another GPU than our device's
        }
        if (SUCCEEDED(a->ActivateObject(IID_PPV_ARGS(&mft_)))) {
            activate_ = a;
            break;
        }
    }
    if (!mft_) {
        error = "no encoder";
        return false;
    }
    HRESULT hr;
    auto fail = [&](const char* what) {
        error = std::string("encoder: ") + what + ": " + hr_text(hr);
        close();
        return false;
    };
    ComPtr<IMFAttributes> attrs;
    if (SUCCEEDED(mft_->GetAttributes(&attrs))) {
        async_ = MFGetAttributeUINT32(attrs.Get(), MF_TRANSFORM_ASYNC, FALSE) != FALSE;
        if (async_) attrs->SetUINT32(MF_TRANSFORM_ASYNC_UNLOCK, TRUE);
        attrs->SetUINT32(MF_LOW_LATENCY, TRUE);
    }
    hr = mft_->ProcessMessage(MFT_MESSAGE_SET_D3D_MANAGER, reinterpret_cast<ULONG_PTR>(manager));
    if (FAILED(hr)) return fail("Direct3D manager");
    DWORD nin = 0, nout = 0;
    mft_->GetStreamCount(&nin, &nout);
    if (FAILED(mft_->GetStreamIDs(1, &in_id_, 1, &out_id_))) in_id_ = out_id_ = 0;

    mft_.As(&codec_api_);
    // Constant bitrate at what the headset asked; no B-frames (they add a frame of delay and reorder); our own
    // key frames every 2 s (the time-based rule needs us: frames come at a variable rate), and low-latency mode
    // so each frame comes out as soon as it went in.
    set_u32(CODECAPI_AVEncCommonRateControlMode, eAVEncCommonRateControlMode_CBR, "CBR");
    set_u32(CODECAPI_AVEncCommonMeanBitRate, static_cast<UINT32>(kbps) * 1000, "bitrate");
    // Some encoders refuse this setting; in low-latency mode they make no B-frames anyway (the tests check).
    set_u32(CODECAPI_AVEncMPVDefaultBPictureCount, 0, nullptr);
    set_u32(CODECAPI_AVEncMPVGOPSize, static_cast<UINT32>(fps_ * 2), "GOP size");
    // Tells the encoder the pictures are a desktop (some tune for text and still areas); not all take it.
    set_u32(CODECAPI_AVScenarioInfo, eAVScenarioInfo_DisplayRemoting, nullptr);
    if (codec_api_) {
        VARIANT v;
        VariantInit(&v);
        v.vt = VT_BOOL;
        v.boolVal = VARIANT_TRUE;
        if (FAILED(codec_api_->SetValue(&CODECAPI_AVLowLatencyMode, &v))) logf("encoder: low-latency mode not taken");
    }

    ComPtr<IMFMediaType> ot;
    MFCreateMediaType(&ot);
    ot->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    ot->SetGUID(MF_MT_SUBTYPE, subtype(codec_));
    ot->SetUINT32(MF_MT_AVG_BITRATE, static_cast<UINT32>(kbps) * 1000);
    MFSetAttributeSize(ot.Get(), MF_MT_FRAME_SIZE, static_cast<UINT32>(w), static_cast<UINT32>(h));
    MFSetAttributeRatio(ot.Get(), MF_MT_FRAME_RATE, static_cast<UINT32>(fps_), 1);
    MFSetAttributeRatio(ot.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    ot->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    ot->SetUINT32(MF_MT_MPEG2_PROFILE, codec_ == media::Codec::Hevc
                                           ? static_cast<UINT32>(eAVEncH265VProfile_Main_420_8)
                                           : static_cast<UINT32>(eAVEncH264VProfile_High));
    ot->SetUINT32(MF_MT_VIDEO_PRIMARIES, MFVideoPrimaries_BT709);
    ot->SetUINT32(MF_MT_TRANSFER_FUNCTION, MFVideoTransFunc_709);
    ot->SetUINT32(MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT709);
    ot->SetUINT32(MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_16_235);
    hr = mft_->SetOutputType(out_id_, ot.Get(), 0);
    if (FAILED(hr)) return fail("output type");

    ComPtr<IMFMediaType> it;
    for (DWORD i = 0;; ++i) {
        ComPtr<IMFMediaType> t;
        if (FAILED(mft_->GetInputAvailableType(in_id_, i, &t))) break;
        GUID sub{};
        t->GetGUID(MF_MT_SUBTYPE, &sub);
        if (sub == MFVideoFormat_NV12) {
            it = t;
            break;
        }
    }
    if (!it) {
        MFCreateMediaType(&it);
        it->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        it->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
    }
    MFSetAttributeSize(it.Get(), MF_MT_FRAME_SIZE, static_cast<UINT32>(w), static_cast<UINT32>(h));
    MFSetAttributeRatio(it.Get(), MF_MT_FRAME_RATE, static_cast<UINT32>(fps_), 1);
    MFSetAttributeRatio(it.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    it->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    it->SetUINT32(MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_16_235);
    it->SetUINT32(MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT709);
    hr = mft_->SetInputType(in_id_, it.Get(), 0);
    if (FAILED(hr)) return fail("input type");

    // The parameter sets, when the encoder says them up front, so a key frame without them can be mended.
    ComPtr<IMFMediaType> cur;
    if (SUCCEEDED(mft_->GetOutputCurrentType(out_id_, &cur))) {
        UINT32 n = 0;
        if (SUCCEEDED(cur->GetBlobSize(MF_MT_MPEG_SEQUENCE_HEADER, &n)) && n) {
            std::vector<uint8_t> b(n);
            if (SUCCEEDED(cur->GetBlob(MF_MT_MPEG_SEQUENCE_HEADER, b.data(), n, nullptr))) ps_->remember(b);
        }
    }

    hr = MFCreateVideoSampleAllocatorEx(IID_PPV_ARGS(&alloc_));
    if (FAILED(hr)) return fail("sample allocator");
    alloc_->SetDirectXManager(manager);
    ComPtr<IMFAttributes> aa;
    MFCreateAttributes(&aa, 2);
    aa->SetUINT32(MF_SA_D3D11_BINDFLAGS, D3D11_BIND_RENDER_TARGET);
    aa->SetUINT32(MF_SA_D3D11_USAGE, D3D11_USAGE_DEFAULT);
    hr = alloc_->InitializeSampleAllocatorEx(3, 8, aa.Get(), it.Get());
    if (FAILED(hr)) return fail("NV12 textures");

    if (async_) {
        hr = mft_.As(&gen_);
        if (FAILED(hr)) return fail("events");
    }
    mft_->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
    hr = mft_->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
    if (FAILED(hr)) return fail("begin streaming");
    hr = mft_->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
    if (FAILED(hr)) return fail("start of stream");
    if (async_) thread_ = std::thread([this] { events(); });
    return true;
}

void VideoEncoder::close() {
    // An async encoder is drained before it is shut down, so its own queued work ends first (2026-11-09: NVIDIA's
    // HEVC encoder crashed pc-windows when a stream closed under a second after it opened: a work item it had
    // queued on Windows' media work queue ran after the encoder was gone, in its own critical section).
    const bool drain = mft_ && async_ && thread_.joinable() && !failed_;
    if (drain) {
        {
            std::lock_guard g(drain_lock_);
            drained_ = false;
        }
        mft_->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
        if (SUCCEEDED(mft_->ProcessMessage(MFT_MESSAGE_COMMAND_DRAIN, 0))) {
            std::unique_lock g(drain_lock_);
            drain_cv_.wait_for(g, std::chrono::milliseconds(300), [this] { return drained_; });
        }
    }
    closing_ = true;
    if (mft_) {
        if (!drain) mft_->ProcessMessage(MFT_MESSAGE_NOTIFY_END_OF_STREAM, 0);
        mft_->ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0);
        ComPtr<IMFShutdown> sd;
        if (SUCCEEDED(mft_.As(&sd))) sd->Shutdown();  // wakes the event thread with MF_E_SHUTDOWN
    }
    if (thread_.joinable()) thread_.join();
    if (activate_) activate_->ShutdownObject();
    if (alloc_) alloc_->UninitializeSampleAllocator();
    // The last references go a few seconds later, on a thread of their own: anything the driver still has queued
    // then finds the encoder whole (cheap; a shut-down encoder holds little).
    std::vector<ComPtr<IUnknown>> last;
    for (IUnknown* p : {static_cast<IUnknown*>(mft_.Get()), static_cast<IUnknown*>(activate_.Get()),
                        static_cast<IUnknown*>(gen_.Get()), static_cast<IUnknown*>(codec_api_.Get()),
                        static_cast<IUnknown*>(alloc_.Get())}) {
        if (p) last.emplace_back(p);
    }
    gen_.Reset();
    codec_api_.Reset();
    alloc_.Reset();
    mft_.Reset();
    activate_.Reset();
    need_input_ = 0;
    if (!last.empty()) {
        std::thread([objs = std::move(last)]() mutable {
            name_thread(L"pcw encoder release");
            CoInitializeEx(nullptr, COINIT_MULTITHREADED);
            Sleep(3000);
            objs.clear();
            CoUninitialize();
        }).detach();
    }
}

void VideoEncoder::events() {
    name_thread(L"pcw encoder events");
    while (!closing_) {
        ComPtr<IMFMediaEvent> ev;
        const HRESULT hr = gen_->GetEvent(0, &ev);
        if (FAILED(hr)) {
            if (hr != MF_E_SHUTDOWN && !closing_) {
                logf("encoder: events stopped (%s)", hr_text(hr).c_str());
                failed_ = true;
                if (wake_) wake_();
            }
            break;
        }
        MediaEventType type = MEUnknown;
        ev->GetType(&type);
        if (type == METransformDrainComplete) {
            {
                std::lock_guard g(drain_lock_);
                drained_ = true;
            }
            drain_cv_.notify_all();
        } else if (type == METransformNeedInput) {
            ++need_input_;
            if (wake_) wake_();
        } else if (type == METransformHaveOutput) {
            drain_output();
        } else if (type == MEError) {
            HRESULT st = S_OK;
            ev->GetStatus(&st);
            logf("encoder: error event (%s)", hr_text(st).c_str());
            failed_ = true;
            if (wake_) wake_();
            break;
        }
    }
}

bool VideoEncoder::drain_output() {
    MFT_OUTPUT_STREAM_INFO info{};
    mft_->GetOutputStreamInfo(out_id_, &info);
    const bool provides = (info.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES));
    MFT_OUTPUT_DATA_BUFFER ob{};
    ob.dwStreamID = out_id_;
    ComPtr<IMFSample> own;
    if (!provides) {
        ComPtr<IMFMediaBuffer> b;
        MFCreateSample(&own);
        MFCreateMemoryBuffer(std::max<DWORD>(info.cbSize, 8u << 20), &b);
        own->AddBuffer(b.Get());
        ob.pSample = own.Get();
    }
    DWORD status = 0;
    HRESULT hr = mft_->ProcessOutput(0, 1, &ob, &status);
    if (ob.pEvents) ob.pEvents->Release();
    ComPtr<IMFSample> sample;
    if (provides) {
        sample.Attach(ob.pSample);
    } else {
        sample = own;
    }
    if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
        ComPtr<IMFMediaType> t;
        if (SUCCEEDED(mft_->GetOutputAvailableType(out_id_, 0, &t))) mft_->SetOutputType(out_id_, t.Get(), 0);
        return true;
    }
    if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) return false;
    if (FAILED(hr)) {
        if (!closing_) logf("encoder: output failed (%s)", hr_text(hr).c_str());
        return false;
    }
    if (!sample) return false;
    EncodedFrame f;
    f.serial = serial_;
    LONGLONG t = 0;
    sample->GetSampleTime(&t);
    f.time_us = t / 10;
    f.key = MFGetAttributeUINT32(sample.Get(), MFSampleExtension_CleanPoint, FALSE) != FALSE;
    ComPtr<IMFMediaBuffer> buf;
    if (FAILED(sample->ConvertToContiguousBuffer(&buf))) return true;
    BYTE* p = nullptr;
    DWORD len = 0;
    if (FAILED(buf->Lock(&p, nullptr, &len))) return true;
    std::vector<uint8_t> raw(p, p + len);
    buf->Unlock();
    if (raw.empty()) return true;
    f.key = f.key || media::is_key_frame(codec_, raw);
    f.data = ps_->fix_key_frame(raw);
    {
        std::lock_guard g(pending_lock_);
        // Frames come out in the order they went in (no B-frames); one the encoder dropped is passed over.
        while (!pending_.empty() && pending_.front().time_us < f.time_us) pending_.pop_front();
        if (!pending_.empty() && pending_.front().time_us == f.time_us) {
            f.capture_us = pending_.front().capture_us;
            pending_.pop_front();
        } else {
            f.capture_us = f.time_us;
        }
    }
    if (out_ && !closing_) out_(std::move(f));
    return true;
}

ComPtr<IMFSample> VideoEncoder::new_sample(ComPtr<ID3D11Texture2D>& texture) {
    if (!alloc_) return nullptr;
    ComPtr<IMFSample> s;
    if (FAILED(alloc_->AllocateSample(&s))) return nullptr;  // all in the encoder's hands: skip this frame
    ComPtr<IMFMediaBuffer> b;
    ComPtr<IMFDXGIBuffer> dx;
    if (FAILED(s->GetBufferByIndex(0, &b)) || FAILED(b.As(&dx)) || FAILED(dx->GetResource(IID_PPV_ARGS(&texture)))) {
        return nullptr;
    }
    return s;
}

bool VideoEncoder::encode(IMFSample* sample, int64_t time_us, int64_t capture_us, bool key) {
    if (!mft_ || failed_) return false;
    if (async_ && need_input_.load() <= 0) return false;
    // An encoder's first frame is a key frame anyway; asking for one there was seen to make NVIDIA's encoder skip
    // the next one asked for.
    if (key && frames_in_ > 0) set_u32(CODECAPI_AVEncVideoForceKeyFrame, 1, "key frame");
    sample->SetSampleTime(time_us * 10);
    sample->SetSampleDuration(10'000'000 / fps_);
    {
        std::lock_guard g(pending_lock_);
        pending_.push_back({time_us, capture_us});
    }
    if (async_) --need_input_;
    const HRESULT hr = mft_->ProcessInput(in_id_, sample, 0);
    if (FAILED(hr)) {
        {
            std::lock_guard g(pending_lock_);
            if (!pending_.empty()) pending_.pop_back();
        }
        if (hr == MF_E_NOTACCEPTING) {
            if (async_) ++need_input_;
            return false;
        }
        logf("encoder: input failed (%s)", hr_text(hr).c_str());
        failed_ = true;
        return false;
    }
    ++frames_in_;
    if (!async_) {
        while (drain_output()) {
        }
    }
    return true;
}

void VideoEncoder::set_bitrate(int kbps) {
    set_u32(CODECAPI_AVEncCommonMeanBitRate, static_cast<UINT32>(kbps) * 1000, "bitrate change");
}

}  // namespace pcw
