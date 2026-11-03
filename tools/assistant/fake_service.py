"""A small stand-in for the headset's assistant service (app/scripts/assistant/assistant_service.gd), over plain HTTP
on 127.0.0.1, for testing the MCP adapter's logic without the engine (tools/assistant/test_mcp_server.py). It keeps
the API's shapes: {ok, result | error}, the token, /describe made from a command list with levels, the level
refusals naming the switch, /messages/wait, /events with the permissions event. The real service is tested by
app/tests/test_assistant.gd and tools/assistant/test_assistant.py. Standard library only.

/describe comes in two forms, as the service has had them: "new" (each command with input_schema, each level with
allowed and its switch) and "old" (params only, levels as text: /status says what is allowed).
"""

import copy
import json
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = "ab" * 32
STATE = {"path": "/home/steamos/Videos/Harbour.mkv", "title": "Harbour", "playing": True, "position": 615.0,
         "duration": 5400.0, "control": True, "room_allowed": True}
# Enough of a PNG for the adapter (it checks the signature and passes the bytes on).
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 24
STOCK = {"stock_parts": [{"name": "Walls", "color": "#303030"}], "bases": ["dim_room"]}


def _p(name, type_, required=False, default=None, description=""):
    p = {"name": name, "type": type_}
    if required:
        p["required"] = True
    else:
        p["default"] = default
    if description:
        p["description"] = description
    return p


# A command set like assistant_commands.gd's: name, level, description, params.
COMMANDS = [
    ("state", "read", "What plays now: path, title, playing, position, duration.", []),
    ("describe", "read", "This list.", []),
    ("places", "read", "The file browser's places: [{label, path}].", []),
    ("list_dir", "read", "A folder as the file browser lists it.",
     [_p("path", "string", True), _p("all", "bool", default=False, description="every file, not just videos")]),
    ("room_state", "read", "The room on show, in the room frame.", []),
    ("browser_page", "read", "The page the Browser source shows now.", []),
    ("perf", "read", "The room's measured cost now.", []),
    ("play", "control", "Plays.", []),
    ("pause", "control", "Pauses.", []),
    ("seek", "control", "Seeks to a time in seconds, or by an amount with relative.",
     [_p("seconds", "float", True), _p("relative", "bool", default=False)]),
    ("open", "control", "Opens a file the headset can reach.",
     [_p("path", "string", True), _p("from_start", "bool", default=False)]),
    ("volume", "control", "The volume: level 0..1, or step (-1..1) from now.",
     [_p("level", "float", default=-1.0), _p("step", "float", default=0.0)]),
    ("fetch", "control", "The headset downloads a file from a server on this network.",
     [_p("url", "string", True), _p("name", "string", default=""), _p("open", "bool", default=True),
      _p("mode", "string", default="")]),
    ("browse", "control", "Asks the viewer to open a web page in the Browser source.", [_p("url", "string", True)]),
    ("add_place", "control", "Suggests a place for the file browser.",
     [_p("label", "string", True), _p("path", "string", True)]),
    ("card", "card", "Shows a short text on a card beside the screen.",
     [_p("text", "string", True), _p("title", "string", default=""), _p("seconds", "float", default=20.0)]),
    ("suggest_seat", "card", "Suggests a seat of the room on show.",
     [_p("seat", "string", True), _p("why", "string", default="")]),
    ("room_apply", "room", "Changes the room on show with a room document (schema 1).",
     [_p("room", "object", True)]),
    ("add_text", "room", "Adds words to the room.",
     [_p("name", "string", True), _p("text", "string", True), _p("size", "float", default=0.1),
      _p("text_options", "object", default={})]),
    ("add_model", "room", "Adds a glTF model (.glb, base64, at most 20 MB).",
     [_p("name", "string", True), _p("model", "string", True, description="the .glb file, base64"),
      _p("position", "array", default=[0, 0, -2])]),
    ("remove", "room", "Removes a part the assistant added.", [_p("name", "string", True)]),
    ("library_delete", "files", "Deletes a file from the Library (a card asks the viewer first).",
     [_p("path", "string", True)]),
]
LEVELS = {"read": "always", "card": "always", "control": "only while the viewer allows playback control",
          "room": "only while the viewer allows room changes", "files": "only while the viewer allows file changes"}
SWITCHES = {"control": "Let the assistant control playback", "room": "Let the assistant change the room",
            "files": "Let the assistant change files"}
TYPES = {"string": "string", "float": "number", "int": "integer", "bool": "boolean", "array": "array",
         "object": "object"}


def _schema(params):
    props, required = {}, []
    for p in params:
        s = {"type": TYPES[p["type"]]}
        if p.get("description"):
            s["description"] = p["description"]
        if "default" in p:
            s["default"] = p["default"]
        props[p["name"]] = s
        if p.get("required"):
            required.append(p["name"])
    out = {"type": "object", "properties": props, "additionalProperties": False}
    if required:
        out["required"] = required
    return out


class FakeService:
    def __init__(self):
        self.received = []          # [{cmd, args}]
        self.cards = []             # [{text, title}]
        self.messages = []
        self.events = []            # [(id, name, data)]
        self.commands = [{"name": n, "level": lv, "description": d, "params": copy.deepcopy(p)}
                         for n, lv, d, p in COMMANDS]
        self.allowed = {"read": True, "card": True, "control": True, "room": True, "files": False}
        self.style = "new"
        self.describes = 0
        self.cond = threading.Condition()
        self.srv = _Server(("127.0.0.1", 0), _handler(self))
        self.srv.daemon_threads = True
        self.url = "http://127.0.0.1:%d" % self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()

    def stop(self):
        self.srv.shutdown()
        self.srv.server_close()

    def publish(self, name, data):
        with self.cond:
            self.events.append((len(self.events) + 1, name, data))
            self.cond.notify_all()

    def add_message(self, text, ctx):
        with self.cond:
            m = {"id": len(self.messages) + 1, "text": text, "context": ctx, "block": "Viewer said: \"%s\"" % text}
            self.messages.append(m)
        self.publish("viewer_message", m)
        return m

    def set_allowed(self, level, on):
        """A switch in the headset: the permissions event follows, as set_allow_control does."""
        self.allowed[level] = on
        self.publish("permissions", {"control": self.allowed["control"], "room": self.allowed["room"]})

    def status(self):
        return {"control_allowed": self.allowed["control"], "room_allowed": self.allowed["room"],
                "files_allowed": self.allowed["files"], "transcriber": "none", "started": 1}

    def describe(self):
        self.describes += 1
        out = []
        for c in self.commands:
            e = {"name": c["name"], "level": c["level"], "description": c["description"], "params": c["params"]}
            if self.style == "new":
                e["input_schema"] = c.get("input_schema") or _schema(c["params"])
            out.append(e)
        if self.style == "new":
            levels = {lv: dict({"allowed": self.allowed[lv], "description": d},
                               **({"switch": SWITCHES[lv]} if lv in SWITCHES else {})) for lv, d in LEVELS.items()}
        else:
            levels = dict(LEVELS)
        return {"ok": True, "result": {"commands": out, "levels": levels, "events": []}}

    def after(self, since, timeout):
        end = time.time() + timeout
        with self.cond:
            while True:
                out = [m for m in self.messages if m["id"] > since]
                if out or time.time() >= end:
                    return out
                self.cond.wait(max(0.01, end - time.time()))

    def command(self, cmd, args):
        spec = next((c for c in self.commands if c["name"] == cmd), None)
        if spec is None:
            return {"ok": False, "refused": True, "error": "%s is not available to the assistant" % cmd}
        level = spec["level"]
        if not self.allowed.get(level, False):
            return {"ok": False, "refused": True, "level": level, "switch": SWITCHES.get(level, ""),
                    "error": "%s: the viewer has not allowed the assistant this (level %s)" % (cmd, level)}
        known = {p["name"] for p in spec["params"]}
        for k in args:
            if k not in known:
                return {"ok": False, "error": "%s: unknown argument %s" % (cmd, k)}
        for p in spec["params"]:
            if p.get("required") and p["name"] not in args:
                return {"ok": False, "error": "%s: %s is required" % (cmd, p["name"])}
        self.received.append({"cmd": cmd, "args": args})
        if cmd == "state":
            return {"ok": True, "result": STATE}
        if cmd == "room_state":
            return {"ok": True, "result": STOCK}
        if cmd == "perf":
            return {"ok": True, "result": {"gpu_ms": 9.8, "budget_ms": 13.89, "headroom_ms": 4.09,
                                           "film_playing": True, "dropped_last_minute": 0}}
        if cmd == "card":
            self.cards.append(args)
        return {"ok": True, "result": {"done": cmd}}


class _Server(ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        # An adapter that ends drops its event stream: not a failure.
        if not isinstance(sys.exc_info()[1], (ConnectionError, OSError)):
            super().handle_error(request, client_address)


def _handler(fake):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def log_message(self, *a):
            pass

        def _send(self, status, obj):
            body = json.dumps(obj).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _ok(self):
            if self.headers.get("Authorization") != "Bearer " + TOKEN:
                self._send(401, {"ok": False, "error": "a token is needed"})
                return False
            return True

        def _query(self):
            return {k: v[0] for k, v in urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).items()}

        def do_GET(self):  # noqa: N802
            if not self._ok():
                return
            path = urllib.parse.urlsplit(self.path).path
            q = self._query()
            if path == "/status":
                return self._send(200, {"ok": True, "result": fake.status()})
            if path == "/describe":
                return self._send(200, fake.describe())
            if path == "/state":
                return self._send(200, fake.command("state", {}))
            if path in ("/snapshot.png", "/snapshot_clip.png"):
                fake.received.append({"cmd": "snapshot" if path == "/snapshot.png" else "clip", "args": q})
                if q.get("from", "viewer") not in ("viewer", "seat"):
                    return self._send(400, {"ok": False, "error": "from: viewer or seat"})
                body = PNG
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if path == "/messages":
                since = int(q.get("since", 0))
                out = [m for m in fake.messages if m["id"] > since][-int(q.get("limit", 20)):]
                return self._send(200, {"ok": True, "result": out})
            if path == "/messages/wait":
                since = int(q["since"]) if "since" in q else len(fake.messages)
                out = fake.after(since, min(float(q.get("timeout", 60)), 600))
                return self._send(200, {"ok": True, "result": out, "timed_out": not out})
            if path == "/events":
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                types = [t for t in q.get("types", "").split(",") if t]
                with fake.cond:
                    last = len(fake.events)
                try:
                    # Every stream starts with the status, as the service's does.
                    self.wfile.write(("id: 0\nevent: status\ndata: %s\n\n" % json.dumps(fake.status())).encode())
                    self.wfile.flush()
                    while True:
                        with fake.cond:
                            fake.cond.wait_for(lambda: len(fake.events) > last, timeout=15)
                            new = fake.events[last:]
                        last += len(new)
                        if not new:
                            self.wfile.write(b": keepalive\n\n")
                        for i, name, data in new:
                            if types and name not in types:
                                continue
                            self.wfile.write(("id: %d\nevent: %s\ndata: %s\n\n" % (i, name, json.dumps(data)))
                                             .encode())
                        self.wfile.flush()
                except OSError:
                    return
            return self._send(404, {"ok": False, "error": "no such endpoint"})

        def do_POST(self):  # noqa: N802
            if not self._ok():
                return
            n = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(n) or b"{}")
            path = urllib.parse.urlsplit(self.path).path
            if path == "/command":
                r = fake.command(body.get("cmd"), body.get("args") or {})
                return self._send(200 if r["ok"] else (403 if r.get("refused") else 422), r)
            if path == "/answer":
                fake.cards.append({"text": body.get("text"), "title": "Conversation", "working": body.get("working")})
                return self._send(200, {"ok": True, "result": {"shown": "conversation"}})
            return self._send(404, {"ok": False, "error": "no such endpoint"})

    return Handler
