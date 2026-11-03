# Phone remote

Idea #13 in `docs/ideas.md`. A phone on the same Wi-Fi controls the player from a web page that the headset serves.
The phone can pick files, scrub, play and pause, set the volume, type into the pane's text fields (host names,
passwords, URLs) and open web pages on the screen. Nothing needs installing on the phone.

## Turn it on

The remote is off by default. Turn it on in one of two ways:

- **On the command line:** `--remote` after `--`, for that run only.
- **From the pane,** once app-shell adds the switch to the System tab. The switch is remembered as `enabled = true`
  under `[remote]` in `settings.cfg`.

The headset then shows the address and a QR code. Scan the code with the phone's camera. The page opens and pairs
itself.

| Setting under `[remote]` | Default | Meaning |
|---|---|---|
| `enabled` | false | start the remote with the app |
| `port` | 47880 | the TCP port |
| `key` | made on first start | the pairing code. Changing it unpairs every phone. |

## What the page does

The page is `app/remote/index.html`: one file with no outside resources, styled with the pane's colours. It has:

- the title, the time, a seek bar, and Prev, -10 s, Play/Pause, +10 s and Next;
- a volume slider;
- the file browser's places, with folders and video files. One tap opens a folder or plays a file.
- "Type into the headset": text goes into the pane's focused field. "then Enter" submits the form, and "replace"
  replaces the field's text.
- "Web page": opens a URL on the screen through the Browser source.

The page asks for the state once a second.

## How it works

`app/scripts/remote/remote.gd` is the entry point. `main.gd` calls it at the end of `_ready()`. With the remote off,
it reads two values and returns, and the server script is not even loaded.

`app/scripts/remote/remote_server.gd` is a small HTTP/1.1 server on a `TCPServer`. It is polled in `_process()`,
never blocks the frame, and closes every connection after one reply. It serves the page at `/`. Every action is
`POST /api` with `{"cmd": ..., "args": {...}}`, which runs the same command registry as the PC dev link
(`docs/dev/control-protocol.md`). So the phone and the PC share one API, and `describe` lists it.

The commands the page uses are `get`, `play`, `pause`, `seek`, `next`, `previous`, `open`, `set volume`, `places`,
`list_dir`, `type_text` and `open_url`. The last four are new in `app/scripts/dev/browse_commands.gd`. They are
available to the PC link as well. `list_dir` uses the file browser's own data and runs on a worker thread, so a
slow share never blocks the frame.

The built-in commands now live on a shared node, `app/scripts/dev/command_host.gd`, under the scene root. Whichever
client comes first makes it: the dev link or the remote.

## Safety

- **LAN only.** The server listens on every interface, but it closes at once a connection from any address that is
  not private. Private here means 10/8, 172.16/12, 192.168/16, 169.254/16, loopback, and IPv6 link-local and
  unique-local. Each refusal is logged.
- **A pairing code.** Every API call needs the pairing code, in the `X-Remote-Key` header or as `?k=`. The QR code
  carries it in the URL, and the page keeps it in the phone's browser. A device that only knows the address can load
  the page but can't do anything. The code is never written to the log.
- **Limited commands.** The phone may use read and control commands only. Scene changes, settings files, reloads
  and code all belong to the dev link, and the phone gets "... is not available from the phone remote".
- **No encryption.** The connection is plain HTTP. Anyone who can watch the Wi-Fi traffic could see the code. That is
  acceptable on a home network, and nothing here is meant for the internet.

## For the pane (app-shell)

```
const Remote := preload("res://scripts/remote/remote.gd")
Remote.start(main, true)                 # the System tab switch on (remembered); Remote.stop(main, true) off
var server := Remote.instance()          # null when off
server.address_changed.connect(func(url: String, qr: Image) -> void: show(url, qr))   # address or code changed
server.get_url()                         # http://192.168.1.50:47880/?k=...
server.get_qr_image(8)                   # Image, 8 px per module, light border; or get_qr_modules() to draw it
server.new_key()                         # "Unpair phones"
server.status()                          # {running, port, address, connections, requests, refused, error}
```

The server is added to the tree one frame after `start()`. Read `get_url()` and `get_qr_image()` once it is in the
tree, and connect `address_changed` for later changes, such as a new Wi-Fi network or a new code.

## The QR code

`app/scripts/remote/qr_code.gd` is a QR encoder written in GDScript, with no library. It supports byte mode,
versions 1 to 10, all four error-correction levels, and mask choice by the standard's penalty rules. The remote uses
level M. A 40-character URL becomes a 29 x 29 code, version 3, in about 15 ms on the desktop. It is encoded once per
address or code change, never per frame.

## Tested

On the desktop only, on 2026-10-31, with the stock 4.7.2 Windows build, headless. The tests covered:

- **The QR encoder.** Eight codes, versions 1 to 9 at all four levels and including UTF-8 text, all decoded
  correctly by OpenCV.
- **The API, through curl.** The page loaded, and a request without the code got 403. These commands worked: `get`,
  `pause` through the LAN address, `seek`, `places`, `list_dir` on `stub://` and on a folder, `open`, and
  `set volume`. `run`, `spawn` and writing a settings file were refused.
- **Typing.** `type_text` went into the pane's focused URL field, and with `submit` it opened the page.
- **The page's script** passed `node --check`.

Not tested: the page on a real phone, the QR code scanned by a phone camera, the device's Wi-Fi address, and the
remote with the headset on.
