# Using the player

How to run the player on a desktop and on the headset, every command-line flag, every setting, the controller
bindings, and the PC tools. To build the engine, see `docs/BUILD.md`. To install a release, see
`docs/packaging.md`. Each feature has its own page in `docs/`; this page links to them.

The floating [keyboard](keyboard.md) opens from **System → Keyboard**: use either laser, poke the keys, or swipe
words into the focused menu field, PC window, terminal or browser. Hold the grip to move it and the stick to resize.

## Run on a desktop

The app runs on any desktop build of the engine (4.7). Without the fork's video module it plays generated test
patterns, so every projection mode, binding and pane control can be tried.

| Engine | Plays | Command, from the repository root |
|---|---|---|
| Stock 4.7.2 on Windows | test patterns | `godot --xr-mode off --path app` |
| The fork, x86_64, in WSL | test patterns, and in software (1080p and below) the files the hardware path can't show: VP9, 10-bit, 4:2:2, High 10. 8-bit H.264 and HEVC get the test pattern, as there is no hardware decoder (`app/tests/pcm10_h264_avi.py` makes High 10 test clips) | `~/src/godot-player/bin/godot.linuxbsd.template_debug.x86_64 --path app --xr-mode off` |
| The fork in WSL, no display | the same, for tests | add `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a` in front (`docs/BUILD.md`) |

On a desktop the view is a flat camera: drag to look, and use the keys in "Controls" below. App flags go after `--`:

```
godot --xr-mode off --path app -- --file=stub://360_tb --overlay
```

Settings on Windows are in `%APPDATA%\Godot\app_userdata\FrameCine\`. Use `--no-save` to start from the
defaults and write nothing.

## Run on the headset

The headset is reached with `ssh frame`, an entry in the PC's `~/.ssh/config`; the tools use the same name
(`FRAME_HOST` to change it). `powershell -File spikes/00-probe/run-probe.ps1` surveys a headset.

**From a release package** (`docs/packaging.md`): `tools/install-on-frame.sh` installs it. Then start "VR Video
Player" from the desktop session's menu, or over ssh:

```
~/framecine/run.sh --file=/home/steamos/Videos/film.mkv
```

**From the repository, for development:** `tools/push-app.sh` copies `app/` to the headset (`--watch` keeps copying
changes, for `--dev` hot-reload). Then, on the headset, from the folder with the engine binary:

```
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot_player --path app --display-driver x11 --xr-mode on -- <flags>
```

The display driver must be x11, and XR must be on. The engine prints `ERROR: Could not load global script cache.`
once. That is harmless. Over ssh from PowerShell, inner double quotes are lost: put long command lines in a script
file on the headset and run that.

The log is the terminal output (with `run.sh`: `~/.local/state/framecine/last.log`). Settings are in
`~/.local/share/godot/app_userdata/FrameCine/settings.cfg`.

## Command-line flags

All flags go after `--`. A flag overrides its setting for that run only. Flags in **bold** start something that
talks on the LAN; each is off unless given (or switched on in the pane).

| Flag | What it does | Page |
|---|---|---|
| **Open** | | |
| `--file=PATH` | Open a file, an `smb://host/share/path` file, or a test pattern `stub://<mode id>` (e.g. `stub://360_tb`). Its folder becomes the playlist. Media-server paths (`upnp://`) need the engine's http input, which is not built yet. | `app/README.md`, `docs/media-servers.md` |
| `--dir=PATH` | Play every video in a folder in order. `--file=` picks the first. `stub://` is every test pattern. | `app/README.md` |
| `--mode=MODE` | `flat`, `mono`, `sbs`, `hsbs`, `fsbs`, `tb`, `ou`, `hou`, `3d`, `180`, `180sbs`, `360`, `360tb`, `fisheye`, `dualfisheye` (or `dfe`: a 360 camera's raw frame, two circles), or a full id (`flat_sbs_half`, `fisheye_sbs_fov200`, `dualfisheye_mono`). Default: guessed from the file name and frame size. | `app/README.md`, `docs/features.md` |
| `--fov=DEG` | Fisheye field of view (stereo fisheye; dual fisheye 360 takes its lens values from its profile). | |
| **Screen and room** | | |
| `--screen-width=M`, `--distance=M`, `--height=M` | Flat screen width, distance, and centre height above eye level. | |
| `--env=void\|room\|cinema` | The environment. | |
| `--overlay` | The info overlay on. | |
| `--no-ui` | Start with the menu panel closed. The menu button opens it. | `docs/ui-design.md` |
| `--controller-model=runtime\|ours` | In XR, the runtime's controller model with our labels (default), or our own model with printed legends. | `app/README.md` |
| **Flat camera (desktop, or `--no-xr`)** | | |
| `--no-xr` | A flat camera even when XR is up. | |
| `--look=YAW,PITCH`, `--camera-fov=DEG` | The flat camera's direction and vertical field of view. | |
| **Runs over ssh, screenshots** | | |
| `--quit-after=N` | Quit after N rendered frames. | |
| `--screenshot=PATH`, `--screenshot-frame=N` | A PNG of both eyes side by side at frame N (default 90), flat camera. | |
| `--snapshot-dir=DIR`, `--snapshot-every=S` | Head view and controller close-ups on left bumper + A (F12 on a desktop), and every S seconds. | `app/README.md` |
| `--shots=DIR` | The screenshot tour into DIR, then quit. | `app/README.md` |
| **Features** | | |
| `--benchmark[=PATH]` | Decode the biggest video in a folder (or PATH) for 10 s and log what the device can do. Also runs once by itself on the first run. | `docs/benchmark.md` |
| `--tour=FILE`, `--kiosk` | Run a tour from a JSON file (a path, or a name in `user://tours`). `--kiosk` loops it. | `docs/tours.md` |
| `--whisper-dir=DIR`, `--whisper-model=NAME`, `--whisper-threads=N`, `--whisper-backend=cpu\|vulkan` | On-device speech to text for the assistant (started only when the assistant needs it): the folder with `whisper-server` and `models/` (default: `whisper/` next to the engine, one folder up, or next to the app folder), the model (`base.en`, a stem such as `small.en-q5_1`, or a `.bin` path), threads, and the CPU or Vulkan build. Also `[voice]`. | `build/whisper/README.md` |
| `--model-url=URL` | Where the one-time speech model download comes from (default: the project's `models-1` release); for tests and mirrors. The model goes to `whisper-models/` in the data folder. | `docs/framedrop.md` |
| **`--remote`** | The phone remote: a web page on the LAN, address and pairing QR code in the pane. | `docs/remote.md` |
| **`--share`** | The headset's folders on the LAN: downloads, uploads to Drop, screenshots. | `docs/share.md` |
| **`--pc-audio=HOST[:PORT]`** | Connect out to `tools/audio_sink.py`; the film's sound plays on the PC and the headset is silent. | `docs/pc-audio.md` |
| **`--pc-audio-mode=MODE`** | With `--pc-audio`: `auto` (the default) takes the sound straight from the engine when it can, else from the player; `pull` or `capture` picks one. | `docs/pc-audio.md` |
| `--hands`, `--passthrough` | XR spikes, untested on the device: hand tracking (pinch is the trigger, the index finger the laser), and the runtime's camera view behind the scene. | `docs/xr-spikes.md` |
| `--pane-layer`, `--video-layer` | XR spike, untested on the device: the pane, or the flat screen, as an OpenXR quad layer (sharper text and picture). `--video-layer` turns on the film layer (`[view] film_layer`, on by default since 2026-11-04) for one run. | `docs/xr-spikes.md`, `docs/features.md` |
| **Development** | | |
| **`--listener=HOST[:PORT]`** | Connect out to the dev listener on a PC (`tools/listener.py`): events out, commands in. Also `[dev] listener_host`. | `docs/dev/control-protocol.md` |
| `--dev` | Hot-reload: changed scripts, shaders, environments and resources reload in place. | `docs/dev/hot-reload.md` |
| `--dev-allow=MIN`, `--dev-code` | Let the listener change the scene and settings for MIN minutes; let it run code. | `docs/dev/permission-ring.md` |
| `--debug` | The overlay on, and every controller input logged. `--verbose-input` logs the inputs only. | |
| `--labels-debug` | A 2 mm sphere at each controller label's anchor, and the print's size in the eye's image in the log. | `app/README.md` |
| `--dump-render-models=DIR` | Write each runtime controller model to `DIR/<side>_controller.glb` and `.json`. Never commit them. | `app/README.md` |
| `--fake-controller-battery=left:N,right:N` | Desktop stand-in for the controllers' battery levels, in percent. | |
| **Tests** | | |
| `--ui-test` | The pane input test, then quit. | `app/README.md`, "Tests" |
| `--window-test`, `--browser-command="CMD ARGS"`, `--browser-match=TEXT` | The Browser place test on an X11 desktop. | `app/README.md` |
| `--no-save` | Do not read or write `settings.cfg`. | |
| `--pseudo-locale` | The menus in the pseudo-locale for this run (accented, longer, in brackets): a check for text not yet translatable. Not saved. | `docs/i18n.md` |

The engine's own flags go before `--`: `--path app`, `--xr-mode on|off`, `--display-driver x11`, `--headless`,
`--resolution WxH`, `--script res://...`. Flags such as `--media=`, `--seek-every=`, `--gpu-time` and
`--hdr-target=` belong to the engine test project in `spikes/03-player`, not to the app.

Environment variables for the engine's video decoding (for tests and A/B runs; set them before the player starts):

| Variable | Effect |
|---|---|
| `HWVIDEO_HW_VP9=0` or `1` | VP9 in software only, or in hardware even when `[hwvideo] hw_vp9` is false. Hardware VP9 is still one video at a time. |
| `HWVIDEO_FORCE_SW=1` | Decode in software every video that software can take (up to about 1080p). |
| `HWVIDEO_P010=1` or `0` | Say that the decoder offers P010 (10-bit in hardware), or that it does not, without asking it. With `0` the decoder also ignores a P010 that it offers, so 10-bit goes to Q10C (below) on a kernel that offers P010 too. |
| `HWVIDEO_Q10C=0` | No Q10C through the YCbCr sampler: without P010, 10-bit decodes in software. |
| `HWVIDEO_Q10C_FORMAT=N`, `G12` or `G16` | The VkFormat to import Q10C as: a number, or the 2-plane 4:2:0 12-bit or 16-bit format (default: the 10-bit one, 1000156027). |
| `HWVIDEO_Q10C_MODIFIER=0x...` | Try only this DRM format modifier, also one the driver does not list (it must still accept it for a dmabuf import). |
| `HWVIDEO_Q10C_LAYOUT=meta`, `data`, `4plane` or `1plane` | Try only this plane layout (the layout table in `spikes/04-q10c-probe/README.md`, "Run"). |
| `HWVIDEO_Q10C_CHECK=0` | Do not check the first Q10C frames (a misread picture then stays on the screen). |

## Settings

Per feature, with what each key does: `docs/features.md` (its index links every feature).

`settings.cfg` is a ConfigFile (INI style). The app writes it at most once a second and at exit. A key that is at its
default is often left out. `<env>` is an environment id (`void`, `room`, `cinema`, ...). The dev link reads any key
as `get SECTION/KEY` and changes it with `set` (`docs/dev/control-protocol.md`); the private ones it cannot see.

| Section | Keys (default) | What |
|---|---|---|
| `[view]` | `environment` ("void"), `overlay` (false), `foveation` ("low"; or "off", "medium", "high"), `foveation_sharp_panel` (true) | Start environment; info overlay; foveated rendering (D22): the level, and off while the panel or the agent pane shows. Also in System, Rendering: Foveation (Off / Low / Medium / High; applies at once; High can look blocky at the edges) and Sharp while the panel shows. A build whose project.godot has `xr/openxr/foveation_level` 0 starts without foveation; the row then says it isn't available. |
| `[audio]` | `volume` (1.0), `av_offset` (0.0 s), `av_offset_<rate>` (s, per display refresh rate; `av_offset` is the fallback), `environment_db` (-60 off to 0 dB, -18) | A/V offset per refresh rate (#24); the Environment sound slider (the room's own sound, always ducked under the film; `docs/environments.md`) |
| `[room:<env>]` | one key per room setting changed from its default: `dim` (true), `ambience_db` (-25 off to 6 dB, 0), `life` (true), `ritual` (true), `flicker` (true), `motion` (0 to 1, 1), and the room's own (the cinema's `house_level` 0 to 1, 0.2; the Void's `ripple` 0 to 1, 0.5) | The Room tab's This room (below) |
| `[sound]` | `night_mode` (false), `night_strength` (1.0), `dialogue_boost_db` (0) | Night mode and dialogue boost (#26) |
| `[player]` | `last_file` | |
| `[screen_<env>]` | `width`, `distance`, `height_offset` (per environment), `yaw` (0.0), `curve_radius` (0 = flat) | The screen in each room |
| `[env_<env>]` | `light` (1.0), `reflection` (on where the room has a floor that can reflect) | Room light; floor reflection |
| `[reflection]` | `strength` (0 to 0.6, 0.25) | Floor reflection (#62) |
| `[room]` | `follow_playback` (true), `play_level` (0.35) | Lights dim while a film plays |
| `[bias_light]` | `enabled` (false), `strength` (0 to 1, 1.0) | Room light from the picture's colours (#29) |
| `[react]` | `enabled` (false), `strength` (0.5) | The room reacts to the film (#81) |
| `[projector]` | `beam` (false), `grain` (0 to 1, 0), `weave` (0 to 1, 0) | Projector mode (#92) |
| `[time_of_day]` | `mode` ("night"; or "clock", "dusk", "day"), `latitude` (50), `longitude` (from the time zone) | Time of day in the rooms (#84) |
| `[zoom_lens]` | `enabled` (true), `magnification` (1.5 to 8, 3.0) | Zoom lens (#38) |
| `[seats]` | `<env>` (the seat number) | `docs/features.md` |
| `[picture_<env>]` | `brightness` (0), `contrast` (1), `saturation` (1), `gamma` (1), `lift` (0), `sharpen` (0), `deband` (0.5: Smooth banding, 8-bit video only); only values off their default are stored. `[picture] steady_detail` (true: the footprint filter) | Picture controls (#27, #90) |
| `[picture]` | `deinterlace` ("off"), `auto_crop` (false), `auto_crop_grow` (true) | Deinterlace (#95); auto letterbox crop (#42) |
| `[trick_play]` | `enabled` (true) | Hold the stick right to scan at 4x, then 8x (#46) |
| `[hdr]` | `tone_map` (true) | |
| `[tonemap_<env>]` | `exposure` (-2 to 2 stops, 0), `knee` (0.5 to 0.95, 0.75), `target_nits` (100 to 400, 203) | HDR tone mapping (#85) |
| `[stereo]` | `depth` (0.0), `edge_fade` (0.0), `mono_eye` (-1 off, 0 left, 1 right) | |
| `[lens]` | `default` ("equidistant"), `k1` to `k4` (0.0) | Fisheye lens profile and its coefficients |
| `[lens_files]` | one key per file | The lens profile chosen for a file |
| `[dual_fisheye]` | `default` ("generic"; or "camera360", "camera360_photo") | The dual fisheye 360 profile for files without a choice (360 camera names, `360_NNNN`, get "camera360", or "camera360_photo" for a picture) |
| `[dual_fisheye_files]` | one key per file | The dual fisheye 360 profile chosen for a file |
| `[dual_fisheye_<profile>]` | `front_<key>`, `back_<key>` with key `fov` (150 to 240), `cx`, `cy` (0 to 1), `radius` (fraction of the frame's height), `yaw`, `pitch`, `roll` (-20 to 20 degrees); `blend` (0 to 15 degrees), `model` ("equidistant", "equisolid", "stereographic"); only values off the profile's own are stored | A camera's lens values: the Picture tab's Lens field and Seam, the dev link's `dual_fisheye_*` settings |
| `[subtitles]` | `enabled` (false), `size` (0.5 to 3, 1.0), `position` ("below" or "inside"), `offset` (-0.5 to 0.5, 0.0), `depth` (0 to 2 m, 0.0), `background` (0 to 1, 0.0), `find_files` (true), `forced_auto` (true), `secondary_language` ("") | `docs/features.md` |
| `[language]` | `audio`, `subtitles` (lists, most preferred first); `ui` (none: English; "zh_CN": Simplified Chinese) | Track language memory; the menus' and controller labels' language. Also in System, Language (each language in its own name; applies at once). Film and file names stay as they are. The Chinese is a machine draft (`docs/i18n.md`). |
| `[queue]` | `repeat` ("off"), `shuffle` (false), `continuous` (false), `gapless` (false) | Gapless: the next file opens behind the current one and takes over at its end, with continuous play only (#44); off until the headset check (runbook E7) |
| `[crossfade]` | `music` (0 to 12 s), `videos` (0 to 10 s); 0 = off, the default | Items overlap into the next (#94) |
| `[pip]` | `size` (0.15 to 0.5, 0.3), `corner` ("top_right"; or "top_left", "bottom_right", "bottom_left") | Picture in picture (#87) |
| `[thumbnails]` | `enabled` (false) | Seek-bar thumbnails from a second decoder session (#40); off until the headset's memory check |
| `[up_next]` | `enabled` (true), `seconds` (10.0) | |
| `[preshow]` | `enabled` (true) | |
| `[intermission]` | `enabled` (false), `minutes` (10.0), `min_film_minutes` (100.0) | |
| `[folder_modes]` | `rules` ({}) | The mode for every file in a folder |
| `[jog]` | `enabled` (true), `seconds_per_turn` (60.0) | |
| `[speakers]` | `enabled` (false), `lfe` (false) | Spatial sound (#21, #47) on, and the bass channel |
| `[spatial]` | `reverb` (0 to 2, 1.0), `output` ("auto", "speakers", "headphones"), `hrtf_<profile>` ("sadie2_d1"; ids of earlier versions are read as their new ids), `eq_<profile>` ([] of {type, freq, gain_db, q}), `tuning_<profile>` ({itd_scale, pinna_warp, concha_db}, and the tuning's result) | Spatial sound's room sound, output profile, HRTF set, EQ and tuning per profile ("speakers" or "headphones") |
| `[resume]` | `mode` ("auto") | Positions are in `resume.cfg` |
| `[images]` | `slideshow` (false), `seconds` (2 to 60, 8.0), `crossfade` (0 to 3 s, 1.0) | Pictures and slideshow (#22) |
| `[sidecar]` | `write` (false) | Write the chosen mode next to the file |
| `[favourites]` | `items` ([]) | |
| `[comfort]` | `head_follow` (false) | |
| `[accessibility]` | `ui_scale` (1.0), `left_handed` (false), `monocular` (false), `monocular_eye` (0), `subtitles_always` (false) | |
| `[haptics]` | `enabled` (true), `strength` (1.0) | |
| `[sleep]` | `fade_seconds` (60), `last_minutes` (0) | Sleep timer |
| `[battery]` | `margin_ok_minutes` (15) | Battery forecast |
| `[display]` | `clock_24h` (true) | |
| `[pane]` | `recentre_hold` (0.6 s: hold the menu button this long to recentre), `tablet_style` (the tablet's look, its palette among it), `theme` (`res://ui/themes/default.tres`) | `docs/ui-design.md`. Also in System, Panel. |
| `[browser]` | `last_folder`, `last_url`, `pages` ([]), `laser` (false), `dictation_partials` (true) | Files place; web pages; the stick pointer (the laser as well on a window) and the live words under a field (`app/docs/window-source.md`). The first two are also in System, Controllers. |
| `[network]` | `hosts` ([]), `live_latency` (0.1 to 2.5 s, 0.5) | Saved file shares (private: holds credentials); the live stream buffer |
| `[remote]` | `enabled` (false), `port` (47880), `key` | Phone remote. `key` is the pairing code: private, never logged. |
| `[share]` | `enabled` (false), `folders` ([]), `drop` ("") | Headset file sharing |
| `[pc_audio]` | `host` ("") | The PC for PC audio |
| `[card]` | `place` ("hand": held above the pointer controller; "screen": beside the screen) | Where the card with the conversation and notes shows. A card that offers choices always shows beside the screen, where the laser reaches it. |
| `[assistant]` | `enabled` (false), `guide_port` (47801, plain HTTP: the guide only), `port` (47802, HTTPS: the API), `allow_control` (false), `allow_room` (false), `voice_to` ("dev": where push-to-talk goes when the dev link is connected too; "assistant" for the assistant) | The assistant service on the headset (`docs/assistant.md`). The paired assistants (token hashes) are not here: they are in `assistant_clients.cfg`; the HTTPS key in `assistant_tls.key` and `.crt` (all owner-only, never logged). Also in System, Assistant. |
| `[pc_windows]` | `enabled` (false), `port` (47803), `delay` (0.15: seconds behind the PC's own time that its pictures and sound play) | PC windows (`docs/pc-windows.md`). The paired PCs (token hashes) are in `pc_clients.cfg` (owner-only, never logged); the TLS key and certificate are the assistant's. Also in System, PC windows. |
| `[dev]` | `listener_host` (""), `listener_port` (47800), `hot_reload` (false), `remote_changes` ("ask"; or "allow", "deny"), `remote_code` (false) | `docs/dev/permission-ring.md` |
| `[benchmark]` | `auto` (true), `result`, `tries`, `last_error` | `docs/benchmark.md` |
| `[intro]` | `done` (false) | The introduction at the first start (eye calibration, the controls, the agent's terminal) has been gone through. Not shown on a run with `--file`, `--dir`, `--tour`, `--no-ui`, a test or read-only settings. System, Test and setup: Show the introduction again. |
| `[hwvideo]` | `hw_vp9` (true) | VP9 in hardware, one video at a time (a second VP9 video, such as picture in picture, decodes in software); false: VP9 always in software. Read at start. The removed setup's `iris_bundle` and `iris_setup_prompt` are ignored if still there. 10-bit needs no setting (`docs/features.md`, "Hardware 10-bit video"). |
| `[voice]` | `whisper_dir` (""; empty: `whisper/` next to the engine or the app), `whisper_model` ("small.en": q8_0, else q5_1, else f16; or a stem such as "small.en-q5_1", or a `.bin` path), `whisper_threads` (4), `whisper_backend` ("cpu"; or "vulkan"), `live_partials` (false: the text shows when you let go; true: live text while you hold the button, which costs CPU the film needs) | On-device speech to text: whisper.cpp's server on 127.0.0.1, started when the assistant needs it. Its output: `whisper-server.log` in this folder. `build/whisper/README.md` |
| `[files]`, `[stereo_depth_files]`, `[zoom_files]`, `[horizon_files]`, `[subtitle_delay_files]` | one key per file (a hash of the path) | What you chose for each file: mode, depth, zoom, horizon, subtitle delay |

Other files in the same folder: `resume.cfg` (one section per file: path, title, position, duration, updated,
finished), `xr_override.cfg` (only after `--hands`, `docs/xr-spikes.md`), `assistant_clients.cfg` (the paired
assistants), `assistant_tls.key` and `assistant_tls.crt` (the assistant service's certificate), `tours/`, `rooms/`, `skyboxes/`, `recipes/` (also the rooms an assistant made and you kept:
`<name>.room.json` and `<name>.files/`), `objects/` (the object library's imported objects, and the models and
pictures kept rooms place: `<id>/object.glb`, `manifest.json`, `thumb.png`), `screenshots/`.

## Controls

The action map binds the headset's own controllers, the generic controller profile, two common third-party
controller profiles and the simple controller. Labels printed on the controllers say what each input does: bring a
controller close to read them. The menu is on a tablet in front of you and a little below the eyes, tilted up
towards them (`docs/ui-design.md`). The menu button on either controller opens it, and that controller points at
it; you can also touch it. One controller is enough.

The tablet has two panes. The top one shows a small line with the chapter and the clock, time left, end time and
battery; under it the title and the time (LIVE for a live stream, 4x or 8x while scanning); and the time bar with a
tick at each chapter: drag the bar with the laser and trigger, or with a controller's tip, to skip. With **Seek bar
pictures** on (System), the laser on the bar shows a picture of the film there. Under the bar, on the left:
Previous, -10 s, Play or Pause, +10 s and Next (hold 4x or 8x to scan); on the right two switches for the picture:
**Steady detail** (fine detail filtered where the picture is shrunk, so it doesn't shimmer) and **Smooth banding**
(the steps in dark gradients hidden, 8-bit video). The main pane has the tabs down the left and the tab beside them.
While a form with the keyboard is open, it has the whole main pane.

| Control | Panel closed | Panel open (the pointer controller) | Keyboard and mouse |
|---|---|---|---|
| Trigger | Play or pause | Laser on the panel: click. Laser off the panel: the focused control | Space, K, mouse click |
| Stick left or right | Seek 10 s back or on, repeats while held | Laser on a slider: move it. Laser off: move the focus | Left, Right, J, L |
| Stick up or down | Screen farther or nearer (flat) | Laser on the panel: scroll, smoothly, faster the further it is pushed (on a slider: move it). Laser off: move the focus | Up, Down, wheel |
| A (right) | Next video | Same | N |
| B (right) | Previous video, or the start of this one after 3 s | Same | P |
| Y (right), the sparkle on its cap, while the right hand points | An agent's terminal on or off. With none running, start the last one used. It keeps working while hidden. | Nothing | |
| X (right) | Enter in an agent's terminal while it shows, whichever hand points (its legend says ENTER then); nothing otherwise | Same | |
| Menu (right) or view (left); right stick click | Open the panel in front; this controller points. With the browser's cursor on an image: keep the picture (below) | Short press: close it. Hold 0.6 s: move it to the front of the head again | M, F3 (hold: recentre); Esc closes |
| Left stick click | Info overlay on or off | Same | Tab, F1 |
| Grip, hold, pointing at an object or in one | Pick it up (`docs/physics.md`): stick up or down nearer or farther, left or right turns it, let go to drop it or throw it, B puts it back where it was picked up; the trigger does nothing meanwhile | Same, with the laser off the panel | |
| Grip, hold and point | Move the flat screen (stick: up / down farther or nearer, left / right bigger or smaller); in 180 and 360, turn the sphere | Held 2 s with the laser on the panel, in dev mode: allow remote changes for an hour | G held and mouse |
| Grip, tap | Screen (or the sphere's front) to where you look | Same | R (also recenters) |
| Pointer hand's bumper, hold | Push to talk, when the dev link is on (`docs/dev/voice.md`), an assistant is paired, or an agent runs on the headset. With the browser on the big screen and a text field selected: speak into that field | | F8 held |
| Pointer hand's bumper, quick tap | With an agent's pane showing: hide it | | |
| Left bumper + A | Snapshot, with `--snapshot-dir` | | F12 |
| - | - | - | V, O, H, X: next projection, layout, half, swap eyes. E: next environment. Drag: look. |

Claude Code or Codex on the headset (Files, `docs/assistant.md`, "Agents on the headset"): talk shows its terminal on
the pointer controller and types what you say into it. X is Enter whenever the terminal shows. The stick, trigger, A
and B stay the film's unless a prompt waits (the pane's edge turns amber), you look at the pane (its edge turns blue;
within 3 degrees of its edge with eye calibration, 5 without) or you hold squeeze: then they are arrows, Enter, Space
and Escape, and squeeze and stick scroll back. A terminal on the big screen
takes the trigger as Enter, the stick as arrows, and B as Escape. Say "one" to "four", "up", "down", "enter" or "escape"
for that key at any time, and "yes" or "no" while a prompt waits. Other words are not typed while a prompt waits. A
keyboard paired to the headset types into the terminal while the pane shows. With a window on the big screen as well,
such as the browser, it types into the terminal while you look at the pane and into the window otherwise.

### The browser on the big screen

With the panel closed, the right controller works the page in two modes. Look at the screen, and a cursor appears
where you look. Look away, and the cursor goes. The legends on the controller change with the mode.

| Control | Looking at the screen (a cursor shows) | Looking away (no cursor) |
|---|---|---|
| Stick | Move the cursor: a small push for fine aim, all the way to cross the page in a second | Up or down: scroll. Left or right: the arrow keys (most web players seek with them) |
| Grip held + stick | Scroll and arrow keys; the cursor stays put | The same |
| Trigger | Click at the cursor; hold it to drag | Nothing |
| Grip, tap | Right click at the cursor | Nothing |
| Right stick click | On an image (the legend says KEEP PICTURE): keep the picture. Elsewhere: the menu | The menu |
| A, B | Space (play or pause), the browser's Back | The same |
| Pointer hand's bumper, hold | With a text field selected: speak into it | The same |

- **Switching modes.** The cursor appears after a tenth of a second of looking at the screen and goes after
  0.4 s of looking away. While you push the stick or hold the trigger, it stays.
- **Where the cursor goes.** Only the stick moves it. It starts in the middle of the page and stays where you left
  it; looking away and back doesn't move it.
- **Without eye tracking.** Where your head points stands in for where you look.
- **The laser.** It is off on the browser. **Laser on the browser** in System, Controllers turns it on as well as the
  stick.
- **Speaking into a field.** Click into a search box or any text field, then hold the bumper and speak. The field
  glows while you hold the button, and your words show under it as you speak. When you let go, the text is typed into
  the field, Chinese and other scripts too.
  - With no field selected, the bumper talks to the assistant as before.
  - A password field is refused: type it with a keyboard.
  - If speech to text isn't working on the headset, a notice says so and nothing is typed.
  - A browser the player didn't open (one that was already running) can't say which field is selected, so the bumper
    stays the assistant's there.
- **Keeping a picture.** Put the cursor on an image and click the right stick. The cursor holds still for the click,
  and a notice says "Picture kept" with its name. The app downloads the full-size picture, or, if it can't, takes it
  from the screen. **Copy image** in the page's menu (a grip tap) and saving an image to Downloads keep it too. The
  pictures are in **Objects → Pictures**.

While the panel is open, the other controller keeps the "Panel closed" functions. On the generic controller profile:
right primary is next, right secondary is previous, left primary or right stick click is the menu, left secondary or
left stick click is the overlay. On the two third-party profiles, a stick click (both sticks on the one with A/B; the
right stick on the one with A/B/X/Y, whose left menu button is the menu too) opens the panel. The full detail,
including the pause when the headset loses focus, is in `app/README.md`, "Controls".

## The Sound tab: spatial sound

The Sound tab's **Spatial sound** section (`docs/features.md`, #21) plays the film's sound from speakers in the room.
You hear it in front of you, behind you and above you, outside your head, and it stays put when you turn your head.
It needs the `PLAYER_BINAURAL` engine or a later one. On older engines the tab says so and the stereo mix plays.

- **Spatial sound:** on or off. Turning it on opens the playing file again at the same place.
- **Bass channel:** also plays the film's separate bass channel (the .1 of 5.1), to both ears.
- **Room sound:** how much of the room's echo you hear, 0 to 200 %. More echo makes the speakers seem farther away.
  100 % is the room as designed: the cinema's dead hall, the home theatre's short reverb, the car at the drive-in.
- **Sound plays on:** Auto (the headset sees whether its own speakers or headphones play), Headset speakers, or
  Headphones. Each has its own head measurements and tuning.
- **Head measurements (HRTF):** the set of measured ears the sound goes through. "Dummy head A" is the
  default. Try the others if sounds behind you seem to come from in front.
  - Sets marked "Fetch" are not part of the app. Choosing one shows its licence and a Download button. After the
    download the set is converted on the headset and listed like the others.
- **Tune spatial sound:** fits the sound to your ears in about 2 minutes (`docs/features.md`, #21, "Tuning"). A
  sound circles you and passes overhead, played twice: as A, then as B. Pick the one that sounds more real, more
  outside your head, on the card beside the screen. There is no right answer. Can't tell keeps what you have, Again
  plays both again, and the menu button stops with nothing changed. What you had at the start is the first to beat,
  so tuning never leaves you with something you like less.
- The line under the section says what plays from where: the channels, or the 360 sound field. At a speed other than
  1x the stereo mix plays.

The same settings are in the dev link and for an assistant: `set_sound` with `speakers`, `bass_channel`,
`output_profile`, `hrtf` and `room_reverb`, and `download_hrtf`.

## Room sound and this room's settings

- **Room, Environment:** the rooms in groups: **Cinemas** (the cinema and the cinema set), **Television** (the
  history of television, one room an era), **Built in** (the other rooms), **Yours** and **Showrooms**. A group with
  no rooms is not shown.

- **Sound, Environment sound:** the room's own sound (rain, birds, the projector, a thrown object's thud), from off
  to full. The default is 18 dB under the film. It always ducks under the film: about 7 dB under a film at its usual
  level, about 19 dB under a loud scene. It rises a little (3 dB) in the pre-show, while paused and after the end.
- **Room, This room:** each room's own settings. Every room has **Dim during the film** and **Ambience** (this room's
  sound against the Environment sound slider; at the bottom the room is silent). Where they do something, also
  **Ambient life**, **Pre-show** (the curtains and the room's start of the show), **Flickering lights** (off holds them
  steady) and **Motion** (how much things in the room move). A room adds its own: the cinema's **House lights in the
  film**, the Void's **Ripple**. **Back to defaults** puts this room's settings back, and its own seat.
- Kept per room as `[room:<env>]` in `settings.cfg`, only what you changed.
- The cinema's start of the show: when a film starts from its beginning, a chime sounds, the house lamps come down
  to half, the curtains part, and the lamps go down to the House lights setting. At the end they come back up.
- The Void: a black floor that reflects the film, and a faint ring on it where you move your head.
- An assistant reads them with `room_settings` (`this_room`) and changes them with `room_setting`; the slider is
  `set_sound`'s `environment_sound_db`.

## The tabs' sections

On the main pane each tab but Source has a column of its sections beside the tabs, as Source has its places. Pick
one and it fills the rest of the pane. A section with nothing to show now (3D, for a flat film) is not listed.

Source lists its places in groups: your films (Library, Search, Favourites, Queue), the headset's folders (Videos
and Downloads first, then home and drives), the network (Network, Media servers), apps (Browser, Android apps), the
assistants, and Test patterns last.

## The Objects tab

The **Objects** tab (after Room) is the object library (`docs/assistant.md`, "Objects"): things to put in the room,
built in (a picture frame, a wall shelf, a pot plant, a wall clock) and imported (by an assistant, or with
`object_import` from the dev link: a `.glb`, or an SVG drawing made solid). It has five sections: **Built-in
objects**, **Your objects** (this install's own: imported, or kept from a room), **Pictures** (pictures you kept from
the browser), **Surfaces** (materials to find, import and apply) and **In this room** (what the room has from the
library, with its parts). Each list of objects has its own **Place**. One controller does it all.

**Fab, in the app.** Under **Your objects**, **Fab** searches Quixel Megascans' free 3D objects on the Fab store and
imports them, with no browser and no sign-in:

1. The first time, read the short summary of Fab's licence. **Read Fab's licence** opens the full text in the
   browser. **Accept** starts it (the app keeps the date: `[fab] eula_accepted` in `settings.cfg`). Until you accept,
   the app asks Fab nothing, and an assistant can't either.
2. **Search Fab**, type a word or two in English (rock, chair, cabbage) and **Search**. The results show as
   thumbnails with names. **More**, under them, loads the next page.
3. Pick one, then **Import**. The line under it says how far the download is; **Cancel** stops it. The object comes
   in as one of **Your objects**, picked, ready to **Place**. One you have already is not downloaded again.

The same card has **Clear Fab's cache** (the searches the app keeps for a day and the thumbnails) and **Withdraw**
(takes your acceptance back: the app asks Fab nothing until you accept again). If Fab is busy, the card says so and
how many seconds the app waits.

A scanned object downloaded from the Fab store in a browser (the Low or Medium quality zip, into Downloads on the
headset) shows in **Your objects** under **In Downloads, from Fab** (only when there is one): **Add <name>** makes it
one of yours. Searching Fab in the app (above) does the same without the browser. Either way it stays on the headset:
the Fab licence lets you use it, not share it.

1. Pick a thumbnail. The line under the thumbnails says its name, how it sits (wall, floor, ...) and how many parts it
   has.
2. **Place**. The panel goes. The object shows where the laser meets a wall (back to the wall) or the floor (standing,
   facing you); with nothing there, it waits 2 m along the laser.
3. Stick left or right turns it, up or down makes it bigger or smaller. The trigger sets it there; B or the menu
   button cancels.
4. The panel comes back with Undo in its footer. A stock room becomes a kept room of its own, "<room> with objects",
   in the Environment list.

**In this room** lists what the room has from the library. Pick one:

- **Move** (as Place, for this one) and **Remove** (asked first in the footer: Remove or Keep).
- Its parts, each with a swatch of its colour. **Colour** opens a palette under the part; pick a colour. **Picture**
  puts the picture on show (a picture file on the headset, opened in Files) on the part. **Material** opens the
  material library under the part (`docs/materials.md`): a row of kinds (All, Floors, Walls, Fabric, Wood, Leather,
  Metal, Stone), then each material of that kind as a button with a swatch of its colour and its name; the one the
  part shows is lit. Pick one and the part takes it, as the material shows itself; Colour afterwards gives it that
  colour with its pattern kept. **Effect** opens the effect library under the part (`docs/effects.md`): a row of
  groups (All, Classic, Energy, Nature, Materials, Stylised, Transitions, Reactive), then each effect of that group
  as a button with a small preview and its name (its description shows when you point at it); the one the part shows
  is lit. Pick one and the part takes it with its options at their defaults; over a material, an effect that keeps
  the surface under it (caustics, rim glow, velvet, ...) keeps the material. The part's line names its material and
  effect. A change that would take the room past its cost limit is refused with a note. **Reset** gives the part its
  own colours back. Each change has Undo in the footer.

**Pictures** (`docs/features.md`, "Pictures"):

1. **Find pictures**, type a few words and **Search**. The browser opens on the big screen with an image search. Browse
   as you like.
2. Keep a picture: the cursor on it and the right stick click (the legend says KEEP PICTURE), or **Copy image**, or
   save it to Downloads. A notice says "Picture kept".
3. In **Pictures**, pick its tile. **Place as:** **Poster**, **Framed**, **Canvas** or **Cut-out** makes it at the
   picture's shape and starts Place (as above). **Apply to a part** puts it on a wall, a seat or an object's part
   (below). **Delete** asks first.

Kept pictures stay on this headset, for your own use: the app never uploads or shares them.

**Surfaces** (`docs/features.md`, "Surfaces"; `docs/materials.md`, "User materials"):

1. **Find surfaces**, type a word or two in English (brick, oak floor, marble) and **Search**. The results come from
   Quixel Megascans (through Fab: accept Fab's licence in Your objects first), Poly Haven and ambientCG, each with
   its badge (MS, PH, aCG). **More** loads the next page.
2. Pick one, then **Import**. The line under it says how far it is. It comes in as one of your materials.
3. Under the results, the materials (**All** or **Yours**): pick one, then **Apply to a part**. **Delete** removes
   one of yours.

**Apply to a part** (a material or a picture): the panel goes, and the part the laser points at shows it at once.
On an imported object it goes on every surface with the same material as the one you point at: point at a sofa's
fabric and only the fabric changes, not the wooden legs.

| Control | Apply to a part |
|---|---|
| Trigger | Put it there |
| Stick up or down | The pattern bigger or smaller |
| Stick left or right | Turn the pattern |
| B, menu button | Cancel: nothing changes |

The room keeps it, with Undo in the footer. A stock room becomes a kept room of its own, as with Place.

**Picking objects up** (`docs/physics.md`): point a controller at an object in the room and hold the grip; it is held
at the laser's end (with the controller in an object, in the hand). The stick brings it nearer or farther and turns
it. Let go to drop it; flick the controller as you let go to throw it. It bounces off the seats, the steps, the walls
and the screen, and stays where it comes to rest, kept with the room. A wall clock, picture or shelf stays on the
wall until you pull it off. B while holding puts it back where you picked it up. In **In this room**, **Put back**
returns a moved object to where it was placed and **Tidy up** returns them all. A text or particles area has
**Attach**: pick the object it follows, and it moves with it; **Detach** leaves it where it is.

**Delete** (imported objects, and the models and pictures an assistant's rooms kept) asks first in the footer. While a
kept room has the object in it, Delete says which rooms instead: rooms are made of the library's objects, so remove it
there first.


## The Mixed reality tab

The **Mixed reality** tab (above System) holds windows to the real room: real
places, the coffee table or the keyboard say, that show through the headset's cameras in every room. Each is a box
fixed to the real place: it stays there when you recentre and next time you start (a new room setup on the headset
moves them; sweep them again then).

- **Sweep an area**: the panel goes and you see the real room. Hold the trigger and pass the controller over the
  place; a tinted box shows what it will keep, turned to fit what you swept (a monitor at an angle gets a box along
  it). Let go to keep it.
- Each area is a row: its name and size, **On**, **Edit** and **Delete** (with Undo in the footer). **All on**,
  **All off**.
- **Edit** works a face at a time. You see the real room, the box tinted and one face of it bright, starting with the
  face towards you. The stick moves that face the way you push it: up and down for the top and bottom, left and right
  for a face on your left or right, up (away) and down (nearer) for a face towards or away from you. The opposite
  face stays put, so moving faces both sizes and moves the box. The trigger goes to the next face, and after the six
  to **Turn**, where left and right turn the box. The menu button keeps it; B puts it back.
- **Settings**, a section of its own: **Passthrough dimming**. The room light dims the cameras' view too, never below
  this (70 % at first).

B cancels any of them. While you mark or edit, a card over the controller says what to do at each step.

## The Library

Files has a Library place: `~/Videos/Library` as posters, seasons and episodes, made the first time you open it. One click
opens, as in any folder. To fill it, ask an agent on the headset to import something; it copies the file and writes the
NFO and artwork. `docs/library.md` has the layout, if you would rather add folders yourself.

## Android apps

Files has an Android apps place. Each folder `~/Android/<name>/` that holds an `.apk` is an app there, shown by the
folder's name. It needs Lepton, the Steam tool; the place says so if it is missing. Copy the APK in, for example to
`~/Android/MyApp/app.apk`, and press its row. The APK's file name must have no spaces for now, and if a folder holds more
than one, the first by name is used. The player does the rest of the setup itself.

A card shows each step as it happens: the display, Android, installing the app, opening it. The first start of an app
takes longest, and later ones take about 20 seconds. The film goes on until the app is ready, and Cancel on the card or
in Files stops the start. If it fails, the card says why. When the app is ready, its window goes on the big screen and
the panel closes.

The window works like the browser (Controls, "The browser on the big screen"): look at it, and the stick moves a
cursor and the trigger clicks; look away, and the stick scrolls. **B is the app's Back.** If Back doesn't get you out of a full-screen player, B goes to the app's main screen instead.

**Leaving stops it.** When the app stops being on the big screen, for any reason, the app and Android shut down
completely: opening a file, Stop in Files, closing it from the panel, the app quitting, or the player closing. Nothing
plays on behind. A login inside the app stays for next time. One app runs at a time: starting another stops the first.

Lepton is a compatibility layer made for games, so video in an Android app may be limited.

## PC tools

All are Python 3.8 or later with the standard library only, or bash. Run them from the repository root. Each one
connects to or serves only the LAN. For the dev link the headset connects out to the listener; the assistant service
(`docs/assistant.md`) listens on the headset itself and needs no PC tool.

| Tool | What | Page |
|---|---|---|
| `app/assistant/tools/assistant.py`, `mcp_server.py` | Optional clients of the assistant service on the headset (which also serves them at `/tools/`): a command line, and an adapter for MCP clients. | `docs/assistant.md` |
| `tools/listener.py` | The dev link's PC end. `serve` waits for the headset; `send`, `describe`, `status`, `events -f`, `wait`, `say` talk to it; `ask` and `answer` are the watch-along answers (`docs/dev/watch-along.md`). | `docs/dev/control-protocol.md` |
| `tools/cast.py` | Play a PC file (through its file share), a headset path or a web page on the headset; `--watch` a folder; Send to and desktop shortcuts. | `docs/cast.md` |
| `tools/voice.py` | The voice grammar and the transcriber hook for push-to-talk. `python tools/voice.py "dim the lights"` prints the actions. | `docs/dev/voice.md` |
| `tools/audio_sink.py` | The PC end of PC audio: plays the film's sound on the PC, with a jitter buffer. | `docs/pc-audio.md` |
| `tools/fake_media_server.py` | A small media server (UPnP/DLNA) serving a folder, for tests. | `docs/media-servers.md` |
| `tools/push-app.sh` | Copy `app/` to the headset; `--watch` for hot-reload. | `docs/dev/hot-reload.md` |
| `tools/package.sh`, `tools/install-on-frame.sh` | Build a release tarball; install it on the headset without root. | `docs/packaging.md` |
| `tools/steam_shortcuts.py` | Add the player to the Steam library on the headset (`install-on-frame.sh --steam`). | `docs/packaging.md` |

Ports (all LAN):

| Port | Direction | What |
|---|---|---|
| TCP 47800 | headset to PC | Dev link (`listener.py serve`); its control port for `send` is TCP 47802 on 127.0.0.1 only |
| TCP 47801, 47802 | PC to headset | The assistant service, when switched on: 47801 plain HTTP for the guide only, 47802 HTTPS for the API; open while "Let an assistant find me" runs or once an assistant is paired; private addresses only |
| TCP and UDP 47803 | PC to headset | PC windows, when switched on (`docs/pc-windows.md`): UDP for discovery, TCP with TLS for the control and stream connections; open while "Add a PC" runs or once a PC is paired; private addresses only |
| TCP 47820 | headset to PC | PC audio (`audio_sink.py`) |
| TCP 47880 | phone or PC to headset | Phone remote and file sharing, when switched on |

The dev link's protocol, every command and every event are in `docs/dev/control-protocol.md`. With a listener
running, `python tools/listener.py describe` prints the live schema.
