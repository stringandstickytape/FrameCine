# Assistant coverage: the Room tab, the System tab, eye gaze and the director

Each control a viewer can use here, and the command that does the same for an assistant. A command's consumer level
is the `"assistant"` key of its registry spec (`app/scripts/dev/dev_commands.gd`); the consumer API reaches only
tagged commands. The levels:

| Level | Here |
|---|---|
| `read` | the reads: always |
| `control` | what acts on playback or moves the viewer: the seat, the sleep timer, eye gaze, director jumps, test cards, the bandwidth meter |
| `room` | what changes the room around the screen: the room itself, its effects, its light and the showing |
| `settings` | persistent preferences of the System tab |

The commands are in `app/scripts/dev/room_tab_commands.gd` and `app/scripts/dev/system_tab_commands.gd` (registered by
`command_host.gd`), and in the feature that owns them (`eye_gaze.gd`, `director.gd`, `test_lab.gd`,
`hw_video.gd`). Each handler calls what the tab's control calls and then syncs the tab. Each change sets a summary and
an undo. A change command takes only what it changes: a parameter left out stays as it is. Values are kept to the
slider's range, as the tab keeps them.

Test: `app/tests/test_assistant_coverage_system.gd`; the object library's commands and the Objects tab:
`app/tests/test_object_library.gd`. The object commands are in `app/scripts/assistant/object_commands.gd`, and the
Objects tab calls the same functions (`app/ui/object_section.gd`, `app/ui/object_placer.gd`).

## Room tab (`app/ui/room_tab.gd`)

| Control | Command (level) |
|---|---|
| Environment: a row of the list | `set_environment` {id} (room). The list: `room_settings` environments (read) |
| Use this picture as the room | `use_picture_as_room` (room) |
| Seat: the label | `room_settings` seat (read) |
| Previous seat, Next seat, Room's own spot | `seat` {to: previous, next or own} (control) |
| Pick a seat (the laser) | `seat` {to: the seat's name} (control) |
| Go to (a seat moved by an assistant's change) | `seat` {to: the seat's name} (control) |
| Floor reflection, Reflection | `floor_reflection` {on, strength} (room) |
| Bias light, its strength | `bias_light` {on, strength} (room) |
| React to the film, Reaction | `react_to_film` {on, strength} (room) |
| Projector beam | `projector_beam` {on} (room) |
| Time of day (Night, Now, Dusk, Day), Latitude | `time_of_day` {mode, latitude} (room) |
| Room light | `room_light` {level} (room) |
| Dim while playing, Dimmed to | `dim_while_playing` {on, level} (room) |
| Reset room | `reset_room` (control; registered by the core agent) |
| Reset screen | Picture tab: see playback.md |
| Objects: the thumbnails (built in and imported) | `object_library` {tag, source} (read); one: `object_info` {id} (read) |
| Objects: Place (laser, stick turns and sizes, trigger sets) | `object_place` {id, at, position, rotation, turn, scale} (room) |
| Objects: Delete (imported only, asked first) | `object_delete` {id} (room; destructive; undo restores it) |
| Objects: importing (no panel control: an assistant or the dev link brings the file) | `object_import` {name, data, format, tags, mount, width, depth, bevel, part_names} (room); `path` instead of `data`: the dev link only |
| Your objects, Fab: Accept, Withdraw (the licence) | none, on purpose: only the user accepts Fab's licence; `fab_status` (read) says whether they have |
| Your objects, Fab: Search Fab, More | `fab_search` {query, cursor} (read; refused with error eula until accepted) |
| Your objects, Fab: Import, its progress, Cancel | `fab_import` {uid} (room), `fab_status` (read), `fab_cancel` (room) |
| Your objects, Fab: Clear Fab's cache, Read Fab's licence | none (the viewer's own) |
| In this room: the list, a pick's parts and their colours | `room_state` objects (read); `object_info` {placed} (read) |
| In this room: Move | `object_move` {name, at, position, rotation, turn, scale} (room) |
| In this room: Remove (asked first) | `remove` {name} (room) |
| In this room: a part's Colour (palette), Picture, Material | `recolour` {match: "<placed>/<part>", color, texture, material} (room) |
| In this room: a part's Reset | `recolour` {match: "<placed>/<part>", reset: true} (room) |
| In this room: Put back (an object moved by hand) | `object_put_back` {name} (room) |
| In this room: Tidy up | `object_tidy_up` (room) |
| In this room: a text's or particles area's Attach, Detach | `object_attach` {name, to, offset, rotation} (room; empty `to` detaches) |
| The controllers: pick up, drop, throw (docs/physics.md; no panel control) | `object_throw` {name, velocity, spin} (room); what moves and the cost: `object_physics` (read) |
| Curtains | `curtains` {on} (room) |
| Up next countdown, Up next in | `up_next` {on, seconds} (room) |
| Intermission, its minutes | `intermission` {on, minutes} (room) |
| Crossfade music, Crossfade films | `crossfade` {music_seconds, video_seconds} (room) |
| Sleep timer (Off, 15, 30, 60, 90 min, End of file), its countdown | `sleep_timer` {set} (control); the countdown: `room_settings` sleep (read) |

The whole tab in one read: `room_settings` (read).

## System tab (`app/ui/system_tab.gd`)

| Control | Command (level) |
|---|---|
| Info overlay | `info_overlay` (control; the playback agent) |
| Stats | excluded: a diagnostics view inside the panel; `perf` (read) gives the numbers |
| Panel: Size, Distance, Hold menu to recentre, Follow my head | `panel_layout` {size, distance, recentre_hold, follow_head} (settings) |
| Panel: Left-handed | `accessibility` {left_handed} (settings) |
| Panel: Reset layout | `reset_panel_layout` (settings) |
| Accessibility: Larger panel, One eye for 3D, Left eye / Right eye, Subtitles always on | `accessibility` {larger_panel, one_eye_3d, eye, subtitles_always} (settings) |
| Test patterns | `list_dir` stub:// and `open` (the core agent's commands) |
| Network hosts | `list_dir` network:// (the core agent's commands) |
| Calibration cards | `lab_cards` (read), `open_test_card` {card} (control) |
| Measure bandwidth | `bandwidth_test` {path} (control): a file on the headset or on a saved host's share only |
| Run benchmark | excluded: dev only |
| Stop tour | excluded: dev only (tours start from the dev link) |
| Hardware video: which way 10-bit plays, Details | `hwvideo_status` (read) |
| Rendering: Foveation (Off / Low / Medium / High), Sharp while the panel shows | `foveation` {level, sharp_panel} (settings); refused when the build starts without foveation |
| Controllers: Look (the presets), its colour and Speed | `controller_looks` (read), `controller_look` {look, options} (settings) |
| Haptic ticks, Tick strength | `haptics` {on, strength} (settings) |
| Jog wheel, One turn | `jog_wheel` {on, seconds_per_turn} (settings) |
| Seek bar pictures | `seek_bar_pictures` {on} (settings) |
| Zoom lens, Magnification | `zoom_lens` {on, magnification} (settings) |
| Phone remote, Unpair phones | excluded: it opens a server with its own pairing; unpairing is pairing |
| Share this headset's files | excluded: it opens the headset's files to the network, with its own pairing code |
| Assistant: on or off, Let an assistant find me, the pairing prompt, Paired assistants and Forget | excluded: the assistant's own pairing |
| Assistant: Let the assistant ... (every permission switch) | excluded: an assistant must never raise its own permissions |
| Assistant: Voice goes to | excluded: where the viewer's voice goes is the viewer's choice |
| Dev tools: Reload theme, Remote changes, Allow for an hour, Revoke, Undo | excluded: dev only |
| About: the version | `system_settings` version (read) |

The whole tab in one read: `system_settings` (read).

## Elsewhere in this area

| Control | Command (level) |
|---|---|
| Recentre (the screen to the gaze; also the controller's held menu button) | `recenter` (control; tagged by the core agent) |
| Eye gaze: its state | `gaze_status` (read) |
| Eye gaze: calibration (no panel control; the viewer looks at dots and pulls the trigger) | `gaze_calibrate` (control) |
| Eye gaze: the dot where the viewer looks | `gaze_pip` {on} (control) |
| Director (the Subtitles tab's Script): find a line | `find_line` {query} (read) |
| Director: the lines around now | `script_lines` (read) |
| Director: jump to a line | `jump_to_line` {query or i} (control) |
| Scene recipes in the Environment list | `set_environment` (room) |
| Scene recipes: save, delete, load | excluded: dev only (a recipe packs what the dev link built); a saved one is opened with `set_environment` |

## Safety

- No tagged command names or takes an `allow`, `pair`, `forget`, `permission` or `token` value, and `set`, `get`,
  `call`, `set_prop` and `run` stay untagged: the `[assistant]` section can't be written by a consumer command. The
  test checks both, and checks that the `[assistant]` section is the same after every command here.
- `bandwidth_test` reads only a file on the headset or on a share of a host saved in the player.
