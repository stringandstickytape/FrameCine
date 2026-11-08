# PC windows in the headset

The PC's windows (and whole monitors) as panes in the headset, used with a mouse and keyboard paired with the
headset. Decision D31 (`docs/decisions.md`) has the why. This file is the design and the protocol both halves follow:
the PC app (`pc/`, C++) and the headset (`app/`, GDScript, with the engine's stream decoder).

Status: phase 1 being built (2026-11-08). The headset's half is in (below, "The headset"); the PC app is being built.

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

Built 2026-11-08 (phase 1). Tested on the desktop against a fake PC; not yet on the device.

| File | What |
|---|---|
| `app/scripts/pc/pc_windows.gd` | the feature (`main.features.pc_windows`): the service on or off, panes, focus, quality, the cursor, keys, text, voice, the big screen, the sound, the commands |
| `app/scripts/pc/pc_service.gd` | discovery, the TLS listener, pairing, the first line of every connection |
| `app/scripts/pc/pc_session.gd` | one connected PC: its control connection, window list, clock and streams |
| `app/scripts/pc/pc_stream.gd` | one stream connection, read and split on a thread of its own |
| `app/scripts/pc/pc_protocol.gd` | the numbers, the PCW1 header, JSON lines, key names |
| `app/scripts/pc/pc_clock.gd` | the PC's clock as the headset sees it, and the delay |
| `app/scripts/pc/pc_video.gd` | one window's decoder: an HWVideoTexture on a MediaSource in stream mode |
| `app/scripts/pc/pc_sound.gd` | the PC's sound in an AudioStreamGenerator, at its time |
| `app/scripts/pc/pc_pane.gd`, `app/shaders/pc_pane.gdshader` | a pane: the picture, the outline, the bar (Close, Show on the big screen) |
| `app/scripts/pc/pc_cursor.gd` | the cursor and its shapes |
| `app/scripts/pc/pc_window_source.gd` | a pane's picture as the big screen's source (`pcwindow://<pc>/<window>`) |
| `app/ui/pc_windows_row.gd` | System, **PC windows**: on / off, Add a PC with the code and the minutes left, the paired PCs and Forget |
| `app/ui/pc_place.gd` | Files, **PC windows**: each PC's windows and monitors as thumbnails; a line and the on-pane keyboard to type into the pane in focus |
| `tools/pc_windows_fake_pc.py`, `app/tests/test_pc_windows.gd` | the fake PC and the test |

### The service

- Off until System, **PC windows** is on (`[pc_windows] enabled`). With it on, UDP and TCP 47803 open only while
  **Add a PC** runs or once a PC is paired; a connection or a datagram from an address that is not private is ignored.
- Discovery: a `pcw_find` gets an answer while **Add a PC** runs, or when its `pc` name is a paired PC's.
- TLS: the assistant service's key and certificate (`user://assistant_tls.key` / `.crt`, `assistant_tls.gd`, made on
  a thread the first time either service needs them). The pin in discovery is `cert_sha256`: the SHA-256 of the
  certificate's DER, hex.
- Pairing: **Add a PC** makes a code of six random digits for 10 minutes. The hello's `code` is compared in constant
  time; five wrong codes end pairing; the right one ends it too and answers with a token. The token's SHA-256, the
  PC's name, when it paired and its address go to `user://pc_clients.cfg` (owner read and write only;
  `assistant_clients.gd`, which the assistant uses too). Codes and tokens are never printed.
- Every connection is polled in `_process()` until its first line (10 s for the handshake, 10 s for the line). A
  hello makes a session (a second one from the same PC replaces the first) and asks for `list`. A stream line is
  taken only for a stream number that PC was asked for, with its token; the connection then belongs to a reader
  thread.
- `ping` every 5 s on the control connection; no `pong` for 15 s and the PC counts as gone.

### The stream decoder (engine branch `frame/pc-windows`)

Fork commit `42bab8c0bf` on PLAYER_ASTC's `95e9090166`, built in the worktree `~/src/godot-pcwindows`; the headset's
build is `PLAYER_PCWIN` (`docs/BUILD.md`). The fork's `MediaSource` has a stream mode, so a PC window decodes exactly as a film does and nothing of the film
path changes:

- `MediaSource.open_stream(codec, width, height, bit_depth)`: H.264 or HEVC, no file and no demux thread. With 0 x 0
  the size and bit depth come from the first SPS.
- `push_video_packet(data, time_usec, keyframe)`: one Annex B access unit at `time_usec / 1e6` media seconds, into the
  same video queue a film's demuxer fills. Any thread. Before the first key frame, and after a drop, everything up to
  a key frame is dropped (the decoder would have no reference). More than 120 access units queued counts as a decoder
  that is behind: the unit is dropped and `is_keyframe_wanted()` turns true.
- `end_stream()`: the queue drains and the decoder ends.
- A seek on a stream (the V4L2 decoder after a resolution change, a switch to software) drops what is queued and
  waits for the next key frame.
- `HWVideoTexture.open_source()` takes the source as it takes a film's: V4L2 in hardware on the Frame (NV12, or P010
  or Q10C for Main 10), FFmpeg's decoders on a desktop. Its `update(delta, clock)` shows the newest frame whose time
  is at or before the clock, so the clock passed in sets the pacing.
- `AudioPacketDecoder`: `open("aac", rate)`, `decode(adts_frame)`: stereo float frames at the AudioServer's rate
  (FFmpeg's AAC decoder reads the ADTS header itself), `flush()`.
- No FFmpeg rebuild: the full build (`ffmpeg-<arch>-all`) already has the H.264, HEVC and AAC decoders.

### Clock, pictures, sound

- Each PC has one clock (`pc_clock.gd`): every packet's arrival gives "headset ticks minus PC time"; the smallest is
  the offset (the packet that waited least). The PC time to show now is the headset's ticks minus the offset minus
  the delay (`[pc_windows] delay`, 0.15 s). Drift moves the offset by at most 2 ms each 5 s; a jump of more than a
  second (the PC restarted) resets it.
- A stream's reader starts a new MediaSource at its first key frame and at every key frame with the config-change
  flag (the codec is read from the first NAL unit). The pane's `pc_video.gd` opens a second HWVideoTexture on it, and
  once that has a frame it takes over the plane textures (`swap_planes_with()`): no black between sizes.
- `is_keyframe_wanted()` or a decoder error, or a stream connection that ends while its window is still listed: the
  headset closes the stream and opens it again with a new number (at most every 2 s).
- The sound: one PC's stream 0 while one of its panes is open (the pane in focus decides which PC). Each AAC frame is
  decoded on the reader thread; `pc_sound.gd` pushes the frames into an AudioStreamGenerator so each is heard at its
  time on the same clock: late frames are dropped, a gap before an early one is filled with silence, slips under 30 ms
  are left alone. It plays on the Film bus, from the big screen while a window is there, else just in front of the
  head.

### Panes

- Opened from Files, **PC windows** (or `pc_open`): in front of the head at 1 m, about one PC pixel per headset pixel
  (20 pixels a degree), turned round the head by a pane's width from the panes already open. On the private render
  layer only (`VideoScreen.PRIVATE_LAYER`).
- Squeeze and hold with the laser on a pane: it follows the laser at the distance it was taken and faces the head;
  the stick up / down while holding makes it bigger or smaller.
- The bar under it: **Close**, **Show on the big screen** (the window becomes the screen's source, `pcwindow://`, the
  pane's picture hides and its bar says **Back to a pane**). Another file opened, or Stop, gives the window back too.
- Focus: the pane looked at (the calibrated eye gaze, else the head) for 0.5 s gets a thin outline in the accent
  colour and takes the keyboard and the voice. The pane in focus and the one on the big screen ask for 60 fps and
  20 Mbit/s (`quality`), the others 5 fps and 1.5 Mbit/s.

### The cursor, the keys, the text

- With a PC connected, the first motion of a mouse paired with the headset captures it
  (`Input.MOUSE_MODE_CAPTURED`). Its relative motion turns the cursor round the head (0.05 degrees a count); the
  cursor is drawn with no depth test at 1.6 degrees, in the shape the PC said for the window under it. Over a pane it
  is on the private layer and is that window's mouse: `move` each frame it moves, `down` / `up` with the button,
  `wheel` in notches; an `up` goes where its `down` went. Over the menu panel it is the menu's mouse. Over nothing it
  does nothing. The PCs gone: the mouse is let go.
- The controller's laser on a pane (when the menu, an object or a captured window doesn't have it): `move` at the
  laser's pixel, the trigger the left button, the bar's buttons pressed.
- Keys: while a pane has the focus and the menu isn't taking the text, each key goes as `key` with
  `OS.get_keycode_string(physical_keycode)`, down and up (and down again while held, as a keyboard repeats).
- `text`: the talk button while a pane has the focus (the headset's speech to text, what was said never logged), and
  the line with the on-pane keyboard in Files, **PC windows**.
- `focus` goes before the first click, key or text after a pane gained the focus, once.

### Privacy and the assistant

- The panes and the cursor over them are on the private render layer; the big screen is private while a PC window is
  there, and the header calls it "PC window". Titles and thumbnails stay in the session and the Files tab: never in a
  log, a command's result or the settings.
- Commands (`docs/dev/assistant-coverage/room-system.md`): `pc_status`, `pc_list` (read: ids, kinds, the program's
  name and size, never titles or pictures, PCs by id not name); `pc_open`, `pc_close`, `pc_screen`, `pc_pane_size`
  (control). On / off, **Add a PC** and **Forget** have no command, as for the phone remote and the assistant's own
  pairing: a paired PC receives the keys typed into its panes.

### Only the device can tell

- V4L2 decoding of several streams at once beside a film (sessions, memory, the decoder's latency).
- The captured mouse under the Frame's compositor, and a Bluetooth keyboard's key names.
- The latency end to end (the 150 ms delay may go down), and text sharpness at one PC pixel per headset pixel.
- The sound's slips against the PC's clock over an hour.
