# The motion system

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each part is.

`scripts/env/systems/motion.gd`. Slow moves of the room's things. It never moves the viewer or their horizon
(`moves_viewer` false in its spec).

One motion system moves one thing. Give each its own id: the id names its actions (`organ.rise`). The thing is:

- a node the document names: `node` (its name, or the plain name it had before `own()` gave it its system's id),
  among the nodes of the system `system` (an id), or anywhere in the room when `system` is empty;
- or a festoon curtain it builds itself: `build` "festoon". It hangs over the screen (`festoon_size` 0: the
  screen's size with a margin) in `festoon_swags` swags, `festoon_depth` in front, its top `festoon_top` over the
  screen's top (0.5 m by default), in the `curtain` material. Fully up, its swags hang about a seventh of its drop
  and up to 0.66 m more under its top: hung higher, behind a proscenium's head, it clears the picture (since
  2026-11-08, the Streamline 1937: `festoon_top` 2.3, a drop of 8.05 m from over the proscenium's head to the stage).
  `festoon_fringe` (since 2026-11-08, the Pink Palace; 0 by default: none): a bullion fringe this deep along the
  hem, following the swags, its foot in little tassels, in the `fringe` material (the festoon's second surface).

### Modes

| Mode | What | Parameters |
|---|---|---|
| `travel` | along `path` (offsets from where it stands, in its parent's frame) and to `turn_to` (degrees, about `pivot` in its own frame). `at` 0 is where it stands, 1 the path's end | `path`, `turn_to`, `pivot`, `at` (live), `speed`, `accel`, `turn_speed` |
| `sway` | to and fro about `sway_axis` and along `shift_dir`, one swing every `sway_period` seconds | `sway_angle` (live), `sway_shift` (live), `sway_period`, `pivot` |
| `turn` | round `turn_axis` | `turn_rate` (live) |

A festoon travels too: `at` 1 is fully up. The hem rises, the cloth above it gathers into tiers of folds, and
between the lift cords it falls in swags that deepen as it rises.

Actions: `rise` (to at 1), `lower` (to at 0), `go` (args `at`), each with `seconds` as a wish; `snap` (at once,
args `at`); `start` and `stop` (a sway or a turn eases in or out). A cue can also `set` `<id>.at`.

### Comfort

| Limit | Value |
|---|---|
| speed | 0.5 m/s |
| acceleration | 0.3 m/s² |
| turning speed (travel) | 20 degrees/s, speeding up at 8 degrees/s² |
| sway | 5 degrees, 0.1 m, a swing at least every 3 s |
| turn | 15 degrees/s, speeding up at 8 degrees/s² |

- Each limit is a `motion` flag in the spec, and the parameter's range ends there. The comfort check and the
  schema refuse more.
- Whatever drives `at` (an action, a cue's fade, a binding), the thing follows it no faster than its limits. It
  speeds up and slows down smoothly. An action's `seconds` is a wish: when it asks for more than the limits, the
  move takes longer. A sway or a turn starts from still and eases in.
- **The Motion setting** (common) scales every motion parameter: half Motion is half the sway, half the speed.
  Under 25 % a travel does not move at all: it snaps to the end it heads for, or (`reduced` "fade") fades out,
  jumps and fades back in. A cue's fade on `at` then snaps to its end too.
- **In front of the screen.** A thing that stands between the viewer and the screen until it moves (`in_front`: a
  painting over the screen; the festoon always) does not count against the sight-line check. It is in the group
  `env_in_front`. It never stays in the way through the film: 4 s after the film starts (no cue took it away), it
  goes to its end by itself. A room whose Pre-show is off needs no cue for it.

Measured (`test_env_motion.gd`): an organ console rising 2.8 m at 0.3 m/s and 0.15 m/s² takes 11.3 s and never goes
faster. A festoon of 5 swags is 1 draw and 840 triangles; the mesh is made again only while it moves.

### Examples

```json
{"system": "motion", "id": "organ", "params": {"system": "kit", "node": "OrganConsole",
 "path": [[0, 2.8, 0]], "speed": 0.3, "accel": 0.15}}
{"system": "motion", "id": "painting", "params": {"node": "Painting", "path": [[0, 3.0, 0]], "in_front": true,
 "reduced": "fade"}}
{"system": "motion", "id": "festoon", "params": {"build": "festoon", "festoon_swags": 6}}
{"system": "motion", "id": "earth", "params": {"system": "sky", "node": "Earth", "mode": "turn",
 "turn_rate": {"bind": "setting.earth_speed", "range": [0.5, 4.0]}}}
```

The ritual raises them: `{"do": "organ.rise", "args": {"seconds": 12}}`, `{"do": "festoon.rise", "args":
{"seconds": 8}}`.
