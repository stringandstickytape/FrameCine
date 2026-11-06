# Window source: the browser on the screen (note for the app)

The engine branch `frame/window` adds `X11WindowSource`. It shows any X11 window of the Frame's desktop as a texture,
zero copy where possible, and sends that window input. The first use is the Flathub Chromium playing BBC iPlayer or
YouTube. Its sound already reaches the headset through PipeWire, so the app handles only the picture and the input.
The design, the gamescope focus findings and the device results are in `spikes/05-window/README.md`.
All of it is verified on the Frame: zero-copy capture, synthetic input, focus, and XR with the controller (tests 1-6).
For one engine build with both modules, use `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_ALL` (fork branch
`frame/window-on-player`: `frame/window` rebased on `frame/player` 2b35386ef0; sha256
e247c7021480ca11e8ae3f6b4ff68271b97f6ec445a3a1555ec1e170e169cd38).
`spikes/05-window/project/main.gd` is a working example of everything below.

## In short

1. **Launch** with
   `flatpak run org.chromium.Chromium --ozone-platform=x11 --window-size=1920,1080 --window-position=0,0 --no-first-run --disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-background-timer-throttling --autoplay-policy=no-user-gesture-required --app=<url>`.
   Then find the window that is new since the launch (class `chromium`). Don't match by pid.
2. **Capture** with `capture(id)` and `update()` every frame. The picture is `get_texture()`: sRGB values, decode them
   in the shader.
3. **Take focus back** with `remap_window(get_own_window())` right after the capture.
4. **Input** goes in as synthetic events (the default method). Pointer coordinates are window pixels; the page sees CSS
   pixels at a scale of 1.5, which needs no correction.
5. **Keyboard.** A paired physical keyboard works directly. The on-screen keyboard (`send_text`, `send_godot_key`) is for
   when there is none.
6. **Close** with `close_window(id)` when the user asks, `stop_capture()` when leaving, and `close()` at exit.

## API

```
var win := X11WindowSource.new()
win.open()                                  # its own X connection (DISPLAY=:0); Error
win.list_windows()                          # [{id, frame, title, class, instance, pid, x, y, width, height, ...}]
win.capture(id)                             # Error; picture in win.get_texture() (stays the same object)
win.update()                                # every frame, main thread; true when the picture changed
win.get_size()                              # Vector2i, signal size_changed(size)
win.get_stats()                             # {mode: dmabuf|shm|get_image, zero_copy, frames_updated, ...}
win.send_pointer(x, y)                      # window pixels
win.send_button(1, pressed)                 # 1 left, 2 middle, 3 right, 8 back, 9 forward
win.send_scroll(0, notches)                 # +down; fractions accumulate
win.send_text("bbc"); win.send_godot_key(KEY_ENTER, true); win.send_godot_key(KEY_ENTER, false)
win.close_window(id)                        # WM_DELETE_WINDOW, as a close button does
win.stop_capture(); win.close()
signal window_closed                        # the captured window went away
```

The texture holds sRGB-encoded values in a UNORM format. The 3D shader must decode them, as `video.gdshader` already
does for the decoder's output. Its alpha is 1 for normal (depth-24) windows. There are no mipmaps: a 1920x1080 page on a
screen narrower than about 1900 px in the headset shimmers a little on fine text.

Use the default input method, `INPUT_SEND_EVENT` (synthetic events). On the Frame, Chromium accepts them all as trusted
input (spike README, test 3), and they need no X focus or stacking. `INPUT_XTEST` exists but isn't needed.

Pointer coordinates are window pixels. Chromium runs at a device scale factor of 1.5 on the Frame, so the page sees CSS
pixels, two thirds of these. That is expected; don't scale anything.

## Wiring it into the player

1. **A source.** Add `scripts/video/window_video_source.gd`, a `VideoSource` with `get_kind() == "window"`:
   - `open("window://<id>")` or `open("browser://<url>")` captures the window.
   - `update()` calls `win.update()`.
   - `has_frame()` is true once captured.
   - `get_audio_stream()` returns null, so the player runs on the frame clock.
   - `can_seek()` is false.
   - `play()` and `pause()` can send Space, which pauses most web players.
   - `get_video_info()` gives the window size.
   - `get_known_mode()` is flat 2D.

   Have `video_source_factory.gd` pick it for the `window://` and `browser://` prefixes.
2. **The shader.** `video.gdshader` samples NV12 planes. Add `uniform bool rgb_source` and
   `uniform sampler2D rgb_tex : filter_linear, repeat_disable`. When `rgb_source` is set, take the colour from `rgb_tex`
   and skip the YUV matrix. The sRGB decode, the projection, the stereo layout and the visible rectangle stay as they are.
   `VideoScreen.set_rgb_texture(tex)` sets both. With that, a browser window can also be shown in 180/360 or SBS (YouTube
   VR videos in the browser, for example).
3. **A "Browser" place** in the file browser, as the first place after Network. The virtual folder `browser://` lists:
   - "Open a web page…": a `LineEdit` with the existing `onscreen_keyboard.gd`, plus the pages the user saved (kept in
     settings like the SMB hosts; none built in, so no third-party names ship as presets). Opening one runs the launch
     below.
   - The browser windows that are already open (`list_windows()` entries whose class or instance contains `chromium`).
     Opening one captures it.
   - On the row of the window being shown: "Close window" (`close_window(id)`).
4. **Launching.** Snapshot the ids from `list_windows(true)`. Run
   `OS.create_process("flatpak", ["run", "org.chromium.Chromium", <flags>, "--app=" + url])` with the flags from the
   spike README ("Browser command"). Then poll `list_windows()` every 0.25 s, for up to 20 s, for a new window whose
   class or instance contains `chromium`, and capture it. Don't match by pid: if the browser is already running, the
   window belongs to the old process.
5. **Focus.** Launching maps a new window, and on the Frame that window takes gamescope's focus, `_NET_ACTIVE_WINDOW` and the
   X keyboard focus. Once the window is captured, call `win.remap_window(win.get_own_window())`. This unmaps and maps our
   window, and gamescope prefers the newest mapped one. It was verified on the device (spike README, test 5): focus came
   back to the player and the capture kept running. Input doesn't depend on focus: synthetic events reach Chromium either
   way.
6. **Ending.** `stop_capture()` when the user picks a file, `close()` when the app quits. Leave the browser running
   unless the user chose "Close window".

## Controller mapping while a window is on screen (menu hidden)

The right controller has two modes, and the eyes choose between them (`scripts/window_pointer.gd`,
`scripts/video/stick_cursor.gd`):

- **Pointer mode, while you look at the screen.** A cursor shows on the page. The stick moves it, and the trigger
  clicks there.
- **Normal mode, while you look away.** No cursor shows, and that tells you the stick does its normal job: it
  scrolls and sends the arrow keys.

The gaze is the calibrated eye gaze (`eye_gaze.gd ray()`). Without eye tracking, the head's direction is used.

| Control | Pointer mode (looking at the screen) | Normal mode (looking away) |
|---|---|---|
| thumbstick | moves the cursor (see "The stick pointer") | up / down: scroll, `send_scroll(0, -stick.y * 12 * delta)` (about 12 notches a second at full tilt); left / right: the Left / Right arrow keys (YouTube and iPlayer seek 5 s with them) |
| squeeze held + thumbstick | the normal mode's scroll and arrow keys; the cursor stays where it is | the same |
| trigger | left button at the cursor, pressed and released with the trigger, so drags work. It replaces play / pause. | nothing |
| squeeze, tap | right button at the cursor (context menu). A squeeze that scrolled with the stick is no tap. | nothing |
| A | Space (play / pause in web players) | the same |
| B | browser Back (`send_godot_key(KEY_BACK, ...)`, XF86Back); an Android app's own Back | the same |
| bumper (the pointer hand's) | talk: voice into the selected field, else the assistant (see "Voice into a field") | talk to the assistant or agent (Claude, Codex) as always |
| menu, view | unchanged (menu, overlay) | the same |

The printed legends follow the mode: `WINDOW_POINTER_LABELS` (POINTER, CLICK, HOLD: SCROLL) and `WINDOW_AWAY_LABELS`
(SCROLL / KEYS; trigger and squeeze blank) in `main.gd`, translated like every legend. An agent's terminal on the big
screen has no cursor and keeps its own mapping (`TERMINAL_LABELS`).

### The stick pointer

- **Hysteresis.** Pointer mode starts after 0.1 s of gaze on the screen. The screen counts with a margin of 5 % of its
  size round its edges. Pointer mode ends after 0.4 s of gaze off the screen.
- **Latch.** While the stick is pushed, or the trigger is held for a drag, pointer mode stays on wherever the gaze
  goes.
- **The cursor never follows the gaze.** The gaze only chooses the mode. The cursor starts in the window's middle
  and stays where the stick leaves it, hidden or shown (the user, 2026-11-06).
- **Speed.** The dead zone is 0.2, as in the app's other stick handling. Past it, the speed is
  `((push - 0.2) / 0.8)²` of full speed, so small tilts move slowly for fine aim. At full tilt the cursor crosses the
  window's width in one second.
- **Drawing.** The capture has no cursor in it, so the app draws its own into the picture itself:
  `draw_cursor()` in `shaders/video_common.gdshaderinc`, from the uniforms `cursor_px` (window pixels) and
  `cursor_alpha`. It is a white ring (11 px radius) with a dark edge on each side and a dot in the middle, so it shows
  on light and dark pages. It is for captured windows only (`rgb_source`). The film layer's SubViewport pass copies
  every uniform of the screen's material, so the layer draws the same cursor. A quad in front of the screen would be
  hidden by the layer (`play/film_layer.gd`), so there is none. The cursor fades in and out over 0.1 s.
- **The X pointer** follows the cursor (`send_pointer` whenever it moves by 0.5 px or more), so hover effects work.

### The laser

The laser is off on a window by default. It was drawn in front of the screen, so the film layer hid whenever it
pointed there (the sharp text went with it). It also competed with the cursor for the trigger. The stick pointer
replaces it. `[browser] laser` (System, Controllers: "Laser on the browser") brings it back as an alternative: where
the laser meets the window, the cursor goes to that point and stays in pointer mode, and the trigger and a squeeze tap
click there. The legends while you look away are then the laser's (`WINDOW_LABELS`: CLICK, R-CLICK, SCROLL / KEYS).
With it off, the UI layer drives the laser as during a film: only on the panel, the card and the tablet.

Text: a keyboard paired to the headset (Bluetooth) types into Chromium directly (verified in the headset), so nothing is
needed for it. Without one, open the on-screen keyboard from the menu ("Keyboard"), and send its keys with `send_text()`
and `send_godot_key()` instead of typing into a `LineEdit`. The mouse and keyboard handling for the flat window is in the
spike's `_unhandled_input()`.

The info overlay can show `get_stats()["mode"]` (`dmabuf` is zero copy, `shm` is the copy fallback),
`frames_updated` per second and `fetch_ms_avg`.

## Voice into a field

While the browser is on the big screen, the menu is hidden **and you are looking at it** (the stick pointer is on: the
ring shows), the talk button (the pointer hand's bumper, `ui_layer.gd talk_hand()`) first asks the page what has focus
(`scripts/video/browser_dictation.gd`). Looking anywhere else, it is the assistant's or the agent's as always, so
Claude or Codex can be talked to without their window open (the user, 2026-11-06):

- **A text field has focus:** an input of a text type (text, search, url, tel, email), a textarea, or
  `isContentEditable`. The recording is transcribed on the headset (`scripts/voice/transcriber.gd`, the whisper
  backend). On release, the final text goes in with DevTools `Input.insertText`, which types as a keyboard does (any
  Unicode, Chinese too). Before the text goes in, the focus is checked again. If the caret follows a word, a space goes
  first.
- **A password field has focus** (`type=password`, or a field masked with `-webkit-text-security`): refused, with the
  toast "That is a password field. Voice never types into one." Nothing is recorded.
- **Anything else, or the page doesn't answer within 1.5 s:** the talk button does what it did before (the
  assistant, the dev link or an agent), exactly as before. There is no new mode to remember. With none of those, a
  toast says "Select a text field on the page first, then hold the talk button."

Without a transcriber backend, the toast says "Speech to text isn't working on the headset, so nothing was typed." and
the field stays as it was. The bumper's legend says TALK while the page can take voice, even with no assistant paired.
The speech model starts when the browser first shows with DevTools, so the first press doesn't wait for it to load.

**The connection.** `scripts/video/devtools_session.gd` keeps one WebSocket open to the page target while the browser
is on the big screen: the `webSocketDebuggerUrl` from `/json`, on 127.0.0.1 only. A question to the page costs one
round trip. On opening, it sends `Page.enable`, so that `Page.frameNavigated` tells it when the page changes, and
`Target.setAutoAttach` with flatten. If the socket closes, it opens again every 2 s.

**The page script.** `scripts/video/page_field.gd` is one function with four operations, run with `Runtime.evaluate`:

- `check`: what has focus. Focus inside shadow roots and same-origin iframes is followed. The answer never includes
  the field's text: it is only the kind, the type, a password flag, the frame and one bit (whether the character before
  the caret is a space).
- `mark`: the check, and the outline on a text field.
- `words`: the live words.
- `unmark`: removes the outline and the words.

**The highlight.** While the talk button is held for a field, and only then, the field glows: a blue ring with a
white edge and a soft glow. The live partial words show in a small dark box under the field (above it near the
bottom of the view).

- Both are one element added at the end of the document, in a closed shadow root, with `pointer-events: none` and the
  highest z-index. The page's own styles and the field itself are not touched.
- Each animation frame, the element is placed on the field's `getBoundingClientRect()`, so it follows scrolling and
  resizing.
- It goes on release, on a cancel (the menu opening, the window closing), on a page change (the document goes, and the
  dictation is cancelled with a toast) and when the field leaves the document.
- `[browser] dictation_partials` (default on) turns the live words off. Each live word costs a short transcription on
  the CPU. A browser on the big screen decodes no film, so this costs less than during a film.

**Iframes.** A login box from another site is a cross-origin iframe in its own process, so the page's script sees
only the `<iframe>`. Auto-attach brings each such frame in as a session on the same socket. When the page says the
focus is in a cross-origin frame, the frames' sessions are asked in turn, and the one with the focus and a field gets
the outline and the words. The text still goes in through the page's own `Input.insertText`: Chromium sends it to the
focused frame. This is tested only against a fake DevTools peer, not yet in Chromium. If a frame can't be reached (it
didn't attach), the field counts as "not a field": `browser_field` says so (`frame: cross-origin` with a note), and
the talk button goes to the assistant. The plain fallback for that case is `browser_insert_text` without DevTools (it
types into whatever has focus).

**Without DevTools** (a browser that was already running, which ignores the flag): nothing can tell what has focus,
or whether it is a password field. The talk button therefore stays the assistant's. `browser_insert_text` falls back
to the window's own text input (`WindowVideoSource.send_text()`, the engine's `send_text`), into whatever has the
keyboard focus, and says so in its reply.

**Privacy.**

- What a field holds is never read.
- What was said is never logged. The log has only "dictating into the page's input" and the like.
- `browser_insert_text` replies with the number of characters, never the text.
- `browser_field` returns the kind, the type, the password flag and the frame only.

**Commands** (the dev link and the assistant):

- `browser_pointer` (read): the mode, the cursor, the window size, the gaze source and the settings.
- `browser_field` (read): what has focus, without its contents.
- `browser_insert_text {text}` (control): types into the focused field through the app, as the voice does, with the
  same checks.

The dev link's `set` also has `browser_laser`.

**Tests.** `tests/test_browser_pointer.gd` covers the pointer. `tests/test_browser_dictation.gd` covers the dictation
against a fake DevTools page: a WebSocket server on the loopback, with a pretend focus. That test also runs
`tests/page_field_check.js`, the page script in a small stand-in DOM, when Node is installed.

### Open questions

- **The gaze jump while reading.** The numbers (10 %, 0.15 s of rest, 0.6 s after the stick) are a first guess. Try
  them in the headset, and on a long article.
- **Cross-origin iframes in Chromium.** Flatten auto-attach over a page's own socket, and `Input.insertText` reaching
  the focused frame, are expected but not proved on the Frame.
- **Chinese and other languages.** The whisper backend asks for English (`language: en`, model `small.en`), so speech
  in Chinese is not transcribed as Chinese. Chinese text goes in correctly through `browser_insert_text`. A language
  setting for the transcriber is still to come.
- **The vocabulary prompt.** The transcriber's prompt is about the player and the assistant, which may bias words
  dictated into a page.
- **The browser's own sound** is not ducked while you speak (it goes through the desktop's audio server, not the
  player's mixer).
- **A modal `<dialog>`** in the top layer can sit above the outline.
- **Left-handed:** the window pointer stays on the right controller, while the talk button follows the pointer hand.

## Terminals of agents on the headset

`app/scripts/agents/` uses this module for terminals as well (`docs/assistant.md`, "Agents on the headset"). A second
`X11WindowSource` next to the screen's captures the agent's window for the pane, while the pane shows. Two instances
work together, on one window too, and closing one leaves the other working (`tests/test_agent_terminal_live.gd`).
Synthetic keys and `send_unicode` sent to xterm's toplevel window reach its text area, provided it runs with
`*allowSendEvents: true`. On the big screen a terminal is the path `terminal://<id>` in `window_video_source.gd`. The
player does not close it: it only lets go of the capture.

## The current page

The browser the player launches gets Chromium's DevTools HTTP endpoint on a random free loopback port
(`--remote-debugging-port=N`, `scripts/video/browser_devtools.gd`), read every 3 s while the window shows: `GET
http://127.0.0.1:N/json`, the page target's url and title (`WindowVideoSource.page_info()`, the assistant's
`browser_page` and `/state`'s `browser`). Loopback only, a new port each launch, gone with the browser. A browser that
was already running ignores the flag: then the page comes from Chromium's history (`browser_history.gd`: a copy of
the locked database, read and deleted at once; the visit titled as the window). The player records its browser
windows (`user://browser_windows.json`); an earlier run's still open are closed before the next launch, so the new
browser gets its port.

## Cost

An idle page costs one non-blocking socket read per frame. A playing video costs, per changed frame, two X round trips
(about 0.1-0.3 ms of CPU), a `poll`, and an ownership transfer of the image, with no copies. Each buffer the X server
uses for the window is imported once (2-3 per window size) and freed when the capture stops. The copy fallback moves
8 MB per changed 1080p frame (about 250 MB/s at 30 fps), so it is only for when the zero-copy path fails.
