#include "ui.h"

#include <commctrl.h>
#include <shellapi.h>

#include <string>

#include "input.h"
#include "log.h"
#include "util.h"

namespace pcw::ui {

namespace {

constexpr UINT kTrayMsg = WM_APP + 1;
constexpr UINT kStatusMsg = WM_APP + 2;
constexpr UINT kTrayId = 1;
// Ctrl+Alt+F12: hands off (the headset's mouse and keys ignored); Ctrl+Alt+Shift+F12: sending stopped too.
enum : int { HotHandsOff = 1, HotStopAll = 2 };
constexpr UINT_PTR kWatchTimer = 1;

enum : int { IdStatus = 100, IdMessage, IdCodeLabel, IdCode, IdPair, IdSendingLabel, IdSending, IdEncoder, IdForget,
             IdQuit, IdMenuShow = 200, IdMenuQuit };

struct State {
    Session* session = nullptr;
    HWND wnd = nullptr;
    HFONT font = nullptr;
    HICON icon = nullptr;
    UINT taskbar_created = 0;
    NOTIFYICONDATAW nid{};
    bool tray_added = false;
};
State g;

// A small icon drawn here, so the exe carries no image files: a dark rounded square with a window in it.
HICON make_icon(int size) {
    BITMAPV5HEADER bh{};
    bh.bV5Size = sizeof bh;
    bh.bV5Width = size;
    bh.bV5Height = -size;
    bh.bV5Planes = 1;
    bh.bV5BitCount = 32;
    bh.bV5Compression = BI_BITFIELDS;
    bh.bV5RedMask = 0x00FF0000;
    bh.bV5GreenMask = 0x0000FF00;
    bh.bV5BlueMask = 0x000000FF;
    bh.bV5AlphaMask = 0xFF000000;
    HDC dc = GetDC(nullptr);
    void* bits = nullptr;
    HBITMAP color = CreateDIBSection(dc, reinterpret_cast<BITMAPINFO*>(&bh), DIB_RGB_COLORS, &bits, nullptr, 0);
    ReleaseDC(nullptr, dc);
    if (!color || !bits) return LoadIconW(nullptr, IDI_APPLICATION);
    auto* px = static_cast<uint32_t*>(bits);
    const int r = size / 6;  // corner radius
    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x) {
            const int cx = x < r ? r - x : x >= size - r ? x - (size - r - 1) : 0;
            const int cy = y < r ? r - y : y >= size - r ? y - (size - r - 1) : 0;
            uint32_t c = 0;
            if (cx * cx + cy * cy <= r * r) c = 0xFF2B3A55;  // the square
            const int m = size / 5;
            const bool in_frame = x >= m && x < size - m && y >= m + size / 10 && y < size - m;
            const bool border = in_frame && (x == m || x == size - m - 1 || y == size - m - 1 ||
                                             y < m + size / 10 + std::max(2, size / 8));
            if (border) c = 0xFFFFFFFF;
            else if (in_frame) c = 0xFF6FA8FF;
            px[y * size + x] = c;
        }
    }
    HBITMAP mask = CreateBitmap(size, size, 1, 1, nullptr);
    ICONINFO ii{TRUE, 0, 0, mask, color};
    HICON icon = CreateIconIndirect(&ii);
    DeleteObject(color);
    DeleteObject(mask);
    return icon ? icon : LoadIconW(nullptr, IDI_APPLICATION);
}

int scale(int v) {
    return MulDiv(v, static_cast<int>(GetDpiForWindow(g.wnd)), 96);
}

void set_font() {
    if (g.font) DeleteObject(g.font);
    NONCLIENTMETRICSW ncm{sizeof ncm};
    SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, sizeof ncm, &ncm, 0, GetDpiForWindow(g.wnd));
    g.font = CreateFontIndirectW(&ncm.lfMessageFont);
    for (HWND c = GetWindow(g.wnd, GW_CHILD); c; c = GetWindow(c, GW_HWNDNEXT)) {
        SendMessageW(c, WM_SETFONT, reinterpret_cast<WPARAM>(g.font), TRUE);
    }
}

void layout() {
    const int pad = scale(12), w = scale(420) - 2 * pad, line = scale(22);
    int y = pad;
    auto place = [&](int id, int x, int width, int height) {
        MoveWindow(GetDlgItem(g.wnd, id), pad + x, y, width, height, TRUE);
    };
    place(IdStatus, 0, w, line);
    y += line;
    place(IdMessage, 0, w, line * 2);
    y += line * 2 + scale(6);
    place(IdCodeLabel, 0, scale(110), line);
    place(IdCode, scale(115), scale(100), line + scale(2));
    place(IdPair, scale(225), scale(80), line + scale(4));
    y += line + scale(14);
    place(IdSendingLabel, 0, w, line);
    y += line;
    place(IdSending, 0, w, scale(110));
    y += scale(116);
    place(IdEncoder, 0, w, line * 2);
    y += line * 2 + scale(6);
    place(IdForget, 0, scale(130), line + scale(6));
    place(IdQuit, w - scale(90), scale(90), line + scale(6));
    y += line + scale(6) + pad;
    RECT rc{0, 0, scale(420), y};
    AdjustWindowRectExForDpi(&rc, static_cast<DWORD>(GetWindowLongPtrW(g.wnd, GWL_STYLE)), FALSE, 0,
                             GetDpiForWindow(g.wnd));
    SetWindowPos(g.wnd, nullptr, 0, 0, rc.right - rc.left, rc.bottom - rc.top, SWP_NOMOVE | SWP_NOZORDER);
}

void tray(DWORD what) {
    g.nid.cbSize = sizeof g.nid;
    g.nid.hWnd = g.wnd;
    g.nid.uID = kTrayId;
    g.nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
    g.nid.uCallbackMessage = kTrayMsg;
    g.nid.hIcon = g.icon;
    if (what == NIM_ADD) {
        g.tray_added = Shell_NotifyIconW(NIM_ADD, &g.nid) != FALSE;
        g.nid.uVersion = NOTIFYICON_VERSION_4;
        Shell_NotifyIconW(NIM_SETVERSION, &g.nid);
    } else {
        Shell_NotifyIconW(what, &g.nid);
    }
}

void refresh() {
    const Status s = g.session->status();
    std::wstring line = L"Headset: ";
    if (s.headset.empty()) line += s.found ? L"found" : L"looking on the network...";
    else line += to_wide(s.headset);
    line += s.connected ? L" - connected" : s.found ? L" - found" : L"";
    line += s.paired ? L", paired" : L", not paired";
    SetDlgItemTextW(g.wnd, IdStatus, line.c_str());
    std::wstring m = to_wide(s.message);
    if (!s.paired && !s.connected) {
        m = (s.offers_pairing ? L"In the headset: System, PC windows, Add a PC. Type the code it shows. "
                              : L"In the headset: System, PC windows, Add a PC. ") +
            m;
    }
    SetDlgItemTextW(g.wnd, IdMessage, m.c_str());
    HWND list = GetDlgItem(g.wnd, IdSending);
    SendMessageW(list, LB_RESETCONTENT, 0, 0);
    for (const auto& t : s.sending) SendMessageW(list, LB_ADDSTRING, 0, reinterpret_cast<LPARAM>(t.c_str()));
    if (s.sound) SendMessageW(list, LB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"(the PC's sound)"));
    std::wstring enc = L"Video encoder: " + s.encoder;
    if (!g.session->sending()) enc += L"   |   SENDING STOPPED (Ctrl+Alt+Shift+F12 to allow)";
    else if (input::hands_off()) enc += L"   |   HANDS OFF: the headset's mouse and keys are ignored (Ctrl+Alt+F12)";
    SetDlgItemTextW(g.wnd, IdEncoder, enc.c_str());
    EnableWindow(GetDlgItem(g.wnd, IdForget), s.paired);
    const std::wstring tip = std::wstring(L"PC windows: ") +
                             (s.connected ? L"connected" : s.paired ? L"waiting for the headset" : L"not paired");
    wcsncpy_s(g.nid.szTip, tip.c_str(), _TRUNCATE);
    if (g.tray_added) tray(NIM_MODIFY);
}

void show(bool on) {
    if (on) {
        ShowWindow(g.wnd, SW_SHOWNORMAL);
        SetForegroundWindow(g.wnd);
    } else {
        ShowWindow(g.wnd, SW_HIDE);
    }
}

void quit() {
    if (g.tray_added) tray(NIM_DELETE);
    g.tray_added = false;
    DestroyWindow(g.wnd);
}

LRESULT CALLBACK proc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == g.taskbar_created && g.taskbar_created) {
        tray(NIM_ADD);  // Explorer started again: the icon must be added again
        return 0;
    }
    switch (msg) {
        case WM_CREATE: {
            g.wnd = h;
            auto mk = [&](const wchar_t* cls, const wchar_t* text, DWORD style, int id, DWORD ex = 0) {
                CreateWindowExW(ex, cls, text, WS_CHILD | WS_VISIBLE | style, 0, 0, 10, 10, h,
                                reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), nullptr, nullptr);
            };
            mk(L"STATIC", L"", SS_LEFT | SS_ENDELLIPSIS, IdStatus);
            mk(L"STATIC", L"", SS_LEFT, IdMessage);
            mk(L"STATIC", L"Pairing code:", SS_LEFT | SS_CENTERIMAGE, IdCodeLabel);
            mk(L"EDIT", L"", ES_NUMBER | ES_CENTER | WS_TABSTOP | WS_BORDER, IdCode);
            SendDlgItemMessageW(h, IdCode, EM_LIMITTEXT, 6, 0);
            mk(L"BUTTON", L"Pair", BS_DEFPUSHBUTTON | WS_TABSTOP, IdPair);
            mk(L"STATIC", L"Being sent to the headset:", SS_LEFT, IdSendingLabel);
            mk(L"LISTBOX", L"", LBS_NOINTEGRALHEIGHT | LBS_NOSEL | WS_VSCROLL | WS_BORDER, IdSending);
            mk(L"STATIC", L"", SS_LEFT, IdEncoder);
            mk(L"BUTTON", L"Forget headset", WS_TABSTOP, IdForget);
            mk(L"BUTTON", L"Quit", WS_TABSTOP, IdQuit);
            set_font();
            layout();
            // The way out when the headset's mouse is on the PC: hot keys that work whatever has the focus, and the
            // PC's own mouse and keyboard always winning (input.h).
            if (!RegisterHotKey(h, HotHandsOff, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_F12))
                logf("ui: Ctrl+Alt+F12 is taken by another program");
            if (!RegisterHotKey(h, HotStopAll, MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT, VK_F12))
                logf("ui: Ctrl+Alt+Shift+F12 is taken by another program");
            input::watch_local_input(true);
            SetTimer(h, kWatchTimer, 250, nullptr);
            return 0;
        }
        case WM_HOTKEY:
            if (wp == HotHandsOff) {
                const bool on = !input::hands_off();
                input::set_hands_off(on);
                g.session->notice(on ? "hands off at the PC: its mouse and keys are its own (Ctrl+Alt+F12 to give "
                                       "them back)"
                                     : "the headset has the PC's mouse and keys again");
            } else if (wp == HotStopAll) {
                const bool on = !g.session->sending();
                g.session->set_sending(on);
                input::set_hands_off(!on);
                g.session->notice(on ? "sending allowed again at the PC" : "sending stopped at the PC");
            }
            refresh();
            return 0;
        case WM_TIMER:
            if (wp == kWatchTimer && input::take_local_takeover() && !input::hands_off())
                g.session->notice("someone is using the PC's own mouse or keyboard: the headset's wait a moment");
            return 0;
        case WM_DPICHANGED: {
            const RECT* r = reinterpret_cast<const RECT*>(lp);
            SetWindowPos(h, nullptr, r->left, r->top, r->right - r->left, r->bottom - r->top, SWP_NOZORDER);
            set_font();
            layout();
            return 0;
        }
        case WM_COMMAND:
            switch (LOWORD(wp)) {
                case IdPair: {
                    wchar_t code[16] = {};
                    GetDlgItemTextW(h, IdCode, code, 16);
                    g.session->pair(to_utf8(code));
                    SetDlgItemTextW(h, IdCode, L"");
                    return 0;
                }
                case IdForget:
                    if (MessageBoxW(h, L"Forget the headset? It will need a new code to pair again.", L"PC windows",
                                    MB_OKCANCEL | MB_ICONQUESTION) == IDOK) {
                        g.session->forget();
                    }
                    return 0;
                case IdQuit:
                case IdMenuQuit: quit(); return 0;
                case IdMenuShow: show(true); return 0;
            }
            break;
        case kTrayMsg:
            switch (LOWORD(lp)) {
                case NIN_SELECT:
                case NIN_KEYSELECT:
                case WM_LBUTTONUP: show(!IsWindowVisible(h)); return 0;
                case WM_CONTEXTMENU:
                case WM_RBUTTONUP: {
                    HMENU m = CreatePopupMenu();
                    AppendMenuW(m, MF_STRING, IdMenuShow, L"Show");
                    AppendMenuW(m, MF_STRING, IdMenuQuit, L"Quit");
                    POINT pt;
                    GetCursorPos(&pt);
                    SetForegroundWindow(h);  // so the menu closes when clicking elsewhere
                    TrackPopupMenu(m, TPM_RIGHTBUTTON, pt.x, pt.y, 0, h, nullptr);
                    DestroyMenu(m);
                    return 0;
                }
            }
            return 0;
        case kStatusMsg: refresh(); return 0;
        case WM_CLOSE: show(false); return 0;  // the window hides; Quit ends the app
        case WM_QUERYENDSESSION: return TRUE;
        case WM_ENDSESSION:
            if (wp) quit();
            return 0;
        case WM_DESTROY:
            UnregisterHotKey(h, HotHandsOff);
            UnregisterHotKey(h, HotStopAll);
            KillTimer(h, kWatchTimer);
            input::watch_local_input(false);
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

}  // namespace

int run(HINSTANCE inst, Session& session, bool show_now) {
    g.session = &session;
    INITCOMMONCONTROLSEX icc{sizeof icc, ICC_STANDARD_CLASSES};
    InitCommonControlsEx(&icc);
    g.icon = make_icon(GetSystemMetrics(SM_CXSMICON) * 2);
    WNDCLASSEXW wc{sizeof wc};
    wc.lpfnWndProc = proc;
    wc.hInstance = inst;
    wc.hIcon = g.icon;
    wc.hIconSm = g.icon;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1);
    wc.lpszClassName = L"pc-windows";
    RegisterClassExW(&wc);
    g.taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
    HWND w = CreateWindowExW(0, wc.lpszClassName, L"PC windows", WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU |
                             WS_MINIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT, 400, 300, nullptr, nullptr, inst, nullptr);
    if (!w) return 1;
    tray(NIM_ADD);
    session.set_on_change([w] { PostMessageW(w, kStatusMsg, 0, 0); });
    refresh();
    if (show_now) show(true);
    MSG m;
    while (GetMessageW(&m, nullptr, 0, 0) > 0) {
        if (!IsDialogMessageW(w, &m)) {
            TranslateMessage(&m);
            DispatchMessageW(&m);
        }
    }
    session.set_on_change(nullptr);
    if (g.font) DeleteObject(g.font);
    return 0;
}

}  // namespace pcw::ui
