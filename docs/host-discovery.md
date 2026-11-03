# SMB host discovery

Idea #49 in `docs/ideas.md`. The headset finds file servers on the LAN by itself, so nobody types an address in VR.
The code is `app/scripts/net/host_discovery.gd`.

## How

Two kinds of query run at once, both over UDP with `PacketPeerUDP`. The socket is polled in `_process()`, the queries
go out 64 per frame, and nothing blocks the frame.

- **NetBIOS.** A node status query (NBSTAT, UDP 137) goes to every address of each local private /24 network, plus
  one broadcast. Windows PCs and Samba servers answer with their name table. A unique name of type 0x20 means a file
  server; otherwise the host's unique workstation name is used.
- **mDNS.** A PTR query for `_smb._tcp.local` goes to 224.0.0.251:5353, with the QU bit set to ask for unicast
  answers. Samba with Avahi, macOS and most NAS boxes answer with the service instance, its host (SRV) and its
  address (A).

Each host is announced once, keyed by address. A host is:

```
{"name": "DESKTOP-PC", "address": "192.168.1.20", "source": "netbios" | "mdns", "file_server": true, "port": 445}
```

mDNS hosts also carry `label`, the service's display name such as "Media Box".

## For the pane's Network place (app-shell)

```
const HostDiscovery := preload("res://scripts/net/host_discovery.gd")
var d := HostDiscovery.new()
add_child(d)
d.host_found.connect(func(h: Dictionary) -> void: add_found_row(h))    # as each answer arrives
d.finished.connect(func(hosts: Array) -> void: d.queue_free())
d.start(3.0)                                                            # seconds
```

A good place is a "Find hosts" row under Network, or a scan each time the Network place opens. A found host opens as
`smb://<name>` (its shares), or `smb://<address>` if the name does not resolve. "Add host" can be prefilled with it.
The scan sends about 255 small packets per network and costs nothing once finished.

Over the dev link and the phone remote, the command is `discover_hosts` (`seconds`, default 3).

## Tested

On the desktop only, on 2026-10-31.

- **Unit tests** (`app/tests/test_host_discovery.gd`): the NBSTAT request's layout; a node status answer with a file
  server name, and one with a workstation only; and an mDNS answer with name compression (PTR, SRV, A) turned into a
  host.
- **Real sockets.** Nothing on this LAN answers NetBIOS or mDNS, and Windows holds UDP 137 on every address. So the
  live test ran against a stand-in responder on this PC's LAN address on port 10137, through `netbios_port`. The scan
  found it once, although it answered both the unicast and the broadcast query. It finished in 2 s, and no frame was
  slower than 20 ms.

Not tested: real Windows, Samba or NAS answers, mDNS on a real network, and the device's Wi-Fi.
