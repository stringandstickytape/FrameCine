# Showrooms

Rooms that ship with the app to show what the room system can do, and to measure what it costs the GPU. Each is a
plain room document (the same JSON as a kept room, `docs/assistant.md` "Rooms"), made from the libraries by a script,
read-only. The Room tab lists them in their own group, **Showrooms**, under the rooms.

- `app/tools/showrooms.gd`: makes them. Run it again when a library grows (an effect, a material or a built-in object
  added):
  `godot --headless --xr-mode off --path app --script res://tools/showrooms.gd` (in WSL, the engine fork's desktop
  build). `-- --check` writes nothing and exits 1 when the files differ from what it would write.
- `app/environments/showrooms/`: what it writes. `index.json` (the rows, in the Room tab's order, each with what it
  shows and its estimated budget), `<id>.room.json` (the document), `<id>.files/` (its models and pictures). A
  `.gdignore` keeps the editor from importing them; the app reads them as they are.
- `app/scripts/env/showrooms.gd`: the list. `main.all_environments()` ends with them (ids `showroom:<id>`), and
  `EnvLibrary.instantiate()` builds each with the room builder (`assistant_room.gd load_saved`), as a kept room.
- `app/tests/test_showrooms.gd`: the tests.

## The rooms

| Id | Name | What it shows |
|---|---|---|
| `effects` | Effects gallery | every effect for parts (43 now), each on a 0.3 m sphere in the previews' colour with the preview's options, by group |
| `materials` | Material wall | every library material (42 now) on a flat panel and a sphere, at its own scale, by kind (wood, stone and concrete, walls, metal, leather, fabric and carpet) |
| `objects` | Objects | the shapes (box, sphere, cylinder, plane, text), surfaces (colour, emission, see-through, a picture on a box three ways, a cut-out picture), every widget, the motions (spin, bob, sway, orbit, flap) and the object library's built-in objects |
| `lights` | Lights | real lighting: the key light with its shadows, the sky's fill, the film's light, a flickering point light and a spot light over things on the floor |
| `sky_<name>` | Aurora sky, ... | each sky effect (5 now) as the whole sky, in a room of its own |

The samples stand on a ring round the seat (at least 2.4 m away, wider when there are more), from 40 degrees right of
ahead round the back to the left, so the screen ahead stays clear; four rows from 0.55 m to 1.7 m. Each sample has its
name to its right, each group its title above. A room may hold 16 text parts (`RoomSchema.LIMITS.texts`), so one
column's names are one text part, its lines spaced to the rows. The engine drops empty lines, so the blank ones hold a
word joiner (U+2060): a line of its own height that draws nothing (`Label3D` skips glyph 0). The test lays the lines
out as `Label3D` does and checks every name is level with its sample.

Not shown: particles. A room that has particle parts when the app starts crashes the GPU driver (it is being fixed);
loading one later is fine, but a showroom is remembered as the room, so it would start in it next time. The `move_to`
motion (once, on the film's clock) is left out too. User objects never: they are the user's data.

## Budget

What one showroom may use (`BUDGET` in the tool), for a mobile GPU drawing both eyes at 72 Hz with a 4K film playing:
100 cost units (the room's own cap is 120, `RoomSchema.COSTS`), 16 text parts, 150 draw calls, 250 000 triangles and
3 lights. A room that would go over is split ("Effects gallery 2"), by group, then within a group. Every showroom is
also within the limits a room an assistant makes must keep (parts, widgets, texts, lights), so an assistant can change
one (the change is kept as the viewer's own room; the showroom stays as it is).

Estimated now (`index.json` budget: draw calls are a mesh each, a second pass, a box's second surface, a model's
parts, a text and its panel, a widget's quad, the sky, contact shadows, and the shadow casters again for the key
light's shadows):

| Room | Cost | Draw calls | Triangles | Texts | Lights |
|---|---|---|---|---|---|
| Effects gallery | 82.8 | 60 | 183 000 (43 spheres of 4 000) | 14 | 0 |
| Material wall | 72.0 | 98 | 179 000 (42 spheres) | 13 | 0 |
| Objects | 41.7 | 56 | 35 000 | 11 | 0 |
| Lights | 41.3 | 32 | 7 500 | 3 | key with shadows, point, spot |
| each sky | 2.0 | 2 | 4 500 | 1 | 0 |

The material wall holds all 42 materials' maps at once (about 50 MB of ASTC textures). The galleries are unlit
(ambient 0.7) so that only the Lights room pays for lighting.

## Measuring (the lead, on the headset)

`perf_rooms` (dev link; `app/scripts/assistant/room_perf.gd measure_rooms`) shows each room in turn and, in each, sets
each foveation level, waits `settle` s (the room's shaders compile, the runtime takes the new level), then measures
the GPU for `seconds` s with the same timer as `perf` (the root viewport, both eyes). A baseline room comes first, so
each row has `delta_gpu_ms`: the room's own cost at that level. Foveation is set as the System tab does but not saved,
and kept while the panel shows; afterwards the viewer's room and foveation come back.

1. Deploy the app (`tools/push-app.sh`) and start it on the headset with the dev link.
2. Play a film, the usual 4K test film, looping (`open` it; the numbers without one are not representative, and the
   reply says so).
3. Close the panel (it is drawn too; the reply notes it if it was open).
4. Run, with a long timeout (all ten rooms at three levels, 3 + 5 s each, take about 4 minutes):

   ```
   python tools/listener.py send -t 600 perf_rooms
   ```

   Or some rooms, some levels, longer windows:

   ```
   python tools/listener.py send -t 300 perf_rooms rooms=showroom:effects,showroom:materials foveation=off,high seconds=10
   ```

   Arguments: `rooms` (ids from `room_settings`, a list or comma-separated; `showrooms` for all, the default),
   `foveation` (`off`, `low`, `medium`, `high`; default off, low, high), `baseline` (default `void`; empty for none),
   `settle` (3 s), `seconds` (5 s).
5. Read `table` (a line per room: each level's GPU ms and the difference from the baseline) and `rows`
   (`gpu_ms`, `gpu_ms_p95`, `cpu_ms`, `fps`, `frames`, `dropped`, `delta_gpu_ms`, and `foveation_applied`: the level
   the runtime had, 0 off to 3 high; -1 when foveation wasn't applied). `budget_ms` is the frame's (13.9 ms at
   72 Hz); `notes` says what makes the numbers less than representative.

By hand: the Room tab's Showrooms, the System tab's Foveation, and `perf` after a minute (its 60 s window).

Untested: on the headset (the numbers above are estimates; the measurements are the lead's), and how the labels read
in the lenses at 2.4 m and more.
