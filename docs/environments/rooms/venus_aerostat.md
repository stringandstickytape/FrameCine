# Venus aerostat

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/venus_aerostat.env.json` (Other worlds, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_venus_aerostat.gd`. A gilded hammered-copper, burnished-brass and cream-enamel Art Nouveau
pressurised observation gondola suspended 52 km above Venus inside sunlit golden-amber cloud canyons beneath a vast
glowing ivory-and-gold buoyant aerostat gas envelope. Sixteen sweeping arched panoramic observation bays and a 7.1 m
ribbed skylight oculus open onto sculpted amber, ochre and burnt-sienna cloud-canyon walls, slanting golden sunbeams,
four distant floating companion aerostats, and very slow soft lower-deck sheet lightning.

## The parts

- **The room frame** (`domestic`, id `room`, `shell: "kit"`): 13.0 m wide (`half_width` 6.5), 14.0 m long (`front_z`
  -7.5, `back_z` 6.5), height 6.8 m with 2.2 m vault rise (`lamps` 0, `ceiling_light` 0, all shell geometry left to the
  kit). The picture is 5.20 m wide and 2.925 m high (16:9), centred at `[0.0, 2.55, -6.9]`.
- **The seats** (`seats`, model `lounge`, `from_builders` true): three rows of three plush deep sea-teal velvet lounge
  armchairs on walnut legs (`rows_front` 1, `rows_back` 1, `seats_per_row` 3, `seat_pitch` 1.25 m, `row_pitch` 1.75 m),
  centred on the viewer's own seat at `(0, 0, 0)` with clear sight lines from all nine seats.
- **The Art Nouveau gondola** (`kit`, id `gondola`, `bake_lamps` 8; `kit/venus_aerostat.gd`, piece `venus_gondola`):
  - Octagonal inlaid herringbone parquet oak deck with dark walnut border inlay, inlaid brass fillets, a central brass
    and walnut compass rose in the forward gallery, and an octagonal deep sea-teal velvet salon rug beneath the seating
    island.
  - Patinated hammered-copper lower pressure dado (`y = 0..1.05 m`) with verdigris plinths, riveted burnished-brass
    pressure bands, recessed copper coffers and sculpted walnut viewing sills.
  - Sixteen sweeping arched brass-and-copper panoramic observation bays wrapping port, starboard, diagonals and aft,
    framed by eight master corner piers, delicate brass spandrel rings and crystal-clear single-surface glazing
    (`PieceGlass`, tuned to `alpha` 0.045, `rim` 0.16).
  - Wrought-brass Art Nouveau mezzanine inspection catwalk balustrade (`y = 4.65..5.56 m`) carried on pier-aligned
    curved brass cantilever brackets, surmounted by eight curved copper-and-brass dome ribs framing a 7.1 m skylight
    oculus compression ring.
  - Ornate cream-enamel, hammered-copper and brass screen proscenium on a two-step oak-and-brass dais with curved
    botanical brass whiplash arches, a central sunburst medallion crest, warm indirect cove troughs (`PieceCove`,
    `cove_floor` 0.40) along the proscenium, mezzanine soffit and skylight ring, and eight frosted-opal tulip wall
    sconces plus four mezzanine tulip pendants (`PieceLamps`).
  - Scientific cloud-city props placed around the perimeter (clear of sight lines and at least 0.5 m from the origin):
    two hanging geodesic glass botanical terrariums overflowing with lush emerald ferns, two aft hammered-copper fern
    urns, an aft-starboard brass atmospheric barometer and optical spectrometer console with three backlit warm amber
    dials (`PieceWindows`) and a glass-and-brass mercury barometer column, a forward-starboard brass altitude binnacle
    with crimson and emerald corrector spheres, a riveted circular aft copper airlock hatch with a 6-spoke burnished
    brass wheel and glowing amber equalizer port, and a working brass astronomical gondola clock (`PieceClock`)
    crowning the aft arch.
- **The Venusian cloud canyons and aerostats** (`kit/venus_aerostat.gd`, piece `venus_clouds` via `c.halls`):
  - `VenusCloudSphere`: 360-degree opaque cloud-canyon sphere (`r = 160 m`, 1 draw, zero alpha blend) shaded by
    `app/shaders/env_venus_clouds.gdshader` — glowing hazy golden-ivory upper zenith with diffused Venusian solar bloom
    and drifting cirrus wisps, towering sunlit saffron and ochre cloud-canyon walls, swirling burnt-sienna lower cloud
    strata scaled by `Motion`, and very slow soft distant lower-deck sheet lightning (< 0.25 Hz cosine swells, strictly
    off when `setting.lightning == "off"` or `Flickering lights` is off).
  - `VenusEnvelope`: vast glowing ivory-and-gold fluted buoyant aerostat gas envelope hovering 13–28 m overhead with
    gilded load bands, swept copper-and-brass tail stabilizer fins, an open brass-and-copper lattice keel harness with
    amber navigation beacons, and sixteen taut bronze rigging cables anchored to the gondola's upper compression rings.
  - `VenusCompanions`: four distant floating companion buoyant aerostats gliding gently at 70–106 m distance across the
    golden cloud canyons (one `MultiMeshInstance3D`, 1 draw, frozen when `Motion < 0.25`).
  - `VenusCloudShafts`: five soft slanting golden Venusian sunbeams strictly outside the gondola
    (`app/shaders/env_world_shaft.gdshader`, group `env_see_through`).
- **The light and sky fallback** (`light`, `sky`): warm sunlit-amber hemisphere fill (`[0.96, 0.78, 0.52]` over
  `[0.34, 0.22, 0.14]`), screen spill 0.65, zero live lights; muted golden Venusian sky fallback behind the cloud sphere
  (`dusk` 0.4, `stars` 0.0, `twilight_zenith` `#d49c54`, `twilight_horizon` `#e8b468`, `ground` `#5c3014`).

## Settings and cues

- **Room settings:**
  - `cloud_light` (`Cloud light`: Amber noon, Copper sunset, Stormy gold; default Amber noon) — shifts the sunlit
    Venusian cloud canyon palette, sunbeams, overhead envelope illumination and companion aerostats live.
  - `cabin_coves` (`Cabin coves`: Warm brass, Botanical emerald, Dim; default Warm brass) — controls the indirect
    Art Nouveau cove glow along the screen proscenium, mezzanine cornice and skylight oculus ring.
  - `lightning` (`Sheet lightning`: Distant glow, Off; default Distant glow) — enables or disables the slow distant
    lower-deck sheet lightning glow (also forced off whenever `Flickering lights` is off).
- **Cues:**
  - `dim` when `starting`: fades `light.house_lamps` to 0.15 and `light.accent` to 0.45 over 5 s while the cloud
    exterior smoothly mellows to 0.42 radiance for cinema screen contrast (`cove_floor` 0.40 holds warm cove trim).
  - `departure_chime` when `starting` (requires the `ritual` pre-show setting): plays `chime.play`.
  - `lights_up` in `preshow` and `ended`: restores `light.house_lamps` and `light.accent` to 1.0 over 4 s.

## Sound

- `acoustics` `hull` (`rt60` 0.88, `damping` 0.36, `wet` 0.28) for the room's beds. Document film acoustics: reflect
  `[0.44, 0.44, 0.24, 0.48, 0.36, 0.42]`, `rt60` 0.88 s, `wet` 0.46, `late` 1.38 (box 13.0 x 9.0 x 14.0 m, Sabine mean
  absorption `alpha` 0.35).
- `sound_bed` `aerostat_hum` (`aerostat_hum`) around `[0.0, 2.2, -0.5]`, `radius` 5.5, `voices` 2, `reach` 9,
  `gain_db` -2, `film_db` -10.
- `sound_bed` `thunder` (`rumble`) every 190 s far below in the lower cloud deck at `[-40.0, -25.0, -30.0]`, `reach`
  65, `gain_db` -5, `film_db` -14.
- `sound_bed` `chime` (`chime`) forward above the gallery at `[0.0, 3.5, -5.5]`, `reach` 12, `gain_db` -5, `film_db`
  -10; plays on the `starting` ritual.
- Measured by `test_room_venus_aerostat.gd`: pre-show -51.1 dBFS RMS (peak -40.2), under a film at the reference -70.4
  dBFS RMS.

## Measured

By `test_room_venus_aerostat.gd` under Vulkan Forward Mobile (`lavapipe`, `60 checks, all passed`):

- Draws: 21 (limit 34; headset budget 40).
- Triangles: 54,872 (limit 90,000; headset budget 400,000).
- Live lights: 0.
- Particles: 0.
- Blended layers: mean 0.40, peak 3 (budget 1.00).
- Build time: 75.6 ms (1.1 pace units; budget 4.0).
- Textures: 9.3 MB; static bake atlas 572 x 496 (limit 2048).

## Not done yet

On the headset: not run.
