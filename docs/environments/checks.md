# The checks

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each part is.

`scripts/env/env_checks.gd`, run by `tests/test_environments.gd` over every `app/environments/*.env.json`, and by
`tests/test_env_checks.gd` against a bad document for each check.

1. **Schema:** `RoomSchema.validate(doc, "new")`, with the version 4 sections. A field of an object can be
   `"required": true` (`env_doc.gd _options()`): an entry without it is refused, "missing", with its path. It is for a
   field with no sensible default: a band of scenery with no shape is a mistake in the document, not a row of whatever
   the system would draw in its place.
2. **Headset budget:** the room is built headless and measured: draw calls (one a mesh surface), triangles, live
   lights (the bake's hidden lights do not count), particles, and texture memory (the images' bytes with mip levels).
   Texture memory is the headset's: a library map counts its ASTC blocks as loaded from its `.mtex`
   (`MaterialLibrary.FRAME_BYTES_META`), so the figure is the same headless, under lavapipe and on the Frame. Before
   2026-11-07 a rendered measure counted the maps as a GPU without ASTC holds them, decompressed (the cinema read
   144 MB under lavapipe against 9 MB on the Frame).

   | Budget | Per room | The cinema | The Void |
   |---|---|---|---|
   | draw calls | 40 | 19 | 1 |
   | triangles | 400 000 | 194 856 | 2 |
   | live lights | 2 | 0 | 0 |
   | particles | 4 000 | 0 | 0 |
   | texture memory | 96 MB | 9.0 MB | 0 |

   The budget leaves room for a sky, weather and life on top of a hall like the cinema. Measured headless
   (`test_environments.gd`); the GPU time on the Frame is the showrooms' measure (`docs/showrooms.md`).

3. **Clear sight line:** from every seat's eyes (1.2 m over its floor point) to nine points of the default screen
   (its corners, edges and centre, 5 % in), nothing static is hit: the room's meshes and seats as physics shapes, ray
   by ray. A seat's own back and anything behind the eyes do not count. A MultiMesh stands at the seats unless it has
   meta `env_placed` (an Array of its instances' transforms, since 2026-11-08: the drive-in's parked cars), which
   places it there instead (a headless MultiMesh keeps no transforms of its own). A mesh in the group
   `env_placed_in_shader` (`PLACED_IN_SHADER`) is not read: its vertices are not where it is drawn (a vertex shader
   carries them there: the passing system's scenery lies about each item's own foot in its mesh). Read as it is, it
   is a heap at the room's origin round the viewer's head, and it would hide everything behind it. What it costs is
   still counted; where it can be is its system's to say (`flow_volumes()`, item 10).
4. **Comfort:** no system moves the viewer; every `motion` parameter within its limit; every binding on a
   `brightness` parameter smoothed by at least 1 / (2 pi MAX_HZ) seconds; every cue fade on one at least
   1 / (2 MAX_HZ) seconds.
5. **Licences:** every library material the room uses is CC0 (its catalogue entry) and in `app/materials/CREDITS.md`;
   every asset in `credits` is CC0 and in `app/environments/CREDITS.md`; synthesised sounds are ours.
6. **Names:** no real mark in any text of the document (`env_checks.gd MARKS`, whole words, any case). Pastiche is
   fine; the real mark never: "Sirclive", not the computer maker's name; "FreeDTV", not the broadcast platform's.
7. **No people:** no system of a people kind, no object whose id or name says person, people, crowd, audience,
   human, mannequin or figure.
8. **Blended layers** (since 2026-11-09): from the room's own seat, looking at the screen, how many blended
   surfaces (glass, haze, glows, flames) lie over each part of the view before the first solid one
   (`blend_layers()`). The triangle count cannot see this, and it is what fills the frame on the headset: a glass
   dome is a few thousand triangles and the whole view. The view is 110 x 100 degrees in cells of 2.5 degrees;
   every crossing counts, a volume's far side as its near one. Budget: 1.0 layer on average (`BLEND_BUDGET`).
   Not counted: particles (the budget has their number), a MultiMesh, quads a vertex shader turns to the eye
   (halos), a mesh in `PLACED_IN_SHADER` (item 3), and anything hidden when the room is built with no film (a
   projector's haze). `flow_clear()` (item 10) reads the room's meshes the same way, without them.
9. **Build time** (since 2026-11-09): a room is built on the main thread when the viewer chooses it, and no frame
   is drawn until it is done. The check measures the machine first (`pace()`: a fixed piece of the same kind of
   work) and counts a room's second build in those (`build_units()`). Budget: 4.0 (`BUILD_BUDGET`). The first
   build of a run also draws the room's pictures; those are kept between runs (below, "The pictures a room draws").
   `BUILD_WAIVED` lists the rooms over the budget when the check came in. It is a list to shorten.
10. **Scenery that goes by** (since 2026-11-09; the passing system, `docs/environments/passing.md`): a system may
    judge its own parameters' comfort (`static comfort_for(params)`, asked by `comfort()`), and `flow_clear()` holds
    moving scenery away from the picture. The limits are constants of `env_checks.gd`, with the reasons beside them:

    | Limit | Value | Constant |
    |---|---|---|
    | the fastest anything crosses the eye, at its nearest | 20 degrees a second | `FLOW_MAX_DEG` |
    | the nearest anything passes the line the room's own seat travels along | 3 m | `FLOW_NEAREST` |
    | how fast the speed changes | 0.3 m/s² | `FLOW_ACCEL` |
    | clear of the picture's edges, from the room's own seat | 10 degrees | `FLOW_CLEAR_DEG` |
    | the Motion setting under which nothing goes by at all | 25 % | `FLOW_MOTION_FLOOR` |

    The scenery only ever goes straight and level. `FLOW_MAX_DEG` is a first judgment: the first journey on the
    headset is there to test it.
11. **Film-time tracks** (since 2026-11-09): `comfort()` reads `timeline.tracks` too. A seek moves a track from one
    key to another in a frame, so a track on a `brightness` parameter needs the same `smooth` as any binding.

## What the rooms measure

Measured headless on 2026-11-09 (`test_environments.gd` prints the table; the desktop's pace was 76 ms).

| Room | Draws | Triangles | Blended layers | Build | First build of a run |
|---|---|---|---|---|---|
| Atmospheric 1928 | 31 | 262 756 | 0.00 | 2.6 | 768 ms |
| Bathysphere | 27 | 105 480 | 0.57 | 0.8 | 120 ms |
| Cinema | 19 | 194 856 | 0.00 | 0.2 | 80 ms |
| Crater | 23 | 161 170 | 0.43 | 7.1 (waived) | 1024 ms |
| Drive-in 1958 | 27 | 151 134 | 0.14 | 2.9 | 303 ms |
| Flagship | 28 | 220 134 | 0.01 | 1.4 | 132 ms |
| Ice cinema | 20 | 75 495 | 0.16 | 2.3 | 277 ms |
| Nave | 19 | 112 510 | 0.00 | 3.1 | 1077 ms |
| Palace of Culture 1974 | 29 | 178 958 | 0.00 | 1.0 | 773 ms |
| Pillow Fort 1993 | 23 | 5 444 | 0.00 | 0.2 | 35 ms |
| Pink Palace | 29 | 282 576 | 0.00 | 1.0 | 276 ms |
| Reclaimed | 24 | 256 051 | 0.11 | 13.9 (waived) | 1106 ms |
| Athens rooftop | 25 | 139 894 | 0.00 | 3.0 | 569 ms |
| Screen 3, 1983 | 25 | 79 946 | 0.00 | 0.2 | 117 ms |
| Screening room 1962 | 28 | 33 632 | 0.17 | 0.9 | 982 ms |
| Shopfront 1906 | 32 | 28 961 | 0.00 | 0.5 | 1326 ms |
| Streamline 1937 | 27 | 201 342 | 0.00 | 0.6 | 239 ms |
| The television rooms (12) | 13 to 29 | 1 110 to 10 390 | 0.00 to 0.17 | 0.1 to 0.3 | 8 to 44 ms |
| Void | 1 | 2 | 0.00 | 0.0 | 2 ms |

What this says:

- **Blended layers are low everywhere.** The Bathysphere runs at the frame's edge on the headset (p95 15 ms against
  13.9 ms), and its glass is only 0.57 of a layer. Its cost is in the shading of its water, which no count made here
  can see. The check guards against a room that stacks glass on haze; it does not explain the Bathysphere.
- **Only the headset can measure shading.** `perf_rooms` (`docs/showrooms.md`) takes a room's GPU time there.
  `tools/room_perf.py` runs it over every room that ships (below, "On the headset").
- **The first build of a run is the long wait,** and it is nearly all pictures: the Shopfront takes 1.3 s the first
  time and 0.04 s after. Two rooms are slow every time, in their geometry: the Crater and Reclaimed.

## The pictures a room draws

`scripts/env/proc_cache.gd`. A room's own maps and pictures are drawn in code the first time a room that uses them
is built, and each generator keeps them in memory for the rest of the run. `ProcCache` keeps them on disk under
that: `user://env_cache/<stamp>/<key's hash>.pic`.

- **The key** is the generator's file, the name of its own memory and that memory's key. The generator already
  decided what tells one of its pictures from another; the disk uses the same answer.
- **The stamp** is one MD5 over every script under `app/scripts/env`. A change to any of them empties the cache, so
  an update redraws each room once. It is coarse on purpose: a generator calls helpers in other files.
- A file is written beside its place and moved into it; a file that is not whole is drawn again.
- `ProcCache.enabled = false` draws every time (`tests/test_env_proc_cache.gd` compares the two).

The generators that keep their pictures on disk (since 2026-11-09; each under its own memory, `scripts/env/systems/`):

| File | Memory | What it holds |
|---|---|---|
| `kit/procedural.gd` | `_maps` | a pattern's albedo, normal and packed maps, and their mean (one float pixel) |
| `kit/procedural.gd` | `_pictures` | the rose window, a sign's letters, gradients, caustics, the abstract canvases, the colour-field canvas, a flame |
| `kit/shopfront_pictures.gd` | `_cache` | the Shopfront's maps (and their mean), the bills, the street, the window's lettering, the roll |
| `kit/shopfront_edwardian.gd` | `_orms` | a flat packed map for each roughness |
| `kit/nave_gothic.gd` | `_maps_cache`, `_rose_tex` | the stone's maps (and their mean); the rose's glass |
| `kit/mosaics.gd` | `_atlas` | both murals in one map |
| `kit/earth_map.gd` | `_texture` | Earth's face |
| `kit/ice_hall.gd` | `_flame_picture`, `_ice_map` | a candle's flame and halo; what is frozen in the ice |
| `kit/lunar_surface.gd` | `_detail` | the regolith's fine relief |
| `kit/screening_1962.gd` | `_city_picture` | the city's lights |
| `kit/dome_fittings.gd` | `_face` | a gauge's face |
| `kit/flagship.gd` | `_atlas` | the seat numbers and row letters, lit and engraved |
| `kit/reflect.gd` | `_flat` | flat maps for paint and chrome |
| `sky.gd` | `_noise` | the noise every sky layer draws from |
| `vehicle.gd` | `_pictures` | the dials' faces, by their glow |

Left alone:

- `kit/nave_gothic.gd` `_atlas_cache` (the windows' glass, 596 ms on the desktop): its key is the windows' names, but
  each window's picture is drawn from its tracery's shape, which the nave's widths change.
- Pictures drawn at every build, with no memory: `kit/athens_roof.gd` `poster_picture()` (12 ms),
  `kit/drive_in_lot.gd` `board_picture()` (4 ms), `halo_picture()`, `bulb_picture()`, `window_picture()`,
  `auditorium.gd` `exit_picture()`, `booth_picture()`, `port_picture()` (each 1 ms or less); `projector.gd`'s motes
  (random points, not a picture).
- Memories of other things: fonts and glyph pages (`kit/shopfront_pictures.gd` `_fonts`, `_glyph_pages`), noise
  generators (`kit/reclaimed.gd` `_noises`, `kit/nave_gothic.gd` `_fnl`), meshes (`kit/seabed.gd` `_ico_cache`),
  materials and shaders (`kit/builder.gd` `GLASS`, `gltf_room.gd` `_cut_shaders`), textures from files
  (`material_library.gd`), star data (`sky.gd` `_catalogue`, `_field`), sounds and levels (`env_synth.gd`,
  `sound_bed.gd`, `presentation.gd`).
- Two keys round their argument (`kit/reflect.gd` `_flat` to 0.01, `kit/procedural.gd` `colour_field()` to 0.001)
  and a colour in a key is written to 4 decimals; they are kept all the same, as the memory decided.

Measured headless on the desktop (2026-11-09, `test_env_proc_cache.gd`): every room built once in a fresh process,
first with an empty cache (58 pictures drawn), then in a second process that reads them all.

| | Every room built |
|---|---|
| Drawn (the first run after an update) | 9201 ms |
| Read from disk | 4975 ms (54 %) |

The largest savings: Shopfront 1906 1319 to 67 ms, Screening room 1962 935 to 95 ms, Palace of Culture 1974 794 to
120 ms, Crater 1050 to 514 ms, Athens rooftop 507 to 225 ms.

## On the headset

`tools/room_perf.py` writes `docs/environments/perf.md`: each room's GPU time (mean and p95) and dropped frames, from
`perf_rooms`. Not run yet.

- `tools/room_perf.py run [--seconds 10] [--settle 4] [--foveation off] [--rooms a,b,c]` measures every room of
  `app/environments/*.env.json` (sorted), or the ones given, on the headset through `tools/listener.py send
  perf_rooms` (the Void first, the baseline). It saves the result as `docs/environments/perf.json` and writes the
  table to `docs/environments/perf.md`. It needs the listener running and the headset on the dev link; play a film
  first and close the panel.
- `tools/room_perf.py format RESULT [OUT]` writes the same table from a saved result (OUT: standard output by
  default).

It never starts the listener and never reaches the headset by any other way: when the send fails it prints the
listener's error and exits 1, writing nothing. `tools/test_room_perf.py` tests it without the headset.
