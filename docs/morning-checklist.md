# Morning runbook

Everything to check in the headset for the work done while it was off, in the order to do it. This file is the single
source: tick `[ ]` to `[x]` here and add a note after the line. The sections as each agent wrote them are kept,
unchanged, in `docs/morning-checklist-raw.md` (do not tick there).

Agents: add new checks at the end, under "F. Added after the runbook", with your name and the feature.

Order: A deploy, B (removed: the kernel module session; one HDR check is left there), C engine runs on the stock
module, D headset checks by where you look, E decisions for you.

## Before you start

On the PC (Git Bash, in the repository):

```
PC=<this PC's LAN address: ipconfig, the 192.168.1.x one>
L="python tools/listener.py"
```

On the headset, in one `ssh frame` session (type these; from PowerShell, inner double quotes get lost):

```
cd ~/spike03
export DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000
H='smb://<PC address>/<share>'
S='--smb-user=USER --smb-password-file=/home/steamos/.smb-password'
DOC=/home/steamos/Videos/Documentary.3D.Full-SBS.mkv
F10="$H/Comedy.1080p.10bit.DTS-HD.mkv"
F720="$H/Feature.720p.10bit.mkv"
app()    { ./godot_player --path app --display-driver x11 --xr-mode on -- "$@"; }
spike()  { ./godot_player --path project --display-driver x11 --xr-mode off -- --no-xr "$@"; }
spikev() { ./godot_player --path project --display-driver x11 --xr-mode off --verbose -- --no-xr "$@"; }
```

`app` is the player (flags in `docs/USAGE.md`); `spike` is the engine test project (`spikes/03-player`). "Over the
listener" means: `$L serve` on the PC and `--listener=$PC` on the app; then `$L send <command>`. `main.features...`
calls go through `$L send run '...'`, which also needs `--dev-allow=60 --dev-code` on the app. Files on the share
(`$H/...`) open in the app with the host saved under Network.

## A. Deploy

- [x] **A1.** (2026-10-31 14:55: "All 293 files match.") On the PC: `tools/morning-deploy.sh`. It copies the engine (PLAYER_FINAL2 unless `--engine`
      says otherwise; see the script's header) to `~/spike03/` with the link `godot_player`, the app to `~/spike03/app`
      (`tools/push-app.sh`), the engine test project to `~/spike03/project`, and the stream tests with their clip
      to `~/spike03/`, with no sudo. It ends with "All N files match." and the next step (C1). Any FAILED line: run
      it again. (Until 2026-11-02 it also copied the kernel module files; that step is gone.)
- [ ] **A2 (optional, any time): the release package** (`docs/packaging.md`). On the PC: `tools/package.sh`, then
      `tools/install-on-frame.sh`; it ends "installed in /home/steamos/framecine (engine 4.7.2...)". In the
      desktop session the menu (and the Desktop) has "FrameCine" and it starts the player; the log is in
      `~/.local/state/framecine/last.log`. `~/framecine/run.sh --file=<a film>` over ssh plays it. Install
      again: the old one is in `~/framecine.old` and the settings are kept. Read-only:
      `python3 ~/framecine/tools/steam_shortcuts.py --list` lists the shortcuts without an error. Then
      `tools/install-on-frame.sh --steam`, restart Steam: the library has "FrameCine" and it starts the player
      (note whether it starts in VR, or needs `--openvr`); a backup `shortcuts.vdf.bak-*` is next to the file. Last,
      `tools/install-on-frame.sh --uninstall --steam` removes the folder, the menu entry and the shortcut.

## B. Kernel module session (removed)

The patched decoder module and its session (B0 to B7, B9 to B11, all done on 2026-10-31) were removed on 2026-11-02
(`docs/decisions.md` D21): 10-bit and HDR10 play in hardware on Valve's stock driver through Q10C. The steps as they
were written are in `docs/morning-checklist-raw.md` and in git history. B8 does not need the module, so it stays.

- [ ] **B8. HDR in the app** (app-features), the 2160p HDR10 film (`FHDR=<the film>`): `app --file="$FHDR" --overlay
      --listener=$PC --dev-allow=60 --dev-code`:
      - The overlay's status says HDR10, "BT.2390" and the file's peak. Colours natural, skin tones and skies natural,
        highlights bright with some detail, not clipped flat, shadows not crushed.
      - Over the listener: `main.features.hdr.set_value("target_nits", 150)`, then 300. Which looks right in the
        cinema, and in the void? (It is kept per environment.)
      - `[hdr] tone_map = false` in settings.cfg, restart: the highlights clip. Is the tone-mapped one better?
      - Too dark or too bright overall? Set `[tonemap_<room>] exposure` (stops, e.g. 0.5 or -0.5) and note the value
        that looks right in each room.

## C. Engine runs on the stock module (engine-demux; `spikes/03-player/README.md`)

In a new `ssh frame` session after the reboot (the lines of "Before you start" again).

- [x] **C1. Software decode CPU, the rerun** (2026-10-31, forced with HWVIDEO_P010=0 as the module is installed: the
      1080p 10-bit file 80 to 99 % of a core, the 720p 10-bit file 30 %, VP9 720p 29 %, all 0 dropped; the same 720p file
      in hardware P010 13 %; the documentary, 1080p SBS H.264, in hardware Q08C 12 %) ("Software decode fallback"; the CPU field was cut off last time):
      ```
      for f in "$F10" "$F720" "$H/<a VP9 file>.webm" "$DOC"; do
        echo "== $f"; spike --media="$f" $S --start=600 --seek-every=20 --seek-by=60 --quit-after=3600 2>&1 | grep -E "software|SOFTWARE|process CPU|Seek .* settled|decode .* fps|ERROR" | cut -c1-600
      done
      ```
      The 10-bit and VP9 files log `software decode` with the reason, and the picture is right. Note `process CPU N%
      of a core` from the 2 s lines for each; the documentary (8-bit, hardware) is the baseline.
- [x] **C2. Software seeks, A/B** (NONREF=1: 1312 and 467 ms, 63 and 80 frames skipped; NONREF=0: 1745 and 491 ms,
      189 and 239 skipped; same frames, 0 errors) (PLAYER_FEATURES2 and later):
      ```
      for v in 1 0; do echo "== NONREF=$v"; env HWVIDEO_SW_SEEK_NONREF=$v ./godot_player --path project --display-driver x11 --xr-mode off -- --no-xr --media="$F10" $S --start=600 --seek-every=20 --seek-by=60 --quit-after=5400 2>&1 | grep -E "Seek .* settled"; done
      ```
      Compare the `Seek N settled in M ms` lines and the "frames skipped so far" counts. Expect shorter settles and
      far fewer skipped frames with NONREF=1 (the default), and the same picture after each seek.
- [x] **C3. Q08C as the default capture format, long run** (2 min, Q08C UBWC imported, 5 seeks settled in 178 to
      543 ms, 0 decoder errors, no NV12 reopen; every seek logs a formatting ERROR from the seek log line, fixed in the
      VP9 engine build) ("UBWC capture"):
      ```
      spikev --sbs --media="$DOC" --seek-every=20 --seek-by=60 --quit-after=10800 2>&1 | grep -E "imported .* decoder buffers|reopening the decoder|Seek .* settled|ERROR" | head -40
      ```
      The log shows `imported N decoder buffers ... Q08C (UBWC)`, no `reopening the decoder with NV12` line, the
      picture is right, every seek settles, no decoder errors. Note anything that differs from an NV12 run (the same
      with `--capture-format=NV12`). For the long run, the same with `--quit-after=54000` (10 minutes).
- [ ] **C4. Stats from sysfs** ("Engine features for the app"): `spike --sbs --media="$DOC" --overlay-stats
      --quit-after=1800 2>&1 | grep Overlay: | tail -3`. The line has `gpu_mhz`, temperatures and `battery_power_w`;
      `video_kbps` moves with the scene; `decode_fps` and `shown_fps` sit near 24; `process_cpu_percent` is low. A
      value missing: `ls /sys/class/devfreq /sys/class/thermal; cat /sys/class/thermal/thermal_zone*/type`, note the
      names.
- [ ] **C5. Playback speed 1.5x with the hardware decoder**, a 4K file with audio: `app --file=<a 4K film> --overlay
      --listener=$PC --dev-allow=60 --dev-code`, then on the PC `$L send run 'main.features.speed.set_speed(1.5)'`.
      Voices keep their pitch, the picture keeps up, and dropped frames stay near 0 (`$L send stats`:
      `dropped_per_second`).
- [ ] **C6. A subtitle file next to a film on the share**: put `<film>.en.srt` next to a film on the share, set
      `[subtitles] enabled=true`, then `app --file="$H/<film>.mkv" --overlay`. The file is found
      (`MediaBrowser.find_subtitles()`), loaded (`add_external_subtitle()`), and its lines show well under a second
      after the film starts over Wi-Fi. Note the time.
- [ ] **C7. HTTP, HTTPS, live streams** (#86, #88; PLAYER_INPUTS, `spikes/03-player/README.md`, "Inputs"). A1 copied
      `spike03/demux-test` and the clip; from the PC: `ssh frame bash spike03/demux-test/stream-tests.sh
      spike03/godot_player spike03/animated_90s.ts`. (By hand instead: `scp
      build/out/godot.linuxbsd.template_debug.arm64.PLAYER_INPUTS frame:spike03/`, `scp -r spikes/03-player/demux-test
      frame:spike03/`, `scp \\wsl.localhost\Ubuntu\home\<user>\media-tests\animated_90s.ts frame:spike03/`, `ssh frame
      chmod +x spike03/godot.linuxbsd.template_debug.arm64.PLAYER_INPUTS`, then the script with that engine.)
      - Four "CPU" lines: a local file, an HTTP file, live HTTP and UDP, 20 s each on the device's loopback. Note the
        network thread's CPU seconds and the audio underruns (on the host it took 0.01 to 0.09 s of the 20 s). The
        script needs python3 on the headset; say so if it is missing.
      - The UDP line names the socket buffer the kernel granted (416 KiB on the host).
      - With the PC on the same Wi-Fi (`python spikes/03-player/demux-test/tools/stream_server.py` on the PC; WSL
        needs mirrored networking): `spike --media=http://$PC:8701/<FILE>.mkv --seek-every=20 --seek-by=60
        --quit-after=3600` plays and seeks.
      - `spike --media=https://<a video on a server with a public certificate> --quit-after=900`: it opens, and the
        log names the stream as HTTPS.

## D. Headset checks, by where you look

Start the player with `app --dev --listener=$PC` (add `--overlay` where a check reads the overlay, and `--dev-allow=60
--dev-code` for `main.features...` calls); other flags are named in the line.

### D1. Controllers and labels (app-shell)

- [ ] **Authored labels** (0944c0d): `app --labels-debug --snapshot-dir=/home/steamos/snaps`, take a
      set (left bumper + A). Right controller: PREV beside B, NEXT beside A, MENU above the menu button, the stick
      legend in the upper inner area, MOVE SCREEN on the handle behind the grip; no cut letters, no bar after MENU. The
      left controller (the right one mirrored; its dump was made untracked): the labels sit on the plastic and read
      upright. (Snapshot sets 2 and 16 were taken with 1dcc1d0, before this layout.)
- [ ] **Our model** (`app --controller-model=ours`): it sits exactly where the runtime's model was, legends printed on
      it; note any offset or turn against the real controller (passthrough or by feel). Legends legible at arm's
      length; the print changes when the menu opens and when a window is on.
- [ ] **Our model moves** (72d5cc5; this closes the old "parts don't move" gap): pull the trigger, squeeze, push the
      stick each way and click it, press A / B / menu / view. The trigger swings back about its top without passing
      through the body; compare each part's travel with the runtime model (no flag, same inputs). X, Y and the d-pad
      don't move (nothing is bound to them).
- [ ] **Controller battery** (caea999): the log's first lines say "Controller batteries: ...". Note what it lists.
      "none": run `ls /sys/class/power_supply; grep . /sys/class/power_supply/*/{type,scope,model_name,capacity}`.
- [ ] **Haptic ticks** (#32): hold the right stick to one side while a film plays: one light tick per 10 s step. Note
      a better `[haptics] strength` if too strong or too weak. Menu hover ticks: see D2 (the pane calls
      `features.haptics.hover(hand)`).
- [ ] **Jog wheel** (#63): circle the right stick slowly round its rim: the time card shows, ticks buzz lightly, it
      scrubs (clockwise forward). A normal flick left or right is still a 10 s jump, not a jog by mistake.
- [ ] **Chapters and the d-pad map** (#15): with the shipped map, every control works as before. Then create
      `app/override.cfg` as in `docs/features.md` (#15) and restart with `--debug`: the log still says "Interaction
      profile for /user/hand/left changed to .../frame_controller_valve", and trigger, A, B, menu and the stick work
      (if the profile does not bind, delete `override.cfg`: the d-pad paths are rejected). With it bound, on
      `--file=stub://flat_mono --overlay`: d-pad right goes to the next chapter (overlay "chapter 2/5 Colour bars"),
      left goes back, down replays 10 s with subtitles.

### D2. The pane (app-shell; `docs/ui-design.md`)

All untested in the headset. `--dev` shows the System tab's dev tools.

**Superseded (2026-10-31):** the pane is now a front panel (`docs/ui-design.md`, "Revision 2"). Skip "Launch and
dock", "Reading pose", "Glance", "Freeze", "Doc correction 1" and "Doc correction 3", and the Dock distance and
Glance opacity in "Pane settings". Use F, "The front panel (menu-rework)", instead. The other checks in this
section still apply to the panel.

- [ ] **Launch and dock**: the pane is docked ahead and a little low, with DOCKED in its corner. Footer and a list row
      readable without effort? Note the distance and size you would want (E5). Docked: the right stick moves the focus
      (outline plus left bar), the right trigger activates, a tick on each move; the left stick still seeks. Menu hides
      the pane; menu again brings it back in front. The dock is pinned in world space (0.9 m along the line of sight,
      12 cm below it), not following the head, so it also works lying down.
- [ ] **Reading pose**: raise the left controller: the pane slides from the dock into the hand; lower it: it fades
      out. Note any flicker at the edge of the pose, and whether it appears when you don't want it (hand resting on a
      knee or the chest). Held pose: upright, facing the eyes, not rolling with the wrist, 0.5 m from the eyes.
- [ ] **Glance**: the wall clock (96 px light), "1:24 left, ends 23:20", the battery line, the name and a thin
      progress line, at 72 % opacity; readable at a glance and clearly not clickable.
- [ ] **Freeze**: point the right controller at it: the laser appears only then, the pane switches to the full view
      and stops following the left hand; small left-hand tremor must not move it; one light tick per new target.
      Trigger clicks; either stick scrolls the list under the laser and the pane stays put while scrolling. Laser off
      for half a second, or the left hand moved about 4 cm: it eases back into the hand without a jump (and re-freezes
      once eased back, after 150 ms).
- [ ] **Poke**: touch a button with the right controller's tip: one click, with a tick.
- [ ] **No laser stub**: lasers show only on the pane (or a captured window).
- [ ] **Look**: the halo and the lit edge look quiet, not glowing; the laser and dot read against bright films.
      Transport buttons are words (Previous, −10 s, Play / Pause ringed, +10 s, Next), as the doc asks.
- [ ] **GPU cost**: frame times with the pane docked and hidden (its SubViewport renders every frame while visible,
      glance included).
- [ ] **Doc correction 1, size**: the doc's 24 x 20 cm and 740 x 600 px (3080 px/m) give 15 px text of 4.9 mm, about
      0.5° at 0.55 m (rows 1.4°, under the doc's 2.5° minimum; 0.3° docked at 0.9 m), not the 1° the doc also says.
      The literal size is built. If too small, `[pane] scale=2.0` (48 cm, the doc's angles) and compare. Decide in E5.
- [ ] **Doc correction 2, alpha**: the renderer blends in linear light, so the doc's 94 % surface let a bright film
      through at about a quarter of its brightness; alpha is now mapped as 1 - (1 - a)^2.2 (like sRGB compositing; the
      glance's 72 % too). The film should not show through the pane.
- [ ] **Doc correction 3, reading-pose thresholds**: enter within 40 cm below the eyes, 45° of the head's forward
      (the doc says 40°; a controller at the chest while looking straight ahead is about 41° down) and its face within
      40° of the head; leave at 50 cm, 55° and 55°. Confirm or change.
- [ ] **Other choices where the doc was silent** (confirm or change): mode diagrams in two groups, layout (Mono, SBS,
      TB) and shape (Flat, 180°, 360°, Fisheye); forms (add host, web page) replace the list and hide the seek bar and
      transport so the keyboard fits, no slide animation; the breadcrumb is the path as text, ".." goes up; grip held
      2 s on the pane (right hand, laser on the pane, dev mode only) allows remote changes, otherwise the grip moves the
      screen as always. Missing because the features did not exist then: Sound's night mode and output choice,
      Subtitles' depth and external files, Room's seat, the phone-remote code on the keyboard.

**Transport and the seek bar**
- [ ] **Seek bar pictures** (app-shell, 0eb9e66): System, Controllers, "Seek bar pictures" on, a 2160p film: point
      along the seek bar: a picture of that moment shows under it within a second or so, with its time; drag: it
      follows. Note the frame time and memory with it on (a second decoder, about 150 MB).
- [ ] **Corner film and gapless** (app-shell, 0eb9e66): Files, "In corner", pick a second film: it plays silent in
      the screen's corner; Picture, Corner film: Swap (its sound comes over), Corner size, another corner, Close
      corner. Queue, Play on and Gapless on: the next file starts with no gap. Room, Crossfade films 3 s and Crossfade
      music 6 s: the change of file fades.
- [ ] **4x and 8x, LIVE** (app-shell, 47add0e): on a film from the hardware decoder, hold 4x (then 8x) on the
      transport: it scans with pictures, the time line shows "· 4x"; let go: it plays on with sound. The buttons are
      absent on pictures, music and live. A live udp:// or http stream: no seek bar or skip buttons, LIVE by the
      time; Sound, Live delay changes how far behind live it plays.
- [ ] **Open a stream** (app-shell, 47add0e): Browser, "+ Open a web page or a stream", `udp://@:1234` (or an http
      .ts URL), Open: it plays in the player, not as a page. An http stream with no extension: Play as video.

- [ ] **Resume per file** (#7): play a real film past a minute, open another, then the first again: it continues
      about 3 s before where it was, picture and sound in step. Quit mid-film (or kill it over ssh) and start with the
      same `--file=`: it resumes (`~/.local/share/godot/app_userdata/FrameCine/resume.cfg` has the entry). B
      (previous) after a resume goes back to the start.
- [ ] **Frame step and A-B loop** (#80), keyboard: period steps one frame (paused), comma steps back; note how long a
      step takes. Slash twice a few seconds apart loops between the marks (overlay "loop ..."); slash again stops it.
- [ ] **Catch-up replay** (#11): Backspace during dialogue with subtitles off: back 10 s, lines appear, after 10 s they
      go away. The first line of the replay is there (if not, the keyframe was after its start; #11 in
      `docs/features.md`).
- [ ] **Chapters in the overlay**: a film with chapters shows them (needs `MediaSource.get_chapters()`).

**Files**
- [ ] **Quick quit while listing** (app-shell, a481639): open a big share folder (or Media servers, which looks for
      3 s) and quit at once, or run `app --quit-after=2` over ssh with the last folder on a share: the app exits
      cleanly (no "previously freed" error, no core dump in the log).

- [ ] **Rows**: resume markers (accent "0:42 ▶") after watching a file a while; mode chips on 3D files.
- [ ] **Keyboard** (969fccc): Network, + Add host: the quick row (smb://, .local) types whole strings; ?123 shows
      symbols; Shift once gives one capital, twice locks; < and > move the caret; Paste pastes the clipboard; Show
      password reveals it; form and keyboard fit without cutting the bottom row. Adding a host works; the Browser place
      still works.
- [ ] **Find hosts** (20f8700): Network, "Find hosts on this network" lists the PC and the NAS within 3 s; a found host
      opens Add host with its name filled in.
- [ ] **Queue, favourites, search** (#76, 20f8700): a queue row jumps; Favourite on a folder's bar adds it; star a
      film, then Search with the on-pane keyboard finds it first by a word of its name. Note how long a search of the
      SD card for a common word takes.
- [ ] **Shuffle, repeat, queue** (#78): `[queue] repeat="one"`, a short clip to its end: it starts again.
      `repeat="all"` and `continuous=true` in a folder of short clips: it plays through and starts over.
- [ ] **Up next** (#34): continuous play on, a short file ends: the card under the screen counts down from 10 and the
      next starts; Next plays it now; a seek cancels.
- [ ] **Pictures** (#22, eab5339): a folder of phone photos (some taken upright) lists them with a PICTURE chip; each
      opens like a video, upright and sharp with natural colours. A phone 360 photo sphere wraps around you, horizon
      level. Next / previous move through pictures and videos. Picture tab, Slideshow on (or `[images] slideshow =
      true`): a change every 8 s ("Each picture") with a 1 s crossfade; Pause holds; is 8 s right? A VR180 photo
      (.vr.jpg), an .mpo from a 3D camera, a .jps: in 3D.
- [ ] **Folder rule** (#83): over the listener, `main.features.folder_modes.use_current_for_folder()` on a 180
      side-by-side file; another file in that folder with no mode of its own opens as 180 side by side.
- [ ] **Music files** (#64; PLAYER_INPUTS): a music file (mp3, flac, ...): the pane shows the cover and the title
      and artist from the tags, and the audio plays.
- [ ] **Media servers place** (a04ab58): see D7.

**Picture**

- [ ] **Mode diagrams**: they change the mode; the depth, curvature, zoom and picture sliders all move the picture.
- [ ] **Container metadata first** (#25): once the engine has the stereo / spherical keys, a 180 or 360 file with no
      tags in its name but metadata in the container: the overlay's mode line says `[metadata]` with the right mode.
- [ ] **3D depth** (#4): on a 3D film (or `stub://flat_sbs`), `[stereo] depth=0.02` (or the slider): the picture sits
      further back, no doubled edges; -0.02 brings it nearer. Note the most comfortable value. In a 180 film, 0.01 does
      not tear the picture at the seam behind you.
- [ ] **Curved screen** (#31): Picture, Curvature is now 0 to 100 % (see F, "The front panel"): 100 % curves the
      screen evenly around you, no distortion at the edges, 3D still fuses. 0 % is flat.
- [ ] **Zoom and pan** (#35), keyboard: `=` until a letterboxed film's bars are gone, numpad 8/2 to centre; reopen:
      the zoom is remembered.
- [ ] **Picture controls** (#27): `[picture_void] lift=0.12` (or the slider) on a dark film: shadows open up, black
      stays black. Remove the key: as before.
- [ ] **Sharpen** (#90): `main.features.picture.set_value("sharpen", 0.5)` on a film: sharper, with no bright halos on
      edges?
- [ ] **2D from 3D** (#59), keyboard 2 on `stub://flat_sbs`: one eye closed at a time, both eyes see LEFT EYE; again,
      RIGHT EYE; again, 3D.
- [ ] **Horizon** (#77), keyboard numpad 9 a few times on a 360 or 180 film: the horizon rolls clockwise; numpad 0
      levels it; the sphere stays centred on the head.
- [ ] **Edge fade** (#79): `[stereo] edge_fade=0.03` on a 3D film with things near the edges: soft edges, objects
      crossing them don't snap. On by default? (E6.)
- [ ] **Fisheye lens** (#73), a 190 to 220 degree fisheye file: `main.features.lens.set_profile("equisolid")`, then
      `"stereographic"`. Which keeps straight lines straight and the horizon level at the edges?
- [ ] **Deinterlace** (#95), an interlaced file (DVD rip, 1080i recording): `main.features.deinterlace.set_mode("edge")`:
      the comb lines on movement go and motion is smooth; then `"bob"`: compare. Any frame rate drop?
- [ ] **SDR and SD after the HDR change** (#85): an SDR film just before and after looks as it did; an old SD
      (DVD-sized) file's skin tones are not slightly green or red (BT.601 is used now).
- [ ] **Sidecar JSON** (#60): with `[sidecar] write=true`, pick a mode for a local film in the pane:
      `<name>.vrmode.json` appears next to it (`ls` over ssh); remove the `[files]` entry in settings.cfg (or use
      another device): the mode comes back from the sidecar (`[sidecar]` in the overlay). Writing is off by default:
      decide in E1.

- [ ] **Pane controls** (app-shell, 5e6473a): the items above from the Picture tab instead of the listener. Size in
      degrees and its presets (In bed also turns on Lying down); Follow my head, then pinned again; Lying down;
      Deinterlace; Sharpen. A fisheye file shows Lens; an HDR file shows HDR (Tone map, Exposure, Knee). "Use for this
      folder" and "Clear folder rule" under the mode. Screenshot: a toast names the saved file.
- [ ] **Pane controls, batch 3** (app-shell, 3c23d2f): "Auto crop bars" on a letterboxed flat film: the footer adds
      "Looking for bars", then "Cropped to 2.39:1"; Grow the screen keeps its height. On an HDR file, "HDR brightness"
      changes the picture; Knee hides on the engine's BT.2390 curve. Film grain and Gate weave move the picture.

**Sound**

- [ ] **Language memory** (#28): a file with two audio languages, pick the second in Sound; another file with the same
      languages starts in it, picture and sound in step.
- [ ] **Speed** (#69, 20f8700): keyboard 0 twice (or Sound, speed 1.5x) on a film with speech: voices at their normal
      pitch, lips in step, overlay "speed 1.5x", the end time moves earlier; 9 back to 1x. 2x on the largest file: no
      dropped frames in the overlay?
- [ ] **Night mode and dialogue boost** (#26; PLAYER_NIGHT and later): an action film at low volume,
      `main.features.night.set_night(true)`: explosions don't jump out, quiet speech stays audible, no pumping on
      music; `set_strength(0.5)`: a middle way? A 5.1 film, `set_dialogue_boost(6)`: voices clearer against music and
      effects, nothing distorts. Process CPU in the overlay stats is the same with both off and both on. Behaviour
      change: AC-3 tracks without night mode now always play at full range (DRC off; before, FFmpeg applied DRC until
      the first seek), so a film may sound louder in its loud scenes than before.
- [ ] **Virtual cinema speakers** (#21, #47; PLAYER_CHANNELS and later): a 5.1 film in the cinema,
      `main.features.speakers.set_enabled(true)`: the film reopens at the same place; voices from the screen, the
      surrounds from beside and behind; turn the head: voices stay on the screen; lip sync the same as with the stereo
      stream. About as loud as the stereo mix (`set_enabled(false)` to compare)? Voices clear? A 360 video with a stereo
      or 5.1 track: the sound stays with the picture's front when you turn round. Pause, seek and 1.5x (the stereo mix
      plays at 1.5x, then the speakers again at 1x): lip sync unchanged. CPU (overlay stats) with the speakers (up to
      eight 3D players) on and off.
- [ ] **Play on a PC** (#9, b393b56): `pip install sounddevice` (optional), `python tools/audio_sink.py` on the PC.
      Over the listener `send pc_audio host=$PC test_tone=true`: the PC plays a tone with a click each second; note
      `delay_ms` and the PC's `underruns` after a minute. Then Sound, "PC:" set to the PC, switch on, a film: the
      headset goes silent, the PC plays the film, the line reads "Playing on ...; the picture is held back N ms"; watch
      lips against the PC sound and note whether speech looks in sync. `send pc_audio on=false` (or the switch): the
      sound comes back on the headset, and `get` shows the old `av_offset`.

- [ ] **Pane controls** (app-shell, 966cfab): Sound, "Speakers in the room" and "Bass channel"; the line under them
      lists the channels playing from the room.
- [ ] **Pane controls, batch 3** (app-shell, 91af377): Calibrate opens the A/V sync card. Night mode, Evening out and
      Dialogue boost show only on an engine with them; the boost is greyed on a stereo file.

**Subtitles**

- [ ] **Rendering** (#67): a film with a text track (SubRip or ASS in an MKV), subtitles on (S on a keyboard, the
      tab, or `[subtitles] enabled=true`): lines below the picture, sharp, not on the pane, in time with speech. Size
      right on the default 3 m screen and in the cinema? Try Size 0.7 and 1.5 (`[subtitles] size`). Italic, bold and
      colour from an .ass file or SubRip `<i>` show.
- [ ] **Look** (18219cd): Inside / Below the picture, Offset, Nearer (in 3D the line floats in front of things coming
      out of the screen) and Background change the line at once. A 3D film with `[subtitles] depth = 0.5`: the lines
      float in front and look the same size; is 0.5 m comfortable? Also `position = "inside"`.
- [ ] **180 and 360**: the lines sit low in front, about 10 degrees down; readable and comfortable to focus on?
- [ ] **Picture subtitles** (#67; PLAYER_SUBS and later): a Blu-ray rip's PGS track (`Animated.Feature.2.3D.2019.MULTi.1080p.Half-SBS.mkv`, French,
      track 1), picked in Subtitles: captions in each eye at the right depth, one caption on 3D rips (cfe7a26), the
      picture clears between lines, at a sensible size. The documentary's VobSub track (track 0): blue with a black edge. Note
      process CPU against the same file with subtitles off: no visible difference expected.
- [ ] **Files next to the film** (#50, 20f8700): `Film.en.srt` next to a local film without tracks: Subtitles shows it
      as a loaded file and a track, and its lines show. A film in your language with `Film.<lang>.forced.srt`,
      subtitles off: only the forced lines show. (On the share: C6.)
- [ ] **Second track** (#65, 18219cd): two files next to the film (Film.en.srt, Film.fr.srt), main English: pick the
      second (or Shift+S): French above in pale yellow, smaller. Another film with a .fr.srt: it comes back by itself.
- [ ] **Delay** (#61): with subtitles on, `'` a few times: lines later by 0.1 s per press; reopen: kept for that track.
- [ ] **Script search** (#8, f540d23, 36594c8): a film with a subtitle file, Find a line, two words, Search: hits with
      times; a row jumps to 0.5 s before the line; "Lines around now" marks the line being said. With two tracks,
      "Script from:" rows switch the source. Over the listener: `send find_line query=<word>` gives the right times;
      `send jump_to_line query=<word>`: the line is heard from its start. Once the engine has `get_subtitle_lines`, a
      film with an embedded text track: `find_line` says `"source": "engine"`; note how long the first search takes on
      a share.
- [ ] **Script read progress** (app-shell, d983445): a 2 GB film with a subtitle track inside it, Subtitles, "Lines
      around now": while the engine reads the film, the line counts "Reading the film for its subtitles: 12 s" until
      the lines come (12 to 23 s expected).

**Room**

- [ ] **New rooms** (#52): Home theatre, Drive-in, Planetarium, Dome. Scale right (car, sofa, seats)? Screen size and
      height comfortable? Frame drops in the overlay?
- [ ] **Photo room** (#18): a phone 360 photo in `~/.local/share/godot/app_userdata/FrameCine/skyboxes/`,
      picked: horizon level at eye height, not mirrored (text reads right), room light dims it.
- [ ] **glTF room** (#53): a .glb from Blender with an empty `ScreenAnchor` (X scale = screen width), per
      `app/docs/rooms.md`, in `.../rooms/`: it is listed and the screen is at the empty.
- [ ] **Floor reflection** (#62): home theatre, flat film: the picture on the floor between table and cabinet,
      mirrored and fading, at the right depth (both eyes, then one)? Too strong: try `[reflection] strength = 0.15`. A
      3D film: the reflection is 3D and comfortable. Frame time with it on and off (`[env_home_theatre] reflection =
      false`).
- [ ] **Room light follows playback** (#20): `--env=cinema`, start a film: the room dims over about 2 s; pause: it
      comes up quickly; menu open: up; closed: dims again. Is 0.35 (`[room] play_level`) too dark or too bright?
- [ ] **Bias light** (#29; off by default until its cost is measured): `main.features.bias.set_enabled(true)` first.
      Cinema and home theatre, a colourful film: walls and floor near the screen take its colours, warmer or bluer by
      side, dark in night scenes; changes fade in, no flicker. Too strong? Try `set_strength(0.5)`; compare with
      `set_enabled(false)`. Almost black even in bright scenes means the device clears the small viewport: report it.
      The GPU frame time (overlay stats) with it on and off. Default: E2.
- [ ] **Pre-show and intermission** (#37, #39): cinema, a film from its start: the curtains are closed, part slowly as
      it plays, the lights go down; at the end they close. Right, or too slow? `[intermission] enabled = true`, a 2 h
      film with chapters, a few minutes before the middle chapter: it stops there, curtains close, the card counts
      down; play goes on.
- [ ] **The room reacts to the film** (#81): `main.features.react.set_enabled(true)`, an action film with deep
      bass: the controllers pulse with the low end; subtle and pleasant, or busy? Try `set_strength(0.25)` and
      `(1.0)`. The drive-in with a thunderstorm or explosions: the lot flashes briefly on the loud moments, not on
      music.
- [ ] **Sleep timer** (#17): keyboard Z on a playing film (overlay "sleep in 15 min"); a quick check with `[sleep]
      fade_seconds=10` and a 1-minute timer (pane or dev link): room and picture dim, the sound fades smoothly with no
      clicks, then it pauses; play brings everything back.
- [ ] **Screen comfort** (#12, #33, #55, #19): lying down, Y (keyboard): the screen comes up to where you look and
      settles; shift on the pillow: it follows slowly, not jumpily; tilt the head: the picture stays level; Y again:
      back. A 360 video lying down too. Head follow: F, turn the chair about 60°: the screen comes round after a
      moment; a quick glance aside doesn't move it; F again pins it. Presets (`main.features.angle.apply_preset`):
      large_format, living_room, in_bed; are 70, 32 and 42 degrees at those distances comfortable? Seats in the cinema
      (`main.features.seat.next_seat(1)` a few times, or `choose_seat` with an index): you end in a seat with the
      screen where the room's screen is; back row, front row, the side.

- [ ] **Pane controls** (app-shell, a58763e): Room lists every environment as a row (a photo or glTF room appears
      after it is added); with a local picture open, "Use this picture as the room". The cinema shows Seat with Next,
      Previous and Room's own spot. Floor reflection and its strength where the room has a floor. The showing:
      Curtains, Up next countdown (seconds), Intermission (minutes, and where this film stops).
- [ ] **Pane controls, batch 3** (app-shell, 91af377): Effects: Bias light, React to the film, Projector beam, each
      with its strength. In the drive-in, Time of day (Night, Now, Dusk, Day; Latitude for Now). Files: a music file
      has a MUSIC chip.
- [ ] **Pick a seat** (app-shell, ec9d312, 6ea06ef, 65a6062): in the cinema, Room, "Pick a seat": the pane leaves the
      dock, the right laser goes out to the floor, a ring lights on the seat it points at, the trigger moves you there
      ("Seat N"). Between rows: no ring, the trigger says "No seat there". Start again and press B: "Seat unchanged",
      and B is "previous file" again afterwards; menu cancels the same way. Note whether picking is easy from the back
      rows (the ring needs the ray within 60 cm of a seat) and whether the ring reads against the seats.

**System**

- [ ] **Overlay: end time** (#36): `--overlay`, a film: the time line ends "ends HH:MM", right against a real clock
      (remaining plus now; whole hours off: the device has no time zone and the app reads UTC).
- [ ] **Overlay: battery** (#2): "battery NN %, ends HH:MM | film ends HH:MM", not "no battery" (else `ls
      /sys/class/power_supply; cat /sys/class/power_supply/*/type`, note the battery entry). The predicted end in the
      first minute and after 15 minutes agree within about 15 minutes, a drain near 9 W (about 35 % an hour). Charger
      in: "charging"; out: a forecast within a few seconds.
- [ ] **Pane settings** (20f8700): Size, Dock distance, Glance opacity apply at once; note the values you like for
      app-shell (they become the defaults). Reset layout goes back to the doc's numbers and docks the pane.
- [ ] **Left-handed and accessibility** (#74): Left-handed swaps the hands at once; Larger pane grows it; One eye for
      3D shows one eye to both. `[accessibility] subtitles_always=true`: every film opens with subtitles;
      `monocular=true`, `monocular_eye=0`: 3D films show the left eye to both.
- [ ] **Stats** (pane): shows frame and decode lines.
- [ ] **Calibration and the test lab** (#48): a calibration card opens. `app --file=lab://alignment`: with both eyes
      open the red and cyan half-lines meet in one straight cross (note any step, in 2 px ticks, vertical and
      horizontal); A to `lab://convergence`: note the outermost near and far rings that still fuse; A to
      `lab://judder_24`, `_30`, `_60`: the bar glides evenly at 72/90 Hz (note stutter, a lit cell holding or skipping).
- [ ] **Bandwidth**: Measure bandwidth on a share file gives a plausible Mbit/s; over the listener `send
      bandwidth_test path=smb://<host>/<share>/<a film> seconds=8`: note `mbps_avg`, `mbps_peak`, `open_ms`.
- [ ] **Benchmark** (#82): start once with an empty `[benchmark]` and no flags, idle 20 s: the log has `Benchmark:
      <codec> <size> hardware: N fps decoded ...` (note it); `send stats`: the `benchmark` key matches. Run benchmark
      in System shows progress and a summary. `send -t 60 benchmark path=<a 4K or 8K file on the headset>`: note
      `decode_fps`, `realtime_x`, `mpix_per_s`, `hottest_c`; then a share file, and compare. Start again: no benchmark;
      with an empty `[benchmark]`, opening a file within 8 s of the start stops it from starting.
- [ ] **Tours** (#91): `tours/demo.json` in the app data folder with two local files, a screen move with `"async":
      true` and `{"environment": "cinema"}`; `app --tour=demo`: the files play in turn, the screen glides (note
      judder), the pane stays out of view; System shows the tour's name, round and step, and Stop tour stops it.
      `--kiosk`: it loops; using the pane doesn't stop it; `send tour stop=true` does. A share file in the playlist
      opens within the 30 s limit or the log says why. Afterwards the saved screen size and room are as before.

- [ ] **Jog wheel switch** (app-shell, 966cfab): System, Controllers, "Jog wheel" off stops circling from scrubbing;
      "One turn" changes how far a turn goes.
- [ ] **Zoom lens switch** (app-shell, 91af377): System, Controllers, "Zoom lens" off: grip and trigger in a 360
      video no longer bring the lens; Magnification changes it.

### D3. The dev link and the tools on the PC

- [ ] **Listener** (#5): `$L serve` (allow private networks if Windows asks); `app --listener=$PC`: within a second or
      two `headset connected`, the hello (engine, model), a `state` line and a `battery` line with a real percentage
      (note it). `$L send ping` answers in well under a second. Ctrl+C, wait 10 s, start again: it reconnects within
      about 30 s with no stutter in the headset (note any hitch). Headset off and on: `session` events (`visible`,
      `focussed`).
- [ ] **Control API** (#56): `$L describe` lists commands, settings and events. `send open
      ~/spike01/streams/documentary_sbs.h264` answers once open, with `playing: true`; `send seek 60`, `pause`, `play`, `set
      volume 0.3` act within a frame or two; `set mode 360tb` then `set mode auto` change the projection and back. `send
      reload app`: the scene restarts (a moment of black; note how long), the listener stays connected, `send get`
      answers.
- [ ] **Screenshots** (#16, #66): a stereo film, `send screenshot`: three files in `~/.frame-listener/shots/`, left
      and right as each eye sees, the third the room from behind. Note any hitch or flattening, and how long it takes.
      Stereo screenshot: `main.features.screenshot.capture()`: a picture with `_sbs` in its name in
      `user://screenshots`; opened in the player it shows in 3D.
- [ ] **Stats** (#57): `send stats every=1`, after 10 s `$L events -n 3 -e stats`: `gpu.clock_mhz` (about 300),
      `battery.power_w` (8 to 10 W), `thermal.zones` (40 to 60 °C), `cpu.process_percent_of_core`, `video.decode_fps`
      (the film's rate), `video.bitrate_mbps` and `video.queue` filled and plausible (note missing or null ones);
      `frames.histogram` nearly all at or below 11.1 ms at 90 Hz (13.9 ms at 72 Hz); `send stats every=0` stops them.
- [ ] **Scene control and the permission ring** (#10, #23): `app --listener=$PC` only: `send spawn
      type=MeshInstance3D` is refused, the error says how to allow it, the headset shows "Refused remote spawn" about
      1.2 m ahead and below eye level (readable, comfortable?). With `--dev-allow=60`: the orange box example from
      `docs/dev/scene-control.md` appears about 1.5 m ahead, toast "Remote: spawn Box"; `send undo`: gone, "Undone:
      spawn Box". `send set dev/remote_changes allow` is refused ("can only be changed on the headset"). `send load_gltf
      --b64 data=<a small .glb> name=Test`: it appears in front (note any frame drop). With `--dev-code`: `send run
      'return main.env_id'` answers the room's id. In the pane (dev mode): hold the right grip on the pane 2 s: the
      footer says remote changes are allowed for an hour; a remote change shows "Remote: ..." with Undo, and Undo works.
- [ ] **Secrets stay on the headset** (d3fcdce): with `--remote`, `send get setting=remote/key` answers
      "remote/key is private".
- [ ] **Recipes** (#30), `--dev-allow=30`: spawn the box, `send save_recipe "Test room"`; switch room in the pane, then
      "Test room" in the list brings the box back with the screen in place. Quit, `app --env="recipe:Test room"`: the
      room comes up with the box. `send delete_recipe "Test room"` (from another room) removes it.
- [ ] **Host discovery** (#49): `send discover_hosts 4`: this PC appears from NetBIOS with `file_server: true`, and
      any NAS (note what is missing; if this PC is missing, turn on "NetBIOS over TCP/IP" for its Ethernet adapter,
      today registered only on the Hyper-V switch). Any frame hitch during the scan (about 255 packets per network)?
- [ ] **Hot-reload** (#3): `tools/push-app.sh` lists the copied files (rsync lines start `>f`, the tar fallback
      `pushed`; note any ssh prompt). `app --dev`: `Hot-reload: watching .../spike03/app/ (N files)`.
      `tools/push-app.sh --watch`; change a colour in `app/shaders/env_unlit.gdshader` (e.g. the dim room's floor) and
      save: within about 2 s `Hot-reload: gdshader res://shaders/env_unlit.gdshader`, the room changes without a
      hitch. `ambient_level` in `app/environments/dim_room.tscn`: `environment dim_room instanced again`, the light
      changes (note any stutter). A typo in `app/scripts/info_overlay.gd`: `does not compile ... the old version
      stays`, the app keeps running; fixed, the next save reloads it.
- [ ] **Cast** (#43): with this PC saved under Network, `python tools/cast.py "<shared folder>/<a film>.mkv"` prints the
      smb:// URL and "playing: ...", and it plays from the share. `python tools/cast.py --install-sendto`, then Send to
      > Play on headset in Explorer plays it (delete `%APPDATA%\Microsoft\Windows\SendTo\Play on headset.cmd` if
      unwanted).
- [ ] **Watch-along** (#54, cfaae75): `send card text="Hello from the PC" title="Test"`: a card right of the screen's
      top edge; laser and trigger: it goes; a second with `seconds=5` goes by itself. Readable, well placed? A film with
      subtitles: `$L ask who is that`: the block has the file, position, chapter (if any) and the last lines said.
      `$L answer "A test answer."`: the card shows with the question as its heading; dismiss it with the laser.

### D4. Phone remote (#13; `docs/remote.md`)

- [ ] `app --remote`: the log says `Phone remote: on, http://192.168.1.x:47880/` (note it). System, Phone remote shows
      a URL and a QR code a phone can scan off the pane (fallback, with `--dev-allow` and `--dev-code`: `$L send run
      'return tree.root.get_node("PhoneRemote").get_url()'`). On the phone the title and time update every second.
- [ ] From the phone: play, pause, +10 s, the seek bar, the volume act within about a second. Test patterns (pick
      one), and Network with a saved host: the listing appears without a stutter in the headset.
- [ ] The pane's "Add host" form, host field focused: type on the phone, press Type: the text appears. "Web page",
      Open: the Browser source starts on it.
- [ ] Without the code (a private tab, `http://<address>:47880/`): refused, the page says to scan the QR code.

### D5. Voice (#14, #41; `docs/dev/voice.md`)

- [ ] `app --dev --listener=$PC`: the right bumper's label says TALK (the left one with Left-handed on); the other
      bumper's says LABELS. Without the dev link both say LABELS and TALK never appears.
- [ ] `send push_to_talk seconds=3` and speak: `[voice_clip] {"peak": ...}`; a peak near 0 means the microphone gave
      nothing (the microphone, or its permission in SteamOS: note it). The WAV in `~/.frame-listener/voice/` is your
      voice at normal speed.
- [ ] Hold TALK: "Listening" in the pane's footer, the glance line, or a line in the world with the pane closed; say
      "dim the lights and skip to chapter 2", let go: the clip goes to the PC; with a transcriber both happen; without
      one, type `say dim the lights` in the listener.

### D6. Hands, passthrough and the runtime's extensions (`docs/xr-spikes.md`)

- [ ] Any XR start: copy the log's `OpenXR capabilities:` line (hand tracking, hand interaction profile, eye gaze,
      refresh rates, blend modes).
- [ ] The full extension list, once: `./godot_player --path app --display-driver x11 --xr-mode on --verbose --
      --quit-after=300 2>&1 | grep "Found OpenXR extension"`. Note XR_EXT_hand_tracking, XR_EXT_hand_interaction,
      XR_FB_passthrough, XR_HTC_passthrough, XR_EXT_dpad_binding and any XR_VALVE_* or XR_MNDX_*.
- [ ] `app --passthrough`: "Passthrough: ALPHA_BLEND on", or that it is not offered. Is the camera view behind the
      screen?
- [ ] `app --hands` (the first start says "start again with --hands"; the package's `run.sh --hands` needs no
      restart), controllers put down: dots on the joints of both hands follow the fingers; point the index finger at
      the pane and pinch: does it click? Off the pane: play / pause. Pick a controller up: it takes over at once (the
      dots stay or go with the hand). A start without `--hands`: the log says hand tracking is off from the next start.

- [ ] **Quad layers** (#70, app-features; `docs/xr-spikes.md`, "Quad layers"): `app --pane-layer`: the log says
      "natively supported: true"? Open the pane: is small text sharper than without the flag (the seek bar's time, the
      Files list)? The laser shows behind the pane: does that bother you? `app --video-layer --file=<a 1080p film>` in
      the void: is the picture sharper (fine text, an end credit)? The pane in front still covers it? A black screen
      means hole punching does not work here. GPU frame time (overlay stats) with and without each flag, same film and
      room.

### D7. Media servers, and the headset as one (#68, #86, #89)

- [ ] A media server (UPnP/DLNA) on the LAN, or `python tools/fake_media_server.py --dir <films>` on the PC: `send
      media_servers` lists it (missing: multicast does not reach the headset over Wi-Fi; note it, and try
      `media_servers url=http://$PC:47950/description.xml`). `send list_dir path=upnp://` and its folders: films with
      sizes and durations.
- [ ] Files, Media servers (a04ab58): the place lists the server within about 3 s; browse in, ".." goes back up, a
      video row shows its length. No server: "Look again for media servers". From PLAYER_INPUTS on (A1's PLAYER_NEXT
      too) the engine reads http://: a video row opens and plays, and `send open path=<a film's URL>` plays and seeks. (On an
      older engine the test pattern says why it can't.)
- [ ] Share (#89, adeaccb): `app --share`, or System, Share files: the switch shows an address without the code and
      a QR code; scan it: the share page opens. The phone remote's switch stays as it was; both off stops the server.
      On the PC `http://<headset>:47880/share?k=<code from the pane>`: the folders list; a film link plays in a PC
      player and seeks. Upload a 1 GB file (the page or `curl -T`): note the MB/s; it shows in Drop. "Screenshot now"
      gives both eyes as the headset sees them. From a phone on mobile data the address does not answer.

## E. Decisions for you

- [ ] **E1. Sidecar files.** May the app write `<film>.vrmode.json` into film folders? Off by default (team lead,
      2026-10-31); reading is always on. Try it with `[sidecar] write=true` (D2, Picture).
- [ ] **E2. Bias light.** Off by default until its GPU cost is measured (D2 Room). With the cost known: on by
      default, at strength 1.0 or 0.5, or leave it off.
- [ ] **E3. The controller models are non-commercial.** Ours is derived from Valve's CAD under CC BY-NC-SA 4.0. Keep
      it as an option, make it the default, or drop it. A commercial release must replace it (`docs/packaging.md`).
- [ ] **E4. SteamOS update.** The headset runs SteamOS 0.4.5 (kernel 6.18.0-ge66bc2ca6f8c). The 0.5.x preview
      (20261022) ships 6.18.0-g733a4be78129 and 7.2.0-g9a8c8ea46950; mainline 7.2 offers P010 by itself, which the
      engine takes before Q10C. Stay on 0.4.5 stable, or move to the preview? The player needs no kernel module
      (`docs/decisions.md` D21), and the installed player (in the home folder) survives an update. After one, the
      System tab's Hardware video row says which 10-bit path is in use.
- [ ] **E5. Pane size.** The literal 24 x 20 cm, `[pane] scale=2.0` (the doc's angles), or the values you set in
      System, Pane (D2). They become app-shell's defaults.
- [ ] **E6. Smaller defaults noted along the way:** edge fade on by default (D2 Picture), the room's play level 0.35,
      slideshow 8 s, subtitle size and depth, haptic strength, the HDR target and exposure per room. Write the values
      next to their lines above.
- [ ] **E7. Gapless playlist (#44) off by default.** It opens a second hardware decoder session at the end of every
      file, and nobody has seen the headset run two sessions at once yet (team lead, 2026-10-31). With the F checks
      for gapless, picture in picture and seek-bar pictures passed: turn `[queue] gapless` on by default, or leave it
      one setting away.

## F. Added after the runbook

(New checks go here, with who added them and the feature.)

### Assistant on the headset, port 47801 (assistant-service; `docs/assistant.md`, D16)

Needs: the app from this branch on the headset (with `whisper/` for speech to text; without it messages come as
audio), and on the PC curl (Windows: `curl.exe`, built in). Nothing to install or start on the PC. Below,
`H=https://192.168.1.50:47801` (the address the panel shows), and TOKEN and PIN come from step 3.

- [ ] **Start:** System, Assistant: switch it on. The log says "Assistant: on (0 paired)"; nothing listens yet:
      `curl.exe -sk $H/` from the PC fails to connect.
- [ ] **Find-me window:** press "Let an assistant find me". The panel shows the address and "60 min left", with Stop.
      The first time the log says "making the HTTPS certificate (once)", then "listening at https://...".
      `curl.exe -sk $H/` prints the guide with "pairing is open for 60 more minutes". `curl.exe -sk $H/status` says
      a token is needed (401).
- [ ] **Pair from the PC with curl:** `curl.exe -sk $H/pair/start --data-urlencode "client=Morning test"`. The panel
      opens at the System tab with "Morning test asks to pair with this headset" and the code in large digits; the
      card beside the screen shows it too. First send a wrong code:
      `curl.exe -sk $H/pair -d pair_id=PAIR_ID -d code=000000`: "wrong code; 2 tries left". Then the right one: the
      reply has `token`, `pin` and `cert_sha256`; the prompt and the card go away; the panel lists "Morning test,
      paired <today>" with Forget.
- [ ] **Pinned:** `curl.exe -s -k --pinnedpubkey "PIN" -H "Authorization: Bearer TOKEN" $H/status` answers ok, with
      `"transcriber"` naming whisper (or "none"). With a wrong pin (`sha256//AAAA...=`) curl exits with 90.
- [ ] **Events stream:** in a second window,
      `curl.exe -sN -k --pinnedpubkey "PIN" -H "Authorization: Bearer TOKEN" "$H/events"`: `event: status`, then
      `event: state`, then ": keepalive" every 15 s. The panel header shows "Assistant".
- [ ] **Voice and answer:** hold the pointer hand's bumper, say "who is that", let go. The card shows "You: who is
      that" (live while you speak, with dots until the final text). The stream prints `event: viewer_message` with
      the text and the film's context. `curl.exe -s -k --pinnedpubkey "PIN" -H "Authorization: Bearer TOKEN" $H/answer
      --data-urlencode "text=The lighthouse keeper."`: the answer shows under your words. Also
      `$H/messages/wait?timeout=600` returns as soon as you speak again. Note how long the text takes after letting go.
- [ ] **Permissions:** `... $H/command -d cmd=pause`: refused (409, "has not allowed"). Switch on "Let the assistant
      control playback": the stream prints `event: permissions`; the same command pauses, and the footer says
      "Assistant: pause" with Undo.
- [ ] **Room change:** switch on "Let the assistant change the room". `... $H/command -d cmd=add_shape -d name=Clock
      -d type=cylinder -d size=[0.4,0.04] -d position=[1.5,1.8,-3] -d rotation=[90,0,0] -d widget=clock`. A wall
      clock shows right of the screen at once (no Keep or Undo; the footer says "Assistant: add Clock"); the reply says
      `"state": "kept"` and the Room tab lists "Assistant room". `... $H/command -d cmd=remove -d name=Clock`: gone.
      `curl.exe ... -o view.png "$H/snapshot.png?from=seat"`: a 640 x 360 picture of the room and the screen, and the
      film did not stutter while it was taken.
- [ ] **Restart persistence:** quit and start the app. Without pressing "Let an assistant find me", the log says
      "listening at ..."; the pinned `/status` with the token works; `curl.exe -sk $H/` says "pairing is closed: ask
      the viewer to press Let an assistant find me"; `/pair/start` is refused (403).
- [ ] **Forget:** press Forget on "Morning test". The pinned `/status` now answers 401. With nobody paired and no
      window, `curl.exe -sk $H/` fails to connect again.
- [ ] **The fresh-session test (the acceptance test):** press "Let an assistant find me". Start a new Claude Code
      session in an empty folder on the PC and say only: "The VR video player in my headset is at
      https://192.168.1.50:47801. Connect to it and keep listening to me; answer me on its card." It should read the
      guide, ask to pair, ask you for the code, pair, start following the events (a background curl) or blocking
      waits, and answer what you say with the bumper. Ask "what am I watching?", then (with control allowed) "pause
      it". Note every place it got stuck or asked you something the guide should have told it. Repeat with Codex if
      you have it.
- [ ] **Log:** the log has "asks to pair" and "paired with", and no token or code: search panel.log for the token
      and the code from this morning: 0 hits.

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

### #92 Projector mode (app-features)

- [ ] Cinema, a film playing: main.features.projector.set_beam(true). Look up and back: a faint beam from the booth
      with dust motes in it. Too faint, too strong? Does it bother you when looking at the screen?
- [ ] An old film: set_grain(0.5) and set_weave(0.5). Does it feel like film, or just noisy and shaky?
- [ ] Frame rate with the beam on (overlay stats).

### #84 Time of day (app-features)

- [ ] The drive-in: main.features.time_of_day.set_latitude(<your latitude>), then set_mode("clock"). Does the sky
      match outside (day, dusk or night)? Then set_mode("dusk") and ("day"): do the colours look right in the
      headset? Is watching in daylight pleasant, or should "clock" stop at dusk?

### #38 Zoom lens (app-features)

- [ ] A 360 or 180 video with the pane hidden: hold the right grip, pull the trigger, aim at a detail. A lens shows
      it 3x larger; moving the aim moves the view. Let go: gone. Is the size and distance right? Is 3x right
      (main.features.zoom_lens.set_magnification(5))? Comfortable in 3D?

### #24 A/V latency card (app-features; `lab://av_sync`)

- [ ] Open lab://av_sync (pane, or --file=lab://av_sync). Watch the flash and listen to the beep; move the Sound
      tab's A/V offset until they land together. Note the offset at each refresh rate you can set (72, 90, 120 Hz).
      Then play a film with clear speech: is lip sync right with that offset?

### #64 Music files (app-features)

- [ ] Open a folder with music (FLAC or MP3 with covers). The screen shows the cover, title, artist and album, the
      bars move with the music, and the next track starts at once at the end. Lying down (Y) is comfortable for
      listening?
- [ ] The visualiser styles (`main.features.set_visualiser("mirror")`, then "line", "radial" and "off"; the pane's
      row comes next session): each moves with the music and is easy to look at. Which should be the default?

### #42, #46 Letterbox detection and trick play (engine-demux; the PLAYER_PICTURE engine)

Copy `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_PICTURE` and `spikes/03-player/project` to `~/spike03`, as
for the other spike binaries. FILM below is a local film or its smb:// URL with the usual `--smb-*` options.

```
# Trick play on the hardware decoder: 8x for 6 s from 10 min, then normal playback with audio.
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER_PICTURE --path project --display-driver x11 --xr-mode off -- --no-xr --media=FILM --start=600 --trick=8 --trick-for=6 --quit-after=1500
# Letterbox detection next to a 2160p hardware decode (a 2160p film with bars).
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER_PICTURE --path project --display-driver x11 --xr-mode off -- --no-xr --media=FILM --letterbox --quit-after=5400
```

- [ ] Trick play: the picture jumps ahead about 2 s of film every 0.25 s, with no green or grey frames. The log's
      clock moves about 48 s in the 6 s.
- [ ] After "Trick play off": normal playback with sound, and the A/V offset in the stats line is back under 50 ms
      within 2 s. Say if the decoder logged errors.
- [ ] Letterbox: a "Letterbox (known)" line after about 15 s and "Letterbox (final)" later, with the picture's
      rectangle. Note the "detector CPU" and "slowest keyframe" figures, and any dropped frames meanwhile (on the
      host a 2160p HEVC keyframe took 60 to 100 ms).

### #42 Auto letterbox crop (app-features)

- [ ] Turn on the Picture tab's auto crop and play a 2.39 film stored in 16:9 (a scope Blu-ray rip). Within about
      15 s the bars go and the screen grows wider at the same height. Does the change itself look all right? Turn
      "grow" off: the screen keeps its width and gets shorter.
- [ ] A side-by-side 3D film with bars: the bars above and below go in both eyes, and the 3D still lines up.
- [ ] A film with no bars: nothing changes, and the footer says "No bars". Any dropped frames while it looks?

### #44 Next item on a second decoder session (engine-demux; the PLAYER_NEXT engine)

Copy `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_NEXT` and `spikes/03-player/project` to `~/spike03`.
FIRST and NEXT are two films (local, or smb:// with the usual `--smb-*` options). START is 40 s before FIRST's end
(the log's "Media:" line gives its duration).

```
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot.linuxbsd.template_debug.arm64.PLAYER_NEXT --path project --display-driver x11 --xr-mode off -- --no-xr --media=FIRST --start=START --next=NEXT --next-before=20 --quit-after=4000
```

- [ ] "Next item: ... opened" and "prerolled in ... s" lines 20 s before the end, with no decoder errors. If the
      second decoder session fails to open, say so and paste the error.
- [ ] "Next item: waiting, prerolled": note the next item's threads' CPU and the RSS change (about 150 MB is expected
      at 2160p: a second set of CAPTURE buffers).
- [ ] At the end: "Next item took over", and the screen goes straight from the last frame of FIRST to the first of
      NEXT, with no black or old frame. NEXT plays with sound; the A/V offset in the stats line stays under 50 ms.
- [ ] No "leaked" warning at exit.

### #46 Trick play in the app (app-features)

- [ ] Play a film and hold the right stick right: a 10 s skip, then the picture scans at 4x and after 2 s at 8x,
      with no green or grey frames. Let go: playback goes on with sound in step at once. A tap still skips 10 s.
- [ ] Hold left: repeated 10 s skips back, as before (there is no reverse scan).

### Live streams (app-features)

- [ ] On a PC on the LAN, send a film as MPEG-TS over UDP to the headset, for example
      `ffmpeg -re -i FILM -c copy -f mpegts udp://HEADSET-IP:1234` (any tool that sends MPEG-TS works). Open
      `udp://@:1234` in the player (the Open URL form once app-shell routes it; else `--file=udp://@:1234`). The
      picture and sound start within about 2 s, the overlay says LIVE, and seeking does nothing.
- [ ] Note how far behind the sender it runs, and whether it stutters. Try `[network] live_latency` at 0.2 and 1.5.

### App requests: whole subtitle tracks and audio without a player (engine-demux; the PLAYER_REQUESTS engine)

Copy `build/out/godot.linuxbsd.template_debug.arm64.PLAYER_REQUESTS` to `~/spike03/godot_player`, and
`spikes/03-player/project` to `~/spike03/project`. Use the session setup at the top of this file.

```
spike $S --media="$F720" --start=600 --subtitle-lines=0 --subtitle-track=0 --quit-after=3000
spike $S --media="$F720" --start=600 --pull-audio=0.1 --quit-after=2500
```

- [ ] First run: "Subtitle lines: ... lines of track 0 in ... s". Note the time, the process CPU and the frames
      dropped that it reports. The host read this 800 MB film in about 5 s. "[subtitle 0 ...]" lines appear as the
      film plays.
- [ ] Second run: no sound from the headset (the audio is taken and dropped). The stats line's "pulled audio: clock
      error" starts near -100 ms and closes towards 0: about -60 ms after 10 s. The A/V offset stays under 50 ms.
      Note the process CPU next to a normal run of the same file.
- [ ] No "leaked" warning at exit in either run.

### Engine builds: PLAYER_FINAL2 replaces the earlier ones (engine-demux)

`build/out/godot.linuxbsd.template_debug.arm64.PLAYER_FINAL2` holds everything of PLAYER_INPUTS, PLAYER_PICTURE,
PLAYER_NEXT, PLAYER_REQUESTS and PLAYER_FINAL (lineage in `spikes/03-player/README.md`). Where an entry above names one
of those builds, use PLAYER_FINAL2: A1 deploys it as `~/spike03/godot_player`. The old files are in
`build/out/superseded/`.

- [ ] With PLAYER_FINAL2, the engine-demux entries above give the same results as with the builds they name.
- [ ] Quit the app a few times: no "corrupted size vs. prev_size" abort. A "WorkerThreadPool: N task(s) were never
      waited for" warning names the tasks a script forgot to wait for.

### #44 Gapless playlist (app-features)

- [ ] Turn on Gapless (Files, queue bar; off by default, E7). Open a folder of episodes, turn on continuous play,
      and seek to 30 s before the end of one. At
      10 s the up-next card counts down to the end. The next episode starts with no black frame and no wait, with
      sound. Try it with 2160p files too, and say if anything stutters while the next one is prepared.
- [ ] Seek back during the countdown: the card goes. Cancel the card (Esc): the episode stops at its end.

### #87 Picture in picture (app-features)

- [ ] Play a 2160p film and open a 1080p one in the corner (the pane's control once app-shell adds it). Both play
      smoothly, and the corner is silent. Note dropped frames in the overlay and any decoder errors in the log.
- [ ] Swap twice: each time the films change places and play on where they were, with the big screen's sound.

### #40 Seek-bar thumbnails (app-features)

- [ ] Turn on seek-bar thumbnails (`[thumbnails] enabled=true`, or the pane once app-shell adds it). Play a 2160p
      film and drag along the seek bar: pictures appear within about a second, and the film keeps playing smoothly.
      Note the memory before and after in the overlay or `top`, and any decoder errors in the log.

### #94 Crossfade between items (app-features)

- [ ] Set `[crossfade] music=4` and play an album with continuous play: each track fades into the next over 4 s, and
      the card fades too. Set `[crossfade] videos=3` and play a folder of short clips: each fades into the next
      without a stutter.

### #65 Second subtitle track inside the file (app-features)

- [ ] Play a film with two text subtitle tracks inside it (for example English and another language). Turn subtitles
      on, pick the second track in the Subtitles tab (or Shift+S), and seek back 30 s: both lines show, the second
      above and smaller.

### Hardware VP9, one session at a time (engine-vp9; the PLAYER_VP9 engine; `spikes/03-player/README.md`, "Hardware VP9")

**Never run two VP9 players at once** (two VP9 sessions crash the firmware, and killing the process then can hang the
headset). One run at a time, about 5 s apart. After each run: `sudo dmesg | tail -40 | grep -iE
"iris|0x5000003|smmu|preempt|oops"`, which should show nothing new. Never `kill -9` a player; let `--quit-after` end it.

On the PC: `tools/morning-deploy.sh --engine godot.linuxbsd.template_debug.arm64.PLAYER_VP9` (the engine as
`~/spike03/godot_player`, the app and `project`). Then copy three longer clips to `~/spike03/`. engine-vp9 left them in
the session scratchpad's `vp9/` folder; to make them again on the PC (any ffmpeg with libvpx), run:

```
ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=24 -f lavfi -i sine=frequency=440:sample_rate=48000 -t 120 -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -row-mt 1 -b:v 4M -g 48 -pix_fmt yuv420p -c:a libopus -b:a 96k vp9_8bit_1080p_120s.webm
ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=24 -f lavfi -i sine=frequency=330:sample_rate=48000 -t 60 -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -row-mt 1 -b:v 4M -g 48 -pix_fmt yuv420p10le -profile:v 2 -c:a libopus -b:a 96k vp9_10bit_1080p_60s.webm
ffmpeg -f lavfi -i testsrc2=size=3840x2160:rate=24 -f lavfi -i sine=frequency=550:sample_rate=48000 -t 30 -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -row-mt 1 -b:v 12M -g 48 -pix_fmt yuv420p -c:a libopus -b:a 96k vp9_8bit_2160p_30s.webm
scp vp9_8bit_1080p_120s.webm vp9_10bit_1080p_60s.webm vp9_8bit_2160p_30s.webm frame:spike03/
```

On the headset, after the session setup at the top:

```
W8=~/spike03/vp9p0_720p_10s.webm; I8=~/spike01/streams/vp9p0_720p_10s.ivf; I10=~/spike01/streams/vp9p2_720p_10bit_10s.ivf
L8=~/spike03/vp9_8bit_1080p_120s.webm; L10=~/spike03/vp9_10bit_1080p_60s.webm; B8=~/spike03/vp9_8bit_2160p_30s.webm
G='MediaSource: /|V4L2Decoder: (/|opened|S_FMT|SOURCE_CHANGE|CAPTURE|P010|seek|VP9|hardware VP9|decoder closed)|HWVideoTexture|^Seek|Next item|decode .* fps|ERROR|Final'
```

The clips named `720p` are 1280x696 (1.85:1).

- [x] **1. 8-bit WebM in hardware.** (2026-10-31, patched module: Q08C 1280x704 imported, 24 fps, 0 errors, 12 to 20 %
      of a core; CAPTURE offered Q08C, NV12, NV21; session released cleanly)
      `./godot_player --path project --display-driver x11 --xr-mode off -- --no-xr --media=$W8 --quit-after=600 --screenshot=/tmp/vp9-hw.png --screenshot-frame=300 2>&1 | tee vp9-1.log | grep -E "$G" | cut -c1-260`
      Expect `... VP9 Profile 0 1280x696 (display 1280x696), 8-bit, 23.976 fps, from a MediaSource ...; the one hardware
      VP9 session.`, `S_FMT OUTPUT VP90 1280x696`, `SOURCE_CHANGE #1`, `CAPTURE formats offered for this VP9 stream:
      ...` (note the list), `CAPTURE generation 1: Q08C 1280x704 ..., visible 1280x696+0+0`, `HWVideoTexture: hardware
      decode (VP9 Profile 0, 8-bit)`, `imported N decoder buffers (generation 1): Q08C (UBWC) 1280x704`. The 2 s lines:
      decode about 24 fps, `decoder errors 0`, ending in `, hardware (VP9)`. At the end `VP9 session released.` and
      `Final: ... 0 decoder errors`. If the Q08C import fails, a `reopening the decoder with NV12` line follows: say so.
- [x] **2. Linear NV12, as spike 01 had it.** (NV12 1280x704, 0 errors, 11 to 20 %) The same with `--capture-format=NV12` and `--screenshot=/tmp/vp9-nv12.png`.
      Expect `CAPTURE generation 1: NV12 1280x704`, `imported ... NV12`.
- [x] **3. Software reference.** (software vp9, 30 to 36 % of a core, 0 errors) `HWVIDEO_HW_VP9=0` in front of command 1, with `--screenshot=/tmp/vp9-sw.png`.
      Expect `HWVideoTexture: software decode (software vp9 ...): Hardware VP9 decode is off (HWVIDEO_HW_VP9=0).`, no
      `V4L2Decoder` lines, and `SOFTWARE decode` on the 2 s lines. Note the process CPU against run 1. Copy the three
      screenshots to the PC: the picture should be the same (colours, no shift, no band at the bottom).
- [x] **4. IVF.** (the third hardware VP9 session of the boot, run 1 and 2 having closed cleanly: the firmware
      crashed, `received system error of type 0x5000003`, and reloaded itself within 30 ms. The engine logged `VP9 decoder
      fault: 4 DQBUFs in a row failed`, released the session and played on in software from 0.000 s, 0 dropped. No oops,
      no hang; an HEVC decode right after was fine. Runs 5 to 10 not done: stopped at the first firmware error) Command 1 with `--media=$I8`: the same lines as run 1 (`ivf` in the `MediaSource:` line).
- [ ] **5. Seeks.** `./godot_player --path project --display-driver x11 --xr-mode off -- --no-xr --media=$L8 --seek-every=5 --seek-by=17 --quit-after=2400 2>&1 | tee vp9-5.log | grep -E "$G" | cut -c1-260`
      Each seek: `seek (serial N): first VP9 packet at T s, keyframe 1920x1080; no flush needed.`, then `Seek k settled
      in ... ms ... decoder errors during the seek 0`. The picture after each seek is clean (no green or smeared blocks)
      and no `switching to software decode` line comes. Then backwards on the short clip: `--media=$W8 --start=1
      --seek-every=3 --seek-by=-2 --quit-after=900`, with the same expectations.
- [ ] **6. 10-bit.** Command 1 with `--media=$I10`, then with `--media=$L10 --quit-after=1200`.
      - Stock module: `linear 10-bit (P010) not available`, then `HWVideoTexture: software decode (...): 10-bit video is
        not supported yet ...`. No VP9 session is opened.
      - A kernel that offers P010 (the patched module was removed on 2026-11-02, D21, so not on the headset for now):
        `CAPTURE formats offered for this 10-bit VP9 stream: ...`. Note the list. Then
        one of two outcomes. (a) P010 is in it: `P010 layout: ...` without `DOESN'T FIT`, `imported ... P010`, and the
        2 s lines end in `, hardware (VP9, 10-bit)`. (b) It is not: `ERROR: V4L2Decoder: 10-bit VP9: the decoder offers
        no P010 for it (offered: ...)`, then `HWVideoTexture: switching to software decode at 0.000 s: 10-bit video is
        not supported yet ...`, and the clip plays on in software. Say which one happened.
- [ ] **7. 2160p in hardware.** Command 1 with `--media=$B8 --quit-after=1800`: hardware VP9 3840x2160, decode 24 fps,
      0 errors. Software could not play this one at all.
- [ ] **8. The one-session rule in the test project.** `./godot_player --path project --display-driver x11 --xr-mode off -- --no-xr --media=$L8 --start=95 --next=$W8 --next-before=20 --quit-after=2400 2>&1 | tee vp9-8.log | grep -E "$G" | cut -c1-260`
      Expect the first file `the one hardware VP9 session`, then `HWVideoTexture: software decode (...): Another video is
      decoding VP9 in hardware: two VP9 sessions at once crash the decoder firmware (SteamOS #2865), so this one decodes
      in software.` and `Next item: vp9p0_720p_10s.webm opened ... (software path)`. Only one `opened
      /dev/video-dec0` line. At the end, `Next item took over` and the short clip plays in software. Then the same with
      `--next=$B8`: `HWVideoTexture: can't play VP9: Another video is decoding VP9 in hardware ... 3840x2160 is too large
      ...` and `--next: can't play ...`, while the first file plays on in hardware.
- [ ] **9. The app: picture in picture and the overlay.** `app --file=$L8 --listener=$PC --dev-allow=60 --dev-code 2>&1 | tee vp9-app.log`.
      The overlay (Tab) says `hardware (VP9)`. On the PC: `$L send run 'main.features.pip.open("/home/steamos/spike03/vp9p0_720p_10s.webm"); return true'`.
      The corner plays, and `grep -E "Another video is decoding VP9|VP9 session" vp9-app.log` shows the software line for
      it. `$L send run 'return [main.player.source.get_stats()["decode_path_text"], main.features.pip.source.get_stats()["decode_path_text"]]'`
      returns `["hardware (VP9)", "software"]`. Swap (`$L send run 'return main.features.pip.swap()'`): both play on,
      the 10 s clip on the big screen in software. Close the PiP (`$L send run 'main.features.pip.close(); return true'`).
      No new `dmesg` lines.
- [ ] **10. The app with VP9 off.** Quit, then `HWVIDEO_HW_VP9=0 app --file=$L8`: the overlay says `software`. (The
      setting `[hwvideo] hw_vp9=false` in `settings.cfg` does the same.)
- [ ] The fault path (decoder errors, then software from the same position) is not to be provoked on the headset: it
      needs a crashed firmware. It was tested on the PC with `switch_to_software()`. If any run above logs `VP9
      decoder fault`, `switching to software decode` or `hardware VP9 is off for the rest of this run`, paste those
      lines and the `dmesg` lines.

### The front panel (menu-rework; `docs/ui-design.md`, "Revision 2")

The menu is now a panel in front of the headset. It replaces the pane on the left controller (D2's hand-held checks).
Start the app as in A, with a film in the folder (for example `app --dir=/home/steamos/Videos 2>&1 | tee panel.log`).
Take both controllers. For the one-controller steps, put the other controller down out of reach.

- [ ] **At launch:** the panel is open about 0.6 m in front of you, at eye height, facing you, about 35° wide (38 cm).
      The header shows "NOW PLAYING" on the left and the clock, the time left with "ends HH:MM" and "battery NN %" on
      the right. There is no "Docked" tag. Point the RIGHT controller at the panel: its laser and dot appear only while
      it points at the panel. The left controller has no laser.
- [ ] **Readability:** body text, tab names, list rows and the footer are readable without effort at this distance.
      Note whether the text looks sharp (one panel pixel per display pixel at the defaults). Note the
      distance and size you prefer: System, Panel, Distance and Size.
- [ ] **Close and open with the right controller:** press the right menu button once (short). The panel fades out,
      and the controller labels go back to PLAY / PAUSE. Press it again: the panel opens in front of where you now
      look, and the RIGHT laser points at it.
- [ ] **Open with the left controller:** close the panel. Press the menu button on the LEFT controller (the view
      button at the front of its face). The panel opens in front of you, and the LEFT laser points at it. The right
      controller shows no laser, and its trigger plays and pauses the film. Click a tab with the left trigger. If the
      view button does nothing (`--debug` logs no `menu pressed` for the left hand), the runtime keeps it: report it,
      and the menu moves to the left stick click (`tools/make_action_map.gd`).
- [ ] **World-locked:** with the panel open, turn your head 60° to one side and back, and walk one step. The panel
      stays at the same place in the room. It does not follow the head and it does not move a little with the head.
- [ ] **Recentre:** turn your head 60° to one side. Hold the menu button 0.6 s. The panel moves to the front of the
      head and the controller vibrates once. Release: the panel stays open. A short press after that closes it.
- [ ] **Always level:** tilt your head to one side (roll) and look about 45° down, then hold the menu button 0.6 s.
      The panel moves in front of you, tilted back to face you, but its top edge stays horizontal: it does not roll
      with the head.
- [ ] **Lying back:** lie back (or lean back fully) and look at the ceiling. Hold the menu button 0.6 s. The panel
      moves above you, facing your face, the correct way up for your eyes. The laser and the trigger work there.
      Sit up, hold the menu button again: the panel comes back in front of you.
- [ ] **Each tab:** open Files, Picture, Sound, Subtitles, Room and System. Each tab shows its content and the panel
      does not move while you use it.
- [ ] **One controller, keyboard:** with only the left controller (the right one put down): Files, Network, "+ Add
      host". Type `nas.local` on the on-pane keyboard with the left laser and the left trigger, then Cancel. Do it
      again with only the right controller.
- [ ] **Stick, scroll:** point the laser at the Files list (Test patterns) and push the stick up and down: the list
      scrolls. Point at a slider (Picture, Size) and push the stick right and left: the slider moves (right
      increases).
- [ ] **Stick, focus without aiming:** point the laser away from the panel. Move the stick of the pointer controller:
      a focus outline moves between the controls with a light tick. The trigger activates the focused control. The
      stick of the other controller still seeks the film.
- [ ] **Pointer without tracking:** open the panel with the right controller, then switch the right controller off
      (or hide it from the headset's cameras). Within a second, the left laser points at the panel.
- [ ] **System row:** System, scroll to Hardware video. The row shows "Hardware 10-bit video: on (Q10C through the
      GPU, stock driver)" and Details opens with the laser. There is nothing to set up and no password field.
- [ ] **Head follow (optional):** System, Panel, "Follow my head" on. Turn your head 15°: the panel stays. Turn
      40°: after a moment the panel moves smoothly to the front of the head and stops. Switch it off again, or Reset
      layout (38 cm, 0.6 m, 0.6 s, world-locked, right-handed).
- [ ] **Info overlay:** close the panel and click the LEFT stick: the info overlay shows the time, the battery and
      the end time (the quick look while the panel is closed). Open the panel: the overlay hides.
- [ ] **Curvature in the cinema:** Room, Cinema; open a flat film. Picture, Curvature: 0 % is flat; 50 % bends the
      screen a little; 100 % wraps it evenly around your seat (all of the picture at the same distance), and never
      into a tube. Change Distance: the curve keeps its percentage. There is no "Curve to distance" button.
- [ ] **Help lines:** in the Picture and Sound tabs, a grey line under each unclear control says what it does (for
      example under Gate weave, Dark-scene lift, Soft edges, Night mode, Dialogue boost). Each line is readable and
      fits one line. Note any control that is still unclear, and any line that is wrong.
- [ ] **Log:** `grep -i 'error' panel.log` has no lines from `ui_layer.gd`, `pane.gd` or `pane_pose.gd`.

### 10-bit without P010: Q10C through a YCbCr sampler, and VP9 superframes (engine-q10c; the PLAYER_Q10C engine; `spikes/04-q10c-probe/README.md`, `spikes/03-player/README.md`, "Q10C through a YCbCr sampler (2026-10-31)")

Written while the headset had the patched module, so P010 was offered; `HWVIDEO_P010=0` made the engine ignore it and
use Q10C, as on the stock module. Since 2026-11-02 the module is gone (`docs/decisions.md` D21): the stock driver offers
no P010, `HWVIDEO_P010=0` changes nothing, and Q3's P010 reference for the 2160p file can't be made. Do the probe (Q1)
before the engine runs: its winner tells what to set if the engine's own choice is wrong. One decoder user at a time,
about 5 s apart.

On the PC: `scp spikes/04-q10c-probe/q10c-probe frame:spike01/q10c-probe` (aarch64, sha256 in the probe README), then
`tools/morning-deploy.sh --engine godot.linuxbsd.template_debug.arm64.PLAYER_Q10C`.

- [x] **Q1. The probe** (on the headset, `cd ~/spike01`):
      ```
      ./q10c-probe > q10c-list.txt 2>&1
      ./q10c-probe --selftest > q10c-selftest.txt 2>&1
      ./q10c-probe --scan-formats > q10c-scan.txt 2>&1
      ./q10c-probe --decode streams/main10_3832x1596_10s.h265 --capture Q10C --out ~/q10c-out --dump-raw > q10c-decode.txt 2>&1
      sleep 2
      ./q10c-probe --decode streams/main10_3832x1596_10s.h265 --capture P010 --out ~/q10c-out-p010 > q10c-p010.txt 2>&1
      grep -E "RESULT|SKIPPED|Summary" q10c-decode.txt q10c-p010.txt
      ```
      Copy the five `.txt` files to the PC (`scp "frame:spike01/q10c-*.txt" .`); the lead or the next agent reads them.
      - `q10c-list.txt`: the driver name and version, then for `G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16` the
        modifiers. Upstream Turnip lists only `LINEAR` and `QCOM_COMPRESSED (0x0500000000000001)`; a `0x...07`, `0x...05`,
        a `NOT LISTED but ...` line or an extra vendor format is what Valve's Turnip adds. Note them.
      - `q10c-selftest.txt`: `PASS` for G10X6, G8 and G16 (Turnip's YCbCr sampling of known codes). A `FAIL` there means
        the pass itself is wrong on Turnip: say so, and the rest is not to be trusted.
      - `q10c-decode.txt`: `SOURCE_CHANGE: CAPTURE ...; offered: ...` (note the list), `CAPTURE Q10C 3840x1600, ...
        sizeimage 12369920` (an `ERROR: asked for CAPTURE Q10C, the driver chose ...`: stop here and report), then one `RESULT <tag>: PLAUSIBLE PICTURE`, `GARBAGE` or `FAILED` per attempt. The winner is a `PLAUSIBLE
        PICTURE`; its tag is `Q10C-<VkFormat>-<modifier>-<layout>`.
      - `q10c-p010.txt` (the control): `RESULT P010-...-linear: PLAUSIBLE PICTURE`.
      Then on the PC (any ffmpeg; Python with numpy and Pillow):
      ```
      mkdir -p spikes/04-q10c-probe/results && scp "frame:q10c-out/*.yuv" "frame:q10c-out-p010/*.yuv" spikes/04-q10c-probe/results/
      ffmpeg -i $O/test/main10_3832x1596_10s.h265 -frames:v 1 -f rawvideo -pix_fmt yuv420p10le ref.yuv
      python spikes/04-q10c-probe/compare.py ref.yuv spikes/04-q10c-probe/results/*.yuv --size 3832x1596 --png
      ```
      (`$O` as in B5; the clip is also on the headset in `spike01/streams/`.) `ref.yuv` is 18,347,616 bytes. Expect the
      P010 control 100 % identical (or PSNR above 60 dB), and the winner the same. A winner below 40 dB is close but
      read differently (paste the line). No winner at all: Q10C cannot be read by this Turnip; skip Q2 to Q4 and say so.
      **Done 2026-10-31.** Selftest `PASS`. Winner `RESULT Q10C-1000156013-0500000000000001-meta: PLAUSIBLE PICTURE`
      (Valve's Mesa 26.3.0_devel). compare.py: the Q10C winner and the P010 control are both 100 % identical to the
      FFmpeg reference in Y, Cb and Cr. Reports in `spikes/04-q10c-probe/results/` (the .yuv and .png frames, 67 MB,
      stay out of git).
- [x] **Q2. The engine on the three 10-bit HEVC files with Q10C.** On the headset, after the session setup at the top:
      ```
      P2160=<a 2160p 10-bit file>
      Q='DmabufImage|Q10C|CAPTURE (formats|generation)|imported .* decoder buffers|software decode|switching|ERROR|decode .* fps|Final'
      n=0; for f in "$F720" "$F10" "$P2160"; do n=$((n+1))
        HWVIDEO_P010=0 spikev --media="$f" $S --start=600 --screenshot=/tmp/q10c-$n.png --screenshot-frame=240 --quit-after=900 2>&1 | tee q10c-$n.log | grep -E "$Q" | cut -c1-300
        sleep 5
      done
      ```
      Expect, per file: `DmabufImage: Q10C through a YCbCr sampler: ... lists ... Candidates: ...` (first file only),
      `V4L2Decoder: HWVIDEO_P010=0: not using the P010 the driver offers.`, `HWVideoTexture: hardware decode, 10-bit
      as Q10C through a YCbCr sampler (no P010).`, `CAPTURE generation 1: Q10C ...`, `HWVideoTexture: imported N
      decoder buffers (generation 1): Q10C through a YCbCr sampler (<format> <modifier> <layout>) ...; shown as P010.`,
      then `HWVideoTexture: the Q10C picture looks right (luma neighbour difference ... )`. The 2 s lines end in
      `, hardware (10-bit, Q10C)`, decode at the film's rate (24 fps), 0 decoder errors.
      - Failure lines, each followed by `switching to software decode` and the file playing on in software (720p and
        1080p; 2160p cannot): `No Q10C import worked (...)`, `No Vulkan import for Q10C: ...`, or `The 10-bit picture
        through Q10C (...) looks like noise (...)`. Paste them. Then rerun the first file with the probe's winner:
        `HWVIDEO_P010=0 HWVIDEO_Q10C_FORMAT=<VkFormat> HWVIDEO_Q10C_MODIFIER=0x<modifier> HWVIDEO_Q10C_LAYOUT=<layout>`
        in front (the three parts of the winner's tag).
      - `picture check inconclusive` 8 times (a flat or dark start) is not a failure: look at the screenshot.
      **Done 2026-10-31.** All three, and the HDR10 film (Q4), logged `hardware (10-bit, Q10C)` and `the Q10C picture
      looks right`, 0 decoder errors, 3 or 4 frames dropped at the start only. 720p 23 fps, 1080p and 2160p 24 fps. CPU
      13 to 22 % of a core. The four screenshots have correct colours (no shift, bands or blocks).
- [ ] **Q3. Screenshots against software.** The same three runs, with `HWVIDEO_FORCE_SW=1` in place of
      `HWVIDEO_P010=0` and `--screenshot=/tmp/sw-$n.png` (the 2160p file is too big for software: without the module
      it has no reference, so skip that pair). Then `scp "frame:/tmp/q10c-*.png" "frame:/tmp/sw-*.png" .`. Each pair matches: the
      same colours, no shift, no band or blocks, no stripes every 48 or 192 pixels. (The frames can differ by a few
      frames, as software may drop at the start.) In the headset, the 1080p file with Q10C: no blockiness or banding
      that software doesn't have.
- [x] **Q4. The HDR10 2160p film with Q10C.** `HWVIDEO_P010=0 spikev --media="$FHDR" $S --start=600 --gpu-time
      --screenshot=/tmp/q10c-hdr.png --quit-after=1800 2>&1 | grep -E "$Q|Colour:|GPU" | cut -c1-300`. The same
      Q10C lines as Q2, `Colour: BT.2020 ... smpte2084 (HDR pq, ...)`, 24 fps, 0 errors, and the picture as B7's
      (`/tmp/hdr.png`). Note the GPU ms against B7 (the YCbCr pass adds a little).
      **Done 2026-10-31.** `Colour: matrix BT.2020 ... smpte2084 (HDR pq, 1000 nits to 203 nits)`, 23.5 fps, 0 errors,
      the picture right. GPU 0.31 to 0.52 ms over the four films.
- [x] **Q5. VP9: sequential sessions with superframes split.** Preferably right after a reboot (the earlier crash came
      on the third VP9 session of the boot). Use `W8`, `I8` and `G` from "Hardware VP9" above, then:
      ```
      n=0; for m in $W8 $I8 $W8 $I8 $W8; do n=$((n+1))
        spike --media=$m --quit-after=600 2>&1 | tee vp9s-$n.log | grep -E "$G|superframe|VP9:" | cut -c1-260
        sudo dmesg | tail -40 | grep -iE "iris|0x5000003|smmu|preempt|oops"
        grep -q "VP9 decoder fault" vp9s-$n.log && break
        sleep 5
      done
      ```
      Per session: `V4L2Decoder: VP9 superframes are split with vp9_superframe_split (the first at T s: 2 frames, 1
      hidden), one frame per OUTPUT buffer.`, 24 fps, 0 decoder errors, and at the end `V4L2Decoder: VP9: N packets
      fed; M superframes split into K frames (H hidden) by vp9_superframe_split.` and `VP9 session released.`. No
      `dmesg` line after any session. **Stop at the first `0x5000003`** in `dmesg` or a `VP9 decoder fault` line (the
      loop stops on the latter by itself): note the session number, paste the `superframe`/`VP9:` lines of that
      session and the `dmesg` lines. Five clean sessions: the superframes were the cause; tick it. A line `isn't
      available ... superframes go to the decoder whole` means the FFmpeg build lacks the filter: report it.
      **Done 2026-10-31, uptime 2.5 h, PLAYER_Q10C.** 8-bit (Profile 0), webm and ivf alternating: five clean
      sessions. Each split superframes (`the first at 0.459 s: 2 frames, 1 hidden`), 24 fps, 0 decoder errors, `VP9
      session released`, and no `dmesg` line. Before the split, the third session crashed. Then 10-bit (Profile 2,
      `vp9p2_720p_10bit_10s.ivf`, `HWVIDEO_P010=0`, so Q10C): the first session clean; the second crashed the
      firmware at its start (`received system error of type 0x5000003`, firmware reloaded at once; `VP9 decoder fault:
      4 DQBUFs in a row failed`, software took over and played the clip at 24 fps). The next 8-bit session was clean in
      hardware. So the split fixed 8-bit in this run, and a crash remains after a 10-bit VP9 session, or after seven
      sessions in one boot. The fallback keeps playback going; no reboot was needed.


### Every format in software (engine-codecs; the PLAYER_CODECS engine; `docs/decisions.md` D18, `docs/features.md`, "Every format")

On the PC: `wsl -d Ubuntu -- bash -c 'cp ~/src/godot-player-codecs/bin/godot.linuxbsd.template_debug.arm64 /mnt/c/path/to/FrameCine/build/out/godot.linuxbsd.template_debug.arm64.PLAYER_CODECS'`,
then `tools/morning-deploy.sh --engine godot.linuxbsd.template_debug.arm64.PLAYER_CODECS`. The files are on the PC's
SMB share. Open each from the Files tab with the overlay on (left stick click), a minute or two each, one seek.

- [ ] **C1. The DivX AVI that showed the test pattern:** `divx5_dx50.avi` of the test library (codecs_test.gd)
      (DivX 5, 680x560, MP3). It plays with sound; the overlay says `software (MPEG-4) 680x560`, decode 25 fps,
      dropped 0. The log has `SoftwareVideoDecoder: MPEG-4 part 2 (DX50) 680x560 ... (FFmpeg mpeg4, 4 frame
      threads)`. The picture is not stretched (square pixels).
- [ ] **C2. The rest of the old library:** DivX 3 (`div3_wma.avi`, WMA sound), Xvid + AC-3
      (`xvid_ac3.avi`), RealVideo (`rv40_cook.rm`, Cook sound), WMV
      (`wmv8_wma2.wmv`), FLV (`flv1_mp3.flv`), MPEG-1
      (`mpeg1_mp2.mpg`, a wide picture from 49:33 pixels). Each: sound, decode at the film's
      rate, 0 dropped after the first seconds, a seek settles.
- [ ] **C3. DVD and TV MPEG-2:** `dvd_bff/VIDEO_TS/VTS_01_1.VOB` (AC-3, bottom field first) and
      `mpeg2_ps_169.mpg` (16:9 anamorphic). The screen is 16:9 where the film
      is; with Picture > deinterlace on "auto", motion is smooth with no combing; the overlay says `software (MPEG-2)`.
- [ ] **C4. The heavy ones:** VC-1 1080p (`Animated.VC-1.Remux.mkv`, from 20:00) and
      MPEG-2 1080i (`mpeg2_1080i.ts`). Note decode fps, dropped frames and the overlay's
      CPU % over two minutes. FFmpeg's VC-1 decoder has no frame threads: if it drops frames, say how many a second.
- [ ] **C5. AV1:** copy `~/src/codec-tests/av1_1080p.mkv` (WSL) to the share; it plays at 30 fps with 0 dropped. If a
      4K AV1 file is at hand, note its decode fps and CPU: the limit (4K at 30 fps) is an estimate to confirm or lower.
- [ ] **C6. Nothing old broke:** an H.264 and an HEVC film still play in hardware (overlay `hardware`), and a 10-bit
      file as before.

### Hardware 10-bit video without the module (app-iris-setup; `docs/features.md`, "Hardware 10-bit video", D21)

The decoder module and the app's one-time setup are gone. Nothing here needs sudo or a password.

- [ ] **The log:** `app 2>&1 | grep "HW video"` says `HW video: 10-bit path q10c (on (Q10C through the GPU, stock
      driver))`. No `HW setup:` line and no card above the tab body.
- [ ] **The row:** System, Hardware video says "Hardware 10-bit video: on (Q10C through the GPU, stock driver)".
      Details: P010 offered no, Q10C read yes, the decoder's formats with `Q10C`, VP9 in hardware yes.
- [ ] **A 10-bit file:** `$F720` plays with `hardware (10-bit)` in the overlay; the row still says Q10C.
- [ ] **The command:** over the listener, `$L send hwvideo_status` returns `"path": "q10c"`; `hwsetup_status` is an
      unknown command.
