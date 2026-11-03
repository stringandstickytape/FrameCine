# VR Video Player (app)

The application: the VR shell around the hardware video texture. It is a project for our engine (4.7) with the Mobile
renderer, XR and scripts only. It runs on the headset with our engine fork, which decodes in hardware through
`modules/hwvideo`. It also runs on any desktop build of the engine (4.7) with a generated test-pattern source, so every
projection mode, binding and menu control can be used without the device.

The app has two layers:

- **The core** is in `scripts/main.gd`. It covers playback, modes, screen, environments, the info overlay, settings,
  the playlist, command-line arguments, and direct controller and keyboard bindings.
- **The menu** is the pane (`docs/ui-design.md`), in `ui/`, the `UILayer` node in `scenes/main.tscn`. It calls only
  the core's public functions and its features hub, and listens to their signals, so it can be restyled or replaced
  without touching playback. Its look is one Theme resource (`ui/themes/default.tres`); see "The pane" below.
- **Without the menu,** delete the `UILayer` node. The bindings and arguments still drive everything.

The project has no `class_name` scripts and no imported assets (the pane's font is a saved FontFile resource, the
controller models load from raw files), so an export template
binary runs it straight from this folder with no `.godot/` cache. The engine then prints
`ERROR: Could not load global script cache.` once at start. It is harmless.

This README names no products or brands. Hardware and runtime identifiers that the code must use, such as
interaction profile paths, appear only as code.

## Run on the headset

Copy the folder next to the player binary (the `docs/` folder is optional):

```
scp -r app headset:<dir>/
```

On the headset, from `<dir>`:

```
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot_player --path app --display-driver x11 --xr-mode on
```

The menu panel starts open in front of you. Pick **Test patterns** to check each mode in the headset, or browse to
a file. Over ssh, give everything as arguments after `--`:

```
# The spike 03 film: hardware decode, documentary.ogg found as sidecar audio, full SBS guessed from name and size.
... --xr-mode on -- --file=~/spike01/streams/documentary_sbs.h264 --overlay

# Every test pattern in turn (A next, B previous), with the info overlay.
... --xr-mode on -- --dir=stub:// --overlay

# A folder in order, forcing the mode, environment and screen.
... --xr-mode on -- --dir=/run/media/<user>/films --mode=hsbs --env=cinema --screen-width=10 --distance=12
```

| Argument | Meaning |
|---|---|
| `--file=PATH` | open a file, or `stub://<mode id>` such as `stub://360_tb`. Its folder becomes the playlist. |
| `--dir=PATH` | play every video in the folder in order, then go on to the next at the end. `--file=` picks the first. `stub://` is the test patterns. |
| `--mode=MODE` | `flat`, `mono`, `sbs`, `hsbs`, `fsbs`, `tb`, `ou`, `hou`, `3d`, `180`, `180sbs`, `360`, `360tb`, `fisheye`, `dualfisheye` (`dfe`), or a full id such as `flat_sbs_half` or `fisheye_sbs_fov200`. The default is the guess from the file name and frame size. |
| `--fov=DEG` | fisheye field of view |
| `--screen-width=M`, `--distance=M`, `--height=M` | flat screen width, distance, and centre height above eye level |
| `--env=void\|room\|cinema` | environment |
| `--overlay` | info overlay on |
| `--labels-debug` | a 2 mm sphere at each controller label's anchor, to check the alignment in the headset |
| `--snapshot-dir=DIR`, `--snapshot-every=S` | in-headset snapshots on left bumper held + A (F12 on a desktop), and every S seconds: `head_<n>.png` (1920x1080 from the head), `left_<n>.png` / `right_<n>.png` (1024x1024 looking down at each controller's face from 25 cm, aim direction up) and `left_side_<n>.png` / `right_side_<n>.png` (from the outer side). The labels are held on meanwhile. An offscreen SubViewport renders only while a snapshot is taken. |
| `--controller-model=runtime\|ours` | in XR, the runtime's controller model with our printed labels (default), or our own model with the legends in its texture |
| `--dump-render-models=DIR` | write each runtime controller model to `DIR/<side>_controller.glb` and `.json` (see "Controller labels") |
| `--dev` | hot-reload: changed shaders, scripts, environments and resources in the app folder reload in place (`../docs/dev/hot-reload.md`) |
| `--listener=HOST[:PORT]` | connect out to the dev listener on a PC (`tools/listener.py`), send events and take commands (`../docs/dev/control-protocol.md`). Also `[dev] listener_host` in the settings. |
| `--pc-audio=HOST[:PORT]` | the film's sound on a PC running `tools/audio_sink.py`; the headset plays silent (`../docs/pc-audio.md`) |
| `--share` | the headset's folders on the LAN: downloads, uploads to Drop, screenshots (`../docs/share.md`) |
| `--remote` | the phone remote: a web page on the LAN, address and QR code in the pane (`../docs/remote.md`) |
| (no flag) | Assistant: System tab, "Assistant" (off by default). The headset serves an HTTPS API on port 47801 (`scripts/assistant/assistant_service.gd`): an AI assistant on the LAN reads the guide at `/`, pairs with a code the headset shows, and then takes a short list of commands, cards, voice and room changes (`../docs/assistant.md`). Works in a release build. |
| `--benchmark[=PATH]` | decode the biggest video in a folder (or PATH) for 10 s and log what the device can do. It also runs once by itself on the first run (`../docs/benchmark.md`). |
| `--party=host\|join\|join:IP` | watch party on the LAN; `--party-name=NAME`, `--party-pin=PIN` (`../docs/watch-party.md`) |
| `--tour=FILE`, `--kiosk` | run a tour: a room, a playlist and screen and camera moves from a JSON file (a path or a name in `user://tours`); `--kiosk` loops it for ever (`../docs/tours.md`) |
| `--dev-allow=MIN`, `--dev-code` | let the listener change the scene and settings for MIN minutes; let it run code (`../docs/dev/permission-ring.md`) |
| `--debug` | info overlay on, and every controller input logged (`--verbose-input` logs inputs only). Each run always logs the interaction profile the runtime bound per hand and when the aim pose is tracked. |
| `--no-ui` | start with the menu panel closed (the menu button opens it). |
| `--no-xr` | flat camera even when XR is up |
| `--look=YAW,PITCH`, `--camera-fov=DEG` | flat camera direction and field of view |
| `--quit-after=N`, `--screenshot=PATH`, `--screenshot-frame=N` | runs over ssh |
| `--shots=DIR`, `--ui-test`, `--window-test`, `--no-save` | tests, see below |
| `--browser-command="CMD ARGS"`, `--browser-match=TEXT` | run CMD instead of the browser and find its window by class (tests) |

Every flag and every setting, in one place: `../docs/USAGE.md`.

Settings are stored in `~/.local/share/godot/app_userdata/VR Video Player/settings.cfg`. They hold the screen size,
distance and height per environment, the environment, its room light, the volume, the A/V offset, the overlay
setting, the last folder, the saved network hosts, and the mode you chose for each file. An argument overrides its
setting for that run.

What to check in the headset with the test patterns:

- **Each eye sees its own word.** With one eye closed, the pattern and the overlay's top band say LEFT EYE in the left
  eye and RIGHT EYE in the right eye.
- **The green "3D" ring floats in front** of the picture in stereo patterns. If it sinks behind, the eyes are swapped.
- **Flat circles are round** in every layout, including half SBS and half TB.
- **Spherical patterns:** FRONT is ahead, RIGHT 90° is on your right, UP is overhead, and the 180° picture ends at
  ±90°.

## Controls

The action map is `xr/openxr_action_map.tres`, generated by `tools/make_action_map.gd`. It binds the headset's own
controller profile (`/interaction_profiles/valve/frame_controller_valve`), the generic controller profile
(`/interaction_profiles/khr/generic_controller`), two common third-party controller profiles and the simple
controller profile. On the headset, the runtime binds the headset's own profile. It does so only after the session is
focused, that is, with the headset worn.

The generic controller profile is a fallback. An early run, made with the engine's default action map, bound it. It
has no menu button. On it:

| Action | Buttons |
|---|---|
| next | right primary |
| previous | right secondary |
| menu | left primary, or right stick click |
| overlay | left secondary, or left stick click |

Trigger, squeeze and stick work as in the table below. Which physical buttons the runtime maps to primary and
secondary is up to the runtime. With `--debug`, each press is logged by action name, so one device run shows the
mapping.

Each XR run logs `XR: session_begun / session_visible / session_focussed ...` and
`XR right_hand: Interaction profile for /user/hand/right changed to ...`. If no profile is bound 5 s after focus, it
prints a warning.

The engine's XR interface stores pose actions on the tracker under short names: `aim_pose` becomes `aim`, `grip_pose`
becomes `grip`, `default_pose` becomes `default`. So the controller nodes use the pose `aim`. No other action may be
named `aim`, `grip` or `default`: the engine drops a second action with the same tracker name and prints only
`Action ... isn't part of an action set!`. The grip button's float action is therefore called `squeeze`.

| Control (headset) | Panel closed | Panel open (the pointer controller) | Keyboard / mouse |
|---|---|---|---|
| trigger | play / pause | click under the laser; laser off the panel: activate the focused control | Space, K / mouse click |
| thumbstick left / right | seek -/+10 s, repeats while held | slider under the laser: move it; laser off: move the focus | Left / Right, J / L |
| thumbstick up / down | screen farther / nearer (flat) | scroll under the laser (a slider: move it); laser off: move the focus | Up / Down / wheel on the panel |
| A (right) | next video in the folder | same | N |
| B (right) | previous video, or the start of this one after 3 s | same | P |
| Y (right), while the right hand points | an agent's terminal on or off; with none running, start the last one used | nothing | - |
| menu (right), view (left), or right stick click | open the panel in front; this controller points | short press: close; hold 0.6 s: recentre | M, F3 (hold: recentre); Esc closes |
| left stick click | info overlay on / off | same | Tab, F1 |
| grip, hold and point | move the flat screen (stick: nearer / farther); in 180/360, turn the sphere | held 2 s on the panel in dev mode: allow remote changes for an hour | G held + mouse, wheel |
| grip, tap | screen (or sphere front) to where you look | same | R (also recenters the view) |
| - | - | - | V / O / H / X: next projection / layout / half / swap eyes; E: next environment; drag: look; F12: screenshot |

While the panel is open, the other controller keeps the "panel closed" column. While a desktop window from the
Browser place is on the screen, the right controller, the mouse and the keyboard work that window instead. See
"Browser (desktop windows)" below.

Third-party controller with A/B: A next, B previous, either stick click the menu (the overlay is in System and on
the keyboard). Third-party controller with A/B/X/Y: A/X next, B/Y previous, the left menu button or the right stick
click for the menu, the left stick click for the overlay.

**Playback pauses when the session loses focus.** When the runtime's dashboard opens, the session goes from FOCUSED to
VISIBLE. When the headset comes off, it goes on to SYNCHRONIZED. Either way, audio and video pause together.
Otherwise our frame loop slows while the audio clock runs on, and the video drops frames to catch up (31 in one test).
When the session is FOCUSED again, playback resumes 0.3 s later, so a quick dashboard flick doesn't stutter. It
resumes only if the app paused it: a film the user paused stays paused, and any play or pause meanwhile cancels the
resume. The overlay says "paused (headset not in focus)". `--ui-test` simulates the session states.

### The panel

The interface is one object, the panel (`docs/ui-design.md`, "Revision 2"): 740 x 600 px, 38 x 31 cm at the
default `[pane] scale = 1.6` (1 is 24 cm), about 35° wide at 0.6 m, in front of the headset. It replaced the pane
carried by the left controller (with its glance state, reading pose and freeze) after the first headset run, at the
size that read well there. Code: `ui/ui_layer.gd`
(open / closed, pointer, menu button, wiring), `ui/pane.gd` (the quad, halo, fades, pointer events),
`ui/pane_pose.gd` (front pose, head follow, the menu button's press / hold / release), `ui/pane_ui.gd` (header, seek
bar, transport, tabs, footer) and one script per tab.

- **Open and close:** the menu button on either controller opens it about 0.6 m in front of the head (`[pane]
  distance`), at eye height, facing the head, wherever the head points. It is always level: its top edge stays
  horizontal, whatever the head's roll. Only looking nearly straight up or down (over about 64°) does it take the
  head's up, so lying back and looking at the ceiling puts it overhead, the right way up for the face. A short press
  closes it. At launch it is open (`--no-ui`: closed). Opening a file from it closes it, after the file is open
  (network, browser).
- **Recentre:** hold the menu button 0.6 s (`[pane] recentre_hold`) while it is open: it comes back in front of the
  head. On a desktop, hold M.
- **World-locked:** once placed it stays put (`[pane] world_locked = true`). With `false` (System, Panel, Follow my
  head) it follows the head lazily: nothing until the head is 25° away, then a smooth catch-up (0.35 s).
- **Pointer:** the controller whose menu button opened it. Its laser shows only while it is aimed at the panel, with a
  dot where it hits; each new target gives one haptic tick. The trigger clicks; the stick scrolls the list under the
  laser, or moves the slider under it (up or right: more); poking the panel with the controller's tip clicks too.
  With the laser off the panel, its stick moves a focus highlight (1 px accent outline) and its trigger activates it,
  so aiming is never needed. The other controller keeps its direct bindings and its position never matters. If the
  pointer controller loses tracking while the other one has it, the other one points. Left-handed (System, or
  `[accessibility] left_handed`) makes the left controller the pointer at launch.
- **Header and transport:** "Now playing" with the chapter and, on the right, the clock, time left with the end time,
  and the headset battery (plus a low controller battery, or "Listening"); the title, the time (LIVE for a live
  stream, "· 8x" while scanning), the seek bar (chapter ticks; with System, "Seek bar pictures" on, a picture of the
  hovered time under it), and Previous, -10 s, Play, +10 s, Next, plus 4x and 8x to hold for scanning where the
  source allows it. A stream that can't seek has no seek bar or skips.
- **Tabs:**
  - **Files:** places (Test patterns, Network with "Find hosts on this network", Media servers (UPnP), Browser,
    Queue with Shuffle, Repeat, Play on and Gapless, Favourites, Search, the local folders); rows with name, resume
    marker, duration or size and a chip (mode, PICTURE, MUSIC); "In corner" plays the next pick as picture in
    picture; the URL form plays stream URLs (udp://, http video) and opens the rest as pages.
  - **Picture:** mode diagrams, Auto and its reason, half, swap, a folder rule (use, clear), the fisheye lens; 2D from
    3D, depth, soft edges; size, distance, height, size in degrees and its presets, curvature (0 to 100 %), zoom,
    auto crop of bars (its state in the footer), Follow my head, Lying down; horizon (180 / 360); picture controls
    with sharpen, deinterlace, film grain and gate weave; HDR (only for HDR files); slideshow; frame step, the A-B
    loop and Screenshot; the Corner film group while one plays. A help line in plain words under each control whose
    name does not say what it does (`ui/help_texts.gd`; the Sound tab has them too).
  - **Sound:** tracks with their flags, volume, A/V offset with Calibrate, Live delay, speed, night mode (on engines
    with it), speakers in the room, and Play on a PC with its address.
  - **Subtitles:** Replay 10 s, tracks, the second track, Look (size, place, offset, nearer, background), delay,
    subtitle files next to the video, and Script: find a line or the lines around now, from a chosen track, with a
    progress line while the film is read.
  - **Room:** the environments as rows (photo and glTF rooms included; "Use this picture as the room"), seat (next,
    previous, own spot, and Pick a seat with the laser), floor reflection, effects (bias light, react to the film,
    projector beam), time of day (outdoor rooms), room light, dim while playing, reset screen, recentre, the
    showing (curtains, up next, intermission, crossfades), the sleep timer and the watch party (host, join, people,
    the host's file not here with Find it).
  - **System:** info overlay, stats; Panel (size, distance, hold to recentre, Follow my head, Left-handed, Reset layout);
    accessibility; test patterns, calibration cards, bandwidth meter, benchmark; a running tour; controllers
    (haptics, jog wheel, zoom lens, seek bar pictures); Hardware video ("Hardware 10-bit video: on (P010 ...) / on
    (Q10C ...) / off", read-only, Details); phone remote and Share files with their QR codes; dev tools; about.
- **Pick a seat:** the laser goes to the floor, a ring marks the seat it points at, the trigger moves you there, B
  or menu cancels.
- **Push-to-talk:** with the dev link on, the pointer hand's bumper (labelled TALK) records while held; "Listening"
  shows in the header and the footer, or in the world while the panel is closed.
- **Keyboard:** letters, a symbols layer, Shift (twice locks), caret keys, Del, Clear, Paste, Done, and a row of whole
  strings per form (https://, .com, udp://@: for web pages and streams; smb://, .local for hosts). The same form,
  with other words, asks for the watch party's name and PIN and the PC's address.
- **Notices:** a low controller battery (#75; read from the peripheral batteries under `/sys/class/power_supply`,
  15 % and 5 %) shows in the footer when the pane is open, else as a quiet line in the world where you look
  (`ui/world_toast.gd`). `--fake-controller-battery=left:12` stubs it on a desktop.
- **Watch-along card** (#54, `ui/watch_card.gd`): the PC link's `card` command shows a short answer on a small panel
  beside the screen; the right laser and the trigger dismiss it, or it times out. `card_clear` takes it away; the
  event `card_dismissed` says how it went.
- **Footer:** the mode and how it was chosen (with auto crop's state while it is on), the item count, and short toasts with an action ("Resumed at 0:42:17"
  with Start over, a remote change with Undo).
- **Theme:** `ui/themes/default.tres`, written by `tools/make_pane_theme.gd`, holds every colour, size and font, with
  the custom parts' tokens under the theme type "Tokens" (`ui/pane_style.gd` reads them). No pane script writes a
  colour or a font; `tests/test_pane.gd` checks. Another theme is another `.tres`: `[pane] theme = "res://..."`.
  `[pane] scale` scales the panel's physical size (1 = 24 cm wide, default 1.6). The font is Inter (SIL OFL 1.1,
  `ui/fonts/LICENSE.Inter.txt`) with tabular numerals.
- **Alpha:** the panel quad maps alpha as 1 - (1 - a)^2.2, so the doc's 94 % surface and the fades look as they
  would composited in sRGB. Blended in linear light as given, a bright film showed through at about a quarter of its
  brightness.

The stick clicks are fallbacks for the menu and view buttons, in case the runtime keeps those for itself.

The **info overlay** shows the file (and its place in the playlist), mode, source (for files: `hardware`,
`hardware (10-bit)` while a 10-bit file plays in hardware, `hardware (VP9)` or `hardware (VP9, 10-bit)` for VP9 in
hardware, `software` or `software (10-bit)`) and frame size, time and duration,
decode fps, dropped frames, render fps, battery (`/sys/class/power_supply`) and environment. Its top band shows LEFT
EYE or RIGHT EYE per eye. It sits in the world under the flat screen's bottom-left corner, scaled to about 20° wide at
the screen's distance. In 180/360 it sits 2 m ahead and below eye level. It redraws 4 times a second while shown.
It is hidden while the pane is open, because it draws on top of everything and would cover the pane's controls.

### Hardware 10-bit video

10-bit HEVC (HDR10 included) plays in hardware with Valve's stock driver: the engine reads the decoder's compressed
10-bit output (Q10C) through the GPU's YCbCr sampler (`docs/decisions.md` D14). When the system's decoder driver offers
linear P010 (mainline Linux 7.2 does), the engine takes P010 first. Without either, 10-bit up to 1080p plays in
software and larger files are refused with a reason. There is nothing to set up: the patched driver and its one-time
setup were removed (`docs/decisions.md` D21).

`scripts/play/hw_video.gd` (`main.features.hwvideo`) only reads what the engine found. At start, once the pane is up,
it reads the decoder's formats once on a worker thread (`V4L2Decoder.is_p010_available()`, which the engine keeps)
and logs `HW video: 10-bit path ...`. The System tab's Hardware video row (`ui/hw_video_row.gd`) says "Hardware 10-bit
video: on (P010 from the system's video driver)", "on (Q10C through the GPU, stock driver)" or "off: 10-bit plays in
software", with Details: P010 offered, Q10C read, why Q10C turned off in this run (if it did), the decoder's formats,
and hardware VP9. `main.features.hwvideo.status()` and the read command `hwvideo_status` give
`{path, text, p010, q10c, q10c_off_reason, decoder_formats, hw_vp9}`. The overlay says `hardware (10-bit)` while a
10-bit file plays in hardware.

**VP9 in hardware** (engine PLAYER_VP9 and later): `[hwvideo] hw_vp9` (default true; `scripts/play/hw_video.gd` reads
it at start) goes to `HWVideoSource.hw_vp9`, which `HWVideoSource.apply_hw_vp9()` sets on every `HWVideoTexture` the
app makes (playback, seek thumbnails, the benchmark). The engine keeps one hardware VP9 session at a time, because two
crash the headset's decoder firmware: a second VP9 video (picture in picture, the gapless next item, thumbnails, a
crossfade) plays in software, up to about 1080p, and its overlay says `software`. If a VP9 hardware session fails, the
engine goes on in software by itself from the same position. `HWVIDEO_HW_VP9=0` or `1` in the environment overrides
the setting. Older engines ignore it.

### Controller labels

Each controller is drawn with a short text label on every input the bound profile maps to an action. The label text
comes from one table in the core, `CONTROL_LABELS` in `scripts/main.gd`, with one text for the pane closed and one for
the panel open. Which input carries which text comes from the action map, for the profile the runtime bound to that
hand. So if a binding changes in `tools/make_action_map.gd`, the labels follow. On a desktop the labels preview the
headset's own profile. When two actions share an input, the label has both lines; a stick click shows as "PUSH: ...".

The labels are always there, like print on the plastic. They change with the state: the panel open, a captured window, a
terminal. Nothing runs for them per frame. Our own model has its legends in its texture, so the print stays off while it
shows.

Labels are printed on the controller. Each label is a small mesh that lies on the model's real triangles, a fraction
of a millimetre above them, so the text follows the plastic like print (`scripts/xr/label_surface.gd`). The text comes
from one atlas of distance fields, shared by every legend on both hands, which Godot's font code makes on the CPU
(`scripts/xr/label_font.gd`), and `shaders/controller_label.gdshader` works out each letter's edge per pixel. So a
legend needs no texture of its own, stays sharp up close, and small or at an angle it is filtered as the true coverage
of the pixel. The print is unlit: near-white on the plastic.

People bring a controller close to read it, so the legends are made to be read from about 15 to 25 cm. They are as big as
the plastic round them allows, with about 1 mm clear of the rim and of the controls, and they are placed by rule from the
controls' measured bounds (`tools/label_layout.tscn`, `--auto`). The layout is solved on the right hand and mirrored to the
left, with the text still reading the right way. Each group has one size and each spot is kept for the longest text that
group has in any state. The face legends run parallel to the lines on that hand's menu or view button, which is the
button's top edge too. `tools/menu_direction.gd` measures that from the button: it lies 5.16 degrees from the aim pose's
right, the outer end towards the front on both hands, so the two hands turn opposite ways, as mirrors do:

- **Thumbstick:** two lines on a 6 mm line (capitals 3.6 mm), on the face in front of the stick and towards the middle. The
  stick stands tall and hides what is just in front of it, and the plastic behind it is too short for two lines.
- **Menu and view:** a 4.8 mm line (capitals 2.9 mm), behind the button, on the same offset on both hands.
- **A and B:** a 5.2 mm line (capitals 3.1 mm), each at one offset from its button: behind it, to the outer side. The next
  legend or the rim would stop anything larger.
- **Trigger and bumper:** a 6 mm line, on the head's outer side wall, one under the other, centred on one point.
- **Grip:** a 5 mm line, on the handle's inner side, at the button.

The walls keep the controller's own axis.

The runtime model is drawn black and white, as the real controller looks. `controller_model.gdshader` keeps the atlas's
plastic near black, with a rim and a faint sheen so the shape, the seams and the stick still read in a dark room. On the
buttons (`INK_PARTS` in `controller_visual.gd`) the moulded art turns white, the white of the printed legends: X, A, B, the
menu lines, the view icon and the Steam mark. The atlas holds plastic up to 0.098 and art at 0.404 with nothing between,
so a straight ramp on its value separates them, and no new texture is needed. The body stays out of that, as its atlas
has a small round port near the menu button. Our own model and the hand-built one keep the shader's defaults.

Y has no legend. Its cap carries a sparkle, a four-point star with a smaller one beside it, for the agent's terminal, the
only colour on the controller: one gradient, blue through violet to pink, from the big one's foot to the small one's tip.
The letter is part of the runtime model's own texture, so printing over it would let it show through at an angle. Instead
the shader paints the letter out of that one cap's picture, where it samples the atlas, and draws the sparkle there. It
stands where the letter stood, at the letter's height, with about its ink. It uses no texture, mesh or draw call of its
own, runs nothing per frame and moves with the cap. The Y mesh's UVs tell whether this is the atlas we know: another
atlas keeps its letter, in white. Our own model keeps its printed Y.

On the face, the text's top points forward, so it reads from above and behind as you hold the controller. On the
walls, the text's top points up. A legend first turns to the surface under it, so a slope does not stretch it, and its
glyphs are spaced along that surface, so a curve does not either. What breaks away from the smooth surface is a step
(the wells round the buttons, seams): the print bridges it and does not dive in. Each legend belongs to the part most of
it lies on. On the headset's models that is always the body, on purpose: a button goes down when pressed, and print
beside it must not. Legends on one part are one mesh under that part's node, one draw call, usually one per controller.
Placement is computed when their texts change and when a model arrives, never per frame. The meshes are built only for
what changed, and kept per legend, so a state seen before costs almost nothing.

`--labels-debug` puts a 2 mm sphere at each label's anchor, drawn through everything. Pink marks a face control
(its centre laid onto the face plane); cyan marks the trigger, bumper and grip. Each run also logs the anchors and
text centres relative to the aim pose, once the runtime model sits at the hand
(`XR right labels (aim space, m): a anchor (...) text (...)`). With a runtime it also logs what the print comes to in
the eye's image (`XR right print: eye image (...), N pixels per degree at its centre; ...`): that image's size is what
limits any print.

`tools/label_proof.gd` (`tools/label-proof.sh MODEL_DIR OUT_DIR`) proves the labels on the PC before they go to the
headset. It draws the dumped models with the app's own code on the Mobile renderer, into an image the size of the eye's,
with the figures measured live on the Frame (1728 px, tangents 2.872 by 2.903: 10.5 pixels per degree at its centre) and
the project's MSAA and render scale. It gates the poses of a controller lifted to read it, 15, 20 and 25 cm from the eye,
each over a small wrist motion, and writes an actual-size crop per control, a view of all the print and a sheet per hand.
The limits there: at least 5 pixels from the top to the foot of a capital, stretch, contrast, how much of the legend is
in sight and shimmer. It also measures the print as laid: each face baseline within 1 degree of that hand's button, which it
measures for itself from the model, each wall baseline within 1 degree of the controller's axis, no glyph dropped, and
within 0.5 mm: A and B's offsets from their buttons, a legend and its mirror on the other hand, the trigger
and bumper rows. The views at 30 and 45 cm and the grazing view are reported and do not fail the run, nor does how far a
legend leans in the picture or parts from the button's lines there, which change with the view however square it lies.
In the face poses it also takes the sparkle: at least 5 pixels tall, 4.5:1 against the cap as the print is, in
sight, and on the same cap with the sparkle off, nothing of the letter left (1.05:1 at most against the pixels round it). Never commit its output: it shows the
runtime's model. It cannot show the lens, the panel or the runtime's foveation: Valve's `fdm_injection` layer attaches to
the app's swapchains though the app asks for no foveation, and it can only lower the density away from where the eye
looks. `--labels-debug` logs the real values for `--eye` and `--tan`.

The controller itself is one of two things:

1. **The runtime's render model**, through `XR_EXT_render_model` and `XR_EXT_interaction_render_model`. The project
   setting `xr/openxr/extensions/render_model` is on, and each hand gets an `OpenXRRenderModelManager` local to its
   aim pose. When a model arrives, the hand-built mesh hides. Labels then anchor to model nodes whose names match an
   input. The device's models have `body`, `bumper`, `trigger`, `thumbstick`, `dpad`, `status` and `button_a`, `_b`,
   `_x`, `_y`, `_grip`, `_menu`, `_view`, `_system`. A label anchors at the centre of its node's mesh bounds, not
   at the node's origin, because in these models every node's origin is the model's origin. The face plane is
   fitted through the face buttons and points away from the body. Inputs with no matching node keep the hand-built
   anchor.

   The labels are children of the model's node and are placed in the model's own space. On the first tracked frame
   the model may not yet sit at the hand, because the manager compensates the aim pose a frame later. Labels placed
   then in hand space ended up 0.65 m away in the first worn test. As children of the model they follow it wherever
   it is. The text's forward direction is the aim direction in model space. It is taken once the model sits within
   0.3 m of the aim pose; until then, the direction from the body to the face centre is used.

   `--dump-render-models=DIR` writes each hand's model as the runtime gives it, for laying out labels offline. The
   `.glb` has the node names, hierarchy, meshes, the runtime's own materials and textures, and each part's pose; it is
   written as soon as the model arrives, before the app makes it unlit. Two seconds later, `<side>_controller.json`
   lists every node with its local and model-space transform, mesh bounds (local and model space), triangle count and
   material names, plus the model's pose relative to the aim pose and the aim and grip poses. The model is Valve's
   asset: copy the files to `app/docs/reference-models/`, which is gitignored, and never commit them.

   **Our layout.** `tools/label_layout.tscn` lays the legends out on the dumped model, and saves them to
   `xr/controller_labels_layout.tres` (`scripts/xr/label_layout.gd`). Each entry is per hand and per input (the
   physical spot; the text still comes from the bindings). It holds the print's transform in the model's own space,
   the line height, how far to look for the surface, and the room along the text. When a model is attached, every input in the layout uses its entry. Inputs not in
   it, and the hand-built controller, keep the placement computed from the model. The tool's `--auto` places each
   legend by rule from the controls' measured bounds. On the face plate the text lies flat on the surface under it. Its
   baseline runs across the controller, the top of the letters towards
   the aim, along the hand's menu or view button. On the side walls it runs along the controller, the face up. `--render=DIR` writes a face view and both
   side views per hand. It keeps each input's spot for its largest legend in any state, on either hand, lays every text
   for real and turns down a spot where one would not lie flush, is hidden from the reading views or is turned too far
   from the eye. The committed layout (both hands, 12 legends) is `--auto` on the device's models, unchanged. The face frame is the
   aim pose's: on these models the face plate is square to the aim pose's up, which is 40 degrees from the model's
   own up. The left dump was written while the left hand was untracked, so its frame is the right one mirrored (the
   models are exact mirror images). Legends land on the body only, never on a part that moves (trigger, bumper,
   grip, buttons). Rays are cast in millimetres: `Geometry3D.ray_intersects_triangle()` takes a triangle with a
   tiny determinant as edge-on, which in metres drops every triangle with edges under about 3 mm. Run the tool with
   the Windows desktop engine:

   ```
   godot --path app res://tools/label_layout.tscn                                  # interactive (keys in the script header)
   godot --path app res://tools/label_layout.tscn -- --auto --save --render=DIR    # DIR outside the repository
   ```

   The log prints every node name of the model (`XR right render model: N nodes [...]`). Once placed, it prints each
   label in model space and relative to the aim pose (`XR right labels (model space / aim space, m): ...`). Expect a
   few centimetres. It also says when the extension is not active.

   The model's glTF materials are lit PBR, and the environments have no lights, so the model rendered black. On
   arrival each material is swapped for `shaders/controller_model.gdshader`. This repeats whenever the runtime
   (re)loads the model's scene, and the log counts the mesh instances done. The shader is unlit and keeps the base
   colour, albedo texture, vertex colours and emission. It fakes a soft key light fixed to the view and a rim, and
   lifts dark plastic slightly, so the model reads in every environment. The runtime still animates the buttons,
   stick and trigger.
2. **Our own controller model** (`models/controllers/`), with the legends printed into its texture. It shows on a
   desktop, in XR until the runtime's model arrives, and in place of it with `--controller-model=ours`. See "Our
   controller model" below.
3. **A hand-built low-poly controller** (`scripts/xr/controller_visual.gd`) when neither is there. It is one mesh
   with baked shading, so one draw call per hand. Its anchors are named like the inputs above.

The fallback layout follows the headset maker's controller drawing. Looking down at the face:

- **Right controller:** thumbstick on the inner side, A/B/X/Y diamond on the outer side (Y front, X inner, B outer,
  A back), menu near the front edge, system button behind the face buttons.
- **Left controller:** the mirror image, with the d-pad where A/B/X/Y are and view where menu is.
- **Both:** the bumper sits above the dual-stage trigger at the front of the head, and the dual-stage grip button sits
  on the inner side of the handle, just under the head.

No source gives dimensions. The mesh assumes a face 65 mm wide and 60 mm deep and a handle tilted 40° back. Positions
on the face are measured from the drawing at that scale. The sources are listed outside the app, in
`../docs/controller-layout-sources.md`, because the app names no products or brands.

### Our controller model

`models/controllers/<side>_controller.glb` is a low-poly model of each controller, about 4,700 to 5,000 triangles
in 8 to 11 parts named like the runtime's nodes. Its legends are printed into the texture, so they are always
there, like print on plastic, and need no print meshes. The texture changes with the state: the normal legends, the
menu's (`_menu.png`) and those for a captured window (`_window.png`), all on the same UVs. The face buttons carry
their letters. The parts move with the input, like the runtime's model: the trigger turns about a hinge at its top,
the grip button moves in with the squeeze, the stick tilts and sinks on a click, and bound buttons sink. Pivots come
from each part's mesh; the ranges are guesses until compared with the runtime's model (`tests/test_controller_motion.gd`).
Buttons without a bound action (X, Y and the d-pad in the shipped map) don't move.

It is derived from the controller CAD the headset maker publishes (STEP files) and is under that CAD's licence,
CC BY-NC-SA 4.0: non-commercial, share-alike, attribution. See `models/controllers/LICENSE-controller.md`. The CAD
itself is not in the repository.

How it is made (`tools/controller_model/`, steps in `cad/run.sh`):

1. `cad/`: download the CAD, tessellate every solid with OCP (cadquery), split the surface into parts, decimate per
   part (pymeshlab), smooth-shade with hard edges over 30°.
2. `export_legends.gd`: the legend textures and decal boxes from our layout, for each state, plus the button
   letters.
3. `bake.py`: register each hand to the runtime model dumped from the device (part centroids, then ICP (iterative
   closest point) on the shell; about 0.75 mm mean distance, part centres within about 1.6 mm), so that it fits the
   same hand poses and the same layout. Then unwrap all parts into one 2048 px atlas (xatlas, 0.1 mm per texel,
   about 41 texels per legend line), paint the plastic and print the legends through their decal boxes, as
   Godot's decals would. `controllers.json` holds each model's pose relative to the aim pose, from the dump (the
   left one mirrored from the right, whose dump was tracked).

Neither the CAD nor the runtime dump is committed. Rerun the steps when the layout or the legends change.
`render.gd` draws `docs/screenshots/controller_model_<side>_{face,outer,inner}.png`.

### Network shares (SMB)

The menu's Files tab has a **Network** place. It lists saved hosts, each opening as `smb://host` (its shares) or
`smb://host/share`. "Add host" opens a form for host, share, user, password and domain, with the on-pane keyboard for
the laser; "Edit hosts" picks a saved host to change or delete. Hosts are saved under `network/hosts` in
`user://settings.cfg`.

The engine's `MediaBrowser` lists shares and folders, and `MediaSource` opens `smb://` files, in our player build
(engine 893d2d87a8 and later). Both calls block, so neither runs on the main thread:

- **Listing** runs on a `WorkerThreadPool` task. "Loading..." shows meanwhile, and the answer is dropped if you have
  already moved on. The app keeps one `MediaBrowser` per host, because a browser keeps its connection open. Later
  listings then take milliseconds instead of a new login. A per-host lock keeps two listings off one browser.
- **Opening** an `smb://` container file connects, logs in and probes on a worker thread. The screen hides, and the
  panel stays up saying "Connecting..." (the overlay says "Connecting to host ...") until the file is open. Opening
  something else meanwhile drops the late answer. If the open fails, the test-pattern stand-in shows the engine's
  reason, such as "No answer from 10.255.255.1 within 8 s." An unreachable host takes up to 8 s per step.
- **Credentials:** before each listing and open, the app gives the host's saved credentials to the engine with
  `set_smb_credentials(host, user, password, domain)`. The engine keeps one registry, keyed by host. After a host is
  edited, its browser is dropped so the next listing logs in afresh, because an open connection keeps its old login.
  A deleted or renamed host's credentials are removed from the registry.
- **Errors** come from `get_last_error()` as user-ready sentences that never contain the password, for example
  "Access denied: HOST refused the user name or password."
- **Playlist:** the browser passes the folder's video files as the playlist, so the share is not listed again.
- **Overlay:** for network files it adds the network rate, buffered megabytes, stalls and reconnects, from
  `MediaSource`'s `net_*` stats. After 5 failed reconnects the source stops with the reason.

On an engine build without `MediaBrowser`, a simulated browser answers with a small fake tree after 400 ms, and the
list says "(simulated)". In it, `offline.invalid` fails to connect and the password `wrong` is refused, so the error
rows can be tested. The pane input test's share-browsing checks run only on such a build; with a real `MediaBrowser`
they check the lookup error instead.

### Browser (desktop windows)

Verified on the device by the user on 2026-10-31. The Files tab has a **Browser** place after Network. It shows web pages and other desktop windows on the screen,
through the engine's `X11WindowSource` (fork branch `frame/window`; `docs/window-source.md` has the API and the device
results). The browser's sound goes through the desktop's audio server, so the app handles only the picture and the
input. The place lists:

- **Stop showing: TITLE**, while a window is on the screen.
- **+ Open a web page...** A URL field with the on-pane keyboard, filled in with the last URL opened. "Open" starts
  the browser on it, "Save page" adds it to the list. Text without a scheme gets `https://`.
- **The saved pages.** One click opens the page; "Edit pages" picks one to change or remove. No pages are built in.
  They are saved under `browser/pages` and `browser/last_url` in `user://settings.cfg`.
- **Desktop windows**, the mapped windows of the X display except our own, browser windows first. One click captures
  a window as it is.

Opening a page (`browser://<url>`) runs the browser with the command from `docs/window-source.md`:
`flatpak run org.chromium.Chromium` with the flags for X11, a 1920x1080 window, no throttling in the background, and
autoplay, then `--app=<url>`. The app notes the windows that exist before the launch. It then looks every 0.25 s, for
up to 20 s, for a new window whose class contains "chrom". It does not match by process id, because a browser that is
already running opens the window in its own process. Once the window is captured, the app calls
`remap_window(own window)` so that the desktop gives the focus back to the player. The panel stays up saying
"Starting the browser..." in its footer until the window is captured, then hides. If no window comes, it says so.

The picture is one RGB texture with sRGB values. `video.gdshader` takes it when `rgb_source` is set, instead of the
NV12 planes. The crop, the eye selection and the sRGB decode are the same as for video. The screen is flat 2D with the
window's aspect, and the mode is not remembered for windows. The other modes can be picked from the pane. The pointer
works only in flat mode.

With the laser off the pane, the window has the input:

| Control | In the window |
|---|---|
| right laser on the screen | the pointer, with a dot where it hits. The point on the quad times the window size gives window pixels; the page's own 1.5 scale needs no correction. |
| right trigger | left button, held as long as the trigger, so drags work |
| right grip, tap | right button. Holding the grip still moves the screen; a tap off the window still recenters it. |
| right stick up / down | scroll wheel, about 12 notches a second at full tilt |
| right stick left / right | Left / Right arrow keys, repeated every 0.4 s while held. Web players seek with them. |
| A | Space, which plays and pauses most web players |
| B | the browser's Back key |
| left trigger, X, Y | nothing |
| menu, view, bumper, left grip and stick | as for video |
| desktop mouse over the screen | the window's mouse: move, buttons, wheel. A drag off the screen looks around. |
| keyboard | types into the window. Only F1 (overlay), F3 (menu) and F12 (screenshot) stay with the player. |

Input is sent as synthetic X events, which need no focus. A Bluetooth keyboard paired to the headset types into the
page directly. An on-screen keyboard for the page is not done yet. The controller labels change to the window's
meanings while it has the input: CLICK, R-CLICK, SCROLL / KEYS, SPACE and BACK on the right controller.

The player's play and pause do nothing to the page. Space would toggle the web player, so an automatic pause on focus
loss could start a paused video. A to play or pause is the control for the page.

The overlay shows the window title, the capture path (`dmabuf` is zero copy, `shm` is the copy fallback), picture
updates a second, damage events a second, the average fetch time and the input event count.

**Closing:** opening something else, "Stop showing" or quitting closes the source. A window the player launched gets
`close_window()` (WM_DELETE_WINDOW, as a close button sends). A window the player only captured stays open. If the
window closes by itself, the source ends and the pane docks in front.

On an engine build without `X11WindowSource` (Windows, the plain player build), the place says so and opening a
`browser://` or `window://` path shows the test-pattern stand-in with the reason. Use the `PLAYER_ALL` build on the
device, which has both the player and the window modules.

## Structure

```
project.godot            Mobile renderer, XR on, shader globals for the environments
scenes/main.tscn         XR origin + camera + hands, flat camera, environment root, screen, player, overlay, UILayer
scripts/main.gd          the core: view, bindings, arguments, playlist, modes, screen, environments, settings, overlay
scripts/window_pointer.gd  input for a captured window: right laser as pointer, buttons, keys, desktop mouse
scripts/video_mode.gd    projection / stereo layout / half / swap / fisheye FOV; ids; file-name guess; --mode= forms
scripts/video_screen.gd  the video surface: quad (flat) or sphere / cap (spherical), one ShaderMaterial
scripts/projection_meshes.gd  equirect 180/360, fisheye and dual fisheye 360 meshes, inside-out, per-vertex UVs
scripts/playback_controller.gd  current source, audio player, A/V clock (audio master, as spike 03)
scripts/app_settings.gd  user://settings.cfg (batched writes)
scripts/info_overlay.gd  world-space info text with the per-eye label; battery
scripts/video/           VideoSource, HWVideoSource, StubVideoSource (+ test_card.gd), WindowVideoSource, factory,
                         video extensions
scripts/xr/xr_hand.gd    one controller: trigger/grip hysteresis, buttons, laser, render model manager
scripts/xr/controller_visual.gd  hand-built controller mesh, input anchors, printed labels
scripts/xr/label_surface.gd  lays each legend on the model's triangles as a small mesh
scripts/xr/label_font.gd  the legends' type: one distance-field atlas, a legend as a list of glyph quads
scripts/xr/label_layout.gd  our layout of the legends on the runtime model
scripts/xr/render_model_dump.gd  --dump-render-models: the runtime controller model to .glb + .json
scripts/net/             saved SMB hosts, directory listing (MediaBrowser or the simulated one), saved web pages
scripts/dev/             screenshot tour (--shots), pane input test (--ui-test), window test (--window-test),
                         in-headset snapshots (--snapshot-dir); dev tools (dev_host.gd: hot-reload, the PC
                         listener link, control API, scene control, permission ring, stats; ../docs/dev/)
scripts/play/            playback features (features.gd: the hub, main.features.<name>): end time, 3D depth, resume,
                         subtitles, catch-up, chapters, metadata mode, picture controls, languages, curve, zoom, ...
scripts/comfort/         battery forecast, sleep timer, haptic ticks, accessibility settings
scripts/env/             room light (user level x feature factors), room light follows playback
                         (all three: ../docs/features.md, one section per feature with its settings and API)
shaders/                 video (NV12 or sRGB window picture -> RGB, eye selection), nv12_encode (stub), env_unlit, grid, eye_overlay,
                         controller_model (the runtime controller model, unlit)
environments/            vr_environment.gd (interface), void, dim_room, cinema
ui/                      the panel: ui_layer.gd (open / closed, pointer, menu, wiring), pane.gd (SubViewport on a quad,
                         halo, fades, pointer -> mouse events), pane_pose.gd, pane_ui.gd (header, seek bar,
                         transport, tabs, footer), files_tab.gd, picture_tab.gd, sound_tab.gd,
                         subtitles_tab.gd, room_tab.gd, system_tab.gd, seek_bar.gd, mode_diagram.gd,
                         pane_widgets.gd, pane_style.gd, host_form.gd, url_form.gd, onscreen_keyboard.gd;
                         themes/default.tres (the one Theme), fonts/ (Inter, OFL)
tools/make_pane_theme.gd writes ui/themes/default.tres
xr/                      XR action map
tools/make_action_map.gd regenerates the action map
tools/label_layout.tscn  lays out the controller legends on the dumped runtime model -> xr/controller_labels_layout.tres
tools/label_proof.gd     proves the labels at the headset's pixels: measures each legend, exits non-zero on a failure
tools/controller_model/  our controller model from the CAD: cad/ (tessellate, split, decimate), export_legends.gd, render.gd,
                         bake.py (register, unwrap, print the legends) -> models/controllers/
models/controllers/      our controller models (CC BY-NC-SA 4.0, LICENSE-controller.md)
tests/                   unit tests (headless --script)
docs/screenshots/        desktop screenshots of every mode (both eyes side by side)
```

### Video sources

`VideoSource` (`scripts/video/video_source.gd`) is what the rest of the app sees. It provides two plane textures (Y, and
CbCr at half size, read as `.r` and `.ra`), the visible UV rectangle, `update(delta, master_clock)`, play, pause, seek,
duration, video info, audio stream and tracks, and statistics. `video_source_factory.gd` picks the source:

- `stub://...` paths always use **StubVideoSource**. Its test card is drawn in a SubViewport and encoded on the GPU into
  NV12, BT.709 limited range, with the height padded to 32 lines like the decoder's output. The real video shader, crop
  and eye selection therefore run on it.
- Other paths use **HWVideoSource** when `ClassDB.class_exists("HWVideoTexture")` and the file opens. The engine
  classes are reached through `ClassDB`, so the script also parses on a stock engine build.
  - With `MediaSource` in the engine, any container goes through `MediaSource.open()`, then
    `HWVideoTexture.open_source()`. Audio, tracks and duration come from the MediaSource.
  - Without it, raw `.h264`/`.hevc` streams go through `HWVideoTexture.open(path, codec, fps)`. The frame rate comes
    from the name, for example `_60` or `29.97fps`, else 23.976. A sidecar `.ogg` provides the audio when it has the
    same name or is a leading word of the name (`documentary.ogg` for `documentary_sbs.h264`).
- `browser://<url>` and `window://<id>` paths use **WindowVideoSource** when the engine has `X11WindowSource`. It
  gives one RGB texture (`get_rgb_texture()`) instead of the planes, no audio and no seeking. See "Browser (desktop
  windows)".
- Otherwise the stub stands in for the file. It shows the pattern for the mode the file name suggests, with the reason
  on the card (for example "Container files need MediaSource").

**MediaSource** is now in the engine module (fork commits `ca57514ecf` and `e4b4769810`). The app uses it as its class
reference describes:

- Opening: `open(path)`, then `HWVideoTexture.open_source(source)`, then `get_audio_stream()` into the
  AudioStreamPlayer, once per file.
- Clock: the audio master clock is `get_playback_position() + time_since_last_mix - output_latency`, as in spike 03.
- Seeking: `HWVideoTexture.seek(t)` seeks the source once. While the texture reports `settling` (decoding from the
  keyframe up to t), the audio is held and the video clock stays at t. The texture follows the new serial, and the player's
  `play(t)` right after does not seek again, because it is within the 50 ms tolerance.
- Audio tracks: `select_audio_track(i)` re-seeks inside the source and keeps the same stream.
- Pixel aspect: `sample_aspect_ratio` from `get_video_info()` is folded into the flat screen's aspect.

### Projections

`shaders/video.gdshader` is the only video shader. The mesh carries the projection: its UV is the position inside one
eye's picture, computed per vertex. The shader picks the eye's rectangle (mono, SBS or TB, with swap) by `VIEW_INDEX`,
clamps half a chroma texel inside it, crops the decoder padding, and converts BT.709 limited-range NV12 to RGB. It uses
no trigonometry per fragment.

| Mode | Mesh |
|---|---|
| Flat (mono, SBS, TB, full and half) | quad, adjustable width, distance and height; aspect from the eye's picture (half layouts are shown at the full frame's aspect) |
| 180° equirect | 64 x 64 latitude/longitude grid, 20 m radius |
| 360° equirect | 128 x 64 grid |
| Fisheye (equidistant) | polar cap of the chosen FOV (120-240°), 2.8° rings x 128 segments |
| Dual fisheye 360 | the whole sphere in 2.8° rings around straight ahead (0.5° rings through the seam band) x 128 segments; two UV sets (front and back lens) and the front lens's weight per vertex; the shader samples one lens, or both inside the seam band (`docs/features.md`, "Dual fisheye 360") |

The grid step is 2.8°, which keeps the interpolation error at about 0.02°, under a pixel. Spherical meshes are centred
on the head every frame (translation only) and wound clockwise as seen from inside, so they render with `cull_back`.

The mode is chosen in this order: a mode remembered for the file, the test pattern's own mode, then a guess from the
file name and frame size. The guess reads tags such as `_SBS`, `_TB`/`_OU`, `HSBS`, `Half-OU`, `3D`, `_180`,
`_360`, `fisheye`, `fisheye200`, `dualfisheye` / `dual_fisheye` / `dfe`, `_LR` and `_RL` (swap), and camera names
(a 360 camera's own `360_0042.MP4` is its raw dual fisheye frame, its phone app's `SAM_100_0001.mp4` a stitched 360). Where the name is ambiguous, it uses the shape: full SBS is wider
than 2.5:1, 180 SBS and 360 TB frames have standard aspect ratios. `tests/test_video_mode.gd` holds 30 cases.

### Environments

Each environment is a scene with `environments/vr_environment.gd` as its interface:

- **Screen anchor:** the `ScreenAnchor` marker plus `default_screen_width`, read through `get_default_screen()`. The
  marker heights assume a 1.2 m seated eye height. The app keeps the screen's offset from your real eye height, which
  it measures at recenter.
- **Light:** `ambient_level` and `screen_glow`, applied as the global shader parameters `env_light` and `screen_glow`.
- **Screen changes:** `on_screen_changed()` lets an environment follow the screen. The cinema moves its masking border.

Every surface is unlit, with `env_unlit.gdshader` and `grid.gdshader`. They have no lights, shadows, GI or
post-processing. The screen "spill" is a distance fall-off in the shader.

| Environment | Draw calls | Default screen |
|---|---|---|
| void (default) | 0 | 3 m wide at 3 m |
| dim room | 2 | 2.6 m at 3 m |
| cinema | 5 | 12 m at 13.8 m |

The cinema has stadium seating, and its seats are one MultiMesh. Screen size, distance and height are remembered per
environment, and so is the room light.

### Power

- While you watch, the GPU draws only the video mesh and the environment.
- The pane's SubViewport renders only while the pane can be seen. The laser shows only while it is on the pane.
- The info overlay redraws 4 times a second, and only when it is on.
- The stub source is for desktops and pattern checks only. It renders three viewports at 10 Hz.


## Tests

Run these from the repository root with any desktop build of the engine (4.7), called `godot` below. All but the
screenshots work with `--headless`.

```
godot --headless --xr-mode off --path app --script res://tests/test_video_mode.gd         # 43 file names, 17 --mode forms, ids, aspects
godot --headless --xr-mode off --path app --script res://tests/test_hw_source_helpers.gd  # fps from name, sidecar audio
godot --headless --xr-mode off --path app --script res://tests/test_director.gd           # subtitle files as text, search
godot --headless --xr-mode off --path app --script res://tests/test_media_servers.gd     # UPnP description, Browse, DIDL
godot --headless --xr-mode off --path app --script res://tests/test_controller_labels.gd  # label texts per profile, model node names
godot --headless --xr-mode off --path app --script res://tests/test_label_print.gd       # the print: conforms, no stretch, follows its part, rebuilds
godot --headless --xr-mode off --path app --script res://tests/test_network_open.gd      # unreachable host: listing, worker-thread open
godot --headless --xr-mode off --path app --script res://tests/test_render_model_dump.gd # --dump-render-models on a stand-in model
godot --headless --xr-mode off --path app --script res://tests/test_features.gd          # every playback feature in the real scene, test patterns
godot --headless --xr-mode off --path app --script res://tests/test_media_features.gd    # features on real files through MediaSource (WSL media)
godot --headless --xr-mode off --path app --script res://tests/test_end_time.gd          # also test_battery_forecast.gd, test_container_mode.gd
godot --headless --xr-mode off --path app --script res://tests/test_pane.gd             # front pose, head follow, menu hold, chips, theme rules
godot --headless --xr-mode off --path app --script res://tests/test_assistant.gd         # assistant service: window, pairing, three strikes, token, whitelist, events, voice, Forget
godot --headless --xr-mode off --path app --script res://tests/test_assistant_room.gd    # assistant rooms: permission, schema paths, model checks, Undo, Keep, restart
godot --headless --xr-mode off --path app --script res://tests/test_controller_motion.gd # our controller model's moving parts
godot --headless --xr-mode off --path app -- --ui-test                                     # 190 checks: the panel (menu, hold, world lock), every tab's controls, places, keyboard, forms, cards, focus, keys, mouse
godot --xr-mode off --path app -- --window-test --browser-command="<abs path>/testwin" --browser-match=x11window-test  # 37 Browser checks, X11 only
godot --xr-mode off --resolution 1280x720 --path app -- --shots=<abs path>/app/docs/screenshots
godot --headless --xr-mode off --path app --script res://tools/make_action_map.gd         # regenerate the action map
```

`test_video_mode.gd` includes release-style names with the same tags as the user's real files, under neutral
titles. A `...3D.2019.MULTi.1080p.Half-SBS.mkv` name gives half SBS, and a `...3D.2010.Full-SBS.mkv` name gives full
SBS. Over the 89 files in the user's film folder, the guess found the 7 3D releases and nothing else.

`--ui-test` clicks through the pane the way the controllers do. For each control it takes the pixel, finds that point
on the pane quad in the world, casts a ray from the camera, checks that `ray_hit()` returns the same pixel, and sends
pointer events. It covers the panel (open at launch, either controller's menu button, the hold to recentre,
world-locked, lying back, head follow, the slider nudge, the dev link's menu command), the places, the file rows, tabs, mode diagrams, Auto and the footer, a
seek-bar click, +10 s, a slider drag, the environment buttons, wheel scrolling, Previous and Next, the stick
focus and trigger, the keys V, N, P, Up, Tab, M and Esc, a real mouse click on the window, the host form with the
on-pane keyboard, and focus loss. It also covers each tab's feature controls (they reach the features hub), the
watch party, sharing, PC audio, push-to-talk, seat picking, live and trick play on the transport, the URL form's
routing, the seek-bar thumbnail (seeded, as the desktop has no second decoder), and the read-only hardware 10-bit
video row (its words, Details, no setup left). The pose and button logic (front pose, head follow, press and hold) is
also covered by `tests/test_pane.gd`.

`--window-test` needs an X display and an engine with `X11WindowSource`: on a desktop, the x86 build of the fork's
`frame/window` branch under WSLg, where only the MIT-SHM copy path is available. Instead of the browser it launches
the spike's test window (`spikes/05-window/testwin`, built with `cc -O2 -o testwin testwin.c -lxcb`), which logs the
input it gets. It checks the Browser place's rows, launching and the menu waiting for the window, the RGB picture on
the screen, the aspect, the overlay's rates, the laser's pixel mapping, the mouse, keys (M and Esc go to the window),
the controller mapping and labels, capturing a window that was already open, closing (a captured window stays open),
and the source ending when its window closes. On an engine without the module it prints that it was skipped.

`docs/screenshots/` shows each eye as the flat camera renders it with that eye forced, left | right:

- `flat_mono`, `flat_sbs_full`, `flat_sbs_half`, `flat_tb_full`, `flat_tb_half`: flat modes.
- `180_mono`, `180_sbs`, `180_sbs_look_right`: 180° modes.
- `360_mono`, `360_mono_look_back`, `360_tb`, `360_tb_look_up`: 360° modes.
- `fisheye_sbs`, `fisheye_sbs_fov200`: fisheye modes.
- `wrong_mode_sbs_as_mono`: an SBS pattern shown as mono, so both halves appear.
- `env_dim_room`, `env_cinema`, `env_cinema_side`: the environments.
- `ui_files`, `ui_picture`, `ui_sound`, `ui_room`, `ui_system`: the panel's tabs, framed. `ui_keyboard`: the
  add-host form with the on-pane keyboard.
- `watch_card`: a watch-along card (#54) beside the screen.
- `controllers_input`: our controller model with the trigger, grip, stick, A and view held (it moves with the input).
- `controllers_labels`: both controllers (our model, legends printed) posed by hand (no tracking on a desktop).
- `controllers_menu`: the same with the menu open: the right laser on the menu, the print says what inputs do there.
- `controllers_close`: our right controller close up.
- `controllers_model`, `controllers_model_close`: the same with a stand-in for the runtime model (the close-up in the void). It
  uses dark lit plastic, starts 0.65 m from the hand for a few frames as on the device, and its node origins sit
  at the model origin and the model is tilted 15°, to check the model path of the placement.

## Decisions to confirm

Each item below is a default I picked. All of them are easy to change.

1. **Spherical modes hide the environment.** Behind a 180° video you see black, not the room.
2. **Everything is in the projection layer**, flat video and menu included. Quad layers for the flat screen and the
   menu (sharper text, runtime-composited) wait for the spike 03-layer comparison.
3. **The panel closes itself when you open a file from it.** With the panel closed, the trigger plays and
   pauses; the menu button on either controller opens the panel in front of you.
4. **The default environment is void**, and the screen is placed relative to eye height at recenter. Defaults: void
   3 m wide at 3 m, cinema 12 m at 13.8 m, 0.4 m above eye level.
5. **A mode you choose is remembered per file** and wins over the file-name guess. "Auto" in the Mode tab forgets it.
   A `--mode=` argument wins over both.
6. **"3D" or "SBS" alone means half SBS.** The exceptions are frames wider than 2.5:1, which are guessed as full SBS,
   and frames taller than 1.2:1, which are guessed as TB.
7. **Button details beyond the brief:**
   - On the headset, next and previous are A and B on the right controller. X, Y and the d-pad are not bound until a
     device run shows what the profile really reports. Every binding is limited to paths the engine registers for the
     profile, because one path the runtime rejects voids the whole profile.
   - The left "view" button toggles the overlay.
   - A grip tap (under 0.35 s, hand turned less than 4°) moves the screen to your gaze. A longer hold drags it.
   - "Previous" restarts the current file when more than 3 s in.
8. **Raw `.h264`/`.hevc` play today** through `HWVideoTexture.open()`, with the frame rate from the name (default
   23.976) and `.ogg` sidecar audio. Seeking there is restart-only, so the seek bar and ±10 s do nothing.
9. **The 180/360 sphere** has a 20 m radius and is centred on the head, so the picture stays at infinity.
10. **Per-vertex projection UVs** (dense meshes) instead of per-fragment `atan`/`asin`, to save fragment ALU. Switch
    if seams or warping show in the headset.
11. **No `class_name` and no imported assets**, so the template build runs the folder directly. Scripts `preload` each
    other.
12. **The pane follows docs/ui-design.md's numbers**: 740 x 600 px on 24 cm, 15 px body text. That is about 0.5° at
    0.55 m, where the doc's own angles say about 1°; `[pane] scale = 2` doubles the size if the headset says so.
13. **SMB passwords are stored in plain text** in `user://settings.cfg` (`network/hosts`). The file is readable by
    the device user only, but anyone with a shell on the device can read it. The OS keyring would be the fix.
14. **The labels button is the bumper**, on either hand, and only on the headset's own profile. The labels are always
    printed now, so holding it no longer changes them: it is the left half of the snapshot chord, and the talk hand's
    push to talk. It keeps its legend until it has a job of its own. The `bumper/click` path is registered by the engine
    for the profile, but no device run has confirmed the runtime accepts it. If the profile stops binding, this path is
    the first suspect.
15. **Labels are short printed legends** ("NEXT", "PREV", "MENU", "SEEK / DIST", "PLAY / PAUSE"), 5 to 6 mm per line,
    printed on the controller where there is free plastic. The longer phrases ("Hold: move screen") did not fit the face
    plate. Both hands get labels for the trigger, grip and stick, even though their meaning is the same.
16. **The player's play and pause leave a web page alone.** Auto-pause and the start of the source don't send Space,
    because Space toggles and would start a video the user had paused. A sends Space by hand.
17. **Closing the Browser source closes the browser window the player launched**, but never a window it only captured.
    A window still starting when the source closes stays open when it arrives.

## Not done yet / stubbed

- **Assistant** (`scripts/assistant/`, `../docs/assistant.md`): tested headless, and end to end over HTTPS with curl and
  Python (`tools/assistant/test_assistant.py`), not yet in the headset. No film-frame screenshot; widgets use the engine's
  fallback font.
- **MediaSource:** plays a .mkv file on the device (worn test); seeking and audio track changes are not yet confirmed
  there.
- **On-device checks still open:** the pane (docs/morning-checklist.md) and overlay legibility, the per-eye check in the headset, battery reading,
  power with the pane open, controller labels and render models.
- **SMB:** tested against the real engine classes only without a server: an unknown host, and a non-routable
  address that waits out the 8 s timeout while the frame loop keeps running. Listing and playing a real share is
  not yet tested.
- **Render models:** they arrive on the device. Labels placed in model space and the unlit look await a worn check.
- **Browser:** verified on the device by the user on 2026-10-31 (79aac6d): pages open, capture and take the
  controller's input. There is no on-screen keyboard for the page yet; a paired keyboard works. Mipmaps for the window picture, against
  shimmer on small text, are an engine item.
- **Ambisonics, equi-angular cubemaps:** not started.
- **XR display latency** is not in the A/V clock, the same as in spike 03. A user A/V offset slider exists.
- **Desktop audio:** the stub has no audio, so A/V sync is only exercised with the hardware source.
