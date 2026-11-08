#include "input.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <mutex>
#include <set>
#include <vector>

#include "../core/keys.h"
#include "../core/mapping.h"
#include "log.h"
#include "util.h"

namespace pcw::input {

namespace {

std::mutex g_lock;
std::set<std::pair<uint16_t, uint32_t>> g_keys;  // held keys: (scan or vk, flags)
std::set<std::string> g_buttons;                  // held mouse buttons, by the protocol's names

// The PC's own input: the headset's is ignored until the PC's has been still this long.
constexpr int64_t kLocalYieldMs = 4000;
std::atomic<bool> g_hands_off{false};
std::atomic<int64_t> g_local_until_ms{0};
std::atomic<bool> g_takeover{false};
std::atomic<bool> g_released{false};
std::atomic<bool> g_local_yield{true};
HHOOK g_mouse_hook = nullptr;
HHOOK g_key_hook = nullptr;

int64_t now_ms() { return static_cast<int64_t>(GetTickCount64()); }

bool may_act();

void local_input() {
    const int64_t now = now_ms();
    if (now >= g_local_until_ms.load()) g_takeover = true;
    g_local_until_ms = now + kLocalYieldMs;
}

// Kept short: Windows drops a low-level hook that is slow to return.
LRESULT CALLBACK mouse_hook(int code, WPARAM wp, LPARAM lp) {
    if (code == HC_ACTION) {
        const auto* m = reinterpret_cast<const MSLLHOOKSTRUCT*>(lp);
        if (!(m->flags & (LLMHF_INJECTED | LLMHF_LOWER_IL_INJECTED))) local_input();
    }
    return CallNextHookEx(nullptr, code, wp, lp);
}

LRESULT CALLBACK key_hook(int code, WPARAM wp, LPARAM lp) {
    if (code == HC_ACTION) {
        const auto* k = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lp);
        if (!(k->flags & (LLKHF_INJECTED | LLKHF_LOWER_IL_INJECTED))) local_input();
    }
    return CallNextHookEx(nullptr, code, wp, lp);
}

bool button_flags(const std::string& b, bool down, DWORD& flags, DWORD& data) {
    data = 0;
    if (b == "left") flags = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
    else if (b == "right") flags = down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP;
    else if (b == "middle") flags = down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP;
    else if (b == "x1" || b == "x2") {
        flags = down ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP;
        data = b == "x1" ? XBUTTON1 : XBUTTON2;
    } else {
        return false;
    }
    return true;
}

mapping::Rect virtual_desktop() {
    return {GetSystemMetrics(SM_XVIRTUALSCREEN), GetSystemMetrics(SM_YVIRTUALSCREEN),
            GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN),
            GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN)};
}

INPUT key_input(const keys::KeyCode& k, bool up) {
    INPUT in{};
    in.type = INPUT_KEYBOARD;
    if (k.scan) {
        in.ki.wScan = k.scan;
        in.ki.dwFlags = KEYEVENTF_SCANCODE;
    } else {
        in.ki.wVk = k.vk;
        in.ki.wScan = static_cast<WORD>(MapVirtualKeyW(k.vk, MAPVK_VK_TO_VSC));
    }
    if (k.extended) in.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
    if (up) in.ki.dwFlags |= KEYEVENTF_KEYUP;
    return in;
}

void send(std::vector<INPUT>& v) {
    if (v.empty()) return;
    const UINT n = SendInput(static_cast<UINT>(v.size()), v.data(), sizeof(INPUT));
    // Windows refuses input into a window of a process with higher rights (UIPI) and while the secure desktop
    // is up; say so once in a while, not for every move.
    if (n != v.size()) {
        static int64_t last = 0;
        if (now_us() - last > 5'000'000) {
            last = now_us();
            logf("input: Windows blocked %u of %zu events (an elevated window, or the lock screen)",
                 static_cast<unsigned>(v.size() - n), v.size());
        }
    }
}

}  // namespace

void mouse(const Target& t, MouseEvent ev, double x, double y, int sw, int sh, const std::string& button, double dx,
           double dy) {
    if (!may_act()) return;
    if (is_minimised(t)) return;
    const auto rect = captured_rect(t);
    if (!rect) return;
    const mapping::Point p = mapping::stream_to_screen(x, y, sw, sh, *rect);
    const mapping::Point a = mapping::to_absolute(p, virtual_desktop());
    std::vector<INPUT> v;
    INPUT m{};
    m.type = INPUT_MOUSE;
    m.mi.dx = a.x;
    m.mi.dy = a.y;
    m.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
    if (ev == MouseEvent::Down || ev == MouseEvent::Up) {
        const bool down = ev == MouseEvent::Down;
        DWORD f = 0, data = 0;
        if (button_flags(button, down, f, data)) {
            // The same event moves and clicks, so the click lands where it was aimed.
            m.mi.dwFlags |= f;
            m.mi.mouseData = data;
            std::lock_guard g(g_lock);
            if (down) g_buttons.insert(button);
            else g_buttons.erase(button);
        }
    }
    v.push_back(m);
    if (ev == MouseEvent::Wheel) {
        // Notches, + up/away and + right; 120 a notch, and fractions for smooth wheels and touchpads.
        if (std::isfinite(dy) && dy != 0) {
            INPUT w{};
            w.type = INPUT_MOUSE;
            w.mi.dwFlags = MOUSEEVENTF_WHEEL;
            w.mi.mouseData = static_cast<DWORD>(static_cast<LONG>(std::lround(std::clamp(dy, -100.0, 100.0) * WHEEL_DELTA)));
            v.push_back(w);
        }
        if (std::isfinite(dx) && dx != 0) {
            INPUT w{};
            w.type = INPUT_MOUSE;
            w.mi.dwFlags = MOUSEEVENTF_HWHEEL;
            w.mi.mouseData = static_cast<DWORD>(static_cast<LONG>(std::lround(std::clamp(dx, -100.0, 100.0) * WHEEL_DELTA)));
            v.push_back(w);
        }
    }
    send(v);
}

bool key(const std::string& name, bool down) {
    const auto k = keys::lookup(name);
    if (!k) return false;
    if (!may_act()) return true;
    std::vector<INPUT> v{key_input(*k, !down)};
    {
        std::lock_guard g(g_lock);
        const auto id = std::make_pair(k->scan ? k->scan : k->vk, static_cast<uint32_t>((k->scan ? 1 : 0) | (k->extended ? 2 : 0)));
        if (down) g_keys.insert(id);
        else g_keys.erase(id);
    }
    send(v);
    return true;
}

void text(const std::string& utf8) {
    if (!may_act()) return;
    const std::wstring w = to_wide(utf8);
    std::vector<INPUT> v;
    auto vk = [&](WORD code) {
        INPUT in{};
        in.type = INPUT_KEYBOARD;
        in.ki.wVk = code;
        in.ki.wScan = static_cast<WORD>(MapVirtualKeyW(code, MAPVK_VK_TO_VSC));
        v.push_back(in);
        in.ki.dwFlags = KEYEVENTF_KEYUP;
        v.push_back(in);
    };
    for (size_t i = 0; i < w.size(); ++i) {
        const wchar_t c = w[i];
        if (c == L'\r') {
            if (i + 1 < w.size() && w[i + 1] == L'\n') continue;
            vk(VK_RETURN);
        } else if (c == L'\n') {
            vk(VK_RETURN);
        } else if (c == L'\t') {
            vk(VK_TAB);
        } else if (c < 0x20 || c == 0x7f) {
            continue;  // other control characters mean nothing typed
        } else {
            INPUT in{};
            in.type = INPUT_KEYBOARD;
            in.ki.wScan = c;
            in.ki.dwFlags = KEYEVENTF_UNICODE;
            v.push_back(in);
            in.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
            v.push_back(in);
        }
    }
    send(v);
}

bool focus(const Target& t) {
    if (!may_act()) return false;
    if (t.monitor) return true;
    HWND h = t.hwnd;
    if (!IsWindow(h)) return false;
    if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
    if (GetForegroundWindow() == h) return true;
    // Windows lets the process that sent the last input event take the foreground, so an empty one first.
    INPUT nothing{};
    nothing.type = INPUT_MOUSE;
    SendInput(1, &nothing, sizeof nothing);
    SetForegroundWindow(h);
    if (GetForegroundWindow() == h) return true;
    // Sharing the foreground window's input state lets us hand it over.
    HWND fg = GetForegroundWindow();
    const DWORD fg_thread = fg ? GetWindowThreadProcessId(fg, nullptr) : 0;
    const DWORD me = GetCurrentThreadId();
    // Not with a hung window in front: attaching to its thread can hang us too.
    if (fg_thread && fg_thread != me && !IsHungAppWindow(fg) && AttachThreadInput(me, fg_thread, TRUE)) {
        BringWindowToTop(h);
        SetForegroundWindow(h);
        AttachThreadInput(me, fg_thread, FALSE);
    }
    if (GetForegroundWindow() == h) return true;
    // The last way: an Alt press, which Windows takes as the user acting.
    INPUT alt[2]{};
    alt[0].type = alt[1].type = INPUT_KEYBOARD;
    alt[0].ki.wVk = alt[1].ki.wVk = VK_MENU;
    alt[1].ki.dwFlags = KEYEVENTF_KEYUP;
    SendInput(1, &alt[0], sizeof(INPUT));
    SetForegroundWindow(h);
    SendInput(1, &alt[1], sizeof(INPUT));
    const bool ok = GetForegroundWindow() == h;
    if (!ok) logf("input: Windows would not bring %s to the front", t.id.c_str());
    return ok;
}

void release_all() {
    std::vector<INPUT> v;
    {
        std::lock_guard g(g_lock);
        for (const auto& [code, f] : g_keys) {
            keys::KeyCode k;
            if (f & 1) k.scan = code;
            else k.vk = code;
            k.extended = (f & 2) != 0;
            v.push_back(key_input(k, true));
        }
        for (const std::string& b : g_buttons) {
            INPUT in{};
            in.type = INPUT_MOUSE;
            DWORD f = 0, data = 0;
            button_flags(b, false, f, data);
            in.mi.dwFlags = f;
            in.mi.mouseData = data;
            v.push_back(in);
        }
        g_keys.clear();
        g_buttons.clear();
    }
    if (!v.empty()) logf("input: let go of %zu held keys and buttons", v.size());
    send(v);
}

std::string cursor_shape() {
    struct Shape {
        LPCWSTR id;
        const char* name;
        HCURSOR h;
    };
    static Shape shapes[] = {
        {IDC_ARROW, "arrow", nullptr},     {IDC_IBEAM, "ibeam", nullptr},     {IDC_HAND, "hand", nullptr},
        {IDC_WAIT, "wait", nullptr},       {IDC_APPSTARTING, "wait", nullptr}, {IDC_CROSS, "cross", nullptr},
        {IDC_SIZEWE, "size_we", nullptr},  {IDC_SIZENS, "size_ns", nullptr},  {IDC_SIZENWSE, "size_nwse", nullptr},
        {IDC_SIZENESW, "size_nesw", nullptr}, {IDC_SIZEALL, "move", nullptr}, {IDC_NO, "no", nullptr},
    };
    static std::once_flag once;
    std::call_once(once, [] {
        for (auto& s : shapes) s.h = LoadCursorW(nullptr, s.id);
    });
    CURSORINFO ci{sizeof ci};
    if (!GetCursorInfo(&ci) || !(ci.flags & CURSOR_SHOWING)) return "arrow";
    for (const auto& s : shapes) {
        if (s.h && s.h == ci.hCursor) return s.name;
    }
    return "other";
}

namespace {

// The headset may act now. On the first refusal it lets go of anything the headset held, so nothing stays down while
// the PC is used directly.
bool may_act() {
    if (g_hands_off || (g_local_yield && now_ms() < g_local_until_ms.load())) {
        if (!g_released.exchange(true)) release_all();
        return false;
    }
    g_released = false;
    return true;
}

}  // namespace

void set_hands_off(bool on) {
    g_hands_off = on;
    logf("input: hands off %s", on ? "on: the headset's mouse and keys are ignored" : "off");
    if (on && !g_released.exchange(true)) release_all();
}

bool hands_off() { return g_hands_off; }

void watch_local_input(bool on) {
    if (on && !g_mouse_hook) {
        g_mouse_hook = SetWindowsHookExW(WH_MOUSE_LL, mouse_hook, GetModuleHandleW(nullptr), 0);
        g_key_hook = SetWindowsHookExW(WH_KEYBOARD_LL, key_hook, GetModuleHandleW(nullptr), 0);
        if (!g_mouse_hook || !g_key_hook) logf("input: could not watch the PC's own mouse and keyboard");
    } else if (!on) {
        if (g_mouse_hook) UnhookWindowsHookEx(g_mouse_hook);
        if (g_key_hook) UnhookWindowsHookEx(g_key_hook);
        g_mouse_hook = g_key_hook = nullptr;
    }
}

bool take_local_takeover() { return g_local_yield && g_takeover.exchange(false); }

void set_local_yield(bool on) { g_local_yield = on; }

}  // namespace pcw::input
