#include "control.h"

#include <psapi.h>

#include <algorithm>

#include "input.h"
#include "log.h"
#include "util.h"
#include "video_encoder.h"

namespace pcw {

namespace {

constexpr int64_t kSilenceLimit = 20'000'000;  // nothing from the headset this long: it is gone (it pings every 5 s)
constexpr int64_t kFoundFresh = 10'000'000;    // a discovery reply counts for this long

json::Value msg(const char* type) {
    json::Value v = json::Value::object();
    v.set("t", type);
    return v;
}

}  // namespace

Session::Session(Options options) : opt_(std::move(options)), pc_name_(pc_name()) {
    pairing_ = load_pairing();
    pending_code_ = opt_.code;
    {
        std::lock_guard g(lock_);
        status_.paired = pairing_.has_value();
        if (pairing_) status_.headset = pairing_->headset;
        if (auto c = choose_encoder(opt_.force_codec)) {
            status_.encoder = c->name + (c->codec == media::Codec::Hevc ? L" (HEVC)" : L" (H.264)");
        } else {
            status_.encoder = L"none: no hardware video encoder on this PC";
        }
    }
    discovery_ = std::make_unique<Discovery>(pc_name_, opt_.port, [this](uint32_t a, const HereMessage& h) {
        bool news = false;
        {
            std::lock_guard g(lock_);
            Found& f = found_[h.pin];
            news = f.address != a || f.here.pairing != h.pairing || f.here.name != h.name;
            f.address = a;
            f.here = h;
            f.seen_us = now_us();
            status_.found = true;
            status_.offers_pairing = h.pairing || status_.offers_pairing;
            if (!pairing_ && status_.headset.empty()) status_.headset = h.name;  // shown until one is paired
        }
        if (news) {
            logf("discovery: a headset at %s (%s)", format_ipv4(a).c_str(), h.pairing ? "pairing open" : "paired only");
            changed();
            wake_cv_.notify_all();
        }
    });
    std::vector<uint32_t> uni = opt_.headsets;
    if (pairing_ && pairing_->address) uni.push_back(pairing_->address);
    discovery_->set_unicast(uni);
    control_thread_ = std::thread([this] { control_loop(); });
    watch_thread_ = std::thread([this] { watch_loop(); });
}

Session::~Session() {
    stop();
}

void Session::stop() {
    if (stop_.exchange(true)) return;
    {
        std::lock_guard g(conn_lock_);
        if (conn_) conn_->close();
    }
    wake_cv_.notify_all();
    if (control_thread_.joinable()) control_thread_.join();
    if (watch_thread_.joinable()) watch_thread_.join();
    stop_streams();
    discovery_.reset();
}

Status Session::status() {
    std::lock_guard g(lock_);
    return status_;
}

void Session::set_on_change(std::function<void()> f) {
    std::lock_guard g(lock_);
    on_change_ = std::move(f);
}

void Session::changed() {
    std::function<void()> f;
    {
        std::lock_guard g(lock_);
        f = on_change_;
    }
    if (f) f();
}

void Session::pair(std::string code) {
    code.erase(std::remove_if(code.begin(), code.end(), [](char c) { return c < '0' || c > '9'; }), code.end());
    {
        std::lock_guard g(lock_);
        pending_code_ = code;
        status_.message = code.size() == 6 ? "pairing..." : "the code is six digits";
        if (code.size() != 6) pending_code_.clear();
    }
    changed();
    wake_cv_.notify_all();
}

void Session::forget() {
    forget_pairing();
    {
        std::lock_guard g(lock_);
        pairing_.reset();
        status_.paired = false;
        status_.message = "forgotten; pair again with a code";
    }
    {
        std::lock_guard g(conn_lock_);
        if (conn_) conn_->close();
    }
    changed();
}

Link Session::link() const {
    std::lock_guard g(lock_);
    Link l;
    if (pairing_) {
        l.address = pairing_->address;
        l.port = pairing_->port;
        l.pin = pairing_->pin;
        l.token = pairing_->token;
    }
    return l;
}

void Session::send(const json::Value& m) {
    std::shared_ptr<TlsClient> c;
    {
        std::lock_guard g(conn_lock_);
        c = conn_;
    }
    if (c && !c->send_line(m.dump())) c->close();
}

void Session::notice(const std::string& what) {
    json::Value m = msg("error");
    m.set("what", json::Value::string(what));
    send(m);
}

void Session::set_sending(bool on) {
    sending_ = on;
    logf("control: sending %s at the PC", on ? "allowed again" : "stopped");
    if (!on) stop_streams();
    changed();
}

void Session::stop_streams() {
    std::map<int, std::unique_ptr<VideoStream>> s;
    std::unique_ptr<AudioStream> a;
    {
        std::lock_guard g(streams_lock_);
        s.swap(streams_);
        a.swap(audio_);
    }
    // Stopped outside the lock: a stream may be sending a control message as it ends.
    for (auto& [n, v] : s) v->stop();
    if (a) a->stop();
    input::release_all();
}

void Session::control_loop() {
    name_thread(L"pcw control");
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    int64_t next_direct = 0;
    int failures = 0;
    while (!stop_) {
        // Who to dial: the paired headset where it was last found (or last known), or one offering pairing when
        // we have a code for it.
        uint32_t addr = 0;
        uint16_t port = opt_.port;
        std::string pin, name, code;
        {
            std::lock_guard g(lock_);
            const int64_t now = now_us();
            if (!pending_code_.empty()) {
                const Found* best = nullptr;
                for (auto& [p, f] : found_) {
                    if (f.here.pairing && now - f.seen_us < kFoundFresh && (!best || f.seen_us > best->seen_us)) {
                        best = &f;
                    }
                }
                if (best) {
                    addr = best->address;
                    port = best->here.port;
                    pin = best->here.pin;
                    name = best->here.name;
                    code = pending_code_;
                }
            }
            if (!addr && pairing_) {
                auto it = found_.find(pairing_->pin);
                if (it != found_.end() && now - it->second.seen_us < kFoundFresh) {
                    addr = it->second.address;
                    port = it->second.here.port;
                    name = it->second.here.name;
                } else if (pairing_->address && now >= next_direct) {
                    addr = pairing_->address;  // not heard by broadcast lately: try where it was
                    port = pairing_->port;
                    name = pairing_->headset;
                    next_direct = now + 6'000'000;
                }
                pin = pairing_->pin;
            }
        }
        if (!addr) {
            std::unique_lock g(wake_lock_);
            wake_cv_.wait_for(g, std::chrono::milliseconds(500));
            continue;
        }
        const bool ok = session_once(addr, port, pin, name, code);
        stop_streams();
        {
            std::lock_guard g(conn_lock_);
            conn_.reset();
        }
        discovery_->set_active(true);
        {
            std::lock_guard g(lock_);
            status_.connected = false;
            status_.sending.clear();
            status_.sound = false;
        }
        changed();
        failures = ok ? 0 : std::min(failures + 1, 5);
        // Wait a little before dialling again, longer after repeated failures.
        const int wait_ms = ok ? 1000 : 1000 * failures;
        std::unique_lock g(wake_lock_);
        wake_cv_.wait_for(g, std::chrono::milliseconds(wait_ms), [this] { return stop_.load(); });
    }
    CoUninitialize();
}

bool Session::session_once(uint32_t addr, uint16_t port, const std::string& pin, const std::string& name,
                           const std::string& code) {
    auto c = std::make_shared<TlsClient>();
    std::string err;
    if (!c->connect(addr, port, pin, 5000, err)) {
        logf("control: %s:%u: %s", format_ipv4(addr).c_str(), port, err.c_str());
        std::lock_guard g(lock_);
        status_.message = err;
        return false;
    }
    json::Value hello = msg("hello");
    hello.set("v", kProtocolVersion).set("pc", pc_name_);
    std::string token;
    {
        std::lock_guard g(lock_);
        if (code.empty() && pairing_) token = pairing_->token;
    }
    if (!code.empty()) hello.set("code", code);
    else hello.set("token", token);
    if (!c->send_line(hello.dump())) return false;

    LineSplitter lines;
    std::string buf;
    // The first line: welcome or refused.
    std::optional<json::Value> first;
    const int64_t until = now_us() + 10'000'000;
    while (!first && !stop_ && now_us() < until) {
        buf.clear();
        const int r = c->recv_some(buf, 500);
        if (r == -2) continue;
        if (r <= 0) {
            logf("control: closed before welcome");
            return false;
        }
        if (!lines.feed(buf)) return false;
        while (auto l = lines.next()) {
            if (l->empty()) continue;
            first = json::parse(*l);
            break;
        }
    }
    if (!first || !first->is_object()) {
        logf("control: no welcome");
        return false;
    }
    const std::string t = first->str("t");
    if (t == "refused") {
        const std::string why = first->str("why", "no reason given");
        logf("control: refused (%s)", why.c_str());
        std::lock_guard g(lock_);
        status_.message = "refused: " + why;
        if (!code.empty()) {
            pending_code_.clear();  // a wrong code is not tried again; the next one comes from the window
            status_.message = "the headset refused the code (" + why + ")";
        }
        return false;
    }
    if (t != "welcome") {
        logf("control: unexpected first line");
        return false;
    }
    const std::string headset = first->str("headset", name);
    if (!code.empty()) {
        Pairing p;
        p.headset = headset;
        p.address = addr;
        p.port = port;
        p.pin = pin;
        p.token = first->str("token");
        if (p.token.empty()) {
            logf("control: welcomed after a code but given no token");
            return false;
        }
        save_pairing(p);
        logf("control: paired");
        std::lock_guard g(lock_);
        pairing_ = p;
        pending_code_.clear();
        status_.paired = true;
        discovery_->set_unicast([&] {
            std::vector<uint32_t> u = opt_.headsets;
            u.push_back(addr);
            return u;
        }());
    } else {
        std::lock_guard g(lock_);
        if (pairing_ && (pairing_->address != addr || pairing_->port != port || pairing_->headset != headset)) {
            // It moved (DHCP) or was renamed: keep the new address for next time.
            pairing_->address = addr;
            pairing_->port = port;
            pairing_->headset = headset;
            save_pairing(*pairing_);
        }
    }
    {
        std::lock_guard g(conn_lock_);
        conn_ = c;
    }
    discovery_->set_active(false);
    {
        std::lock_guard g(lock_);
        status_.connected = true;
        status_.found = true;
        status_.headset = headset;
        status_.message = "connected (" + c->tls_version() + ")";
    }
    logf("control: connected to the headset (%s)", c->tls_version().c_str());
    changed();
    list_wanted_ = true;  // the headset will ask, but a list ready at once does no harm

    int64_t last_heard = now_us();
    while (!stop_ && !c->closed()) {
        // Lines that came with the welcome first.
        while (auto l = lines.next()) {
            if (l->empty()) continue;
            auto m = json::parse(*l);
            if (m && m->is_object()) handle(*m);
        }
        buf.clear();
        const int r = c->recv_some(buf, 1000);
        if (r == -2) {
            if (now_us() - last_heard > kSilenceLimit) {
                logf("control: nothing from the headset for %lld s; dialling again",
                     static_cast<long long>(kSilenceLimit / 1'000'000));
                break;
            }
            continue;
        }
        if (r <= 0) {
            logf("control: the connection closed");
            break;
        }
        last_heard = now_us();
        if (!lines.feed(buf)) {
            logf("control: a line too long; closing");
            break;
        }
    }
    c->close();
    return true;
}

void Session::handle(const json::Value& m) {
    const std::string t = m.str("t");
    if (t == "ping") {
        json::Value p = msg("pong");
        p.set("n", m.integer("n"));
        send(p);
    } else if (t == "list") {
        list_wanted_ = true;
        wake_cv_.notify_all();
    } else if (t == "open") {
        if (!sending_) {
            notice("sending is stopped at the PC (Ctrl+Alt+Shift+F12 to allow it)");
            return;
        }
        StreamRequest r;
        r.stream = static_cast<int>(m.integer("stream", -1));
        r.id = m.str("id");
        if (r.stream < 1 || r.id.empty()) return;
        if (const json::Value* mx = m.get("max"); mx && mx->is_array() && mx->items().size() == 2) {
            r.max_w = std::clamp(static_cast<int>(mx->items()[0].as_number()), 64, 8192);
            r.max_h = std::clamp(static_cast<int>(mx->items()[1].as_number()), 64, 8192);
        }
        r.fps = static_cast<int>(m.integer("fps", 30));
        r.kbps = static_cast<int>(m.integer("kbps", 8000));
        logf("control: open stream %d: %s, at most %dx%d, %d fps, %d kbit/s", r.stream, r.id.c_str(), r.max_w,
             r.max_h, r.fps, r.kbps);
        std::unique_ptr<VideoStream> old;
        auto s = std::make_unique<VideoStream>(r, link(), opt_.force_codec, [this](const json::Value& v) { send(v); });
        {
            std::lock_guard g(streams_lock_);
            auto it = streams_.find(r.stream);
            if (it != streams_.end()) old = std::move(it->second);
            streams_[r.stream] = std::move(s);
        }
        if (old) old->stop();
    } else if (t == "quality") {
        std::lock_guard g(streams_lock_);
        auto it = streams_.find(static_cast<int>(m.integer("stream", -1)));
        if (it != streams_.end()) {
            it->second->set_quality(static_cast<int>(m.integer("fps", 0)), static_cast<int>(m.integer("kbps", 0)));
        }
    } else if (t == "close") {
        std::unique_ptr<VideoStream> s;
        {
            std::lock_guard g(streams_lock_);
            auto it = streams_.find(static_cast<int>(m.integer("stream", -1)));
            if (it != streams_.end()) {
                s = std::move(it->second);
                streams_.erase(it);
            }
        }
        if (s) {
            logf("control: close stream %d", s->stream());
            s->stop();
        }
    } else if (t == "sound") {
        const bool on = m.flag("on") && sending_;
        std::unique_ptr<AudioStream> old;
        {
            std::lock_guard g(streams_lock_);
            if (on && !audio_) {
                audio_ = std::make_unique<AudioStream>(link(), [this](const json::Value& v) { send(v); });
            } else if (!on) {
                old = std::move(audio_);
            }
        }
        if (old) old->stop();
        logf("control: sound %s", on ? "on" : "off");
    } else if (t == "mouse" || t == "key" || t == "text" || t == "focus") {
        const std::string id = m.str("id");
        if (t == "key") {
            if (!input::key(m.str("key"), m.flag("down"))) logf("input: unknown key name");
            return;
        }
        if (t == "text") {
            input::text(m.str("text"));
            return;
        }
        auto target = find_target(id);
        if (!target) return;
        if (t == "focus") {
            input::focus(*target);
            return;
        }
        // Positions are in the stream's pixels; without a stream, in the window's own.
        int sw = 0, sh = 0;
        {
            std::lock_guard g(streams_lock_);
            for (auto& [n, s] : streams_) {
                if (s->id() == id) {
                    s->size(sw, sh);
                    if (sw) break;
                }
            }
        }
        if (!sw) {
            if (auto r = captured_rect(*target)) {
                sw = r->width();
                sh = r->height();
            }
        }
        const std::string e = m.str("event");
        const input::MouseEvent ev = e == "down"    ? input::MouseEvent::Down
                                     : e == "up"    ? input::MouseEvent::Up
                                     : e == "wheel" ? input::MouseEvent::Wheel
                                                    : input::MouseEvent::Move;
        input::mouse(*target, ev, m.num("x"), m.num("y"), sw, sh, m.str("button"), m.num("dx"), m.num("dy"));
        std::lock_guard g(mouse_lock_);
        mouse_id_ = id;
    }
    // Anything else is from a newer headset: ignored.
}

void Session::watch_loop() {
    name_thread(L"pcw watch");
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    std::string last_signature;
    int64_t next_list = 0, next_stats = now_us() + opt_.stats_every_s * 1'000'000LL;
    int64_t last_sent_list = 0;
    struct Thumb {
        std::string data;
        int64_t made_us = 0;
        bool sent = false;  // this connection has it: later lists leave it out until it is made again
    };
    std::map<std::string, Thumb> thumbs;
    std::string last_shape;
    std::string last_shape_id;
    FILETIME c0, e0, k0, u0;
    GetProcessTimes(GetCurrentProcess(), &c0, &e0, &k0, &u0);
    int64_t cpu_wall0 = now_us();
    auto ft = [](const FILETIME& f) { return (static_cast<int64_t>(f.dwHighDateTime) << 32) | f.dwLowDateTime; };
    SYSTEM_INFO si;
    GetSystemInfo(&si);

    while (!stop_) {
        {
            std::unique_lock g(wake_lock_);
            wake_cv_.wait_for(g, std::chrono::milliseconds(100));
        }
        if (stop_) break;
        bool connected;
        {
            std::lock_guard g(conn_lock_);
            connected = conn_ != nullptr && !conn_->closed();
        }
        const int64_t now = now_us();

        // Streams that ended by themselves (window closed, connection gone for good).
        std::vector<std::unique_ptr<VideoStream>> done;
        std::unique_ptr<AudioStream> audio_done;
        {
            std::lock_guard g(streams_lock_);
            for (auto it = streams_.begin(); it != streams_.end();) {
                if (it->second->finished()) {
                    done.push_back(std::move(it->second));
                    it = streams_.erase(it);
                } else {
                    ++it;
                }
            }
            if (audio_ && audio_->finished()) audio_done = std::move(audio_);
        }
        for (auto& s : done) s->stop();
        if (audio_done) audio_done->stop();

        if (connected) {
            // The window list: sent when asked, and when it changed (at most once a second).
            if (list_wanted_ || now >= next_list) {
                next_list = now + 1'000'000;
                const auto list = list_windows(opt_.list);
                std::string sig;
                for (const auto& w : list) {
                    sig += w.target.id + '\x1f' + to_utf8(w.title) + '\x1f' + std::to_string(w.w) + 'x' +
                           std::to_string(w.h) + (w.minimised ? "m" : "") + '\x1e';
                }
                const bool asked = list_wanted_.exchange(false);
                if ((asked || sig != last_signature) && (asked || now - last_sent_list >= 1'000'000)) {
                    last_signature = sig;
                    last_sent_list = now;
                    json::Value arr = json::Value::array();
                    for (const auto& w : list) {
                        Thumb& th = thumbs[w.target.id];
                        // A thumbnail is made again when it is older than 10 s, or when the list was asked for.
                        if (th.made_us == 0 || now - th.made_us > 10'000'000 || asked) {
                            std::string fresh = thumbnail_base64(w, 256, opt_.list.only_titles.empty());
                            if (fresh != th.data) th.sent = false;
                            th.data = std::move(fresh);
                            th.made_us = now;
                        }
                        json::Value e = json::Value::object();
                        e.set("id", w.target.id)
                            .set("kind", w.target.monitor ? "monitor" : "window")
                            .set("title", to_utf8(w.title))
                            .set("app", w.app)
                            .set("w", w.w)
                            .set("h", w.h);
                        // Only a thumbnail the headset has not had: a title changing every second (a clock, a
                        // spinner) sent all of them, half a megabyte a second, and the headset lurched each time
                        // (the user, 2026-11-08). An answer to `list` has them all.
                        if (asked || !th.sent) {
                            e.set("thumb", th.data);
                            th.sent = true;
                        }
                        arr.push(std::move(e));
                    }
                    // Thumbnails of windows that went are dropped.
                    for (auto it = thumbs.begin(); it != thumbs.end();) {
                        const bool there = std::any_of(list.begin(), list.end(),
                                                       [&](const WindowInfo& w) { return w.target.id == it->first; });
                        it = there ? std::next(it) : thumbs.erase(it);
                    }
                    json::Value m = msg("windows");
                    m.set("list", std::move(arr));
                    send(m);
                    logf("control: sent the list (%zu windows and monitors)", list.size());
                }
            }

            // The cursor's shape over the window the mouse is on.
            std::string id;
            {
                std::lock_guard g(mouse_lock_);
                id = mouse_id_;
            }
            if (!id.empty()) {
                const std::string shape = input::cursor_shape();
                if (shape != last_shape || id != last_shape_id) {
                    last_shape = shape;
                    last_shape_id = id;
                    json::Value c = msg("cursor");
                    c.set("id", id).set("shape", shape);
                    send(c);
                }
            }
        }

        // What is being sent, for the window.
        {
            std::vector<std::wstring> sending;
            bool sound;
            {
                std::lock_guard g(streams_lock_);
                for (auto& [n, s] : streams_) {
                    std::wstring title = s->id().rfind("m:", 0) == 0 ? L"Monitor " + to_wide(s->id().substr(2)) : L"";
                    if (title.empty()) {
                        if (auto t = find_target(s->id())) {
                            wchar_t buf[256];
                            GetWindowTextW(t->hwnd, buf, 256);
                            title = buf;
                        }
                    }
                    sending.push_back(title);
                }
                sound = audio_ != nullptr;
            }
            bool news = false;
            {
                std::lock_guard g(lock_);
                news = sending != status_.sending || sound != status_.sound;
                status_.sending = sending;
                status_.sound = sound;
            }
            if (news) changed();
        }

        if (now >= next_stats) {
            next_stats = now + opt_.stats_every_s * 1'000'000LL;
            FILETIME c1, e1, k1, u1;
            GetProcessTimes(GetCurrentProcess(), &c1, &e1, &k1, &u1);
            const double cpu_us = (ft(k1) - ft(k0) + ft(u1) - ft(u0)) / 10.0;
            const double wall = static_cast<double>(now - cpu_wall0);
            const double cpu_pct = wall > 0 ? 100.0 * cpu_us / wall / si.dwNumberOfProcessors : 0;
            k0 = k1;
            u0 = u1;
            cpu_wall0 = now;
            PROCESS_MEMORY_COUNTERS pm{};
            GetProcessMemoryInfo(GetCurrentProcess(), &pm, sizeof pm);
            std::vector<StreamStats> st;
            double akbps = 0;
            int aframes = 0;
            {
                std::lock_guard g(streams_lock_);
                for (auto& [n, s] : streams_) st.push_back(s->take_stats());
                if (audio_) audio_->take_stats(akbps, aframes);
            }
            for (const auto& s : st) {
                logf("stats: stream %d %s %dx%d %.1f fps (asked %d, captured %.1f), %.0f kbit/s (asked %d), capture "
                     "to sent p50 %.1f ms p95 %.1f ms max %.1f ms%s",
                     s.stream, s.codec.c_str(), s.w, s.h, s.fps, s.requested_fps, s.captured_fps, s.kbps,
                     s.requested_kbps, s.lat_p50_ms, s.lat_p95_ms, s.lat_max_ms, s.minimised ? " (minimised)" : "");
            }
            if (aframes) logf("stats: sound %.0f kbit/s, %d frames", akbps, aframes);
            logf("stats: cpu %.2f %% of the PC (%u logical processors), memory %.0f MB", cpu_pct,
                 si.dwNumberOfProcessors, pm.WorkingSetSize / 1048576.0);
        }
    }
    CoUninitialize();
}

}  // namespace pcw
