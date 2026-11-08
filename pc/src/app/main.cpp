// pc-windows: the PC's windows and monitors as panes in the headset (docs/pc-windows.md, decision D31).
//
//   pc-windows.exe                      the tray app (the window opens by itself until paired)
//   Options, mostly for tests:
//     --config-dir DIR    keep the pairing and the log in DIR instead of %APPDATA%\pc-windows
//     --log FILE          the log file (default: pc-windows.log in the config folder)
//     --headset ADDRESS   ask this private address directly too (may be given more than once)
//     --code 123456       pair with the first headset that offers pairing, with this code
//     --codec hevc|h264   use this codec only (H.264 to test the fall-back; none: act as a PC without one)
//     --only-titles TEXT  list only windows whose title starts with TEXT, and monitors without thumbnails
//     --no-monitors       leave the monitors out of the list
//     --port N            the headset's port (47803)
//     --stats-every S     numbers in the log every S seconds (5)
//     --hidden            never open the window by itself
//     --encoders          write the hardware encoders found to the log and stop
#include <windows.h>
#include <mfapi.h>
#include <shellapi.h>
#include <winrt/base.h>

#include <string>
#include <vector>

#include "capture.h"
#include "control.h"
#include "log.h"
#include "net.h"
#include "ui.h"
#include "util.h"
#include "video_encoder.h"

using namespace pcw;

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR, int) {
    // The manifest says per-monitor-v2 too; this covers a copy run without it.
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    std::vector<std::wstring> args(argv + 1, argv + argc);
    LocalFree(argv);

    Options opt;
    std::wstring log_path;
    bool hidden = false, list_encoders = false, own_config = false;
    for (size_t i = 0; i < args.size(); ++i) {
        const std::wstring& a = args[i];
        const bool more = i + 1 < args.size();
        if (a == L"--config-dir" && more) {
            set_config_dir(args[++i]);
            own_config = true;
        } else if (a == L"--log" && more) {
            log_path = args[++i];
        } else if (a == L"--headset" && more) {
            if (auto ip = parse_ipv4(to_utf8(args[++i])); ip && is_private_ipv4(*ip)) opt.headsets.push_back(*ip);
        } else if (a == L"--code" && more) {
            opt.code = to_utf8(args[++i]);
        } else if (a == L"--codec" && more) {
            const std::wstring c = args[++i];
            if (c == L"h264") opt.force_codec = media::Codec::H264;
            if (c == L"hevc") opt.force_codec = media::Codec::Hevc;
            if (c == L"none") pretend_no_hardware_encoder();
        } else if (a == L"--only-titles" && more) {
            opt.list.only_titles = args[++i];
        } else if (a == L"--no-monitors") {
            opt.list.monitors = false;
        } else if (a == L"--port" && more) {
            opt.port = static_cast<uint16_t>(std::wcstoul(args[++i].c_str(), nullptr, 10));
        } else if (a == L"--stats-every" && more) {
            opt.stats_every_s = std::max(1, _wtoi(args[++i].c_str()));
        } else if (a == L"--hidden") {
            hidden = true;
        } else if (a == L"--encoders") {
            list_encoders = true;
        }
    }

    // One copy per user; a test with its own config folder runs beside it.
    HANDLE single = nullptr;
    if (!own_config) {
        single = CreateMutexW(nullptr, TRUE, L"Local\\pc-windows-tray");
        if (GetLastError() == ERROR_ALREADY_EXISTS) {
            if (HWND w = FindWindowW(L"pc-windows", nullptr)) {
                ShowWindow(w, SW_SHOWNORMAL);
                SetForegroundWindow(w);
            }
            return 0;
        }
    }

    log_open(log_path.empty() ? config_dir() + L"\\pc-windows.log" : log_path);
    logf("pc-windows starting");
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET);
    net::startup();

    for (auto codec : {media::Codec::Hevc, media::Codec::H264}) {
        auto c = find_hardware_encoder(codec);
        logf("encoder: %s: %s", codec == media::Codec::Hevc ? "HEVC" : "H.264",
             c ? to_utf8(c->name).c_str() : "no hardware encoder");
    }
    if (list_encoders) {
        MFShutdown();
        log_close();
        return 0;
    }
    if (!capture_supported()) logf("capture: Windows.Graphics.Capture is not available (Windows 10 2004 or later)");
    capture_init();

    int code = 0;
    {
        Session session(opt);
        const bool paired = session.status().paired;
        code = ui::run(inst, session, !hidden && !paired && opt.code.empty());
        logf("pc-windows quitting");
        session.stop();
    }
    MFShutdown();
    logf("pc-windows stopped");
    log_close();
    if (single) CloseHandle(single);
    return code;
}
