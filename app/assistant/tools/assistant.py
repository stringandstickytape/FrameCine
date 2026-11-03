#!/usr/bin/env python3
"""A command line and a small client for the VR Video Player's assistant service on the headset (docs/assistant.md).
Python 3.8+, standard library only. The headset serves this file at https://<headset>:47801/tools/assistant.py.

    python assistant.py --url https://192.168.1.50:47801 guide              # the guide (no token needed)
    python assistant.py --url URL pair-start "Claude Code"                  # the headset shows a code
    python assistant.py --url URL pair PAIR_ID 123456 --save vrvp.json      # keeps url, token and pin in vrvp.json
    python assistant.py --config vrvp.json status                           # then everything with the token
    python assistant.py --config vrvp.json state
    python assistant.py --config vrvp.json send seek seconds=-30 relative=true
    python assistant.py --config vrvp.json card "Back in five minutes" --title Note
    python assistant.py --config vrvp.json answer "It is the lighthouse keeper."
    python assistant.py --config vrvp.json wait -t 600                      # the next thing the viewer says
    python assistant.py --config vrvp.json events -t viewer_message         # follow the event stream
    python assistant.py --config vrvp.json voice 7 -o said.wav              # a message's audio
    python assistant.py --config vrvp.json forget                           # this assistant's token stops working

Instead of the arguments: VRVP_ASSISTANT_URL, VRVP_ASSISTANT_TOKEN, VRVP_ASSISTANT_PIN, or VRVP_ASSISTANT_CONFIG (a
JSON file {url, token, pin}, or a curl config with the token and the pin, as an agent's .assistant-link on the headset). The pin ("sha256//BASE64", the headset's public key, as curl --pinnedpubkey takes it;
or the certificate's SHA-256 in hex) is checked on every connection once it is known.

As a library (mcp_server.py uses it):
    api = Api(url, token, pin)
    api.get("/state")                                  # {"ok": true, "result": {...}}
    api.post("/command", {"cmd": "seek", "args": {"seconds": -30, "relative": True}})
    for event in api.events(types=["viewer_message"]): ...
"""

import argparse
import base64
import hashlib
import http.client
import json
import os
import ssl
import sys
import urllib.parse

DEFAULT_PORT = 47801


class PinError(Exception):
    pass


def _tlv(data, pos):
    """A DER element at pos: (tag, content start, content end)."""
    tag = data[pos]
    length = data[pos + 1]
    start = pos + 2
    if length & 0x80:
        n = length & 0x7F
        length = int.from_bytes(data[start:start + n], "big")
        start += n
    return tag, start, start + length


def spki_pin(cert_der):
    """curl's --pinnedpubkey form of a certificate: sha256// and the base64 SHA-256 of its SubjectPublicKeyInfo."""
    _, start, end = _tlv(cert_der, 0)            # Certificate
    _, start, end = _tlv(cert_der, start)        # tbsCertificate
    fields = []
    pos = start
    while pos < end:
        tag, _, nxt = _tlv(cert_der, pos)
        fields.append((tag, pos, nxt))
        pos = nxt
    if fields and fields[0][0] == 0xA0:          # [0] version
        fields = fields[1:]
    _, a, b = fields[5]                          # serial, signature, issuer, validity, subject, subjectPublicKeyInfo
    return "sha256//" + base64.b64encode(hashlib.sha256(cert_der[a:b]).digest()).decode()


def load_config(path):
    """{url, token, pin} from a JSON file (pair --save), or from a curl config such as an agent's .assistant-link on
    the headset (its Authorization header and pinnedpubkey; it has no url: give --url)."""
    if not path:
        return {}
    try:
        with open(os.path.expanduser(path), encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return {}
    try:
        v = json.loads(text)
        return v if isinstance(v, dict) else {}
    except ValueError:
        return curl_config(text)


def curl_config(text):
    """The token and the pin of a curl config (header = "Authorization: Bearer ...", pinnedpubkey = "...")."""
    out = {}
    for line in text.splitlines():
        k, sep, v = line.strip().partition("=")
        if not sep or k.strip().startswith("#"):
            continue
        k = k.strip().lstrip("-")
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] == '"':
            v = v[1:-1]
        if k == "header" and v.lower().startswith("authorization: bearer "):
            out["token"] = v[len("authorization: bearer "):].strip()
        elif k == "pinnedpubkey":
            out["pin"] = v
    return out


def save_config(path, obj):
    path = os.path.expanduser(path)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=1)
    if os.name != "nt":
        os.chmod(path, 0o600)


class Api:
    def __init__(self, url=None, token=None, pin=None, timeout=30.0, config=None):
        cfg = load_config(config or os.environ.get("VRVP_ASSISTANT_CONFIG"))
        self.url = (url or os.environ.get("VRVP_ASSISTANT_URL") or cfg.get("url") or "").rstrip("/")
        self.token = token if token is not None else (os.environ.get("VRVP_ASSISTANT_TOKEN") or cfg.get("token")
                                                       or "")
        self.pin = pin if pin is not None else (os.environ.get("VRVP_ASSISTANT_PIN") or cfg.get("pin")
                                                 or cfg.get("cert_sha256") or "")
        self.timeout = timeout
        if self.url and "://" not in self.url:
            self.url = "https://" + self.url
        u = urllib.parse.urlsplit(self.url)
        self.host = u.hostname or ""
        self.port = u.port or DEFAULT_PORT
        self.plain = u.scheme == "http"        # only test stand-ins speak plain HTTP; the headset is HTTPS
        self.ctx = ssl.create_default_context()
        self.ctx.check_hostname = False
        self.ctx.verify_mode = ssl.CERT_NONE   # self-signed: the pin is the check

    def _connect(self, timeout):
        if not self.host:
            raise OSError("no headset address: give --url https://<headset>:47801 (or VRVP_ASSISTANT_URL)")
        if self.plain:
            conn = http.client.HTTPConnection(self.host, self.port, timeout=timeout)
            conn.connect()
            return conn
        conn = http.client.HTTPSConnection(self.host, self.port, context=self.ctx, timeout=timeout)
        conn.connect()
        if self.pin:
            der = conn.sock.getpeercert(True)
            pin = self.pin.strip()
            ok = spki_pin(der) == pin if pin.startswith("sha256//") else \
                hashlib.sha256(der).hexdigest() == pin.lower()
            if not ok:
                conn.close()
                raise PinError("the headset's certificate does not match the pin: this is not the paired headset")
        return conn

    def _headers(self, extra=None):
        h = {"Accept": "application/json"}
        if self.token:
            h["Authorization"] = "Bearer " + self.token
        h.update(extra or {})
        return h

    def raw(self, method, path, body=None, timeout=None, headers=None):
        """(status, bytes) of one request."""
        conn = self._connect(timeout or self.timeout)
        try:
            data = None
            h = self._headers(headers)
            if body is not None:
                data = json.dumps(body).encode()
                h["Content-Type"] = "application/json"
            conn.request(method, path, data, h)
            r = conn.getresponse()
            return r.status, r.read()
        finally:
            conn.close()

    def _request(self, method, path, body=None, timeout=None):
        try:
            status, raw = self.raw(method, path, body, timeout)
        except PinError as e:
            return {"ok": False, "error": str(e), "pin_mismatch": True}
        except (OSError, http.client.HTTPException) as e:
            return {"ok": False, "error": "can't reach the headset at %s (%s): is the assistant on (System, "
                                          "Assistant)?" % (self.url, e), "no_server": True}
        try:
            out = json.loads(raw.decode("utf-8"))
        except ValueError:
            out = {"ok": False, "error": raw.decode("utf-8", "replace")[:500]}
        if isinstance(out, dict) and status >= 400:
            out.setdefault("ok", False)
            out.setdefault("status", status)
        return out

    def get(self, path, query=None, timeout=None):
        q = {k: v for k, v in (query or {}).items() if v is not None}
        return self._request("GET", path + ("?" + urllib.parse.urlencode(q) if q else ""), timeout=timeout)

    def post(self, path, body=None, timeout=None):
        return self._request("POST", path, body if body is not None else {}, timeout=timeout)

    def text(self, path):
        status, raw = self.raw("GET", path)
        return raw.decode("utf-8")

    def events(self, types=None, last_id=None, timeout=None):
        """Yields {"id", "event", "data"} from GET /events until the headset closes it. Raises OSError when it can't
        connect."""
        q = {"types": ",".join(types)} if types else {}
        h = {"Accept": "text/event-stream"}
        if last_id is not None:
            h["Last-Event-ID"] = str(last_id)
        conn = self._connect(timeout)
        try:
            conn.request("GET", "/events" + ("?" + urllib.parse.urlencode(q) if q else ""), None, self._headers(h))
            r = conn.getresponse()
            if r.status != 200:
                raise OSError("the headset refused the event stream (%d): %s" % (r.status,
                                                                                 r.read().decode("utf-8", "replace")))
            ev = {}
            while True:
                raw = r.fp.readline()
                if not raw:
                    return
                line = raw.decode("utf-8").rstrip("\r\n")
                if line == "":
                    if "data" in ev:
                        try:
                            ev["data"] = json.loads(ev["data"])
                        except ValueError:
                            pass
                        yield ev
                    ev = {}
                elif line.startswith(":"):
                    continue
                else:
                    k, _, v = line.partition(":")
                    v = v[1:] if v.startswith(" ") else v
                    if k == "data":
                        ev["data"] = ev["data"] + "\n" + v if "data" in ev else v
                    elif k in ("id", "event"):
                        ev[k] = int(v) if k == "id" and v.isdigit() else v
        finally:
            conn.close()


def parse_value(s):
    try:
        return json.loads(s)
    except ValueError:
        return s


def show(r):
    print(json.dumps(r, indent=1, ensure_ascii=False))
    return 0 if r.get("ok") else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default=None, help="https://<headset>:47801")
    ap.add_argument("--token", default=None)
    ap.add_argument("--pin", default=None, help="sha256//BASE64 (or the certificate's SHA-256 in hex)")
    ap.add_argument("--config", default=None, help="a JSON file {url, token, pin} (pair --save writes one), or a curl config "
                    "with the token and the pin")
    sub = ap.add_subparsers(dest="what", required=True)
    sub.add_parser("guide")
    p = sub.add_parser("pair-start")
    p.add_argument("client", help="your name, as the viewer will see it")
    p = sub.add_parser("pair")
    p.add_argument("pair_id")
    p.add_argument("code")
    p.add_argument("--save", default=None, help="write url, token and pin to this file (owner-only)")
    sub.add_parser("status")
    sub.add_parser("state")
    sub.add_parser("describe")
    p = sub.add_parser("send")
    p.add_argument("cmd")
    p.add_argument("args", nargs="*", help="name=value (values are JSON when they parse: 5, true, \"text\")")
    p = sub.add_parser("card")
    p.add_argument("text")
    p.add_argument("--title", default="")
    p.add_argument("--seconds", type=float, default=None)
    p = sub.add_parser("answer")
    p.add_argument("text")
    p.add_argument("--heard", default=None, help="what you transcribed of a message without text")
    p.add_argument("--message", type=int, default=None, help="that message's id")
    p = sub.add_parser("events")
    p.add_argument("-t", "--types", default="", help="comma-separated event names")
    p = sub.add_parser("wait")
    p.add_argument("-t", "--timeout", type=float, default=600.0)
    p.add_argument("--since", type=int, default=None)
    p = sub.add_parser("messages")
    p.add_argument("--since", type=int, default=0)
    p = sub.add_parser("voice")
    p.add_argument("id", type=int)
    p.add_argument("-o", "--out", default=None)
    sub.add_parser("forget")
    a = ap.parse_args(argv)
    api = Api(a.url, a.token, a.pin, config=a.config)

    try:
        if a.what == "guide":
            print(api.text("/"))
            return 0
        if a.what == "pair-start":
            return show(api.post("/pair/start", {"client": a.client}))
        if a.what == "pair":
            r = api.post("/pair", {"pair_id": a.pair_id, "code": a.code})
            if r.get("ok") and a.save:
                res = r["result"]
                save_config(a.save, {"url": api.url, "token": res["token"], "pin": res["pin"],
                                     "cert_sha256": res["cert_sha256"], "client_id": res.get("client_id")})
                print("saved to %s (keep it private)" % a.save, file=sys.stderr)
            return show(r)
        if a.what == "status":
            return show(api.get("/status"))
        if a.what == "state":
            return show(api.get("/state"))
        if a.what == "describe":
            return show(api.get("/describe"))
        if a.what == "send":
            args = {}
            for kv in a.args:
                k, sep, v = kv.partition("=")
                if not sep:
                    print("arguments are name=value: %s" % kv, file=sys.stderr)
                    return 2
                args[k] = parse_value(v)
            return show(api.post("/command", {"cmd": a.cmd, "args": args}, timeout=130))
        if a.what == "card":
            body = {"text": a.text, "title": a.title}
            if a.seconds is not None:
                body["seconds"] = a.seconds
            return show(api.post("/card", body))
        if a.what == "answer":
            body = {"text": a.text}
            if a.heard is not None and a.message is not None:
                body.update(heard=a.heard, message_id=a.message)
            return show(api.post("/answer", body))
        if a.what == "forget":
            return show(api.post("/forget", {}))
        if a.what == "messages":
            return show(api.get("/messages", {"since": a.since}))
        if a.what == "voice":
            status, raw = api.raw("GET", "/voice/%d.wav" % a.id)
            if status != 200:
                print(raw.decode("utf-8", "replace"), file=sys.stderr)
                return 1
            with open(a.out or "voice_%d.wav" % a.id, "wb") as f:
                f.write(raw)
            return 0
        if a.what == "wait":
            r = api.get("/messages/wait", {"timeout": a.timeout, "since": a.since}, timeout=a.timeout + 20)
            if r.get("ok") and r.get("result"):
                for m in r["result"]:
                    print("[message %d]\n%s" % (m["id"], m.get("block", "")))
                return 0
            if r.get("ok"):
                print("(nothing said in %.0f s)" % a.timeout)
                return 1
            return show(r)
        if a.what == "events":
            types = [t for t in a.types.split(",") if t]
            try:
                for ev in api.events(types=types or None):
                    print(json.dumps(ev, ensure_ascii=False), flush=True)
            except KeyboardInterrupt:
                return 0
    except PinError as e:
        print(str(e), file=sys.stderr)
        return 1
    except (OSError, http.client.HTTPException) as e:
        print("can't reach the headset at %s: %s" % (api.url, e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
