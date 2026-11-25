# Sunken rotunda

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/sunken_rotunda.env.json` (Other Worlds, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_sunken_rotunda.gd`. A flooded classical marble Atlantis rotunda resting on the sunlit ocean floor
beneath animated underwater caustics. A circular stepped marble sanctuary dais inlaid with a woven sea-jade and gold
mosaic medallion sits dry at the heart of a knee-deep flooded peristyle ring canal, encircled by twelve towering fluted
veined-marble columns, solid arched colonnade bays, and a partially ruined coffered dome opening to a vast ocean oculus.
Sunlit pelagic light shafts slant down through the oculus and across a romantically collapsed aft-starboard bay, while
monumental twin carved marble-and-bronze screen pylons rise from the forward canal edge. Beyond the colonnade,
silhouetted outer aqueduct arches fade into turquoise ocean depths as silver schooling fish, bioluminescent jellies, an
overhead gliding manta ray, and a rare passing whale drift through the deep.

## The parts

- **The room frame** (`domestic`, id `room`, `shell` `kit`): 20.0 m wide (`half_width` 10.0), 20.0 m deep (`front_z`
  -11.0 to `back_z` 9.0), 8.0 m eave height with 3.5 m vault rise (11.5 m acoustic envelope), supplying the screen frame,
  seat transforms, and room metrics while `kit` builds the entire classical sanctuary and flooded canal. No default room
  lamps, windows, doors, heaters, fort, or fairy lights. The picture is 6.20 m wide and 3.49 m high (16:9), bottom at
  1.005 m, centred at `[0.0, 2.75, -10.2]`.
- **The seats** (`seats`, model `club_chair`, `from_builders` true): twelve deep sea-teal `velvet` club armchairs on
  tarnished `brass` frames arranged on the dry mosaic sanctuary dais — four rows of three (`rows_front` 1, `rows_back`
  2, `seats_per_row` 3, `seat_pitch` 1.15 m, `row_pitch` 1.55 m), viewer's own seat at `(0, 0, 0)` with clear sight
  lines to the screen from every seat.
- **The sunken marble sanctuary** (`kit`, id `fittings`; `kit/sunken_rotunda.gd`):
  - `rotunda_hall`:
    - Circular stepped dry veined-marble sanctuary dais (radius 5.80 m, centred at `[0.0, 0.0, -1.0]`, floor at `y = 0`)
      inlaid with the procedural `mosaic_medallion` star rosette (`r = 4.25 m`), framed by sea-jade and tarnished-bronze
      inlay rings, sculpted low parapet curbs with four ceremonial stepped landings, submerged wet marble steps
      (`y = -0.11 m` and `-0.22 m`) descending into the knee-deep peristyle ring canal (`r = 5.80..11.60 m`, water
      surface at `y = -0.25 m`, submerged flagstone bed below), and indirect rim-lip cove lighting (`PieceCove`,
      `cove_floor` 0.38).
    - Twelve 12-flute entasis-tapered veined-marble Classical columns on `r = 9.20 m` (leaving a wide 66-degree forward
      screen bay and eleven 26.73-degree arched colonnade bays), moulded attic bases, echinus capitals, solid impost
      piers (`y = 5.85..7.75 m`), semicircular moulded arches with keystones and bronze bosses, a continuous circular
      entablature (`y = 7.75..8.65 m`) with bronze frieze trim, and a partially ruined 16-rib, three-tier coffered dome
      ring with bronze coffer rosettes framing a wide open ocean oculus (`y = 11.10 m`, `r = 4.85 m`). The aft-starboard
      column (`+86.45°`) is broken off low with jagged fracture blocks along the breached entablature and dome ribs,
      cantilevered arch haunches, and three tumbled fluted column drums resting on the submerged steps below.
    - Monumental twin carved white-marble and tarnished-bronze screen pylons (`x = ±3.88 m`, `z = -10.2 m`) rising from
      the forward canal edge with recessed sea-jade panels, bronze lozenge reliefs, a sculpted wave-scroll architrave
      frieze, a broken raking pediment crowning a radiant solar-compass crest with a glowing crystal orb, a dark matte
      backing slab, and indirect `PieceCove` reveal washes.
    - Eight waterproof bronze-and-crystal Atlantis floor lanterns on carved rim pedestals (`r = 5.46 m`, `bake_lamps` 8,
      `PieceLamps` with gentle film-time ember retention) plus two pylon-top crystal braziers.
    - Nine sunken terracotta amphorae with twin handles, five weathered frieze rubble blocks, nineteen branching and
      brain coral reef clusters, and eighteen swaying underwater sea-fern clumps distributed along the outer canal steps
      and column plinths.
  - `rotunda_water` (`RotundaWaterHall`, registered in `c.halls`, 3 draws, 0 live lights):
    - `RotundaWater`: opaque rippled ocean and flooded marble canal surface extending smoothly from `r = 5.65 m` to
      `155.0 m` (`res://shaders/env_world_water.gdshader`, `Procedural.caustic_map()`, live clock scaled by Motion,
      submerged marble flagstone sheen near the canal, screen spill reflection, golden/cyan lantern glints, and smooth
      pelagic palette shifts bound to `setting.water_light`).
    - `RotundaShafts`: six volumetric pelagic underwater light shafts slanting through the ruined oculus and starboard
      breach (`res://shaders/env_world_shaft.gdshader`, in group `"env_see_through"`, live clock and `setting.water_light`
      intensity, placed strictly clear of the cinema screen).
    - `RotundaAqueducts`: four distant ruined outer aqueduct arcs and three monoliths silhouetted in the deep
      (`r = 25.5..36.5 m`), tinting live with `setting.water_light`.
- **The light** (`light`): cool sunlit pelagic fill (`fill_top` `[0.38, 0.68, 0.76]`, `fill_bottom` `[0.08, 0.20, 0.24]`),
  warm bronze-lantern bake light (`[1.0, 0.78, 0.44]`, `lamp_energy` 2.8, `lamp_range` 7.5), strong animated screen
  spill (`1.15`), `baked_fill` 0.18, and animated underwater caustics (`caustic_scale` 1.3, `caustic_speed` 0.75,
  strength 0.85 / 0.45 / 0.24 and colour shifting live with `setting.water_light`).
- **The pelagic ocean dome** (`sky`): `mode` sky, `stars` 0.0, `milky_way` 0.0, transitioning smoothly via live `dusk`
  and `blackout` bindings from sunlit turquoise (`#12687e` zenith / `#063244` horizon) to deep sapphire (`#08254c` /
  `#020f24`) and dark bioluminescent night, over a matching deep ocean floor (`#052838`).
- **Marine life** (`life`, five systems, every region strictly outside the dry dais and clear of the screen sight line):
  - `port_fish`: 34 silver `fish` (`schooling` 0.75, `x = -15.5..-7.6 m`, `y = 1.2..7.2 m`), `attraction` following
    `film.brightness`.
  - `starboard_fish`: 28 silver-teal `fish` (`schooling` 0.75, `x = 7.6..15.5 m`, `y = 1.2..7.2 m`), `attraction`
    following `film.brightness`.
  - `jellies`: 14 bioluminescent `jelly` blooms (`size` 1.85, `y = 5.6..10.4 m`), tinting gently toward `film.colour`
    with glow rising in deeper water modes (`0.95` sunlit to `1.75` bioluminescent).
  - `manta`: gliding `ray` (`size` 1.45, `every` 140 s) sweeping overhead across the ruined dome oculus
    (`y = 11.6..13.6 m`).
  - `whale`: rare passing `whale` (`size` 0.9, `voice_db` -4.0) gliding along `[-26, 5.2, -19] -> [0, 6.4, -22] ->
    [26, 5.0, -19]` beyond the far colonnade arches during quiet film scenes (`film.quiet`).

## Settings and cues

- **Settings:**

  | Setting | Choices | Default | What it moves |
  |---|---|---|---|
  | `water_light` (`Water light`) | `sunlit` (`Sunlit turquoise`), `sapphire` (`Deep sapphire`), `bioluminescent` (`Bioluminescent night`) | `sunlit` | Ocean dome `dusk`/`blackout`, animated caustics strength and colour, water surface palette, volumetric shaft glow, distant aqueduct tint, and jellyfish glow |
  | `lanterns` (`Lanterns`) | `gold` (`Warm gold`), `cyan` (`Sea cyan`), `dim` (`Dim`) | `gold` | Waterproof floor lantern and pylon brazier `glow_colour`/`glow_mix`, and indirect marble cove brightness and hue |
  | `whale` (`Whale`) | `rare` (`Rarely`), `sometimes` (`Sometimes`), `never` (`Never`) | `rare` | Frequency and chance of distant whale passes and whale song cues during quiet scenes of the film |

- **Cues:**
  - `dim` when `starting` (requires `setting.dim`): dims `light.house_lamps` to `0.18` over 4.5 s while the sanctuary
    coves retain their `0.38` floor.
  - `lights_up` in `preshow` and `ended`: restores `light.house_lamps` to `1.0` over 4.0 s.
  - `opening_bell` when `starting` (requires `setting.ritual`): strikes the distant underwater `bell` (`temple_bell`).
  - `far_song_rare` / `far_song_sometimes` during `playing` when `film.quiet` holds above `0.9` for 8.0 s: triggers the
    distant `far_song` whale call (`30%` / `1200 s` cooldown on `rare`, `55%` / `600 s` on `sometimes`; suppressed on
    `never`).
  - `whale_rare` / `whale_sometimes` during `playing` when `film.quiet` holds above `0.9` for 4.0 s: sends `whale.pass`
    across the far colonnade arches (`30%` / `1800 s` cooldown on `rare`, `70%` / `900 s` on `sometimes`; suppressed on
    `never`).
- **Timeline:** 8 s start, 6 minutes of credits.

## Sound

- `acoustics` `stone_nave` (`rt60` 1.8, `damping` 0.35, `wet` 0.34, `predelay_ms` 45.0) for the room's ambient beds.
  Document film acoustics: `reflect` `[0.54, 0.54, 0.42, 0.36, 0.50, 0.50]`, `rt60` 1.55 s, `wet` 0.60, `late` 1.78
  (resonant flooded stone rotunda, Sabine mean absorption `alpha` 0.28).
- `sound_bed` `deep` (`deep_hum`): ocean-floor sub-bass bed (`gain_db` -4.0, `film_db` -10.0).
- `sound_bed` `canal_lap` (`water_lap`): four voices placed around the flooded peristyle canal at `[0.0, 0.2, -1.0]`,
  `radius` 6.5, `pitch` 0.72, `gain_db` -3.0, `film_db` -10.0.
- `sound_bed` `reef_bubbles` (`bubbles`): reef stream at `[9.0, 1.5, -5.0]`, `reach` 12.0, `gain_db` -4.0, `film_db`
  -10.0.
- `sound_bed` `bell` (`temple_bell`): ceremonial opening bell near the forward screen pylons at `[0.0, 3.0, -9.5]`,
  `reach` 18.0, `gain_db` -4.0, `film_db` -10.0.
- `sound_bed` `far_song` (`whale`): distant abyssal call at `[-20.0, 11.0, -22.0]`, `reach` 32.0, `gain_db` -5.0,
  `film_db` -10.0.
- Measured by `test_room_sunken_rotunda.gd` and `test_room_acoustics.gd`: pre-show `-52.9 dBFS` RMS (peak `-40.1 dBFS`),
  under a film at the reference `-72.4 dBFS` RMS (`C80` 16.5 dB, reverb/direct `-11.5 dB`, `T20` 1.20 s, `alpha` 0.28).

## Measured

By `test_room_sunken_rotunda.gd` under Vulkan Forward Mobile (`lavapipe`, `53 checks, all passed`):

- Draws: 21 (limit 34).
- Triangles: 50,703 (limit 90,000).
- Live lights: 0.
- Particles: 0.
- Textures: 6.3 MB, lightmap atlas 876 x 668 (limit 2048).
- See-through overdraw (`blend_layers`): mean 0.39, peak 3, share 0.22 (limit 1.00).
- Second-build time: 105.6 ms (1.20 pace units; limit 4.00).

## Not done yet

On the headset: not run.
