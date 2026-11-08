# pc-windows

The PC half of "PC windows in the headset" (`docs/pc-windows.md`, decision D31): a small Windows tray app that sends
the PC's windows and monitors to the headset, with the PC's sound, and replays the headset's mouse and keyboard on
the PC. The headset is the other half (`app/scripts/pc/`). MIT, like the rest of the repository.

Windows 10 2004 or later, 64-bit. Nothing to install beside it: it uses only what Windows has
(Windows.Graphics.Capture, Direct3D 11, the GPU's own video encoder through Media Foundation, WASAPI, Windows' AAC
encoder, Schannel, DPAPI). One exe, statically linked.

## Build

Visual Studio 2022 or later with "Desktop development with C++" (it brings CMake and Ninja). Then, from a command
prompt:

    pc\build.cmd          configure, build (Release) and run the unit tests
    pc\build.cmd clean    start again from nothing

The exe is `pc\build\pc-windows.exe`. By hand, from a "x64 Native Tools" prompt:

    cmake -S pc -B pc\build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build pc\build
    ctest --test-dir pc\build

The code builds at `/W4 /WX` (warnings are errors).

## Run

1. Start `pc-windows.exe`. A tray icon appears; until it is paired its window opens by itself.
2. In the headset: System, **PC windows**, on, **Add a PC**. It shows six digits.
3. Type them into the window's **Pairing code** and press **Pair**. From then on the two find each other by
   themselves whenever both are on; the window can stay closed (the tray icon opens it again).
4. In the headset, Files, **PC windows**: pick a window or a monitor.

The window shows the headset (found, connected, paired), the code field, what is being sent, the video encoder in
use, **Forget headset** and **Quit**. Closing the window keeps the app in the tray; **Quit** (or the tray menu's
Quit) ends it. Run it at sign-in by putting a shortcut to it in `shell:startup`.

Windows may ask once whether `pc-windows.exe` may use the network: allow private networks.

Options, mostly for tests: `--config-dir DIR`, `--log FILE`, `--headset ADDRESS` (ask that private address directly
as well as by broadcast), `--code 123456` (pair at once), `--codec hevc|h264|none`, `--only-titles TEXT`,
`--no-monitors`, `--port N`, `--stats-every S`, `--hidden`, `--encoders` (write the encoders found to the log and
stop). See the top of `src/app/main.cpp`.

## What it sends, and to whom

- Only to the paired headset, over TLS (1.2 or 1.3) on TCP 47803, checked against the certificate's pin learned at
  pairing; only to private addresses (the home network). Nothing listens on the PC: it dials the headset.
- Discovery: a UDP broadcast every 2 s until connected, holding the PC's name.
- When the headset asks: the list of windows and monitors (title, program name, size, a thumbnail of at most 256 px),
  the pictures of the windows it opens (HEVC, or H.264 on a GPU without HEVC, encoded on the GPU), the PC's sound
  while it asks for it (AAC, 160 kbit/s), and the cursor's shape over the window it points at.
- It types and clicks only what the headset sends, into the window the headset has open, and lets go of every key
  and button when the headset goes.
- A window that is minimised sends its last picture every 2 s; a window that closes ends its stream. A PC with no
  hardware video encoder tells the headset so; there is no software encoder.

## Privacy

- The pairing (headset name, address, pin and token) is kept in `%APPDATA%\pc-windows\pairing.dat`, encrypted for the
  Windows user with DPAPI. **Forget headset** deletes it.
- The log (`%APPDATA%\pc-windows\pc-windows.log`, started again each run) has window ids (handles), sizes, rates and
  errors. Never titles, thumbnails, pictures, sound, typed text, keys, the pairing code or the token.
- Nothing is recorded or kept on the PC; pictures and sound go straight to the headset.

## Tests

- `ctest --test-dir pc\build` (in `pc\build.cmd`): the unit tests (`tests/unit_tests.cpp`): the PCW1 packet framing,
  JSON lines (parsing, escaping, bad input), discovery messages, private addresses, base64 and hex, every Godot key
  name (scan codes and extended flags), the mouse mapping (stream pixels to the screen and SendInput's absolute units,
  exact for every pixel of several desktops), the stream size rules, Annex B and ADTS helpers.
- `python tools\pc_windows_fake_headset.py`: the end-to-end test with a fake headset (Python standard library only)
  on this PC: discovery, a wrong and a right pairing code, the list, a stream with sound, `quality`, focus, mouse,
  wheel, keys, Ctrl+C and Unicode text into a test window (`tests/testwin.cpp`, which records what it got), a resize,
  minimise and restore, close and reopen, a scaled stream, the control and a stream connection dropping, opening a
  minimised window, the window closing, H.264 over TLS 1.2, and a PC with no encoder. The recordings are decoded
  with ffmpeg (on the PATH, or in WSL) and checked: sizes, every packet a frame, no B-frames, the test pattern's
  colours, the sound's 1 kHz test tone. It drives only its own test windows (`--only-titles`), but it moves the
  real mouse and brings the test window to the front for a few seconds.
- `python tools\pc_windows_fake_headset.py --bench [--busy] [--rounds 3]`: one and three 1920x1080 windows at 60 fps
  and 20 Mbit/s: frame rate, bitrate, latency, the app's CPU and the whole PC's CPU and GPU load, median and range
  over the rounds.
- `pc/tests/data/test_only_headset.*`: a throwaway self-signed certificate and key for the fake headset. Test only:
  they protect nothing.

## Taking the PC back

The PC's own mouse and keyboard always win. Move the PC's mouse or press a key and the headset's mouse and keys are
ignored until the PC's have been still for about 4 seconds (the headset is told). Two keys work whatever has the focus:

| Keys | What |
|---|---|
| Ctrl+Alt+F12 | Hands off: the headset's mouse and keys are ignored until pressed again |
| Ctrl+Alt+Shift+F12 | Sending stopped as well: every window and the sound end, and the headset can't open more until pressed again |

The window (Alt+Tab to "PC windows") works from the keyboard: Tab, Enter, Esc.
