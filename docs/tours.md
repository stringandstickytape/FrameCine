# Scripted tours and kiosk mode

Idea #91 in `docs/ideas.md`. A tour is a JSON file with a room, a playlist, and screen and camera moves. The app runs
it unattended. Kiosk mode loops it for ever, for a demo in a shop or at a show. It is in `app/scripts/dev/tour.gd`.

## Start and stop

- **At start:** `--tour=FILE`. FILE is a path, `~/path`, or a name in `user://tours/` (with or without `.json`). On the
  headset that folder is `~/.local/share/godot/app_userdata/Frame VR Video/tours/`. Add `--kiosk` to loop it for
  ever, whatever the file says.
- **Over the PC link or from the phone:** `tour file=NAME` starts a tour (and stops the one running), `tour stop=true`
  stops it, and `tour_status` returns the file, the step, the round and the last errors.

```
python tools/listener.py send tour file=lobby kiosk=true
python tools/listener.py send tour_status
```

While a tour runs, the settings are not written. Its screen moves, rooms and files are not remembered. When the tour
stops, writes go on as before.

## The file

```json
{
  "name": "Lobby",
  "recipe": "lobby",
  "volume": 0.6,
  "kiosk": true,
  "steps": [
    {"screen": {"width": 4, "distance": 5, "yaw": 0}, "over": 0},
    {"open": "films/a.mkv", "mode": "flat_sbs_half", "start": 30, "for": 60},
    {"screen": {"yaw": 25, "distance": 4}, "over": 6, "async": true},
    {"playlist": ["b.mp4", "c.mp4"], "each": 20},
    {"camera": {"yaw": 20, "pitch": -5}, "over": 4},
    {"environment": "cinema"},
    {"wait": 3}
  ]
}
```

The top level can have these keys:

| Key | Meaning |
|---|---|
| `name` | a name for the log and `tour_status` |
| `recipe`, `environment`, `light`, `volume`, `screen` | applied at the start of each round, as the steps of the same name |
| `kiosk` | loop for ever, and keep the info overlay off |
| `loop` | loop (default: the same as `kiosk`) |
| `quit` | quit the app when a tour that does not loop ends |
| `steps` | the list of steps, run in order |

Each step does one thing:

| Step | What it does |
|---|---|
| `{"open": PATH, "mode": ID, "start": S, "for": S}` | opens a file, sets the mode (a VideoMode id, as `--mode`), seeks to `start`, and plays for `for` seconds, or to the end without `for` |
| `{"playlist": [PATH or {open...}], "each": S}` | opens each in turn; `each` is the default `for`; `mode` and `start` apply to all |
| `{"recipe": NAME}` | a saved scene recipe as the room (`docs/recipes.md`) |
| `{"environment": ID}` | a room: an id, or an `--env` name such as `room` or `cinema` |
| `{"light": X}`, `{"volume": X}`, `{"overlay": true}` | room light, volume (0 to 1), info overlay |
| `{"screen": {"width", "distance", "height", "yaw"}, "over": S}` | eases the screen from where it is to the values given, in metres and degrees (yaw > 0 is to the right) |
| `{"camera": {"yaw", "pitch", "fov", "position": [x, y, z]}, "over": S}` | eases the flat camera, in degrees as `--look`. In XR the head is the camera, so the step is skipped. |
| `{"wait": S}` | waits |
| `{"play": true}`, `{"pause": true}`, `{"seek": S}`, `{"mode": ID}` | playback |
| `{"command": NAME, "args": {...}}` | any shared command at the read, control or change level (`docs/dev/control-protocol.md`). Code commands are refused. |
| `{"print": TEXT}` | a line in the log |

A step waits until it is done: the file's `for` seconds or its end, or the move's `over` seconds. With
`"async": true` it runs alongside the next steps, for example a screen move while a film plays.

Paths are relative to the tour file's folder. `~/` is the home folder, and `smb://`, `stub://` and `lab://` paths
work as they do everywhere.

## When something fails

A step that fails is logged as a warning and the tour goes on. Examples are a file that does not open within 30 s, a
room that does not exist, or a command that is refused. `tour_status` lists the last 10 errors. If a whole round
takes less than 2 s, for example because every file is missing, the tour waits 10 s before the next round. Each step
also hides the pane, so the view stays clear. A visitor can still raise the pane and use it; the tour goes on.

## For the pane (app-shell)

`preload("res://scripts/dev/tour.gd").running()` is the tour node or null. `.status()` gives the same dictionary as
`tour_status`. A kiosk could lock the pane while `running() != null and running().kiosk`; the tour does not do that.

## Tested

On the desktop only, with the stock 4.7.2 Windows build, on 2026-10-31.

- **A tour of 11 steps** with test patterns and lab cards: the room, volume and screen applied; the files opened in
  turn; the screen moved alongside the camera move; a missing file, a missing recipe and a code command were logged
  and skipped; `quit` ended the app.
- **The camera move:** a screenshot showed the view turned 35° right and 10° up.
- **Kiosk over the link:** `tour` started it, it ran 4 rounds in 9 s, `tour stop=true` stopped it, and an unknown
  file gave the reason.
- **The menu input test** (50 checks) passed with the hook in `main.gd`.

Not tested on the device: tours in the headset, screen moves in XR, files on a share, a recipe room, and long kiosk
runs.
