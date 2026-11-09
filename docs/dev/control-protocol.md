# The dev link: control protocol

Idea #5 in `docs/ideas.md`, "Claude as the listener". This is the shared plumbing for the dev and LAN ideas. The headset
opens one TCP connection to a listener on the PC. It sends events over it and takes commands back on the same socket.

**Nothing listens on the headset.** The headset only connects out, to the host and port in its own settings. A PC
with nothing listening costs the headset one refused connection now and then.

## Turn it on

The link is off by default. Turn it on with either of these:

- the argument `--listener=HOST[:PORT]` after `--`;
- `listener_host` (and optionally `listener_port`, default 47800) under `[dev]` in `settings.cfg`. On the device the
  file is `~/.local/share/godot/app_userdata/FrameCine/settings.cfg`.

```
[dev]
listener_host="192.168.1.20"
listener_port=47800
```

On the PC:

```
python tools/listener.py serve
```

The listener needs Python 3.8 or later and nothing else. Windows asks once whether Python may accept connections on
private networks. Answer yes, or the headset can't reach port 47800.

## Use from a terminal or an AI session

`serve` prints each event and also takes commands typed on its terminal. Other terminals and scripts talk to the
running `serve` through a control port, 47802, which is bound to 127.0.0.1 only (47801 is the assistant link, `docs/assistant.md`):

```
python tools/listener.py status                    # connected? the headset's hello
python tools/listener.py describe                  # every command, setting and event, with parameters
python tools/listener.py send ping
python tools/listener.py send seek 120             # positional arguments, in the order describe lists
python tools/listener.py send seek seconds=10 relative=true
python tools/listener.py send open /home/steamos/films/a b.mkv   # a single text parameter takes the rest
python tools/listener.py send '{"cmd": "set", "args": {"setting": "volume", "value": 0.5}}'
python tools/listener.py events -n 50              # the last 50 logged messages
python tools/listener.py events -f -e error        # errors as they arrive
python tools/listener.py wait file_opened -t 30    # block until the next file opens
```

`send` prints the result as JSON and exits with 0, or prints the whole reply and exits with 1 when the command
fails. Values are read as JSON when they parse, such as `120`, `true` or `[0, 1.6, -2]`, and as text otherwise.

Everything is logged to `~/.frame-listener/events-YYYY-MM-DD.jsonl`, one JSON object per line. The log holds every
message from the headset and every command sent, each with `rx`, the PC's receive time. Images that the headset sends
inline are written to `~/.frame-listener/shots/`. In the log, `"local_path"` replaces the image data. Use `--log-dir`
to choose another folder.

For an AI session, the simplest loop is this:

1. Read the log file, or run `events -f`, to see what happens.
2. Run `send` to act.

## Wire format

Each message is one JSON object on one line, in UTF-8, ending with `\n`. The protocol version is 1.

### Headset to PC

**hello**, sent first on every connection:

```
{"type": "hello", "proto": 1, "session": "7016f2c9", "t": 1793420986.8, "app": "FrameCine",
 "engine": "4.7.2-stable (custom_build)", "os": "Linux", "model": "...", "pid": 1234,
 "app_dir": "/home/steamos/spike03/app/", "user_dir": "...", "hot_reload": true, "backlog": 3, "dropped": 0}
```

`session` stays the same across reconnects of one app run. `backlog` counts the messages queued while there was no
connection. They follow the hello.

**event**:

```
{"type": "event", "event": "file_opened", "t": 1793420990.5, "seq": 12, "data": {...}}
```

`t` is the headset's Unix time. `seq` counts up through the app run, so a gap means that events were dropped.

**reply**, one for every command:

```
{"type": "reply", "id": 7, "ok": true, "result": ...}
{"type": "reply", "id": 7, "ok": false, "error": "no command nosuch (try describe)"}
```

### PC to headset

**command**:

```
{"id": 7, "cmd": "seek", "args": {"seconds": 120}}
{"id": 8, "cmd": "seek", "args": [120]}
```

`id` is any JSON value and comes back in the reply. `args` is an object, or a list in parameter order. It can be left
out. Commands run in the order they arrive. A command that waits, such as `screenshot`, does not hold up the next one,
so replies can come back out of order.

### Events

| Event | When | Data |
|---|---|---|
| `state` | on connect, on play or pause, and every 10 s while playing | path, title, playing, position, duration, auto_paused, mode, mode_source, environment, playlist_index, playlist_size, menu_shown, xr, session_focused |
| `file_opened` | a file opened (path `""`: closed) | path, title, kind, playlist_index, playlist_size, mode, mode_source |
| `mode_changed` | projection or layout changed | mode (id), describe, source, auto |
| `environment_changed` | | id, light |
| `screen_changed` | screen moved or resized; at most every 0.5 s, plus the final value | width, distance, height_offset, yaw |
| `settings_changed` | volume, A/V offset or overlay | volume, av_offset, overlay |
| `playback_ended` | the file ended and nothing plays next | path |
| `session` | XR session state (`focussed`, `visible`, ...) | state |
| `battery` | on connect and when the value changes, checked every 60 s | percent (-1: no battery) |
| `log` | every line the app prints | level (`info` or `stderr`), text |
| `error`, `warning` | engine and script errors and warnings | text, kind (`error`, `warning`, `script`, `shader`), code, function, file, line |
| `reload` | hot-reload reloaded a file (`hot-reload.md`) | path, kind, ok, ms, note |
| `heartbeat` | every 15 s | uptime, dropped |
| `card_dismissed` | a watch-along card went away (app-shell's `app/ui/watch_card.gd`) | id, how (`user`, `timeout`, `replaced`, `cleared`) |
| `voice_state` | push-to-talk pressed or let go (`voice.md`) | recording |
| `voice_clip` | push-to-talk let go | wav_b64 (16 kHz mono 16-bit WAV; the listener saves it to `voice/` and logs local_path instead), seconds, rate, peak |

The listener adds its own `{"type": "listener", "event": "disconnected"}` to the log when the headset goes away.

## Commands: the self-describing API

Idea #56. The first call is `describe`. It returns the schema of every command, setting and event, generated from
what the running app has registered. The listener fetches it after each hello, to map positional arguments to
names. This table lists the built-in commands; `describe` is always the full and current list.

| Command | Parameters | Level | Does |
|---|---|---|---|
| `describe` | | read | the schema: `{proto, app, levels, commands, settings, events}` |
| `ping` | | read | answers at once |
| `get` | `setting` = `""` | read | a setting's value. With no setting: `{state, settings}`, the app state and every registered setting. `SECTION/KEY` reads `settings.cfg` directly. |
| `set` | `setting`, `value` | change, or the setting's own level | changes a registered setting now. `SECTION/KEY` writes `settings.cfg`, which is read at the next start. |
| `play`, `pause` | | control | returns the state |
| `seek` | `seconds`, `relative` = false | control | returns `{position, duration}` |
| `open` | `path` | control | a headset path (`~/` works), `stub://<mode id>`, `smb://host/share/path` or `browser://url`. Waits up to 10 s for the file to open and returns the state, or `{opening: path}` while still connecting. |
| `next`, `previous` | | control | playlist navigation, as A and B |
| `menu` | `shown` | control | shows or hides the menu |
| `list_tree` | `path` = `/root`, `depth` = 3, `properties` = false | read | the node tree: name, class, path, script, visibility and position. A relative path starts at the main scene. Stops at 3000 nodes. |
| `reload` | `target` = `""` | change | hot-reload now. `""` reloads the files changed since the last check, a `res://` path reloads that file, and `app` instances the main scene again. |
| `screenshot` | `views`, `size`, `position`, `target`, `fov`, `inline` | read | each eye and a third-person camera; see `screenshots.md` |
| `spawn`, `set_prop`, `get_prop`, `call`, `free`, `load_gltf`, `run` | | change, code | the scene control port; see `scene-control.md` |
| `undo` | `id` = -1 | control | takes back a remote change; see `permission-ring.md` |
| `permissions` | | read | the permission ring's mode, allowed window and recent changes |
| `places`, `list_dir` | `path` | read | the file browser's places and a folder's folders and video files (`stub://`, `network://`, `browser://`, `smb://` too) |
| `type_text` | `text`, `submit` = false, `replace` = false | control | types into the pane's focused text field |
| `save_recipe`, `list_recipes`, `load_recipe`, `delete_recipe` | `name`, `replace` | change, read, control | what was built over the link, saved as a room under user://recipes (`../recipes.md`) |
| `card`, `card_clear` | `text`, `title`, `image` (base64 PNG or JPEG, 256 KB at most), `seconds` = 20 (0: until dismissed), `id`; `card_clear`: `id` (empty: all) | control | a watch-along card at the screen's top-right edge, one at a time (app-shell, #54); returns `{id}` / `{cleared}` |
| `pc_audio`, `pc_audio_status` | `host`, `port` = 47820, `on`, `test_tone` | control / read | the film's sound on a PC (`tools/audio_sink.py`), the video held back by the measured delay (`../pc-audio.md`) |
| `share_files` | `on`, `remember` = false | change | shares the headset's folders on the LAN (`../share.md`); the reply has the address, never the pairing code |
| `media_servers` | `seconds` = 3, `url` | read | media servers (UPnP/DLNA) on the LAN; `list_dir path=upnp://...` browses them (`../media-servers.md`) |
| `chapter`, `subtitles`, `recenter` | `n` or `step`; `on` | control | chapter n (1 = first) or next / previous; subtitles on or off; the screen to the gaze (`voice.md`) |
| `chapters` | | read | the open file's chapters and the one playing now: `{count, current (1 = first, 0 = none), title, list}` (`watch-along.md`) |
| `push_to_talk` | `seconds` = 3 | control | records the microphone and sends a `voice_clip`, as holding F8 does (`voice.md`) |
| `find_line`, `jump_to_line`, `script_lines` | `query`, `n`, `i`, `lead`, `offset`, `count`, `track` | read / control | director mode: search the open file's subtitle text and jump to a line (`../director.md`) |
| `tour`, `tour_status` | `file`, `kiosk` = false, `stop` = false | control / read | runs a tour file or stops it; where it is (`../tours.md`) |
| `benchmark` | `path` = "", `seconds` = 10 | control | decodes the biggest video in a folder (or a file) as fast as it goes and returns what the device can do; saved, and in `stats` as `benchmark` (`../benchmark.md`) |
| `lab_cards`, `bandwidth_test` | `path`, `seconds` = 8 | read | the test lab's calibration cards (`lab://...`) and a share's throughput (`../test-lab.md`) |
| `discover_hosts` | `seconds` = 3 | read | file servers on the LAN by NetBIOS and mDNS (`../host-discovery.md`) |
| `open_url` | `url` | control | opens a web page on the screen through the Browser source |
| `android_status`, `android_start`, `android_stop`, `android_back` | `name` (its folder in `~/Android`) | read / control | Android apps (`../features.md`): the state and step; start one, which returns at once and goes on in the background; stop one or cancel a start; what B does, returning `{way: back, launcher or none, before, after}` |
| `hwvideo_status` | | read | which way 10-bit video plays now (`main.features.hwvideo.status()`): `path` (`p010`, `q10c`, `software`, or `unknown` before the look at start), `text`, `p010`, `q10c`, `q10c_off_reason`, `decoder_formats`, `hw_vp9`. Read-only: nothing is installed (`../features.md`, "Hardware 10-bit video") |

Built-in settings for `get` and `set`: `volume`, `av_offset`, `overlay`, `environment`, `room_light`, `screen_width`,
`screen_distance`, `screen_height` and `mode`. `mode` takes a mode id such as `flat_sbs_half`, a `--mode=` form such
as `360tb`, or `auto`. For a dual fisheye 360 file (`mode` `dualfisheye`): `dual_fisheye_profile` (`camera360`,
`camera360_photo` or `generic`, for the open file), `dual_fisheye_fov` (both lenses, degrees), `dual_fisheye_seam` (the
back lens's yaw, -5 to 5 degrees) and `dual_fisheye_lens` (every value: `{"front": {"fov", "cx", "cy", "radius",
"yaw", "pitch", "roll"}, "back": {...}, "blend", "model"}`; a `set` changes only the parts it names, e.g.
`{"back": {"roll": -0.5}}`). The lens values are kept for the profile, and they apply at once (`../features.md`,
"Dual fisheye 360"). The `network` section of `settings.cfg`, which holds the saved SMB passwords, is never read or
written over the link. The `dev` section can be read but not written, so the PC can't raise its own permissions.

**Secrets never go over the link,** because the listener logs every reply. `get`, `set`, `get_prop`, `set_prop` and
`call` refuse a name with a word such as key, pin, password, secret, token or credential in it (`remote/key`, the
phone remote's pairing code), and a private member (a name that starts with `_`). `call` also refuses
the generic accessors (`get`, `set`, `get_meta`, `call`, ...). `get_prop` with no property leaves these names out. The
reply is "NAME is private". A masked text field's text (a password being typed, as in the SMB host form) is private
too: `get_prop`, `set_prop` and `call` (`get_text`, ...) refuse it, `list_tree` and `get_prop` with no property
leave it out, and `type_text` answers with an empty text.

Levels say how much a command changes:

| Level | Means |
|---|---|
| read | changes nothing |
| control | playback and view: play, seek, open, volume, screen |
| change | settings files, the scene, reloads |
| code | runs code sent from the PC |

The permission ring gates the levels; see `permission-ring.md`.

### Registering a command or a setting

Features register into `app/scripts/dev/dev_commands.gd`. Registering costs one dictionary entry, so a feature may
register whether or not dev mode is on. The registry is kept in Engine metadata, so it survives a hot-reload and
`reload app`.

```
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

func _ready() -> void:
	DevCommands.register("depth", _cmd_depth, {
		"description": "Shifts the eye pictures apart.",
		"params": [{"name": "shift", "type": "float", "required": true, "description": "-1..1"}],
		"level": "control", "returns": "the new shift"})
	DevCommands.register_setting("depth_3d", func() -> float: return depth, set_depth,
		{"type": "float", "min": -1.0, "max": 1.0, "level": "control", "description": "3D depth"})


func _cmd_depth(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var old := depth
	set_depth(args["shift"])
	ctx.summary = "3D depth %.2f" % depth   # shown in the headset's toast
	ctx.undo = set_depth.bind(old)           # offered as undo
	return depth                             # or: return ctx.fail("why")
```

Parameter types are `string`, `int`, `float`, `bool`, `array`, `object`, `vector3`, `color` and `any`. Values are
converted before the handler runs. A list `[x, y, z]` becomes a `Vector3`, and `#rrggbb` becomes a `Color`. Results
are converted back: vectors and colours become lists, and nodes become `"<Class:/root/path>"`. A handler may `await`.

## On the headset: never blocking the frame

The link is `app/scripts/dev/dev_link.gd`. It works like this:

- **Name lookup.** A host name is resolved on the engine's resolver thread. An IP address skips the lookup.
- **Connecting.** The socket is non-blocking. A connect that has not finished after 5 s is dropped.
- **Writing.** Messages go into an outgoing buffer. It is drained with `put_partial_data()`, at most 1 MiB a frame.
  If nothing can be written for 10 s while data waits, the PC is taken as gone, for example after a Wi-Fi drop, and
  the link reconnects. Beyond 64 MiB waiting, new events are dropped and counted. Replies are never dropped.
- **Reading.** Only the bytes that have arrived are read, at most 1 MiB a frame. They are split at newlines.
- **Reconnecting.** A refused, failed or lost connection is retried after 1, 2, 4, 8, 15, then every 30 s. The first
  failure and every tenth after it are logged.
- **Without a connection.** The last 200 events are kept and sent after the next hello.
- **The log.** The engine's log reaches the link through an `OS.add_logger()` logger. It only queues, because the
  engine calls it from any thread. The queue is drained on the main thread, at most 200 lines a frame.

Off, the link costs nothing: `dev_host.gd` makes no node. On, it costs one socket poll a frame and the events above.

### Slow commands run on a worker

A command that blocks, for example a folder listing on a share, a bandwidth measurement or the benchmark's file
probe, runs on a worker thread through `app/scripts/dev/worker_task.gd`. The command waits for it frame by frame, so
the frame never blocks.

Every task is waited for exactly once. A task whose command gave up after its time limit keeps running. It is waited for
when it ends, or when the app quits. The app also waits at quit for a task whose command was still waiting. All of these
waits happen when the scene tree's root leaves the tree. A task nobody waited for is freed by the engine at its very
end, after the script runtime has shut down. That corrupts the heap and aborts the app at exit with "corrupted size vs.
prev_size". So a quit waits until a running task ends, for example a hung share listing. The engine's own thread
shutdown would wait for it anyway.

Other app code follows the same rule. Keep the task ID from `WorkerThreadPool.add_task()` and wait for it, at the
latest in `_exit_tree()`. `app/tests/test_dev_tasks.gd` checks the rule. Judge it by its exit code: the abort comes
after the test has printed "OK".

## Trust

The headset connects only to the host in its own settings, or given on its command line. Whoever runs the listener
there can send commands. The listener takes only one headset at a time, and `--allow IP` restricts it to known
addresses. The control port accepts connections from the PC itself only. Nothing is encrypted. This is a tool for a
home LAN, not for the internet.

Commands that change things pass the permission ring first (`permission-ring.md`). No credentials pass over the link:
the app never prints SMB passwords, and the settings it reports leave them out.

## Tested

On the desktop only, on 2026-10-31, with the stock 4.7.2 Windows build, headless. The test covered: the hello, `state`
and `battery` events, log forwarding, `ping`, an unknown command (exit code 1), and a listener restart, after which the
app reconnected within a second.

Not tested on the device: the link over Wi-Fi, a name lookup, and the PC's firewall prompt.

Worker tasks were tested on the desktop only, on 2026-10-31, with `test_dev_tasks.gd` on the x86_64 fork build in WSL:

| Build | Runs | Clean exits |
|---|---|---|
| With the wait at quit | 5 | 5 |
| Wait at quit turned off | 6 | 0 (all aborted, exit code 134) |

The folder listing, both time-limit paths, the bandwidth meter and the benchmark's helper also gave the same results as
before on the stock Windows build. Not tested on the device.
