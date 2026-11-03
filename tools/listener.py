#!/usr/bin/env python3
"""The PC end of the dev link (docs/dev/control-protocol.md). Python 3.8+, standard library only.

The headset connects OUT to this listener; nothing listens on the headset. The listener logs every event to a file
and lets a terminal, a script or an AI session send commands back on the same connection.

    python tools/listener.py serve                 # listen for the headset on 0.0.0.0:47800, log, accept commands
    python tools/listener.py send play             # one command; prints the reply as JSON; exit 1 on failure
    python tools/listener.py send seek 120         # positional arguments follow the command's params (see describe)
    python tools/listener.py send set setting=volume value=0.5
    python tools/listener.py send '{"cmd": "open", "args": {"path": "/home/steamos/films/a.mkv"}}'
    python tools/listener.py send load_gltf --b64 data=room.glb name=Room   # a PC file sent inline
    python tools/listener.py describe              # the schema of every command, setting and event
    python tools/listener.py status                # is the headset connected; its hello
    python tools/listener.py events -f             # print events as they arrive (-e NAME to filter, -n N for history)
    python tools/listener.py wait file_opened -t 30   # block until the next such event; print it
    python tools/listener.py say dim the lights and skip to chapter 9   # a sentence, as a voice command (voice.py)
    python tools/listener.py ask who is the man in the hat      # watch-along: the question with the film's context
    python tools/listener.py answer "He is the brother."         # the answer on a card beside the screen

`serve` also reads commands typed on its own terminal, in the same form as `send` (`seek 120`, or a JSON line).
Other commands talk to a running `serve` through a control port bound to 127.0.0.1 only.

Files (default folder ~/.frame-listener, --log-dir to change):
    events-YYYY-MM-DD.jsonl   every message from the headset and every command sent, one JSON object per line,
                              with "rx" (PC receive time) added
    shots/                    images the headset sent inline (screenshots); the log has "local_path" instead of data
    voice/                    push-to-talk clips (WAV) from the headset; transcribed when a transcriber is set up
                              (serve --transcriber CMD, or see tools/voice.py), else typed: `say <sentence>`
"""

import argparse
import base64
import datetime
import json
import os
import queue
import shlex
import socket
import sys
import threading
import time

import voice
import watch_along

HEADSET_PORT = 47800
CONTROL_PORT = 47802  # 47801 is the assistant link (tools/assistant, docs/assistant.md)
DEFAULT_LOG_DIR = os.path.join(os.path.expanduser("~"), ".frame-listener")
MAX_LINE = 256 << 20



def tcp_server_socket():
    """A TCP socket for a server. On Windows, SO_REUSEADDR lets a second process bind a port in use (both then get
    connections), so a stale listener would answer instead of the new one: there it binds exclusively."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
        s.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
    else:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    return s


def open_server(bind, port, backlog):
    srv = tcp_server_socket()
    srv.bind((bind, port))
    srv.listen(backlog)
    return srv

def now_iso():
    return datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]


class Listener:
    """One headset connection at a time; a new one replaces the old. Thread per connection."""

    def __init__(self, log_dir, allow, quiet, transcriber=None):
        self.log_dir = log_dir
        self.voice_dir = os.path.join(log_dir, "voice")
        self.transcriber = transcriber
        self.voice_count = 0
        self.shot_dir = os.path.join(log_dir, "shots")
        os.makedirs(self.shot_dir, exist_ok=True)
        self.allow = set(allow or [])
        self.quiet = quiet
        self.lock = threading.Lock()
        self.headset = None          # socket
        self.peer = None
        self.hello = None
        self.schema = None
        self.connected_at = None
        self.next_id = 1
        self.waiting = {}            # id -> [threading.Event, reply]
        self.subscribers = []        # queue.Queue per control subscriber
        self.log_lock = threading.Lock()
        self.last_question = None    # (question, time) of the last `ask`, for the answer card's heading
        self._conversation_time = 0.0
        self._utterance_count = 0
        self._pending_uids = []     # utterances whose final clip has not arrived yet, oldest first
        self._live_uid = None       # the utterance being recorded now
        self._live_pcm = bytearray()
        self._live_busy = False
        self._model_lock = threading.Lock()  # one transcription at a time (CPU, and the model is shared)
        self.conversation = []      # [{uid, who, text, live}]: utterances and answers, shown together on the card
        self.shot_count = 0

    # --- log ------------------------------------------------------------------------------------------------------

    def log(self, obj):
        obj = dict(obj)
        obj["rx"] = time.time()
        path = os.path.join(self.log_dir, "events-%s.jsonl" % datetime.date.today().isoformat())
        line = json.dumps(obj, ensure_ascii=False)
        with self.log_lock:
            with open(path, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        return obj

    def save_images(self, obj):
        """Replaces every {"png_b64": ...} in obj with {"local_path": ...}, writing the file."""
        if isinstance(obj, dict):
            if "png_b64" in obj:
                data = base64.b64decode(obj.pop("png_b64"))
                with self.lock:
                    self.shot_count += 1
                    n = self.shot_count
                name = "%s_%03d_%s.png" % (datetime.datetime.now().strftime("%Y%m%d-%H%M%S"), n,
                                            str(obj.get("view", "image")).replace("/", "_"))
                path = os.path.join(self.shot_dir, name)
                with open(path, "wb") as f:
                    f.write(data)
                obj["local_path"] = path
            for v in obj.values():
                self.save_images(v)
        elif isinstance(obj, list):
            for v in obj:
                self.save_images(v)
        return obj

    def say(self, text):
        if not self.quiet:
            print("%s %s" % (now_iso(), text), flush=True)

    # --- headset side ---------------------------------------------------------------------------------------------

    def serve_headset(self, srv):
        bind, port = srv.getsockname()[:2]
        self.say("listening for the headset on %s:%d (log: %s)" % (bind, port, self.log_dir))
        while True:
            conn, addr = srv.accept()
            if self.allow and addr[0] not in self.allow:
                self.say("refused %s:%d (not in --allow)" % addr)
                conn.close()
                continue
            conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            conn.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            with self.lock:
                old = self.headset
                self.headset, self.peer, self.hello, self.connected_at = conn, addr, None, time.time()
            if old is not None:
                try:
                    old.close()
                except OSError:
                    pass
            threading.Thread(target=self.read_headset, args=(conn, addr), daemon=True).start()

    def read_headset(self, conn, addr):
        self.say("headset connected from %s:%d" % addr)
        buf = b""
        try:
            while True:
                data = conn.recv(1 << 16)
                if not data:
                    break
                buf += data
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if line.strip():
                        self.on_line(line)
                if len(buf) > MAX_LINE:
                    buf = b""
        except OSError as e:
            self.say("headset connection error: %s" % e)
        with self.lock:
            current = self.headset is conn
            if current:
                self.headset = None
            # Fail everyone waiting for a reply on this connection.
            for w in self.waiting.values():
                w[1] = {"type": "reply", "ok": False, "error": "the headset disconnected"}
                w[0].set()
            self.waiting.clear()
        self.say("headset disconnected (%s:%d)" % addr)
        self.publish(self.log({"type": "listener", "event": "disconnected", "peer": "%s:%d" % addr}))

    def on_line(self, line):
        try:
            msg = json.loads(line.decode("utf-8"))
        except (ValueError, UnicodeDecodeError) as e:
            self.say("bad line from the headset: %s" % e)
            return
        if not isinstance(msg, dict):
            return
        msg = self.save_images(msg)
        kind = msg.get("type")
        if kind == "event" and msg.get("event") == "voice_partial":
            # Live audio: transcribed, never printed or logged (the final voice_clip is saved as a WAV).
            self.on_voice_partial(msg.get("data") or {})
            return
        clip = self.save_clip(msg) if kind == "event" and msg.get("event") == "voice_clip" else None
        logged = self.log(msg)
        if kind == "hello":
            with self.lock:
                self.hello = msg
            self.say("hello: %s, engine %s, %s %s, session %s" % (msg.get("app"), msg.get("engine"), msg.get("os"),
                                                                  msg.get("model"), msg.get("session")))
            # Fetch the schema for positional arguments.
            threading.Thread(target=self.fetch_schema, daemon=True).start()
        elif kind == "reply":
            with self.lock:
                w = self.waiting.pop(msg.get("id"), None)
            if w is not None:
                w[1] = msg
                w[0].set()
            elif msg.get("ok") is False:
                self.say("error from the headset: %s" % msg.get("error"))
        elif kind == "event":
            self.print_event(msg)
        self.publish(logged)
        # Each press of the talk button is one utterance with its own line on the card: "(listening)" with dancing dots,
        # filled in by the live transcription, and replaced by the final one. A new press while the last one is still
        # being transcribed gets a new line; it never takes over the old one (the user talks faster than it settles).
        # Never wait for a headset reply on this reader thread: the reply arrives on this same thread (it deadlocked
        # for 15 s and the headset dropped the link as stalled).
        if kind == "event" and msg.get("event") == "voice_state" and (msg.get("data") or {}).get("recording"):
            with self.lock:
                self._utterance_count += 1
                uid = self._utterance_count
                self._live_uid = uid
                self._live_pcm = bytearray()
                self._pending_uids.append(uid)
            threading.Thread(target=self.set_line, args=(uid, "You", "(listening)", True), daemon=True).start()
        if clip:
            with self.lock:
                uid = self._pending_uids.pop(0) if self._pending_uids else None
                if uid == self._live_uid:
                    self._live_uid = None  # no more partial updates for it: the final transcription is coming
            threading.Thread(target=self.on_voice_clip, args=(clip, msg.get("data") or {}, uid), daemon=True).start()

    def on_voice_partial(self, data):
        """Live transcription: appends the new audio and, unless a transcription is already running, transcribes all of
        it so far and shows it on the utterance's line (corrected as more arrives)."""
        try:
            pcm = base64.b64decode(data.get("pcm_b64") or "")
        except (ValueError, TypeError):
            return
        with self.lock:
            if self._live_uid is None:
                return
            self._live_pcm.extend(pcm)
            if self._live_busy:
                return
            self._live_busy = True
        threading.Thread(target=self._live_worker, daemon=True).start()

    def _live_worker(self):
        try:
            while True:
                with self.lock:
                    uid = self._live_uid
                    pcm = bytes(self._live_pcm)
                if uid is None:
                    return
                with self._model_lock:
                    text = voice.transcribe_pcm(pcm)
                with self.lock:
                    current = uid == self._live_uid
                    more = len(self._live_pcm) > len(pcm)
                if current and text:
                    self.set_line(uid, "You", text, True)
                if not (current and more):
                    return
        finally:
            with self.lock:
                self._live_busy = False

    # --- voice (docs/dev/voice.md) --------------------------------------------------------------------------------

    def save_clip(self, msg):
        """Writes a voice_clip event's WAV to voice/; the log keeps its path instead of the data."""
        data = msg.get("data")
        if not isinstance(data, dict) or "wav_b64" not in data:
            return None
        raw = base64.b64decode(data.pop("wav_b64"))
        os.makedirs(self.voice_dir, exist_ok=True)
        with self.lock:
            self.voice_count += 1
            n = self.voice_count
        path = os.path.join(self.voice_dir, "%s_%03d.wav" % (datetime.datetime.now().strftime("%Y%m%d-%H%M%S"), n))
        with open(path, "wb") as f:
            f.write(raw)
        data["local_path"] = path
        return path

    def on_voice_clip(self, path, data, uid=None):
        with self._model_lock:
            text = voice.transcribe(path, self.transcriber)
        if not text:
            self.say("voice clip (%.1f s, peak %s) saved: %s. No transcriber%s; type the sentence: say <sentence>"
                     % (float(data.get("seconds", 0)), data.get("peak"), path,
                        "" if voice.transcriber_name(self.transcriber) is None else " result"))
            self.publish(self.log({"type": "voice", "clip": path, "text": None}))
            if uid is not None:
                self.set_line(uid, "You", None)  # drops the utterance's line
            return
        self.say("heard: %s" % text)
        if uid is not None:
            self.set_line(uid, "You", text)
        else:
            self.add_to_conversation("You", text)
        self.run_sentence(text, clip=path)

    def run_sentence(self, text, clip=None, dry_run=False):
        def send(cmd, args):
            return self.command({"cmd": cmd, "args": args}, timeout=30)

        def get_state():
            reply = self.command({"cmd": "get"}, timeout=10)
            return reply.get("result") if reply.get("ok") else {}

        report = voice.run(text, send, get_state, dry_run=dry_run)
        for e in report["actions"]:
            self.say("  %s %s%s" % (e["cmd"], json.dumps(e["args"], ensure_ascii=False),
                                    "" if e.get("ok") is not False else "  -> %s" % e.get("error")))
        for u in report["unknown"]:
            self.say("  not understood: %s" % u)
        entry = dict(report, type="voice")
        if clip:
            entry["clip"] = clip
        self.publish(self.log(entry))
        return report

    # --- watch-along (idea #54; tools/watch_along.py, docs/dev/watch-along.md) -------------------------------------

    def ask(self, question, lines=watch_along.DEFAULT_LINES):
        """Gathers the context of a question from the headset, prints it as one block and logs it."""
        def send(cmd, args):
            return self.command({"cmd": cmd, "args": args}, timeout=15)

        ctx = watch_along.gather(send, question, lines)
        block = watch_along.format_block(ctx)
        with self.lock:
            self.last_question = (ctx["question"], time.time())
        print(block, flush=True)
        self.publish(self.log({"type": "ask", "question": ctx["question"], "context": ctx}))
        return {"ok": "file" in ctx, "block": block, "context": ctx}

    CONVERSATION_CHARS = 1500     # an upper bound; the card itself drops the oldest lines that do not fit
    CONVERSATION_SECONDS = 180

    def add_to_conversation(self, who, text):
        """Adds a line (an answer, or a sentence without an utterance) to the running conversation and shows it on the
        card at once, under what was said (the user's request, 2026-10-31)."""
        return self.set_line(None, who, text)

    def set_line(self, uid, who, text, live=False):
        """Sets an utterance's line (uid: the talk-button press it belongs to; text None removes it), or appends a new
        line when uid is None, then shows the conversation on the card. A `live` line is a transcription in progress:
        the card draws dancing dots after it until its final text arrives."""
        with self.lock:
            entry = next((e for e in self.conversation if uid is not None and e["uid"] == uid), None)
            if text is None:
                if entry is not None:
                    self.conversation.remove(entry)
            elif entry is not None:
                entry.update(text=" ".join(str(text).split()), live=live)
            else:
                self.conversation.append({"uid": uid, "who": who, "text": " ".join(str(text).split()), "live": live})
            self._conversation_time = time.time()
            lines = []
            total = 0
            for e in reversed(self.conversation):
                t = e["text"] if len(e["text"]) <= 2000 else e["text"][:1997] + "..."
                line = "%s: %s%s" % (e["who"], t, " ..." if e["live"] else "")
                if lines and total + len(line) > self.CONVERSATION_CHARS:
                    break
                lines.insert(0, line)
                total += len(line) + 2
            del self.conversation[:-12]
            # The card draws dots only after a live LAST line; a live line further up keeps its "...".
        reply = self.command({"cmd": "card", "args": watch_along.card_args(
            "\n\n".join(lines), "Conversation", self.CONVERSATION_SECONDS)}, timeout=15)
        return reply

    def answer(self, text, title=None, seconds=None):
        """Shows an answer on the headset's card. With a push-to-talk conversation going (a line heard in the last
        10 minutes) and no title given, the answer goes under the conversation instead. Else the heading defaults to
        the last question (asked within 30 min)."""
        if title is None and self.conversation_recent():
            reply = self.add_to_conversation("Claude", text)
            self.publish(self.log({"type": "answer", "text": text, "title": "Conversation",
                                   "ok": bool(reply.get("ok"))}))
            return reply
        if title is None:
            with self.lock:
                q = self.last_question
            title = watch_along.question_title(q[0]) if q and time.time() - q[1] < 1800 else "Answer"
        reply = self.command({"cmd": "card", "args": watch_along.card_args(text, title, seconds)}, timeout=15)
        self.publish(self.log({"type": "answer", "text": text, "title": title, "ok": bool(reply.get("ok"))}))
        return reply

    def conversation_recent(self):
        with self.lock:
            return bool(self.conversation) and time.time() - self._conversation_time < 600

    def print_event(self, msg):
        name = msg.get("event")
        data = msg.get("data")
        if name == "heartbeat":
            return
        if name == "log" and isinstance(data, dict):
            self.say("[log] %s" % data.get("text", ""))
        elif name in ("error", "warning") and isinstance(data, dict):
            where = (" (%s:%s)" % (data.get("file"), data.get("line"))) if data.get("file") else ""
            self.say("[%s] %s%s" % (name, data.get("text", ""), where))
        else:
            text = json.dumps(data, ensure_ascii=False)
            self.say("[%s] %s" % (name, text if len(text) < 400 else text[:400] + " ..."))

    def fetch_schema(self):
        reply = self.command({"cmd": "describe"}, timeout=10)
        if reply.get("ok"):
            with self.lock:
                self.schema = reply.get("result")

    def command(self, msg, timeout=30.0):
        """Sends {"cmd", "args"} to the headset; returns the reply dict."""
        with self.lock:
            conn = self.headset
            if conn is None:
                return {"type": "reply", "ok": False, "error": "no headset connected"}
            cid = self.next_id
            self.next_id += 1
            ev = threading.Event()
            w = [ev, None]
            self.waiting[cid] = w
        out = {"id": cid, "cmd": msg["cmd"], "args": msg.get("args", {})}
        self.log({"type": "command", "id": cid, "cmd": out["cmd"], "args": out["args"]})
        try:
            conn.sendall((json.dumps(out) + "\n").encode("utf-8"))
        except OSError as e:
            with self.lock:
                self.waiting.pop(cid, None)
            return {"type": "reply", "ok": False, "error": "send failed: %s" % e}
        if not ev.wait(timeout):
            with self.lock:
                self.waiting.pop(cid, None)
            return {"type": "reply", "id": cid, "ok": False, "error": "no reply within %.0f s" % timeout}
        return w[1]

    def publish(self, obj):
        with self.lock:
            subs = list(self.subscribers)
        for q in subs:
            q.put(obj)

    # --- control side (127.0.0.1) ---------------------------------------------------------------------------------

    def serve_control(self, srv):
        while True:
            conn, _ = srv.accept()
            threading.Thread(target=self.handle_control, args=(conn,), daemon=True).start()

    def handle_control(self, conn):
        f = conn.makefile("rwb")
        try:
            line = f.readline()
            if not line:
                return
            req = json.loads(line.decode("utf-8"))
            op = req.get("op")
            if op == "send":
                if req.get("text") is not None or req.get("words") is not None:
                    msg, err = self.parse_text(req["text"]) if req.get("text") is not None                         else self.parse_words(req["words"])
                    if err:
                        self.reply(f, {"type": "reply", "ok": False, "error": err})
                        return
                else:
                    msg = req
                self.reply(f, self.command(msg, float(req.get("timeout", 30))))
            elif op == "say":
                self.reply(f, self.run_sentence(str(req.get("text", "")), dry_run=bool(req.get("dry_run"))))
            elif op == "ask":
                self.reply(f, self.ask(str(req.get("text", "")), int(req.get("lines", watch_along.DEFAULT_LINES))))
            elif op == "answer":
                self.reply(f, self.answer(str(req.get("text", "")), req.get("title"), req.get("seconds")))
            elif op == "status":
                with self.lock:
                    st = {"connected": self.headset is not None,
                          "peer": "%s:%d" % self.peer if self.peer else None,
                          "since": self.connected_at, "hello": self.hello, "log_dir": self.log_dir}
                self.reply(f, st)
            elif op == "schema":
                with self.lock:
                    self.reply(f, {"schema": self.schema})
            elif op == "subscribe":
                q = queue.Queue()
                with self.lock:
                    self.subscribers.append(q)
                try:
                    while True:
                        try:
                            obj = q.get(timeout=5)
                        except queue.Empty:
                            obj = {"type": "listener", "event": "keepalive"}
                        self.reply(f, obj)
                except OSError:
                    pass
                finally:
                    with self.lock:
                        self.subscribers.remove(q)
            else:
                self.reply(f, {"ok": False, "error": "unknown op %r" % op})
        except (OSError, ValueError) as e:
            try:
                self.reply(f, {"ok": False, "error": str(e)})
            except OSError:
                pass
        finally:
            try:
                f.close()
                conn.close()
            except OSError:
                pass

    @staticmethod
    def reply(f, obj):
        f.write((json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8"))
        f.flush()

    # --- text commands --------------------------------------------------------------------------------------------

    def parse_text(self, text):
        with self.lock:
            schema = self.schema
        return parse_command_text(text, schema)

    def parse_words(self, words):
        with self.lock:
            schema = self.schema
        if len(words) == 1 and words[0].lstrip().startswith("{"):
            return parse_json_command(words[0])
        return parse_command_words(words[0] if words else "", list(words[1:]), schema)


def parse_value(s):
    try:
        return json.loads(s)
    except ValueError:
        return s


def _params(schema, cmd):
    if schema and cmd in schema.get("commands", {}):
        return schema["commands"][cmd].get("params", [])
    return []


def _single_text_param(schema, cmd):
    """The command's one param when it is a string (open path, run code): it takes the rest of the line verbatim."""
    params = _params(schema, cmd)
    if len(params) == 1 and params[0].get("type") == "string":
        return params[0]["name"]
    return None


def parse_command_text(text, schema):
    """A typed line: `seek 120`, `set volume 0.5`, `open /x/y z.mkv`, `seek seconds=5 relative=true`, or a JSON
    object. Returns (msg, error)."""
    text = text.strip()
    if text.startswith("{"):
        return parse_json_command(text)
    cmd, _, rest = text.partition(" ")
    rest = rest.strip()
    single = _single_text_param(schema, cmd)
    if single is not None and not rest.startswith(single + "="):
        if len(rest) >= 2 and rest[0] == rest[-1] and rest[0] in "'\"":
            rest = rest[1:-1]
        return {"cmd": cmd, "args": {single: rest} if rest else {}}, None
    try:
        words = shlex.split(rest, posix=True)
    except ValueError as e:
        return None, str(e)
    return parse_command_words(cmd, words, schema)


def parse_json_command(text):
    try:
        msg = json.loads(text)
    except ValueError as e:
        return None, "bad JSON: %s" % e
    if not isinstance(msg, dict) or "cmd" not in msg:
        return None, "a JSON command needs \"cmd\""
    return msg, None


def parse_command_words(cmd, words, schema):
    """cmd plus already-split words (command-line arguments). name=value sets a param by name; the others fill the
    remaining params in order. Values are JSON when they parse (numbers, true, lists), else text."""
    if not cmd:
        return None, "empty command"
    params = _params(schema, cmd)
    names = [p["name"] for p in params]
    single = _single_text_param(schema, cmd)
    if single is not None and words and not words[0].startswith(single + "="):
        return {"cmd": cmd, "args": {single: " ".join(words)}}, None
    args = {}
    positional = []
    for w in words:
        k, eq, v = w.partition("=")
        if eq and (k in names or not names):
            args[k] = parse_value(v)
        else:
            positional.append(w)
    free = [n for n in names if n not in args]
    if positional and not names:
        return None, "no schema for %r (is the headset connected? try describe); use name=value or JSON" % cmd
    if len(positional) > len(free):
        return None, "%s takes %d argument(s): %s" % (cmd, len(names), " ".join(names))
    for name, v in zip(free, positional):
        args[name] = v if _param_type(params, name) == "string" else parse_value(v)
    return {"cmd": cmd, "args": args}, None


def _param_type(params, name):
    for p in params:
        if p["name"] == name:
            return p.get("type", "any")
    return "any"


# --- client side of the control port --------------------------------------------------------------------------------

def control(req, port, stream=False):
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    s.settimeout(None)
    f = s.makefile("rwb")
    f.write((json.dumps(req) + "\n").encode("utf-8"))
    f.flush()
    if stream:
        return f
    line = f.readline()
    f.close()
    s.close()
    return json.loads(line.decode("utf-8")) if line else {"ok": False, "error": "no answer"}


def no_listener(port):
    print("No listener on 127.0.0.1:%d. Start one with: python tools/listener.py serve" % port, file=sys.stderr)
    return 2


def cmd_serve(a):
    # Both ports are bound before anything starts, so a second listener stops here instead of running without them.
    try:
        control = open_server("127.0.0.1", a.control_port, 8)
        headset = open_server(a.bind, a.port, 2)
    except OSError as e:
        print("can't listen: %s. Is another listener running? (--port, --control-port)" % e, file=sys.stderr)
        return 1
    lst = Listener(a.log_dir, a.allow, a.quiet, a.transcriber)
    # Load the speech model now, not on the first spoken word (the first clip stalled the link while it loaded).
    threading.Thread(target=lambda: voice.transcribe_pcm(bytes(6400)), daemon=True).start()
    name = voice.transcriber_name(a.transcriber)
    lst.say("voice: %s" % ("transcriber %s" % name if name else
                           "no transcriber; clips are saved and you type the sentence (say <sentence>)"))
    threading.Thread(target=lst.serve_control, args=(control,), daemon=True).start()
    threading.Thread(target=lst.serve_headset, args=(headset,), daemon=True).start()
    try:
        if sys.stdin is None or not sys.stdin.isatty():
            while True:
                time.sleep(3600)
        print("Type commands (`describe`, `ping`, `seek 120`, JSON, `say ...`, `ask ...`, `answer ...`); "
              "Ctrl+C to quit.", flush=True)
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            if line.startswith("say "):
                lst.run_sentence(line[4:])
                continue
            if line.startswith("ask "):
                lst.ask(line[4:])
                continue
            if line.startswith("answer "):
                reply = lst.answer(line[7:])
                print("card shown" if reply.get("ok") else "! %s" % reply.get("error"), flush=True)
                continue
            msg, err = lst.parse_text(line)
            if err:
                print("! %s" % err, flush=True)
                continue
            reply = lst.command(msg, timeout=60)
            print(json.dumps(reply, indent=2, ensure_ascii=False), flush=True)
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        return 0


def msys_root():
    """Git Bash turns arguments that start with / (headset paths, /root) into Windows paths under its own install
    folder before Python sees them. Returns that folder ("C:/Program Files/Git/") so they can be turned back."""
    if not os.environ.get("MSYSTEM"):
        return None
    try:
        import subprocess
        out = subprocess.run(["cygpath", "-m", "/"], capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, ValueError):
        return None
    return out.rstrip("/") + "/" if out else None


def unmangle(words):
    root = msys_root()
    if not root:
        return words
    out = []
    for w in words:
        k, eq, v = w.partition("=")
        if eq and v.startswith(root):
            out.append(k + "=/" + v[len(root):])
        elif w.startswith(root):
            out.append("/" + w[len(root):])
        else:
            out.append(w)
    return out


def cmd_send(a):
    words = unmangle(a.words)
    for spec in getattr(a, "b64", None) or []:
        key, eq, path = spec.partition("=")
        if not eq:
            print("--b64 needs KEY=FILE", file=sys.stderr)
            return 2
        with open(path, "rb") as f:
            words.append("%s=%s" % (key, base64.b64encode(f.read()).decode("ascii")))
    try:
        reply = control({"op": "send", "words": words, "timeout": a.timeout}, a.control_port)
    except OSError:
        return no_listener(a.control_port)
    print(json.dumps(reply.get("result") if (reply.get("ok") and not a.full) else reply, indent=2,
                     ensure_ascii=False))
    return 0 if reply.get("ok") else 1


def cmd_say(a):
    text = " ".join(a.words)
    if a.dry_run:
        actions, unknown = voice.parse(text)
        print(json.dumps({"actions": [{"cmd": x.cmd, "args": {k: ("<relative>" if callable(v) else v)
                                                                for k, v in x.args.items()}, "said": x.said}
                                      for x in actions], "unknown": unknown}, indent=2, ensure_ascii=False))
        return 0 if actions and not unknown else 1
    try:
        report = control({"op": "say", "text": text}, a.control_port)
    except OSError:
        return no_listener(a.control_port)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0 if report.get("ok") else 1


def cmd_ask(a):
    try:
        reply = control({"op": "ask", "text": " ".join(a.words), "lines": a.lines}, a.control_port)
    except OSError:
        return no_listener(a.control_port)
    print(reply.get("block") or json.dumps(reply, indent=2, ensure_ascii=False))
    return 0 if reply.get("ok") else 1


def cmd_answer(a):
    req = {"op": "answer", "text": " ".join(a.words)}
    if a.title is not None:
        req["title"] = a.title
    if a.seconds is not None:
        req["seconds"] = a.seconds
    try:
        reply = control(req, a.control_port)
    except OSError:
        return no_listener(a.control_port)
    print("card shown" if reply.get("ok") else "! %s" % reply.get("error"))
    return 0 if reply.get("ok") else 1


def cmd_status(a):
    try:
        print(json.dumps(control({"op": "status"}, a.control_port), indent=2, ensure_ascii=False))
    except OSError:
        return no_listener(a.control_port)
    return 0


def cmd_describe(a):
    a.words, a.full = ["describe"], False
    return cmd_send(a)


def read_history(log_dir, n, names):
    files = sorted(f for f in os.listdir(log_dir) if f.startswith("events-") and f.endswith(".jsonl")) \
        if os.path.isdir(log_dir) else []
    out = []
    for name in reversed(files):
        with open(os.path.join(log_dir, name), encoding="utf-8") as f:
            lines = f.readlines()
        for line in reversed(lines):
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if names and obj.get("event") not in names:
                continue
            out.append(obj)
            if len(out) >= n:
                return list(reversed(out))
    return list(reversed(out))


def cmd_events(a):
    names = set(a.event or [])
    for obj in read_history(a.log_dir, a.n, names) if a.n > 0 else []:
        print(json.dumps(obj, ensure_ascii=False), flush=True)
    if not a.follow:
        return 0
    try:
        f = control({"op": "subscribe"}, a.control_port, stream=True)
    except OSError:
        return no_listener(a.control_port)
    try:
        for line in f:
            obj = json.loads(line.decode("utf-8"))
            if obj.get("event") == "keepalive" or (names and obj.get("event") not in names):
                continue
            print(json.dumps(obj, ensure_ascii=False), flush=True)
    except KeyboardInterrupt:
        pass
    return 0


def cmd_wait(a):
    try:
        f = control({"op": "subscribe"}, a.control_port, stream=True)
    except OSError:
        return no_listener(a.control_port)
    deadline = time.time() + a.timeout
    for line in f:
        obj = json.loads(line.decode("utf-8"))
        if obj.get("event") == a.event or (a.event == "hello" and obj.get("type") == "hello"):
            print(json.dumps(obj, indent=2, ensure_ascii=False))
            return 0
        if time.time() > deadline:
            break
    print("no %s event within %.0f s" % (a.event, a.timeout), file=sys.stderr)
    return 1


def main(argv=None):
    # A character the console or a redirected file's code page can't show must never kill a thread (the headset
    # sends UTF-8; Windows defaults to cp1252 when stdout is a file).
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--control-port", type=int, default=CONTROL_PORT, help="local control port (127.0.0.1)")
    ap.add_argument("--log-dir", default=DEFAULT_LOG_DIR)
    sub = ap.add_subparsers(dest="what", required=True)

    p = sub.add_parser("serve", help="listen for the headset")
    p.add_argument("--bind", default="0.0.0.0", help="address the headset connects to (default all)")
    p.add_argument("--port", type=int, default=HEADSET_PORT)
    p.add_argument("--allow", action="append", help="accept the headset only from this IP (repeatable)")
    p.add_argument("--quiet", action="store_true", help="don't print events (still logged)")
    p.add_argument("--transcriber", help="command that prints a voice clip's text; {wav} is the clip's path "
                                         "(default: $VOICE_TRANSCRIBE_CMD, else an installed package; tools/voice.py)")
    p.set_defaults(fn=cmd_serve)

    p = sub.add_parser("say", help="run a sentence as a voice command (tools/voice.py)")
    p.add_argument("words", nargs="+")
    p.add_argument("--dry-run", action="store_true", help="only show the actions (no headset or listener needed)")
    p.set_defaults(fn=cmd_say)

    p = sub.add_parser("ask", help="watch-along: print a question with the film's context (file, time, chapter, "
                                   "last subtitle lines, mode) and log it")
    p.add_argument("words", nargs="+")
    p.add_argument("--lines", type=int, default=watch_along.DEFAULT_LINES, help="subtitle lines (default %(default)s)")
    p.set_defaults(fn=cmd_ask)

    p = sub.add_parser("answer", help="watch-along: show an answer on a card beside the screen")
    p.add_argument("words", nargs="+")
    p.add_argument("--title", help="the card's heading (default: the last question)")
    p.add_argument("--seconds", type=float, help="how long it shows (0: until dismissed; default: the headset's)")
    p.set_defaults(fn=cmd_answer)

    p = sub.add_parser("send", help="send one command and print the reply")
    p.add_argument("words", nargs="+", help="command and arguments, or one JSON object")
    p.add_argument("-t", "--timeout", type=float, default=30.0)
    p.add_argument("--full", action="store_true", help="print the whole reply, not just the result")
    p.add_argument("--b64", action="append", metavar="KEY=FILE",
                   help="send a PC file as a base64 argument (load_gltf --b64 data=room.glb)")
    p.set_defaults(fn=cmd_send)

    p = sub.add_parser("describe", help="the schema of every command")
    p.add_argument("-t", "--timeout", type=float, default=30.0)
    p.set_defaults(fn=cmd_describe)

    p = sub.add_parser("status", help="is the headset connected")
    p.set_defaults(fn=cmd_status)

    p = sub.add_parser("events", help="print logged events, and with -f new ones as they arrive")
    p.add_argument("-n", type=int, default=20, help="this many from the log first (0: none)")
    p.add_argument("-f", "--follow", action="store_true")
    p.add_argument("-e", "--event", action="append", help="only this event (repeatable)")
    p.set_defaults(fn=cmd_events)

    p = sub.add_parser("wait", help="wait for the next event of a kind and print it")
    p.add_argument("event")
    p.add_argument("-t", "--timeout", type=float, default=60.0)
    p.set_defaults(fn=cmd_wait)

    # `send` takes options anywhere among its words (load_gltf --b64 data=x.glb name=Room).
    a, extra = ap.parse_known_args(argv)
    if extra:
        if a.what != "send":
            ap.error("unrecognized arguments: %s" % " ".join(extra))
        a.words += extra
    os.makedirs(a.log_dir, exist_ok=True)
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
