# Spike 05: an X11 window (the browser) on the virtual screen

Goal: show any X11 window of the Frame's desktop on the player's virtual screen, zero copy, with controller input
forwarded to it. First target: the Flathub Chromium (`org.chromium.Chromium`, arm64, `--ozone-platform=x11`) playing BBC
iPlayer or YouTube. Its audio already reaches the headset through PipeWire, so only the picture and input are needed.

The Frame's desktop is gamescope with an Xwayland display `:0` (1920x1080, with Composite, DRI3 and Present).
gamescope shows only its focused window, but unfocused mapped windows keep rendering, and so they can be captured.

## Engine side: `modules/x11window` (fork branch `frame/window`, from `frame/player` 6d48ab6812)

| File | What |
|---|---|
| `xcb_loader.{h,cpp}` | Loads libxcb and the composite, damage, xfixes, xtest, dri3 and shm libraries with `dlopen`. The binary gets no new `NEEDED` entries and still starts where they are missing. The generated libxcb 1.15 headers are vendored in `thirdparty/xcb/` (MIT). |
| `x11_dmabuf_image.{h,cpp}` | `X11DmabufImage`: one dmabuf imported as a `VkImage` with an explicit DRM format modifier and a dedicated memory import. This is hwvideo's `DmabufImage` mechanism, for packed `XRGB8888`/`ARGB8888` (and 2101010) instead of NV12. Depth-24 windows get a view with alpha swizzled to 1. |
| `x11_window_source.{h,cpp}` | `X11WindowSource` (RefCounted, script-visible), and `X11WindowTexture` (the Texture2D proxy). |

### Picture path

1. `open()` connects with its own xcb connection (`DISPLAY`). It does not share Godot's Xlib connection.
2. `capture(id)` selects StructureNotify and PropertyChange on the window. It adds an automatic Composite redirect (Xwayland's own manual redirect stays) and creates a DAMAGE object (level NonEmpty).
3. On damage, `update()` subtracts the damage, then names the window's current pixmap (`NameWindowPixmap`). `DRI3 BuffersFromPixmap` returns the dmabuf fds, strides, offsets and DRM modifier. The pixmap is freed at once.
4. The dmabuf's inode identifies the buffer: the same GEM buffer always exports as the same dma-buf. Xwayland can swap a window between a few buffers, so the source keeps up to 6 imports, each made **once** and least recently used first out. It never imports per frame, because per-frame dmabuf import can oops the 6.18 kernel (`msm_gem_import`).
5. Implicit sync: a non-blocking `poll(POLLIN)` on the dmabuf says whether the X server's GPU writes are done. If not, the previous buffer stays on screen for up to 3 frames.
6. On the render thread: the previous buffer is released and the current one acquired through the render graph (FOREIGN ↔ graphics queue family transfer, as for the decoder). The same buffer with new content gets a release and an acquire.
7. `X11WindowTexture` is a RenderingServer proxy pointed at the current buffer's texture, so the material never changes.

An idle window costs one non-blocking read per frame and nothing else. A changed window costs two round trips
(NameWindowPixmap and BuffersFromPixmap), an fstat, a poll and two barriers. There are no copies and no per-frame
allocations beyond xcb's small reply structs.

**Fallback** if DRI3 is missing, the modifier is implicit or unsupported, or the import fails: MIT-SHM `GetImage` into
a memfd (fd passing) or SysV segment, then `texture_update` of a BGRA8 texture. If MIT-SHM is missing too, plain
`GetImage` is used. It is damage-driven as well. `get_stats()` reports `mode`, `zero_copy`, `copies`, `bytes_copied` and
`dmabuf_error`.

The texture holds the window's sRGB-encoded values in a UNORM format, so the shader decodes them
(`project/window.gdshader`).

### Input

The `x`, `y` arguments are window pixels. `send_pointer`, `send_button` (1 left, 2 middle, 3 right, 8/9 back/forward),
`send_scroll` (notches; fractions accumulate into wheel buttons 4-7), `send_key(keysym)`, `send_unicode`, `send_text`
and `send_godot_key(Key)` are available. A keysym that no key produces is put on a spare keycode while it is used
(xdotool's method).

- `INPUT_SEND_EVENT` (default): synthetic core events with an empty event mask, which the X server delivers to the
  client that created the window, whatever it selected. Chromium reads XInput2 for real input, so its core-event path
  decides whether this works. The events carry the server time (synced once with a PropertyNotify), not 0, so
  double-click timing stays sane. `send_focus_in()` sends a synthetic FocusIn.
- `INPUT_XTEST`: real input. The X server delivers pointer events to the window under the X pointer (X stacking order)
  and key events to the X input focus. Under gamescope the focused window (ours) is on top, so for XTEST:
  `set_input_passthrough(own toplevel, true)` (empty XFixes input shape: pointer events fall through our window),
  `raise_window(target)` and `set_input_focus(target)`.

### gamescope focus (from its source, `ValveSoftware/gamescope` ecc518b, 2026-10-30)

- gamescope's `steamcompmgr` is the X window manager. It handles MapRequest and ConfigureRequest (stacking requests are
  applied as asked). It raises a window on a `_NET_ACTIVE_WINDOW` client message, and nothing more: that message does
  not move focus.
- The focus pick (`GetPossibleFocusWindows`, `is_focus_priority_greater`): a candidate is mapped, InputOutput and not
  translucent. In Steam mode (`gamescope -e`, strategy SteamControlled) only windows with an app id count, plus Steam's
  own windows. The app id comes from the window's `STEAM_GAME` property, or from the process's cgroup or reaper parent.
  Windows with an app id come first. Among those the **most recently mapped** wins, then the most recently damaged.
  Without Steam mode every window's app id is its own id, so the newest mapped window wins.
- Steam's controls on the root window: `GAMESCOPECTRL_BASELAYER_WINDOW` (a window id, honoured first in Steam mode) and
  `GAMESCOPECTRL_BASELAYER_APPID` (app ids in order of preference).
- gamescope publishes `GAMESCOPE_FOCUSED_WINDOW`, `GAMESCOPE_FOCUSED_APP`, `GAMESCOPE_FOCUSED_APP_GFX`,
  `GAMESCOPE_FOCUSABLE_APPS` and `GAMESCOPE_FOCUSABLE_WINDOWS` (window, app id, pid triplets) on the root.
- When its pick changes, gamescope calls `XSetInputFocus` on the chosen window, sets `_NET_ACTIVE_WINDOW` and raises the
  window. A client's own `SetInputFocus` therefore lasts until gamescope's next focus change.
- gamescope gives real (Wayland seat) input only to its focused surface. XTEST input is routed by Xwayland's X-side
  rules. SendEvent bypasses both.

What follows for the app: launching the browser maps a new window, which takes gamescope's focus without Steam mode.
The helpers to take it back are on `X11WindowSource`:

| Helper | What it does |
|---|---|
| `remap_window(own)` | Unmap and map: newest mapped wins. |
| `gamescope_focus(own)` | `STEAM_GAME` on our window plus `GAMESCOPECTRL_BASELAYER_WINDOW`. `gamescope_release_focus()` undoes the root property. |
| `set_input_focus(id)` | X keyboard focus only. |
| `raise_window(id)` | Stacking plus `_NET_ACTIVE_WINDOW`. |
| `get_focus_info()` | gamescope's root properties, `_NET_ACTIVE_WINDOW`, the X input focus and our own window. |

Which of these is needed on the Frame is a device test (below). In XR the headset shows the OpenXR session whatever
gamescope shows, so gamescope's focus matters for the flat view and for routing real keyboard and mouse input.

### Browser command

```
flatpak run org.chromium.Chromium --ozone-platform=x11 --window-size=1920,1080 --window-position=0,0 --no-first-run \
  --disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-background-timer-throttling \
  --autoplay-policy=no-user-gesture-required [--kiosk] --app=<url>
```

- `--ozone-platform=x11`: gamescope also offers Wayland, but only X11 windows can be captured this way.
- `--app=<url>`: no tabs or address bar, and its own window (WM_CLASS instance from the URL).
- `--window-size` / `--window-position`: a 1920x1080 picture at the origin.
- The three `--disable-*background*` flags keep a window that Chromium thinks is hidden or occluded rendering and
  playing at full rate. Our window covers it in gamescope.
- `--kiosk` is optional: fullscreen with no browser UI. Without Steam mode, gamescope shows a newest-mapped window
  fullscreen anyway.
- If Chromium is already running (the user's profile), `flatpak run` hands the URL to that instance and exits. The new
  window belongs to the old process, and the instance's own flags stay in force. So find the window by "new since
  launch", not by pid. `close_window(id)` (WM_DELETE_WINDOW) closes it again. A separate `--user-data-dir` would force a
  new instance but lose the user's logins (iPlayer).

## Test project (`project/`)

`main.gd` lists windows, captures by `--title=`, `--class=`, `--window=` or `--launch=URL`, and draws the window on a
16:9 quad (its height follows the window). It forwards the desktop mouse and keyboard in the flat view. In XR, the right
controller's aim ray is the pointer, shown as a red dot on the screen. The trigger is the left button, squeeze the right
button, the stick scrolls, A sends Space and B sends browser Back. It uses the app's action map
(`project/xr/openxr_action_map.tres`, a copy of `app/xr/`). `--test-input`, `--focus=METHOD[+METHOD][@FRAME]`, `--shm`, `--input=xtest`, `--passthrough`,
`--close-on-exit`, `--screenshot=` and `--quit-after=` are for runs over ssh. Frame numbers count from the capture. See
the comment at the top of `main.gd`.

`input-test.html` is a page that lists the input it gets (mouse moves, clicks with `isTrusted`, keys, wheel, focus).
`device-test.sh` passes it to Chromium as a `data:` URL, so a screenshot shows whether input arrived.
`testwin/testwin.c` is a plain xcb client that animates and logs every event with its synthetic flag, for desktop tests.

## Device commands

Copy, from the repository root on the PC:

```
ssh frame mkdir -p spike05
scp build/out/godot.linuxbsd.template_debug.arm64.PLAYER_WINDOW spikes/05-window/device-test.sh spikes/05-window/input-test.html frame:spike05/
scp -r spikes/05-window/project frame:spike05/
ssh frame chmod +x spike05/godot.linuxbsd.template_debug.arm64.PLAYER_WINDOW
```

Then `ssh frame bash spike05/device-test.sh <test>`. The tests:

| Test | What it does |
|---|---|
| `inventory` | Read only, headless, maps no window. |
| `capture` / `capture-shm` | Flat, the first Chromium window, zero copy or forced copy, with a screenshot. |
| `input` / `input-xtest` | Launches the input test page and sends scripted input, then a screenshot. |
| `focus` | Takes `FOCUS=<method>` from the environment. |
| `xr` | In the headset. |

Logs and screenshots go to `~/spike05/logs/`. The binary's sha256 is in the status below.

## Verified without the device (WSLg, x86_64 build of the same code)

WSLg's Xwayland has Composite 0.4, DAMAGE 1.1, XFixes 5.0, XTEST 2.2 and MIT-SHM 1.2, but **no DRI3**. So the copy path
was tested there and the zero-copy path wasn't.

- Window list, including Weston's reparenting: the client window is found under its frame by `WM_STATE`.
- MIT-SHM capture (fd passing) of `testwin`: correct orientation and colour order. The click marker that `testwin`
  draws after our synthetic click shows in the captured picture.
- Damage-driven updates: a static window was read 2 times in 400 frames (the first picture, and the redraw after the
  click). An animated window at 30 fps was read 29.9 times a second.
- Resize (640x360 to 960x540: texture and quad follow), window destroyed (`window_closed`, capture stopped), `--launch`
  with a stand-in browser, and `close_window`.
- SendEvent input: motion, Enter, click with the right button state, keys with Shift for `H` and `!`, Enter, and the
  wheel. All arrived at `testwin` flagged synthetic.
- XTEST input: pointer and buttons arrived as real events (`synthetic=0`). Keys didn't, because WSLg's window manager
  takes the X focus back at once. Under gamescope that is different (above).
- `--headless --list` works, so the inventory needs no window.

## Device results

### Test 1: inventory (2026-10-31, `results/inventory.log`)

- **gamescope runs in Steam mode with the OpenVR backend.** The arguments include `--backend openvr`, `--steam`,
  `--virtual-connector-strategy PerAppId`, `--xwayland-count 2`, a nested 1280x720 picture and 1920x1080 output, and
  `--vr-app-overlay-key valve.steam.desktopgame`. Desktop windows are shown as SteamVR overlays, one virtual connector
  per app id. `:0` is Xwayland server 0.
- **The root window, with our VR app running in XR:**
  - `GAMESCOPE_FOCUSED_WINDOW` is the app's window, and so is `_NET_ACTIVE_WINDOW`.
  - `GAMESCOPE_FOCUSABLE_WINDOWS` holds two (window, app id, pid) triplets: the app and Chromium, both with app id 0.
  - `GAMESCOPE_FOCUSED_APP` and `GAMESCOPE_FOCUSABLE_APPS` are empty.
  - `GAMESCOPECTRL_BASELAYER_*` is not set.

  So `STEAM_GAME` and the base-layer properties aren't in use on the device.
- **X server:** X.Org (Xwayland) 24.1.9, with Composite 0.4, DAMAGE 1.1, XFixes 5.0, XTEST 2.2, DRI3 1.2, MIT-SHM 1.2
  (fd passing) and Present. All seven xcb libraries are in `/usr/lib`. The engine connected with every extension.
- **Chromium:** 154.0.8037.57 (Flathub, runtime org.freedesktop.Platform 25.08). Its window is 1920x1080 at the origin
  with **depth 32**, so the `AR24` format with alpha. Its `_NET_WM_PID` is the sandbox's pid (2). There are also a
  dozen SteamVR overlay windows (depth 32, pid of SteamVR).

### Test 2: zero-copy capture (2026-10-31, `results/capture.log`)

**Pass.** The open Chromium window ("New Tab", depth 32) was captured through the dmabuf path:

```
X11WindowSource: importing the window's buffers: 1920x1080 AR24, modifier 0x500000000000001, 1 plane(s), pitch 7680, offset 0.
```

- **Xwayland gives Turnip a UBWC buffer.** The modifier is Qualcomm's compressed (UBWC) one, 0x0500000000000001, with
  one memory plane, and Turnip imports and samples it. This is the same modifier as the decoder's `Q08C`.
- **The picture is right.** The screenshot showed the page with correct colours and orientation (not kept: it shows a
  third-party page).
- **The counters are as expected.** 1 import, 0 copies, one buffer lookup of 0.34 ms, 0 X errors, render 72 fps, no
  Vulkan errors.
- **An idle page costs nothing.** The New Tab page gave 1 damage event and 1 update, then 0 per second for the rest of
  the 20 s run.

### Test 3: synthetic input (2026-10-31, `results/input.log`, `results/input.png`)

**Pass: Chromium accepts SendEvent input completely.** The input test page was launched through the running Chromium
(a new app window). It was captured zero copy, and the scripted synthetic events were sent to it. The page recorded:

| Input | What the page saw |
|---|---|
| pointer | 6 moves, ending at the centre. The green dot is exactly at the window centre. |
| left click | `mousedown button 0 ... trusted true`, then `mouseup` |
| keys | `"H"` (KeyH, Shift), `"i"`, `"!"` (Digit1, Shift), `"Enter"`. The text box holds `Hi!`. |
| wheel | `wheel dy 120`, `dy 240`: Chromium merged the 3 notches. |
| focus | `window focus`, and `document.hasFocus()` true, without gamescope's focus. |

- **Synthetic events are trusted.** Chromium marks them `isTrusted` and handles them like real input.
- **The pointer doesn't need correcting.** The event at window pixel 960,540 arrived as `clientX/Y` 640,360. Those are
  CSS pixels: Chromium runs at a device scale factor of 1.5 on the Frame, and the 900 px text box spans 1350 of 1920
  device pixels. The page now prints `devicePixelRatio` and the viewport to make this explicit.
- **The capture kept up with the page.** The moving box gave about 67 damage events a second and 66 updates a second.
  There were 3 imports for the whole run: Xwayland cycled the window through 3 buffers, with 133 switches between them,
  each imported once. There were 0 copies, an average buffer lookup of 0.21 ms, and 0 X errors.

So `INPUT_SEND_EVENT` (the default) is the input method. It needs no X focus, no stacking and no input passthrough,
which also leaves gamescope's focus alone.

### Test 4: XTEST input (skipped)

Synthetic input works completely (test 3). XTEST would move the real X pointer, restack Chromium and take the X
keyboard focus. That is more intrusive, and no longer needed. The `input-xtest` test stays in `device-test.sh`.

### Test 5: gamescope focus (2026-10-31, `results/focus-self-remap.log`)

**Pass: `remap_window(own window)` takes gamescope's focus back.**

| | Before | After `remap_window` (60 frames later) |
|---|---|---|
| `GAMESCOPE_FOCUSED_WINDOW` | the launched page | our window |
| `_NET_ACTIVE_WINDOW` and X input focus | the launched page | our window |
| first in `GAMESCOPE_FOCUSABLE_WINDOWS` | the launched page | our window |

- **Launching takes focus, as the source predicts.** The page was launched through the running Chromium and mapped as
  the newest window. That gave it gamescope's focus, `_NET_ACTIVE_WINDOW` and the X input focus.
- **Unmap and map makes our window the newest mapped one.** All app ids are 0, so the newest mapped window wins.
- **The capture survived the change.** Zero copy continued at 65-89 updates a second, with 3 cached imports and
  0 X errors.

The app therefore calls `remap_window(get_own_window())` once the launched window is captured. `gamescope_focus` (the
base-layer property) isn't needed on this device.

### Test 6: in the headset (2026-10-31, `results/xr.log`)

**Pass (user report: "yep all good I think. Bluetooth keyboard types into field correctly").** The input test page was
launched and shown on the screen in OpenXR at 72 fps. It was also mirrored on the desktop panel. The user reported no
flicker and no orientation or colour problems.

- **The controller worked.** The pointer, trigger, squeeze, stick and A/B behaved as described, through the app's
  action map.
- **A physical keyboard needs nothing from us.** A Bluetooth keyboard paired to the headset typed into the page
  directly: gamescope routes real keyboard input to Chromium's window. The on-screen keyboard is only needed when no
  keyboard is paired.
- **Over the 3-minute run:**
  - 11222 damage events and 9886 updates.
  - 4 imports in all, 0 copies, 0 X errors.
  - Buffer lookups of 0.21 ms on average.
  - 3671 pointer and button events sent.
  - The page redraws at 55-60 Hz and the screen updated 45-50 times a second.
- **Deferred frames.** In about 1 frame in 6 the dmabuf was still being written when it was polled. The previous buffer
  stayed on screen for that frame (2114 deferrals in the run, never more than 3 in a row). This is the implicit-sync
  guard working: no tearing was seen.

## Conclusion

| Part | Result on the Frame |
|---|---|
| zero-copy capture of an X11 window | works: Chromium's UBWC buffers, each imported once, damage-driven |
| synthetic (SendEvent) input | accepted by Chromium as trusted input |
| real keyboard | reaches Chromium directly |
| taking gamescope's focus back after a launch | `remap_window(own window)` |

The browser source is ready for the app: see `app/docs/window-source.md`.

Open points:

- **No mipmaps.** Small text shimmers a little at a distance. A mip chain per changed frame would cost GPU time; render
  the screen larger or closer first.
- **Display size and scale.** Xwayland `:0` is 1920x1080 while gamescope's nested picture is 1280x720, and Chromium
  picks a scale factor of 1.5 from that. A larger browser window needs `--window-size` and maybe
  `--force-device-scale-factor`.
- **Multi-threaded rendering is untested.** The default single-threaded model is what was tested, as for
  HWVideoTexture.

## Binaries

| Binary | Engine commit | sha256 | What it is |
|---|---|---|---|
| `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_WINDOW` | `frame/window` 9818abd06e | `d1c4fe6ab86b6b6aeeff1c83da495552dd5dea97a71e2425af1645332b5afcc7` | the build tests 1-6 used |
| `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_ALL` | `frame/window-on-player` 0ecbc5407b | `e247c7021480ca11e8ae3f6b4ff68271b97f6ec445a3a1555ec1e170e169cd38` | the same module on `frame/player` 2b35386ef0, so hwvideo (with SMB) and x11window are in one build |
