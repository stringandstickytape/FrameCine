#!/usr/bin/env python3
"""A desktop peer for the watch party (docs/watch-party.md), to test the app without a second headset.
Python 3.8+, standard library only. Speaks the same UDP protocol as app/scripts/party/watch_party.gd.

    python tools/party_peer.py host [--port 47892] [--file NAME] [--rate 1.0] [--script "pause@6,seek:120@8,play@10"]
        beacons on the LAN, takes joins, sends its clock (a simulated timeline that runs at --rate while it reports
        speed 1.0: a drifting clock for the guest to follow), applies controls from guests, sends moving hands
    python tools/party_peer.py join 127.0.0.1[:47890] [--script "pause@3,seek:300@5,play@7"]
        joins a host, measures the clock offset, follows its clock, sends controls and moving hands
Both print one JSON line per second ({t, position, ...}) and a summary at the end (--seconds, default 20).
"""

import argparse
import json
import math
import os
import random
import select
import socket
import sys
import time

PORT = 47890
VERSION = 1


def now():
    return time.monotonic()


class Peer:
    def __init__(self, args):
        self.args = args
        self.id = "%08x" % random.getrandbits(31)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.sock.bind(("0.0.0.0", args.port if args.role == "host" else 0))
        self.script = []
        for item in (args.script or "").split(","):
            item = item.strip()
            if item:
                action, at = item.split("@")
                self.script.append((float(at), action))
        self.start = now()
        self.log = []

    def send(self, addr, msg):
        msg = dict(msg, v=VERSION, id=self.id)
        self.sock.sendto(json.dumps(msg).encode(), addr)

    def recv(self, timeout):
        r, _, _ = select.select([self.sock], [], [], timeout)
        if not r:
            return None, None
        try:
            data, addr = self.sock.recvfrom(65536)
        except OSError:  # Windows: an earlier packet's port unreachable
            return None, None
        try:
            msg = json.loads(data.decode())
        except ValueError:
            return None, None
        if msg.get("v") != VERSION or msg.get("id") == self.id:
            return None, None
        return msg, addr

    def hands(self):
        t = now() - self.start
        a = t * 2.0
        left = [round(-0.25 + 0.1 * math.cos(a), 3), round(1.1 + 0.1 * math.sin(a), 3), -0.35, 0, 0, 0, 1]
        right = [round(0.25 + 0.1 * math.cos(-a), 3), round(1.1 + 0.1 * math.sin(-a), 3), -0.35, 0, 0, 0, 1]
        head = [0, 1.6, 0, 0, round(math.sin(t * 0.5) * 0.2, 4), 0, round(math.cos(t * 0.5) * 0.2 + 0.8, 4)]
        n = math.sqrt(head[4] ** 2 + head[6] ** 2)
        head[4], head[6] = round(head[4] / n, 4), round(head[6] / n, 4)
        return head, left, right


class Host(Peer):
    def run(self):
        a = self.args
        guests = {}
        pos, playing, anchor = 0.0, True, now()   # the timeline: pos at anchor, running at rate while playing
        file = {"name": a.file.rstrip("/").split("/")[-1], "path": a.file, "duration": 600.0}
        t_beacon = t_clock = t_pose = t_print = 0.0
        controls = []

        def position():
            return pos + ((now() - anchor) * a.rate if playing else 0.0)

        def clock_msg():
            return {"t": "clock", "ht": now(), "pos": position(), "playing": playing, "file": file, "speed": 1.0}

        end = self.start + a.seconds
        while now() < end:
            t = now()
            if t - t_beacon >= 1.0:
                t_beacon = t
                self.send(("255.255.255.255", PORT), {"t": "beacon", "name": "desktop peer", "port": a.port,
                                                     "file": file, "peers": len(guests) + 1, "pin": False})
            while self.script and t - self.start >= self.script[0][0]:
                _, action = self.script.pop(0)
                p0 = position()
                if action == "pause":
                    pos, playing, anchor = p0, False, t
                elif action == "play":
                    pos, playing, anchor = p0, True, t
                elif action.startswith("seek:"):
                    pos, anchor = float(action[5:]), t
                print(json.dumps({"t": round(t - self.start, 2), "script": action}), flush=True)
                for g in guests.values():
                    self.send(g["addr"], clock_msg())
            if t - t_clock >= 0.25:
                t_clock = t
                for g in guests.values():
                    self.send(g["addr"], clock_msg())
            if t - t_pose >= 0.05:
                t_pose = t
                head, left, right = self.hands()
                for g in guests.values():
                    self.send(g["addr"], {"t": "pose", "seat": 0, "head": head, "l": left, "r": right})
            if t - t_print >= 1.0:
                t_print = t
                print(json.dumps({"t": round(t - self.start, 2), "position": round(position(), 3),
                                  "playing": playing, "guests": len(guests)}), flush=True)
            msg, addr = self.recv(0.01)
            if not msg:
                continue
            kind = msg.get("t")
            if kind == "join":
                guests[msg["id"]] = {"addr": addr, "name": msg.get("name"), "seat": len(guests) + 1}
                self.send(addr, {"t": "welcome", "seat": guests[msg["id"]]["seat"], "file": file,
                                 "peers": [{"id": self.id, "name": "desktop peer", "seat": 0}] +
                                          [{"id": k, "name": g["name"], "seat": g["seat"]} for k, g in guests.items()]})
                self.send(addr, clock_msg())
                print(json.dumps({"t": round(t - self.start, 2), "joined": msg.get("name"), "from": addr[0]}), flush=True)
            elif kind == "ping":
                self.send(addr, {"t": "pong", "seq": msg["seq"], "t0": msg["t0"], "th": now()})
            elif kind == "control":
                controls.append(msg.get("action"))
                p0 = position()
                if msg.get("action") == "pause":
                    pos, playing, anchor = p0, False, now()
                elif msg.get("action") == "play":
                    pos, playing, anchor = p0, True, now()
                elif msg.get("action") == "seek":
                    pos, anchor = float(msg.get("pos", 0)), now()
                print(json.dumps({"t": round(t - self.start, 2), "control": msg.get("action"), "pos": msg.get("pos")}),
                      flush=True)
                for g in guests.values():
                    self.send(g["addr"], clock_msg())
            elif kind == "bye":
                guests.pop(msg["id"], None)
        for g in guests.values():
            self.send(g["addr"], {"t": "bye", "reason": "peer done"})
        print(json.dumps({"summary": {"guests": len(guests), "controls": controls, "position": round(position(), 3)}}),
              flush=True)


class Guest(Peer):
    def run(self):
        a = self.args
        host, _, hp = a.host.partition(":")
        haddr = (host, int(hp) if hp else PORT)
        joined, seq, pings, offsets, clock = False, 0, {}, [], None
        t_join = t_ping = t_pose = t_print = 0.0
        sent = []
        end = self.start + a.seconds

        def host_pos():
            if not clock or not offsets:
                return None
            best = min(offsets[-8:])
            p = clock["pos"]
            if clock["playing"]:
                p += (now() + best[1] - clock["ht"]) * clock.get("speed", 1.0)
            return p

        while now() < end:
            t = now()
            if not joined and t - t_join >= 1.0:
                t_join = t
                self.send(haddr, {"t": "join", "name": "desktop peer", "pin": a.pin})
            if joined and t - t_ping >= 1.0:
                t_ping = t
                seq += 1
                pings[seq] = t
                self.send(haddr, {"t": "ping", "seq": seq, "t0": t})
            if joined:
                while self.script and t - self.start >= self.script[0][0]:
                    _, action = self.script.pop(0)
                    msg = {"t": "control", "action": action.split(":")[0]}
                    if action.startswith("seek:"):
                        msg["pos"] = float(action[5:])
                    self.send(haddr, msg)
                    sent.append(action)
                    print(json.dumps({"t": round(t - self.start, 2), "sent": action}), flush=True)
            if joined and t - t_pose >= 0.05:
                t_pose = t
                head, left, right = self.hands()
                self.send(haddr, {"t": "pose", "seat": 1, "head": head, "l": left, "r": right})
            if joined and t - t_print >= 1.0:
                t_print = t
                hp_ = host_pos()
                best = min(offsets[-8:]) if offsets else None
                print(json.dumps({"t": round(t - self.start, 2), "host_position": None if hp_ is None else round(hp_, 3),
                                  "playing": clock and clock["playing"], "rtt_ms": best and round(best[0] * 1000, 2),
                                  "file": clock and clock["file"].get("name")}), flush=True)
            msg, addr = self.recv(0.01)
            if not msg:
                continue
            kind = msg.get("t")
            if kind == "welcome":
                joined = True
                print(json.dumps({"t": round(t - self.start, 2), "welcome": msg.get("seat"),
                                  "peers": [p["name"] for p in msg.get("peers", [])]}), flush=True)
            elif kind == "reject":
                print(json.dumps({"rejected": msg.get("reason")}), flush=True)
                return 1
            elif kind == "pong" and msg.get("seq") in pings:
                t1 = now()
                t0 = pings.pop(msg["seq"])
                offsets.append((t1 - t0, msg["th"] - (t0 + t1) / 2))
            elif kind == "clock":
                clock = msg
            elif kind == "bye":
                print(json.dumps({"bye": msg.get("reason")}), flush=True)
                break
        if joined:
            self.send(haddr, {"t": "bye", "reason": "peer done"})
        print(json.dumps({"summary": {"joined": joined, "sent": sent, "pings": len(offsets),
                                      "host_position": host_pos()}}), flush=True)
        return 0 if joined else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="role", required=True)
    h = sub.add_parser("host")
    h.add_argument("--port", type=int, default=PORT)
    h.add_argument("--file", default="stub://flat_sbs")
    h.add_argument("--rate", type=float, default=1.0, help="timeline rate (reports 1.0: != 1 simulates drift)")
    j = sub.add_parser("join")
    j.add_argument("host")
    j.add_argument("--pin", default="")
    for p in (h, j):
        p.add_argument("--script", default="", help="actions at seconds: pause@3,seek:120@5,play@7")
        p.add_argument("--seconds", type=float, default=20.0)
    a = ap.parse_args(argv)
    if a.role == "join":
        a.port = 0
    return (Host(a) if a.role == "host" else Guest(a)).run() or 0


if __name__ == "__main__":
    sys.exit(main())
