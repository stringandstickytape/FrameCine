# Cenote cavern

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/cenote_cavern.env.json` (Other worlds, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_cenote_cavern.gd`. An underground limestone sinkhole and bioluminescent crystal grotto cinema.
Rows of woven terracotta and emerald floor cushions sit on a tiered travertine viewing island encircled by a wide,
rippling emerald-turquoise cenote pool. Towering per-vertex-shaded karst limestone walls rise into an organic cavern
dome crowned by a jagged overhead jungle oculus framed in strangler-fig aerial roots, hanging liana vines and tropical
fern fronds open to the tropical night sky and Moon. Twin carved dark-basalt screen pylons rise from the far reef across
the water, lit by warm wrought-bronze cave lanterns, faceted mineral crystal clusters and silky volumetric moonlight
columns pouring into the lagoon.

## The parts

- **The cavern layout** (`domestic`, id `room`, `shell` `kit`): 19.0 x 12.0 x 20.0 m acoustic volume (`half_width`
  9.5 m, `front_z` -11.5 m, `back_z` 8.5 m, `height` 8.0 m, `vault_rise` 4.0 m) with plain domestic shell, windows,
  doors and ceiling lamps omitted so the sculpted karst grotto owns the view. The picture is 5.80 m wide and 3.26 m high
  (16:9), its bottom 0.82 m up, centred at `[0.0, 2.45, -10.8]`.
- **The seats** (`seats`, model `cushion`): four rows of three low woven floor cushions (`rows_front` 1, `rows_back` 2,
  `seats_per_row` 3, `seat_pitch` 1.05 m, `row_pitch` 1.45 m) in terracotta and emerald `woven_upholstery`. 12 seat
  transforms, one at the origin, with clear sight lines to the screen from every seat.
- **The cenote shell** (`kit`, piece `cenote_shell`, `kit/cenote_cavern.gd`):
  - Sculpted three-tier travertine limestone viewing island (`y = 0.0` at the viewer's seat stepping down to a submerged
    reef base at `-1.30 m`), curved stone water steps and rounded river-stone stepping boulders, keeping physics boxes
    well clear of `(0, 0, 0)`, plus a 25-plank weathered timber boardwalk bridge (`rustic_planks`) on pilings connecting
    the island aft to a sculpted arched rear grotto cave portal.
  - 20-ring smoothly per-vertex-shaded organic karst limestone cavern dome (`r` 12.5 to 15 m, vault rising to `+13.4 m`)
    built with `RoomMesh.sheet()` across six sectors, grounded by six terraced karst cliff buttresses rising directly out
    of the deep lagoon, four mossy limestone water islets, 44 clustered karst stalactites overhead (kept strictly above
    `y >= 5.5 m`), and 12 multi-spired flowstone stalagmite reef columns.
  - Wide jagged overhead jungle oculus (`r` ~5.15 m) collared in mossy crags and framed by 22 gnarled strangler-fig
    aerial roots, 32 cascading liana vines and 34 broad tropical fern fronds silhouetted cleanly against the starry sky
    and Moon.
  - Twin carved dark-basalt screen pylons (`dark_metal` volcanic stone) anchored in reef boulders at the far edge of the
    pool with aged-bronze clasps (`brass`) and a stepped carved architrave lintel.
  - Eight warm hanging wrought-bronze cave lanterns (`PieceLamps`, backed by 8 hidden `c.lamps` bake lights and 1 hidden
    downward oculus moonlight `SpotLight3D`, plus four low amber step markers) and 14 firmly anchored six-sided faceted
    mineral crystal clusters (`PieceCove`, `cove_floor` 0.45, live-bound to `setting.crystals`, backed by 2 live-tinted
    `c.footlights`).
- **The cenote pool and volumetric shafts** (`kit`, piece `cenote_water`, `CenoteWaterHall` via `c.halls`):
  - Wide mirror-rippling emerald-turquoise underground cenote pool (`CenotePool`, `y = -0.42 m`, radius 16.8 m) using
    the shared opaque `res://shaders/env_world_water.gdshader` (`Procedural.caustic_map()`, vertex `COLOR.r` shallow
    turquoise shelves around the island, islets and basalt reef, `COLOR.g` pool bloom beneath the light shafts, screen
    spill reflection, zero blend cost).
  - Two parallel silky-soft volumetric light shafts (`CenoteShaft`, `res://shaders/env_world_shaft.gdshader`,
    `edge_softness` 2.95, `wisp_strength` 0.65, group `env_see_through`) pouring from the overhead jungle oculus onto
    the left and aft turquoise pool without crossing the Moon or screen sight line. Both water and shafts scale their
    clock by the Motion setting and adapt live to `setting.time`, `setting.crystals` and playback state.
- **The light** (`light`): animated water `caustics` (`0.75` moonlight / `0.92` dusk / `0.40` starlight, `caustic_scale`
  1.4, `caustic_colour` tracking `setting.crystals`, `caustic_speed` 0.75), screen `spill` 1.1, `baked_fill` 0.20, warm
  cave lantern colour `[1.0, 0.78, 0.48]`.
- **The tropical sky** (`sky`): latitude `20.5°` N, `day_of_year` 195, gibbous Moon (`moon_bearing` 158°,
  `moon_altitude` 74°, `moon_phase` 0.88, `moon_size` 3.0) framed cleanly inside the overhead oculus, with stars and the
  Milky Way shifting smoothly across `setting.time`.
- **Cavern life and mist** (`life` & `atmosphere`): 42 golden-green `firefly` insects drifting through the cavern
  (`keep_out` 0.7, `personal` 1.8, strictly clear of the sight line, glowing brighter in dark film scenes) and two soft
  low water-surface mist layers (`fog_center` `[0.0, -0.43, -1.8]`, `fog_height` 0.40 m, held below the viewing island
  deck and controlled by `setting.mist`).

## Cues, tracks and settings

- **Tracks** (by `film.progress`): `sky.hour` advances from 20.5 to 23.5 (2 s smooth) and `sky.moon_altitude` drifts
  from 74° through 78° to 71° (2 s smooth), keeping the Moon visible inside the overhead jungle oculus for the entire
  screening. Timeline: 8 s start, 6 minutes of credits.
- **Cues:**
  - `lanterns_down` when `starting` or `playing`: dims `light.house_lamps` to `0.16` over 5 s while the glowing mineral
    crystals retain their `0.45` cove floor.
  - `lanterns_up` in `preshow` and `ended`: restores `light.house_lamps` to `1.0` over 4 s and releases `sky.dusk` over
    5 s.
  - `dusk_falls` when `playing` and `setting.time == "dusk"`: deepens `sky.dusk` smoothly to `0.90` over 120 s.
- **Room settings:**
  - `time` (`Sky and shaft`: Moonlight shaft, Dusk emerald, Starlight grotto; default Moonlight shaft — sets the sky
    twilight, Moon brightness, water caustics and volumetric oculus shaft colour and intensity).
  - `crystals` (`Mineral crystals`: Bioluminescent cyan, Amethyst crystal, Lanterns only; default Bioluminescent cyan —
    shifts the glowing crystal clusters, footlights and water caustics between cyan, amethyst and unlit translucent quartz
    under warm lanterns alone).
  - `mist` (`Water mist`: Soft mist, Clear air; default Soft mist — toggles the low mist drifting over the pool).

## Sound

- `acoustics` `stone_nave` (`rt60` 2.1 s, `damping` 0.35, `wet` 0.30, `predelay_ms` 48, `echo` 0.12) for the room's
  ambient sound beds. Document film acoustics on the 19.0 x 12.0 x 20.0 m box: `reflect` `[0.55, 0.55, 0.35, 0.42, 0.52,
  0.52]`, `rt60` 1.75 s, `wet` 0.62, `late` 1.85 (Sabine mean absorption `alpha` 0.247).
- `sound_bed` `cavern` (`cavern_hum`): `gain_db` -2, `film_db` -10.
- `sound_bed` `drips` (`drips`): placed around the cavern at radius 6.0 m (`reach` 6.0 m, 4 voices), `gain_db` -3,
  `film_db` -10.
- `sound_bed` `water` (`water_lap`): placed around the island at radius 5.0 m (`reach` 6.0 m, 4 voices, `pitch` 0.75),
  `gain_db` -4, `film_db` -10.
- `sound_bed` `crickets` (`crickets`): placed at the jungle oculus above (`[0.0, 14.0, -1.0]`, `reach` 18.0 m),
  `gain_db` -6, `film_db` -14.
- Measured by `test_room_cenote_cavern.gd`: pre-show `-52.9 dBFS` RMS (peak `-39.2`), under a reference film `-70.7 dBFS`
  RMS.

## Measured

By `test_room_cenote_cavern.gd` under Vulkan Forward Mobile (`lavapipe`, `54 checks, all passed`):

- Draws: 21 (limit 34).
- Triangles: 52,555 (limit 90,000).
- Live lights: 0 (8 hidden lantern bake lamps and 1 hidden downward moonlight spot).
- Particles: 0.
- Textures: 6.4 MB; lightmap atlas 380 x 320 (`PieceStatic`).
- Blended layers: mean 0.68, peak 4, share 0.36 (limit 1.00).
- Build time: 80.8 ms (0.9 pace units; limit 4.0).
- Sight lines: clear from all 12 seats; open overhead oculus directly up and toward the Moon.

## Not done yet

On the headset: not run.
