# Morning checklist: the raw per-agent sections (archive)

The sections as each agent appended them, kept verbatim so nothing is lost. **Do not tick here:** the runbook
`docs/morning-checklist.md` holds every check from these sections, in order, and is the single source.

---

# Morning checklist

What to check in the headset for work done while it was off. Append only; several agents write here. Each section
names who added it and the feature. Tick items off by editing `[ ]` to `[x]` and adding a note.

## Playback features (app-features; details in `docs/features.md`)

### #36 Wall-clock end time

- [ ] Open a film with the info overlay on (`--overlay` or the view button). The time line ends in "ends HH:MM".
      Check it against a real clock: remaining time plus now. If it is off by whole hours, the device has no time
      zone set and the app reads UTC.

### #2 Battery versus film end

- [ ] With the overlay on and a film playing, the battery line reads "battery NN %, ends HH:MM | film ends HH:MM",
      not "no battery". If it says "no battery", run `ls /sys/class/power_supply; cat /sys/class/power_supply/*/type`
      over ssh and note which entry is the battery.
- [ ] Note the predicted battery end in the first minute and again after 15 minutes of playback. They should agree
      within about 15 minutes, and the implied drain should be near 9 W (about 35 % an hour).
- [ ] Plug the charger in: the line says "charging". Unplug: a forecast returns within a few seconds.

## Dev plumbing (dev-plumbing; details in `docs/dev/`)

### #3 Hot-reload on the device (`docs/dev/hot-reload.md`)

- [ ] From Git Bash on the PC: `tools/push-app.sh`. It should list the copied files. Note whether it used rsync
      (lines start with `>f`) or the tar fallback (lines start with `pushed`). If ssh asks for anything, note what.
- [ ] Start the app on the device with `-- --dev` at the end of the usual command line. The log shows
      `Hot-reload: watching .../spike03/app/ (N files)`.
- [ ] Run `tools/push-app.sh --watch` on the PC. Change the colour of something in `app/shaders/env_unlit.gdshader`
      (for example the floor in the dim room) and save. Within about two seconds the log shows
      `Hot-reload: gdshader res://shaders/env_unlit.gdshader` and the room changes in the headset without a hitch.
- [ ] Change `ambient_level` in `app/environments/dim_room.tscn` and save. The log shows
      `environment dim_room instanced again` and the room light changes. Note any visible stutter.
- [ ] Put a deliberate typo in `app/scripts/info_overlay.gd` and save. The log shows `does not compile ... the old
      version stays` and the app keeps running. Fix the typo; the next save reloads it.

### #4 3D depth slider

- [ ] Play a 3D film (or `stub://flat_sbs`). There is no controller binding yet; set `[stereo] depth=0.02` in
      settings.cfg, or use the pane once it has the slider. The picture should sit further back, with no doubled
      edges. Try -0.02: it comes nearer. Note the value that is most comfortable.
- [ ] In a 180 film, a small depth (0.01) should not tear the picture at the seam behind you.

### #7 Resume per file

- [ ] Play a real film past a minute, open another file, then the first again. It should continue about 3 s
      before where it was, with the picture and sound in step (the seek happens right after the open).
- [ ] Quit the app mid-film (or take the headset off and kill it over ssh), start it with the same `--file=`: it
      resumes. `~/.local/share/godot/app_userdata/VR Video Player/resume.cfg` holds the entry.
- [ ] B (previous) after a resume goes back to the start.

### Subtitles (stand-in display)

- [ ] Open a film with a text subtitle track (SubRip or ASS in an MKV). Press S on a paired keyboard, or set
      `[subtitles] enabled=true` in settings.cfg before starting. Lines appear in white inside the bottom of the
      picture, in time with speech.
- [ ] Check the size: readable without effort on the default 3 m screen and in the cinema. Note a better `[subtitles]
      size` if needed.
- [ ] In a 180 film the line sits low in front; check it is readable and not uncomfortable to focus on.

### #11 Catch-up replay

- [ ] With a paired keyboard (or the pane's button once it exists), press Backspace during dialogue with subtitles
      off. Playback jumps back 10 s, lines appear, and after 10 s they go away again.
- [ ] Check the first line of the replay is there. If it is missing, the keyframe before the target was after that
      line's start (see `docs/features.md`, #11).

### #5 The PC listener (`docs/dev/control-protocol.md`)

- [ ] Find the PC's LAN address (`ipconfig`, the 192.168.1.x one). On the PC: `python tools/listener.py serve`.
      If Windows asks whether Python may accept connections, allow private networks.
- [ ] Start the app on the device with `-- --listener=<PC address>` at the end of the usual command line. Within a
      second or two the listener prints `headset connected`, the hello (engine, model `...`), a `state` line and a
      `battery` line with a real percentage. Note the battery value.
- [ ] In a second terminal on the PC: `python tools/listener.py send ping`. It answers in well under a second.
- [ ] Stop the listener (Ctrl+C), wait 10 s, start it again. The headset reconnects within about 30 s, and the app
      never stutters meanwhile. Note any hitch in the headset during the reconnect.
- [ ] Take the headset off and put it on again: the listener shows `session` events (`visible`, `focussed`).

## Video engine (engine-demux; details in `spikes/03-player/README.md`)

Binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_P010` (fork `e3694cc68e`). It carries the window merge,
SMB, the software fallback, Q08C by default and P010. Copy `spikes/03-player/project/main.gd` and `video.gdshader`
with it. Command lines are in the README sections named below.

### Q08C as the default capture format ("UBWC capture")

- [ ] Play the 8-bit full-SBS documentary file with no `--capture-format`. The log shows `imported N decoder buffers ... Q08C
      (UBWC)` and the picture is right. There is no `reopening the decoder with NV12` line.
- [ ] Seek a few times (`--seek-every=20 --seek-by=60`) for two minutes. Every seek settles and there are no
      decoder errors. Note anything that differs from an NV12 run.

### Software decode fallback ("Software decode fallback")

- [ ] Play the 720p 10-bit HEVC file and a VP9 file with the stock module. The log shows `software decode` with the
      reason, and the picture is right. Note `process CPU N% of a core` from the 2 s line, and the same for an 8-bit
      hardware file as a baseline.

### P010 with the patched iris module ("10-bit in hardware: P010")

- [ ] Stock module, a 10-bit file: the log shows `linear 10-bit (P010) not available` and plays in software.
- [ ] Patched module, the 720p 10-bit file, no variable: `P010 available`, a P010 layout line without `DOESN'T FIT`,
      and `imported N decoder buffers ... P010`. Screenshot at frame 300.
- [ ] Same file with `HWVIDEO_P010=0`: the software reference screenshot. The two should match closely. A shift or
      wrong colours below a line means the chroma offset is wrong; rerun with `--chroma-offset=` from the kernel
      agent's layout.
- [ ] Only if the first patched run said `not available` at idle: rerun with `HWVIDEO_P010=1` and note whether the
      stream's own list offered P010.
- [ ] Patched module, the 2160p 10-bit file (too big for software): it plays. Note decode fps and GPU ms.
- [ ] The `Colour:` line names the matrix (BT.709 for these files). A BT.2020 or HDR file shows `BT.2020` and
      `HDR: not tone-mapped yet`. Its picture will look wrong until tone mapping exists; that is expected.

### #15 Chapters and the d-pad map

- [ ] First run with the shipped action map: every control works as before (the map is unchanged).
- [ ] Then create `app/override.cfg` as in `docs/features.md` (#15) and restart with `--debug`. Check that the
      controller profile still binds (the log line "Interaction profile for /user/hand/left changed to
      .../frame_controller_valve") and that trigger, A, B, menu and the stick still work. If the profile does not bind,
      delete `override.cfg`: the d-pad paths are rejected.
- [ ] With it bound: on `--file=stub://flat_mono --overlay`, d-pad right goes to the next chapter (overlay "chapter
      2/5 Colour bars"), left goes back, down replays 10 s with subtitles.
- [ ] Once the engine has `MediaSource.get_chapters()`: a film with chapters shows them in the overlay.

### #56 The control API (`docs/dev/control-protocol.md`, "Commands")

- [ ] With the listener connected: `python tools/listener.py describe` lists the commands, settings and events.
- [ ] `send open ~/spike01/streams/documentary_sbs.h264` (or any film on the device). The reply comes back once the file
      is open, with `playing: true`. Then try `send seek 60`, `send pause`, `send play` and `send set volume 0.3`.
      Each acts in the headset within a frame or two.
- [ ] `send set mode 360tb`, then `send set mode auto`. The projection changes and changes back.
- [ ] `send reload app`. The main scene restarts in the headset (a moment of black is expected). The listener stays
      connected, and `send get` answers afterwards. Note how long the black lasts.

### #16 Screenshots over the link (`docs/dev/screenshots.md`)

- [ ] With a stereo film playing: `send screenshot`. Three files appear in `~/.frame-listener/shots/`. The left
      and right pictures match what each eye sees, and the third shows the room from behind.
- [ ] Note any visible hitch or flattening in the headset while the pictures are taken, and how long the command
      takes (the listener's log has the times).

### #17 Sleep timer

- [ ] With a keyboard, press Z on a playing film (overlay: "sleep in 15 min"). For a quick check set `[sleep]
      fade_seconds=10` and use the pane or a 1-minute timer from the dev port if it exists. The room and picture dim
      and the sound fades smoothly, with no clicks, then it pauses. Pressing play brings everything back.

### #20 Room light follows playback

- [ ] In the cinema (`--env=cinema`), start a film: the room dims over about 2 s. Pause: it comes up quickly. Open
      the menu while playing: it comes up; close it: it dims again. Note whether 0.35 (`[room] play_level`) is too
      dark or too bright.

### #25 Container metadata first

- [ ] Only once the engine has the stereo / spherical keys: open a 180 or 360 file whose name has no tags but whose
      container has the metadata. The overlay's mode line says `[metadata]` with the right mode.

### #10 Scene control and #23 the permission ring (`docs/dev/scene-control.md`, `docs/dev/permission-ring.md`)

- [ ] Start the app with `-- --listener=<PC address>` only (no `--dev-allow`). `send spawn type=MeshInstance3D` is
      refused, the error says how to allow it, and the headset shows "Refused remote spawn" about 1.2 m ahead and
      below eye level. Note whether the toast is readable and placed comfortably.
- [ ] Restart with `-- --listener=<PC address> --dev-allow=60`. Run the spawn example from `scene-control.md` (the
      orange unshaded box). The box appears about 1.5 m ahead; the toast says "Remote: spawn Box".
- [ ] `send undo`. The box disappears and the toast says "Undone: spawn Box".
- [ ] `send set dev/remote_changes allow` is refused ("can only be changed on the headset").
- [ ] Copy a small .glb to the PC and run `send load_gltf --b64 data=<file> name=Test`. It appears in front.
      Note any frame drop while it loads (the listener log has the time of the command and the reply).
- [ ] Restart with `--dev-code` added. `send run 'return main.env_id'` answers the environment's id.

### #27 Picture controls

- [ ] Until the pane has sliders, set `[picture_void] lift=0.12` in settings.cfg and play a dark film. Shadows should
      open up while black stays black. Remove the key: the picture is as before.

### #28 Language memory

- [ ] Open a file with two audio languages, pick the second in the menu's Sound/Audio tab. Open another file with the
      same languages: it starts in the language you picked, with picture and sound in step.

### #57 Stats for nerds (`docs/dev/stats.md`)

- [ ] With the listener connected and a film playing: `python tools/listener.py send stats every=1`, then after
      ten seconds `python tools/listener.py events -n 3 -e stats`. Check that these are filled in and plausible:
      `gpu.clock_mhz` (about 300 during playback), `battery.power_w` (about 8 to 10 W), `thermal.zones` (40 to 60
      °C), `cpu.process_percent_of_core`, `video.decode_fps` (the film's rate), `video.bitrate_mbps`, and
      `video.queue`. Note any that are missing or null.
- [ ] Check that `frames.histogram` puts nearly all frames at or below 11.1 ms at 90 Hz (13.9 ms at 72 Hz).
- [ ] `send stats every=0` stops the events.

### #31 Curved screen

- [ ] Set `[screen_void] curve_radius=3.0` (the default distance) and open a film: the screen curves around you, the
      picture is not distorted at the edges, and 3D still fuses. Remove the key for flat.

### #32 Haptic ticks

- [ ] Hold the right stick to one side while a film plays: one light tick per 10 s seek step. Too strong or too weak?
      Note a better `[haptics] strength`.
- [ ] Menu hover ticks only once the pane calls `features.haptics.hover(hand)` (app-shell).

### #35 Zoom and pan

- [ ] With a keyboard on a letterboxed film: `=` until the bars are gone, numpad 8/2 to centre it. Reopen the file:
      the zoom is remembered.

### #59 2D from 3D

- [ ] On `stub://flat_sbs`, press 2 (keyboard): with one eye closed at a time, both eyes see LEFT EYE; press again,
      both see RIGHT EYE; again, back to 3D.

### #77 Horizon correction

- [ ] On a 360 or 180 film, numpad 9 a few times (keyboard): the horizon rolls clockwise; numpad 0 levels it. The
      sphere stays centred on the head.

### #79 Edge fade

- [ ] Set `[stereo] edge_fade=0.03` and watch a 3D film with things near the screen's edges. The edges are soft and
      objects crossing them don't snap. Say whether it should be on by default.

### #61 Subtitle delay

- [ ] With subtitles on, press `'` a few times (keyboard): lines come later by 0.1 s per press. Reopen the file: the
      delay is still there for that track.

### #60 Sidecar JSON

- [ ] Pick a mode for a local film in the menu. A `<name>.vrmode.json` appears next to it (`ls` over ssh). Delete
      `settings.cfg`'s `[files]` entry or use another device: the mode comes back from the sidecar (`[sidecar]` in the
      overlay). If writing into the film folder is unwanted, set `[sidecar] write=false`.

### #78 Shuffle, repeat, queue

- [ ] Set `[queue] repeat="one"`, play a short real clip to its end: it starts again. With `repeat="all"` and
      `continuous=true` in a folder of short clips: it plays through and starts over.

### #80 Frame step and A-B loop

- [ ] On a real film with a keyboard: period steps one frame (paused), comma steps back. Note how long a step takes.
- [ ] Slash twice a few seconds apart: it loops between the marks (overlay "loop ..."); slash again stops it.

## Controller labels and our controller model (app-shell)

### Authored label layout (0944c0d)

- [ ] The device snapshot sets 2 and 16 were taken with 1dcc1d0, before the authored layout. Run the current build
      with `-- --labels-debug --snapshot-dir=/home/steamos/snaps`, and take a set
      (left bumper + A). Expected on the right controller: PREV beside B, NEXT beside A, MENU above the menu button,
      the stick legend in the upper inner area, and MOVE SCREEN on the handle behind the grip. No cut letters and no
      bar after MENU.
- [ ] The left controller's frame is the right one mirrored (the left dump was made while it was untracked). Check
      that the left labels sit on the plastic and read upright.

### Our controller model (`-- --controller-model=ours`)

- [ ] Start with `--controller-model=ours`. Our model should sit exactly where the runtime's model was, with the
      legends printed on it. Note any offset or turn against the real controller (pass-through or by feel).
- [ ] The printed legends are always there and legible with the controller brought close; the print changes when the menu opens and when a window is on.
- [ ] Known gap: our model's parts don't move (no trigger, stick or button animation).
- [ ] Decision for the user: the model is derived from Valve's CAD under CC BY-NC-SA 4.0 (non-commercial). Keep it as
      an option, make it the default, or drop it.

### #76 Favourites and search

- [ ] Data only until the pane shows it. Over ssh, after the pane lands: star a film, search for a word of its name
      with the on-pane keyboard; it is listed first. Search the SD card for a common word and note how long it takes.

## Kernel module (P010) (kernel-p010; details in `build/iris-module/README.md`)

A patched copy of Valve's iris decoder module that offers linear P010 for 10-bit HEVC. It loads in memory only;
a reboot restores Valve's driver. All files are in WSL at `~/src/deckard-kernel/out/` (from Windows:
`\wsl.localhost\Ubuntu\home\<user>\src\deckard-kernel\out`), listed in `out/SHA256SUMS`. A bad module can crash
the kernel: then the headset reboots, or needs a long press on the power button. Run the engine's "P010 with the
patched iris module" items above between step 4 and step 7, while the module is loaded.

- [ ] **0. Copy the files** (Git Bash on the PC; `~/iris-module` must not exist on the headset yet):
      ```
      O=//wsl.localhost/Ubuntu/home/<user>/src/deckard-kernel/out
      scp -r $O/iris-module frame:~/iris-module
      scp $O/test/v4l2dec frame:~/spike01/v4l2dec
      scp $O/test/main10_3832x1596_10s.h265 frame:~/spike01/streams/
      ```
- [ ] **1. Read-only check** (no sudo): `ssh frame bash iris-module/load-temporary.sh --check iris-module/iris-p010.ko`
      Expect `Checks passed: 6.18.0-ge66bc2ca6f8c, Valve's iris.ko, matching config and vermagic, iris idle.` and the
      formats `'Q08C' 'NV12' 'NV21' 'Q10C' 'AB24' 'QC24'` (no P010). Any `Error:` line: stop here and note it.
- [ ] **2. Baseline with Valve's driver** (optional): `ssh frame bash iris-module/device-test.sh before`
      Expect CAPTURE `Q10C` only after SOURCE_CHANGE, and `result ok`.
- [ ] **3. Load** (type it yourself; sudo asks for the password):
      ```
      ssh -t frame
      sudo bash ~/iris-module/load-temporary.sh --load ~/iris-module/iris-p010.ko
      ```
      Expect `'P010'` in the HEVC CAPTURE list and `Temporary module iris-p010.ko is loaded. Records:
      /run/iris-module-temporary.XXXXXX`.
- [ ] **4. Decode tests** (no sudo): `ssh frame bash iris-module/device-test.sh after`
      Logs go to `~/spike01/results/p010_*.txt`. Expect:
      - `p010_default`: `G_FMT CAPTURE after SOURCE_CHANGE: P010 3840x1600`, `plane 0: bytesperline 7680 sizeimage
        18432000`, CAPTURE lists `Q10C` and `P010`, visible `3832x1596+0+0`, 120 frames, 0 with ERROR, `result ok`,
        and the dump `~/spike01/p010_s0_f30_3840x1600_P010.raw` (18432000 bytes).
      - `p010_q10c`: still works, 120 frames.
      - `p010_nv12_regression`: the summary says the frame 30 MD5 matches spike 01 (`fb6348591e4c22576f5279b3c82a0405`).
      - `p010_8k`: 600 frames, `bytesperline 15360 sizeimage 88473600`. Note the fps (spike 01: 140 fps to Q10C,
        129 fps to NV12).
- [ ] **5. Kernel log** (interactive): `ssh -t frame`, then `sudo dmesg | tail -60`. No oops, no `smmu` fault, no
      `0x5000003`. Save the output with the results.
- [ ] **6. Check the picture on the PC** (Git Bash or WSL):
      ```
      scp "frame:~/spike01/p010_s0_f30_3840x1600_P010.raw*" .
      ffmpeg -f rawvideo -pix_fmt p010le -video_size 3840x1600 -i p010_s0_f30_3840x1600_P010.raw -vf crop=3832:1596:0:0 -frames:v 1 hw_f30.png
      ffmpeg -f rawvideo -pix_fmt p010le -video_size 3840x1600 -i p010_s0_f30_3840x1600_P010.raw -i $O/test/main10_3832x1596_10s.h265 -lavfi "[0:v]crop=3832:1596:0:0,format=yuv420p10le[a];[1:v]select=eq(n\,30),format=yuv420p10le[b];[a][b]psnr" -f null -
      ```
      `hw_f30.png` must look like `$O/test/sw_f30.png` (airport "Departures", people with pink suitcases), and the
      PSNR must be `inf`. A very dark picture: the samples are LSB-aligned. Chroma offset: the UV plane is not at
      `bytesperline x 1600`. A sheared or doubled picture with an empty (green) lower part: the firmware took the
      stride as bytes, not pixels. Note which, if any.
- [ ] **7. Restore Valve's driver**: `ssh -t frame sudo reboot`. Afterwards the step 1 command must pass again.

### #13 Phone remote (`docs/remote.md`)

- [ ] Start the app on the device with `-- --remote` at the end of the command line. The log shows
      `Phone remote: on, http://192.168.1.x:47880/`. Note the address.
- [ ] Until the pane shows the QR code, get the full URL with the code over the dev link:
      `python tools/listener.py send run 'return tree.root.get_node("PhoneRemote").get_url()'` (needs `--listener`,
      `--dev-allow` and `--dev-code`). Open it on the phone. The title and time update every second.
- [ ] From the phone: play, pause, +10 s, drag the seek bar, change the volume. Each acts in the headset within about
      a second.
- [ ] Tap Test patterns and pick one; tap Network and a saved host. The listing appears without a stutter in the
      headset.
- [ ] Open the pane's "Add host" form, focus the host field, type a name on the phone and press Type. The text
      appears in the field.
- [ ] Type a web page into "Web page" and press Open. The Browser source starts on it.
- [ ] Check that the phone's request without the code is refused: open `http://<address>:47880/` in a private tab
      (no code); the page says to scan the QR code.

### #74 Accessibility pack

- [ ] Set `[accessibility] subtitles_always=true`: every film opens with subtitles. `monocular=true` with
      `monocular_eye=0`: 3D films show the left eye to both eyes. UI scale and left-handed need the pane.

### #43 Cast from the PC (`docs/cast.md`)

- [ ] With the listener running and the headset connected, and this PC saved under Network on the headset:
      `python tools/cast.py "<shared folder>/<a film>.mkv"`. It prints the smb:// URL and "playing: ...", and the film
      plays in the headset from the share.
- [ ] `python tools/cast.py --install-sendto`, then right-click a film in Explorer > Send to > Play on headset. It
      plays. Delete `%APPDATA%\Microsoft\Windows\SendTo\Play on headset.cmd` afterwards if not wanted.

## Video engine: app features (engine-demux; details in `spikes/03-player/README.md`, "Engine features for the app")

Binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_FEATURES` (fork `6b7f34ddbc`; everything of PLAYER_P010
too). Desktop tests pass; these need the Frame.

- [ ] Overlay numbers during hardware playback: run the spike with `--overlay-stats` on the documentary file. The
      `Overlay:` line has `gpu_mhz`, temperatures and `battery_power_w`. If one is missing, run
      `ls /sys/class/devfreq /sys/class/thermal; cat /sys/class/thermal/thermal_zone*/type` and note the names.
- [ ] In the same line, `video_kbps` moves with the scene and `decode_fps` and `shown_fps` sit near 24.
      `process_cpu_percent` is low.
- [ ] Playback speed: play a 4K file with audio and set `MediaSource.playback_speed = 1.5` (app control, or the
      spike once it has an option). Voices keep their pitch, the picture keeps up, and `dropped_per_second` stays near 0.
- [ ] A subtitle file next to a film on the SMB share: `MediaBrowser.find_subtitles()` lists it, and
      `add_external_subtitle()` loads it in well under a second over Wi-Fi.

### #49 SMB host discovery (`docs/host-discovery.md`)

- [ ] With the listener connected: `python tools/listener.py send discover_hosts 4`. This PC should appear, from
      NetBIOS, with `file_server: true`, and any NAS on the LAN too. Note what is missing. If this PC is missing,
      check that "NetBIOS over TCP/IP" is on for its Ethernet adapter. Today it is registered only on the Hyper-V
      switch.
- [ ] Note any frame hitch in the headset while the scan runs (about 255 packets per network).

### #30 Scene recipes (`docs/recipes.md`)

- [ ] With `--listener` and `--dev-allow=30`: spawn the orange box from `docs/dev/scene-control.md`, then
      `send save_recipe "Test room"`. Switch to another room in the pane; "Test room" is in the environment list,
      and picking it brings the box back where it was, with the screen in the same place.
- [ ] Quit, start again with `-- --env="recipe:Test room"`. The room comes up with the box.
- [ ] `send delete_recipe "Test room"` (after switching to another room) removes it from the list.

### #48 Test lab (`docs/test-lab.md`)

- [ ] Start with `-- --file=lab://alignment`. With both eyes open, the red and cyan half-lines meet in one straight
      cross. Note any step, in ticks (2 px each), vertical and horizontal.
- [ ] Press A to go to `lab://convergence`. Note the outermost "near" and "far" rings that still fuse into one.
- [ ] A to `lab://judder_24`, `_30` and `_60`. The bar should glide evenly at 72/90 Hz. Note any stutter, and
      whether the lit cell ever holds or skips.
- [ ] With the listener: `send bandwidth_test path=smb://<host>/<share>/<a film> seconds=8`. Note `mbps_avg`,
      `mbps_peak` and `open_ms` over Wi-Fi.

### #50 Subtitle files next to the video

- [ ] Put `Film.en.srt` next to a local film without subtitle tracks. Open it with subtitles on: the file's lines show.
      On a share, the same, and note how long the subtitles take to appear after the film starts.
- [ ] A film whose audio is in your language with a `Film.<lang>.forced.srt` next to it, subtitles off: only the
      forced lines show.

### #69 Playback speed

- [ ] Keyboard 0 twice on a film with speech: 1.5x, voices at their normal pitch, lips in step, the overlay says
      "speed 1.5x" and the end time moves earlier. 9 back to 1x. Try 2x on the largest file: no dropped frames in
      the overlay?

### #60 Sidecar JSON: writing is now off by default (team lead, 2026-10-31)

- [ ] Decide whether the app may write `<film>.vrmode.json` files into the film folders. To try it, set `[sidecar]
      write=true`; reading such files is always on.

### Software seeks skip unreferenced pictures (engine-demux; PLAYER_FEATURES2)

- [ ] The 1080p 10-bit HEVC film over SMB with PLAYER_FEATURES2, the same seek run as the software fallback test, twice: once as is
      and once with `HWVIDEO_SW_SEEK_NONREF=0` in front of the command. Compare the `Seek N settled in M ms` lines
      and the "frames skipped so far" counts. Expect shorter settles and far fewer skipped frames without the
      variable, and the same picture after each seek.

## The pane (app-shell; docs/ui-design.md, commits 9cfc85e and b329777)

The old menu is gone. All of this is untested in the headset. Start with `-- --dev` so the System tab's dev tools show.

### Decisions where the doc was silent or self-contradictory (confirm or change)

- [ ] **Size.** The doc says 24 x 20 cm and 740 x 600 px (3080 px/m), and also that 15 px body text is about 1° at
      0.55 m. Those disagree: at 3080 px/m, 15 px is 4.9 mm, about 0.5°, and rows are 1.4°, under the doc's 2.5°
      minimum. I built the literal size. If the text is too small, set `[pane] scale=2.0` in settings.cfg (48 cm, the
      doc's angles) and compare. Docked at 0.9 m, the literal size is smaller still (0.3° text).
- [ ] **Alpha.** The renderer blends in linear light, so the doc's 94 % surface let a bright film show through at
      about a quarter of its brightness. The pane quad maps alpha as 1 - (1 - a)^2.2, which looks like sRGB
      compositing. The glance state's 72 % is mapped the same way.
- [ ] **Reading pose thresholds:** enter when the controller is less than 40 cm below the eyes, within 45° of the
      head's forward, and its face within 40° of the head; leave at 50 cm, 55° and 55°. The 45° view cone is wider
      than the doc's 40°, because a controller held at the chest while looking straight ahead is about 41° down.
- [ ] **Held pose:** upright and facing the eyes; it does not roll with the wrist. Pushed out to 0.5 m from the eyes.
- [ ] **Freeze release** by hand motion: 4 cm. After a release it re-freezes once it has eased back (150 ms).
- [ ] **Dock** is pinned in world space; it does not follow the head as the old panel did. It sits 0.9 m along the
      line of sight and 12 cm below it, so it also works lying down.
- [ ] **Glance** shows the wall clock (96 px light), "1:24 left, ends 23:20", the battery line, the name and a thin
      progress line, at 72 % opacity.
- [ ] **Transport** buttons are words: Previous, −10 s, Play / Pause (ringed), +10 s, Next (the doc forbids icons
      where a word does).
- [ ] **Mode diagrams** are two groups: layout (Mono, SBS, TB) and shape (Flat, 180°, 360°, Fisheye).
- [ ] **Forms** (add host, web page) replace the list and also hide the seek bar and transport, so the keyboard fits;
      no slide animation. The breadcrumb is the path as text; ".." goes up.
- [ ] **Not there because the features don't exist yet:** Sound's night mode and output choice, Subtitles' depth and
      external files, Room's seat, the phone-remote code on the keyboard.
- [ ] **No laser stub** any more: lasers show only on the pane (or on a captured window, as before).
- [ ] **Docked:** the right stick moves the focus and the right trigger activates it; the left stick still seeks.
- [ ] **Grip-hold permission:** grip held 2 s on the right hand with the laser on the pane, dev mode only. Otherwise the
      grip on the pane does what it always did (moves the screen).

### Headset checks

- [ ] At launch the pane is docked ahead and a little low, with DOCKED in its corner. Read the footer and a list row
      without effort? Note the distance and size you would want.
- [ ] Docked: right stick left / right / up / down moves the focus (outline plus left bar); the trigger activates;
      a tick on each move. Menu hides the pane; menu again brings it back in front.
- [ ] Raise the left controller to read it: the pane slides from the dock into the hand. Lower it: it fades out.
      Note whether it flickers at the edge of the pose, and whether it appears when you don't want it (resting the
      hand on a knee or the chest).
- [ ] Glance: the clock, time left and end, battery and title are readable at a glance, and it is clearly "not
      clickable".
- [ ] Point the right controller at it: the laser appears only then, the pane switches to the full view and stops
      following the left hand. Small left-hand tremor must not move it. One light tick per new target.
- [ ] Trigger clicks, either stick scrolls the list under the laser, and the pane stays put while scrolling.
- [ ] Laser off for half a second, or the left hand moved a few cm: the pane eases back into the hand without a jump.
- [ ] Poke a button with the right controller's tip: it clicks once, with a tick.
- [ ] Files: rows show resume markers (accent "0:42 ▶") after watching a file a while, and mode chips on 3D files.
      Add a network host with the keyboard; the Browser place still works.
- [ ] Picture: the mode diagrams change the mode; depth, curvature, zoom, picture sliders all move the picture.
- [ ] System: Left-handed swaps the hands at once. Stats shows frame and decode lines. Phone remote on shows a URL
      and a QR code that a phone can scan off the pane.
- [ ] Dev (`--dev` with the listener): hold the right grip on the pane for 2 s: the footer says remote changes are
      allowed for an hour. A remote change from the PC shows "Remote: ..." with Undo in the footer, and Undo works.
- [ ] The halo and the lit edge look quiet, not glowing. The laser and dot read against bright films.
- [ ] GPU cost: the pane's SubViewport renders every frame while it is visible (glance included). Compare frame times
      with the pane docked and hidden.

### #82 Self-benchmark (`docs/benchmark.md`)

- [ ] Start once with an empty `[benchmark]` section and nothing on the command line. Leave it idle for 20 s. The log
      shows `Benchmark: <codec> <size> hardware: N fps decoded ...`. Note the line.
- [ ] With the listener: `send stats`. The `benchmark` key has the same result.
- [ ] `send -t 60 benchmark path=<a 4K or 8K file on the headset>`. Note `decode_fps`, `realtime_x`,
      `mpix_per_s` and `hottest_c`. Then the same with a file on a share, and compare.
- [ ] Start again: no benchmark runs. Then, with an empty `[benchmark]`, open a file within 8 s of the start: it does
      not start.

### #91 Tours and kiosk mode (`docs/tours.md`)

- [ ] Copy a tour file to `~/.local/share/godot/app_userdata/VR Video Player/tours/demo.json` with two local files,
      a screen move with `"async": true` and a `{"environment": "cinema"}` step. Start with `-- --tour=demo`. The
      files play in turn, the screen glides, the pane stays out of the view. Note any judder during the screen move.
- [ ] The same with `--kiosk`: it loops. Raise the pane and use it: the tour goes on. Then `send tour stop=true`.
- [ ] A file on a share in the playlist: it opens within the 30 s limit, or the log says why.
- [ ] After a tour, the saved screen size and room are the ones from before it.

### #67 Subtitle pictures and styles (engine-demux; PLAYER_SUBS, fork `153727c6ce`)

Binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_SUBS` (everything of PLAYER_FEATURES2 too). Desktop tests
pass. Details in `spikes/03-player/README.md`, "Subtitle pictures and styles".

- [ ] Play the half-SBS animated 3D film with its full French PGS track (track 1) once the app draws `images`. Captions appear in
      each eye at the right depth, and the picture clears between lines.
- [ ] The same with the documentary's VobSub track (track 0). Captions are blue with a black edge.
- [ ] During both, note `process_cpu_percent` in the overlay against the same file with subtitles off. Expect no
      visible difference.

### Pane additions (app-shell, 20f8700)

- [ ] System, Pane: drag Size, Dock distance and Glance opacity; each applies at once. Note the values you like and
      tell app-shell (they become the defaults). Reset layout goes back to the doc's numbers and docks the pane.
- [ ] System, Accessibility: Larger pane grows the pane; One eye for 3D shows one eye's picture to both.
- [ ] Files, Network: "Find hosts on this network" lists the PC and the NAS within 3 s; a found host opens Add host
      with its name filled in.
- [ ] Files, Queue / Favourites / Search: a queue row jumps; Favourite on a folder's bar adds it; Search with the
      keyboard finds a file by a word of its name.
- [ ] Sound: speed 1.5x plays faster with the voice's pitch kept. Subtitles: an .srt next to a film shows as a
      loaded file and a track.
- [ ] System: a calibration card opens; Measure bandwidth on a share file gives a plausible Mbit/s; Run benchmark
      shows progress and a summary.
### #8 Director mode (`docs/director.md`)

- [ ] Open a film with a `.srt` next to it. With the listener: `send find_line query=<a word you remember>`. The hits
      have the right times. `send jump_to_line query=<the word>`: the line is heard from its start.
- [ ] A film with an embedded text track, once the engine has `get_subtitle_lines`: `find_line` says
      `"source": "engine"`. Note how long the first search takes on a share.

### Keyboard, moving controller model, battery warning, watch-along card (app-shell)

- [ ] Keyboard (969fccc): Files, Network, + Add host. The quick row (smb://, .local) types whole strings; ?123 shows
      symbols; Shift once gives one capital, twice locks; < and > move the caret; Paste pastes the clipboard. Show
      password reveals it. The form and keyboard fit the pane without cutting the bottom row.
- [ ] Our model moves (72d5cc5): with `--controller-model=ours`, pull the trigger, squeeze, push the stick each way
      and click it, press A / B / menu / view. The trigger should swing back about its top without passing through
      the body; compare each part's travel with the runtime model (start without the flag, same inputs). X, Y and
      the d-pad don't move: no action is bound to them in the shipped map.
- [ ] Controller battery (caea999): the log's first lines say "Controller batteries: ...". Note what it lists. If it
      says "none", the controllers' charge isn't under /sys/class/power_supply and the warning can't work this way;
      run `ls /sys/class/power_supply; grep . /sys/class/power_supply/*/{type,scope,model_name,capacity}` over ssh.
- [ ] Watch-along card (cfaae75): with the listener connected, `python tools/listener.py send card text="Hello from
      the PC" title="Test"`. A card appears to the right of the screen's top edge; point the right laser at it and
      pull the trigger: it goes. A second one with `seconds=5` goes by itself. Is it readable, and is the place right?

### #67 Subtitle rendering and #65 a second subtitle track (app-features)

- [ ] A film with a text track, subtitles on: the lines show below the picture, sharp, not on the pane. Is the size
      right at the default? Try Size 0.7 and 1.5 in the Subtitles tab.
- [ ] A film with italic or coloured lines (an .ass file next to it, or SubRip with <i>): italic, bold and colour show.
- [ ] A Blu-ray rip with a PGS track (or a DVD rip with VobSub): pick it in the Subtitles tab. The picture lines show in
      the band at a sensible size, and go when they should. Note the engine build: this needs engine-demux's bitmap
      events.
- [ ] A 3D film: set [subtitles] depth = 0.5 in settings.cfg. The lines float in front of the screen and look the
      same size. Is 0.5 m comfortable? Also try position = "inside".
- [ ] A 180 or 360 video with subtitles: the lines are low in front, about 10 degrees down. Readable?
- [ ] Second track: a film with two subtitle files next to it (Film.en.srt, Film.fr.srt), main track English. Shift+S
      on a keyboard (or the pane, once it has the control) shows the French file above in pale yellow, smaller.
      Open another film with a .fr.srt: the second track comes back by itself.
### #14 / #41 Push-to-talk and voice commands (`docs/dev/voice.md`)

- [ ] Start with `--dev --listener=<PC>`. On the PC: `python tools/listener.py serve`. Send `push_to_talk seconds=3`
      and speak. The listener prints `[voice_clip] {"peak": ...}`. A peak near 0 means the Frame's microphone gave
      nothing: note it (the microphone, or its permission in SteamOS).
- [ ] Play the saved WAV from `~/.frame-listener/voice/` on the PC: it is your voice, at normal speed.
- [ ] Once app-shell binds a controller button: hold it, say "dim the lights and skip to chapter 2", let go. With
      a transcriber set up on the PC, both happen; without one, type `say dim the lights` in the listener.

### Pane: script search, subtitle look, second track, tour status (app-shell)

- [ ] Subtitles, Script (f540d23): on a film with a subtitle file next to it, Find a line, type two words from a line
      you remember, Search: the hits list with times; a row jumps to 0.5 s before the line. "Lines around now" marks
      the line being said.
- [ ] Subtitles, Look (18219cd): Inside the picture / Below the picture, Offset, Nearer (in a 3D film the line should
      float in front of things coming out of the screen) and Background all change the line at once. Second track:
      with two subtitle files next to the film, pick the second; it shows above the first, smaller.
- [ ] System, during a tour (`--tour=...`): the tour's name, round and step, and Stop tour stops it.
- [ ] Subtitles, Script from (36594c8): on a file with two subtitle tracks (or a track and a file next to it), Lines
      around now lists "Script from:" rows; pick the other one and the lines come from it.
- [ ] Files, pictures (eab5339): a folder with photos lists them with a PICTURE chip; one opens like a video. Picture,
      Slideshow on: each picture shows for "Each picture" seconds, then the next opens with the crossfade. Pause holds.
- [ ] Files, Media servers (a04ab58): with a DLNA server on the LAN (a NAS, Plex, Jellyfin, minidlna), the place
      lists it within about 3 s; browse in, ".." goes back up, a video row shows its length. Opening one waits on the
      engine's http input (until then the test pattern shows why). No server: "Look again for media servers".
- [ ] System, Share files (adeaccb): the switch shows an address (no code) and a QR code; scan it on a phone and the
      share page opens. The phone remote's switch stays as it was; turning both off stops the server.
- [ ] Sound, Play on a PC (b393b56): `python tools/audio_sink.py` on the PC, set "PC:" to its address, switch on. The
      headset goes silent, the PC plays the sound, and the line reads "Playing on ...; the picture is held back N ms".

### Push-to-talk button (app-shell, a9803fb)

- [ ] With the dev link on (`--dev --listener=<PC>`), the right controller's bumper label says TALK (the left one with
      Left-handed on). Hold it: "Listening" shows in the pane's footer, in the glance line, or as a line in the world
      with the pane closed. Let go: the clip goes to the PC. The other bumper's label says LABELS.
- [ ] Without the dev link, both bumpers' labels say LABELS and TALK never appears.

### #85 HDR tone mapping (app-features)

- [ ] An HDR10 film (the overlay's status line says HDR10): colours look right, not grey and flat. Skin tones and
      skies are natural. Bright highlights (sun, lamps) are bright but keep some detail.
- [ ] The same scene with [hdr] tone_map = false in settings.cfg: the highlights clip. Is the tone mapped one better?
- [ ] Is the picture too dark or too bright overall? Set [tonemap_<room>] exposure (stops, e.g. 0.5 or -0.5) and note
      the value that looks right in each room.
- [ ] An SDR film just before and after: it looks as it did before this change.
- [ ] An old SD (DVD-sized) file: skin tones are not slightly green or red (the BT.601 matrix is used now).

### #26 Night mode and dialogue boost (engine-demux; PLAYER_NIGHT, fork `0178dc9a02`)

Binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_NIGHT` (everything of PLAYER_SUBS too). Desktop tests
pass. Details in `spikes/03-player/README.md`, "Night mode and dialogue boost".

- [ ] At low volume, play a loud scene in a film, once with `MediaSource.night_mode` off and once on. With it on,
      dialogue stays clear and explosions do not jump out. Note any pumping on music.
- [ ] `dialogue_boost` at 6 dB on a 5.1 film: voices come forward, and nothing distorts.
- [ ] In the overlay stats, the CPU use is the same with both off and both on.
- [ ] Behaviour change: AC-3 tracks without night mode now always play at the full range (DRC off). Before, FFmpeg
      applied DRC until the first seek. If a film sounds louder in its loud scenes than before, this is why.

### #22 Pictures and slideshow (app-features)

- [ ] Copy a few phone photos (some taken upright) into a folder on the device, and open one with --file= or the
      Files tab once it lists pictures. Each is upright and sharp, with natural colours.
- [ ] A photo sphere from a phone (360 panorama): it wraps around you, and the horizon is level.
- [ ] Next / previous move through the folder's pictures and videos.
- [ ] Slideshow: [images] slideshow = true in settings.cfg. Pictures change every 8 s with a 1 s crossfade. Pause
      holds one. Is 8 s right?
- [ ] If you have them: a VR180 photo (.vr.jpg), an .mpo from a 3D camera, a .jps. They show in 3D.

### #21 / #47 Discrete channels (engine-demux; PLAYER_CHANNELS, fork `59676f3368`)

Binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_CHANNELS` (everything of PLAYER_NIGHT too). Desktop tests
pass. Details in `spikes/03-player/README.md`, "Discrete channels".

- [ ] Once the app places speakers: a 5.1 film with `discrete_channels` on and one `AudioStreamPlayer3D` per present
      channel. Voices come from the screen, and surround effects come from behind. Lip sync is the same as with the
      stereo stream.
- [ ] CPU use with eight 3D players against the stereo stream alone (overlay stats, process CPU).

### #52, #18, #53 New rooms, photo rooms, glTF rooms (app-features)

- [ ] Each new room from the environment list: Home theatre, Drive-in, Planetarium, Dome. Is the scale right (car,
      sofa, seats)? Is the screen at a comfortable size and height? Note any frame drops in the overlay.
- [ ] Photo room: copy a phone 360 photo into ~/.local/share/godot/app_userdata/VR Video Player/skyboxes/ and pick
      it. The photo's horizon is level at eye height, it isn't mirrored (text in the photo reads right), and room
      light dims it.
- [ ] glTF room: export a simple room from Blender as .glb with an empty named ScreenAnchor (X scale = screen
      width), following app/docs/rooms.md, into .../rooms/. It appears in the list, and the screen is at the empty.

### #62 Floor reflection (app-features)

- [ ] Home theatre with a flat film: the picture shows on the floor between the table and the cabinet, mirrored and
      fading. Does it sit at the right depth (look at it with both eyes, then one)? Too strong? Try
      [reflection] strength = 0.15.
- [ ] A 3D film in the home theatre: the reflection is 3D too and doesn't hurt to look at.
- [ ] Frame time with the reflection on and off ([env_home_theatre] reflection = false), from the overlay.
### #68 / #86 Media servers (`docs/media-servers.md`)

- [ ] With a media server (UPnP/DLNA) on the LAN, or `python tools/fake_media_server.py --dir <films>` on the PC:
      `send media_servers`. The server is listed. A missing server means multicast does not reach the Frame over
      Wi-Fi: note it, and try `media_servers url=http://<PC>:47950/description.xml`.
- [ ] `send list_dir path=upnp://`, then its folders: the films show with sizes and durations.
- [ ] Once the engine reads http://: `send open path=<a film's URL>`. It plays and seeks.

### #89 The headset as a media server (`docs/share.md`)

- [ ] Start with `--share`. On the PC: open `http://<headset>:47880/share?k=<code from the pane>`. The folders list.
      A film link plays in a PC player and seeks.
- [ ] Upload a 1 GB file from the page or with `curl -T`. Note the MB/s over Wi-Fi. It shows in Drop.
- [ ] "Screenshot now" gives both eyes as the headset sees them.
- [ ] From a phone on mobile data (not the LAN), the address does not answer.

### #9 PC audio sync groundwork (`docs/pc-audio.md`)

- [ ] On the PC: `pip install sounddevice` (optional), then `python tools/audio_sink.py`. On the headset:
      `send pc_audio host=<PC IP> test_tone=true`. The PC plays a tone with a click each second. Note `delay_ms`
      and the PC's `underruns` over Wi-Fi after a minute.
- [ ] `send pc_audio host=<PC IP>` with a film playing: the headset goes silent and the PC plays the film. Watch lips
      against the PC sound. Note `delay_ms` and whether speech looks in sync.
- [ ] `send pc_audio on=false`: the sound comes back on the headset, and `get` shows the old `av_offset`.

### #85 HDR metadata and tone mapping (engine-demux; PLAYER_HDR, fork `015fc1857b`)

Binary `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_HDR` (everything of PLAYER_CHANNELS too). Desktop tests
pass. Details in `spikes/03-player/README.md`, "HDR metadata and tone mapping".

- [ ] The spike on an HDR film in hardware (P010), for example a 2160p HDR10 film:
      `--media=<file> --start=600 --screenshot=/tmp/hdr.png`. The log's `Colour:` line says "HDR pq, 989 nits to 203
      nits". The picture has normal contrast and colour, not grey and flat.
- [ ] The same with `--no-tone-map`, to see the difference, and with `--hdr-target=100` and `--hdr-target=400`. Note
      which target looks best in the headset.
- [ ] GPU time with and without tone mapping (`--gpu-time`) on the 2160p film.

### #12, #33, #55, #19 Screen comfort (app-features; all untested in the headset)

- [ ] Lying down: lie on a bed or sofa, press Y (keyboard) or the pane's control when it has one. The screen comes
      up to where you look and settles. Shift on the pillow: it follows slowly, not jumpily. Tilt your head
      sideways: the picture stays level. Y again: it goes back. Try a 360 video while lying down too.
- [ ] Head follow: F, then turn your chair about 60 degrees. The screen comes round after a moment. A quick glance
      aside doesn't move it. F again pins it where it is.
- [ ] Presets (from the pane once wired, or main.features.angle.apply_preset over the listener): large_format,
      living_room, in_bed. Are 70, 32 and 42 degrees at those distances comfortable?
- [ ] Seats: in the cinema, over the listener, main.features.seat.next_seat(1) a few times, or choose_seat with an
      index. You end up in a seat and the screen is where the room's screen is. Back row, front row, the side.
### Packaging and install without a store (dev-plumbing; `docs/packaging.md`)

Tested in WSL only: package, install, update, wrong-architecture refusal, uninstall, and the library shortcut on a
fake Steam folder. Nothing of this is tested on the device.

- [ ] On the PC: `tools/package.sh`, then `tools/install-on-frame.sh`. It ends with "installed in
      /home/steamos/vr-video-player (engine 4.7.2...)".
- [ ] In the desktop session, the menu has "VR Video Player" (and the Desktop has the icon). It starts the player in
      the headset. The log is in `~/.local/state/vr-video-player/last.log`.
- [ ] `~/vr-video-player/run.sh --file=<a film>` over ssh plays the film.
- [ ] Run the install again: the old one is in `~/vr-video-player.old` and the settings are kept.
- [ ] Read-only: `python3 ~/vr-video-player/tools/steam_shortcuts.py --list` lists the existing shortcuts, without
      an error.
- [ ] `tools/install-on-frame.sh --steam`, then restart Steam: the library has "VR Video Player", and it starts the
      player. Note if it starts in VR, or if `--openvr` is needed. A backup `shortcuts.vdf.bak-*` is next to the file.
- [ ] `tools/install-on-frame.sh --uninstall --steam` removes the folder, the menu entry and the shortcut.

### #34, #37, #39, #63, #66 Up next, pre-show, intermission, jog wheel, stereo screenshots (app-features)

- [ ] Cinema, a film from its start: the curtains are closed, then part slowly as it plays and the lights go down.
      At the end they close. Does it feel right, or too slow?
- [ ] Up next: turn continuous play on in the queue and let a short file end. The card under the screen counts
      down from 10 and the next one starts. Next-button plays now; a seek cancels.
- [ ] Jog wheel: circle the right stick slowly round its rim. The time card shows, ticks buzz lightly, and it
      scrubs (clockwise forward). Then a normal flick left or right: still a 10 s jump, not a jog by mistake?
- [ ] Intermission: [intermission] enabled = true, a long film with chapters (2 h). Jump to a few minutes before
      the middle chapter and play: it stops there, the curtains close, the card counts down. Press play to go on.
- [ ] Stereo screenshot over the listener (main.features.screenshot.capture()): the picture appears in
      user://screenshots with _sbs in its name. Open it in the player: it shows in 3D.

### #54 Watch-along answers, the PC half (dev-plumbing; `docs/dev/watch-along.md`)

Tested in WSL with the fork (a clip with a sidecar subtitle file). Not tested on the device.

- [ ] With `--listener=<PC address>` and a film with subtitles playing: `python tools/listener.py ask who is that`.
      The block has the file, the position, the chapter (if the file has chapters) and the last subtitle lines said.
- [ ] `python tools/listener.py answer "A test answer."`: the card shows beside the screen with the question as its
      heading. Dismiss it with the laser and trigger.

### #73, #83, #90, #95 Fisheye lens profiles, folder rules, sharpen, deinterlace (app-features)

- [ ] A 190 to 220 degree fisheye file: over the listener, main.features.lens.set_profile("equisolid"), then
      "stereographic". Which one keeps straight lines straight and the horizon level at the edges?
- [ ] Folder rule: main.features.folder_modes.use_current_for_folder() on a 180 side-by-side file. Another file in
      the same folder with no mode of its own opens as 180 side by side.
- [ ] Sharpen: main.features.picture.set_value("sharpen", 0.5) on a film. Sharper, with no bright halos on edges?
- [ ] An interlaced file (a DVD rip or 1080i recording): main.features.deinterlace.set_mode("edge"). The comb lines
      on movement go and motion is smooth. Then "bob": compare. Any frame rate drop?

### XR spikes: capabilities line, passthrough (#71), hand tracking (#72) (dev-plumbing; `docs/xr-spikes.md`)

Desktop tests only (`app/tests/test_hands.gd`, the settings file round trip). Nothing of this is tested on the device.

- [ ] Any XR start: copy the log's `OpenXR capabilities:` line (hand tracking, hand interaction profile, eye gaze,
      refresh rates, blend modes).
- [ ] The runtime's full extension list, once: `./bin/vr-video-player-engine --path app --display-driver x11
      --xr-mode on --verbose -- --quit-after=300 2>&1 | grep "Found OpenXR extension"`. Note XR_EXT_hand_tracking,
      XR_EXT_hand_interaction, XR_FB_passthrough, XR_HTC_passthrough, XR_EXT_dpad_binding and any XR_VALVE_* or
      XR_MNDX_* extension.
- [ ] `run.sh --passthrough`: the log says "Passthrough: ALPHA_BLEND on" or that it is not offered. Is the camera
      view behind the screen?
- [ ] `run.sh --hands` with the controllers put down: dots on the joints of both hands follow the fingers. Point with
      the index finger at the pane and pinch: does it click? Pinch off the pane: play / pause.
- [ ] Pick a controller up again: it takes over at once, and the dots stay (or go) with the hand.
- [ ] `run.sh` without `--hands`: the log says hand tracking is off from the next start.

### #21, #47 Virtual cinema speakers, world-locked sound (app-features; needs the PLAYER_CHANNELS engine)

- [ ] A 5.1 film in the cinema: over the listener, main.features.speakers.set_enabled(true). The film reopens at the
      same place. Voices come from the screen, the surrounds from beside and behind. Turn the head: the voices stay
      on the screen.
- [ ] Level: is it about as loud as the stereo mix (set_enabled(false) to compare)? Are voices clear?
- [ ] A 360 video with a stereo or 5.1 track: the sound stays with the picture's front when you turn round.
- [ ] Pause, seek and 1.5x speed (the stereo mix plays at 1.5x, then the speakers again at 1x). Lip sync unchanged.
- [ ] CPU: the overlay stats with the speakers on and off.

### #29 Bias light from the picture (app-features)

- [ ] Cinema and home theatre with a colourful film: the walls and floor near the screen take the picture's colours,
      warmer or bluer by side, and go dark in night scenes. Changes fade in, with no flicker. Is it too strong?
      Compare with main.features.bias.set_enabled(false), and try set_strength(0.5). If the room goes almost black
      with it on, even in bright scenes, the device clears the small viewport: report it.
- [ ] Frame rate: the overlay stats with the bias light on and off.

### #26 Night mode and dialogue boost (app-features; needs the PLAYER_NIGHT engine)

- [ ] An action film at low volume: main.features.night.set_night(true). Explosions don't jump out and quiet
      speech stays audible, with no pumping on music. Then set_strength(0.5): a middle way?
- [ ] A 5.1 film: main.features.night.set_dialogue_boost(6). Voices are clearer against music and effects.

### #85 HDR on the engine's BT.2390 curve (app-features; needs the PLAYER_HDR engine)

- [ ] An HDR10 film (hardware or software decode): the overlay's status says "BT.2390" and the file's peak. Colours
      natural, highlights not clipped flat, shadows not crushed.
- [ ] Brightness: main.features.hdr.set_value("target_nits", 150), then 300. Which looks right in the headset in
      the cinema, and in the void? The value is kept per environment.
- [ ] (#29 note) The bias light is now off by default: turn it on first with
      main.features.bias.set_enabled(true), and note the GPU frame time with it on and off (overlay stats).

### #86, #88, #64 HTTP, HTTPS, live streams, music files (engine-demux; the PLAYER_INPUTS engine)

From Windows, in the repo:

```
scp build/out/godot.linuxbsd.template_debug.arm64.PLAYER_INPUTS frame:spike03/
scp -r spikes/03-player/demux-test frame:spike03/
scp \\wsl.localhost\Ubuntu\home\<user>\media-tests\animated_90s.ts frame:spike03/
ssh frame chmod +x spike03/godot.linuxbsd.template_debug.arm64.PLAYER_INPUTS
ssh frame bash spike03/demux-test/stream-tests.sh spike03/godot.linuxbsd.template_debug.arm64.PLAYER_INPUTS spike03/animated_90s.ts
```

- [ ] Four "CPU" lines: a local file, an HTTP file, live HTTP and UDP, 20 s each on the device's loopback. Note the
      network thread's CPU seconds and the audio underruns. On the host the network thread took 0.01 to 0.09 s of
      the 20 s. The script needs python3 on the Frame; say so if it is missing.
- [ ] The UDP line names the socket buffer the kernel granted (416 KiB on the host).
- [ ] With the PC on the same Wi-Fi, an HTTP URL from the PC plays and seeks in the spike:
      `--media=http://PC_ADDRESS:8701/FILE.mkv` (run tools/stream_server.py on the PC; WSL needs mirrored networking).
- [ ] An `https://` URL of a video on a server with a public certificate opens; the log names the stream as HTTPS.
- [ ] (app) A music file: the pane shows the cover and the title and artist from the tags, and the audio plays.

### #70 Quad layers spike (app-features; `docs/xr-spikes.md`, "Quad layers")

- [ ] Start with `-- --pane-layer`. The log says "natively supported: true"? Open the pane: is small text sharper
      than without the flag (compare the seek bar's time and the Files list)? The laser shows behind the pane: does
      that bother you?
- [ ] Start with `-- --video-layer` and a 1080p film in the void. Is the picture sharper (fine text in the film, an
      end credit)? The pane in front still covers it? If the screen is black, hole punching does not work here.
- [ ] GPU cost: overlay stats (GPU frame time) with and without each flag, same film and room.

### #81 The environment reacts to the film (app-features)

- [ ] main.features.react.set_enabled(true), then an action film with deep bass: the controllers pulse with the
      low end. Subtle and pleasant, or busy? Try set_strength(0.25) and (1.0).
- [ ] The drive-in with a thunderstorm or explosions: the lot flashes briefly on the loud moments, not on music.
