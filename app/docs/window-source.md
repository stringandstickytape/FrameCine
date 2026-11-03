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

| Control | Action |
|---|---|
| laser on the screen | `send_pointer` at the hit point. The quad's UV times `get_size()` gives window pixels; see `_ray_to_window()` in the spike. |
| trigger | left button, pressed and released with the trigger, so drags work. It replaces play / pause. |
| squeeze, tap | right button (context menu). Squeeze-hold keeps moving the screen, so tell the two apart as the app already does. |
| thumbstick up / down | scroll, `send_scroll(0, -stick.y * 12 * delta)` (about 12 notches a second at full tilt). |
| thumbstick left / right | Left / Right arrow keys. YouTube and iPlayer seek 5 s with them. |
| A | Space (play / pause in web players). |
| B | browser Back (`send_godot_key(KEY_BACK, ...)`, XF86Back). |
| menu, view | unchanged (menu, overlay). |

Text: a keyboard paired to the headset (Bluetooth) types into Chromium directly (verified in the headset), so nothing is
needed for it. Without one, open the on-screen keyboard from the menu ("Keyboard"), and send its keys with `send_text()`
and `send_godot_key()` instead of typing into a `LineEdit`. The mouse and keyboard handling for the flat window is in the
spike's `_unhandled_input()`.

The info overlay can show `get_stats()["mode"]` (`dmabuf` is zero copy, `shm` is the copy fallback),
`frames_updated` per second and `fetch_ms_avg`.

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
