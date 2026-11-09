#!/usr/bin/env python3
"""Tests for the MCP adapter (app/assistant/tools/mcp_server.py) as an MCP client starts it: a subprocess on stdio,
talking to a stand-in for the headset's service (fake_service.py; the real service is tested by test_assistant.py).
Both protocol eras: the legacy initialize handshake and the modern per-request _meta. The tools come from the
service's /describe (both of its forms), follow the viewer's switches, and an agent's curl-config link file works as
the config. Standard library only.

    python tools/assistant/test_mcp_server.py
"""

import base64
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(os.path.dirname(os.path.dirname(HERE)), "app", "assistant", "tools")
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True

from fake_service import TOKEN, FakeService  # noqa: E402

META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientInfo": {"name": "test", "version": "1"},
        "io.modelcontextprotocol/clientCapabilities": {}}
OWN = ("get_status", "answer_viewer", "wait_for_viewer_message", "get_recent_viewer_messages", "look_at_room")


class Client:
    def __init__(self, url, args=None):
        env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONDONTWRITEBYTECODE="1")
        for k in ("VRVP_ASSISTANT_URL", "VRVP_ASSISTANT_TOKEN", "VRVP_ASSISTANT_PIN", "VRVP_ASSISTANT_CONFIG"):
            env.pop(k, None)
        if args is None:
            env.update(VRVP_ASSISTANT_URL=url, VRVP_ASSISTANT_TOKEN=TOKEN)
        self.argv = [sys.executable, os.path.join(TOOLS, "mcp_server.py")] + list(args or [])
        self.p = subprocess.Popen(self.argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  env=env)
        self.q = queue.Queue()
        self.next_id = 1
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.p.stdout:
            self.q.put(json.loads(line))

    def send(self, obj):
        self.p.stdin.write((json.dumps(obj) + "\n").encode())
        self.p.stdin.flush()

    def request(self, method, params=None, modern=False, timeout=30):
        rid = self.next_id
        self.next_id += 1
        params = dict(params or {})
        if modern:
            params["_meta"] = dict(META, **params.get("_meta", {}))
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        return self.wait(lambda m: m.get("id") == rid, timeout)

    def wait(self, cond, timeout=30):
        end = time.time() + timeout
        skipped = []
        try:
            while time.time() < end:
                try:
                    m = self.q.get(timeout=max(0.05, end - time.time()))
                except queue.Empty:
                    break
                if cond(m):
                    return m
                skipped.append(m)
            raise AssertionError("no matching message; got %s" % skipped)
        finally:
            for m in skipped:
                self.q.put(m)

    def close(self):
        if self.p.poll() is None:
            self.p.stdin.close()
            self.p.wait(5)
        self.p.stdout.close()
        self.p.stderr.close()


class McpTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = cls.h = FakeService()
        cls.url = cls.app.url

    @classmethod
    def tearDownClass(cls):
        cls.app.stop()

    def setUp(self):
        self.c = Client(self.url)

    def tearDown(self):
        self.c.close()
        self.h.style = "new"
        self.h.allowed.update(control=True, room=True, files=False)
        self.h.commands = [c for c in self.h.commands if c["name"] != "subtitle_size"]

    def tools(self, modern=True):
        return {t["name"]: t for t in self.c.request("tools/list", modern=modern)["result"]["tools"]}

    def test_legacy_handshake_and_tools(self):
        r = self.c.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                          "clientInfo": {"name": "t", "version": "1"}})
        self.assertEqual(r["result"]["protocolVersion"], "2025-06-18")
        self.assertTrue(r["result"]["capabilities"]["tools"]["listChanged"])
        self.assertIn("wait_for_viewer_message", r["result"]["instructions"])
        self.assertNotIn("resultType", r["result"])
        self.c.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        tools = self.c.request("tools/list")["result"]["tools"]
        names = [t["name"] for t in tools]
        for n in ("state", "play", "pause", "seek", "open", "list_dir", "volume", "card") + OWN:
            self.assertIn(n, names)
        self.assertNotIn("describe", names)
        self.assertEqual(len(names), len(set(names)))
        for t in tools:
            self.assertEqual(t["inputSchema"]["type"], "object")
        r = self.c.request("tools/call", {"name": "state", "arguments": {}})["result"]
        self.assertFalse(r.get("isError"))
        self.assertEqual(r["structuredContent"]["title"], "Harbour")
        r = self.c.request("tools/call", {"name": "seek", "arguments": {"seconds": 30, "relative": True}})["result"]
        self.assertFalse(r.get("isError"), r)
        self.assertEqual(self.h.received[-1], {"cmd": "seek", "args": {"seconds": 30, "relative": True}})
        r = self.c.request("tools/call", {"name": "seek", "arguments": {"nonsense": 1}})["result"]
        self.assertTrue(r["isError"])
        self.assertIn("nonsense", r["content"][0]["text"])
        r = self.c.request("tools/call", {"name": "no_such_tool", "arguments": {}})
        self.assertEqual(r["error"]["code"], -32602)
        r = self.c.request("initialize", {"protocolVersion": "1999-01-01", "capabilities": {}})
        self.assertEqual(r["result"]["protocolVersion"], "2025-11-25")

    def test_modern_requests(self):
        r = self.c.request("server/discover", modern=True)["result"]
        self.assertEqual(r["resultType"], "complete")
        self.assertIn("2026-07-28", r["supportedVersions"])
        self.assertEqual(r["_meta"]["io.modelcontextprotocol/serverInfo"]["name"], "framecine-assistant")
        r = self.c.request("tools/list", modern=True)["result"]
        self.assertEqual(r["resultType"], "complete")
        r = self.c.request("tools/call", {"name": "card", "arguments": {"text": "Hello"}}, modern=True)
        self.assertFalse(r["result"].get("isError"), r)
        self.assertEqual(self.h.cards[-1]["text"], "Hello")
        r = self.c.request("tools/call", {"name": "answer_viewer", "arguments": {"text": "Looking", "working": True}},
                           modern=True)
        self.assertFalse(r["result"].get("isError"), r)
        self.assertEqual(self.h.cards[-1], {"text": "Looking", "title": "Conversation", "working": True})

    def test_tools_come_from_describe(self):
        tools = self.tools()
        described = [c["name"] for c in self.h.commands if c["name"] != "describe"]
        self.assertEqual(sorted(n for n in tools if n not in OWN), sorted(described))
        seek = tools["seek"]
        self.assertEqual(seek["inputSchema"], {"type": "object", "additionalProperties": False, "required": ["seconds"],
                                               "properties": {"seconds": {"type": "number"},
                                                              "relative": {"type": "boolean", "default": False}}})
        self.assertIn("Seeks to a time", seek["description"])
        self.assertEqual(seek["title"], "Seek")
        self.assertFalse(seek["annotations"]["readOnlyHint"])
        self.assertTrue(tools["state"]["annotations"]["readOnlyHint"])
        self.assertFalse(tools["state"]["annotations"]["destructiveHint"])
        self.assertTrue(tools["remove"]["annotations"]["destructiveHint"])
        self.assertTrue(tools["library_delete"]["annotations"]["destructiveHint"])
        self.assertFalse(tools["card"]["annotations"]["destructiveHint"])
        self.assertFalse(seek["description"].startswith("Off now"))
        # files is off: said first, with the switch to ask for.
        self.assertTrue(tools["library_delete"]["description"].startswith(
            "Off now: the viewer has not turned on \"Let the assistant change files\""), tools["library_delete"])

    def test_schemas_pass_through(self):
        vol = next(c for c in self.h.commands if c["name"] == "volume")
        vol["input_schema"] = {"type": "object", "additionalProperties": False, "properties": {
            "level": {"type": "number", "minimum": 0, "maximum": 1},
            "step": {"type": "number", "minimum": -1, "maximum": 1}}}
        try:
            self.assertEqual(self.tools()["volume"]["inputSchema"], vol["input_schema"])
        finally:
            del vol["input_schema"]

    def test_a_new_command_appears(self):
        self.c.request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}})
        self.assertNotIn("subtitle_size", self.tools(modern=False))
        self.h.commands.append({"name": "subtitle_size", "level": "control", "description": "The subtitles' size.",
                                "params": [{"name": "size", "type": "float", "required": True,
                                            "description": "1 is the default"}]})
        tools = self.tools(modern=False)
        self.assertEqual(tools["subtitle_size"]["inputSchema"]["properties"]["size"],
                         {"type": "number", "description": "1 is the default"})
        r = self.c.request("tools/call", {"name": "subtitle_size", "arguments": {"size": 1.4}})["result"]
        self.assertFalse(r.get("isError"), r)
        self.assertEqual(self.h.received[-1], {"cmd": "subtitle_size", "args": {"size": 1.4}})

    def test_a_new_command_called_before_the_list(self):
        self.h.commands.append({"name": "subtitle_size", "level": "control", "description": "The subtitles' size.",
                                "params": [{"name": "size", "type": "float", "required": True}]})
        r = self.c.request("tools/call", {"name": "subtitle_size", "arguments": {"size": 0.8}}, modern=True)["result"]
        self.assertFalse(r.get("isError"), r)
        self.assertEqual(self.h.received[-1], {"cmd": "subtitle_size", "args": {"size": 0.8}})

    def test_refusal_and_the_list_following_the_switches(self):
        self.c.request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}})
        self.c.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        self.assertFalse(self.tools(modern=False)["seek"]["description"].startswith("Off now"))
        time.sleep(0.8)                                    # the adapter follows the events once it gave the list
        self.h.set_allowed("control", False)
        self.c.wait(lambda m: m.get("method") == "notifications/tools/list_changed", 10)
        seek = self.tools(modern=False)["seek"]
        self.assertTrue(seek["description"].startswith(
            "Off now: the viewer has not turned on \"Let the assistant control playback\""), seek["description"])
        r = self.c.request("tools/call", {"name": "seek", "arguments": {"seconds": 10}})["result"]
        self.assertTrue(r["isError"])
        self.assertIn("Let the assistant control playback", r["content"][0]["text"])
        self.assertIn("System, Assistant", r["content"][0]["text"])
        self.h.set_allowed("control", True)
        self.c.wait(lambda m: m.get("method") == "notifications/tools/list_changed", 10)
        r = self.c.request("tools/call", {"name": "seek", "arguments": {"seconds": 10}})["result"]
        self.assertFalse(r.get("isError"), r)

    def test_old_describe(self):
        # params only, levels as text: /status says what is allowed.
        self.h.style = "old"
        self.h.allowed["room"] = False
        tools = self.tools()
        self.assertEqual(tools["seek"]["inputSchema"]["required"], ["seconds"])
        self.assertTrue(tools["add_text"]["description"].startswith(
            "Off now: the viewer has not turned on \"Let the assistant change the room\""))
        self.assertFalse(tools["seek"]["description"].startswith("Off now"))
        r = self.c.request("tools/call", {"name": "add_text", "arguments": {"name": "A", "text": "B"}},
                           modern=True)["result"]
        self.assertTrue(r["isError"])
        self.assertIn("Let the assistant change the room", r["content"][0]["text"])

    def test_link_file(self):
        # An agent on the headset: --url, and --config with its .assistant-link (a curl config). The token is on no
        # command line.
        self.c.close()
        link = os.path.join(tempfile.mkdtemp(), ".assistant-link")
        with open(link, "w", encoding="utf-8") as f:
            f.write("# The VR video player's API\nheader = \"Authorization: Bearer %s\"\n"
                    "pinnedpubkey = \"sha256//PIN\"\ninsecure\n" % TOKEN)
        self.c = Client(None, ["--url", self.url, "--config", link])
        self.assertNotIn(TOKEN, " ".join(self.c.argv))
        r = self.c.request("tools/call", {"name": "get_status", "arguments": {}}, modern=True)["result"]
        self.assertFalse(r.get("isError"), r)
        self.assertTrue(r["structuredContent"]["control_allowed"])
        self.assertIn("seek", self.tools())

    def test_no_service(self):
        # Nothing answers yet: the tools made here are listed, and a call says why it fails.
        self.c.close()
        self.c = Client("http://127.0.0.1:9")
        names = [t["name"] for t in self.c.request("tools/list", modern=True)["result"]["tools"]]
        self.assertEqual(sorted(names), sorted(OWN))
        r = self.c.request("tools/call", {"name": "get_status", "arguments": {}}, modern=True)["result"]
        self.assertTrue(r["isError"])
        self.assertIn("can't reach the headset", r["content"][0]["text"])

    def test_room_tools(self):
        tools = self.tools()
        for n in ("room_state", "room_apply", "add_text", "add_model", "remove"):
            self.assertIn(n, tools)
        # A base64 field may be a file here: its *_path twin is in the schema, and the field is no longer required.
        schema = tools["add_model"]["inputSchema"]
        self.assertIn("model_path", schema["properties"])
        self.assertEqual(schema["required"], ["name"])
        self.assertIn("model_path", tools["room_apply"]["description"])
        r = self.c.request("tools/call", {"name": "room_state", "arguments": {}}, modern=True)["result"]
        self.assertEqual(r["structuredContent"]["stock_parts"][0]["name"], "Walls")
        glb = os.path.join(tempfile.mkdtemp(), "thing.glb")
        with open(glb, "wb") as f:
            f.write(b"glTF-not-really")
        r = self.c.request("tools/call", {"name": "add_model", "arguments": {"name": "Thing", "model_path": glb}},
                           modern=True)["result"]
        self.assertFalse(r.get("isError"), r)
        sent = [m for m in self.h.received if m["cmd"] == "add_model"][-1]["args"]
        self.assertEqual(base64.b64decode(sent["model"]), b"glTF-not-really")
        self.assertNotIn("model_path", sent)
        r = self.c.request("tools/call", {"name": "room_apply", "arguments": {"room": {"parts": [
            {"name": "P", "type": "model", "model_path": glb}]}}}, modern=True)["result"]
        self.assertFalse(r.get("isError"), r)
        sent = [m for m in self.h.received if m["cmd"] == "room_apply"][-1]["args"]["room"]
        self.assertEqual(sent["schema"], 1)
        self.assertEqual(base64.b64decode(sent["parts"][0]["model"]), b"glTF-not-really")
        r = self.c.request("tools/call", {"name": "add_text", "arguments": {"name": "Sign", "text": "Now showing",
                           "size": 0.2, "text_options": {"weight": "bold"}}}, modern=True)["result"]
        self.assertFalse(r.get("isError"), r)
        sent = [m for m in self.h.received if m["cmd"] == "add_text"][-1]["args"]
        self.assertEqual(sent["text"], "Now showing")
        r = self.c.request("tools/call", {"name": "look_at_room", "arguments": {"from": "seat", "width": 320}},
                           modern=True)["result"]
        self.assertEqual(r["content"][0]["type"], "image", r)
        self.assertEqual(r["content"][0]["mimeType"], "image/png")
        self.assertTrue(base64.b64decode(r["content"][0]["data"]).startswith(b"\x89PNG"))
        asked = [m for m in self.h.received if m["cmd"] == "snapshot"][-1]["args"]
        self.assertEqual(asked, {"from": "seat", "width": "320"})
        r = self.c.request("tools/call", {"name": "look_at_room", "arguments": {"from": "sideways"}},
                           modern=True)["result"]
        self.assertTrue(r.get("isError"), r)
        r = self.c.request("tools/call", {"name": "look_at_room", "arguments": {"seconds": 2, "fps": 6}},
                           modern=True)["result"]
        self.assertEqual(r["content"][0]["type"], "image", r)
        asked = [m for m in self.h.received if m["cmd"] == "clip"][-1]["args"]
        self.assertEqual(asked, {"seconds": "2", "fps": "6"})
        r = self.c.request("tools/call", {"name": "look_at_room", "arguments": {"from": "seat", "seat": "Front row"}},
                           modern=True)["result"]
        self.assertEqual(r["content"][0]["type"], "image", r)
        asked = [m for m in self.h.received if m["cmd"] == "snapshot"][-1]["args"]
        self.assertEqual(asked, {"from": "seat", "seat": "Front row"})
        r = self.c.request("tools/call", {"name": "suggest_seat", "arguments": {"seat": "Front row", "why": "closer"}},
                           modern=True)["result"]
        self.assertFalse(r.get("isError"), r)
        sent = [m for m in self.h.received if m["cmd"] == "suggest_seat"][-1]["args"]
        self.assertEqual(sent, {"seat": "Front row", "why": "closer"})
        r = self.c.request("tools/call", {"name": "fetch", "arguments": {"url": "http://192.168.1.10:8000/a_360.mkv",
                           "mode": "360"}}, modern=True)["result"]
        self.assertFalse(r.get("isError"), r)
        sent = [m for m in self.h.received if m["cmd"] == "fetch"][-1]["args"]
        self.assertEqual(sent, {"url": "http://192.168.1.10:8000/a_360.mkv", "mode": "360"})
        r = self.c.request("tools/call", {"name": "add_place", "arguments": {"label": "TV",
                           "path": "smb://192.168.1.20/TV"}}, modern=True)["result"]
        self.assertFalse(r.get("isError"), r)
        sent = [m for m in self.h.received if m["cmd"] == "add_place"][-1]["args"]
        self.assertEqual(sent, {"label": "TV", "path": "smb://192.168.1.20/TV"})
        r = self.c.request("tools/call", {"name": "browse", "arguments": {"url": "https://example.org/watch"}},
                           modern=True)["result"]
        self.assertFalse(r.get("isError"), r)
        sent = [m for m in self.h.received if m["cmd"] == "browse"][-1]["args"]
        self.assertEqual(sent, {"url": "https://example.org/watch"})
        r = self.c.request("tools/call", {"name": "browser_page", "arguments": {}}, modern=True)["result"]
        self.assertFalse(r.get("isError"), r)
        self.assertTrue(any(m["cmd"] == "browser_page" for m in self.h.received))
        r = self.c.request("tools/call", {"name": "perf", "arguments": {}}, modern=True)["result"]
        self.assertFalse(r.get("isError"), r)
        self.assertIn("headroom_ms", r["content"][0]["text"])
        self.assertTrue(any(m["cmd"] == "perf" for m in self.h.received))

    def test_version_errors(self):
        r = self.c.request("tools/list")                   # no _meta and no initialize
        self.assertEqual(r["error"]["code"], -32602)
        r = self.c.request("tools/list", {"_meta": {"io.modelcontextprotocol/protocolVersion": "1900-01-01",
                                                    "io.modelcontextprotocol/clientCapabilities": {}}})
        self.assertEqual(r["error"]["code"], -32022)
        self.assertIn("2026-07-28", r["error"]["data"]["supported"])
        r = self.c.request("tools/list", {"_meta": {"io.modelcontextprotocol/protocolVersion": "2026-07-28"}})
        self.assertEqual(r["error"]["code"], -32602)       # clientCapabilities is required
        r = self.c.request("no/such", modern=True)
        self.assertEqual(r["error"]["code"], -32601)
        self.c.send({"jsonrpc": "2.0", "id": 99, "method": "ping"})
        self.assertEqual(self.c.wait(lambda m: m.get("id") == 99)["result"], {})

    def test_wait_for_viewer_message(self):
        def speak():
            time.sleep(1.0)
            self.app.add_message("what is that tower", {"file": "Harbour.mkv", "position": 615.0})
        threading.Thread(target=speak, daemon=True).start()
        r = self.c.request("tools/call", {"name": "wait_for_viewer_message", "arguments": {"timeout_seconds": 20}},
                           modern=True, timeout=30)["result"]
        self.assertFalse(r.get("isError"), r)
        self.assertIn("what is that tower", r["content"][0]["text"])
        last = r["structuredContent"]["since_id"]
        r = self.c.request("tools/call", {"name": "wait_for_viewer_message",
                                          "arguments": {"timeout_seconds": 1, "since_id": last}}, modern=True)
        self.assertIn("said nothing", r["result"]["content"][0]["text"])
        r = self.c.request("tools/call", {"name": "get_recent_viewer_messages", "arguments": {}}, modern=True)
        self.assertIn("what is that tower", r["result"]["content"][0]["text"])

    def test_cancel_wait(self):
        self.c.request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}})
        self.c.send({"jsonrpc": "2.0", "id": 500, "method": "tools/call",
                     "params": {"name": "wait_for_viewer_message", "arguments": {"timeout_seconds": 3}}})
        self.c.send({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": 500}})
        time.sleep(4)
        r = self.c.request("ping")
        self.assertEqual(r["result"], {})
        self.assertTrue(all(m.get("id") != 500 for m in list(self.c.q.queue)))

    def test_resources_and_subscriptions(self):
        self.c.request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}})
        res = self.c.request("resources/list")["result"]["resources"]
        self.assertIn("player://state", [x["uri"] for x in res])
        r = self.c.request("resources/read", {"uri": "player://state"})["result"]
        self.assertEqual(json.loads(r["contents"][0]["text"])["title"], "Harbour")
        self.assertEqual(self.c.request("resources/subscribe", {"uri": "player://state"})["result"], {})
        time.sleep(0.8)
        self.h.publish("state", {"title": "Harbour", "playing": False})
        n = self.c.wait(lambda m: m.get("method") == "notifications/resources/updated", 10)
        self.assertEqual(n["params"]["uri"], "player://state")

    def test_modern_subscription(self):
        sid = 77
        self.c.send({"jsonrpc": "2.0", "id": sid, "method": "subscriptions/listen",
                     "params": {"_meta": META, "notifications": {"resourceSubscriptions": ["player://viewer-messages",
                                                                                          "file:///nope"],
                                                                "toolsListChanged": True}}})
        ack = self.c.wait(lambda m: m.get("method") == "notifications/subscriptions/acknowledged")
        self.assertEqual(ack["params"]["_meta"]["io.modelcontextprotocol/subscriptionId"], sid)
        self.assertEqual(ack["params"]["notifications"], {"resourceSubscriptions": ["player://viewer-messages"],
                                                          "toolsListChanged": True})
        self.tools()
        time.sleep(0.8)
        self.app.add_message("louder please", {})
        n = self.c.wait(lambda m: m.get("method") == "notifications/resources/updated", 10)
        self.assertEqual(n["params"]["_meta"]["io.modelcontextprotocol/subscriptionId"], sid)
        self.assertEqual(n["params"]["uri"], "player://viewer-messages")
        self.h.set_allowed("room", False)
        n = self.c.wait(lambda m: m.get("method") == "notifications/tools/list_changed", 10)
        self.assertEqual(n["params"]["_meta"]["io.modelcontextprotocol/subscriptionId"], sid)
        self.assertTrue(self.tools()["add_text"]["description"].startswith("Off now"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
