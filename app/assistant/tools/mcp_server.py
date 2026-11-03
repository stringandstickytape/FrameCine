#!/usr/bin/env python3
"""An MCP adapter for the VR Video Player's assistant service on the headset (docs/assistant.md, "Optional clients").
Python 3.8+, standard library only. The headset serves this file at https://<headset>:47802/tools/mcp_server.py; it
needs assistant.py (served beside it) in the same folder.

For MCP-capable clients: they start this as a local stdio server. It is a thin client of the headset's HTTPS API
(pair first: the guide at http://<headset>:47801/ says how), so the client can start and stop it as it likes.

The tools are the service's own commands: one tool per command in GET /describe, with its description, its
parameters as the input schema, and hints from its level (read-only for read). A command added to the app is a tool
here with no change to this file. A few tools are more than one call and are made here: get_status,
wait_for_viewer_message, get_recent_viewer_messages, answer_viewer and look_at_room (the snapshot as an image).
The list follows the headset: a command for a level the viewer has not allowed says so in its description, and when
the viewer changes a switch or the app restarts (the event stream's permissions and status events) the client gets
notifications/tools/list_changed. Every tools/list also asks /describe again.

Protocol: MCP over stdio (newline-delimited JSON-RPC 2.0), dual-era:
  - modern (2026-07-28): stateless, every request carries _meta io.modelcontextprotocol/protocolVersion and
    clientCapabilities; server/discover; subscriptions/listen for resource updates and tool list changes;
  - legacy (2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05): the initialize handshake, then requests without _meta;
    resources/subscribe.
Resources (player://state, player://viewer-messages) with update notifications. Nothing is written to stdout but MCP
messages; diagnostics go to stderr.

    python mcp_server.py --url https://192.168.1.50:47802 --token TOKEN --pin "sha256//PIN"
    python mcp_server.py --config vrvp.json           # a file {url, token, pin} (assistant.py pair --save)
    python3 mcp_server.py --url https://127.0.0.1:47802 --config ~/Claude/.assistant-link   # an agent on the headset
VRVP_ASSISTANT_URL, VRVP_ASSISTANT_TOKEN, VRVP_ASSISTANT_PIN and VRVP_ASSISTANT_CONFIG work instead of the arguments.
"""

import argparse

import base64
import json
import os
import re
import sys
import threading
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from assistant import Api  # noqa: E402

SERVER_INFO = {"name": "vr-video-player-assistant", "title": "VR Video Player", "version": "2.0.0"}
MODERN = ["2026-07-28"]
LEGACY = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
WAIT_DEFAULT = 120.0
# Some clients give a tool call about 240 s; stay under it.
WAIT_MAX = 200.0
PROGRESS_EVERY = 15.0
# A command can wait on the headset: opening a file over the network, loading a room change.
COMMAND_TIMEOUT = 210.0
DESCRIBE_TIMEOUT = 15.0

INSTRUCTIONS = (
    "These tools reach a VR video player on a headset: see what plays, control playback, show short text on a card "
    "beside the screen, change the room around the screen, and hear the viewer (push-to-talk, transcribed in the "
    "headset). Call get_status first. Each tool is one of the player's commands; what it may do follows the viewer's "
    "switches (System, Assistant in the headset): a tool for a level the viewer has not allowed says 'Off now' in its "
    "description and is refused, naming the switch to ask for. To talk with the viewer, call wait_for_viewer_message "
    "in a loop: each result is what they said with the film's context; reply with answer_viewer. Keep card text to a "
    "few lines. For the room, room_state first; you send data, never code; each change shows in the headset at once "
    "and is kept (change it back if the viewer asks); look at it with look_at_room. Files on this machine can stand "
    "in for base64 fields: model_path, texture_path, image_path, base_model_path, sky_image_path.")

CAPABILITIES = {"tools": {"listChanged": True}, "resources": {"subscribe": True, "listChanged": False}}

RESOURCES = [
    {"uri": "player://state", "name": "state", "title": "What plays", "mimeType": "application/json",
     "description": "The headset's playback state; updated on play, pause, seek and file changes."},
    {"uri": "player://viewer-messages", "name": "viewer-messages", "title": "What the viewer said",
     "mimeType": "application/json", "description": "The viewer's recent push-to-talk messages with the film's "
     "context; updated when the viewer speaks."},
]

# The switches in the headset (System, Assistant) for the levels that have one, when /describe doesn't name them.
SWITCHES = {"control": "Let the assistant control playback", "room": "Let the assistant change the room"}
# /describe's parameter types -> JSON Schema types ("any" has none).
TYPES = {"string": "string", "str": "string", "int": "integer", "integer": "integer", "float": "number",
         "number": "number", "bool": "boolean", "boolean": "boolean", "array": "array", "list": "array",
         "object": "object", "dict": "object", "dictionary": "object"}
# Commands that are not tools: the tool list itself.
NOT_TOOLS = {"describe"}
# A command that changes or loses something the viewer would miss, by its description.
DESTRUCTIVE = re.compile(r"\b(delet|remov|replac|overwrit|forget|eras|discard|uninstall|wipe)", re.I)
# Events after which the tool list may differ: a switch changed, or a new stream (the app may have restarted).
REFRESH_EVENTS = {"status", "permissions", "commands"}


def _obj(props=None, required=None):
    s = {"type": "object", "properties": props or {}, "additionalProperties": False}
    if required:
        s["required"] = required
    return s


def _ann(read_only, title, idempotent=False):
    return {"title": title, "readOnlyHint": read_only, "destructiveHint": False, "idempotentHint": idempotent,
            "openWorldHint": False}


# The tools made here: more than one plain command. name, description, input schema, annotations, how: ("GET", path),
# ("POST", path), ("IMAGE", path, query keys), ("WAIT",), ("RECENT",).
OWN_TOOLS = [
    ("get_status", "Who is paired, may the assistant control playback (control_allowed) and change the room "
     "(room_allowed), is there speech to text in the headset (transcriber). Call this first.", _obj(),
     _ann(True, "Status", True), ("GET", "/status")),
    ("answer_viewer", "Answers what the viewer said: the text goes under their words on the card. With working true it "
     "is a short note while you work ('Looking that up'): the dots stay, and your next answer replaces it.",
     _obj({"text": {"type": "string"}, "working": {"type": "boolean", "default": False},
           "heard": {"type": "string", "description": "what you transcribed of a message that had no text"},
           "message_id": {"type": "integer", "description": "with heard: that message's id"}}, ["text"]),
     _ann(False, "Answer the viewer"), ("POST", "/answer")),
    ("wait_for_viewer_message", "Waits for the viewer to say something (push-to-talk) and returns it with the "
     "film's context (file, position, chapter, the last subtitle lines). Returns nothing said when it times out; "
     "call it again to keep listening.",
     _obj({"timeout_seconds": {"type": "number", "default": WAIT_DEFAULT, "maximum": WAIT_MAX},
           "since_id": {"type": "integer", "description": "only messages after this id (default: from now)"}}),
     _ann(True, "Wait for the viewer"), ("WAIT",)),
    ("get_recent_viewer_messages", "What the viewer said recently, each with the film's context.",
     _obj({"since_id": {"type": "integer", "default": 0}, "limit": {"type": "integer", "default": 10}}),
     _ann(True, "Recent viewer messages", True), ("RECENT",)),
    ("look_at_room", "A picture (PNG) of what the viewer sees now, or with from=seat the view from the seat towards "
     "the screen (seat: one of room_state's seats by name, else the seat in use). Look at your room changes with it "
     "before you tell the viewer they are done. With seconds (at most 4), a clip instead: one PNG with the frames in "
     "a grid, left to right then down, fps frames a second (default 8) at width (default 320), to check motion.",
     _obj({"from": {"enum": ["viewer", "seat"], "default": "viewer"},
           "seat": {"type": "string", "description": "with from=seat: a seat's name"},
           "width": {"type": "integer", "default": 640, "maximum": 1280},
           "height": {"type": "integer", "description": "default width x 9 / 16"},
           "fov": {"type": "number", "default": 60, "description": "vertical field of view, degrees"},
           "seconds": {"type": "number", "maximum": 4, "description": "a clip of this many seconds"},
           "fps": {"type": "integer", "maximum": 12, "default": 8}}),
     _ann(True, "Look at the room"),
     ("IMAGE", "/snapshot.png", ["from", "seat", "width", "height", "fov", "seconds", "fps"])),
]
OWN = {t[0]: t for t in OWN_TOOLS}

# Fields that may name a file on this machine instead of carrying base64: path field -> base64 field.
PATH_FIELDS = {"model_path": "model", "texture_path": "texture", "image_path": "image",
               "base_model_path": "base_model", "sky_image_path": "sky_image"}
MAX_FILE = 20 * 1024 * 1024


def inline_files(v):
    """Replaces file paths on this machine with their base64 contents, anywhere in a tool's arguments."""
    if isinstance(v, dict):
        out = {}
        for k, x in v.items():
            if k in PATH_FIELDS and isinstance(x, str):
                path = os.path.expanduser(x)
                if os.path.getsize(path) > MAX_FILE:
                    raise ValueError("%s is over %d MB" % (x, MAX_FILE // (1024 * 1024)))
                with open(path, "rb") as f:
                    out[PATH_FIELDS[k]] = base64.b64encode(f.read()).decode()
            else:
                out[k] = inline_files(x)
        return out
    if isinstance(v, list):
        return [inline_files(x) for x in v]
    return v


def param_schema(p):
    """One /describe parameter as a JSON Schema property."""
    s = {}
    t = TYPES.get(str(p.get("type", "")).lower())
    if t:
        s["type"] = t
    if p.get("description"):
        s["description"] = str(p["description"])
    if p.get("default") is not None:
        s["default"] = p["default"]
    if isinstance(p.get("enum"), list) and p["enum"]:
        s["enum"] = p["enum"]
    return s


def input_schema(cmd):
    """The command's input_schema from /describe, else one made from its params; a base64 field gets its *_path twin
    (a file on this machine), and then either will do."""
    given = cmd.get("input_schema")
    if isinstance(given, dict) and given.get("type") == "object":
        s = json.loads(json.dumps(given))
        s.setdefault("properties", {})
    else:
        props, required = {}, []
        for p in cmd.get("params") or []:
            if not isinstance(p, dict) or not p.get("name"):
                continue
            props[str(p["name"])] = param_schema(p)
            if p.get("required"):
                required.append(str(p["name"]))
        s = _obj(props, required)
    props = s["properties"]
    for path_key, field in PATH_FIELDS.items():
        if field in props and path_key not in props:
            props[path_key] = {"type": "string", "description": "a file on this machine, instead of %s" % field}
            if field in (s.get("required") or []):
                s["required"] = [r for r in s["required"] if r != field]
                if not s["required"]:
                    del s["required"]
    return s


def _title(name):
    return name.replace("_", " ").strip().capitalize()


def levels_allowed(levels, status=None):
    """level -> True, False or None (not known from /describe alone: then /status's <level>_allowed decides)."""
    out = {}
    for name, v in (levels or {}).items():
        if isinstance(v, dict) and isinstance(v.get("allowed"), bool):
            out[name] = v["allowed"]
        elif isinstance(v, bool):
            out[name] = v
        elif isinstance(v, str) and v.strip().lower().startswith("always"):
            out[name] = True
        elif status is not None and isinstance(status.get(name + "_allowed"), bool):
            out[name] = status[name + "_allowed"]
        else:
            out[name] = None
    return out


def level_switch(levels, level):
    v = (levels or {}).get(level)
    if isinstance(v, dict) and v.get("switch"):
        return str(v["switch"])
    return SWITCHES.get(level, "")


def command_tool(cmd, levels, allowed):
    """The MCP tool for one /describe command."""
    name = str(cmd["name"])
    level = str(cmd.get("level", ""))
    desc = str(cmd.get("description", "")).strip()
    schema = input_schema(cmd)
    if any(k in schema["properties"] for k in PATH_FIELDS) or "room" in schema["properties"]:
        desc += " Files on this machine can stand in for base64 fields: %s." % ", ".join(sorted(PATH_FIELDS))
    if level and level != "read":
        desc += " (Level: %s.)" % level
    if allowed.get(level) is False:
        switch = level_switch(levels, level)
        desc = "Off now: %s. " % ("the viewer has not turned on \"%s\" (System, Assistant)" % switch if switch
                                  else "the viewer has not allowed %s" % level) + desc
    read = level == "read"
    if "destructive" in cmd:
        destructive = bool(cmd["destructive"])
    else:
        destructive = not read and bool(DESTRUCTIVE.search(str(cmd.get("description", ""))))
    title = str(cmd.get("title") or _title(name))
    ann = {"title": title, "readOnlyHint": read, "destructiveHint": destructive, "idempotentHint": read,
           "openWorldHint": False}
    return {"name": name, "title": title, "description": desc, "inputSchema": schema, "annotations": ann}


class RpcError(Exception):
    def __init__(self, code, message, data=None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.data = data


class McpServer:
    def __init__(self, api=None, out=None):
        self.api = api or Api()
        self.out = out or sys.stdout.buffer
        self.write_lock = threading.Lock()
        self.legacy_version = None
        self.cancelled = set()
        self.lock = threading.Lock()
        self.legacy_subs = set()
        self.modern_subs = {}       # subscription (request) id -> (id, set of URIs, tool list changes wanted)
        self.commands = {}          # tool name -> its MCP tool, from /describe
        self.levels = {}
        self._signature = None
        self.follow_tools = False   # the client has the tool list: follow the events that can change it
        self._watcher = None

    # -- transport --

    def write(self, obj):
        data = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
        with self.write_lock:
            self.out.write(data)
            self.out.flush()

    def serve(self, inp=None):
        inp = inp or sys.stdin.buffer
        for raw in inp:
            raw = raw.strip()
            if not raw:
                continue
            try:
                msg = json.loads(raw.decode("utf-8"))
            except ValueError:
                self.write({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}})
                continue
            if isinstance(msg, list):
                self.write({"jsonrpc": "2.0", "id": None,
                            "error": {"code": -32600, "message": "Batches are not supported"}})
                continue
            if not isinstance(msg, dict) or msg.get("jsonrpc") != "2.0":
                self.write({"jsonrpc": "2.0", "id": None, "error": {"code": -32600, "message": "Invalid Request"}})
                continue
            if "method" not in msg:
                continue  # a response: this server sends no requests
            if "id" not in msg:
                self.notification(msg)
            elif msg.get("method") in ("initialize", "ping", "server/discover", "resources/list"):
                self.request(msg)
            else:
                threading.Thread(target=self.request, args=(msg,), daemon=True).start()

    def notification(self, msg):
        method = msg.get("method")
        params = msg.get("params") or {}
        if method == "notifications/cancelled":
            rid = params.get("requestId")
            with self.lock:
                self.cancelled.add(_key(rid))
                self.modern_subs.pop(_key(rid), None)

    def request(self, msg):
        rid = msg.get("id")
        if rid is None:
            self.write({"jsonrpc": "2.0", "id": None, "error": {"code": -32600, "message": "id must not be null"}})
            return
        try:
            result, modern = self.dispatch(msg)
            if result is None:
                return  # a subscription stream: no response until it ends
            if modern:
                result = dict(result)
                result.setdefault("resultType", "complete")
                meta = dict(result.get("_meta") or {})
                meta["io.modelcontextprotocol/serverInfo"] = SERVER_INFO
                result["_meta"] = meta
            out = {"jsonrpc": "2.0", "id": rid, "result": result}
        except RpcError as e:
            err = {"code": e.code, "message": e.message}
            if e.data is not None:
                err["data"] = e.data
            out = {"jsonrpc": "2.0", "id": rid, "error": err}
        except Exception as e:  # noqa: BLE001
            out = {"jsonrpc": "2.0", "id": rid, "error": {"code": -32603, "message": "Internal error: %s" % e}}
        with self.lock:
            if _key(rid) in self.cancelled:
                self.cancelled.discard(_key(rid))
                return
        self.write(out)

    # -- dispatch --

    def dispatch(self, msg):
        method = msg.get("method")
        params = msg.get("params") or {}
        if not isinstance(params, dict):
            raise RpcError(-32602, "params must be an object")
        meta = params.get("_meta") or {}
        version = meta.get("io.modelcontextprotocol/protocolVersion") if isinstance(meta, dict) else None
        if method == "initialize":
            requested = params.get("protocolVersion")
            self.legacy_version = requested if requested in LEGACY else LEGACY[0]
            return {"protocolVersion": self.legacy_version, "capabilities": CAPABILITIES,
                    "serverInfo": SERVER_INFO, "instructions": INSTRUCTIONS}, False
        if version is not None:
            if version not in MODERN:
                raise RpcError(-32022, "Unsupported protocol version",
                               {"supported": MODERN + LEGACY, "requested": version})
            if "io.modelcontextprotocol/clientCapabilities" not in meta:
                raise RpcError(-32602, "Missing _meta io.modelcontextprotocol/clientCapabilities")
            modern = True
        elif self.legacy_version is not None or method == "ping":
            modern = False
        else:
            raise RpcError(-32602, "Missing _meta io.modelcontextprotocol/protocolVersion: this server speaks %s, "
                                   "or %s after initialize" % (", ".join(MODERN), ", ".join(LEGACY)))
        if method == "ping":
            return {}, modern
        if method == "server/discover":
            if not modern:
                raise RpcError(-32601, "Method not found: server/discover")
            return {"supportedVersions": MODERN + LEGACY, "capabilities": CAPABILITIES,
                    "instructions": INSTRUCTIONS}, True
        if method == "tools/list":
            return {"tools": self.list_tools()}, modern
        if method == "tools/call":
            return self.call_tool(msg.get("id"), params), modern
        if method == "resources/list":
            return {"resources": RESOURCES}, modern
        if method == "resources/templates/list":
            return {"resourceTemplates": []}, modern
        if method == "resources/read":
            return {"contents": [self.read_resource(str(params.get("uri", "")))]}, modern
        if method == "resources/subscribe" and not modern:
            self._uri(params.get("uri"))
            with self.lock:
                self.legacy_subs.add(params["uri"])
            self._watch()
            return {}, False
        if method == "resources/unsubscribe" and not modern:
            with self.lock:
                self.legacy_subs.discard(params.get("uri"))
            return {}, False
        if method == "subscriptions/listen" and modern:
            return self.listen(msg.get("id"), params), True
        if method == "logging/setLevel":
            return {}, modern
        raise RpcError(-32601, "Method not found: %s" % method)

    # -- the tool list --

    def refresh(self):
        """Asks /describe for the commands and the levels allowed now. True when the tool list changed. On failure the
        list stays as it was (only the tools made here, before the first answer)."""
        d = self.api.get("/describe", timeout=DESCRIBE_TIMEOUT)
        res = d.get("result") if d.get("ok") else None
        if not isinstance(res, dict) or not isinstance(res.get("commands"), list):
            return False
        levels = res.get("levels") if isinstance(res.get("levels"), dict) else {}
        allowed = levels_allowed(levels)
        if None in allowed.values():
            st = self.api.get("/status", timeout=DESCRIBE_TIMEOUT)
            allowed = levels_allowed(levels, st.get("result") if st.get("ok") else {})
        tools = {}
        for cmd in res["commands"]:
            if not isinstance(cmd, dict) or not cmd.get("name"):
                continue
            name = str(cmd["name"])
            if name in NOT_TOOLS or name in OWN:
                continue
            tools[name] = command_tool(cmd, levels, allowed)
        signature = json.dumps(tools, sort_keys=True)
        with self.lock:
            changed = self._signature is not None and signature != self._signature
            self.commands = tools
            self.levels = levels
            self._signature = signature
        return changed

    def list_tools(self):
        self.refresh()
        with self.lock:
            self.follow_tools = True
            commands = list(self.commands.values())
        self._watch()
        return [{"name": t[0], "title": t[3]["title"], "description": t[1], "inputSchema": t[2],
                 "annotations": t[3]} for t in OWN_TOOLS] + commands

    def tools_changed(self):
        """notifications/tools/list_changed: to a legacy client after initialize, and to each modern subscription
        that asked for it."""
        with self.lock:
            legacy = self.legacy_version is not None
            modern = [rid for rid, _, tools in self.modern_subs.values() if tools]
        if legacy:
            self.write({"jsonrpc": "2.0", "method": "notifications/tools/list_changed"})
        for rid in modern:
            self.write({"jsonrpc": "2.0", "method": "notifications/tools/list_changed",
                        "params": {"_meta": {"io.modelcontextprotocol/subscriptionId": rid}}})

    def _refresh_and_tell(self):
        if self.refresh():
            self.tools_changed()

    # -- tools --

    def call_tool(self, rid, params):
        name = params.get("name")
        args = params.get("arguments") or {}
        if not isinstance(args, dict):
            raise RpcError(-32602, "arguments must be an object")
        spec = OWN.get(name)
        if spec is not None:
            return self.call_own(rid, spec, args, params.get("_meta") or {})
        with self.lock:
            tool = self.commands.get(name)
        if tool is None:
            # A command the app gained since the list was made, or a call before any tools/list.
            if self.refresh():
                self.tools_changed()
            with self.lock:
                tool = self.commands.get(name)
        if tool is None:
            raise RpcError(-32602, "Unknown tool: %s" % name)
        why = _check_args(tool["inputSchema"], args)
        if why:
            return _tool_result({"ok": False, "error": "%s: %s" % (name, why)})
        try:
            args = inline_files(args)
        except (OSError, ValueError) as e:
            return _tool_result({"ok": False, "error": "can't read the file: %s" % e})
        if isinstance(args.get("room"), dict) and "schema" not in args["room"]:
            args["room"] = dict(args["room"], schema=1)
        r = self.api.post("/command", {"cmd": name, "args": args}, timeout=COMMAND_TIMEOUT)
        if r.get("refused"):
            # The switches may have changed without an event reaching us: the next list says so.
            threading.Thread(target=self._refresh_and_tell, daemon=True).start()
        return _tool_result(r)

    def call_own(self, rid, spec, args, meta):
        why = _check_args(spec[2], args)
        if why:
            return _tool_result({"ok": False, "error": why})
        how = spec[4]
        if how[0] == "GET":
            return _tool_result(self.api.get(how[1]))
        if how[0] == "POST":
            return _tool_result(self.api.post(how[1], args))
        if how[0] == "IMAGE":
            return self.image(how[1], {k: args[k] for k in how[2] if k in args})
        if how[0] == "RECENT":
            r = self.api.get("/messages", {"since": int(args.get("since_id", 0)), "limit": int(args.get("limit", 10))})
            return _messages_result(r, "nothing said yet")
        return self.wait_for_message(rid, args, meta)

    def image(self, path, query):
        """A picture from the headset as MCP image content; its JSON error as a tool error."""
        if "seconds" in query or "fps" in query:
            path = "/snapshot_clip.png"
        q = urllib.parse.urlencode({k: v for k, v in query.items() if v is not None})
        try:
            status, raw = self.api.raw("GET", path + ("?" + q if q else ""), timeout=60)
        except Exception as e:  # PinError, OSError, HTTPException: said as the tool's error
            return _tool_result({"ok": False, "error": "can't get the picture: %s" % e})
        if status == 200 and raw[:8] == b"\x89PNG\r\n\x1a\n":
            return {"content": [{"type": "image", "data": base64.b64encode(raw).decode(), "mimeType": "image/png"}]}
        try:
            r = json.loads(raw.decode("utf-8"))
        except ValueError:
            r = {"ok": False, "error": "HTTP %d" % status}
        return _tool_result(r if isinstance(r, dict) else {"ok": False, "error": "HTTP %d" % status})

    def wait_for_message(self, rid, args, meta):
        timeout = min(max(float(args.get("timeout_seconds", WAIT_DEFAULT)), 1.0), WAIT_MAX)
        since = args.get("since_id")
        if since is None:
            r = self.api.get("/messages", {"since": 0, "limit": 1})
            if not r.get("ok"):
                return _tool_result(r)
            since = r["result"][-1]["id"] if r.get("result") else 0
        token = meta.get("progressToken") if isinstance(meta, dict) else None
        deadline = time.time() + timeout
        waited = 0.0
        while True:
            with self.lock:
                if _key(rid) in self.cancelled:
                    return {"content": [{"type": "text", "text": "cancelled"}], "isError": True}
            left = deadline - time.time()
            if left <= 0:
                return {"content": [{"type": "text", "text": "The viewer said nothing in %.0f s. Call again to keep "
                                     "listening." % timeout}], "structuredContent": {"messages": [], "since_id": since}}
            chunk = min(left, PROGRESS_EVERY)
            r = self.api.get("/messages/wait", {"since": since, "timeout": round(chunk, 1)}, timeout=chunk + 15)
            if not r.get("ok"):
                return _tool_result(r)
            if r.get("result"):
                return _messages_result(r, "")
            waited += chunk
            if token is not None:
                self.write({"jsonrpc": "2.0", "method": "notifications/progress",
                            "params": {"progressToken": token, "progress": round(waited, 1), "total": timeout,
                                       "message": "listening for the viewer"}})

    # -- resources --

    def _uri(self, uri):
        if uri not in [r["uri"] for r in RESOURCES]:
            raise RpcError(-32602, "Unknown resource: %s" % uri)
        return uri

    def read_resource(self, uri):
        self._uri(uri)
        if uri == "player://state":
            r = self.api.get("/state")
        else:
            r = self.api.get("/messages", {"since": 0, "limit": 20})
        return {"uri": uri, "mimeType": "application/json",
                "text": json.dumps(r.get("result") if r.get("ok") else {"error": r.get("error")}, ensure_ascii=False)}

    def listen(self, rid, params):
        wanted = params.get("notifications") or {}
        known = [u for u in wanted.get("resourceSubscriptions") or [] if u in [r["uri"] for r in RESOURCES]]
        tools = bool(wanted.get("toolsListChanged"))
        with self.lock:
            self.modern_subs[_key(rid)] = (rid, set(known), tools)
            if tools:
                self.follow_tools = True
        ack = {"resourceSubscriptions": known}
        if tools:
            ack["toolsListChanged"] = True
        self.write({"jsonrpc": "2.0", "method": "notifications/subscriptions/acknowledged",
                    "params": {"_meta": {"io.modelcontextprotocol/subscriptionId": rid}, "notifications": ack}})
        self._watch()
        return None

    def _wanted(self):
        with self.lock:
            return bool(self.legacy_subs or self.modern_subs or self.follow_tools)

    def _watch(self):
        with self.lock:
            if self._watcher is not None and self._watcher.is_alive():
                return
            self._watcher = threading.Thread(target=self._watch_loop, daemon=True)
            self._watcher.start()

    def _watch_loop(self):
        """Follows the API's event stream while anything wants it: resource updates, and a new tool list when the
        viewer changes a switch or the app restarts (each new stream starts with a status event)."""
        backoff = 1.0
        while True:
            if not self._wanted():
                return
            try:
                for ev in self.api.events(types=["state", "file_opened", "viewer_message", "headset", "permissions",
                                                 "commands"]):
                    backoff = 1.0
                    name = ev.get("event")
                    if name in REFRESH_EVENTS:
                        if self.follow_tools:
                            self._refresh_and_tell()
                        if name == "status":
                            continue
                    if name in ("state", "file_opened", "headset"):
                        self.updated("player://state")
                    elif name == "viewer_message":
                        self.updated("player://viewer-messages")
                    if not self._wanted():
                        return
            except OSError:
                pass
            time.sleep(backoff)
            backoff = min(backoff * 2, 30.0)

    def updated(self, uri):
        with self.lock:
            legacy = uri in self.legacy_subs
            modern = [rid for rid, uris, _ in self.modern_subs.values() if uri in uris]
        if legacy:
            self.write({"jsonrpc": "2.0", "method": "notifications/resources/updated", "params": {"uri": uri}})
        for rid in modern:
            self.write({"jsonrpc": "2.0", "method": "notifications/resources/updated",
                        "params": {"_meta": {"io.modelcontextprotocol/subscriptionId": rid}, "uri": uri}})


def _key(rid):
    return json.dumps(rid)


def _check_args(schema, args):
    """Unknown or missing arguments, said plainly, or ""."""
    props = schema.get("properties") or {}
    if schema.get("additionalProperties") is False:
        unknown = sorted(k for k in args if k not in props)
        if unknown:
            return "unknown arguments %s (the tool's schema lists them)" % unknown
    missing = [k for k in schema.get("required") or [] if k not in args]
    if missing:
        return "missing arguments %s" % missing
    return ""


def _tool_result(r):
    if r.get("ok"):
        res = r.get("result")
        out = {"content": [{"type": "text", "text": json.dumps(res, ensure_ascii=False, indent=1)}]}
        if isinstance(res, dict):
            out["structuredContent"] = res
        return out
    text = str(r.get("error") or "failed")
    switch = r.get("switch")
    if r.get("refused") and switch and str(switch) not in text:
        text += " (ask the viewer to turn on \"%s\" in System, Assistant)" % switch
    return {"content": [{"type": "text", "text": text}], "isError": True}


def _messages_result(r, empty):
    if not r.get("ok"):
        return _tool_result(r)
    msgs = r.get("result") or []
    if not msgs:
        return {"content": [{"type": "text", "text": empty}], "structuredContent": {"messages": []}}
    return {"content": [{"type": "text", "text": "\n\n".join("[message %d] %s" % (m["id"], m.get("block", ""))
                                                              for m in msgs)}],
            "structuredContent": {"messages": msgs, "since_id": msgs[-1]["id"]}}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default=None, help="https://<headset>:47802")
    ap.add_argument("--token", default=None)
    ap.add_argument("--pin", default=None, help="sha256//BASE64 from pairing")
    ap.add_argument("--config", default=None, help="a JSON file {url, token, pin}, or a curl config with the token "
                    "and the pin (an agent's .assistant-link on the headset)")
    a = ap.parse_args(argv)
    McpServer(Api(a.url, a.token, a.pin, config=a.config)).serve()
    return 0


if __name__ == "__main__":
    sys.exit(main())
