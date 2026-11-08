# PC windows in the headset

The PC's windows (and whole monitors) as panes in the headset, used with a mouse and keyboard paired with the
headset. Decision D31 (`docs/decisions.md`) has the why. This file is the design and the protocol both halves follow:
the PC app (`pc/`, C++) and the headset (`app/`, GDScript, with the engine's stream decoder).

Status: phase 1 being built (2026-11-08).

## What the viewer does

1. On the PC: run `pc-windows.exe` (a tray icon). It looks for the headset on the LAN.
2. In the headset: System tab, **PC windows**: turn it on, press **Add a PC**. The panel shows a six-digit code for 10
   minutes.
3. The PC app shows the headset's name and asks for the code; once given, the PC is paired (kept on both sides) and
   connects by itself from then on, whenever both are on.
4. In the headset: the PC's windows and monitors are listed with their thumbnails (Files tab, the PC's place). Pick
   one: it opens as a pane in front of you. **Show on the big screen** puts it where the film goes, with the room's
   presentation.
5. Squeeze and hold on a pane to move it; the stick while holding makes it bigger or smaller. The pane looked at
   (half a second) is highlighted and takes the keyboard and voice.
6. The mouse paired with the headset moves a cursor round you; over a pane it is that window's mouse. Clicks, the
   wheel and keys go to the PC window. The controller's laser and trigger work as a mouse on a pane too.

## Phase 1 (now)

The PC app (discovery, pairing, the window and monitor list with thumbnails, capture, encode, send, the sound, the
input), the headset's service (discovery reply, pairing, control, streams), the stream decoder in the engine, panes
(open, close, move, resize, highlight, private layer), the cursor on the sphere with mouse and keyboard forwarding,
voice and the on-pane keyboard as text into the focused pane, one pane on the big screen. The sound plays from the
big screen's place, or in front when no pane is there.

Later: per-window sound from each pane (Windows' process loopback), layouts remembered, monitors' own panes laid out
as the monitors are.

## Network

| Port | Who to whom | What |
|---|---|---|
| UDP 47803 | PC broadcast to 255.255.255.255, headset replies to the sender | Discovery |
| TCP 47803 | PC to headset | TLS: the control connection and the stream connections |

Private addresses only (the headset ignores and refuses others). The headset's service is off until switched on in
System; with it on, the port is open while **Add a PC** runs or once a PC is paired.

### Discovery

The PC sends, every 2 s until connected, a UDP datagram to 255.255.255.255:47803 (and to each interface's broadcast
address) holding the UTF-8 JSON `{"t":"pcw_find","v":1,"pc":"<the PC's name>"}`. The headset, while **Add a PC** runs
or when a paired PC asks, replies to the sender's address and port with
`{"t":"pcw_here","v":1,"name":"<headset name>","port":47803,"pin":"<SHA-256 of the TLS certificate's DER, hex>",
"pairing":true|false}`. The PC app keeps the headset's address, name and pin.

### TLS

The headset's service uses the assistant service's self-signed certificate (`assistant_tls.key` / `.crt`, made once,
owner-only). The PC app checks the certificate against the pin it was given in discovery and kept at pairing (trust on
first use, pinned after). TLS 1.2 or later.

### Pairing

On the control connection's first line (below) the PC sends `"code"` with the six digits shown in the headset. The
headset answers with a new random token (32 bytes, hex); it keeps only the token's SHA-256 and the PC's name in
`pc_clients.cfg` (owner-only, never logged). The PC app keeps the token with the headset's name, address and pin,
encrypted for the user with DPAPI, under `%APPDATA%\pc-windows\`. Five wrong codes close pairing.

## Control connection

TLS on TCP 47803. Both ways: UTF-8 JSON objects, one per line (`\n`), each with `"t"` its type. Unknown types and
fields are ignored (so either side can be newer). The first line from the PC is
`{"t":"hello","v":1,"pc":"<name>","token":"<hex>"}` (paired) or `{"t":"hello","v":1,"pc":"<name>","code":"123456"}`
(pairing). The headset replies `{"t":"welcome","v":1,"headset":"<name>","token":"<hex, only when just paired>"}` or
`{"t":"refused","why":"..."}` and closes.

Window ids are strings from the PC: `"w:<window handle, hex>"` for a window, `"m:<monitor index>"` for a monitor.

### PC to headset

| Type | Fields | When |
|---|---|---|
| `windows` | `list`: `[{id, kind: "window"\|"monitor", title, app (the exe's name), w, h, thumb (base64 JPEG, at most 256 px on its long side)}]` | on `list`, and when the list changes (at most once a second) |
| `stream` | `stream` (number), `id`, `codec` (`"hevc"` or `"h264"`), `bits` (8 or 10), `w`, `h` | a stream connection is up and sending |
| `resized` | `id`, `w`, `h` | the window's size changed (the stream goes on at the new size from its next key frame) |
| `closed` | `id` | the window went (its stream ends) |
| `cursor` | `id`, `shape` (`arrow`, `ibeam`, `hand`, `wait`, `cross`, `size_we`, `size_ns`, `size_nwse`, `size_nesw`, `move`, `no`, `other`) | the cursor's shape over that window changed |
| `pong` | `n` | answer to `ping` |
| `error` | `what`, `id?` | something the PC could not do (no encoder, a window that refuses capture) |

### Headset to PC

| Type | Fields | Meaning |
|---|---|---|
| `list` | | send `windows` now |
| `open` | `id`, `stream` (a number the headset picks, 1 up), `max` ([w, h], the most it wants), `fps`, `kbps` | start capturing that window and open stream connection `stream` |
| `quality` | `stream`, `fps`, `kbps` | change the rate (the pane looked at gets more, the others less) |
| `close` | `stream` | stop that stream |
| `sound` | `on` (bool) | start or stop the sound stream (stream 0) |
| `mouse` | `id`, `event` (`move`, `down`, `up`, `wheel`), `x`, `y` (in the stream's pixels, floats, 0..w, 0..h), `button` (`left`, `right`, `middle`, `x1`, `x2`; for down and up), `dx`, `dy` (wheel, in notches, floats) | the mouse over that window |
| `key` | `id`, `key` (Godot's name for the physical key, as `OS.get_keycode_string(physical_keycode)`: `"A"`, `"Ctrl"`, `"F5"`, `"Left"`, `"Kp 1"`...), `down` (bool) | a key on the keyboard paired with the headset |
| `text` | `id`, `text` | text typed as it is (voice, the on-pane keyboard): Unicode, sent as typed characters |
| `focus` | `id` | bring that window to the front (sent before its first click or key after it gained focus in the headset) |
| `ping` | `n` | every 5 s; no `pong` in 15 s and the headset closes |

Mouse coordinates are in the captured picture's pixels (the whole window as captured, title bar included). The PC
maps them to the screen through the window's rectangle at the time (per-monitor DPI aware) and moves the real cursor
there with `SendInput` (absolute, virtual desktop). The PC brings a window to the front only on `focus`.

## Stream connections

TLS on TCP 47803, opened by the PC for each `open` (and stream 0 for the sound). First line:
`{"t":"stream","v":1,"token":"<hex>","stream":<n>}\n`. Then packets, back to back:

| Bytes | Field |
|---|---|
| 4 | magic `PCW1` |
| 1 | kind: 1 video, 2 sound |
| 1 | flags: bit 0 key frame (video: carries VPS/SPS/PPS before the frame), bit 1 config change (a new size or codec: the decoder starts again) |
| 2 | reserved, 0 |
| 8 | time, microseconds, little-endian signed: the PC's one clock (QueryPerformanceCounter) for every stream |
| 4 | length of the payload, little-endian |
| n | payload: video, one access unit in Annex B (start codes); sound, one AAC-LC frame with its ADTS header (48 kHz, stereo) |

Video: HEVC Main (8 bit) or Main 10, 4:2:0, or H.264 High where there is no HEVC encoder; no B-frames; a key frame
every 2 s and on request (a new pane, a decoder that lost its place: the headset closes and reopens the stream);
variable frame rate (a frame only when the window changed, at least one every 2 s so the pane knows the PC is there).
Sound: AAC-LC 48 kHz stereo, 160 kbit/s.

The headset plays each packet at its time plus a fixed delay (the same for picture and sound, so they stay together;
150 ms to start with), so frames are evenly paced and the sound matches the picture.

## The PC app (`pc/`)

C++20, CMake, MSVC (Visual Studio 2022 or later), Windows 10 2004 or later. Windows.Graphics.Capture (C++/WinRT) for
windows and monitors, Direct3D 11 for the frames and their scaling, Media Foundation hardware encoders (HEVC, else
H.264), WASAPI loopback and Windows' AAC encoder for the sound, `SendInput` for the mouse and keys, DPAPI for the
token, Schannel for TLS. No other libraries. A tray icon with a small
window: the headset found, the code to pair, the windows being sent, Quit.

## The headset (`app/`)

- The service: `app/scripts/pc/` (the discovery reply, TLS on 47803 with the assistant's certificate, pairing,
  control, streams), System tab's **PC windows** section, the PC's place in Files with the window list.
- The stream decoder: the engine (`~/src/godot-binaural`) takes packets (Annex B access units with a time) and decodes
  them in hardware on the Frame (V4L2, as films do), in software on a desktop, into the textures a pane draws.
- Panes: `app/scripts/pc/pc_pane.gd`: the picture on a quad on the private render layer, moved by squeeze and hold,
  resized by the stick, highlighted when looked at; one may be the big screen's source instead.
- The cursor: captured mouse mode, relative motion on a sphere round the head; over a pane, its pixel; drawn in the
  headset in the shape the PC said.
