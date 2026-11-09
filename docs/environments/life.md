# Ambient life

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each part is.

`scripts/env/systems/life.gd`, kind `life`. Animals only, never people. One system is one kind of creature. A room
with moths and a cat has two `life` systems, each with its own id (for example `moths` and `cat`). A cue calls a
creature by that id: `whale.pass`, `cat.settle`.

Each creature is a script in `scripts/env/systems/life/` (the base is `creature.gd`). All are procedural low-poly
meshes on two shaders: `shaders/env_life.gdshader` (unlit with the room's spill; wings, legs, the body's wave and the
head move in the vertex shader) and `shaders/env_life_glow.gdshader` (additive: glowing points and bells). There are
no textures, no live lights and no particles.

| Parameter | Default | What |
|---|---|---|
| `creature` | `moth` | `moth`, `bird`, `firefly`, `cat`, `deer`, `fish`, `jelly` (glowing deep-sea creatures), `ray` (a manta gliding over), `whale`, `plane` (a plane's lights). Built once |
| `count` | 0 | how many; 0: the creature's own (below). The cat, the deer, the ray and the whale are one at most |
| `schooling` | 0 | fish: how tightly they school (since 2026-11-08). Over 0 the school draws in (to 60 % at 1) and stretches along its way (1.9 times), and each fish keeps its place relative to where the school was a moment before, the later the further back it swims (up to 2.4 s at 1): a turn starts at the leaders and ripples back. One lookup in a short history a fish, no neighbour search |
| `region` | null | the box `{min, max}` they keep to, in the room's frame; null: the creature's own |
| `path` | [] | points in the room's frame: the cat's wall top, the deer's and the whale's way (first to last), the birds' perches |
| `size` | 1 | times the creature's own size |
| `speed` | 1 | times its own speed. Live |
| `colour` | null | the body's colour, or the glow's (fireflies, jellies); null: its own. Live, a brightness (it can follow `film.colour`) |
| `glow` | 1 | how bright the lights are (fireflies, jellies, planes). Live, a brightness |
| `attraction` | 0.5 | how strongly they go to the light: moths to the beam, fish and jellies to the screen. Live |
| `activity` | 1 | the share out and about; the rest fade away. For birds: how often they flit. Live |
| `every` | null | seconds between visits on average (the deer, planes, a bird across the roof); 0: only on a cue; null: its own |
| `keep_out` | 0.4 m | how far they keep from the sight line to the picture |
| `personal` | 1.5 m | how far they keep from the viewer's eyes |
| `blink` | true | fireflies flash and a plane's strobe blinks; off: a steady glow. Live. A `flicker` parameter: the common "Flickering lights" setting holds it steady |
| `voice`, `voice_db` | true, -12 dB | a call where the synthesiser has one (now only the whale's song), on the Environment bus |

Actions (each creature does what fits it; args in brackets):

| Action | What |
|---|---|
| `pass` | one goes by now: the whale or the deer crosses, a plane flies over, a bird flies the length of the roof, the cat walks its wall, the school sweeps past (`side`: left or right; `seconds`) |
| `scatter` | they start away and settle again: birds take off and circle, fish dart, moths and fireflies spread, the cat trots off (`from`: [x, y, z]) |
| `settle` | they rest now: birds to their perches, the cat sits, fish and moths slow |
| `call` | one call: a bird's, the cat's purr, the whale's song |

### The creatures

| Creature | Own count | What it does |
|---|---|---|
| `moth` | 40 | pale, 7 cm. They flutter in the projector's beam, between a tenth and three fifths of the way from the lens, lit by the beam. `attraction` is the share that keep to the beam. Without a beam they wander the region |
| `bird` | 6 (40 at most) | dark, 32 cm across the wings. They roost on perches (the path, or the region's top edges), turn now and then, and one at a time flit to another perch on an arc through the open air |
| `firefly` | 60 | yellow-green points low in the region. Each flashes every 1.5 to 6 s (a 0.6 s swell and fall), faint between |
| `cat` | 1 | dark, 42 cm. It walks its wall, sits a while, walks on and turns at the ends. Sitting down it purrs. It faces the way it walks: at an end (or a bend of more than about 57 degrees) it stops and turns on the spot, eased, in 0.35 s (a small turn) to 0.55 s (turning round), 0.3 s when it hurries or turns in the sight line, its legs stepping round; a gentler bend it steers through as it walks. Until 2026-11-09 it walked back facing the way it came |
| `deer` | 1 | every 300 s on average it comes out of the dark at one end of its path, grazes once or twice, and fades at the far end. By default its way runs past the viewer's left |
| `fish` | 48 | a silver school, 28 cm each. The school's centre wanders the region; `attraction` pulls it to the region's point nearest the screen. They take the screen's light on their flanks |
| `jelly` | 18 | bells of 35 cm that glow at the rim and pulse every 2 to 3 s. Each has a place on a ring round the picture, just clear of the sight line, in front of the screen or behind it |
| `ray` | 1 | a manta ray 4 m across its wings, dark above and pale below (the body shader's `belly`). Every 90 s on average (`every`), or on `pass`, it comes out of the gloom on one side, glides high over the room on a long gentle curve (the `path`, or a chord across the `region` at its height), banking a little into the turn, its wings beating slowly half the time and gliding the rest, and fades on the other side. 1.4 m/s at most; kept out of the sight line |
| `whale` | 1 | 14 m, dark, slow. It comes only when called (`every` 0 by default): a cue on `film.quiet` with a long cooldown. By default its way runs high behind the screen. A third of the way along it sings |
| `plane` | 2 at once | a red, a green and a white light and a soft white strobe every 1.5 s, on a great circle 160 m out, 17 to 52 degrees up. A crossing takes a minute or two. One every 75 s on average |

The flashes and the strobe are slow swells, far under the photosensitivity limit. With `blink` off or the room's
"Flickering lights" setting off, they glow steady.

### Out of the viewer's face and the sight line

- **The sight line** is the pyramid from the viewer's eyes to the picture's edges, widened by `keep_out`, from the
  eyes to the screen's plane. The eyes are the camera's; without a camera, the room's seat nearest the origin, 1.2 m
  up. It follows the screen when the viewer moves or resizes it.
- **Fliers and swimmers** (moths, birds, fireflies, fish, jellies) are pushed out of the pyramid every frame, and out
  of a `personal` sphere round the eyes.
- **Walkers** (the cat, the deer, the whale) follow their path. In the sight line they never stop, and go 2.5 times
  faster. The test holds each walker's longest time in the sight line under 4 s.
- **Moths in the beam** use the part of the beam over the viewer's head, outside the pyramid.
- **The Ambient life setting** (common, `life`): off, every creature fades away over 1.5 s; on, they fade back.

### Film reactions

The system reads no film signal itself. A room binds the live parameters in its document, so the host computes only
the channels a room uses. Suggested bindings:

| Creature | Binding |
|---|---|
| fireflies | `glow`: `{"bind": "film.brightness", "range": [1.0, 0.2], "smooth": 1}`: they dim while the film is bright |
| fish, jellies | `attraction`: `{"bind": "film.brightness", "smooth": 2}`: they come closer in a bright scene |
| jellies | `colour`: `{"bind": "film.colour", "strength": 0.5, "base": "#59bfff", "smooth": 1}` |
| birds | `activity`: `{"bind": "time.of_day"}`: they roost at night |
| planes | `activity`: `{"bind": "time.of_day", "invert": true}`: lights at night only |
| the whale | a cue: `{"when": {"signal": "film.quiet", "above": 0.9, "for": 4}, "states": ["playing"], "cooldown": 900, "steps": [{"do": "whale.pass"}]}` |

### Sounds

The whale's song, a bird's call and the cat's purr are sounds: the synthesiser's `whale`, `bird` and `purr`, from
where the creature is, on the Environment bus. Each is also an event (the signal `creature_event(what, at)` and the
list `events`). At the default `voice_db` (-12) the whale's song measures -53.8 dBFS RMS over its first 1.5 s, with
no distance, under the -38 dBFS target. As heard at a distance, and the `voice_db` to give each: "Sound and music",
"Ambient life's calls".

### The film layer

On the Frame the film layer is drawn over anything between the eyes and the picture. Ambient life does not make the
layer step aside. Instead, no creature goes into the sight line, so nothing of it is hidden and the film stays sharp.
Only a walker whose path crosses the sight line can be in it, and only while it trots through; on the Frame it is
hidden there for that moment. Rooms should give walkers paths clear of the sight line.

### Cost

Each creature is one draw: a MultiMesh for the many, one mesh for the cat, the deer and the whale (the sight-line check
puts a MultiMesh's base mesh at every seat). Measured at the own counts (`test_env_life.gd`):

| Creature | Triangles | Ticks (desktop, ms a frame) |
|---|---|---|
| moths | 240 | 0.37 |
| birds | 186 | 0.01 |
| fireflies | 120 | 0.24 |
| fish | 1632 | 0.22 |
| jellies | 1080 | 0.11 |
| planes | 16 | 0.01 |
| the cat | 86 | 0.01 |
| the deer | 98 | 0.01 |
| the ray | 35 | 0.01 |
| the whale | 240 (102 before 2026-11-08) | 0.00 |

All nine (before the ray) at once: 9 draws, about 3600 triangles, under 1 ms a frame on the desktop. The spec declares the largest (fish,
1700 triangles); 200 fish would be 6800. The time on the Frame is not measured yet.

### For the rooms

| Room | Use |
|---|---|
| Drive-in | `moth` in the beam; `plane` with `activity` bound to `time.of_day` inverted |
| Rooftop Athens | `cat` with a `path` along the wall top, clear of the sight line; `plane` |
| Reclaimed | `bird` with perches on the broken roof's edge; `firefly` low over the floor, `glow` bound to `film.brightness`; `deer` with a path along a side aisle |
| Bathysphere | `fish` (two schools, `schooling` 0.8 and 0.6) and `jelly` outside the glass, `attraction` bound to `film.brightness`, the bells' `glow` to `film.quiet`; a `ray` gliding over every 150 s; `whale` on the quiet-scene cue, its `chance` set by the room's whale setting |
