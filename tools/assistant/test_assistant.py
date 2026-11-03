#!/usr/bin/env python3
"""End to end: the app's assistant service in the headless engine on 127.0.0.1 (app/tests/assistant_host.gd), and
this test as a fresh assistant that knows only the address. It reads the guide, pairs with the code "the headset"
shows (the host writes it to a file, as the viewer would read it out), checks the pin with Python's ssl and with
curl, follows the event stream while "the viewer" speaks, waits for a message, answers on the card, uses
assistant.py and the MCP adapter served by the headset, and checks the engine's log never holds the token or the code.
Linux or WSL (it runs the Linux engine). Standard library only.

    python3 tools/assistant/test_assistant.py
    GODOT=/path/to/godot python3 tools/assistant/test_assistant.py
"""

import hashlib
import http.client
import json
import os
import shutil
import socket
import ssl
import subprocess
import re
import sys
import tempfile
import threading
import time
import unittest
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
APP = os.path.join(REPO, "app")
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(APP, "assistant", "tools"))

from assistant import Api, spki_pin  # noqa: E402

GODOT = os.environ.get("GODOT") or os.path.expanduser("~/src/godot-player/bin/godot.linuxbsd.template_debug.x86_64")
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def request(port, method, path, body=None, token=None, headers=None, timeout=30):
    """(status, text, peer certificate DER) of one HTTPS request; body: a dict sent as a form."""
    c = http.client.HTTPSConnection("127.0.0.1", port, context=CTX, timeout=timeout)
    c.connect()
    der = c.sock.getpeercert(True)
    h = dict(headers or {})
    data = None
    if body is not None:
        data = urllib.parse.urlencode(body)
        h["Content-Type"] = "application/x-www-form-urlencoded"
    if token:
        h["Authorization"] = "Bearer " + token
    c.request(method, path, data, h)
    r = c.getresponse()
    text = r.read().decode("utf-8", "replace")
    c.close()
    return r.status, text, der


@unittest.skipUnless(os.path.exists(GODOT), "no engine at %s (set GODOT)" % GODOT)
class EndToEnd(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp()
        cls.port = free_port()
        cls.url = "https://127.0.0.1:%d" % cls.port
        cls.log = open(os.path.join(cls.dir, "engine.log"), "w+", encoding="utf-8")
        cls.proc = subprocess.Popen([GODOT, "--headless", "--xr-mode", "off", "--path", APP, "--script",
                                     "res://tests/assistant_host.gd", "--", "--assistant-port=%d" % cls.port,
                                     "--assistant-dir=%s" % cls.dir], stdout=cls.log, stderr=subprocess.STDOUT)
        if not cls.wait_state(lambda s: s.get("listening"), 120):
            cls.tearDownClass()
            raise RuntimeError("the app did not start listening")

    @classmethod
    def tearDownClass(cls):
        cls.control("quit")
        try:
            cls.proc.wait(15)
        except subprocess.TimeoutExpired:
            cls.proc.kill()
        cls.log.close()

    @classmethod
    def state(cls):
        try:
            with open(os.path.join(cls.dir, "state.json"), encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return {}

    @classmethod
    def wait_state(cls, cond, timeout=15):
        end = time.time() + timeout
        while time.time() < end:
            s = cls.state()
            if s and cond(s):
                return s
            if cls.proc.poll() is not None:
                return None
            time.sleep(0.1)
        return None

    @classmethod
    def control(cls, line):
        path = os.path.join(cls.dir, "control.txt")
        end = time.time() + 5
        while os.path.exists(path) and time.time() < end:
            time.sleep(0.05)
        with open(path + ".tmp", "w", encoding="utf-8") as f:
            f.write(line + "\n")
        os.replace(path + ".tmp", path)

    def test_fresh_assistant(self):
        # 1. The guide, with nothing but the address.
        status, guide, der = request(self.port, "GET", "/")
        self.assertEqual(status, 200)
        self.assertIn("pairing is open", guide)
        self.assertIn("/pair/start", guide)
        self.assertIn("Listening to the viewer", guide)
        status, text, _ = request(self.port, "GET", "/status")
        self.assertEqual(status, 401)

        # 2. Pair: start, the viewer reads out the code, send it.
        status, text, _ = request(self.port, "POST", "/pair/start", {"client": "Fresh Agent"})
        self.assertEqual(status, 200, text)
        pair_id = json.loads(text)["result"]["pair_id"]
        s = self.wait_state(lambda s: s.get("code"))
        self.assertIsNotNone(s)
        self.assertEqual(s["client"], "Fresh Agent")
        self.assertEqual(s["card_title"], "Pairing")
        self.assertIn(s["code"][:3] + " " + s["code"][3:], s["card_text"])
        code = s["code"]
        status, text, der = request(self.port, "POST", "/pair", {"pair_id": pair_id, "code": code})
        self.assertEqual(status, 200, text)
        res = json.loads(text)["result"]
        token, pin, cert = res["token"], res["pin"], res["cert_sha256"]
        self.assertEqual(spki_pin(der), pin)
        self.assertEqual(hashlib.sha256(der).hexdigest(), cert)
        self.assertIsNotNone(self.wait_state(lambda s: not s.get("code")))

        # 3. The pinned client (assistant.py, as served by the headset).
        status, served, _ = request(self.port, "GET", "/tools/assistant.py")
        self.assertEqual(status, 200)
        with open(os.path.join(APP, "assistant", "tools", "assistant.py"), encoding="utf-8") as f:
            self.assertEqual(served, f.read())
        api = Api(self.url, token, pin)
        r = api.get("/status")
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["result"]["you"]["name"], "Fresh Agent")
        self.assertTrue(Api(self.url, token, cert).get("/state")["ok"])
        bad = Api(self.url, token, "sha256//" + "A" * 43 + "=")
        self.assertTrue(bad.get("/status").get("pin_mismatch"))
        self.assertEqual(Api(self.url, "00" * 32, pin).get("/status").get("status"), 401)

        # 4. curl, as the guide shows it.
        curl = shutil.which("curl")
        if curl:
            base = [curl, "-s", "-k", "--pinnedpubkey", pin, "-H", "Authorization: Bearer " + token]
            out = subprocess.run(base + [self.url + "/status"], capture_output=True, text=True, timeout=30)
            self.assertEqual(out.returncode, 0, out.stderr)
            self.assertTrue(json.loads(out.stdout)["ok"])
            out = subprocess.run([curl, "-s", "-k", "--pinnedpubkey", "sha256//" + "A" * 43 + "=", self.url + "/"],
                                 capture_output=True, text=True, timeout=30)
            self.assertEqual(out.returncode, 90)        # CURLE_SSL_PINNEDPUBKEYNOTMATCH
            out = subprocess.run(base + [self.url + "/command", "-d", "cmd=play"], capture_output=True, text=True,
                                 timeout=30)
            r = json.loads(out.stdout)
            self.assertTrue(r.get("refused"), r)
            out = subprocess.run(base + [self.url + "/card", "--data-urlencode", "text=Hello from curl", "-d",
                                         "title=Note"], capture_output=True, text=True, timeout=30)
            self.assertTrue(json.loads(out.stdout)["ok"], out.stdout)
            self.assertIsNotNone(self.wait_state(lambda s: s["card_text"] == "Hello from curl"))

        # 5. Listening: the event stream in the background, and a blocking wait.
        got = []

        def follow():
            try:
                for ev in Api(self.url, token, pin).events(types=["viewer_message"]):
                    if ev.get("event") == "viewer_message":   # status always comes first
                        got.append(ev)
                        return
            except OSError:
                pass

        t = threading.Thread(target=follow, daemon=True)
        t.start()
        waited = {}

        def wait():
            waited.update(Api(self.url, token, pin).get("/messages/wait", {"timeout": 30}, timeout=40))

        w = threading.Thread(target=wait, daemon=True)
        w.start()
        self.assertIsNotNone(self.wait_state(lambda s: s.get("connected")))
        time.sleep(1.0)
        self.control("speak")
        t.join(20)
        w.join(20)
        self.assertEqual(len(got), 1)
        m = got[0]["data"]
        self.assertEqual(got[0]["event"], "viewer_message")
        self.assertEqual(m["text"], "what is this")
        self.assertNotIn("audio", m)  # the headset transcribes; audio is never sent instead
        self.assertIn("flat_sbs", m["block"])
        self.assertEqual(waited["result"][0]["id"], m["id"])
        r = api.post("/answer", {"text": "It is a test pattern.", "message_id": m["id"]})
        self.assertTrue(r["ok"], r)
        s = self.wait_state(lambda s: "Assistant: It is a test pattern." in s["card_text"])
        self.assertIsNotNone(s)
        self.assertIn("You: what is this", s["card_text"])

        # 6. Control once the viewer allows it.
        self.control("allow_control 1")
        self.assertIsNotNone(self.wait_state(lambda s: s.get("playing")))
        time.sleep(0.5)
        r = api.post("/command", {"cmd": "pause"})
        self.assertTrue(r["ok"], r)
        self.assertIsNotNone(self.wait_state(lambda s: not s["playing"]))

        # 6b. /list with a URL-encoded smb:// path answers as list_dir through /command does (a fresh assistant found
        # /list mangling such paths on the headset).
        smb = "smb://192.168.1.20/Movies/Some Folder"
        # Lowercase hex, as some clients send it (the engine's own decoder drops the "%" of those).
        q = re.sub(r"%[0-9A-F]{2}", lambda m: m.group(0).lower(), urllib.parse.quote(smb, safe=""))
        st1, t1, _ = request(self.port, "GET", "/list?path=" + q, token=token)
        st2, t2, _ = request(self.port, "POST", "/command", {"cmd": "list_dir", "path": smb}, token=token)
        self.assertEqual((st1, t1), (st2, t2))

        # 7. The MCP adapter, fetched from the headset into a folder of its own.
        tools = tempfile.mkdtemp()
        for name in ("assistant.py", "mcp_server.py"):
            status, text, _ = request(self.port, "GET", "/tools/" + name)
            with open(os.path.join(tools, name), "w", encoding="utf-8") as f:
                f.write(text)
        # Configured as an agent on the headset is: the token and the pin in a curl config (.assistant-link), only
        # its path on the command line.
        link = os.path.join(tools, ".assistant-link")
        with open(link, "w", encoding="utf-8") as f:
            f.write("header = \"Authorization: Bearer %s\"\npinnedpubkey = \"%s\"\ninsecure\n" % (token, pin))
        p = subprocess.Popen([sys.executable, os.path.join(tools, "mcp_server.py"), "--url", self.url, "--config",
                              link], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
        try:
            def rpc(i, method, params):
                p.stdin.write((json.dumps({"jsonrpc": "2.0", "id": i, "method": method, "params": params}) + "\n")
                              .encode())
                p.stdin.flush()
                return json.loads(p.stdout.readline())
            rpc(1, "initialize", {"protocolVersion": "2025-11-25", "capabilities": {}})
            r = rpc(2, "tools/call", {"name": "get_status", "arguments": {}})
            self.assertFalse(r["result"].get("isError"), r)
            self.assertTrue(r["result"]["structuredContent"]["control_allowed"])
            r = rpc(3, "tools/call", {"name": "answer_viewer", "arguments": {"text": "From MCP."}})
            self.assertFalse(r["result"].get("isError"), r)
            self.assertIsNotNone(self.wait_state(lambda s: "Assistant: From MCP." in s["card_text"]))
            # The tools are the service's own commands, from its /describe.
            r = rpc(4, "tools/call", {"name": "state", "arguments": {}})
            self.assertFalse(r["result"].get("isError"), r)
            r = rpc(5, "tools/list", {})
            tools = {t["name"]: t for t in r["result"]["tools"]}
            for name in ("state", "seek", "card", "room_state", "wait_for_viewer_message", "look_at_room"):
                self.assertIn(name, tools)
            self.assertEqual(tools["seek"]["inputSchema"]["required"], ["seconds"])
            self.assertTrue(tools["state"]["annotations"]["readOnlyHint"])
        finally:
            p.stdin.close()
            p.wait(10)
            p.stdout.close()
            p.stderr.close()

        # 8. Forget: the token stops working.
        self.assertTrue(api.post("/forget")["ok"])
        self.assertEqual(api.get("/status").get("status"), 401)

        # 9. The engine's log never holds the token or the code.
        self.log.flush()
        with open(self.log.name, encoding="utf-8", errors="replace") as f:
            log = f.read()
        self.assertIn("asks to pair", log)
        self.assertNotIn(token, log)
        self.assertNotIn(code, log)


if __name__ == "__main__":
    unittest.main(verbosity=2)
