# The Salon, 1870

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/salon_1870.env.json` (Journeys — Water, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_salon_1870.gd`. A sumptuous 1870 Victorian submarine velvet salon gliding slowly across the ocean
floor beneath sunlit turquoise waters. Inside a gently inward-leaning riveted wrought-iron pressure hull lined with deep
crimson velvet, mahogany panelling, brass-grilled bookcases and a 21-pipe aft salon organ, two monumental bolted-brass
circular observation viewports house animated 10-blade mechanical brass iris shutters. In the pre-show the brass blades
close down to a dramatic glowing turquoise oculus; as the film begins, the engine-room brass telegraph bell double-rings
and the blades spiral wide open over five seconds to unveil swaying giant kelp forests, coral outcrops, silver fish
schools, bioluminescent jellies, a sunken timber galleon wreck at departure, and towering volcanic hydrothermal vents at
arrival. The journey is as long as the film (`docs/environments/passing.md`).

## The parts

- **The salon hull** (`cabin`, id `salon`; `docs/environments/cabin.md`): 4.8 m wide at the floor, walls 2.75 m high
  leaning gently inwards (`lean` 3.0 degrees, narrowing to 4.51 m at the eaves), under an arched dark-iron hull ceiling
  rising 0.52 m more (3.27 m at the crown). From the front bulkhead at z -4.2 to the rear at z 3.6: 7.8 m long, centre
  line at x -0.82 putting the viewer's own seat at the origin. Two monumental circular observation viewports centred at
  z -0.50 on both port and starboard walls (1.64 m cutout, `window_round` 0.82, sill 0.72 m, masked cleanly to a
  32-segment 1.56 m clear circular aperture by the bolted brass pressure bezels), deep mahogany `wood_panelling` dado to
  0.72 m, crimson `velvet` upper walls, `dark_metal` riveted hull ceiling, and no plain rear door (`rear_door` none) so
  the aft pipe organ owns the rear bulkhead. The picture is 3.20 m wide and 1.80 m high (16:9), its bottom 1.05 m up,
  centred at [-0.82, 1.95, -4.17].
- **The seats** (`seats`, model `club_chair`, `from_builders` true): three rows of two deep crimson button-tufted
  Chesterfield club chairs (`tufted_leather` on `walnut_veneer` feet, one row ahead of the viewer's, one behind),
  flanking a 0.72 m centre aisle with 1.1 m of clear promenade along both observation walls. Rows 1.50 m apart, seats
  0.92 m apart; viewer in the right chair (`own_side` right, `own_index` 0). 6 seat transforms, one at the origin, with
  clear sight lines from every seat.
- **The 1870 submarine salon fittings** (`kit`, id `fittings`; `kit/salon_1870.gd`):
  - `carpet` (`art_deco_runner`): deep crimson and tarnished-gold woven diamond-medallion Victorian salon carpet.
  - `salon_1870_interior`:
    - Five heavy riveted wrought-iron and burnished-brass arched pressure-hull ribs (z -4.08, -1.86, 0.86, 2.32, 3.48)
      with floor knee-gussets, longitudinal ceiling stringers, central crown spine beam and paired domed brass rivets.
    - Two monumental 32-segment bolted cast-brass & iron circular observation viewport bezels studded with 20 domed
      hex bolts each, spoked brass iris actuator handwheels, and sculpted mahogany viewing sills.
    - Stepped mahogany-and-brass screen dais, fluted mahogany proscenium pilasters with vertical brass flutes, deep
      crimson-velvet tied-back side drapes and scalloped header pelmet, Victorian brass astrolabe compass-rose tympanum
      crest, and warm indirect cove lighting (`PieceCove`, `cove_floor` 0.35) along the proscenium and vaulted eaves.
    - Two tall forward mahogany & diamond-brass-grilled library bookcases packed with colourful leather-bound atlases
      (plus an antique ocean-teal brass-meridian terrestrial globe in the starboard open niche), and two aft mahogany
      naturalist's specimen credenzas with map drawers, a brass armillary sphere, spiral chambered shell sculpture, and
      mounted brass marine spyglass.
    - Six gooseneck marine brass wall sconces with protective wire cages and two overhead brass-caged ceiling dome
      lanterns (`PieceLamps`, `bake_lamps` 4).
    - Aft centerpiece: 21-pipe Victorian mahogany-and-brass salon pipe organ with stepped twin ivory/ebony manuals,
      draw-stop knobs, illuminated parchment music desk, pedalboard and crimson-velvet bench; working bolted-brass
      marine chronometer (`PieceClock`) crowning the organ arch; starboard brass navigation binnacle with red/green
      quadrantal spheres, illuminated compass hood and engine-room order telegraph lever; port copper-and-brass ballast
      manifold with spoked crimson handwheels; and six illuminated circular brass pressure/depth gauges.
  - `salon_1870_iris`: twenty curved, bevelled, helically-shingled riveted brass iris blades (10 port, 10 starboard) in
    a single `MultiMeshInstance3D` (`SalonIrisShutters`, 1 draw, 0 lights) driven live via `c.halls`. Smoothly spirals
    over 5 seconds between a dramatic glowing turquoise pre-show oculus (`35.5°` blade angle) and a wide-open 1.56 m
    circular ocean vista (`0.0°`) when playback begins (snapping cleanly when `Motion < 0.25`).
- **The light** (`light`): warm amber `[1.0, 0.78, 0.44]`, spill 0.55, baked fill 0.16, underwater `caustics` 0.65
  (`caustic_scale` 1.3, `caustic_colour` `[0.38, 0.86, 0.94]`, `caustic_speed` 0.65) shimmering softly across the salon.
- **The pelagic dome** (`sky`): `mode` sky, `dusk` 1.0, `stars` 0.0, `milky_way` 0.0, sunlit turquoise ocean surface
  zenith (`#0c4258`) fading into deep pelagic blue-teal (`#031a28`) and abyssal ground (`#010c14`).
- **The underwater voyage** (`passing`, id `voyage`): forward at 2.4 m/s, `light` 1.65, viewport `glow` 1.1 in `#ffd898`
  reaching 18 m out and 8 m fore/aft, underwater `mist` 0.46 in `#062a3d`, screen spill 0.35.
- **Marine life** (`life`, all regions strictly outside the hull `x >= 3.6` or `x <= -5.0`): starboard and port schooling
  silver `fish` (34 + 30), bioluminescent `jelly` blooms (10 + 10) tinting subtly toward `film.colour`, an occasional
  gliding `ray` (manta) sweeping past the starboard viewport, and a rare `whale` gliding past the port viewport during
  quiet film scenes (`film.quiet`).

### The ocean floor's cross-section

Metres from the way's line; heights are relative to the salon floor (eyes at 1.2 m, roughly 6.0 m above the seabed at
-4.8 m).

| Side | From | To | What |
|---|---|---|---|
| both | 0.0 | 175.0 | `seabed` sandy ocean floor sloping from -4.8 m to -3.2 m (`#183840`) with animated turquoise caustics |
| both | 12.5 | 28.0 | near giant `kelp` forest, 68 on a 220 m loop, feet at -4.8 m (size 1.15, thinning toward the volcanic rift) |
| both | 28.0 | 65.0 | distant towering `kelp`, 56 on a 260 m loop, seeming 1.8 times further, feet at -4.5 m (size 1.45) |
| both | 14.5 | 42.0 | craggy `sea_rock` basalt & coral reef outcrops with cyan polyps, 42 on a 240 m loop, feet at -4.6 m (size 1.15) |
| both | 78.0 | 78.0 | far abyssal seafloor `ridge` silhouette on a 300 m loop, seeming 4 times further, feet at -4.0 m (size 1.4) |

### Along the route

| Place | What | Side |
|---|---|---|
| 0.0, 1.5 m ahead | departure `sunken_wreck` (18th-century timber hull & glowing turquoise stern cabin), 18.0 m off, foot at -4.8 m | right |
| 0.45 | mid-voyage ghostly `sunken_wreck`, 21.0 m off, foot at -4.8 m | left |
| 0.72 | deep volcanic `hydro_vent` chimney herald, 19.0 m off, foot at -4.8 m | right |
| 1.0, 10 m before | arrival flanking `hydro_vent` chimney cluster, 24.0 m off, foot at -4.8 m | left |
| 1.0, 0.5 m ahead | arrival monumental `hydro_vent` volcanic chimney with glowing fissures, 17.5 m off, foot at -4.8 m | right |

## The voyage's cues and settings

- **Tracks** (by `film.progress`): `voyage.mist` shifting smoothly from 0.46 to 0.58 and 0.52 (0.8 s); `light.caustics`
  deepening gently from 0.65 to 0.35 and 0.45 as the boat cruises toward the deeper volcanic vent rift (1.5 s). Timeline:
  8 s start, 6 minutes of credits.
- **Cues:**
  - `dim` when `starting`: house lamps to 0.15, viewport glow to 0.50 over 5 s (proscenium and hull eaves keep a 0.35
    cove floor).
  - `departure_bell` when `starting` (requires the pre-show ritual setting): rings the brass engine-room `telegraph.play`.
  - `lights_up` in the pre-show and at the end: house lamps to 1.0 and viewport glow released over 4 s.
  - `arrival_bell` once `journey.progress` passes 0.92 for 2 s (7200 s cooldown): rings `telegraph.play` on arrival.
  - `whale_pass` during quiet playing scenes (`film.quiet` above 0.88 for 6 s, 45% chance, 1200 s cooldown): sends the
    port-side `whale.pass`.
- **Room settings:**
  - `shutters` (`Viewport iris`: Open for the film, Always open, Half open; default Open for the film — controls both
    10-blade mechanical brass iris shutters).
  - `organ` (`Salon organ`: on/off; default on — toggles the aft Victorian flute pipe organ in pre-show, interval and
    after the end).
  - `cove` (`Cove glow`: Warm amber, Sea turquoise, Off; default Warm amber — tints the indirect proscenium and hull
    eave cove lighting).

## Comfort

Measured by `test_room_salon_1870.gd` at the fastest the journey goes: 2.4 m/s x (1 + `CATCH_UP`) = 2.76 m/s, slowed by
`seems`. Limits: 3 m and 20 degrees a second (`docs/environments/checks.md`).

| What | Nearest | Rate |
|---|---|---|
| band 0 `kelp` both | 9.91 m | 16.0 deg/s |
| band 1 `kelp` both | 24.74 m | 3.6 deg/s |
| band 2 `sea_rock` both | 10.19 m | 15.5 deg/s |
| band 3 `ridge` both | 78.00 m | 0.5 deg/s |
| landmark 0 `sunken_wreck` right (departure) | 12.23 m | 12.9 deg/s |
| landmark 1 `sunken_wreck` left (mid-voyage) | 14.95 m | 10.6 deg/s |
| landmark 2 `hydro_vent` right (rift approach) | 14.95 m | 10.6 deg/s |
| landmark 3 `hydro_vent` left (arrival flank) | 20.18 m | 7.8 deg/s |
| landmark 4 `hydro_vent` right (arrival) | 13.00 m | 12.2 deg/s |

## Sound

- `acoustics` `hull` (`rt60` 0.85, `damping` 0.42, `wet` 0.24) for the room's beds and pipe organ. Document film
  acoustics: reflect [0.36, 0.36, 0.18, 0.44, 0.34, 0.34], rt60 0.62 s, wet 0.42, late 1.24 (Sabine mean absorption 0.20).
- `sound_bed` `hull_hum` (`deep_hum`) aft below the salon at [-0.82, -1.8, 4.2], `reach` 8, `gain_db` -2, `film_db` -10;
  `level` follows `journey.speed` from 0.25 to 1.0, smoothed 2 s.
- `sound_bed` `water` (`water_lap`) around the hull at [-0.82, 1.4, -0.5], `radius` 4.5, `voices` 2, `pitch` 0.62,
  `gain_db` -5, `film_db` -10.
- `sound_bed` `vent_bubbles` (`bubbles`) outside the starboard viewport at [5.5, 0.8, -0.5], `reach` 7, `gain_db` -5,
  `film_db` -10.
- `sound_bed` `creak` (`hull_creak`) every 140 s on the port pressure hull at [-3.4, 1.8, 1.2], `reach` 7, `gain_db` -4,
  `film_db` -10.
- `sound_bed` `telegraph` (`telegraph_bell`) at the starboard aft telegraph [0.76, 1.45, 3.1], `reach` 8, `gain_db` -4,
  `film_db` -10; double-rings on departure and arrival.
- `music` `organ` (`organ`, `stop` flute, `mode` minor, `tempo` 54, `tremulant` 0.3, `seed` 1870) at the aft pipe organ
  [-0.82, 1.6, 3.2], `reach` 8, `gain_db` -3, `film_db` -14, `plays_in` preshow/intermission/ended, `on` bound to
  `setting.organ`.
- Measured by `test_room_salon_1870.gd`: pre-show -47.3 dBFS RMS (peak -33.6), under a film at the reference -74.6 dBFS
  RMS (`test_room_acoustics.gd`: C80 31.3 dB, reverb/direct -19.6 dB, T20 0.49 s, alpha 0.20).

## Measured

By `test_room_salon_1870.gd` under Vulkan Forward Mobile (`lavapipe`, `60 checks, all passed`):

- Draws: 28 (30 with the baked lightmap atlas; limit 38).
- Triangles: 54,178 (54,453 with atlas; limit 120,000).
- Live lights: 0.
- Particles: 0.
- Textures: 8.3 MB, lightmap atlas 560 x 448.

## Not done yet

On the headset: not run.
