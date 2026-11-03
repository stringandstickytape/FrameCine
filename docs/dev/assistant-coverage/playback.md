# Assistant coverage: playback, Picture, Sound, Subtitles

Every control of the transport and the Picture, Sound and Subtitles tabs, and the command an assistant uses for it.
The level is the command's `assistant` tag in the registry (`scripts/dev/dev_commands.gd`); the consumer whitelist,
`/describe`, the guide and the MCP tools come from it. A control is covered when its command does what the control
does, through the same feature call.

The new commands are in `app/scripts/dev/playback_tab_commands.gd`. Each tab has one read (`picture`, `sound`,
`subtitle_settings`; `playback` for the transport's extras) and section setters whose params are all optional: give
the ones to change. A setter refuses a value outside the tab's own range (it does not clamp), syncs the tab, sets the
toast, and its undo puts back every value it changed. Test: `app/tests/test_assistant_coverage_playback.gd`.

Commands marked (core) are registered by the core agent (`state`, `tracks`, `audio_track`, `subtitle_track`,
`volume`, `subtitle_lines`); (system) by the system agent.

## Controllers (direct bindings, panel closed)

| Control | Command (level) |
|---|---|
| Trigger: play / pause | `play`, `pause` (control) |
| Stick left / right, tap: seek -/+10 s | `seek` with `relative` (control) |
| Stick right, held: scan at 4x, then 8x | `trick_play` `speed` 4 or 8, 0 to stop (control) |
| Stick circled: jog wheel scrub | `seek` (control) |
| Stick up / down: screen distance | `set_screen` `distance` (settings) |
| A / X: next file | `next` (control) |
| B / Y: previous file, or this one's start | `previous` (control) |
| INFO (left stick click): info overlay | `info_overlay` (control) |
| CHAPTER - / + (d-pad map) | `chapter` `step` -1 / 1 (control) |
| REPLAY (d-pad map): 10 s back with subtitles | `replay` (control) |
| Grip + trigger on 180 / 360: zoom lens | excluded: a magnifier aimed with the hand while held; nothing to aim without one. The picture's own zoom is `set_screen` `zoom` |
| Menu: the panel; held: recentre it | excluded here: the panel and recentring are the system agent's (`menu`, `recenter`) |
| LABELS | excluded here: the controller labels are not part of playback |
| Desktop keys V, O, H, X (projection, layout, half, swap) | `set_mode` (settings) |
| Desktop keys F, Y (pin, lying down) | `set_screen` `follow_head`, `lying_down` (settings) |

## The pane's transport

| Control | Command (level) |
|---|---|
| Seek bar: click or drag | `seek` (control) |
| -10 s, +10 s | `seek` `seconds` -10 / 10, `relative` true (control) |
| Play / Pause | `play`, `pause` (control) |
| Previous, Next | `previous`, `next` (control) |
| 4x, 8x (held) | `trick_play` (control) |
| Chapter ticks on the bar, "chapter 3/12" in the header | `chapters` (read) |
| Header: time, time left, end time, battery | `state` (read, core) |
| Seek-bar thumbnails while pointing | excluded: a picture while pointing at the bar; nothing changes |
| Tab buttons | excluded: panel navigation |
| Footer Undo | excluded here: each command's undo (core) |

## Picture tab

Read: `picture` (read).

| Control | Command (level) |
|---|---|
| Layout diagrams: Mono, SBS, TB | `set_mode` `layout` (settings) |
| Projection diagrams: Flat, 180, 360, Fisheye, Dual 360 | `set_mode` `projection` (settings) |
| Auto | `mode_auto` (settings) |
| Half | `set_mode` `half` (settings) |
| Swap eyes | `set_mode` `swap` (settings) |
| Use for this folder | `folder_rule` `on` true (settings) |
| Clear folder rule | `folder_rule` `on` false (settings) |
| Fisheye field | `set_mode` `fisheye_fov` (settings) |
| Lens (Equidistant, Equisolid, Stereographic, Polynomial) | `set_lens` `fisheye_lens` (settings) |
| Camera (dual fisheye 360) | `set_lens` `dual_camera` (settings) |
| Lens field | `set_lens` `dual_fov` (settings) |
| Seam | `set_lens` `dual_seam` (settings) |
| Reset lens | `picture_reset` `part` dual_lens (settings) |
| Show: 3D, Left eye, Right eye | `set_3d` `show` (settings) |
| Depth | `set_3d` `depth` (settings) |
| This file only | `set_3d` `depth_this_file_only` (settings) |
| Soft edges | `set_3d` `soft_edges` (settings) |
| Size | `set_screen` `width` (settings) |
| Distance | `set_screen` `distance` (settings) |
| Height | `set_screen` `height` (settings) |
| Size in degrees | `set_screen` `size_degrees` (settings); one setting with Size: give one or the other |
| Presets: Large format, Living room, In bed | `set_screen` `preset` (settings) |
| Follow my head | `set_screen` `follow_head` (settings) |
| Lying down | `set_screen` `lying_down` (settings) |
| Curvature | `set_screen` `curvature` (settings) |
| Zoom | `set_screen` `zoom` (settings) |
| Reset zoom | `picture_reset` `part` zoom (settings) |
| Auto crop bars | `set_screen` `auto_crop` (settings) |
| Grow the screen to keep its height | `set_screen` `grow_screen` (settings) |
| (no button) the screen back to the room's size and place | `picture_reset` `part` screen (settings) |
| Horizon: Pitch, Roll | `set_horizon` `pitch`, `roll` (settings) |
| Level | `picture_reset` `part` horizon (settings) |
| Brightness, Contrast, Saturation, Gamma, Dark-scene lift, Sharpen | `set_picture` (settings) |
| Deinterlace: Off, Bob, Edge, Auto | `set_picture` `deinterlace` (settings) |
| Film grain, Gate weave | `set_picture` `film_grain`, `gate_weave` (settings) |
| Reset picture | `picture_reset` `part` picture (settings) |
| Tone map | `set_hdr` `tone_map` (settings) |
| Exposure, Knee, HDR brightness | `set_hdr` `exposure`, `knee`, `brightness_nits` (settings) |
| Reset HDR | `picture_reset` `part` hdr (settings) |
| Slideshow, Each picture, Crossfade | `slideshow` `on`, `seconds`, `crossfade` (settings) |
| Frame back, Frame forward | `frame_step` `frames` -1 / 1 (control) |
| Mark A / B | `loop` `a`, `b` (control): the times, where the button marks the position now |
| Clear loop | `loop_clear` (control) |
| Screenshot | `screenshot_frame` (control) |
| Corner film: Swap | `pip_swap` (control) |
| Corner film: Close corner | `pip_close` (control) |
| Corner film: Corner size | `pip_set` `size` (control) |
| Corner film: Top right, Top left, Bottom right, Bottom left | `pip_set` `corner` (control) |

## Sound tab

Read: `sound` (read); `pc_audio_status` (read).

| Control | Command (level) |
|---|---|
| Audio track rows | `audio_track` (control, core); `tracks` (read, core) lists them |
| Volume | `volume` (control, core) |
| A/V offset | `set_sound` `av_offset_ms` (settings) |
| Calibrate | `av_calibrate` (control) |
| Live delay | `set_sound` `live_delay` (settings) |
| Speed: 0.5x to 2x | `speed` (control) |
| Night mode | `set_sound` `night_mode` (settings) |
| Evening out | `set_sound` `night_strength` (settings) |
| Dialogue boost | `set_sound` `dialogue_boost` (settings) |
| Speakers in the room | `set_sound` `speakers` (settings) |
| Bass channel | `set_sound` `bass_channel` (settings) |
| Play sound on a PC | `pc_audio` `on` (control) |
| PC: address (and its keyboard form) | `pc_audio` `host`, `port` (control); the address is not saved as the tab's |

## Subtitles tab

Read: `subtitle_settings` (read); `subtitle_lines` (read, core).

| Control | Command (level) |
|---|---|
| Replay 10 s | `replay` (control) |
| Track rows | `subtitle_track` (control, core); `tracks` (read, core) lists them |
| Off | `subtitles` `on` false (control) |
| Second track rows, and its Off | `second_subtitles` `index`, -1 for off (control) |
| Size | `set_subtitle_options` `size` (settings) |
| Below the picture, Inside the picture | `set_subtitle_options` `position` (settings) |
| Offset | `set_subtitle_options` `offset` (settings) |
| Nearer | `set_subtitle_options` `nearer` (settings) |
| Background | `set_subtitle_options` `background` (settings) |
| Delay | `set_subtitle_options` `delay` (settings) |
| Reset delay | `set_subtitle_options` `delay` 0 (settings) |
| Find files next to the video | `set_subtitle_options` `find_files` (settings) |
| Find a line (and its keyboard) | `find_line` (read) |
| Lines around now | `script_lines` (read) |
| Script from: track rows | the `track` param of `find_line`, `script_lines` and `jump_to_line` |
| A line's row: jump there | `jump_to_line` (control) |

## Summary

A row is one control, or a group of like controls that one command sets (the six picture sliders).

| | Count |
|---|---|
| Rows covered | 95 |
| Rows excluded (the reason is in the row) | 6 |
| New commands | 30 |
| Existing commands tagged | 13 |
