# Playback features

Features from `ideas.md`, as built. Each entry says what it does, its settings keys in `user://settings.cfg`, its
API for the menu, and what is not tested yet. The numbers are the `#` column of `ideas.md`.

All features hang off one hub node, `main.features` (`app/scripts/play/features.gd`). The menu reads their
properties, calls their setters and listens to their signals. The core runs without the hub.

The menu is one panel in front of the headset (`docs/ui-design.md`, "Revision 2", since 2026-10-31): the menu button
on either controller opens it 0.6 m ahead, level, and makes that controller the pointer, a short press closes it, a
0.6 s hold recentres it, and it is world-locked. Where an entry below says "the pane", it means this panel. The glance
state that some entries mention is gone; its clock, time left and battery are in the panel's header.

Desktop test command used throughout (WSL, x86_64 engine build, no headset):

```
godot --headless --xr-mode off --path app --script res://tests/<test>.gd
godot --xr-mode off --path app -- --no-xr --file=stub://flat_sbs --overlay
```

## Index

Every feature below is built and tested on the desktop (WSL, the fork's x86_64 build). None is tested on the headset
yet; each section's "Untested" says what is left, and `docs/morning-checklist.md` has the checks. "Settings" are the
sections of `user://settings.cfg`; `<environment id>` and `<id>` sections hold one environment's values, and
`_files` sections one value per file.

| Feature | # | Settings | Status |
|---|---|---|---|
| [Wall-clock end time](#36-wall-clock-end-time) | #36 | `[display]` | on |
| [Battery versus film end](#2-battery-versus-film-end) | #2 | `[battery]` | on |
| [3D depth slider](#4-3d-depth-slider) | #4 | `[stereo]`, `[stereo_depth_files]` | on |
| [Resume per file](#7-resume-per-file) | #7 | `[resume] mode`; positions in `user://resume.cfg` | on |
| [Catch-up replay](#11-catch-up-replay) | #11 | none | on |
| [Chapters](#15-chapters) | #15 | none | on |
| [Sleep timer](#17-sleep-timer) | #17 | `[sleep]` | on |
| [Room light follows playback](#20-room-light-follows-playback) | #20 | `[room]` | on |
| [Container metadata first](#25-container-metadata-first) | #25 | none | on |
| [Picture controls](#27-picture-controls) | #27 | `[picture_<environment id>]` | on |
| [Language memory](#28-language-memory) | #28 | `[language]`, `[subtitles]` | on |
| [Curved screen](#31-curved-screen) | #31 | `[screen_<environment id>]` | on |
| [Haptic ticks](#32-haptic-ticks) | #32 | `[haptics]` | on |
| [Manual zoom and pan](#35-manual-zoom-and-pan) | #35 | `[zoom_files]` | on |
| [2D from 3D](#59-2d-from-3d) | #59 | `[stereo]` | on |
| [Horizon correction](#77-horizon-correction) | #77 | `[horizon_files]` | on |
| [Edge fade for 3D](#79-edge-fade-for-3d) | #79 | `[stereo]` | off by default |
| [Subtitle delay per track](#61-subtitle-delay-per-track) | #61 | `[subtitle_delay_files]` | on |
| [Sidecar JSON for the chosen mode](#60-sidecar-json-for-the-chosen-mode) | #60 | `[sidecar]` | off by default |
| [Shuffle, repeat, queue editing](#78-shuffle-repeat-queue-editing) | #78 | `[queue]` | on (shuffle and repeat off by default) |
| [Frame step and A-B loop](#80-frame-step-and-a-b-loop) | #80 | none | on |
| [Favourites and search (data side)](#76-favourites-and-search-data-side) | #76 | `[favourites]` | data side; the pane shows it |
| [Accessibility pack (settings)](#74-accessibility-pack-settings) | #74 | `[accessibility]` | on |
| [Subtitle files next to the video](#50-subtitle-files-next-to-the-video) | #50 | `[subtitles]` | on |
| [Playback speed, pitch kept](#69-playback-speed-pitch-kept) | #69 | none | on |
| [Subtitle rendering, and a second subtitle track](#67-subtitle-rendering-and-65-a-second-subtitle-track) | #67, #65 | `[subtitles]` | on |
| [HDR tone mapping, and the colour matrix](#85-hdr-tone-mapping-and-the-colour-matrix) | #85 | `[hdr]`, `[tonemap_<environment id>]` | on |
| [Still pictures, photo spheres and a slideshow](#22-still-pictures-photo-spheres-and-a-slideshow) | #22 | `[images]` | on (slideshow off by default) |
| [More environments, photo rooms, glTF rooms](#52-more-environments-18-photo-rooms-53-gltf-rooms) | #52, #18, #53 | `[env_<id>]`, `[screen_<id>]` | on |
| [Floor reflection](#62-floor-reflection) | #62 | `[env_<id>]`, `[reflection]` | on where the room has a floor for it (off in the void) |
| [Lying down, head-follow screen, screen size in degrees, seat choice](#12-lying-down-33-head-follow-screen-55-screen-size-in-degrees-19-seat-choice) | #12, #33, #55, #19 | `[comfort]`, `[seats]` | on (each by its control) |
| [Up next, pre-show, intermission, jog wheel, stereo screenshots](#34-up-next-37-pre-show-39-intermission-63-jog-wheel-66-stereo-screenshots) | #34, #37, #39, #63, #66 | `[up_next]`, `[preshow]`, `[intermission]`, `[jog]` | on (intermission off by default) |
| [Fisheye lens profiles, folder rules, light sharpen, deinterlace](#73-fisheye-lens-profiles-83-folder-rules-90-light-sharpen-95-deinterlace) | #73, #83, #90, #95 | `[lens]`, `[lens_files]`, `[folder_modes]`, `[picture_<environment id>]`, `[picture]` | on (sharpen and deinterlace off by default) |
| [Dual fisheye 360](#dual-fisheye-360) | none | `[dual_fisheye]`, `[dual_fisheye_files]`, `[dual_fisheye_<profile>]` | on (guessed for 360 camera names and dual fisheye tags) |
| [Virtual cinema speakers, world-locked sound for 180 / 360](#21-virtual-cinema-speakers-47-world-locked-sound-for-180--360) (spatial audio) | #21, #47 | `[speakers]`, `[spatial]` | off by default (until the headset check) |
| [Bias light from the picture](#29-bias-light-from-the-picture) | #29 | `[bias_light]` | off by default |
| [Night mode and dialogue boost](#26-night-mode-and-dialogue-boost) | #26 | `[sound]` | off by default |
| [Quad layers (a spike behind flags)](#70-quad-layers-a-spike-behind-flags) | #70 | none (flags `--pane-layer`, `--video-layer`) | spike behind flags |
| [Film layer](#70-film-layer) | #70 | `[view] film_layer` | on by default (flat films) |
| [The environment reacts to the film](#81-the-environment-reacts-to-the-film) | #81 | `[react]` | off by default |
| [Projector mode](#92-projector-mode) | #92 | `[projector]` | off by default |
| [Time of day for the outdoor rooms](#84-time-of-day-for-the-outdoor-rooms) | #84 | `[time_of_day]` | on, "night" by default (the room as designed) |
| [Zoom lens for 180 and 360 pictures](#38-zoom-lens-for-180-and-360-pictures) | #38 | `[zoom_lens]` | on (grip + trigger) |
| [A/V latency test card, and the offset per refresh rate](#24-av-latency-test-card-and-the-offset-per-refresh-rate) | #24 | `[audio]` | on (the card is opened by hand) |
| [Music files](#64-music-files) | #64 | `[music] visualiser` | on |
| [Auto letterbox crop](#42-auto-letterbox-crop) | #42 | `[picture] auto_crop`, `auto_crop_grow` | off by default |
| [Trick play at 4x and 8x](#46-trick-play-at-4x-and-8x) | #46 | `[trick_play] enabled` | on (hold the stick right) |
| [Live streams](#live-streams) | none | `[network] live_latency` | on |
| [Gapless playlist](#44-gapless-playlist) | #44 | `[queue] gapless` | off by default (headset check, runbook E7) |
| [Picture in picture](#87-picture-in-picture) | #87 | `[pip]` | on demand (the pane opens it) |
| [Seek-bar thumbnails](#40-seek-bar-thumbnails) | #40 | `[thumbnails] enabled` | off by default (memory check) |
| [Object physics](#object-physics) | none | none (the places are in the kept room) | on in kept rooms with objects |
| [Crossfade between items](#94-crossfade-between-items) | #94 | `[crossfade] music`, `videos` | off by default |
| [Hardware 10-bit video](#hardware-10-bit-video) | none | `[hwvideo] hw_vp9` | read-only: P010 when the driver offers it, else Q10C, else software |
| [Agents on the headset](#agents-on-the-headset) | | `[assistant] voice_to` | on demand, from Files |
| [The Library](#the-library) | | none | on; a place in Files, made on first use |
| [Android apps](#android-apps) | | none | on demand, from Files |
| [Effect library](#effect-library) | | none | data and shaders; a room names an effect (`docs/effects.md`) |
| [Controller look](#controller-look) | | `[controllers] look`, `look_options` | on; black as the controllers come by default |
| [Showrooms](#showrooms) | | none | in the Room tab's Showrooms group (`docs/showrooms.md`) |
| [Every format: old and other codecs in software](#every-format-old-and-other-codecs-in-software) | none | none | on (engine branch `frame/codecs`) |
| [The browser: stick pointer and voice into a field](#the-browser-stick-pointer-and-voice-into-a-field) | none | `[browser] pointer_follows_gaze`, `laser`, `dictation_partials` | on (the laser off by default) |

## #36 Wall-clock end time

Wherever a remaining duration is shown, the clock time it ends at is shown too: "ends 23:20". An end after
midnight says "ends 01:10 tomorrow". An end more than a day away gives the weekday.

- **Where:** the info overlay's time line (`0:42:17 / 2:06:33  ends 23:20  playing`), and the menu panel's header
  ("21:42  ·  1:12 left, ends 22:54  ·  battery 74 %").
- **API:** `scripts/play/end_time.gd` (static). `format_end(remaining, speed)`, `clock_at(unix)`,
  `end_unix(remaining, speed)`, `format_remaining(remaining)` ("1:24 left"). The hub has `remaining()` and
  `end_text()` for what is playing.
- **Settings:** `[display] clock_24h` (default true; false gives "11:20 pm").
- **Local time** comes from the system's time zone (`Time.get_time_zone_from_system()`).
- **Tested:** `tests/test_end_time.gd` (21 cases: time zones, the day boundary, 12-hour clock). The overlay line in a
  headless desktop run.
- **Untested:** the device's time zone setting. SteamOS may run the app with UTC if no zone is set; check the
  overlay's end time against a real clock.

## #2 Battery versus film end

Measures the headset battery's drain and predicts when it runs out, against when the film ends: "battery 72 %, ends
23:20 | film ends 22:47". When the battery would run out first, the line adds "(battery first)".

- **Battery:** found at run time under `/sys/class/power_supply`: the first entry of type `Battery` whose scope is not
  `Device` (a peripheral) and that is present. On the headset that is the fuel gauge `max1720x_bat_*` (the probe of
  2026-10-30 saw `charge_now`/`charge_full` in µAh, a signed `current_now` and `voltage_now`). Without one (a
  desktop), the line says "no battery" and nothing fails.
- **Level:** `energy_now/energy_full`, else `charge_now/charge_full`, else `capacity`. The charge counter has far
  finer steps than the 1 % capacity, so the drain settles within minutes.
- **Drain:** a least-squares slope over the last 10 minutes, one sample every 20 s. Until 2 minutes of samples
  exist, the instantaneous `power_now` (or `|current_now| × voltage_now`) stands in. With neither, the spike 04
  average of 9 W does. Plugging in or out restarts the window.
- **Verdict:** `ok` with 15 minutes or more to spare, `tight` below, `short` when the battery ends first,
  `charging`, or `unknown`.
- **API:** `main.features.battery` (`scripts/comfort/battery_forecast.gd`). Signal `forecast_changed(info)` after each
  sample, and `get_forecast()`. The dictionary holds `available`, `percent`, `charging`, `drain_per_hour`,
  `drain_source`, `watts`, `battery_end_unix`, `battery_end_text`, `film_end_unix`, `film_end_text`,
  `margin_minutes`, `verdict` and `text`. The menu panel's header shows `percent` (and charging) next to the clock.
  `main.features.battery_text()` is the overlay's line.
- **Where:** the info overlay's battery line, and the header of the menu panel (`ui/pane_ui.gd`, `status_text()`).
- **Settings:** `[battery] margin_ok_minutes` (default 15).
- **Tested:** `tests/test_battery_forecast.gd` on a fake power-supply tree (a controller battery skipped, charge and
  current units, the window slope, charging, no battery). `tests/test_features.gd` in the real scene on a desktop
  without a battery.
- **Untested:** the real gauge. The sign of `current_now` while discharging, whether `power_now` exists, and whether
  the window's drain matches the spike 04 figure of about 9 W.

## #4 3D depth slider

A horizontal shift between the two eyes' pictures: positive pushes the picture further away, negative brings it
nearer. It applies to stereo layouts only. The strip uncovered at the edge is black, except in 360, where the picture
wraps around.

- **Shader:** `video.gdshader` uniforms `stereo_shift` (fraction of one eye's width; each view moves by half of it)
  and `wrap_x` (set by `video_screen.gd` for 360).
- **Remembered:** a global value, and a value per file that wins when the file has one. The file key is a hash of
  the path and size (`scripts/play/file_key.gd`, path only for network files).
- **API:** `main.features.depth` (`scripts/play/stereo_depth.gd`). `value`, `global_value`, `has_file_value()`,
  `set_depth(v, for_file)`, `nudge(step, for_file)`, `clear_file()`, signal `changed(value, for_file)`. Range ±0.04,
  step 0.002. The pane's slider wants a "this file only" toggle next to it.
- **Desktop keys** (menu hidden): `[` and `]` nudge. With Shift they nudge this file's own value.
- **Settings:** `[stereo] depth`, `[stereo_depth_files] <file key>`.
- **Tested:** `tests/test_features.gd` (global, per file, back to global, 360 wrap). A WSLg render of both eyes of the
  full SBS pattern at +0.04: the left view moved left and the right view right, with black strips at the outer edges.
- **Untested:** how it feels in the headset, and whether ±4 % is the right range on a 3 m screen and in 180.

## #7 Resume per file

Each file remembers where it was left. Opening it again goes back there, 3 s early so the scene is picked up. The B
button (previous) still goes to the start when more than 3 s in, which is "start over".

- **Stored** in `user://resume.cfg`, not `settings.cfg`, because it changes every few seconds. One section per file
  key (hash of path and size; path only on a share) with `path`, `title`, `position`, `duration`, `updated` (Unix
  time) and `finished`. At most 500 files; the oldest go first.
- **When saved:** every 5 s while playing, on pause, when another file opens, and on exit.
- **Rules:** a position under 30 s is never saved and never replaces a saved one, so opening a file by mistake keeps
  its place. Within the last 5 % or the last minute, whichever is longer, the file counts as finished: its position
  is cleared and `finished` is set, so a row can show it as watched. Captured windows are not tracked; test patterns
  are.
- **Modes** (`[resume] mode`): `auto` (default) seeks and emits `resumed(position)`, so the pane can show "Resumed at
  0:42:17" with a "Start over" button. `ask` emits `resume_offered(position)` and waits for `resume()` or
  `start_over()`. `off` neither saves nor resumes.
- **API:** `main.features.resume` (`scripts/play/resume.gd`). `position_for(path)` and `entry_for(path)` for the resume
  marker on a list row, `continue_watching(limit)` for the "continue watching" row (most recent first, each with
  `path`, `title`, `position`, `duration`, `updated`, `progress`), `forget(path)`, `resume()`, `start_over()`,
  `pending_position`, and signal `entries_changed`.
- **Tested:** `tests/test_features.gd` with test patterns: saved on switching files, listed, resumed, a short visit
  keeps the place, finished near the end, ask mode, resume and start over.
- **Untested:** the headset, and a real file through MediaSource: the seek is issued on the frame after the file
  opens, before the first frame shows. Network files: the key is the path only.

## Subtitle state (groundwork for #11, #28, #61, #74)

The app had no subtitles. Catch-up replay, language memory, subtitle delay and forced subtitles all need a subtitle
state, so there is now a small one, with a plain text display until real rendering (#67) exists.

- **Source API:** `VideoSource` gains `get_subtitle_tracks()`, `select_subtitle_track()`, `get_subtitle_track()`,
  `read_subtitle_event()` and `get_chapters()`. The hardware source passes them to `MediaSource`. The test patterns
  have two text tracks of their own (English "Line N at M:SS" and French "Ligne N à M:SS"), a line every 5 s.
- **State:** `main.features.subtitles` (`scripts/play/subtitles.gd`). `tracks`, `track`, `enabled`, `text`,
  `set_enabled()`, `select_track()`, `cycle_track()`, `pick_track()`, `get_state()`/`set_state()`, `delay`, and
  signals `tracks_changed`, `track_changed`, `text_changed`. Events are kept for the whole file and de-duplicated, so
  a jump back shows earlier lines even when the demuxer does not deliver them again. With subtitles off, no track is
  selected, which saves the demuxer the work.
- **Display:** replaced by the subtitle renderer (#67, below). The stand-in `Label3D` is gone.
- **Desktop key** (menu hidden): `S` cycles off and each track.
- **Settings:** `[subtitles] enabled`, `[subtitles] size` (scale, 0.5 to 3).
- **Playback controller:** a new `seeked(seconds)` signal.
- **Tested:** `tests/test_features.gd` with the test pattern's tracks (lines at their times, open-ended events,
  lines kept after a jump back, cycling, off stays off, the spherical placement). WSLg renders of a flat and a 180
  pattern with a line showing.
- **Untested:** a real file's subtitle track through `MediaSource` (the event dictionary is used as its class
  reference documents it), legibility and size in the headset.

## #11 Catch-up replay

One action replays the last 10 s with subtitles forced on. Once playback is back where the replay started, the
subtitles return to how they were.

- **Rules:** a second press during a replay goes back another 10 s and keeps the original end. The replay also
  ends, and the subtitles are restored, when someone seeks elsewhere or another file opens. If the user changes the
  subtitles during the replay, their choice stays. A paused film starts playing. Without subtitle tracks it still
  replays, without text.
- **API:** `main.features.catch_up` (`scripts/play/catch_up.gd`). `replay()`, `cancel()`, `active`, `end_position`,
  signals `started(from, to)` and `finished`.
- **Controls:** Backspace on a keyboard (menu hidden). There is no controller binding: every button is taken, and
  the pane is the place for a "Replay 10 s" button next to −10 s. A later binding could be a long press on B.
- **Settings:** none.
- **Tested:** `tests/test_features.gd` with the test pattern (back 10 s, playing, subtitles on, a replayed line
  shows, a foreign seek ends it, the end point restores, an existing track is kept, the user's change is kept).
- **Untested:** a real file. `MediaSource` delivers events again after a backward seek only from the keyframe the
  seek lands on, so a line that started before that keyframe is missing unless it was read earlier with subtitles
  on (then the kept events cover it).

## #15 Chapters

The file's chapters: skip to the next or previous, the title in the overlay, and tick positions for the seek bar.

- **Source:** `VideoSource.get_chapters()`. The hardware source calls `MediaSource.get_chapters()` (`{index, start,
  end, title}` in media seconds), which the engine fork has since 2026-10-31 (`media_source_extras.cpp`). Every test
  pattern has five chapters of 2 minutes ("Opening", "Colour bars", "Motion", "Stereo check", "Closing").
- **Rules:** the list is sorted, each end is the next start (or the duration), and an empty title becomes
  "Chapter N". Previous goes to the start of the current chapter when more than 3 s into it, else to the chapter
  before, like the previous-file button. Next in the last chapter does nothing.
- **API:** `main.features.chapters` (`scripts/play/chapters.gd`). `chapters`, `current`, `next_chapter()`,
  `previous_chapter()`, `go_to(i)`, `index_at(t)`, `title_text()` ("3/12 Title"), `tick_positions()` (fractions of
  the duration for the seek bar's ticks), signals `chapters_changed(chapters)` and `chapter_changed(index, title)`.
- **Overlay:** a line "chapter 3/12 Title" while a chapter plays.
- **Controls:** PageUp and PageDown on a keyboard (menu hidden). On the controller, the left d-pad's left and
  right, but only with the opt-in action map below.
- **D-pad action map (opt-in):** `tools/make_action_map.gd` now also writes `xr/openxr_action_map_dpad.tres`: the
  shipped map (unchanged, byte for byte) plus `chapter_prev`, `chapter_next` and `replay` (catch-up, #11) on the
  left d-pad's left, right and down clicks. One path the runtime rejects voids the whole profile's bindings, and no
  device run has tried the d-pad, so the shipped map does not use it. To try it, create `app/override.cfg`:

  ```
  [xr]
  openxr/default_action_map="res://xr/openxr_action_map_dpad.tres"
  ```

  The controller labels have no text for these actions yet (`CONTROL_LABELS` in `main.gd`, which the pane work
  owns).
- **Settings:** none.
- **Tested:** `tests/test_features.gd` (five pattern chapters, next, previous within and at a chapter start, the
  last chapter, ticks, the overlay line, the `chapter_prev` action through the controller's `button_pressed`
  signal, normalising an unsorted list). The shipped action map regenerated byte-identical.
- **Also tested** on real files: `tests/test_media_features.gd` reads the chapters of the engine-demux test set
  through `MediaSource`, and opens a VP9 MKV with six chapters through the app (the software decoder on a desktop):
  six chapters listed, next chapter lands on the second's start.
- **Untested:** the d-pad on the device.

## #17 Sleep timer

After the chosen time, the room and the picture dim and the sound fades out over a minute; then playback pauses and
the position is saved for resume. The room and picture stay dim until playback starts again, and the sound level is
back by then.

- **Choices:** 15, 30, 60 or 90 minutes, or "end of file": the fade runs over the file's last minute and it pauses at
  the end. While end-of-file is armed, a `--dir` playlist does not go on to the next file.
- **Cancel:** anything the user does during the fade (play or pause, a seek, another file) undoes the fade; the timer
  stays armed. The timer counts wall-clock time, also while paused. If it runs out while paused, it just disarms.
- **Levels:** room light to 15 % of the user's setting, picture to 25 % (the shader's `brightness`), sound to silence
  (the player's own volume, not the user's volume setting).
- **Room light:** a new shared node, `main.features.room_light` (`scripts/env/room_light.gd`), multiplies the user's
  room light by factors that features set with their own fade (`set_factor(name, value, fade_seconds)`), so the
  sleep timer and #20 never overwrite the user's setting or each other.
- **API:** `main.features.sleep` (`scripts/comfort/sleep_timer.gd`). `start(minutes)`, `start_end_of_file()`,
  `cancel()`, `cycle()` (off, 15, 30, 60, 90, off), `active`, `fading`, `remaining()`, `status_text()` ("sleep in 23
  min"), signals `changed(active, remaining)`, `fade_started`, `slept`.
- **Overlay:** "sleep in 23 min" on the feature status line (`main.features.status_line()`, which also carries the
  chapter).
- **Desktop key** (menu hidden): `Z` cycles. No controller binding; the pane gets the choices.
- **Settings:** `[sleep] fade_seconds` (default 60), `[sleep] last_minutes` (the last choice, for the pane).
- **Tested:** `tests/test_features.gd` with a 1-minute timer and a 0.6 s fade: fading levels, pause, saved position,
  dim until play, back on play, a seek during the fade, cycling, end of file on the looping pattern.
- **Untested:** the headset: how the fade feels, whether 15 % room light is dark enough, and that the pause after
  the fade saves before the user takes the headset off.

## #20 Room light follows playback

The room dims while the film plays, over 2 s, and comes back up over 0.8 s on pause, when nothing plays, or while
the menu is open. It is a factor on the shared room light, so the user's own room light setting is kept and the
sleep timer's dimming adds to it.

- **API:** `main.features.light_follow` (`scripts/env/light_follow.gd`). `enabled`, `play_level`, `set_enabled(on)`,
  `set_play_level(v)`, `wanted()`.
- **Settings:** `[room] follow_playback` (default on), `[room] play_level` (default 0.35 of the user's level).
- **Where it shows:** the dim room and the cinema. The void has no light, and 180 and 360 hide the room.
- **Tested:** `tests/test_features.gd` in the cinema: dims while playing, up on pause and with the menu open, the
  user's room light still applies underneath, off restores it.
- **Untested:** the look in the headset, and whether 0.35 is a good default in the cinema.

## #25 Container metadata first

The mode comes from the container's stereo and spherical metadata before the guess from the file name. The order is
now: `--mode`, a mode remembered for the file, a test pattern's own mode, the container's metadata, then the name.
The name's guess is still the fallback, and it fills in what the metadata leaves out.

- **Keys** read from `get_video_info()`, as the engine fork fills them from FFmpeg's stereo-3D and spherical side
  data (Matroska StereoMode and Projection, MP4 `st3d`/`sv3d`): `stereo_mode` ("sbs", "tb", "2d", "unspecified",
  "frame_sequence", ...), `stereo_inverted`, `stereo_fov`, `projection` ("equirectangular", "half_equirectangular",
  "fisheye", "cubemap", "rectilinear", "parametric_immersive", "other"), `projection_fov` (horizontal and vertical
  degrees: an equirectangular picture 200° or less wide is a 180) and `projection_bounds`. The longer names first
  proposed ("side_by_side", `bound_left`, `stereo_hfov`) are accepted too.
- **Rules:** "2d" alone is ignored, because many muxers write it by default. A projection without a stereo layout
  keeps the name's layout and the frame-shape rule (square 360 is top/bottom, 2:1 180 is side by side). A stereo
  layout without a projection keeps the name's projection. Flat half or full comes from the frame shape. Cubemap,
  equi-angular tiles and frame-sequential 3D are not supported: the name's guess is used and the footer says why.
- **Where it shows:** the overlay's mode line says `[metadata]`, and the menu's Auto text says "(container: 360°,
  mono)".
- **Not applied:** the container's pose (`projection_yaw_pitch_roll`). Which way each angle turns the picture can't
  be checked without footage from a camera that writes it, and a wrong sign would make a level film crooked. The
  horizon trim (#77) is the manual fix meanwhile.
- **Code:** `scripts/play/container_mode.gd` (`from_info(info, file_name, width, height)`), called from
  `_guessed_mode()` in `main.gd`.
- **Tested:** `tests/test_container_mode.gd` (19 cases), `tests/test_features.gd` (a stand-in source with metadata
  through the real open path, and without), `tests/test_video_mode.gd` unchanged.
- **Also tested** on real files: `tests/test_media_features.gd` runs the engine-demux test set (no metadata, SBS
  with chapters, TB inverted, VR180 in MKV and MP4, 360 TB) through `MediaSource` and gets the right mode for each,
  and opens a VP9 MKV with a StereoMode tag through the app: `[metadata]`, half SBS.
- **Untested:** the headset, and files from real cameras.

## #27 Picture controls

Brightness, contrast, saturation, gamma and a dark-scene lift, remembered per environment, because a dark cinema and
the void want different settings.

- **Shader:** `video.gdshader` applies them to the gamma-encoded picture in this order: lift, gamma, contrast around
  mid grey, brightness, saturation (BT.709 luma). At the defaults the whole stage is skipped (`pc_enabled`), so it
  costs nothing unless used. The dark-scene lift raises the shadows most at a third of full scale and leaves black
  and white where they are.
- **Ranges:** brightness −0.3 to 0.3, contrast 0.5 to 1.5, saturation 0 to 2, gamma 0.6 to 1.6, lift 0 to 0.25.
  `RANGES` holds min, max, default and step for the pane's sliders.
- **API:** `main.features.picture` (`scripts/play/picture_controls.gd`). `values`, `set_value(name, v)`, `reset()`,
  `is_default()`, signal `changed(values)`.
- **Settings:** `[picture_<environment id>] brightness, contrast, saturation, gamma, lift`; only values that differ
  from the default are stored.
- **Tested:** `tests/test_features.gd` (per environment, clamping, the stage off at defaults, reset). A WSLg render
  with saturation 0, lift 0.25 and contrast 1.3: grey and lifted, as intended.
- **Untested:** the headset's panels; whether the lift helps dark films on these LCDs without lifting black.

## #28 Language memory

The audio and subtitle languages the user chose are remembered, so multi-language releases open right.

- **On open:** if the file's selected audio track is not in the remembered language and another track is, that
  track is selected. When subtitles are on, the track in the remembered subtitle language is picked, full before
  forced, text before bitmap. Otherwise the default-flagged track, as before.
- **What counts as a choice:** the user picking an audio track (anything calling
  `PlaybackController.select_audio_track`, which now emits `audio_track_selected(index)`) or a subtitle track
  (`select_track`, `set_enabled`, `cycle_track`). The automatic pick on open and features' changes (the catch-up
  replay) are not choices; `Subtitles.by_user` tells them apart. A track without a language changes nothing.
- **Several languages:** the last three choices are kept, newest first, and the first one a file has wins.
- **Forced parts:** with subtitles off, a forced track in the audio's language is shown (the foreign-language parts
  of a film). `[subtitles] forced_auto` turns this off. It is a feature's change: the user's on/off setting stays,
  and the next file starts from it again.
- **Engine helpers:** with the engine's `MediaSource.normalize_language`, `pick_audio_track` and
  `pick_subtitle_track` (fork `6b7f34ddbc`), those decide. Commentary and audio description lose ties; for subtitles
  text beats bitmap, full beats forced, and tracks without hearing-impaired notes come first. On older engines and the
  test patterns the app applies the same rules itself; on the real test files both pick the same track in all 12
  cases tried.
- **Matching:** codes are normalised to ISO 639-1 ("ger", "deu", "German" and "de" are "de"), with a region kept
  ("pt-br"). A preference without a region matches every region; one with a region matches only that region.
- **API:** `main.features.languages` (`scripts/play/language_memory.gd`). `audio_languages`, `subtitle_languages`,
  `audio_language`, `subtitle_language`, `forced_auto`, `set_forced_auto(on)`, `normalize(code)`,
  `pick_audio(tracks)`, `pick_subtitle(tracks, forced_only)`, `same_language(preference, track)`, `forget()`, signal
  `changed(audio, subtitles)`. `VideoSource.get_audio_track()`, `pick_audio_track()` and `pick_subtitle_track()` are
  new.
- **Test patterns** now have two silent audio tracks (English, Japanese) so this can be tested without sound.
- **Settings:** `[language] audio`, `[language] subtitles` (lists; a single code from before is read as a list of
  one), `[subtitles] forced_auto` (default on).
- **Tested:** `tests/test_features.gd` (audio and subtitle picks remembered, applied on the next file, the replay not
  counted, language groups, forced after full). `--ui-test` unchanged (the same 9 SMB failures).
- **Untested:** a real multi-language file through `MediaSource` (the track switch on open re-seeks inside the
  source, before the first frame).

## #31 Curved screen

The flat projections (mono, SBS, TB) can be shown on a section of a vertical cylinder that curves toward the viewer.
The picture's width is the arc length, so the screen width setting means the same thing. A radius equal to the
viewing distance puts every column of the picture at the same distance from the eyes.

- **Amount, not radius** (since 2026-10-31): the Picture tab's "Curvature" is 0 to 100 %. 0 % is flat. 100 % is a
  radius equal to the screen distance (the screen wraps evenly around the viewer). The radius is distance / amount,
  so it is never smaller than the viewing distance. The radius slider (0 to 30 m) let a radius far below the distance
  roll a wide screen into a tube (12 m of arc on a 2.5 m radius is 275°), so it looked as if curvature did not work.
  When the distance changes, the radius follows, so the percentage stays. "Curve to distance" is gone: 100 % is that.
- **Mesh:** `CurvedScreen.build(size, radius)`, 64 columns, the same per-vertex UV as the quad, so the shader and
  every stereo layout work unchanged. `VideoScreen.set_curve_radius(r)` swaps the quad for it (0 = flat).
- **Captured windows** stay flat, because the pointer maps onto the plane.
- **API:** `main.features.curve` (`scripts/play/curved_screen.gd`). `amount`, `set_amount(a)` (0..1; below 1 %
  flat), `radius`, `set_radius(r)` (converted to an amount, at most 1), `match_distance()` (amount 1), static
  `radius_for(distance, amount)` and `amount_for(distance, radius)`, signal `changed(radius)`.
- **Settings:** `[screen_<environment id>] curve_radius` (absent = flat). The radius is stored as before and read
  back as an amount at the environment's distance.
- **Tested:** `tests/test_features.gd` (mesh depth R(1 − cos θ/2), chord narrower than the arc, flat below the
  minimum, per environment, the percentage held when the distance changes, a radius below the distance taken as
  100 %). A WSLg render in the dim room at 2 m: the edges come toward the viewer and the picture faces the right way.
- **Untested:** the headset: whether the curve helps on large screens, and the cinema's masking border, which still
  assumes a flat screen.

## #32 Haptic ticks

A short, light pulse on seek steps, on the d-pad's chapter and replay buttons, and on menu hover, through the action
map's existing `haptic` output. Each kind has its own strength and length; pulses are at least 45 ms apart per
hand, so a held stick or a fast sweep across a list does not buzz.

- **Seek steps** are found without a hook in the core: after every seek, the hand whose stick is past the seek
  threshold gets a tick.
- **Menu hover** needs the pane to call `main.features.haptics.hover(hand)` when the pointer moves onto a new
  target. The pane is being rebuilt by the app-shell agent, which has been asked to add the call.
- **API:** `main.features.haptics` (`scripts/comfort/haptics.gd`). `tick(hand, kind)` with kind "hover", "seek",
  "chapter" or "click", `hover(hand)`, `seek_step(hand)`, `set_enabled(on)`, `set_strength(s)`, `pulses` (a count).
- **Settings:** `[haptics] enabled` (default on), `[haptics] strength` (0 to 1, default 1).
- **Tested:** `tests/test_features.gd` (hover pulses, the rate limit, no pulse on a seek without a stick, the chapter
  button, off). On a desktop the pulse call goes nowhere; only the logic is tested.
- **Untested:** how the pulses feel on the headset's controllers; the strengths are guesses.

## #35 Manual zoom and pan

For odd aspects and burnt-in bars: the picture is magnified about its centre and moved, inside the same screen.
Flat projections only; 180, 360 and fisheye ignore it. Remembered per file, because the bars belong to the file.

- **Shader:** `video.gdshader` uniforms `zoom` and `pan`, applied after the 3D depth shift, so the depth stays
  relative to the screen.
- **Limits:** zoom 1 to 3. The pan is limited to 0.5 − 0.5/zoom on each axis, so the screen never shows past the
  picture's edge.
- **API:** `main.features.zoom` (`scripts/play/zoom_pan.gd`). `zoom`, `pan`, `set_zoom(z)`, `set_pan(p)`,
  `nudge_zoom(step)`, `nudge_pan(delta)`, `reset()`, `pan_limit()`, signal `changed(zoom, pan)`.
- **Desktop keys** (menu hidden): `=` and `-` zoom; numpad 4, 6, 8, 2 pan; numpad 5 resets.
- **Settings:** `[zoom_files] <file key> = [zoom, pan x, pan y]`; absent means none.
- **Tested:** `tests/test_features.gd` (pan limit, shader values, per file, spherical ignored, reset). A WSLg render
  at 1.5x panned right.
- **Untested:** the headset.

## #59 2D from 3D

One eye's picture goes to both views, for eye strain or a damaged eye. It works for every stereo layout and
projection; mono files are unaffected. "Left" is the left eye as the file intends, after any eye swap. The 3D depth
shift is off while it is on. The accessibility pack's monocular setting (#74) is this same switch.

- **Shader:** `video.gdshader` uniform `mono_eye` (−1 off, 0 left, 1 right).
- **API:** `main.features.two_d` (`scripts/play/two_d.gd`). `eye`, `set_eye(e)`, `cycle()`, `describe()`, signal
  `changed(eye)`.
- **Desktop key** (menu hidden): `2` cycles off, left, right.
- **Settings:** `[stereo] mono_eye` (global: it is about the viewer, not the file).
- **Tested:** `tests/test_features.gd`; a WSLg render of the full SBS pattern with the right eye to both: both views
  say RIGHT EYE.
- **Untested:** the headset.

## #77 Horizon correction

Pitch and roll trim for 180, 360 and fisheye files shot off-level. The sphere turns in the picture's own frame,
before the yaw that a grip drag sets. Remembered per file, because the camera was crooked for that recording.

- **Range:** ±20°, steps of 0.5° on the keys. Pitch > 0 tips the picture's front up; roll > 0 turns it clockwise as
  seen.
- **Code:** `VideoScreen.sphere_tilt` (pitch, roll in radians), applied where the sphere is put on the head each
  frame. `main.features.horizon` (`scripts/play/horizon.gd`): `pitch`, `roll`, `set_trim(p, r)`, `nudge(dp, dr)`,
  `reset()`, signal `changed(pitch, roll)`.
- **Desktop keys** (menu hidden): numpad 7 and 9 roll, numpad 1 and 3 pitch, numpad 0 resets.
- **Settings:** `[horizon_files] <file key> = [pitch, roll]`.
- **Tested:** `tests/test_features.gd` (roll and pitch angles of the sphere's basis, clamping, per file). A WSLg
  render of the 360 pattern at 15° roll: the horizon turns clockwise.
- **Untested:** the headset. Large pitch trims leave the 180's edge closer to the view; nothing hides it.

## #79 Edge fade for 3D

Soft screen edges, so things that come out of the screen are not cut by its hard frame (a window violation). The
picture fades to black over the chosen fraction of the screen's width at the left and right edges, and half of it
at the top and bottom. Only for flat stereo pictures; mono and spherical ones keep hard edges, and so does a 3D file
shown as 2D (#59).

- **Shader:** `video.gdshader` uniform `edge_fade` (0 = off), on the mesh's UV, so zoom, pan and the depth shift
  don't move it.
- **API:** `main.features.edge_fade` (`scripts/play/edge_fade.gd`). `width`, `set_width(w)` (0 to 0.1),
  `applies()`, `DEFAULT_ON` (0.03, for the pane's toggle), signal `changed(width)`.
- **Settings:** `[stereo] edge_fade` (global, default off).
- **Tested:** `tests/test_features.gd` (on for flat SBS, off for 2D from 3D, mono and spherical). A WSLg render of
  the SBS pattern at 0.08.
- **Untested:** whether it helps in the headset, and a good default width.

## #61 Subtitle delay per track

Shifts the selected subtitle track's timing, remembered with the file and the track, so a badly timed track stays
fixed next time. Positive: the lines come later.

- **API:** `main.features.sub_delay` (`scripts/play/subtitle_delay.gd`). `delay`, `set_delay(s)` (±30 s),
  `nudge(step)`, `reset()`, signal `changed(delay)`. It sets `Subtitles.delay`, which shifts the time the line is
  looked up at.
- **Desktop keys** (menu hidden): `;` and `'` move it by 0.1 s.
- **Settings:** `[subtitle_delay_files] <file key>_<track index> = seconds`.
- **Negative delays:** lines shown earlier are needed before the demuxer would read them (about 1 s ahead). The app
  sets `MediaSource.subtitle_read_ahead` to the size of a negative delay, so the video is read that much further
  ahead while a track of the file is selected. The engine's queue limits that to about 20 s at 24 fps; beyond it,
  lines come up to the difference late. Subtitle files (#50) need none of this.
- **Tested:** `tests/test_features.gd` (a line at its shifted time, per track, per file, reset);
  `tests/test_media_features.gd` (a −4 s delay sets the source's read-ahead to 4 s, a positive one to 0).
- **Untested:** the headset; a real track through MediaSource with a negative delay.

## #60 Sidecar JSON for the chosen mode

With `[sidecar] write=true`, a mode the user picks for a file is also written next to the file, so the choice travels
with it to another headset, a reinstall or a copy. Writing is off by default. On open, the sidecar is read when the settings remember no mode for the file. The
mode order is now: `--mode`, the settings' remembered mode, the sidecar, a test pattern's own mode, the container's
metadata, the name.

- **File:** `<video file name>.vrmode.json` in the same folder, for example `Holiday.mkv.vrmode.json`, holding
  `{"mode": "flat_sbs_half", "version": 1}`.
- **Local files only.** The share browser has no write call, so files on a share neither read nor write one. A
  folder that can't be written to is skipped with a log line.
- **Auto** in the menu (which forgets the remembered mode) also deletes the sidecar, but only one in this format: a
  file with any other key is left alone.
- **Overlay:** the mode line says `[sidecar]` when it came from one.
- **API:** `main.features.sidecar` (`scripts/play/sidecar.gd`). `read_mode(path)`, `write_mode(path, id)`,
  `remove(path)`, `sidecar_path(path)`, `enabled`, `set_enabled(on)`, signal `written(path)`.
- **Settings:** `[sidecar] write` (default off since 2026-10-31: writing files into the library is the user's call; reading is always on).
- **Tested:** `tests/test_features.gd` (written on a user's pick, read back after the settings forget it, removed by
  Auto, a foreign sidecar kept, never for network paths).
- **Untested:** the headset's SD card and media folders (permissions), and a file manager's view of the extra files.

## #78 Shuffle, repeat, queue editing

The playlist (the folder, or the files the browser passed) as a proper queue. It edits `main.playlist` in place and
keeps `main.playlist_index` on the current file, so next and previous (A / B, N / P) follow it unchanged.

- **Shuffle:** the files after the current one are shuffled; turning it off restores the original order, with files
  added meanwhile at the end. A new folder is shuffled afresh.
- **Repeat:** "off", "one" (the file again) or "all" (back to the first after the last; reshuffled when shuffle is
  on).
- **Continuous:** plays on through the queue at the end of a file. A `--dir` run always does. Off by default, as
  before. An armed end-of-file sleep timer (#17) wins over all of this.
- **Editing:** `play_next(path)`, `append(path)`, `remove(index)` (not the playing file), `move(from, to)`,
  `clear_upcoming()`, `jump(index)`, and `items()` for the pane's list (`path`, `title`, `current`).
- **Core hook:** `main._on_ended` asks `features.queue.on_ended()` first.
- **API:** `main.features.queue` (`scripts/play/play_queue.gd`). `repeat`, `shuffle`, `continuous`,
  `set_repeat(r)`, `cycle_repeat()`, `set_shuffle(on)`, `set_continuous(on)`, signal `changed`.
- **Desktop keys** (menu hidden): `T` cycles repeat, `U` toggles shuffle.
- **Settings:** `[queue] repeat`, `[queue] shuffle`, `[queue] continuous`.
- **Tested:** `tests/test_features.gd` with the test patterns as the playlist (shuffle and restore, play next, move,
  remove, repeat one, not continuous, continuous, repeat all, the sleep timer winning, clear). The end of a file is
  simulated, because the test pattern loops.
- **Untested:** a real file reaching its end on the headset.

## #80 Frame step and A-B loop

- **Frame step:** pauses, then moves one frame back or forward. The engine has no step call, so it is a seek of one
  frame's duration (1/fps from the video info, 24 when unknown). `MediaSource` seeks decode from the keyframe up to
  the target, so the step is exact but can take a moment on long GOPs.
- **A-B loop:** the first mark sets A, the second sets B and starts looping (B before A swaps them; at least 0.5 s), a
  third clears it. Reaching B goes back to A. Another file clears it. The overlay's status line shows "A 1:02:03"
  and then "loop 1:02:03-1:02:10".
- **API:** `main.features.step_loop` (`scripts/play/frame_step_loop.gd`). `step(frames)`, `frame_duration()`,
  `mark()`, `clear()`, `set_loop(a, b)`, `active`, `a`, `b`, `text()`, signal `loop_changed(active, a, b)`.
- **Desktop keys** (menu hidden): comma and period step, slash marks. No controller binding; the pane gets buttons.
- **Settings:** none.
- **Tested:** `tests/test_features.gd` (step forward and back, marks, the overlay text, the jump back at B, clearing,
  the minimum length, another file).
- **Untested:** stepping through a real file on the headset (how long each step takes on a long GOP).

## #76 Favourites and search (data side)

The data for a favourites list and a search box; the pane shows them, with the on-pane keyboard for the query.

- **Favourites:** files or folders the user starred, newest first, each with `path`, `title`, `is_dir` and `added`.
  `favourites()`, `is_favourite(path)`, `add_favourite(path, title, is_dir)`, `remove_favourite(path)`,
  `toggle_favourite(path, is_dir)`, signal `favourites_changed`.
- **Matching:** every word of the query must appear in the name. Case and common accents are ignored, and dots,
  dashes, underscores and brackets count as spaces, so "show s01" finds `Show.S01E02.mkv` and "cafe" finds "Café".
  Names that start with the query rank first, then names with a word that starts with it; favourites rank above
  everything else.
- **search_known(query):** favourites, the watch history (resume, #7) and the queue, without duplicates, each with a
  `source` of "favourite", "history" or "queue".
- **search_folder(root, query):** walks a local folder and its subfolders on a worker thread (at most 6 levels, 2000
  folders, 200 results), video files and folder names only. The answer comes as `folder_results(query, results)`; a
  newer search drops an older one's answer. Shares are not walked: each listing is a network round trip and the
  browser holds the connection. Their known files are still found by `search_known`.
- **API:** `main.features.library` (`scripts/play/favourites_search.gd`), plus static `matches()`, `score()`,
  `normalise()` and `walk()`.
- **Settings:** `[favourites] items` (an array of dictionaries).
- **Tested:** `tests/test_features.gd` (matching, ranking, favourites add/toggle/order, search_known over
  favourites and the queue, a folder search on a worker thread over a small tree, shares answered empty).
- **Untested:** search speed over a large SD card on the headset; the pane's list and keyboard.

## #74 Accessibility pack (settings)

Four settings in one place. Two are applied by the features; two are for the pane to read.

- **UI scale** (1 to 2): the menu's text larger, on the same tablet (the front panel grew instead; it is gone,
  2026-11-06). The layer applies it (`ui_layer.gd` apply_tablet()); it listens to `changed("ui_scale", v)`.
- **Left-handed:** the left controller is the panel's pointer at launch (`ui-design.md`, "Revision 2"). Any
  controller's menu button then picks the pointer. The panel applies it. The direct bindings stay.
- **Monocular:** one eye's picture to both views for every 3D file, through 2D from 3D (#59) with the chosen eye.
  Turning it off turns 2D from 3D off.
- **Subtitles always on:** every file opens with subtitles on (the remembered language's track, else the default),
  whatever the last file's on/off was. Turning them off during a film lasts for that film. This does not change the
  user's own on/off setting, and language memory does not learn from it.
- **API:** `main.features.access` (`scripts/comfort/accessibility.gd`). `get_value(key)`, `set_value(key, value)`,
  signal `changed(key, value)`, keys `ui_scale`, `left_handed`, `monocular`, `monocular_eye`, `subtitles_always`.
- **Settings:** `[accessibility]` with the same keys; defaults are not stored.
- **Tested:** `tests/test_features.gd` (monocular on and off, subtitles always on for the next file without touching
  the user's setting or language memory, the scale clamped and signalled, left-handed stored, defaults not stored).
- **Untested:** the headset. `--ui-test` covers the UI scale and Left-handed in the panel.

## Tests on real files

`tests/test_media_features.gd` opens real files through `MediaSource` on a desktop: the engine-demux agent's metadata
set in WSL (`~/media-tests/features/`) at the `MediaSource` level, and a VP9 MKV made by
`tests/make-feature-media.sh` through the app's own open path, because VP9 goes through the engine's software decoder
and there is no V4L2 decoder off the headset. It covers container metadata (#25), chapters (#15), subtitles from a
real SubRip track and catch-up replay (#11). It skips when the engine or the files are missing. Headless, the audio
driver is a dummy and the audio master clock does not run, so the test moves through the file by seeking.

```
wsl -d Ubuntu -- bash app/tests/make-feature-media.sh
godot --headless --xr-mode off --path app --script res://tests/test_media_features.gd
```

It found one real bug, fixed in `PlaybackController.get_position()`: right after a seek the source reports the frame
from before it until the decoder settles, which ended the catch-up replay at once.

## #50 Subtitle files next to the video

When a file opens, the engine's `MediaBrowser.find_subtitles()` lists the subtitle files that go with it: those
named after the video, all of them in a folder with one video, and those in a Subs folder next to it, local or on a
share. Each is loaded into the `MediaSource` as one more subtitle track (`add_external_subtitle`; SubRip, ASS and
WebVTT, in UTF-8, UTF-16 or Windows-1252). The language, forced and hearing-impaired flags come from the file name
(`Film.en.forced.srt`, `2_English.srt`, `Film.pt-BR.srt`).

- **Threading:** listing and reading both block, so they run on a worker thread; opening another file meanwhile
  drops the late answer. At most 16 files.
- **Picking:** when the files are in, the track list is refreshed. If the user has subtitles on and hasn't chosen a
  track for this file, the pick runs again, so a file in the remembered language (#28) can win. With subtitles off, a
  forced file in the audio's language is shown (forced parts, #28).
- **API:** `main.features.sub_files` (`scripts/play/external_subtitles.gd`). `enabled`, `set_enabled(on)`, `loaded`
  (`path`, `index`, `language`, `forced`, `hearing_impaired`), signal `loaded_changed(loaded)`.
  `VideoSource.supports_external_subtitles()` and `add_external_subtitle()` are new, and
  `Subtitles.refresh_tracks()`.
- **Settings:** `[subtitles] find_files` (default on).
- **Tested:** `tests/test_media_features.gd` through the app on the VP9 test file with a forced German and a French
  file next to it, and German audio: both files load as tracks, the forced German one shows with subtitles off, the
  user's setting stays off, turning subtitles on picks the French full track, and its line shows at its time.
- **Untested:** the headset, and files on a share (a listing and a read per file over Wi-Fi).

## #69 Playback speed, pitch kept

0.5x to 2x. The engine time-stretches the audio (`MediaSource.playback_speed`, a WSOLA stretch in the mixer, fork
`6b7f34ddbc`) and, as the audio is the master clock, the video follows; without audio the frame clock runs at the
speed (`HWVideoTexture.playback_speed`). The test patterns follow too.

- **Clock:** the audio clock's mix-time corrections are real seconds, so `PlaybackController` multiplies them by the
  speed (`PlaybackController.speed`).
- **End time and battery:** "ends 23:20" (#36) and the film end in the battery forecast (#2) count real time at the
  speed (`main.features.remaining_real()`).
- **Kept** from file to file for the session; back to 1x at the next start. Not for a captured window.
- **Overlay:** "speed 1.5x" on the status line when not 1x.
- **API:** `main.features.speed` (`scripts/play/playback_speed.gd`). `speed`, `STEPS` (0.5, 0.75, 1, 1.25, 1.5,
  1.75, 2), `set_speed(s)`, `faster()`, `slower()`, `reset()`, `text()`, signal `changed(speed)`.
  `VideoSource.set_playback_speed()` is new.
- **Desktop keys** (menu hidden): `9` slower, `0` faster.
- **Settings:** none.
- **Tested:** `tests/test_features.gd` (the pattern's clock at 2x within 0.3, status line, end time, steps, limits,
  kept on the next file, reset); `tests/test_media_features.gd` (the speed reaches the MediaSource). The time
  stretch itself is the engine's test (spikes/03-player, PLAYER_FEATURES).
- **Untested:** the headset, and whether the hardware decoder keeps up at 2x on 4K and 8K files.

## #67 Subtitle rendering, and #65 a second subtitle track

Subtitles are now drawn on one quad in the world, below the picture (not on the pane). The quad shows a transparent
SubViewport, which renders again only when the lines change. The quad is hidden between lines.

- **Text with style:** bold, italic, underline, strike-out, colour, outline colour and relative size. The source is
  the engine's parsed ASS lines (the event's `styled` list from the engine's subtitle style parser). For engines
  without it, the app parses the event's `ass` line itself (`\b \i \u \s \c \1c \an \a \r \p`, `\N`, `\h`). Fonts,
  explicit positions, karaoke and transforms are not used. Every line is drawn in the app's font, in the band.
- **Alignment:** left, centre or right comes from the line's ASS alignment. Top-aligned lines (signs) go first in
  the band, not at the top of the frame.
- **Picture subtitles** (PGS, VobSub, DVB): the engine's bitmap events (`images` of `{rect, image}` on a
  `canvas_size`) are drawn in the same band. They keep their size relative to the picture and their positions
  relative to each other. Their place on the frame is not kept. An open-ended event lasts until the next event of
  the same kind (an empty picture event clears it), at most 30 s.
  - On a 3D rip (side by side or top and bottom), the canvas is the whole frame and each eye's half carries its own
    copy of the caption. Only the first half's images are drawn, on that half, stretched back to the eye's aspect
    for half-width or half-height rips (`eye_images()`). The caption's depth is the band's own depth setting, not
    the rip's.
- **Place and size:**
  - Flat: the band is the picture's width. The text is 5 % of the picture's height times the size setting.
  - "Below" (default): the band's top edge is just under the picture, and the band grows down.
  - "Inside": the band sits in the bottom of the picture and grows up.
  - Offset moves the band up or down, in picture heights.
  - 180, 360 and fisheye: the band is 2.5 m ahead and grows up from 0.45 m below eye level. It is about 48° wide.
  - Depth: the quad moves toward the eyes by that many metres and shrinks with the distance. It looks the same size
    in the same place but sits in front of what comes out of a 3D picture.
  - Canvas pixels follow the band's angular width: 30 per degree, 512 to 2048.
  - Background: an optional dark box behind each line.
- **Second track (#65):** shown above the main track, at 85 % size and pale yellow, while subtitles are on.
  - A subtitle file next to the video (#50) is read by the app itself (`scripts/play/subtitle_file.gd`: SubRip,
    WebVTT and ASS/SSA; UTF-8, UTF-16 with a BOM, or Windows-1252), on a worker thread. The app waits for that thread
    when it finishes and at exit. An unwaited task crashed `test_features` at exit now and then; dev-plumbing found it.
  - A text track inside the file is read by the engine alongside the main one
    (`MediaSource.select_secondary_subtitle_track`, engine PLAYER_REQUESTS). Each event carries `track`, so the app
    puts the second track's lines in their own list. Like a track change, choosing one doesn't seek: its lines start
    from where the demuxer is reading, and earlier ones come after a seek back. Bitmap tracks can't be the second.
  - The second track's language is remembered. A later file with a subtitle file in that language opens with it.
- **API:**
  - `main.features.subtitles`: `secondary`, `secondary_tracks()`, `select_secondary(index)`, `cycle_secondary()`,
    `events_at(t)`, `add_event(start, end, text, event)`, signal `secondary_changed(index)`.
  - `main.features.subtitles.display` (`scripts/play/subtitle_renderer.gd`): `set_scale_factor()`,
    `set_position_mode("below" | "inside")`, `set_offset()`, `set_depth()`, `set_background()`, the matching
    properties, `is_showing()`, `get_canvas_size()` and `get_band_size()`. `scale_factor` and `set_scale_factor()`
    are unchanged, so the pane's size slider still works.
  - `scripts/play/subtitle_style.gd`: `from_event(event)` and `to_bbcode(lines, font_px)`.
- **Desktop keys** (menu hidden): `S` cycles the main track; `Shift+S` cycles the second track.
- **Settings:** `[subtitles] size` (0.5 to 3), `position` (below, inside), `offset` (-0.5 to 0.5), `depth` (metres,
  0 to 2), `background` (0 to 1), `secondary_language`.
- **Tested:**
  - `tests/test_subtitle_style.gd`: ASS tags, the engine's styled lines, SubRip, WebVTT and ASS files, and the three
    text encodings.
  - `tests/test_features.gd` on the test pattern: below and inside, offset, size, depth (same direction and angular
    size), background, styled lines in order, a picture line at the picture's scale, an open-ended picture ended by
    an empty one, a second track from a file, and the 360 placement.
  - `tests/test_media_features.gd` on the VP9 test file: the German file's line drawn with the French one.
  - `tests/test_pane.gd` still passes.
  - WSLg renders of the flat pattern below and inside, with a background, and of 360.
  - `tests/test_dual_subs.gd`, 8 checks, on `animated_subs.mkv` (SubRip and ASS tracks, both English): the ASS track
    is offered as the second, the engine reads it, its lines go to the second list by `track` ("ASS 0" with "Cue 0"
    at 10 s), both are on screen, turning it off goes back to one track, and taking its index as the main track
    clears it. `test_features` ran three times without the exit crash.
- **Untested:**
  - The headset: legibility, the pixel density, and depth in a 3D film.
  - Real PGS, VobSub and DVB tracks. The event shape is the one in engine-demux's uncommitted work, and the test
    used a made-up picture.
  - Real ASS files with many styles through the engine's parser. The app's own parse is tested.
  - A curved screen (the band stays flat), files on a share for the second track, and 1000+ line files.

## #85 HDR tone mapping, and the colour matrix

The shader used to treat every file as BT.709 SDR, so HDR10 films looked grey and flat. It now follows the file's
colour description from `get_video_info()` and tone maps HDR to the display.

- **Matrix:** BT.709, BT.601 or BT.2020, from `color_matrix`. When the file doesn't say, BT.601 is used up to 576
  lines, BT.2020 for HDR, and BT.709 otherwise. The range (`full_range`) now comes from the file too.
- **Transfer:** PQ (`smpte2084`, HDR10) and HLG (`arib-std-b67`) are decoded to light. HLG uses a 1000 nit
  reference display with system gamma 1.2.
- **Primaries:** BT.2020 is converted to BT.709 in linear light. Colours outside BT.709 clip.
- **Tone map, engine curve:** when the engine has `MediaSource.get_tone_mapping()` (fork 015fc1857b), HDR files use
  its BT.2390 EETF. The shader's `eetf()` works in PQ on the brightest channel, with the engine's source range,
  knee and target. Display white is the target brightness (default 203 nits, reference white), lowered by the
  exposure: +1 stop halves it, so everything is brighter. The three channels scale together, so hue is kept.
- **Tone map, fallback:** on engines without the helper, linear light with reference white (203 nits) at 1.0, times
  the exposure and 203 / target. Above the knee, an extended Reinhard curve takes the content's peak to display
  white. The slope is 1 at the knee and the curve is monotonic. The knee applies to this curve only.
- **Content peak:** the file's MaxCLL (`max_cll`), capped by its mastering display's peak
  (`mastering_display_luminance`, the engine's key, or `mastering_max_luminance`). Without either, 1000 nits. With
  the engine curve, the engine picks the peak the same way.
- **Dolby Vision profile 5** (no HDR10 base: the planes are Dolby's IPT-PQ-c2 signal, and such a file usually declares
  no colour at all, so it showed as BT.709 SDR with a purple and green cast): `describe()` sees the profile and the
  shader (`dovi`) turns I'P'T' into PQ-encoded LMS with the RPU's matrix, decodes PQ, goes to linear BT.2020 with a
  matrix fitted against the HDR10 base of the same master (a profile 8 encode of the same film, aligned to the frame:
  median error 0.8 % over 5445 block means, where the published IPT and BT.2100 LMS matrices were 5 % out) and tone
  maps as HDR10. The RPU's reshaping curves are not read: the files seen carry the limited-to-full range expansion
  only, which the range step does. Profiles 7 and 8 keep their HDR10 base, as before.
  The status line says "DV profile 5 (IPT, as PQ)". The write-up, the fit and what the RPU still holds:
  `docs/dolby-vision.md`; the tools in `tools/dovi/`.
- **Per environment:** exposure (stops), knee and target brightness (100 to 400 nits), like the picture controls.
- **Cost:** SDR BT.709 files take the same path as before, except for one uniform branch. HDR adds a few `pow` and
  `exp` per pixel.
- **Overlay:** "HDR10" or "HLG" on the status line.
- **API:** `main.features.hdr` (`scripts/play/hdr_tone_map.gd`):
  - `describe(info)` (static): matrix, transfer, primaries, range, peak and where the peak came from.
  - `current`, `is_hdr()`, `text()`, `enabled`, `set_enabled(on)`.
  - `values`, `RANGES`, `set_value("exposure" | "knee" | "target_nits", v)`, `reset()`, signal `changed(values)`.
  - `uses_engine_curve()`: true when the BT.2390 curve is in use. Hide the knee then. Also `engine_params` and
    `display_white_nits()`.
  - Shader uniforms: `yuv_matrix`, `transfer`, `primaries_bt2020`, `tm_enabled`, `tm_peak`, `tm_exposure`, `tm_knee`,
    and for the engine curve `tm_curve`, `tm_src_min_pq`, `tm_src_max_pq`, `tm_max_lum`, `tm_knee_start`,
    `tm_target_nits`.
- **Settings:** `[hdr] tone_map` (default on; off clips the highlights, for comparison).
  `[tonemap_<environment id>] exposure` (-2 to 2 stops, default 0), `knee` (0.5 to 0.95, default 0.75) and
  `target_nits` (100 to 400, default 203).
- **Tested:**
  - `tests/test_hdr.gd`: describe() rules. The real shader, drawn into a viewport with WSLg: the 709, 601 and 2020
    matrices, PQ reference white tone mapped, and clipped with tone mapping off. Also PQ 1000 nits reaching white,
    100 nits unchanged below the knee, exposure, HLG reference white matching PQ's, and grey staying neutral.
  - The HDR10 film on G: (1080p HEVC 10-bit, PQ, BT.2020) in software decode with WSLg, at three times, tone mapping
    on, off and +1 stop. Colours look natural, no longer grey.
  - `tests/test_features.gd`, `tests/test_media_features.gd` and `tests/test_pane.gd` still pass.
  - Engine curve (38 checks in `test_hdr` now): the engine's keys (`hdr_transfer`, `mastering_display_luminance`),
    the node choosing the engine curve with MaxCLL 482 as the peak, and the target and exposure moving display
    white. Six PQ greys through the shader's BT.2390 path match the engine's CPU reference (`tone_map_color()`)
    within 0.012. The HDR10 film renders natural on it (its MaxCLL is 668 nits).
- **Untested:**
  - The headset: its panel's white level, whether 203 nits as reference white suits it, and the cost per pixel at
    the headset's resolution.
  - An HLG file (none on hand).
  - The hardware P010 path (10-bit planes in the shader; the desktop's software path gives 8-bit planes).
  - Dolby Vision's own layer: profiles 7 and 8 show their HDR10 base, the RPU ignored. A profile 5 file whose RPU
    carries real reshaping curves (not only the range expansion) would need the RPU read per frame on the hardware
    path; the one on hand doesn't.

## #22 Still pictures, photo spheres and a slideshow

JPEG, PNG and WebP pictures open like videos. They show on the same screen, meshes and projections, through the
shader's RGB path (the one a captured window uses). Folders and the playlist now hold pictures as well as videos.

- **Source:** `scripts/play/image_source.gd`, kind "image", chosen by the factory for jpg, jpeg, png, webp, jps and
  mpo. The picture decodes on a worker thread. The screen shows once it is ready.
- **The mode** comes from what the file says, like a video container's metadata, else from the file-name guess:
  - Photo spheres: XMP `GPano:ProjectionType` equirectangular gives 360, or 180 when the picture covers 200° or
    less. A partial panorama is padded with black to its place in the sphere.
  - VR180 photos: the right eye's JPEG in XMP `GImage:Data` (extended XMP) gives the two eyes side by side, 180.
  - `.jps` gives side by side with the right eye first. `.mpo` gives its first two images side by side.
  - EXIF orientation turns phone photos upright.
  - A plain 2:1 picture is flat unless its name says 360 or 180. The guess is the same as for video.
- **Sizes:** flat pictures are scaled to 2560 on the long side, because the shader samples without mipmaps.
  Spheres and stereo pairs are scaled to 8192 wide.
- **Slideshow:** `main.features.slideshow` (`scripts/play/slideshow.gd`).
  - With it on, each picture shows for `seconds`, then the queue moves on. Shuffle and repeat (#78) apply, and
    pause holds the picture.
  - A picture of the same shape as the last crossfades from it. A SubViewport mixes the two, then the plain texture
    takes over. Pictures of a different shape cut.
  - With it off, a picture stays until next or previous.
  - API: `enabled`, `seconds`, `crossfade`, `set_enabled()`, `set_seconds()`, `set_crossfade()`, `is_picture()`,
    signal `changed`.
- **Helpers:** `scripts/play/image_meta.gd` (EXIF, XMP in JPEG, PNG and WebP, GPano, GImage, MPF).
  `VideoSourceFactory.is_image_file()` and `is_media_file()` are new.
- **Hooks:** the factory, `list_videos()` (pictures included), `HWVideoSource.opens_async()` (pictures don't go to
  MediaSource), `main._on_opened()` (the screen waits for the picture) and `PlayQueue.on_ended()` (a picture that
  ends moves on).
- **Browser rows:** the data side is ready (`is_media_file()`). The Files tab still lists videos only; its rows
  belong to app-shell.
- **Settings:** `[images] slideshow` (default off), `seconds` (2 to 60, default 8), `crossfade` (0 to 3 s, default 1).
- **Tested:**
  - `tests/test_images.gd`: decode of PNG, a broken file, EXIF orientation 6, a partial 180 sphere padded and
    picked as 180, a 360 with missing poles, JPS, an MPO built here, a VR180 photo with the right eye in extended
    XMP, XMP in PNG and WebP, and the size limits.
  - The real scene: a folder of three pictures, the RGB path, slideshow off then on, the crossfade and its end,
    pause, and a video afterwards.
  - WSLg renders of a JPEG and a WebP from G:.
  - `tests/test_features.gd`, `tests/test_pane.gd`, `tests/test_media_features.gd` and `tests/test_director.gd` still
    pass.
- **Untested:**
  - The headset, and real camera files: no MPO, VR180 or GPano photo was on hand. They were built from the formats'
    descriptions.
  - Pictures on a share: these need `MediaBrowser.read_file()` in the engine. Until then they show the stand-in
    pattern with the reason.
  - Very large pictures on the device: decode time and memory for 8192 x 4096.

## #71 Passthrough room

The real room around the screen. "Passthrough" in the room list (`environments/passthrough.tscn`) turns on the
OpenXR ALPHA_BLEND blend mode. The app clears to transparent, and the runtime shows its camera view behind everything
the app draws. The built-in cameras give a monochrome view. With the colour camera add-on plugged in, the same view is
in colour, with no change in the app (`research-cameras-and-splats.md`).

- **Dimming:** the room light dims the camera view. A black shell around the viewer has opacity 1 minus the light, so
  lights-down during playback (#20) and the sleep timer dim the real room as they dim the other rooms.
- **Leaving the room** puts back the opaque blend mode, the viewport's transparency and the background.
- **Without XR,** or when the runtime offers no ALPHA_BLEND, it is a black room and says so once in the log.
- **Tested on the device (2026-10-31):** the runtime lists `opaque, alpha_blend`, and the user saw the camera view
  behind the screen. Switching to the cinema and back turns it off and on. The look of the dimming is not checked yet.
- The `--passthrough` spike flag (`xr-spikes.md`) does the same without the room list.

### Windows to the real room

A real place (the coffee table, the arm of the sofa) marked once and shown by the headset's cameras in every room
(`scripts/play/real_windows.gd`, `shaders/real_window.gdshader`; the Mixed reality tab, `ui/mixed_reality_tab.gd`;
the user, 2026-11-06). While making or changing one, the whole view is the cameras' and the box shows tinted.

- **Sweep:** the trigger held sweeps the controller's tip over the place; letting go keeps an upright box round it,
  4 cm round, turned to the least floor area within 45 degrees of the way the viewer faced (`fit_yaw`; ties go to the
  facing turn, so a table in front stays square). A monitor at 45 degrees first gave a box across it with the
  monitor diagonal inside.
- **Edit, a face at a time** (the user, 2026-11-06: one way to move and size instead of two, and a turn): the chosen
  face shows as a bright slab and the stick moves it along its own axis the way the stick is pushed as the viewer
  sees it (`_push`: up for a face up or away, right for a face on the right), squared for fine control, 25 cm a
  second at full stick, the opposite face kept (`move_face`). The trigger steps through the faces nearest-first and
  then Turn (45 degrees a second). Menu keeps, B puts back. Each area a row in the tab: On, Edit, Delete (with
  Undo); All on, All off. No outlines while the menu is open: an area is seen by turning it on. (Touch corners and
  Mark again were tried and dropped: the fitted sweep and Edit cover them.)
- **The steps' instructions** are on a card over the pointer controller (`ui/hand_hint.gd`, from `hint()`), turned to
  the head, for as long as the mode lasts: notices placed once where the head looked faded while the viewer looked
  down at the table.

- **Fixed to the real room:** kept in the runtime's tracking space (the Stage reference space, from the headset's room
  setup), placed each frame by XROrigin3D times XRServer's reference frame. Recentring the screen leaves the windows
  on the table; they are there next session (`user://real_windows.json`). A new room setup moves them: sweep again.
- **Showing the cameras:** while a window is on, the ALPHA_BLEND blend mode with the viewport's alpha kept (as the
  passthrough room) and a black backstop far out so nothing else lets the cameras through. Each window draws
  back faces with no depth test and multiply blending: colour times 1 - reveal, alpha times 1 - reveal x light. So it
  shows through whatever the room has in front. With none on, opaque again (no camera cost).
- **Draw order:** windows at render priority 2, after the room's see-through effects (0 and 1): the cinema's
  projector beam, drawn after a window, put its alpha back and the top of a window by the screen went black while the
  film played. Before the tablet (moved up to 4..7), the watch card (4), subtitles and toasts (10) and the panel
  (11, 12), which still draw over a window.
- **Light:** the room light dims the cameras' view as in the passthrough room, never under `[real_room] light_min`
  (70 %; the tab's Passthrough dimming): a window is for finding the cup in the dark.
- **While marking** the film layer steps aside (the screen's mesh draws the film, wiped to the cameras' view too).
- A window over the screen shows the film, not the cameras: the film layer is between them.
- Each area: On (off: not drawn, and with none on the cameras stop) and Delete, with Undo. At most 16.

## #52 More environments, #18 photo rooms, #53 glTF rooms

Four more built-in rooms, any 360 photo as a room, and rooms from glTF files at runtime. They all follow the
environments' screen-anchor convention (`environments/vr_environment.gd`, `app/docs/rooms.md`).

- **New rooms (#52),** built from primitives in code like the cinema (`scripts/env/primitive_room.gd` is the shared
  base). All are unlit, with stars and lamps as constant colours:
  - Home theatre: a sofa in a dark room, the screen on the front wall, towers either side, acoustic panels, and
    downlights that dim with the room. It has a wooden floor for the floor reflection.
  - Drive-in: you sit in a car at night. The big screen is on a frame across the lot, with rows of cars, speaker
    posts, a projection booth behind, lamps, a dusk band and stars.
  - Planetarium: a dark dome full of stars over a skyline silhouette, with a cove light and reclined seats. The
    projector is behind you, and the screen is high on the dome.
  - Dome: a geodesic frame of struts (an icosahedron subdivided once) on a plain at dusk, with a warm horizon.
- **The cinema, rebuilt (2026-11-04):** the flagship room, lit for real and ready for a lightmap bake
  (`environments/cinema.gd`; the house form of the library materials, `docs/materials.md`).
  - A stadium hall 19.2 x 20.7 m, 12 m from the pit to the ceiling: 11 carpeted tiers that curve gently toward the
    screen, side aisles with two steps a row and a light on every step's nose, a pit and a stage with a lit edge,
    pleated curtains and a valance, fabric wall panels with wooden rails, sconces between them, acoustic clouds
    with ceiling cans, brass handrails, four exits with doors and lit signs, and the projection booth's windows in
    the rear wall.
  - 297 modelled seats in one MultiMesh (velvet cushion and curved, tilted back, arm rests and standards shared with
    the neighbour, a pedestal; 564 vertices; a slightly different velvet per seat). The viewer's row and seat stay
    where they were; every seat back in front stays under the sight line to the default screen. The seat you sit in
    is folded away, also after a seat change.
  - Light: no live lights. A warm fill, the screen's spill and lamps standing in for the sconces, all in the
    surface shader, follow the room light (dim while the film plays). The room's real lights (sconces, house lights,
    step lights, exit signs: 26) are there, hidden, for a lightmap bake; with a lightmap the stand-ins step back. The
    beam from the booth to the screen shows while the film plays (the dust motes it had went: they spoilt the
    picture).
  - Budget: 20 draw calls (one per mesh surface), 172 000 vertices (the seats 167 000).
  - Tested: `tests/test_cinema.gd` (50 checks, lavapipe); renders of the seat, the aisle, the stage and the hall from
    above, playing and with the lights up.
  - On the headset (2026-11-04, SteamOS 0.5.7): shown with a 4K film playing, judged "looks great". The house
    lights keep a floor of 4 % of the designed level, so the room never goes fully out while the film plays
    (the "dimmed to" setting can be 0).
- **Rooms light themselves (2026-11-04):** a room built for a lightmap (the cinema: `static_meshes()`,
  `bake_lights()`, `set_baking()`) is baked on the headset the first time it is shown, behind a notice, and the
  bake is kept under `user://lightmaps/<room>/` with a stamp of what went in; a changed room bakes again, else
  every later start loads it (`scripts/env/room_lightmaps.gd` over `scripts/env/room_bake.gd`; the engine fork's
  `LightmapGI.bake()`, `docs/BUILD.md` PLAYER_BAKE). No PC step. The cinema takes 3.0 s on the Frame, during which
  no frames are drawn. `[env] lightmaps` turns it off. Seats are a MultiMesh and keep the shader's light.
  - Tested: `tests/test_room_lightmaps.gd` (headless: which rooms, the setting; lavapipe: the first showing bakes,
    the second loads, `bake_now()`), `tests/test_bake.gd`.
- **Photo rooms (#18):** every picture in `user://skyboxes` is in the list as "<name> (photo)"
  (`scripts/env/skybox_room.gd`, `shaders/sky_photo.gdshader`).
  - The photo surrounds the viewer, centred ahead, with its horizon at eye level. It decodes on a worker thread
    through the image source (EXIF, photo-sphere padding, size limit).
  - A stereo panorama uses its left eye. A narrower picture is centred on black.
  - Its brightness follows the room light setting, and lights-down during playback (#20) applies.
  - `EnvLibrary.add_skybox(path)` copies a picture in, for "use this photo as the room".
- **glTF rooms (#53):** every `.glb` or `.gltf` in `user://rooms` (`scripts/env/gltf_room.gd`). It is read with
  `GLTFDocument` when chosen.
  - A node named ScreenAnchor places the screen. Its X scale is the width.
  - An optional `<name>.json` sets the name, light levels, width and reflection floor.
  - Materials become unlit (`shaders/env_unlit_tex.gdshader`: base colour and texture, lit by the room's level and
    the screen's spill, with emission added). Lights and cameras are removed.
  - A file that fails shows the void. The convention for room makers is in `app/docs/rooms.md`.
- **List and hooks:** `scripts/env/env_library.gd` lists these after main's three, with aliases for `--env=`
  (home, drivein, planetarium, dome). It builds any entry. `main.all_environments()` and `main.set_environment()`
  call it (two lines).
- **Settings:** the usual ones per environment (`[env_<id>] light`, `[screen_<id>]`). Photo rooms use ids
  `sky:<file>`, and glTF rooms `room:<file>`.
- **Tested:**
  - `tests/test_rooms.gd`: the library lists everything, and the geodesic frame has 120 edges. A glTF room exported
    by Godot and read back has its anchor, width from the X scale, sidecar JSON, unlit materials and emission.
    A missing file gives a reason, a 1:1 photo is centred on 2:1, and main switches to each new room with the
    screen from its anchor. The photo appears, the aliases work, and add_skybox works.
  - WSLg renders of every room with the flat pattern. The photo room was rendered with the screen hidden: the
    photo's centre is ahead, and its right side is on the right.
- **Untested:**
  - The headset: scale, comfort and frame time of each room. The drive-in, planetarium and dome have up to about
    1000 instances in MultiMeshes.
  - glTF rooms made in Blender (the test file came from Godot's own exporter), and large rooms.
  - Big photos on the device (decode time).

## #62 Floor reflection

The screen shows on the floor in front of it, like a glossy floor, fading away from the screen's foot.

- **How:** one quad lies on the floor between you and the screen (`scripts/env/floor_reflection.gd`). Its shader
  (`shaders/video_reflection.gdshader`) traces a line from the eye mirrored under the floor through each floor point
  to the screen's plane, and shows that part of the picture. This is the true mirror image, per eye, so it has the
  right depth in 3D. It is blended over the floor and depth-tested, so furniture in front hides it. It fades over the
  lower half of the picture's height.
- **Shared shader:** the picture's sampling and colour (every uniform, `video_pixel()`) moved from `video.gdshader`
  into `shaders/video_common.gdshaderinc`, which both shaders include. The screen's output is unchanged: before and
  after screenshots of a stereo and a 360 pattern differ only in the pattern's moving parts. The reflection copies
  the screen material's uniforms each frame while it shows.
- **Where:** flat screens only, in rooms with a floor for it: an environment's `reflection_floor_y` (the home theatre,
  and glTF rooms through their JSON) and the void (floor at 0). It is on by default where the room has a floor for
  it, but off in the void.
- **API:** `main.features.reflection`: `enabled`, `available()`, `strength`, `set_enabled(on)` (this environment),
  `set_strength(v)`, `is_showing()`, signal `changed`.
- **Settings:** `[env_<id>] reflection`, `[reflection] strength` (0 to 0.6, default 0.25).
- **Tested:**
  - `tests/test_rooms.gd`: on in the home theatre, the uniforms reach it, and the quad lies on the floor between
    viewer and screen. Unavailable in the drive-in, off by default then on in the void, and hidden in 360.
  - `tests/test_hdr.gd`'s shader checks still pass through the include.
  - WSLg renders in the void (a clean mirror image fading out) and the home theatre (the cabinet hides the part
    nearest the screen).
- **Untested:** the headset: the stereo depth of the reflection, and its cost per frame. A second pass of the video
  shader runs over the floor quad's pixels.

## #12 Lying down, #33 head-follow screen, #55 screen size in degrees, #19 seat choice

Four ways to fit the screen to how you sit or lie. All four are built and tested on the desktop. None has been tried
in the headset.

- **Lying down (#12):** one action (`Y` on a keyboard).
  - The flat screen goes up to where your head points, as far as the ceiling.
  - It then follows your head's pitch slowly: it waits for an 8° move and takes a few seconds, so you can settle on
    the pillow. It never follows roll: the picture stays level with the room.
  - 180, 360 and fisheye pictures turn up the same way, through the horizon feature's new session-only
    `extra_pitch`.
  - Turned off, the screen goes back to its usual place.
  - Subtitles and the overlay go with the screen. The floor reflection hides while the screen is tipped up.
  - For the session only, not saved.
- **Head follow and pin (#33):** `F` toggles them.
  - Unpinned, the flat screen follows your head's yaw and pitch lazily, after a 15° move, so it stays ahead.
  - Pinned, the usual state, it stays where it is in the room. Pinning keeps the place it followed to, and that
    becomes the screen's place in this room.
  - 180 and 360 pictures don't follow.
- **Both use one hook:** `main.screen_pose_override` (a Callable). `main._place_screen()` passes it the pose it
  computed and uses the one it returns. The subtitle renderer and the reflection now follow a screen that moves by
  itself: they check its transform each frame.
- **Screen size in degrees (#55):** `set_angle(deg)` keeps the distance and sets the width. Presets set both:
  - Large format: 70° at 14 m.
  - Living room: 32° at 3.2 m.
  - In bed: 42° at 2.4 m, with lying down on.
  - `matching_preset()` says which one applies now.
- **Seat choice (#19):** an environment that has seats lists them with `get_seats()` (the floor point under a seated
  viewer's eyes).
  - Choosing a seat moves the room so the seat comes to you, and puts the screen at the room's anchor as seen from
    there: distance, height and direction.
  - `choose_seat_at(point)` picks the seat nearest a point you pointed at, within 1.5 m, for the laser.
  - The choice is remembered per environment.
  - Rooms with seats: the cinema (every seat; an additive `get_seats()` in `environments/cinema.gd`), the home
    theatre (three places on the sofa), the planetarium (every seat) and the dome (spots on the platform). The
    floor reflection moves with the room.
- **API:**
  - `main.features.pose` (`scripts/comfort/screen_pose.gd`): `lying`, `set_lying()`, `toggle_lying()`, `follow`,
    `set_follow()`, `toggle_pin()`, `yaw`, `pitch`, `is_active()`, signal `changed`.
  - `main.features.angle` (`scripts/comfort/screen_angle.gd`): `angle()`, `set_angle()`, `PRESETS`,
    `apply_preset(id)`, `preset_ids()`, `matching_preset()`, `width_for()`, signal `changed(angle)`.
  - `main.features.seat` (`scripts/comfort/seat_choice.gd`): `seats()`, `seat`, `choose_seat(i)`,
    `choose_seat_at(point)`, `next_seat(step)`, signal `changed(seat)`.
  - Seat choice has no keyboard key, because none is free. The pane or the laser calls it.
- **Settings:** `[comfort] head_follow`, `[seats] <environment id>`. Lying down is not saved.
- **Tested:** `tests/test_comfort.gd` with the desktop camera turned by the test:
  - Lying down: up to the head's 70°, facing the viewer, roll level. A 15° head move followed slowly and then
    reached, no move inside the dead zone, subtitles going up with the screen, 360 turning up, and back on off.
  - Head follow: a 10° glance ignored, a 60° turn followed, and pinning keeping the place.
  - The angle and the three presets, with lying down on in bed and off again.
  - Seats in the cinema: the back row further away, the screen at the anchor, a side seat turned toward the middle,
    pointing at a seat and at nothing, and back to the own spot. Three places in the home theatre, none in the void.
  - `tests/test_features.gd`, `tests/test_rooms.gd`, `tests/test_images.gd` and `tests/test_pane.gd` still pass.
- **Untested, all in the headset:**
  - Whether the follow speeds and dead zones feel right.
  - Lying down with a real head on a pillow, and with the XR camera's own pitch.
  - Pointing at seats with the laser (the pane or the laser still has to call `choose_seat_at`).
  - The presets' sizes for comfort.

## #34 Up next, #37 pre-show, #39 intermission, #63 jog wheel, #66 stereo screenshots

Five small touches around playback. Their cards share one helper: `scripts/play/screen_card.gd` is a dark panel with
a title and a line, kept at a constant angular size, in the pane's fonts and colours. It sits under the screen's
right half, or in front of its centre (1.8 times larger), and low ahead in 180 and 360.

- **Up next (#34):** when a file ends and the queue goes on by itself (continuous play or repeat all, #78), a card
  under the screen says "Up next: <name>" and "Playing in 8 s", and then the next file opens.
  - Play now: the next button or `N` as usual, or `play_now()`.
  - Cancel: `cancel()`, `Esc`, pressing play (the film starts over), a seek, or opening something else.
  - A `--dir` run (tours, kiosk) and the picture slideshow go on at once as before.
  - `PlayQueue.on_ended()` asks `up_next.begin(path, go)` first.
  - With the gapless playlist (#44), the card shows during the film's last 10 s instead, and the next file runs
    straight on at the end. See [#44](#44-gapless-playlist).
- **Pre-show (#37):** in rooms with curtains, a film that opens at its start sits behind closed curtains.
  - When playback starts (autoplay included), they part over 4 s with a slow start and stop, while room light
    follow (#20) dims the lights. At the end of the film they close over 3 s.
  - A resumed film (#7) doesn't start behind them. With #20 off, the pre-show dims the room itself.
  - The curtains are two heavy panels just in front of the flat screen, lit by its spill.
  - Rooms with curtains: the cinema, the home theatre, and any environment with `has_curtains`. Not in 180 or 360.
- **Intermission (#39):** off by default.
  - A film longer than the minimum (100 min) stops once, at the chapter start nearest its middle (35 to 65 % of the
    way). The curtains close, the lights come up because playback is paused, and a plain card says "Intermission"
    and "The film continues in 9:57".
  - Then the curtains open and the film goes on. Pressing play, or `resume_now()`, ends it early.
  - A seek across the point doesn't trigger it, and it happens once per showing. No logos and no music.
- **Jog wheel (#63):** circle a thumbstick round its rim to scrub: clockwise forward, 60 s per turn. A light haptic
  tick comes every 15°, and a card shows the time. Let go to stop: it seeks there.
  - It shares the stick with the flick-seek and the distance push. At the rim it waits up to 150 ms. If the stick
    sweeps 25° in that time it is a jog, and it keeps the stick until released. Otherwise main gets the stick as
    before.
  - A quick flick that springs back within the wait still seeks 10 s: the jog does it.
  - One line in `main._update_sticks()` asks the jog first, after the pane. The haptics' per-seek tick skips a hand
    that is jogging.
- **Stereo screenshots (#66):** `capture()` saves the frame now in the video's own layout, at the picture's
  resolution, to `user://screenshots/`.
  - The layout is side by side or top and bottom for 3D, one picture for 2D, or the 180, 360 or fisheye frame
    itself. Each eye is drawn through the video shader in an offscreen viewport with the screen's colour settings,
    without depth shift, zoom, edge fade or dimming.
  - The file name carries the mode (for example `Film_1h02m05s_sbs.jpg` or `_360_tb`), so the picture viewer (#22)
    opens it the same way.
  - No key (none free): the pane or the listener.
- **API:**
  - `main.features.up_next`: `enabled`, `seconds`, `active`, `remaining`, `next_path`, `play_now()`, `cancel()`,
    signal `changed`.
  - `main.features.preshow`: `enabled`, `openness`, `available()`, `open_curtains()`, `close_curtains()`, signal
    `changed`.
  - `main.features.intermission`: `enabled`, `minutes`, `min_film_minutes`, `point()`, `active`, `remaining`,
    `begin()`, `resume_now()`, signal `changed`.
  - `main.features.jog`: `enabled`, `seconds_per_turn`, `on_stick()`, `jogging(hand)`, `target`, signal `changed`.
  - `main.features.screenshot`: `capture()` (await), signal `saved(path)`.
- **Settings:** `[up_next] enabled, seconds`; `[preshow] enabled`; `[intermission] enabled, minutes,
  min_film_minutes`; `[jog] enabled, seconds_per_turn`.
- **Tested:** `tests/test_delight.gd`. The test patterns loop rather than end, so the test emits the player's end
  of file, as a real file gives it.
  - Curtains closed at the start, open after 4.5 s, closing at the end.
  - The countdown, its card and the next file opening, a seek cancelling, and a `--dir` run going on at once.
  - The intermission point, the stop with curtains closing and the card, resume, once only, and short films
    skipped.
  - A quarter circle scrubbing 15 s, the card, seeking on release, a quick flick still seeking 10 s, and a stick
    held still handed back.
  - Screenshot names that reopen in the same mode. With WSLg, a real capture of the stereo pattern (3840x1080, the
    left eye's red on the left and the right eye's blue on the right).
  - WSLg renders of the curtains opening, the up-next card and the intermission. `tests/test_features.gd`,
    `tests/test_comfort.gd` and `tests/test_pane.gd` still pass.
- **Untested:**
  - The headset: the jog wheel with real sticks, the haptics, and its feel against the flick-seek.
  - A real file's end. The pre-show timing with a film's opening.
  - The screenshot on the hardware decoder's planes and HDR files.

## #73 Fisheye lens profiles, #83 folder rules, #90 light sharpen, #95 deinterlace

- **Fisheye lens profiles (#73):** a fisheye picture was mapped as if every lens were equidistant (distance from the
  circle's centre grows evenly with the angle). Wide lenses of 190 to 220 degrees are often nearer equisolid or
  stereographic, and the wrong model bends straight lines and misplaces the edge of the view.
  - `scripts/play/fisheye_lens.gd` has four generic models: equidistant (the default, as before), equisolid
    (2 sin(t/2)), stereographic (2 tan(t/2)) and polynomial (t (1 + k1 t^2 + k2 t^4 + k3 t^6 + k4 t^8), the common
    fisheye calibration model, with the coefficients in settings). Each is scaled so the edge of the field of view
    meets the edge of the image circle.
  - The profile reshapes the fisheye mesh (`ProjectionMeshes.fisheye()` takes the mapping). Nothing changes per
    pixel. The choice is kept per file, with a default for all files.
  - No maker's lens data ships with the app. A calibrated lens goes in through k1 to k4.
- **Folder rules (#83):** "everything in this folder is 180 side by side". A file with no mode of its own opens in
  its folder's rule. The deepest folder with a rule wins, so rules on `/VR/` and `/VR/360/` both work.
  - `scripts/play/folder_modes.gd`; one line in `main._on_opened()` asks it after the file's remembered mode and its
    sidecar (#60), before the test pattern's own mode, the container's metadata and the name guess. The mode
    source is then "folder".
  - `use_current_for_folder()` makes the mode on screen now the rule for the open file's folder.
- **Light sharpen (#90):** a new picture control, `sharpen` (0 to 1, default 0, off). An unsharp mask over the four
  neighbouring pixels, on luma for video and on the colour for windows and pictures. At 0 the shader skips it. It is
  kept per environment with the other picture controls (#27).
- **Deinterlace (#95):** for interlaced video (DVD rips, 1080i recordings). Off by default.
  - The two fields of each frame show one after the other, so motion runs at twice the frame rate. The other
    field's lines are rebuilt in the shader (`field_luma()` and `field_chroma()` in `video_common.gdshaderinc`).
  - "bob" interpolates straight down. "edge" interpolates along the best of three directions (down-left, down,
    down-right), so diagonals stay smooth. It uses the current frame only, which is lighter than a full temporal
    deinterlacer.
  - "auto" uses edge when the video info says the file is interlaced (`field_order` tt, tb, bb or bt, from the
    engine since PLAYER_REQUESTS), and off otherwise. The field order also sets which field comes first, in FFmpeg's
    names: tt and bt show the top field first, bb and tb the bottom one. The first letter is the field coded first,
    the second the one shown first. Before, tb and bt were the wrong way round.
- **API:**
  - `main.features.lens`: `profile`, `default_profile`, `PROFILES`, `set_profile(id, for_file := true)`,
    `coefficients`, `set_coefficients(k)`, static `mapping(id, fov, k)`, signal `changed`.
  - `main.features.folder_modes`: `rule_for(path)`, `mode_for(path)`, `set_rule(folder, mode_id)`,
    `clear_rule(folder)`, `rules()`, `use_current_for_folder()`, signal `changed`.
  - `main.features.picture`: `set_value("sharpen", v)`.
  - `main.features.deinterlace`: `mode`, `MODES`, `set_mode(m)`, `active()`, `top_first`, static `field_at()`,
    signal `changed`.
  - No keys: the pane or the listener.
- **Settings:** `[lens] default, k1..k4`; `[lens_files] <file key>`; `[folder_modes] rules` (one dictionary: folder
  paths have spaces, colons and slashes); `[picture_<environment id>] sharpen`; `[picture] deinterlace`.
- **Tested:** `tests/test_picture.gd`.
  - The mapping maths for each profile, edges at 1, monotonic for 190, 200 and 220 degrees.
  - The fisheye 200 pattern's mesh: equidistant, equisolid and polynomial rings where the maths puts them, the
    mesh rebuilt on a change, and the profile kept per file and restored on reopening.
  - Folder rules: the deepest wins, a name prefix is not a folder, clearing, and main opening a real path in its
    folder's mode with the source "folder".
  - Deinterlace modes reaching the shader, auto off on a progressive pattern, the field timing, and the four field
    orders.
  - With a renderer: stripes rebuilt by bob for each field, a diagonal edge grey under bob and true under edge, and
    sharpen's overshoot on both sides of a step with flat areas unchanged.
  - `test_hdr`, `test_features`, `test_media_features`, `test_images`, `test_comfort`, `test_delight`, `test_rooms`,
    `test_pane` and `test_video_mode` still pass.
- **Untested:**
  - A real 190 to 220 degree fisheye file under each profile.
  - Real interlaced files (the engine sends `field_order` now; no interlaced test clip yet), and the cost of edge on
    the headset.
  - Sharpen's look on a real film in the headset.

## Filtering by footprint (a picture shrunk on the display)

Most video is shrunk on the Frame, not stretched: the eye image is about 10.5 pixels a degree at its centre, an 8K
360 frame about 21, a 4K flat film on a 60° screen about 64. One bilinear sample per screen pixel then skips texels,
and fine detail shimmers and drops out as the head moves (stars in a still 4K frame aliased on the sphere).

- **How:** `video_pixel_filtered()` in `shaders/video_common.gdshaderinc` takes the screen pixel's footprint in the
  frame (the mesh UV's derivatives, through the zoom and the eye's rectangle) and averages a grid of bilinear samples
  across it: as many along each axis as the footprint is texels long, up to `footprint_taps` (3), separately for luma
  and the half-size chroma. Near 1:1 or stretched it is one sample, as before. No mipmaps: the decoder's frames are
  imported as they are, and a mip chain per frame would cost the bandwidth this saves; the samples lie close
  together, so most come from the texture cache. The foveated edge, where the eye image is coarser, is filtered more,
  as it should be. The derivatives are taken in `video.gdshader` before the dual fisheye seam's branch. The screen
  and the crossfade use it; the floor reflection, the magnifier and the film layer's copy keep one sample (blurred,
  or drawn 1:1). Flat films on the film layer are drawn by the compositor, not this shader.
- **Measured** (`tests/test_footprint.gd`, rendered with lavapipe at 640 x 640): the 8K 360 zone plate where its
  rings are finer than the screen shows false rings at 0.215 spread off, 0.055 on; where they are coarse, 0.357 and
  0.355 (kept). The 8K starfield turned in steps of 0.013°: a patch's light varies 0.043 off, 0.007 on.
- **Switch:** Steady detail on the tablet's band (`[picture] steady_detail`, on by default; off sets
  `footprint_taps` 1). Smooth banding beside it turns the deband off and back to its value.
- **On the Frame** (2026-11-06, `lab://zoneplate_360` playing, the app's GPU cycles from its DRM fdinfo, `drm-cycles-gpu`;
  the `perf` command's `gpu_ms` reads 0 there, the GPU timer isn't available): 150 M cycles a second with neither,
  221 with the filter (+47 %), 271 with the deband, 329 with both, of the GPU's 903 M at its top clock; 72 fps held
  in each. Flat films on the film layer showed no difference: the layer is drawn once per video frame.

## Deband (Smooth banding)

8-bit video shows steps in dark gradients (a night sky, a dim wall), worst in a dark room on an LCD. A picture
control, `deband` (Smooth banding, 0 to 1, on at 0.5, per environment like the others, outside their `pc_enabled`
block), for 8-bit sources; 10-bit ones rarely band and are left alone.

- **How:** in `video_common.gdshaderinc`, after the planes are read (and filtered by footprint): four samples up to
  16 texels away for a 1080-line frame (32 for 4K, up to 48), at a turn fixed per texel, two pairs at right angles.
  Where all four lie within the threshold (up to 3 code values at full strength) the pixel takes their mean, fading
  back to itself as they part, so a real edge is left alone. Luma and chroma apart. Then a triangular dither of one
  output code value, new each frame, on the screen (`video.gdshader`) and in the film layer's copy
  (`video_layer.gdshader`): the dither is what hides the bands, the mean spreads their edges. The floor reflection
  keeps it off (blurred anyway). `lab://gradient` is the test card: dark grey and blue ramps that band in 8 bits.
- **Measured** (`tests/test_deband.gd`, the film layer's shader into an 8-bit viewport, lavapipe): the grey ramp's
  largest step between neighbouring columns 0.0078 off (two code values: the limited range's), 0.0016 on; its level
  0.0794 and 0.0799.
- **To do:** the cost on the Frame (eight more samples a pixel), and its look on a real dark film; whether 10-bit
  sources want it too.

## Dual fisheye 360

A 360 camera's raw file: two image circles side by side in a 2:1 frame. The left circle is the lens that looks
ahead, the right circle the lens that looks back. The app shows the whole sphere from it, with a soft seam where the
two lenses meet. Before, such a file showed as a 360 equirect (its name has "360" in it) or, chosen by hand, as
stereo fisheye (one circle per eye): both wrong.

- **Mode:** `VideoMode.Proj.DUAL_FISHEYE`, id `dualfisheye_mono` (`--mode=dualfisheye` or `dfe`). It is always
  mono: one picture for both eyes, no layout, half or swap. The Picture tab has a "Dual 360" diagram (two circles);
  with it chosen, the layouts other than mono are off. The diagrams are now two rows, layouts then projections:
  eight in one row made the panel wider than its 740 pixels and broke clicks in other tabs.
- **The guess:**
  - A 360 camera's own file name, `360_NNNN` (`360_0042.MP4`, `360_0010.JPG`), with a 2:1 frame (or a size
    not known yet) is dual fisheye. All 199 such files in the user's folder that can be read are raw dual fisheye
    (black corners).
  - A name with `dualfisheye`, `dual_fisheye`, `dual-fisheye`, `dual fisheye` or the word `dfe` is dual fisheye.
  - The plain `fisheye` tags keep their meaning: stereo fisheye, one circle per eye (VR180 cameras).
  - The camera's phone app's copies, `SAM_100_NNNN`, are already stitched: all 26 in the user's folder are
    equirect. With a 2:1 frame they are a 360 equirect now (before: flat). `SAM_NNNN` without the `100` is a phone's
    own video or photo and stays flat.
  - Pictures use the same guess, so the 360 camera's stills open as dual fisheye too.
- **Orientation, from the footage:** both circles are upright (the camera's handle is at the bottom of both). The
  back lens looks the other way, so its picture is mirrored left-right against the front's: the right edge of the
  left circle and the left edge of the right circle show the same place (the viewer's right), and the right
  circle's right edge meets the left circle's left edge (the viewer's left). Of the three possible orientations of
  the back circle (mirrored, turned 180 degrees, as is), the mirrored one matches the front's picture across the
  seam (a correlation fit over 10 stills). The left circle is the front: it is what the viewer sees ahead at the
  start.
- **The mesh:** `ProjectionMeshes.dual_fisheye()`. The whole sphere in rings every 2.8 degrees around straight
  ahead, with rings every 0.5 degrees through the seam band, 128 segments around: about 10,000 vertices, built in
  16 ms on the desktop. Each vertex carries both lenses' places in the frame (UV for the front lens, UV2 for the
  back) and the front lens's weight (COLOR.r): 1 up to (90 - blend) degrees off straight ahead, 0 from
  (90 + blend), a smoothstep between. Each place comes from that lens's own field of view, circle and turn, so the
  lens values cost nothing per pixel. A change rebuilds the mesh.
- **The seam blend:** `video.gdshader` samples the picture once where the weight is 0 or 1 (everywhere but the seam
  band), as for every other projection. Inside the band it samples both lenses' places and mixes them by the
  weight, so the seam is a cross-fade over 2 x blend degrees (6 degrees for the 360 camera) instead of a hard line.
  Both lenses see past 90 degrees (the 360 camera about 7.5), so both have picture there.
  - Why the mesh, not the shader: per pixel, finding the place in a circle needs an `acos` and an `atan` for each
    lens. The mesh does that once per vertex, and the pixel work stays one texture fetch (two in the band). The
    headset draws 2 x 2160 x 2160 at 72 Hz or more.
  - Cost: the band is 6 of the 180 degrees from front to back. Looking straight at the seam with a 100 degree
    view, about 6 % of the pixels sample twice; looking anywhere else, none. The extra varyings (UV2 and the weight)
    are interpolated for every pixel of every projection: a small fixed cost. Not measured on the headset.
- **Lens values:** `scripts/play/dual_fisheye.gd` (`main.features.dual_fisheye`). Per lens (front, back): `fov`
  (degrees across the circle), `cx`, `cy` (the circle's centre, fractions of the frame's width and height),
  `radius` (fraction of the frame's height; 0.5 touches the top and bottom), `yaw`, `pitch`, `roll` (degrees, the
  lens turned from straight ahead or straight back). And `blend` (half the band, degrees) and the lens `model`
  (equidistant, or #73's equisolid and stereographic).
  - Profiles: `camera360` (the 360 camera's video), `camera360_photo` (its stills) and `generic` (190 degrees, centred
    circles that touch the top and bottom, no turn, blend 2.5). A 360 camera file name gets `camera360_photo` when its
    frame is wider than 5000 pixels (the stills are 5792; before the size is known, a picture extension decides) and
    `camera360` otherwise (a video frame saved as a picture is still video). Other files get the default, `generic`.
    The choice is kept per file.
  - Changes are kept per profile, so one nudge serves all the files of that camera. "Reset lens" goes back to the
    profile's own values.
  - The Picture tab, with dual fisheye chosen: Camera (360 camera video, 360 camera photo, Other camera), Lens field
    (both lenses' field of view), Seam (the back lens's yaw, -5 to 5 degrees: it slides the back picture sideways
    along the seam) and Reset lens.
  - The dev link: `dual_fisheye_profile`, `dual_fisheye_fov`, `dual_fisheye_seam`, and `dual_fisheye_lens` for every
    value (`docs/dev/control-protocol.md`).
- **360 camera defaults (fitted 2026-11-01):** the user's camera is a dual-lens 360 camera: 4096 x 2048 HEVC video
  at 24 fps (BT.601, 8-bit 4:2:0) and 5792 x 2896 stills.
  - Method: for each frame, both lenses' views of the band 80 to 100 degrees were unwrapped onto the same
    directions, SIFT features were matched between them, and a robust least-squares fit found the lens values that
    make each pair's two rays the same direction. 13,246 pairs from the 119 stills, 8,443 from 158 frames of 79
    videos (two each).
  - Video (`camera360`): each lens sees 195 degrees across a circle of radius 0.518 of the frame's height (a little
    larger than the frame: it is cut at the top and bottom). Front circle centre (0.249, 0.507), back (0.752,
    0.505). The back lens is turned yaw -0.68, pitch +0.68, roll -0.40 degrees. Median mismatch at the seam
    0.65 degrees, against 5.9 for "195 degrees on a circle of the frame's height, centred, no turn".
  - Stills (`camera360_photo`): 195 degrees across a radius of 0.510. Front centre (0.249, 0.501), back (0.752,
    0.499). The back lens is turned yaw -0.99, pitch -0.15, roll -0.39. Median mismatch 0.31 degrees, against 3.7.
  - Video and stills differ: in the video the circles are about 1.5 % larger and sit 0.5 % lower in the frame, a
    different readout of the sensor. One set of values for both left a mismatch of 0.7 degrees on each.
  - Equidistant fits a little better than equisolid (0.30 against 0.36 degrees on the stills).
  - The video's mismatch is higher than the stills' because of motion blur, compression and near subjects. The
    lenses are a few centimetres apart, so an object nearer than about 2 m cannot meet at the seam whatever the
    values; the fit favours the distances in the footage. The hand that holds the camera always doubles.
  - The two lenses' exposure matches: across the band, the front lens is 0.99 as bright as the back (median over 116
    stills and 15 video frames), so there is no per-lens gain. Both lenses darken towards their edge, so the seam
    band is a little darker than the middle of each lens; this shows most in a clear sky.
- **Zoom lens (#38):** `magnifier.gdshader` maps a direction to both lenses the same way (equidistant), with the same
  blend.
- **Pictures:** `docs/shots/dual-fisheye/`, rendered on the desktop through the app (flat camera, 90 degree vertical
  view; one eye, as both are the same):
  - Pictures from a real dual fisheye camera's footage (a video frame and a still, each from the front, both seams,
    up, down and back) were checked but are not in the repository: they are the user's own footage.
  - `pattern_*.png`: the test pattern (`stub://dualfisheye_mono`): the rings and labels of each lens, and a rainbow
    band round the horizon that continues across both seams.
- **Settings:** `[dual_fisheye] default`; `[dual_fisheye_files] <file key>`; `[dual_fisheye_<profile>]
  front_<key>`, `back_<key>`, `blend`, `model` (only values off the profile's own).
- **Tested:** `tests/test_dual_fisheye.gd`, 51 checks (43 without a renderer).
  - The mesh: ahead is the front circle's centre and behind the back circle's; the right seam is the right edge of
    the front circle and the left edge of the back circle (mirrored), the left seam the other way; up is the top of
    both circles; the weights (1, 0, the smoothstep in the band); a back yaw of 2 degrees moves its centre 2 degrees
    round to the right; every used place inverted back to its vertex's direction within 0.01 degrees.
  - The app: the pattern opens as `dualfisheye_mono` with the shader switch on and the generic profile; 2:1 pictures
    named `360_0001.png` open as dual fisheye with `camera360_photo` (5792 wide) or `camera360` (1024 wide); field of
    view, seam (clamped to 5), nested values, reset, values kept per profile, the profile per file and restored on
    reopening; the Picture tab (the diagram, the controls shown and hidden, mono only, the seam slider); the dev
    link's settings; the zoom lens's uniforms.
  - With a renderer: ahead shows the front lens's tint and behind the back lens's; at the seam, the front on one
    side and the back on the other, and inside the band the two tints mixed by the expected weight (at 88.8 and 91.2
    degrees); the zoom lens aimed ahead and behind.
  - `tests/test_video_mode.gd`: 16 more name cases (360 camera raw and stitched names, the tags, stereo fisheye kept)
    and 5 more `--mode=` forms. `test_picture`, `test_features`, `test_pane`, `test_zoom_lens`, `test_images`,
    `test_media_features`, `test_container_mode` still pass; `--ui-test` has the same two failures as before this
    change (the card command and push-to-talk).
- **Untested:**
  - The headset: the seam in stereo (both eyes see the same picture, so the seam is at infinity), the cost of the
    band at 72 Hz, the mesh rebuild while the Lens field or Seam slider moves, and the 360 camera's 4096 x 2048 HEVC
    through the hardware decoder.
  - The desktop cannot decode the HEVC files, so the video pictures use a frame extracted with ffmpeg and opened as
    a picture. Both take the same path through the mesh and the shader.
  - Other dual fisheye cameras (other makes and models): their circles and orientation may
    differ; the generic profile and the dev link's `dual_fisheye_lens` are the way in.
  - `360 - Car and Bedtime.mp4` and `360_0013.MP4` in the user's folder cannot be read (no `moov` atom: the
    recording did not finish), so whether the first is stitched is not known.

## #21 Virtual cinema speakers, #47 world-locked sound for 180 / 360

Spatial audio: the film's sound comes from speakers in the room, heard through a head-related transfer function
(HRTF). Sound comes from in front, from behind and from above, outside the head, and it stays where it is when the
head turns. This works for every channel layout and for the sound field (ambisonics) of 360 videos.

- **How it sounds where it is:** the engine's `BinauralRenderer` (fork branch `frame/binaural`, `docs/decisions.md`
  D23) renders each channel as a virtual speaker:
  - The direction from the head to the speaker, in the head's axes, every 64 frames (1.3 ms). The head pose comes
    from the XR camera each frame; between poses the head is carried on at its last speed and smoothed (10 ms),
    because the audio callbacks come in bursts.
  - That direction's HRTF: a fractional delay per ear (the interaural time difference) and a 128-tap filter, both
    interpolated bilinearly from a grid of 192 azimuths by 14 elevations (-40 to 90 degrees). When the direction
    changes, the old and new filters are crossfaded over the 64 frames, so a head turn makes no click.
  - The filters are minimum-phase and smoothed across azimuth, and the delays are a spherical head's fitted to the
    measured ones. With the measured data as it was, a head turn pulsed in pitch and brightness each time it crossed
    a grid point.
  - No FFT and no blocks, so no latency is added (an impulse from the front leaves after about 0.5 ms, the HRTF's
    own onset). The binaural mix is the film's stereo stream itself: the same player and the same clock. The A/V
    offset and the latency compensation hold as before, and nothing needs compensating.
- **Layouts:** every layout FFmpeg gives for the decoded track, up to 16 channels, in the track's own order
  (`MediaSource.get_audio_channels()`). Tracks with more channels are mixed to 7.1.4. Each channel's direction comes
  from its name (`scripts/play/speaker_layouts.gd`, ITU-R BS.775 and BS.2051):
  - FC 0, FL / FR 30 degrees left / right, FLC / FRC 15, WL / WR 60.
  - The one surround pair of 5.x (side or back) at 110. With both pairs (7.x), the sides at 90 and the backs at 135.
    BC at 180.
  - Heights 40 degrees up: TFL / TFR at 45, TSL / TSR at 90, TBL / TBR at 135, TFC, TBC. TC is straight up.
    Bottoms (BFL, BFC, BFR) 30 degrees down.
  - LFE: no direction. It is left out unless Bass channel is on; then it goes to both ears.
  - Channels without a name are spread round the listener in order.
  - Mono, stereo (world-locked stereo), 3.0, quad, 5.0, 5.1 side and back, 6.1, 7.1, 7.1 wide, 5.1.2, 5.1.4,
    7.1.2, 7.1.4, 9.1.6 and 22.2 are covered.
- **Ambisonics:** first, second and third order AmbiX (ACN order, SN3D), recognised from the track's own layout: an
  MP4 `SA3D` box (360 video from YouTube and the cameras) or Opus channel mapping 2. This works even when the
  decoder labels its frames as a plain layout (AAC). Higher orders are cut to third.
  - The engine decodes the sound field to world-fixed virtual speakers (a cube for first order, an icosahedron for
    second, Lebedev's 26 points for third) with max-rE weights, and renders those through the HRTF. The field turns
    with the picture's front and stays put when the head turns.
  - A head-locked stereo pair after the ambisonic channels (SA3D `head_locked_stereo`) plays straight to the ears.
  - Object-based formats (Dolby Atmos objects in E-AC-3 JOC or TrueHD, DTS:X objects) have no open decoder. Their
    channel bed plays (5.1 or 7.1), placed as above. The objects' height and movement are lost; there is no
    proprietary code here.
- **Where the speakers stand:** each room declares its speakers and its acoustics
  (`VREnvironment.get_sound_room()`, in the room's own frame).
  - Cinema: the screen channels 0.3 m behind the screen; the front pair kept between 22 and 35 degrees however
    small or far the screen. Surround arrays of three speakers, 3 m apart, on the side and back walls, 4 m up; the
    heights on the ceiling.
  - Home theatre: the fronts from the two towers' tweeters, the centre from the speaker under the screen; surrounds on
    the walls at 1.8 m, heights in the ceiling.
  - Dim room: the screen channels on the screen, the rest on the walls at 1.6 m and on the ceiling.
  - Dome and planetarium: a ring of 6 m (in the dome's frame) and 8 m (behind the planetarium dome's foot), the
    heights and the top channel overhead.
  - Drive-in: the car's own speakers. Doors and dashboard at the front, rear doors and the parcel shelf behind, the
    headlining above.
  - Passthrough: the standard layout (ITU angles) 2 m round the seat.
  - The void: the standard layout, 2.5 m round the seat.
  - Assistant rooms and kept rooms: the layout of the built-in room they are built on, or the standard layout for a
    glTF base. The room document has no say in it, and the room schema is unchanged.
  - 180 / 360 (#47): a ring round the head facing the picture's front (the screen yaw). For ambisonics, the field
    is turned the same way.
- **Distance and outside the head:** each room's reflections and reverb:
  - First-order reflections off the room box's six walls, each wall with its own reflection amount. They are image
    sources, delayed by the extra path, panned by a spherical-head model of time and level, and low-passed.
  - A late reverb: an 8-line feedback delay network sized to the room's mean free path, with the room's decay time.
  - The amounts: cinema RT60 0.7 s, wet 0.55; home theatre 0.35 s, 0.5; dim room 0.55 s, 0.55; planetarium 1.2 s,
    0.5; dome 0.3 s, 0.25 (open air, the ground reflects); drive-in 0.12 s, 0.35 (the car); passthrough 0.4 s,
    0.45; standard 0.35 s, 0.35 (reverb only).
  - In 180 / 360 the picture is the room: a light reverb only (0.3 s, wet 0.25).
  - Room sound in the Sound tab scales the wet amount from 0 to 200 %.
- **Output profiles:** the headset's own speakers, or headphones and earbuds. Auto asks PulseAudio / PipeWire for
  the default sink every 10 s (`pactl`). Bluetooth, USB or a headphone port count as headphones; anything else is
  the speakers. Each profile has its own HRTF set, an EQ hook (`[spatial] eq_<profile>`, up to 8 peak or shelf
  bands, for a measured correction) and the tuning of "Tune spatial sound".
- **HRTF sets:** see `app/audio/hrtf/CREDITS.md`.
  - Bundled (2 MB): six sets of the SADIE II database (University of York, Apache License 2.0): "Dummy head A"
    (the default), "Dummy head B", and listeners H3 to H6.
  - Fetched on request: the MIT dummy head, HUTUBS listener 1, ARI listener NH2 and CIPIC subject 003. They come
    from the SOFA collection (sofacoustics.org) and are converted on the headset into `user://hrtf`. Each licence is
    shown before the download: the MIT dummy head free with citation; HUTUBS CC BY 4.0; ARI CC BY-SA 4.0; CIPIC the
    database's own terms.
  - Ids of earlier versions in settings are read as their new ids.
  - Not offered: LISTEN (its terms are not clear).
  - `app/tools/hrtf_pack.gd` converts any SOFA file (AES69 SimpleFreeFieldHRIR). The steps: resample to 48 kHz,
    equalise to the diffuse field, take the delay out of each response, put it on the grid, and store it as 16-bit.
- **Tuning ("Tune spatial sound", `scripts/play/spatial_tune.gd`):** "which sounds better?" picks that fit the
  spatial sound to the viewer's ears, for the output profile in use. It replaced a pointing test (point where each
  short burst was heard, about 70 of them, no feedback): in the headset it was not possible to tell whether the
  answers were right, and the user gave up halfway.
  - The sound: pink noise in pulses, four a second (170 ms on, 12 ms fades, each pulse within 2 dB of -16 dB). It is
    broadband with a rhythm, and each pulse's onset gives the ear a fresh cue. In 6 s it circles the head on the
    horizon (front, right, behind, left, front; 4.4 s), then rises over the top to 30 degrees up behind.
  - Head tracking is on. The path is fixed in the room, facing where the head faced when the pick began, so the viewer
    may turn toward the sound. The film pauses while it runs.
  - Each pick plays the sound through two candidates: A, then 0.6 s later B. The card beside the screen says which
    one plays. It has four buttons for the laser and trigger: A, B, Can't tell (the champion stays) and Again (both
    again). A or B counts only once both have been heard. The menu button cancels, and then nothing changes.
  - The card says there is no right answer: pick whichever sounds more real, more outside your head, more in the
    room. Its title gives the progress ("Head size: pick 7 of 9").
  - The order (`Knockout`, pure):
    1. The profile's HRTF set and tuning start as the champion, so tuning never leaves the viewer with something they
       like less. Every other set (bundled and fetched) challenges it once, with no tuning, and the winner stays.
    2. Head size (ITD scale, steps of 0.1, 0.7 to 1.3): a step one way, chosen at random. If it won, a step further
       that way; if it lost, a step the other way. Two picks, fewer at the limits.
    3. Ear shape (pinna warp, steps of 7 %, 0.85 to 1.18), in the same way, only if all the picks fit in 9 (about 2
       minutes): with the six bundled sets, yes; with fetched sets too, no.
    - Which of the two is A is random each pick, so the champion isn't always first. The concha gain is kept as it
      is.
  - The stream: an `AudioStreamGenerator` (0.25 s buffer) kept 50 ms ahead, fed each frame in blocks of 512 frames.
    Each set and ear shape has its own `BinauralRenderer`, loaded on a worker thread while the pick before plays: a
    new pinna warp rebuilds the set's grid, which takes as long as loading it. Before each block
    the listener is set to the head's pose, turned back by the path. The source stays straight ahead, so it moves as
    smoothly as a head turn does. The renderer has the profile's EQ, the speakers' gain and the light room of 180 /
    360 (reverb only). Head tracking lags by the 50 ms lead plus the sound device's own latency. `status().skips`
    counts underruns.
  - The result is saved for the profile: the set (`[spatial] hrtf_<profile>`) and `[spatial] tuning_<profile>`
    (`itd_scale`, `pinna_warp`, `concha_db`, `picks`, `changed`, `tuned_at`). A card says what was chosen and what it
    was before. The Sound tab's line gives the head size.
  - Started from the Sound tab, or by the `spatial_tune` command (assistant level control): `action` is start (the
    default), cancel, status, or a pick for the viewer (a, b, same, again).
- **Sync and speed:** at a speed other than 1x the engine time-stretches the stereo mix only, so the stereo mix
  plays until the speed is 1x again. With the sound on a PC (#9) the renderer is taken off, and the PC's speakers get
  the plain mix. A seek clears the room's echoes.
- **Off by default** until checked on the headset (`SpatialAudio.DEFAULT_ON`). Turning it on reopens the open file
  at its place, because the channels are chosen when a file opens.
- **API:** `main.features.speakers` (`scripts/play/spatial_audio.gd`):
  - `enabled`, `set_enabled(on)`, `lfe`, `set_lfe(on)`, `hrtf`, `set_hrtf(id)`, `reverb`, `set_reverb(x)`, `output`,
    `set_output(mode)`.
  - `profile()`, `profile_settings()`, `set_profile_eq()`, `set_profile_tuning()`.
  - `active`, `available()`, `channels()`, `speaker_position(name)`, `sources()`, `sound_field()`, `stats()`.
  - `hrtf_sets()`, `download_hrtf(id)`.
  - Signals `changed(active)` and `download_finished(id, error)`.
- **Commands:** `sound` and `set_sound` (`speakers`, `bass_channel`, `output_profile`, `hrtf`, `room_reverb`),
  `download_hrtf` and `spatial_tune`, all tagged for the assistant.
- **Settings:** `[speakers] enabled, lfe`; `[spatial] reverb` (1.0), `output` ("auto"), `hrtf_<profile>`,
  `eq_<profile>`, `tuning_<profile>`.
- **CPU, measured on the desktop** (x86_64 WSL, template_debug at -O3, 512-frame blocks at 48 kHz). The head turns
  all the time, which is the costlier path (two filters crossfaded), and the room is on (`tests/test_binaural.gd`):

  | Input | Per block | One core |
  |---|---|---|
  | 2 channels | 74 us | 0.7 % |
  | 6 channels | 218 us | 2.0 % |
  | 8 channels | 296 us | 2.8 % |
  | 12 channels | 416 us | 3.9 % |
  | Ambisonics, first order (8 virtual speakers) | 186 us | 1.8 % |
  | Ambisonics, third order (26 virtual speakers) | 667 us | 6.3 % |

  - The cinema's surround arrays add sources: 7.1.4 there is 20 sources, about 6.5 %.
  - The convolution is vectorised on arm64 too (NEON, 4 lanes). The headset's cores should be within 2x of the
    desktop's, so expect about 4 to 8 % of one core for 5.1 to 7.1.4 and up to 13 % for third-order ambisonics. That
    is well under one core next to hardware HEVC decoding. To be measured; see On the headset.
- **Tested:**
  - `tests/test_binaural.gd` (51 checks):
    - The packs, and the HRTF lookup and its interpolation.
    - The time and level differences between the ears of rendered noise from the front, back, left, right and above.
      Left: the left ear leads by 39 samples and is 16 dB louder. Front and back are centred, with 3.7 dB of
      timbre between them.
    - A head turn keeps a source where it is in the room, and gives no clicks.
    - Ambisonic decoding at first and third order, turning with the head and with the picture's front.
    - LFE and head-locked channels, no added latency, the room's tail, the tuning, and the CPU.
  - `tests/test_spatial_audio.gd` (93 checks):
    - Every layout's directions, the ring, and every room's 7.1.4 placement and acoustics.
    - The settings, the commands and the output sink's classification.
    - In the engine, with the files of `tests/make-spatial-media.py`: every WAV layout's channels; the SA3D box as
      first-order ambisonics, with and without the head-locked pair; each 7.1.4 tone from its side; the sound field
      and the head-locked tone on the left; the binaural mix's loudness against the stereo mix (0.4 dB); the audio
      clock unchanged.
  - `tests/test_spatial_tune.gd` (44 checks):
    - The knockout: the profile's set is the first champion; every other set challenges once; the champion plays
      as A in some picks and as B in others; 9 picks with six sets, no ear shape picks with ten. The next challenger
      is always one of those foreseen (loaded while the pick before plays).
    - Against listeners who prefer one set, head size and ear shape, over 20 seeded runs each: their set wins
      every time; a step away, the head size and ear shape are found every time; two steps away, one step is taken
      toward it. Can't tell throughout changes nothing. At the limit, no step goes past it, and the count of picks
      shrinks to match.
    - The path (front, right, behind, left, over the top to behind, no jumps), and the listener pose: whichever way
      the head turns, the source is heard where it is in the room.
    - The pulsed pink noise: its level, pulses four a second, silent between.
    - The step in the main scene, with picks on the card's buttons: the menu cancels with nothing changed; A plays,
      then B; a pick before both are heard is refused; Again plays them again; the sound is rendered; every pick runs;
      the result is saved and shown; the `spatial_tune` command's status, picks, start and cancel.
  - `test_features`, `test_night`, `test_media_features`, `test_pane`, `test_assistant_coverage_playback` and
    `test_assistant` still pass. `test_media_features`' "events arrive" fails now and then on the base engine as on
    this one (1 run in 6 on the base engine, 2 runs in 8 here). It is a subtitle timing check, headless.
  - `test_night` uses `app-features/vp9_51side.mkv`: a VP9 picture with a 5.1(side) FLAC track, one tone per channel
    (FL 300, FR 400, FC 500, LFE 60, SL 700, SR 800 Hz). It was made with FFmpeg from a generated six-channel WAVE
    with a channel mask.
- **On the headset** (for the lead; the app never touches the device itself):
  - Deploy `PLAYER_BINAURAL` and turn on Spatial sound with a 5.1 or 7.1 film. Check that dialogue sits on the screen,
    the surrounds beside and behind, and that nothing sits inside the head, on the headset's speakers and on
    earbuds. Turn the head: the sound should stay put, with no clicks.
  - A 360 video with spatial audio (SA3D): sounds should come from where their source is in the picture.
  - Read the CPU: the `sound` command, or `main.features.speakers.stats()` (`load` is the share of one core) while
    4K HEVC plays.
  - Lip sync with the A/V calibration card (lab://av_sync), spatial sound on and off: the offsets should match.
  - The loudness against the stereo mix (`SpatialAudio.GAIN`), and which output `pactl` reports for the speakers and
    for earbuds (it decides the profile).
  - Run Tune spatial sound once on the speakers and once on earbuds. Check that the sound starts in front and goes
    round to the right, and that it stays put in the room when the head turns (no lag you can hear, no clicks). Check
    that A and B are told apart on the card, and that the menu button stops it. Check `status().skips` (underruns)
    after a run; if it is not 0, raise `LEAD_SECONDS`. Time a whole run (about 2 minutes).
  - Then set `DEFAULT_ON` to true.
- **Untested:** the headset (all of the above); 44.1 kHz output (the HRTF is resampled to the mix rate, but checked
  only at 48 kHz); real films' Atmos beds; Opus ambisonics (no encoder here, so the test file is PCM in MP4); the
  downloads from sofacoustics.org (the code path is the same as the bundled conversion, but no download was made
  here).

## #29 Bias light from the picture

The screen's light on the room takes the film's colour and brightness. A sunset warms the walls, and a night scene
lets the room go dark. Each side of the room takes the colour of the picture's side nearest to it.

- **How, all on the GPU with nothing read back:**
  - A tiny offscreen viewport (4 x 2 pixels) draws the picture through the screen's own uniforms
    (`shaders/bias_sample.gdshader`). Each pixel is the mean linear colour of its part of the picture (36 samples).
  - The viewport keeps its contents between frames (background "keep", never cleared), and each frame is blended
    over them. This is an exponential average with a time constant of 0.25 s, so cuts fade in and nothing flickers.
  - The room shaders (`env_unlit`, `env_unlit_tex` and `grid`) now share `shaders/env_spill.gdshaderinc`. It reads
    the viewport as the global `screen_thumb` and multiplies the screen's spill by the colour of the picture's
    nearest side (globals `screen_tint` and `screen_axis`).
  - A picture of a typical film's mean brightness (sRGB about 0.38) lights the room as designed. Brighter pictures
    light it more, up to 2.5 times; darker ones less.
  - Three globals are added to `project.godot`. With `screen_tint` at 0 the spill is white, as before.
- **Where:** flat screens with a picture showing. 180 and 360 hide the room. The void has no spill to colour. The
  sleep timer's and the playback dimming's factors still apply, because they scale the spill itself.
- **API:** `main.features.bias`: `enabled`, `set_enabled(on)`, `strength`, `set_strength(v)`, `active()`,
  `thumbnail()`, `tint`, `axis`, signal `changed`.
- **Settings:** `[bias_light] enabled` (default off until its GPU cost is measured on the headset; the user is
  battery-conscious), `strength` (0 to 1, default 1).
- **Tested:** `tests/test_bias.gd`, 14 checks, with a WSLg renderer for the GPU checks.
  - Off by default; turned on, active on a flat screen. Off in 360 and when turned off (tint 0). The axis is the screen's
    right direction over its width.
  - A red and blue picture gives red left cells and blue right cells in the thumbnail.
  - A change to green is part way after one frame and settled after 1.5 s.
  - A white wall left of the screen renders reddish and one right of it bluish. With the bias light off it renders
    white.
  - WSLg renders of the cinema and the home theatre, with the bias light off and on, show the room warm on one
    side and blue on the other.
  - `test_rooms`, `test_delight`, `test_comfort`, `test_features`, `test_pane`, `test_images` and `test_picture`
    still pass.
- **Untested:** the headset: whether the default strength feels right on real films, the cost of the extra
  offscreen pass (36 picture samples for each of 8 pixels), and the "keep" background on the device's GPU. The
  keep is Godot's own choice of render-pass load operation, so it should behave the same there. If the viewport
  were cleared each frame, the room would come out far too dark with the bias light on.

## #26 Night mode and dialogue boost

- **What:** night mode turns loud passages down and quiet ones up, for watching at low volume. Dialogue boost
  raises the centre channel (0 to 12 dB), where the voices are, for audio that has one.
- **How:** both are the engine's (MediaSource `night_mode`, `night_mode_strength` and `dialogue_boost`, fork
  0178dc9a02). AC-3 and E-AC-3 tracks use their own DRC data, and every track goes through a compressor that
  levels the film towards -24 dBFS, with a limiter under -1 dBFS. `scripts/play/night_mode.gd` remembers the
  choices for all files and applies them when each file opens and at once on a change. A change is heard after
  about 1 s, the audio queue. `scripts/video/hw_video_source.gd` forwards them (`set_audio_dynamics()`) and the
  engine's statistics (`get_media_stats()`). Engines without them ignore it.
- **Note:** with night mode off, the engine plays AC-3 at its full range (DRC off), as other players do.
- **API:** `main.features.night`: `night`, `strength`, `boost_db`, `set_night(on)`, `set_strength(v)`,
  `set_dialogue_boost(db)` (0 to 12, half-dB steps), `available()`, `boost_applies()`, `stats()`, signal `changed`.
- **Settings:** `[sound] night_mode` (default off), `night_strength` (0 to 1, default 1), `dialogue_boost_db`
  (default 0).
- **Tested:** `tests/test_night.gd`, 9 checks, headless on the fork with the 5.1 file of the speakers test.
  Defaults, settings and clamping, nothing applied to a test pattern, values reaching MediaSource when the file
  opens and at once on a change, and the engine reporting that the boost applies to 5.1. `test_features` and
  `test_media_features` still pass.
- **Untested:** the headset: how it sounds on real films at low volume, and whether dialogue stays clear.

## #70 Quad layers (a spike behind flags)

`--pane-layer` puts the pane into an OpenXR quad layer that the runtime samples once into the lens view, for
sharper text. `--video-layer` turns on the film layer (below) for one run, without saving it. The normal path stays
the default. Details, limits, tests and the cost are in `docs/xr-spikes.md`, "Quad layers". Code:
`app/scripts/xr_spikes/quad_layers.gd`.
- **API:** `QuadLayers.attach(main, args, force)` (static), `pane_layer`. No settings: flags only.

## #70 Film layer

The flat film as an OpenXR composition layer instead of a mesh in the room. On by default since 2026-11-04; the
System tab can turn it off. Code: `app/scripts/play/film_layer.gd`, `app/shaders/video_layer.gdshader`.

- **On the Steam Frame (2026-11-04):** the hole punch works, and the film shows through it at 3840 x 1608 for a 4K
  scope film. Stars in a paused 4K frame alias badly on the mesh and stay still on the layer, whatever their size
  against a pixel. With a 4K HEVC film playing at 72 fps, the app's GPU time was 1.4 ms with the layer and 2.5 ms
  without, with no dropped frames either way; the runtime's own cost for the extra layer is not in that figure.

- **Why:** in the room, the film is resampled twice: into the eye buffers, then again by the runtime's lens
  distortion. With foveation on (D22), the eye buffers have lower resolution away from the centre. As a layer, the
  runtime samples the film's own pixels once, at display resolution. Small text and fine detail should be sharper,
  and foveation no longer touches the film.
- **How:** each layer has a SubViewport the size of one eye's picture (at most 3840 px a side). A 2D pass of the
  screen's own picture code (`video_common.gdshaderinc`) draws into it, with the screen's uniforms copied over. The
  pass runs only on a frame with a new video frame (`VideoSource.frame_key()`) or a changed uniform. On other
  frames the runtime shows the last image again. The layers are children of the screen node, so they follow moves,
  resizes and recentring.
- **Modes:**
  - Flat 2D, and 3D shown as 2D (#59): one quad layer for both eyes.
  - Flat 3D (side by side, top / bottom): two quad layers, one for each eye.
  - Curved screen: a cylinder layer when the runtime has it. The Frame's runtime has no cylinder layers, so on the
    Frame the curved screen stays a mesh.
  - 180, 360 and fisheye: always the mesh. The Frame has no equirect layers, and fisheye would need a reprojection
    pass.
- **Depth:** a layer has no depth test. The layers sit behind the room (`sort_order` -1) with a hole punched where
  the screen is: the engine's hole-punch mesh writes depth and alpha 0, and the runtime shows the layer there.
  - The pane, the laser, the controllers, subtitles and room objects in front of the screen still cover the film.
    Half-transparent ones blend over it.
  - Objects behind the screen stay hidden by the hole's depth.
  - **On the Frame, the runtime still draws the layer over what is in front of it.** It drew it over the menu's panels
    (2026-11-04), over a ham thrown at the screen and over a controller held up in front of the film (2026-11-06).
    So the layer hides, and the screen's mesh draws the film, while the menu is open and while something is between
    the eyes and the picture: a room object (placed, held, in flight, or attached text), a controller, the laser or
    its dot, whose bounds, seen from the eyes, cover part of the picture. The layer comes back one second after the
    view is clear (`film_layer.gd _covered()`, `COVER_RELEASE`).
- **Same as before:** colour (BT.709 / 601 / 2020, PQ and HLG tone mapping, 10-bit planes), picture controls,
  sharpen, deinterlace, zoom and pan, 3D depth shift, edge fade, film grain, and the dimming when the menu opens or
  the sleep timer fades. The bias light, the floor reflection and the room's light from the screen read the video
  planes, not the screen mesh, so they do not change. The swapchain is 8-bit sRGB, like the eye buffers.
- **Lost:**
  - A room's fog or glow no longer sees the film. Fog colour over the hole adds onto the film instead of mixing with
    it.
  - Room snapshots and other cameras in the scene show no film on the screen. Layers exist only in the headset.
  - When the app misses frames and the runtime reprojects the room, the hole and the layer can part at the
    screen's edge for a moment.
  - Nothing else in the scene can draw behind the film and show through it.
- **Cost:** the 2D pass runs once per video frame, at the film's resolution. A 1080p film at 24 fps is about
  50 Mpx/s. The mesh path runs the same shader on every screen pixel of both eyes at the display rate, which is more
  pixels for most screen sizes. The swapchains take memory: 3 images of the layer's size each. That is about 25 MB
  at 1080p and 100 MB at 4K, doubled for 3D. The runtime composites one or two more layers.
- **Fallback:** setting off, no XR session (a desktop), an engine without the layer nodes, or a mode without a
  layer: the screen's mesh, as always. Switching at run time keeps playback going.
- **What to compare on the headset:** the same film and room, with the setting off and then on.
  - Small text: subtitles burnt into the film, end credits, a captured browser window.
  - Fine detail at the edge of the view, where foveation works hardest.
  - Colour and black level of an HDR film (the two paths should match).
  - Shimmer on a 4K film shown small: there are no mipmaps on either path.
  - GPU frame time in the overlay stats.
  - The pane, the laser and subtitles over the film.
  - The screen's edges while you turn your head fast.
- **API:** `main.features.film_layer`: `enabled`, `set_enabled(on, save := true)`, `kind` ("quad", "cylinder" or
  ""), `layers`, `viewports`, `updates`, `status()`, `wanted_kind()`, static `available()`, static
  `eye_pixels(frame_px, flat_size, mode)`, signal `changed`. The System tab, Rendering: "Film drawn by the headset",
  with a status line under it.
- **Settings:** `[view] film_layer` (default on; only false is stored).
- **Tested:** `tests/test_film_layer.gd`, 33 checks headless, 35 with a renderer (WSLg), forced on without an XR
  session:
  - the setting and its round trip;
  - the mesh without an XR session;
  - layer kind, eyes, sort order, hole punch, size and place for flat 2D, 3D, 3D shown as 2D, curved and 360;
  - drawing only on new pictures or changed uniforms;
  - switching off and on while playing;
  - the sizing helper.

  With a renderer, the layer's colour bars match the screen shader's within 4 of 255 per channel (the check allows
  0.02), and the two eyes differ on a 3D pattern.
- **Untested:** cylinder layers (no runtime here has them), and side-by-side 3D on the headset.

## #81 The environment reacts to the film

The film's sound drives two subtle effects. Off by default.

- **Bass:** the low end (20 to 120 Hz) above -30 dBFS sends short pulses (60 ms) to both controllers, like a seat
  shaker. Stronger bass gives a stronger pulse, up to full at -10 dBFS, at most 8 a second. The controllers'
  haptics setting (#32) must be on, and its strength applies too.
- **Loud moments:** a sudden jump of the broadband level (120 Hz to 8 kHz) at least 14 dB over its 2 s running
  average, and louder than -24 dBFS, flashes the room light. The flash raises the light by at most 40 % (the same
  photosensitivity ceiling as every assistant room effect, `RoomSchema.MAX_SWING`; it was up to 2.5 times) and
  fades back over 0.35 s, at most one every 1.2 s. Only rooms that opt in flash (an environment's
  `reacts_to_film`): the drive-in, under its open sky.
- **How:** `scripts/env/film_react.gd` adds an `AudioEffectSpectrumAnalyzer` to the Master bus while it is on, and
  removes it when off. It hears what the viewer hears, from the stereo player or the cinema speakers (#21). With the
  PC audio sink (#9) the headset is silent and nothing reacts. The flash is a factor on the shared room light,
  which now accepts factors up to 4 (above 1 brightens).
- **API:** `main.features.react`: `enabled`, `set_enabled(on)`, `strength`, `set_strength(v)`, `room_opts_in()`,
  `feed(bass_db, broad_db, delta)`, `pulses`, `flashes`, signals `pulsed(amplitude)` and `flashed(amount)`.
- **Settings:** `[react] enabled` (default off), `strength` (0 to 1, default 0.5).
- **Tested:** `tests/test_react.gd`, 15 checks, with WSLg.
  - The analyzer is added and removed with the setting.
  - Pulses: none for quiet bass, the scale at -15 dB, the rate limit, and none with haptics off.
  - Flashes: none in the void, none for a small rise, one for a loud jump in the drive-in, the cooldown, and the
    fade back to 1.
  - A real 50 Hz tone reads as bass through the analyzer (-12.6 dB against -47.8 dB broadband).
  - `test_rooms`, `test_features`, `test_comfort` and `test_delight` still pass.
- **Untested:** the headset: how the pulses feel on real films (too busy, too weak?), whether flashes match thunder
  and explosions and are not set off by music, and the analyzer's CPU cost.

## #92 Projector mode

The feel of a film projector. Each part is off by default.

- **Beam:** a faint light cone from a projector 6 m behind and 2.2 m above the seat to the flat screen's corners,
  with dust motes drifting in it. The cone is one transparent mesh with four sides, drawn additively. It is
  brightest near the lens and fades out before the screen. Each side is weighted by how directly it is seen, a
  cheap stand-in for the length of the path through the light. The motes are 240 GPU particles emitted at random
  points inside the cone, fading in and out over 9 s. The beam follows the screen, for flat screens only.
- **Grain:** monochrome film grain on the picture (0 to 1), about two picture pixels per grain, strongest in the
  mid-tones, and a new pattern every frame (`film_grain` and `grain_seed` in `video_common.gdshaderinc`).
- **Gate weave:** the picture drifts by a fraction of a percent (at most 0.3 % of its height at weave 1), as film
  does in a projector's gate. It is a slow random walk plus a little jitter each frame (`film_weave`).
- Grain and weave suit old releases and apply in every projection. The floor reflection and the bias light copy
  them with the screen's other uniforms.
- **API:** `main.features.projector`: `beam`, `grain`, `weave`, `set_beam(on)`, `set_grain(v)`, `set_weave(v)`,
  `beam_applies()`, `apex()`, signal `changed`.
- **Settings:** `[projector] beam` (default off), `grain` (0 to 1, default 0), `weave` (0 to 1, default 0).
- **Tested:** `tests/test_projector.gd`, 12 checks, with WSLg.
  - The lens behind and above the seat, the four sides reaching the screen's corners, and the motes emitting.
    No beam in 360, and the beam back on a flat screen.
  - Grain reaching the shader with a new seed each frame. Weave moving and staying under its maximum. Both off
    again, with the settings erased at the defaults.
  - Rendered: grain spreads a flat grey picture, and weave moves the picture by the set amount.
  - WSLg renders of the cinema, facing the screen and looking back at the lens. At the first strength the beam
    washed out the view overhead, so the strength was cut to a quarter.
  - `test_hdr`, `test_picture` and `test_features` still pass.
- **Untested:** the headset: the beam's look in stereo and in the dark, whether the motes read as dust, the grain's
  look at the headset's resolution, and the cost of the transparent cone and the particles.

## #84 Time of day for the outdoor rooms

The drive-in at dusk when it is dusk outside. No internet and no weather.

- **The sun:** its elevation from the system clock, a latitude setting (default 50 degrees north) and a longitude.
  Without a longitude setting, the longitude comes from the system's time zone (15 degrees an hour), so daylight
  saving can put the sun's times about an hour off. The formula is a low-precision solar position, within 0.01
  degree of the NOAA solar calculator in the tests.
- **The drive-in:** `set_time_of_day(elevation)` sets its sky, horizon band, stars and the lot's light. Below -12
  degrees it is night, and stars fade out through twilight. Between about -6 and +4 the band glows warm. Above
  about 10 degrees it is day, with a blue sky and the lot fully lit (ambient 0.9). The room's colours are set in
  linear light, so they show as designed at each ambient level. Rooms without a sky are left alone.
- **Modes:** "night" (the default: the room as designed), "clock" (the real sun, updated once a minute), "dusk"
  and "day".
- **API:** `main.features.time_of_day`: `mode`, `MODES`, `set_mode(m)`, `latitude`, `set_latitude(v)`,
  `longitude`, `set_longitude(v or null)`, `longitude_in_use()`, `elevation()`, static
  `sun_elevation(lat, lon, unix_utc)`, signal `changed(elevation)`. Environments may implement
  `set_time_of_day(elevation_deg)`.
- **Settings:** `[time_of_day] mode` (default night), `latitude` (default 50), `longitude` (default: from the time
  zone).
- **Tested:** `tests/test_time_of_day.gd`, 16 checks, headless.
  - Six sun positions match the NOAA calculator's values within 0.01 degree: London's summer noon and midnight,
    the equator at the equinox, London at a winter dusk, Sydney and New York.
  - The default night as designed. Clock mode at a summer noon gives day (blue sky, no stars, full light), and at
    a winter 16:30 gives dusk (warm band, stars coming).
  - The fixed modes, a cinema untouched, a new drive-in getting the mode, night restored, and the longitude from
    the time zone.
  - WSLg renders of night, dusk and day. The first dusk was far too bright: the albedo is an sRGB colour, so
    dividing the ambient out has to happen in linear light. Fixed.
  - `test_rooms` and `test_react` still pass.
- **Untested:** the headset: whether day at the drive-in is pleasant to watch a film in, and the colours in the
  headset.

## #38 Zoom lens for 180 and 360 pictures

Hold the grip and pull the trigger, and a round lens appears where the hand aims. It shows that part of the picture
magnified, 3x by default. Let go of either to put it away.

- **How:** the lens is a disc 32 cm across, 0.8 m in front of the eyes on the line along the aim, drawn on top of
  everything by `shaders/magnifier.gdshader` with the screen's uniforms. Each fragment looks along its own
  direction from the eye, pulled towards the aim by the magnification, turned into the sphere's own space (its yaw
  and tilt), and mapped to the picture the way the projection meshes map it (180, 360, or an equidistant fisheye).
  The picture keeps its stereo depth.
- **Input:** main's trigger handler asks the lens first, after the pane and the window pointer. A docked pane still
  takes the trigger. While the lens is up, the grip does not turn the sphere, and the trigger does not pause.
  The trigger alone plays and pauses as before. Flat screens have the manual zoom (#35) instead.
- **Note:** the fisheye mapping is equidistant; the lens profiles (#73) are not applied in the lens yet.
- **API:** `main.features.zoom_lens`: `enabled`, `set_enabled(on)`, `magnification`, `set_magnification(v)`
  (1.5 to 8), `active`, `hand`, `on_trigger(hand, pressed)`, `begin(hand)`, `end()`, `aim()`, signal
  `changed(active)`.
- **Settings:** `[zoom_lens] enabled` (default on), `magnification` (default 3).
- **Tested:** `tests/test_zoom_lens.gd`, 10 checks, with WSLg.
  - Through main's trigger handler: no lens on a flat screen. In 360, grip held plus trigger brings the lens
    without pausing. It sits on the aim 0.8 m out, and goes on release. The trigger alone still plays and pauses.
  - Clamping and settings.
  - Rendered: through the lens, the picture at the aim is the band of a striped equirectangular picture that the
    aim points at. At 6x the lens shows fewer bands than at 1.5x (5 against 10 colour changes).
  - `test_features`, `test_pane`, `test_comfort` and `test_time_of_day` still pass.
- **Untested:** the headset: the gesture's feel, the lens size and distance, and stereo comfort through it.

## #24 A/V latency test card, and the offset per refresh rate

- **The card:** `lab://av_sync`, a new card in dev-plumbing's test lab (#48, `docs/test-lab.md`). It flashes white
  for two content frames at each whole second while its own audio track beeps (30 ms at 1 kHz). The beep track is
  generated when the card opens: 8-bit at 8 kHz, 600 s, about 4.8 MB. It is the player's audio, so it is the master
  clock as a film's is, and the A/V offset moves the picture against it exactly as for a film. Move the offset (the
  Sound tab's slider) until the flash and the beep land together; it applies live.
- **Per refresh rate:** the picture's delay through the display differs at 72, 90 and 120 Hz.
  `scripts/play/av_latency.gd` remembers the offset for the rate it was set at (`main.set_av_offset()` calls
  `remember()`, one hook), and puts it back whenever the display runs at that rate again (checked every 2 s; the XR
  runtime's rate, else the screen's). The plain `[audio] av_offset` stays the value for rates never set.
- **API:** `main.features.latency`: `refresh_rate()`, `remember(seconds)`, `offset_for(rate)`, `rate_override`
  (tests), signal `applied(rate, seconds)`. `LabVideoSource.beep_stream(seconds)` (static).
- **Settings:** `[audio] av_offset_<rate>` (seconds).
- **Tested:** `tests/test_av_sync.gd`, 11 checks, with WSLg. A beep at each whole second and silence between. The
  card listed. The card rendered white on frames 0, 1, 60 and 61, and dark on 2 and 30. The card's beep track is
  the player's audio, and the player's position follows it. The offset stored for 90 Hz, kept at 72 Hz with nothing
  stored there, and each rate's own offset put back. `test_features` and `test_pane` still pass.
- **Untested:** the headset: the measured offsets at 72, 90 and 120 Hz, and whether the 8 kHz beep is easy to
  judge.

## #64 Music files

MP3, FLAC, Ogg, Opus, WAV, AAC and M4A, AC-3, DTS and other audio files play on the engine's MediaSource without
video (fork 5997ea5369: the audio is the clock). The flat screen shows a card instead of a picture.

- **The card** (1280 x 720, flat and mono): the file's cover (`get_album_art()`) on the left, with title, artist and
  album from its tags. Without a title tag, the file name is used. Below them is a visualiser: 32 bars over 40 Hz
  to 12 kHz from an `AudioEffectSpectrumAnalyzer` on the Master bus while the file is open. The bars rise at once
  and fall slowly. Without a cover, the bars take the card's middle. A time line runs along the bottom.
- **Lying down:** the card is the flat screen, so lying down (#12) and the other screen comforts work as for films.
- **How:** `scripts/play/music_source.gd`, a video source of kind "music". The factory (dev-plumbing's) opens music
  extensions with it and lists them as media files. Network files open on the player's worker thread, as videos
  do, and hand over their MediaSource (`open_with_media()`). It has the night mode, dialogue boost and speed
  forwards. Up next (#34) does not count down between tracks; the next one starts at once.
- **Visualiser styles:** "bars" (the default), "mirror" (bars both ways from a middle line), "line" (one line through
  the bands with a faint fill), "radial" (spokes round a circle, low bands at the top, clockwise) and "off". The
  choice applies at once to the card showing and is kept in `[music] visualiser`.
- **API:** `MusicSource`: `is_music_path(p)`, `available()` (static), `title`, `artist`, `album`, `cover`,
  `levels()`, `STYLES`, `STYLE_NAMES` (names for the pane), static `style`. `main.features.visualiser()`,
  `main.features.set_visualiser(style)`. Factory: `is_music_file(path)`.
- **Settings:** `[music] visualiser` (default "bars").
- **Tested:** `tests/test_music.gd`, 12 checks, with WSLg and the fork, on the music clips of
  `make-feature-files.sh`.
  - Music extensions are media files.
  - An M4A opens as music, with its tags and cover. The card is the screen's picture, flat and shown, with the
    cover drawn on the left.
  - The audio is the clock, the visualiser hears it, seeking to 10 s works, and up next does not count down. The
    end is reported.
  - A WAV without a cover uses its name.
  - Visualiser styles (4 more checks): bars by default, five styles; read back from the card, "off" draws nothing in
    the visualiser's area and the other four draw there, each looking different; an unknown style is ignored.
  - `test_features`, `test_media_features`, `test_images`, `test_pane` and `test_delight` still pass.
- **Untested:** the headset, MP3 and Ogg (the tool build of FFmpeg cannot make test files), music over SMB and
  HTTP, and the Files tab's rows for music (app-shell's).

## #42 Auto letterbox crop

A 2.39 film stored in a 16:9 frame has black bars above and below. With the crop on, the flat screen shows only the
picture and grows wider to keep its height, as a cinema's scope screen does. A pillarboxed 4:3 picture loses its black
sides and keeps its height. The bars then take no room, and do not light the room (#29) or show in the floor (#62).

- **How:** the engine finds the picture (fork c318810fdd). `HWVideoSource.letterbox_detection` sets
  `MediaSource.letterbox_detection` before the file opens. A nice-10 thread then decodes a keyframe every 4 s of
  film and reports `get_letterbox()`. `scripts/play/auto_crop.gd` reads it every 0.5 s until the result is final.
  It snaps the picture's rectangle to the nearest cinema aspect within 2.5 % (1.33, 1.375, 1.43, 1.5, 1.66, 1.78,
  1.85, 1.9, 2.0, 2.2, 2.35, 2.39, 2.76), keeps it centred, and shows it with the screen's visible rectangle. The
  screen's size gets the crop's own aspect, times a width scale when "grow" is on.
- **3D:** side-by-side files take only the rows, so the bars above and below each eye go. Top-and-bottom files take
  only the columns. 180 and 360 pictures are never cropped.
- **Turning it on** while a file plays opens the file again at its place, because the detector starts when a file
  opens. Until the result is known, the whole frame shows. The first frames can widen it again if a later frame
  lights the bars (a logo or a flash): the engine leaves one outlier out from four frames on.
- **Engines without the detector:** the state says "Not available for this file" and nothing changes.
- **API:** `main.features.auto_crop`: `enabled`, `set_enabled(on)`, `grow`, `set_grow(on)`, `crop` (UV
  rectangle of the whole frame), `aspect`, `state()` returns `{enabled, detecting, known, bars, aspect, text}` for
  the footer, with text such as "Looking for bars", "Cropped to 2.39:1", "No bars". Static
  `crop_for(letterbox, layout, base_aspect)`. Signal `changed`. `HWVideoSource.get_letterbox()`.
- **Settings:** `[picture] auto_crop` (default off), `auto_crop_grow` (default on; off keeps the width and makes the
  screen shorter).
- **Tested:** `tests/test_auto_crop.gd`, 13 checks, with WSLg and the fork.
  - Maths: a picture slightly off 2.39 snaps back to it, centred. No bars, or not known yet, gives the whole frame.
    Side by side takes rows only. An aspect far from any cinema one is kept.
  - Playback, on High 10 I_PCM H.264 clips with exact 40-row and 80-column bars (the desktop decodes 10-bit H.264 in
    software): turning it on reopens the file and finds the bars, 2.35:1. The shader shows only those rows. The
    screen grows from 3.0 to 3.88 m wide at the same height; grow off keeps the width. Side by side still crops the
    rows. Off restores the whole frame and the size. The pillarbox clip crops the columns at the same height.
- **Untested:** the headset, real films (engine-demux's table in `spikes/03-player/README.md` has the detector's
  results on 16), the footer line (app-shell's), and the detector's CPU next to a 2160p hardware decode.

## #46 Trick play at 4x and 8x

Hold the thumbstick right to scan forward with pictures: 4x, then 8x after 2 s more. Let go and playback goes on, with
sound, from the picture on screen. A tap still skips 10 s, as before.

- **How:** the engine does the work (fork c318810fdd). `MediaSource.trick_play(speed, from)` with a speed of 2 to 64
  reads and shows keyframes only, at most one per 0.25 s of wall time, without audio. `HWVideoTexture` runs its
  clock at that speed. With an index (Matroska, MP4, AVI) it jumps from keyframe to keyframe. `trick_play(0, position)`
  goes back to normal playback. The engine's audio stream reports itself finished meanwhile, so
  `scripts/play/trick_play.gd` starts the AudioStreamPlayer again at the same place on the way back.
- **The stick:** main's stick handler asks trick play after the jog wheel (#63). A push past 0.75 first skips 10 s
  as before; held for 0.35 s, trick play takes over from the repeat seeks. Forward only: the engine has no reverse,
  so holding left still repeats 10 s skips back. Holding from pause plays.
- **Ends:** letting go, a seek from elsewhere (the pane's bar, a chapter), or a new file.
- **Not for:** live streams, still pictures, music, the lab, and engine builds without it. These keep the repeat
  seeks.
- **API:** `main.features.trick`: `enabled`, `set_enabled(on)`, `speed` (0 for normal playback), `available()`,
  `start(speed)` (2 to 64, for a pane button held down), `stop()`, `on_stick(hand, stick, delta)`, signal
  `changed(speed)`. `HWVideoSource`: `has_trick_play()`, `trick_play(speed, from)` (the new serial, or -1),
  `get_trick_play_speed()`.
- **Settings:** `[trick_play] enabled` (default on).
- **Tested:** `tests/test_trick_play.gd`, 19 checks, with WSLg and the fork, on a High 10 I_PCM clip at 10 fps with a
  beep track (`tests/pcm10_h264_avi.py`, run by `tests/make-feature-media.sh`).
  - A tap does not start it. Held, 4x moved 4.03 s of film a second with 4 pictures. Held on, 8x moved 8.02 s.
  - Let go: back at 1x, the audio running and in step 58 ms after the release, at most 15 ms off in the next 2 s.
  - `start(16)`, then a seek, ends it at the seek's place. From pause, the hold plays and scans. Off, the hold does
    nothing. A new file resets it.
  - `test_features`, `test_delight`, `test_pane` and `test_auto_crop` still pass.
- **Untested:** the headset's hardware decoder (engine-demux's checklist entry runs the engine alone), real films
  with long keyframe gaps, and the feel of the hold.

## Live streams

`udp://` streams and HTTP streams without a length play as they arrive, and can't seek. `udp://` is MPEG-TS in
datagrams: `udp://@:1234` listens on every interface, and `udp://239.1.1.1:1234` joins a multicast group. HTTP without
a length is, for example, a media server's live TV or a camera's MPEG-TS. The engine finds them live
(`MediaSource.is_live()`); the app only opens them and stands the seek features aside.

- **Opening:** `udp://` URLs now go to `HWVideoSource` and open on the worker thread, as smb:// and http(s):// do.
  A live open waits for the next keyframe. The playlist is the stream alone.
- **No seeking:** `HWVideoSource.can_seek()` is false for a live stream, and for HTTP from a server without Range
  requests. The features that seek already ask `can_seek()`. The playback controller ignores every seek on a live
  stream, a restart to 0 included. Trick play (#46) is off.
- **Latency:** `[network] live_latency`, 0.1 to 2.5 s, default 0.5, is given to `MediaSource.live_latency` before
  each open. The engine buffers that much audio before playing and after an underrun, and skips ahead when it falls
  more than twice that behind. Smaller is closer to live; larger rides out more jitter. Changing it while a live
  stream plays opens the stream again.
- **Without audio:** a file or stream with no audio track now has no audio stream in the player, and the video runs
  on its own clock. Before, the engine's empty audio stream stood the clock still, and a live stream without audio
  showed only its first picture.
- **Marker:** the overlay's feature line says "LIVE (0.5 s buffer)". The pane's LIVE marker and the hidden seek
  controls are app-shell's, from the API below. The line also says "scan 8x" during trick play.
- **API:** `main.features.live`: `live`, `latency`, `set_latency(seconds)`, `buffered()` (seconds of audio decoded
  ahead, or -1), `state()` returns `{live, latency, buffered, skips, text}` with text "LIVE" or "", signal
  `changed(live)`. Static `is_media_url(url)`: udp://, or http(s):// to a video or music file (.ts included), for
  the Open URL form to play instead of browse. `HWVideoSource`: `is_live()`, `is_stream_url(path)`, static
  `live_latency`.
- **Settings:** `[network] live_latency` (default 0.5).
- **Tested:** `tests/test_live.gd`, 17 checks, with WSLg and the fork. The test sends the trick play clip as MPEG-TS
  (video only, `make-feature-media.sh`) to `udp://@:47912` at its own rate.
  - URL rule: udp:// and http(s) media files play; web pages, a bare host and a scheme-less path do not.
  - Latency default, clamping, and given to the source.
  - The stream opens on the worker thread and plays, live with the marker. No audio stream, so the video's own
    clock runs. Can't seek and no trick play. Seeks forward, back and to the start do nothing, and it plays on at
    1x with no skips and no overruns.
  - A new latency opens it again, and the engine has the new value. A file after it is not live.
  - `test_features`, `test_pane`, `test_media_features`, `test_music`, `test_network_open`, `test_media_servers`,
    `test_hw_source_helpers`, `test_trick_play` and `test_auto_crop` still pass.
- **Untested:** the headset, a real multicast stream on the LAN, HTTP live from a media server, live streams with
  audio (the pre-roll and underruns), and the pane's marker (app-shell's).

## #44 Gapless playlist

When the queue goes on by itself (continuous play, or a `--dir` run), the next file opens 10 s before the current
one ends, on a second decoder session behind it. It takes over at the last frame, with no black and no wait. Meanwhile
the up-next card (#34) counts down to the end: "Up next: <name>", "Playing in 8 s".

- **How:** the engine does the change (fork 347778e84c). The next MediaSource opens on a worker thread. Then
  `HWVideoSource.chain_next()` opens its `HWVideoTexture` without playing, and `HWVideoTexture.set_next()` chains it.
  It decodes and holds its first frame. At the end, the two textures swap plane textures, so the screen's material
  shows the next file at the next draw without a parameter change. The next texture plays, and
  `main.adopt_next()` makes it the open file as `open_path()` would: `PlaybackController.adopt()` starts its audio
  with its first frame, and the old source closes. Every feature sees an ordinary file open.
- **No end in between:** the old file reports no end while a next item is chained, so the queue's end handling and
  the countdown after the end don't run.
- **The card:** seeks and pressing play don't cancel it. `Esc` or the card's cancel drops the next file; the film
  then stops at its end, and no countdown starts there. "Play now" opens the next file at once, as before.
- **Dropped when:** a seek back to more than 13 s before the end, another file opening, or turning it off. The
  prepared item's decoder buffers go with it.
- **Not for:** pictures (the slideshow), music, the lab, live and raw streams, repeat "one", a sleep timer set to the
  end of the file, the wrap of repeat "all", and engine builds without `set_next`. These end and go on as before.
- **Cost (engine-demux's figures on x86):** 27 to 103 ms to open, 40 to 70 MB more, 0.3 % of a core while it waits,
  3 to 5 ms for the swap. On the headset's hardware path, a second set of decoder buffers for up to 10 s.
- **API:** `main.features.gapless`: `enabled`, `set_enabled(on)`, `state` ("idle", "opening", "ready"),
  `next_path`, `next_for()`, `cancel()`, static `chainable(path)`, signal `changed(state, next_path)`.
  `up_next`: `following`, `follow(...)`, `set_remaining(s)`. `HWVideoSource`: `can_chain()`,
  `chain_next(path, result, host)`, `get_chained()`, `cancel_next()`, signal `next_started(next)`.
  `PlaybackController.adopt(source)`, `main.adopt_next(path, source)`.
- **Settings:** `[queue] gapless` (default off until the headset check: it opens a second hardware decoder session
  at the end of every file, and nobody has yet seen the headset run two at once; team lead, runbook E7).
- **Tested:** `tests/test_gapless.gd`, 20 checks, with WSLg and the fork, on two 14 s clips, one dark and one light
  (`pcm10_h264_avi.py` gap_a and gap_b, 10 fps, with a beep track).
  - Over 10 s before the end: idle. At 9.9 s left: ready, with the card counting down to the end. The next file's
    first frame was ready 26 to 30 ms after chaining.
  - The change: b took over by itself at the end of a, with no end reported and no countdown after it. The old
    source closed. Read back from the window every frame from 1 s before the end to 1.5 s after, the picture went from
    dark (0.149) to light (0.577) and was never darker than a. b played on with its own audio.
  - A seek into the window prepares it; a seek back drops it. Cancelling the card drops it, and the film ends and
    stays. Off: nothing prepared, and the countdown after the end as before.
  - `test_features`, `test_delight`, `test_pane`, `test_comfort`, `test_trick_play`, `test_live`,
    `test_media_features`, `test_music` and `test_images` still pass.
- **Untested:** the headset: the second hardware decoder session next to a 2160p film (memory and buffers), files on
  a share, files of different sizes or modes in a row, and how the change looks in the cinema room.

## #87 Picture in picture

A second film plays, silent, on a small screen in a corner of the main one. Swap puts it on the big screen with its
sound, and the film that was there goes to the corner. Both play on from where they were.

- **How:** a second decoder session (fork 347778e84c): its own MediaSource, opened on a worker thread, and its own
  `HWVideoTexture`. No audio track is selected on it (`select_audio_track(-1)`), so no audio is decoded or heard, and
  its texture runs on its own clock. It pauses and plays with the main film, and closes at its end.
- **The small screen:** a quad with the video shader, a child of the screen node, so it moves and sizes with the
  screen. It sits 2 cm in front, in a corner with a margin of 4 % of the screen's width. It is 0.3 of the screen's
  width by default. A stereo file shows its left eye. Colour matrix and range come from the file, as on the screen.
  In 180 and 360 it floats where the flat screen's corner would be.
- **Swap:** `PlaybackController.adopt()` with the old source kept (`main.adopt_next(path, source, true)`). The
  audio tracks switch over. The open-file bookkeeping runs for the swapped-in film (mode, subtitles, its other
  features). Resume (#7) leaves a film alone that is already playing past 0.5 s. The film then seeks back to the
  frame that was showing, because its audio track comes back from the demuxer's place, up to a second ahead.
- **Not for:** pictures, music, the lab and windows.
- **API:** `main.features.pip`: `open(path)`, `close()`, `swap()`, `state` ("", "opening", "playing"), `path`,
  `source`, `size`, `set_size(f)`, `corner`, `set_corner(c)`, `available()`, static `can_show(path)`, signal
  `changed(state, path)`. `PlaybackController.adopt(source, keep_old)` returns the old source when kept.
- **Settings:** `[pip] size` (0.15 to 0.5, default 0.3), `corner` ("top_right" by default, "top_left",
  "bottom_right", "bottom_left").
- **Tested:** `tests/test_pip.gd`, 22 checks, with WSLg and the fork. The big film is the trick play clip, and the
  small one is the light gapless clip.
  - Video files only. It opens and plays in the top-right corner at 0.3 of the width, inside the screen. It is
    silent, and the big film keeps the sound.
  - Read back from the window: the corner is light (0.839) over the big film (0.292).
  - It plays at 1x on its own clock, pauses and plays with the film, and moves to the bottom left at half the width.
  - Swap: the small film becomes the open file, and both materials follow. Both play on from where they were: 1.81 s
    to 2.91 s after 1 s, and 2.89 s to 3.82 s. The sound is the big screen's, in step. The big screen shows the light
    film. Swap back works.
  - Close: gone, and the film plays on. It closes by itself at its end.
  - `test_features`, `test_pane`, `test_delight`, `test_gapless`, `test_media_features`, `test_trick_play`,
    `test_auto_crop` and `test_live` still pass.
- **Untested:** the headset: two hardware decoder sessions at once (a 2160p film with a 1080p one in the corner),
  memory, and the pane's controls (app-shell's).

## #40 Seek-bar thumbnails

While the seek bar is hovered or scrubbed, a small picture of the film near that time (on the tablet's time
bar since the front panel went, 2026-11-06: where the laser is on it, or where it is dragged, `ui/tablet.gd`). Off by default until the
headset's memory is checked: a second set of decoder buffers is about 150 MB at 2160p.

- **How:** a second decoder session on the open file (fork 347778e84c): its own MediaSource, opened on a worker
  thread with no audio track, and its own `HWVideoTexture`. For a time, `MediaSource.trick_play(2, t)` jumps to the
  keyframe at or before it. The texture shows that frame and pauses. The frame is drawn once into a small viewport with
  the video shader, read back, and kept as an `ImageTexture`, 256 pixels wide at the film's aspect. Stereo files show
  the left eye.
- **Throttled:** one picture at a time; the newest request wins. A request within 0.5 s of a cached one uses the
  cache. The last 24 pictures are kept, and `thumbnail_for(t)` returns the nearest within 6 s.
- **The session** opens on the first request for a file. It closes after 20 s without one, on another file, or when
  turned off. Not for live streams, pictures, music or the lab.
- **Engine note:** a jump right after the session opens lands late (on the clip, at 7 s for a request at 3 s). So the
  session first shows its first frame, then jumps. A frame after the requested time is never kept.
- **API:** `main.features.thumbs`: `enabled`, `set_enabled(on)`, `request(seconds)`, `thumbnail_for(seconds)`,
  `size`, `state` ("off", "idle", "opening", "warming", "ready", "grabbing"), signal
  `thumbnail_ready(seconds, texture)` (the keyframe's time).
- **Settings:** `[thumbnails] enabled` (default off).
- **Tested:** `tests/test_thumbnails.gd`, 13 checks, with WSLg and the fork, on the trick play clip, where a bright
  column moves a step each second, so the picture says which second it shows.
  - Off by default, and a request then does nothing. On, it is idle until asked.
  - 3 s: keyframe 3.0, 66 ms with the session's open, 256 x 153, the column at second 3. 7.5 s: second 7, 36 ms.
    Near times share a picture, and far ones have none.
  - Three requests at once (20, 40, 55 s): only 55 s was grabbed, showing second 55.
  - The film played on meanwhile with its sound, A/V in step. Another file closes the session and clears the cache.
  - Passed three runs in a row. `test_features`, `test_pane`, `test_pip`, `test_gapless` and `test_bias` still pass.
- **Untested:** the headset: memory and decoder buffers next to a 2160p film, keyframes far apart (seconds of GOP),
  files on a share, and the pane's picture over the seek bar (app-shell's).

## #94 Crossfade between items

When the queue goes on by itself (continuous play, or a `--dir` run), the next item can start a few seconds before
the current one ends, so the two overlap. Its sound comes up as the current one's goes down, and its picture fades in
over the screen. Music tracks and videos each have their own length. Pictures in a slideshow already crossfade by
themselves (#22, `[images] crossfade`).

- **How:** the next item opens on a worker thread 2 s before the fade, as a second session (fork 347778e84c for
  videos). It plays into a second `AudioStreamPlayer` on the same bus, and this node updates it with that player's
  clock. The sound crosses at equal power (cosine and sine). Its picture is on a quad 1 cm in front of the screen,
  drawn by `shaders/video_fade.gdshader`: the screen's own conversion with an alpha. For music, that is the next
  track's card. 0.2 s before the end, `main.adopt_next()` makes it the open file, as the gapless change does, and it
  carries on from where its fade got to. The outgoing item holds its end meanwhile (`hold_end`), so it can't end
  first.
- **Videos:** the up-next card counts down to the end, as with gapless. With a video crossfade set, the gapless
  change (#44) stands aside.
- **Dropped when:** a seek back out of the window, another file opening, or the next item not opening in time (the
  film then ends and the queue goes on as before). Pause and play follow the film.
- **Not for:** music into video or the other way, repeat "one", a sleep timer at the end of the file. In 180 and 360
  only the sound fades.
- **API:** `main.features.crossfade`: `music_seconds`, `set_music_seconds(s)` (0 to 12), `video_seconds`,
  `set_video_seconds(s)` (0 to 10), `active`, `progress` (0 to 1), `next_path`, `plan()`, signal
  `changed(active, next_path)`. `hold_end` on `HWVideoSource` and `MusicSource`.
- **Settings:** `[crossfade] music`, `videos` (seconds, default 0: off). Off by default because many albums are
  meant to run on without a gap.
- **Tested:** `tests/test_crossfade.gd`, 14 checks, with WSLg and the fork; passed twice in a row.
  - Off by default, and clamped.
  - Music, 4 s, WAV into FLAC: the next track opens 6 s before the end. Halfway, -2.4 and -3.7 dB, both playing.
    The FLAC took over without an end at 3.75 to 3.94 s, then at full volume with one player.
  - Videos, 3 s, the dark clip into the light one: crossfade instead of gapless, with the up-next card. Read back
    halfway, the screen was 0.438 to 0.441, between dark (0.149) and light (0.577). b took over without an end at
    3.3 to 3.4 s, the overlay gone, full volume, A/V in step. A seek back drops it.
  - `test_features`, `test_pane`, `test_delight`, `test_music`, `test_gapless`, `test_pip`, `test_thumbnails`,
    `test_trick_play`, `test_media_features`, `test_images` and `test_live` still pass.
- **Untested:** the headset: two hardware sessions during a video fade, how the fade looks in the cinema room, and the
  pane's controls (app-shell's).


## Hardware 10-bit video

10-bit HEVC, HDR10 included, plays in hardware with the stock driver: the engine reads the decoder's compressed
10-bit output (Q10C) through the GPU's YCbCr sampler (docs/decisions.md D14). On 2026-10-31 this played 720p, 1080p,
2160p SDR and 2160p HDR10 10-bit files in hardware on the device, bit-exact against FFmpeg, with no setup. When the
system's decoder driver offers linear P010 (mainline Linux 7.2 does, so a later SteamOS kernel will), the engine takes
P010 first. Without either, 10-bit up to 1080p plays in software and larger files are refused with a reason. Nothing
is set up and nothing asks for a password: the patched driver and its one-time setup were removed on 2026-11-02
(docs/decisions.md D21).

- **How:** `scripts/play/hw_video.gd` only reads what the engine found. At start, once the pane is up, it reads the
  decoder's formats once on a worker thread (`V4L2Decoder.is_p010_available()`, which the engine keeps; a 10-bit
  stream's own format list wins later). `q10c_available()` asks `DmabufImage.is_q10c_available()`, which turns false
  for the rest of the run after a failed Q10C import or picture check. The order is the engine's
  (`HWVideoTexture.open_source()`): P010, then Q10C, then software.
- **What the user sees:** the System tab's Hardware video row: "Hardware 10-bit video: on (P010 from the system's
  video driver)", "on (Q10C through the GPU, stock driver)" or "off: 10-bit plays in software", with Details (P010
  offered, Q10C read, why Q10C turned off in this run, the decoder's formats, hardware VP9). The overlay says
  `hardware (10-bit)` while a 10-bit file plays in hardware. There is no card and no toast.
- **API:** `main.features.hwvideo`: `status()` (`{path, text, p010, q10c, q10c_off_reason, decoder_formats,
  hw_vp9}`; `path` is `p010`, `q10c`, `software`, or `unknown` before the look at start), `path()`, `summary()`,
  `p010_available()`, `q10c_available()` (static), `decode_text(kind, info, stats)` (static), `probed`, signal
  `changed`. Dev link and assistant: `hwvideo_status` (read, no parameters).
- **Settings:** `[hwvideo] hw_vp9` (true). The setup's `[hwvideo] iris_bundle` and `iris_setup_prompt` are ignored
  when an old settings file still has them.
- **Tested:** in WSL with the fork's x86_64 build (no decoder there, so the path is `software`).
  - `--ui-test` (10 checks): the status and the System row's words, P010 before Q10C, Details, no Set up, Remove the
    setup or password field anywhere in the pane, the overlay's decode text, the read command, and the dev link's
    rule for a masked field.
  - `tests/test_assistant_coverage_system.gd`: `hwvideo_status` answers with the path, an assistant reads it, and
    `hwsetup_status` is gone.
- **Untested:** the headset: the row and the log line on the stock driver (expect "on (Q10C ...)"), and on a kernel
  that offers P010.

## Every format: old and other codecs in software

A 2000s DivX AVI used to show the test pattern with "MPEG4 video can't be decoded in hardware ... can't be decoded in
software here (H.264, HEVC and VP9 only)". 62 % of the library was like that. Now every format FFmpeg can decode
plays, with no licence fees paid (`docs/decisions.md` D18, which also has the licence and patent notes).

- **How:** the engine's FFmpeg has every decoder, demuxer, parser and bitstream filter, swscale, and dav1d for AV1
  (`build/ffmpeg-build.sh`, `build/dav1d-build.sh`; engine branch `frame/codecs`). H.264, HEVC and VP9 still decode
  in hardware. Everything else decodes on the CPU (`SoftwareVideoDecoder`, frame threads), up to 1920 x 1088 (AV1:
  4K at 30 fps), and shows through the same shader. Pictures that are not 8-bit 4:2:0 (palette, RGB, gray, 4:2:2,
  4:4:4, 10-bit 4:2:2) are converted by swscale to the matrix and range the shader uses.
- **Formats.** Video: MPEG-4 part 2 (DivX 4/5, Xvid, MP4V), DivX 3 (MS-MPEG4 v1-v3), MPEG-1, MPEG-2 (DVD, SVCD, TV),
  H.263, Flash H.263, VP6, WMV 7/8/9, VC-1, RealVideo 1-4, Theora, VP8, AV1, MJPEG, DV, ProRes, Cinepak, Indeo and
  the rest of FFmpeg's decoders. Audio: everything FFmpeg decodes (WMA, Cook/RealAudio, AMR, ADPCM, AC-3, MP2, Opus,
  Nellymoser, ...). Containers: AVI, DivX, ASF/WMV, RealMedia, FLV, MPEG-PS/VOB, MPEG-TS, MXF, NUT, Ogg, Matroska,
  MP4/MOV/3GP, WTV, NSV, DV and more.
- **The file browser** lists `.avi .divx .xvid .vob .mpg .mpeg .mpe .m1v .m2v .mpv .wmv .asf .rm .rmvb .rv .flv .f4v
  .ogv .ogm .3gp .3g2 .mxf .nut .m2ts .mts .m2t .ts .tp .trp .webm .mov .qt .dv .dif .wtv .dvr-ms .nsv .ivf .y4m .mjpg
  .amv .bik .smk .nuv .evo .vro .mk3d .obu .h263 .vc1` beside the earlier ones
  (`scripts/video/video_source_factory.gd`; the engine's `MediaLanguages.is_video_extension()` and the DLNA list
  have the same list).
- **Timing of old containers.** AVI's frame-counter timestamps, DivX 5's packed B-frames, MPEG-PS frames without a
  PTS, and variable frame rate all come out in order at the right times. Seeking works in files without an index
  (by bytes) and in AVIs that lose their keyframe flags after a seek.
- **Aspect and interlacing.** Anamorphic DVDs (16:9 at 720x576), SVCD (480x480 shown 4:3) and other non-square
  pixels get the right screen shape, as before through `sample_aspect_ratio`. DVDs and TV recordings report their
  field order, so deinterlace "auto" (#95) turns on for them.
- **Overlay:** the decode path names the codec when only software decodes it: `software (DivX 3)`, `software
  (MPEG-2)`, `software (AV1, 10-bit)`.
- **What is refused,** with the reason on the stand-in: a video beyond the size limit ("1920x1080 AV1 at 120 fps is
  too much to decode in software on the Frame (up to 3840x2176 at 30 fps, 2560x1440 at 60)."; "3840x2160 MPEG-2 video
  is too large to decode in software on the Frame (up to 1920x1088).") or a codec FFmpeg doesn't know.
- **API:** `MediaSource.get_video_info()` adds `codec_long_name`, `codec_tag` (the FourCC), `codec_display_name`,
  `software_unsupported_reason`, `software_max_pixels` and `video_filter`; `get_stats()` adds `keyframes_guessed`.
  `HWVideoTexture.get_stats()` on the software path adds `software_pixel_format`, `software_conversion`,
  `software_frames_converted`, `software_field_order` (the decoder's view), `software_frames_interlaced`,
  `software_frames_hidden` and `software_frames_guessed_time`.
- **Settings:** none. `HWVideoTexture.software_max_pixels` (1920 x 1088) still sets the limit for every codec but AV1.
- **Tested:** in WSL with the `frame/codecs` x86_64 build, xvfb and lavapipe (`spikes/03-player/demux-test/
  codecs-tests.sh`; clips from `make-codec-files.sh`). For each file: the codec, size, pixel aspect and field order
  from `get_video_info()`, the audio track decoding to sound, playback on the software path at the decoded size with
  frame times only rising in steps of one frame, the colour of a flat area read back from the textures (clips: within
  8 of the encoded Y'CbCr), and a seek landing within 0.2 s.
  - 27 clips: Xvid with B-frames, DivX 3, MS-MPEG4 v2, MPEG-1 + MP2, interlaced 16:9 MPEG-2 VOB + AC-3, H.263 + AMR
    in 3GP, WMV 7 + WMA 1, WMV 8 + WMA 2, MPEG-4 in ASF, FLV1 + MP3, FLV1 + Nellymoser, RealVideo 1 and 2, Theora +
    Vorbis, VP8 + Opus, AV1 1080p and 720p 10-bit + Opus, MJPEG 4:2:2 + IMA ADPCM, Cinepak (RGB) + mu-law, MS Video 1
    (RGB555) + 8-bit PCM, HuffYUV 4:2:2, ProRes 4:4:4 10-bit + 24-bit PCM, FFV1 gray at 351x239 + FLAC in NUT, PNG
    with a palette, DV PAL (bottom field first), MPEG-2 in MXF, VFR MPEG-4 in Matroska.
  - 21 real files from the library, read in place: DivX 5 680x560 (the AVI that failed before), Xvid, Xvid + AC-3,
    DivX 4 720x576, a `.divx` at 30 fps, DivX 3 + WMA and + MP3, MPEG-4 in MP4, FLV1 in AVI, FLV, RealVideo 4 + Cook,
    WMV 8 + WMA 2, MPEG-1 (49:33 pixels), interlaced 16:9 MPEG-2 PS, SVCD, two DVD VOBs (bottom and top field first)
    with AC-3, MPEG-2 1080i in TS, an H.263 camera MOV, VC-1 1080p (Blu-ray remux), H.264 in AVI.
  - Decoding flat out on the PC's CPU (x86, FFmpeg without its assembly, lavapipe drawing too; not the headset's
    speeds): SD MPEG-4, DivX 3, MPEG-1/2, WMV, FLV1 and RealVideo 500 to 1500 fps; MPEG-2 1080i 254 fps; VC-1 1080p
    85 fps; AV1 1080p 555 fps; ProRes 720p 150 fps.
  - Unchanged paths on the same build: `run-tests.sh` (13 files, `test.gd`), `vp9_test.gd`, `features_test.gd` (550
    checks), and the app's `test_video_mode`, `test_hw_source_helpers`, `test_media_servers`, `test_media_features`,
    `test_hdr` and `test_picture` all pass. `--ui-test` passes its new check (the overlay's codec names); its 3
    other failures (the dev card command, push-to-talk) fail the same way on the `frame/player` engine.
  - The arm64 build opens AV1, Xvid, RealVideo + Cook and WMV under `qemu-aarch64-static`.
- **Known:** FFmpeg's Theora decoder rejects the inter frames of what libtheora 1.2 encodes (the PC's ffmpeg, the
  test clip): only its keyframes show. Whether older Theora files decode fully is not tested; the library has none.
  MPEG-2 with mostly progressive pictures in an interlaced stream (film in a 1080i broadcast) can report a field
  order, so "auto" deinterlaces pictures that are progressive (softer, not broken).
  No WMV 9 (WMV3) file was at hand (FFmpeg decodes it with the VC-1 decoder, tested).
- **Untested:** the headset: decode speed and power on its CPU (DivX at SD should be a few percent of one core; VC-1
  and MPEG-2 at 1080 and AV1 at 4K are the ones to watch), and audio sync of these files over a whole film.

## Agents on the headset

Claude Code and Codex running on the headset itself, in a real terminal shown on a pane on the pointer controller,
while the film goes on. The full description, with the security notes, is in `docs/assistant.md`, "Agents on the
headset".

- **What it does:** Files has an entry per agent: start it briefed on the player or plain, show it, hide it, or put it
  on the big screen. Talk shows the pane and types what you say into the terminal. A hook adds what you are watching
  to each message. Prompts are answered by voice, or with the stick and trigger while one waits. The agent has a link
  to the player already: its token is in `.assistant-link` in its folder, and picking the entry is the consent. An
  agent that is not installed gets a card first. The terminal survives film changes and player restarts.
- **Settings:** `[assistant] voice_to` also takes `claude` or `codex`. Constants: `AgentTerminal.COLUMNS`, `LINES`,
  `FONT_PX`, `AgentPane.PANE_WIDTH_M`. The room and control switches of the assistant apply.
- **API:** `main.local_agents` (`scripts/agents/local_agents.gd`): `open_agent(id, plain)`, `show_on_screen(id)`,
  `set_active(id)`, `hide_pane()`, `toggle_pane()`, `running()`, `active`, `pane_shown()`, `waiting()`,
  `deliver(text)`. The table of agents and what is on disk are in `scripts/agents/agent_terminal.gd`, the pane in
  `ui/agent_pane.gd`.
- **Tested:** `test_local_agents` (129 checks) against a stand-in for the X display. `test_assistant` pairs a local
  agent. `test_agent_terminal_live` with a real xterm under Xvfb, a script standing in for the agent, and lavapipe: 10
  checks, and 3 more after a restart of the player. `test_pane`, `test_features`, `test_assistant_fetch` and
  `test_assistant_places` still pass.
- **Untested:** the headset, and the real Claude Code and Codex (the hooks, real prompts, sign-in). See `docs/assistant.md`,
  "Not done yet".

## The Library

A local shelf on the headset, `~/Videos/Library`, shown in Files as posters, seasons and episodes. The full description is
in `docs/library.md`; D19 records why this replaced "no library" in D11.

- **What it does:** the place reads Kodi's NFO files beside the videos and shows shows and films as a poster grid, a show's
  seasons, and episodes as rows with thumbnail, number, title, short plot and what was watched. A folder with no NFO is a
  plain folder. The overlay and `/state` use the NFO's title, and next and previous follow the season. Agents and
  assistants fill it, from a share with `copy_to_library`.
- **Settings:** none. Watched comes from `user://resume.cfg`; pictures are cached in `user://library_cache/`.
- **API:** `scripts/library/`: `LibraryIndex.read(path)`, `title_for(path)`, `details_for(path)`, `playlist_for(path)`,
  `LibraryNfo.read(path)`, `LibraryImages.request(path, size, callback)`, `LibraryCopy.start(from, to)`. Drawn by
  `ui/library_view.gd` in `ui/files_tab.gd`.
- **Tested:** `test_library` (115 checks) and `test_library_view` (5, with lavapipe). Building the poster wall took 2 to 3
  ms on the main thread, and the worst frame while it opened matched the worst frame with nothing happening.
- **Untested:** the headset, and `open_read` against a real SMB server. See `docs/library.md`, "Not done yet".

## Android apps

An Android app (an APK) in a window on the big screen, with one click, shut down fully when you leave. Valve's Lepton, a
Steam tool, runs the APK in a podman Android 11 container, as the normal user. Lepton is a compatibility layer made for
games, so video in an Android app may be limited.

- **What it does:** each folder `~/Android/<name>/` holding an `.apk` is a row in the Android apps place in Files. One
  click starts a nested compositor, because Android draws to a Wayland socket and the capture is X11, then the container,
  then the app. The card and the rows show each step, read from Lepton's log as it grows, with Cancel. A start has a time
  limit, and a failure gives the log's last useful line. Once up, the window goes on the big screen as a `window://`
  source and the panel closes. The pointer works it like any window. B is Android Back, with a fallback (below).
- **Leaving stops it:** this is the design. When the window stops being the big screen's source for any reason, the app,
  the container and the compositor all stop, with the steps on the card and nothing keeping on behind. The app looks at
  the source on a timer rather than waiting for `file_opened`, because a file on a share takes the source away seconds
  before that comes. Opening something else while an app is starting cancels the start. One app at a time: starting
  another stops the first.
- **The stop:** `~/Android/.player/stop.sh`, in a `systemd-run --user` unit of its own, so it finishes if the player has
  gone. It force-stops the app, which keeps a login in `~/.local/share/lepton/contexts/`, waits for the unit to end, falls
  back to `systemctl --user stop`, then stops the compositor. The player's exit starts it and doesn't wait. A crash leaves
  the marker file `~/Android/.player/running`, and the next run of the player clears up, as does the next start.
- **Setup:** none by hand. The app creates `lepton-show-flatscreen` in the APK's folder, because Lepton hides its flat
  window without it, and writes `display.sh`, `run.sh` and `stop.sh` in `~/Android/.player/` (mode 700), with the logs. It
  doesn't rename your files: an APK with spaces in its file name is listed with a note and can't run yet.
- **Settings:** none. Limits in `AndroidApps`: `start_timeout` (180 s), `display_timeout` (20 s), `stop_timeout` (45 s).
  The window's size: `Lepton.WIDTH`, `HEIGHT`.
- **Privacy:** nothing reads the app's data. Of `lepton exec` output, only the one line asked for is used. A log line
  shown as a reason is one short line, and a line holding a word such as password, token or cookie is never shown. The
  window stays out of the room snapshots for assistants, as an agent's terminal does. The dev link's screenshots show it.
- **The assistant:** left out. It may not open a captured window (`open_refusal`), so the assistant link can't start an
  app. Opening a file through it does stop one, as any other new source would.
- **API:** `main.android_apps` (`scripts/android/android_apps.gd`): `start_app(name)`, `cancel()`, `stop_app()`, `back()`,
  `status()`, `on_big_screen()`, `state`, `step`, `last_error`. What is on disk, the scripts, the commands and the log are
  in `scripts/android/lepton.gd`. The dev link has `android_status`, `android_start`, `android_stop` and `android_back`
  (control level, so the phone remote can use them too).
- **Tested:** `test_android_apps` (245 checks) with stand-ins for the commands and the window capture. It runs the real
  `stop.sh` against stand-in `systemctl` and `lepton` programs. `test_local_agents` and `test_features` still pass.

### What is proved and what isn't

Proved by hand on the headset, as the normal user: Lepton running an APK, `lepton-show-flatscreen`, the nested compositor
giving an X window, `systemd-run` for the start, the log's lines in order, bringing the app forward, and force-stop keeping
the login. `--activity-clear-top` left a full-screen player.

**Not yet run on the headset:** all of this feature as the app runs it. In particular:

- **B is unverified.** It is unknown whether input injection works here at all: on a full-screen player, `sh
  /system/bin/input keyevent 4` and an X Escape key both showed no effect, which may be the injection or the app. So B
  sends Back, compares the `ResumedActivity` line before and after, and if it didn't change, starts the app's launcher
  activity with `--activity-clear-top`. The commands are all in `Lepton.back_now()`, to adjust after a real test.
- The pointer on the nested window: that kwin takes the capture's clicks and scrolling.
- `lepton exec` from the player, with no terminal. It may need `IS_PARENT=true`, as `lepton start` does.
- That the container goes when `systemctl --user stop` is the way the unit ended, not force-stop.
- That the compositor's window doesn't take the desktop's focus from a paired keyboard.
- A folder under `~/Android` with spaces in its name is quoted by our scripts, but Lepton's handling of it is untested.

## The material library

- **What:** 42 CC0 texture sets (Poly Haven, ambientCG) for room surfaces: wood floors and parquet, carpet, velvet,
  upholstery, leather, plaster, concrete, brick, marble and tiles, metals, felt, acoustic foam, wicker. Each is a
  catalogue entry (`app/materials/<id>.json`: name, tags, tiling in metres, tunables, source) and three maps
  (base colour, normal, ambient occlusion / roughness / metallic) stored as ASTC 8 x 8 with mip levels, which the
  headset's GPU samples as they are: no import step, no compression on the device. About 52 MB in the repository.
- **Look:** `shaders/room_material.gdshader` keeps the rooms' fake light (ambient plus the screen's spill, no lights or
  shadows) and adds the maps' detail: relief from the normal map, ambient occlusion, a soft highlight from the screen,
  sheen on fabrics, pleats for curtains. Box projection in metres (one fetch per map); mesh UVs or triplanar on demand.
- **Rooms:** the cinema (felt walls, carpeted tiers, velvet seats, a wooden stage, new pleated curtains), the home
  theatre, the dim room's walls, the planetarium's seats and floor and the dome's platform, in their old colours.
- **API:** `scripts/env/material_library.gd`: `list()`, `entry(id)`, `get_material(id, options)`,
  `apply(mesh, id, options, surface)`; the `materials` command (read). Details, the cost and how to add a material:
  `docs/materials.md`; credits: `app/materials/CREDITS.md`.
- **Tested:** `test_materials` (33 checks); renders before and after in `docs/shots/materials/` (lavapipe). Not yet
  run on the headset.

## Effect library

About forty procedural looks a surface can name by id: energy (plasma, aurora, force field, neon...), natural (water,
lava, embers, smoke, caustics, wind sway...), procedural materials (pearl, velvet, brushed metal, marble, crystal...),
stylised (hatching, halftone, pixel, wireframe, stained glass, duotone), transitions (dissolve, wipe, scan-in, a
selection outline), reactive (the film's sound and colours) and skies (aurora, stars, nebula, sunset, cloud layers).
Each has a description written for an assistant to choose by, bounded options, a measured cost tier, how it animates
(always under the photosensitivity ceiling) and a preview in `docs/shots/effects/`. The assistant reads them with
`effects` and `effect_info`; a room names one once the room document is connected to the library. All of it, with the
performance and photosensitivity rules and how to add an effect: `docs/effects.md`.

Untested: on the headset (each effect's cost there, and how the slow motions read in the lenses).

## Controller look

- **What:** how both controllers look, from presets: the black plastic they come in (the default); plastics (white,
  graphite, red, blue, and any colour); metals from the material library (brushed steel, dark metal, brass: the
  library's picture three ways in the part's own space, a made-up studio reflected); and effects from the effect
  library that suit a held object: plasma (two colourways), embers, circuit, neon, starfield, liquid chrome, iridescent
  and carbon fibre, sized for a hand-held shell, their options (colour, speed, ...) within the library's bounds and
  its photosensitivity ceiling. Chosen as opaque, one-pass effects drawn in the part's own space that read as a
  material at 10 cm; left out: the see-through ones (overdraw, and a see-through controller), the transitions (they
  cut the part away), the room-sized ones (aurora, water, lava, clouds, nebula, marble: their sizes don't go small
  enough), the stylised and reactive ones and the first eight (their shader has no print hook). One setting for both
  hands. Code: `scripts/xr/controller_look.gd` (the presets, the print style), `controller_visual.gd` (`set_look`).
- **Where:** the look goes on the shell (the body and the battery door) of the runtime's model, our own model and the
  hand-built body; buttons, stick, trigger and grip stay black with their moulded art white. Black puts each model's
  own material back.
- **Legible print:** on a plastic or a metal the ink is white or near-black, whichever stands out more from the
  darkest and brightest the shell gets under the controllers' fake light; below 4.5 : 1 against either, the letters
  also get a backing in the other colour. On an effect they always get it: white ink, a near-black outline (18 : 1).
  The print on the runtime's model draws the outline from its distance field (`controller_label.gdshader`
  `backing_width`, the same four samples); our model's legends, which are in its texture, take the ink over the look
  and a halo from a coarser mip of the texture (`controller_print.gdshaderinc`, in the model shader and, with
  `FX_PRINT`, in the effect shaders). A print on a part that keeps its black stays white.
- **Cost:** the look replaces the shell's material: no draw call or pass is added, nothing runs per frame in GDScript
  (effects animate by the shader's clock). Plastic: the default shader. Metal: three texture reads more. Effects:
  their measured tier over a plain surface (plasma 1.24, liquid chrome 2.04, circuit 2.26, embers 2.6, iridescent
  1.72, starfield 0.9, neon 0.5; carbon fibre 3.5, medium), on the few per cent of the view the controllers cover.
  The first choice of an effect compiles its shader once (a short hitch).
- **Controls:** System tab, Controllers, Look: a button per preset with its swatch or the effect's preview (the
  controllers in your hands are the preview), and for a look that takes them a colour palette and Speed.
- **Assistant:** `controller_looks` (read: the presets, their options and bounds, their cost) and `controller_look
  {look, options}` (settings), which validates the look and every option against its bounds and can be undone;
  `system_settings` names the look on show.
- **Tested:** `test_controller_look` (612 checks headless, 647 with a renderer: every preset builds and draws on each
  model, options and bounds, the print's contrast on every preset and on any colour, the shell only, the setting's
  round trip, the command). Not yet seen on the headset.

## Showrooms

Rooms that ship with the app to show what the room system can do: the Effects gallery (every effect on a sphere, by
group), the Material wall (every library material on a panel and a sphere), Objects (shapes, text, surfaces and
pictures, every widget, motion, the built-in objects), Lights (the key light with shadows, sky fill, the film's
light, a point and a spot light) and one room per sky. Each sample has its name beside it. They are plain room
documents, made from the libraries by `app/tools/showrooms.gd` (run it again when a library grows), read-only under
`app/environments/showrooms/`, and listed in the Room tab under **Showrooms** (ids `showroom:<id>`, so
`set_environment` and `--env` take them too). Each keeps a budget for a mobile GPU (100 cost units, 150 draw calls,
250 000 triangles, 16 text parts); a room that would go over is split. Particles are left out for now.

- **Measuring:** the dev link's `perf_rooms` shows each showroom in turn at each foveation level and returns the GPU
  time of each, against the void (`app/scripts/assistant/room_perf.gd`); the steps for the headset are in
  `docs/showrooms.md`.
- **Also:** a room's sky sphere is now 180 m, inside the cameras' 200 m far plane (it was 400 m, so a room's sky
  only showed in snapshots).
- **Tested:** `tests/test_showrooms.gd` (every document valid and within the limits, every effect, sky, material,
  built-in object, part type, widget and motion shown, the labels level with their samples, the files as the tool
  makes them, each built in the main scene, the Room tab's group, `perf_rooms`). Rendered in WSL with lavapipe.

Untested: on the headset (the GPU cost of each, how the labels read in the lenses).

## Object physics

Any object from the object library can be picked up with a controller (the laser, or the hand in it), held, turned,
dropped or thrown; it bounces off the room's seats, steps, walls and floor and off the film's screen in every shape,
comes to rest and stays there, kept with the room. Put back and Tidy up return objects to where they were placed. A
wall object stays on its wall until pulled off. A text or particles area can follow an object (attach and offset).
One thud, made in code, plays where an impact happens, through the spatial audio. The design, the controls, the
numbers and the open questions are in `docs/physics.md`.

- **API:** `main.features.physics` (`app/scripts/play/object_physics.gd`): `available()`, `aim()`, `near()`,
  `pick_up()`, `hold_to()`, `let_go()`, `cancel()`, `throw()`, `settle_all()`, `state()`, signal `changed`;
  `main.features.grab` (`object_grab.gd`): the controllers, `holding(hand)`, signal `changed` (the legends).
- **Commands:** `object_put_back`, `object_tidy_up`, `object_attach`, `object_throw`, `object_physics`.
- **Engine:** Jolt (`project.godot`); the moving objects interpolated to the frame by the feature itself.
- **Tested:** `tests/test_physics.gd` (66 checks), on the desktop.

Untested: on the headset (the feel of a throw, the trail of a held object, the thud through the earbuds, the step's
cost on the Frame's cores with a 4K film decoding).

## The browser: stick pointer and voice into a field

Two ways to work the browser on the big screen without the laser or a keyboard. The details, the numbers and the
open questions are in `app/docs/window-source.md` ("Controller mapping", "Voice into a field").

- **The stick pointer.** While you look at the screen (eye gaze, else the head's direction), the right stick moves a
  cursor over the page, and the trigger clicks there. A squeeze tap is a right click. Squeeze held with the stick
  scrolls and sends the arrow keys.
  - When you look away, the cursor is not drawn, and the stick scrolls and sends the arrow keys as before.
  - Pointer mode starts after 0.1 s of gaze on the screen (with a 5 % margin) and ends after 0.4 s of gaze off it. A
    pushed stick or a held trigger keeps it on.
  - The cursor appears where you look. It jumps to your gaze when your gaze rests far from it (over 10 % of the width,
    for 0.15 s, with the stick still): `[browser] pointer_follows_gaze`, on by default.
  - The stick has a curve: small tilts aim finely, and full tilt crosses the page in one second.
  - The cursor is drawn into the picture by the screen's shader (`video_common.gdshaderinc`), so the film layer
    shows it too. It fades in and out in 0.1 s.
  - The laser is off on a window by default. `[browser] laser` brings it back as an alternative.
  - The legends follow the mode.
- **Voice into a field.** With a text field selected on the page, the talk button (the pointer hand's bumper)
  transcribes on the headset and types the text with DevTools `Input.insertText` (any Unicode).
  - While you hold the button, the field glows and the live words show under it. Both go on release, on a cancel and
    on a page change.
  - A password field is refused.
  - With no field selected, the talk button goes to the assistant as before.
  - Fields in cross-origin iframes are reached through the frame's own DevTools session.
  - Without DevTools, `browser_insert_text` types into whatever has focus through the window's own text input.
- **Commands:** `browser_pointer`, `browser_field` (never the field's contents) and `browser_insert_text`, for the dev
  link and the assistant.
- **Files:** `scripts/window_pointer.gd`, `scripts/video/stick_cursor.gd`, `scripts/video/browser_dictation.gd`,
  `scripts/video/devtools_session.gd`, `scripts/video/page_field.gd`.
- **Tested:** `tests/test_browser_pointer.gd` and `tests/test_browser_dictation.gd` (a fake DevTools page on the
  loopback, and the page script in a stand-in DOM under Node), on the desktop.

Untested: on the headset (the feel of the gaze switch and the jump, the cursor's size in the lenses), and in a real
Chromium (the page script, cross-origin frames, `Input.insertText` into the focused frame).
