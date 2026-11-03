# Assistant coverage: the Room tab, the System tab, the watch party, eye gaze and the director

Each control a viewer can use here, and the command that does the same for an assistant. A command's consumer level
is the `"assistant"` key of its registry spec (`app/scripts/dev/dev_commands.gd`); the consumer API reaches only
tagged commands. The levels:

| Level | Here |
|---|---|
| `read` | the reads: always |
| `control` | what acts on playback or moves the viewer: the seat, the sleep timer, the watch party, eye gaze, director jumps, test cards, the bandwidth meter |
| `room` | what changes the room around the screen: the room itself, its effects, its light and the showing |
| `settings` | persistent preferences of the System tab, and the watch party's name and PIN |

The commands are in `app/scripts/dev/room_tab_commands.gd` and `app/scripts/dev/system_tab_commands.gd` (registered by
`command_host.gd`), and in the feature that owns them (`watch_party.gd`, `eye_gaze.gd`, `director.gd`, `test_lab.gd`,
`hw_video.gd`). Each handler calls what the tab's control calls and then syncs the tab. Each change sets a summary and
an undo. A change command takes only what it changes: a parameter left out stays as it is. Values are kept to the
slider's range, as the tab keeps them.

Test: `app/tests/test_assistant_coverage_system.gd`.

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
| Curtains | `curtains` {on} (room) |
| Up next countdown, Up next in | `up_next` {on, seconds} (room) |
| Intermission, its minutes | `intermission` {on, minutes} (room) |
| Crossfade music, Crossfade films | `crossfade` {music_seconds, video_seconds} (room) |
| Sleep timer (Off, 15, 30, 60, 90 min, End of file), its countdown | `sleep_timer` {set} (control); the countdown: `room_settings` sleep (read) |
| Watch party: Host | `party_host` (control) |
| Watch party: Join | `party_join` (control) |
| Watch party: Leave, End party | `party_leave` (control) |
| Watch party: status, who is in it, the sync | `party_status` (read) |
| Watch party: Name | `party_settings` {name} (settings) |
| Watch party: PIN | `party_settings` {pin} (settings); reads say only `pin_set` |
| Watch party: Find it (the host's file isn't open here) | excluded here: a search of the Files tab (the files commands). The file's name is in `party_status` file |

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
- The watch party is LAN only: `party_join` refuses a host that is not a private address. Its PIN is saved as the
  tab saves it and is in no reply, summary or log.
- `bandwidth_test` reads only a file on the headset or on a share of a host saved in the player.
