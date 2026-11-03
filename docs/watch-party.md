# Watch party on the LAN

Idea #51 in `docs/ideas.md`. Two or more headsets play the same file on one clock. Each shows the others' head and
controllers in the seats beside it. Play, pause and seek on any headset apply to all. The code is in
`app/scripts/party/watch_party.gd`.

It is off until someone starts it, and it works on the LAN only. Packets from addresses that are not private
(loopback, 10/8, 172.16/12, 192.168/16, link-local, IPv6 unique-local) are dropped. A host can set a PIN, which
guests must give to join.

## Start

| Where | Host | Guest |
|---|---|---|
| Command line | `--party=host` | `--party=join` (the first host heard), `--party=join:192.168.1.20` |
| Commands (PC link, phone) | `party_host name=Robin pin=1234` | `party_join name=Sam host=` (empty: by beacon) or `host=IP[:PORT]` |
| Pane (app-shell) | `WatchParty.host(main, name, pin)` | `WatchParty.join(main, name, "", pin)` |

`--party-name=NAME` and `--party-pin=PIN` go with the command-line forms. `party_leave` leaves, or as the host ends
the party. `party_status` returns the role, the peers, and for a guest the sync figures.

## Protocol

UDP, port 47890, one JSON object per packet, each with `"v": 1` and the sender's random `id`. The host is the
authority on time and state. Guests talk only to the host, and the host forwards what the others need.

| Message | From, to | When | Data |
|---|---|---|---|
| `beacon` | host, broadcast to 47890 | every 1 s | name, port, file, peers, pin (bool) |
| `join` | guest, host | until welcomed, every 1 s | name, pin |
| `welcome` / `reject` | host, guest | on a join | seat, peers, file / reason |
| `peers` | host, guests | when someone comes or goes | peers: [{id, name, seat}] |
| `ping` / `pong` | guest, host / back | every 1 s | seq, t0 / seq, t0, th (host clock) |
| `clock` | host, guests | every 0.25 s and at once on a change | ht (host clock), pos, playing, file, speed |
| `control` | guest, host | on a local play, pause, seek, open | action, pos, path |
| `pose` | everyone, host, the others | 20 Hz | seat, head, l, r: [x, y, z, qx, qy, qz, qw] or null; `from` when forwarded |
| `bye` | either way | leaving or ending | reason |

**The clock.** Each guest keeps the last 8 ping round trips. The one with the shortest round trip gives the offset
between the host's clock and its own (NTP's rule). The host's position now is the clock's `pos`, plus the time since
`ht` (offset applied), times `speed` while playing.

**Following.** Each frame the guest compares that target with its own position:
- More than 0.5 s off: it seeks.
- More than 20 ms off while playing: it changes its speed by up to 5 %, half the error per second. The audio is
  time-stretched with the pitch kept. This trim sits on top of the user's own playback speed.
- Within 20 ms: normal speed.
- Play and pause follow the host's state.

**The file.** The host's clock names its file. When a guest's open file has another name, the guest opens the host's
path if it exists here (the same share, the same local path, a test pattern). Otherwise it emits
`file_needed({name, path, duration})` for the pane to ask the user. It does not follow until the names match. A file
opened on a guest is sent to the host as `open`.

**Seats.** The host is seat 0 and guests get 1, 2 and so on. Each headset puts the others 0.8 m to the right per
seat, relative to its own seat, in its own play space (under the XR origin). An avatar is a sphere with a visor and
a name tag for the head, plus two small boxes for the controllers, in the seat's colour. A hand that is not tracked
is hidden. A guest that is silent for 6 s is dropped. A guest whose host is silent for 6 s ends the party.

## For the pane (app-shell)

```
const WatchParty := preload("res://scripts/party/watch_party.gd")
WatchParty.host(main, "Robin")                      # or .join(main, "Sam", "") to find a host
var p := WatchParty.instance()                    # null when off; p.status() for a peers list
p.peers_changed.connect(func(list: Array) -> void: ...)        # [{id, name, seat}]
p.file_needed.connect(func(f: Dictionary) -> void: ...)        # ask the user to open f.name
p.ended.connect(func(reason: String) -> void: ...)
WatchParty.leave()
```

## The desktop peer

`tools/party_peer.py` (standard library only) speaks the protocol. Use it to test the app without a second headset:

```
python tools/party_peer.py join 127.0.0.1 --script "pause@4,seek:120@6,play@8"     # the app hosts
python tools/party_peer.py host --port 47892 --rate 1.02 --script "seek:200@12"    # the app joins; a fast clock
```

## Tested

On the desktop only, with the stock 4.7.2 Windows build, on 2026-10-31. There was one app and the desktop peer;
**two headsets were not tested, because that needs a second device**.

- **The app as host** (`--party=host`): the peer joined and got seat 1. Its pause, seek to 120 s and play applied in
  the app. The peer's computed host position matched the app's own position (121.1 s at 9.1 s, then 121.9 s at
  9.5 s). The peer's head and moving hands showed in the app, 0.8 m to the right, in seat 1's colour. The peer
  leaving removed it.
- **The app as guest** (`party_join` with no address): it found the peer by its beacon and joined it over the LAN
  address. The peer's clock ran 2 % fast. The app held 25 to 56 ms behind it with a speed trim of about 2 %. It
  followed the peer's seek to 200 s (one seek), pause and play. A seek made in the app reached the peer as a
  `control`. When the peer ended, the app's party ended.

Not tested: two headsets (needs a second device), the Frame's Wi-Fi (round trips and broadcast), a real file on a
share, three or more peers, and the avatars in XR.
