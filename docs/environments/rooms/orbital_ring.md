# Orbital ring

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/orbital_ring.env.json` (Other worlds, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_orbital_ring.gd`. A sleek cantilevered mid-century-futurist glass-and-travertine observation
terrace suspended inside a colossal rotating cylindrical space habitat where illuminated agricultural valleys, winding
silver rivers, and sparkling night cities curve upside-down overhead across the sky between three monumental open
space-window strips revealing the Milky Way and 3,200 stars.

## The parts

- **The terrace layout** (`domestic`, id `room`, `shell: "kit"`): `17.0 m` wide (`half_width: 8.5`), `16.0 m` deep
  (`front_z: -9.5` to `back_z: 6.5`), `6.5 m` high, with no builder shell, lamps, ceiling light, windows, doors,
  heater, fort, or fairy lights. Provides the room acoustic box, slots, and nine seat transforms arranged in three
  rows of three (`rows_front: 1`, `rows_back: 1`, `seats_per_row: 3`, `seat_pitch: 1.35`, `row_pitch: 1.85`), with
  the viewer's own seat at the origin facing `-Z`. The floating cinema picture is `6.2 x 3.49 m` (16:9), centred at
  `[0.0, 2.85, -8.9]` (`screen_bottom: 1.105`).
- **The seats** (`seats`, model `lounge`, `from_builders: true`): nine warm ivory-slate leather mid-century lounge
  chairs on dark satin-metal splayed frames (`variation: 0.35`, `seed: 2077`), with the viewer's own chair folded away
  at `(0, 0, 0)`. All nine seats have unobstructed sight lines to the screen. Each drawn chair is wrapped by a tailored
  oiled-cedar and champagne-bronze molded rear cabinet shell in `ring_terrace` (`_seat_shells`), sealing the rear
  profile cleanly from behind.
- **The observation terrace** (`kit`, piece `ring_terrace`, `bake_lamps: 6`, `cove_floor: 0.45`;
  `app/scripts/env/systems/kit/orbital_ring.gd`):
  - **Cantilevered deck & infinity pool:** sweeping curved honed-travertine deck (`y = 0`, `half_width: 7.6 m`, curved
    forward prow to `z = -5.65 m`, aft to `z = +6.25 m`) with champagne-bronze floor expansion inlays, a dark woven
    architectural wool lounge rug under the chairs, a tapered under-deck structural hull belly, and a stepped forward
    terrace rim dropping into a dark-slate crescent infinity reflecting pool (`RingWater` on `env_world_water.gdshader`,
    1 opaque draw, zero blend cost, `ripple_scale: 0.68`). Submerged step glow is localized tightly along the inner
    step and knife-edge weir, leaving a dark liquid obsidian-sapphire mirror basin reflecting the screen and sky.
  - **Floating cinema screen frame:** recessed matte-slate mask bezel and solid rear backing (`z <= -8.92`), outer
    chamfered brushed-titanium aerospace halo with machined corner clamps and champagne-bronze lower pinstripe, and
    twin cantilevered brushed-titanium V-struts clamped to the forward infinity weir by dark-slate and bronze anchor
    collars.
  - **Canopy wing-ribs & indirect coves:** four pairs of travertine perimeter buttress plinths rooting sweeping
    parabolic brushed-titanium arches (`z = -2.55, +0.35, +3.15, +5.72`). The two forward pairs open into cantilevered
    gull-wing tips (`|x| = 4.35, y = 6.15`) leaving the entire central overhead and forward sky unobstructed; the two
    aft arches span continuously overhead supporting a curved warm-cedar observatory canopy soffit with four recessed
    downlight discs (`PieceLamps`). Longitudinal satin-titanium purlins terminate flush between the four rib stations.
    Continuous indirect cove ribbons (`PieceCove`) wash the curved prow lip, outer deck walkways, wing-rib soffits, aft
    canopy leading edge, planter kick-plinths, and aft monolith reveals.
  - **Balustrades, planters & furnishings:** single-layer frameless low-iron glass balustrades (`PieceGlass`,
    `alpha: 0.045`, `rim: 0.16`, zero double-layer overdraw) along both flanks and outer prow wings, keeping the
    central pool overlook (`|x| < 4.35`) completely glass-free in front of the screen; four vertical-slat cedar and
    travertine architectural planters holding segmented terrace bamboo groves forward and cloud-pruned dwarf cypresses
    aft with agave tufts; six opal-globe spun-titanium bollard lamps (`PieceLamps`, all six registered for lightmap
    baking); and twin circular travertine-and-titanium tulip lounge side-tables holding ceramic carafes and bronze
    tumblers (`x = ±2.45`, clear of the origin).
  - **Aft observatory promenade:** stepped honed-travertine central monolith (`z = +6.02`) flanked by acoustic
    cedar-slat wings, a floating cantilevered travertine-and-cedar credenza holding an orbital bronze gyroscope model
    and ivory bowls, a working modernist titanium-and-bronze orbital wall clock (`PieceClock`, real local time) with
    horizontal speed-wings, and twin cyan backlit orbital-ring schematic placards (`PieceWindows`: port 3-land/3-window
    cross-section and starboard domed-cylinder elevation with solar mirror vanes and orbital arc, pure geometry, zero
    text or trademarks).
- **The O'Neill cylinder world** (`kit`, piece `ring_cylinder`, `RingCylinder` on `app/shaders/env_ring_world.gdshader`,
  1 opaque unshaded draw, 0 blend cost):
  - **Spatial geometry:** radius `78.0 m`, axis at `y = 68.0 m` (`theta = 0` straight down at `y = -10 m`, `theta = 180`
    directly upside-down overhead at `y = +146 m`), length `174.0 m` (`z = -96.0` to `+78.0`), hemispherical alpine
    end-caps bulging `16.0 m`. Every cylinder vertex lies at most `173.7 m` from the eye (`< 182 m`), safely inside the
    `184 m` constellation lines, `185 m` stars, `190 m` sky dome, and `200 m` camera far plane so stars never clip over
    solid terrain.
  - **3 land strips / 3 real open space windows:** three opaque 62-degree continent strips (starboard `[29..91]`,
    upside-down zenith `[149..211]`, port `[269..331]`) separated by three genuine 58-degree geometric gaps (`[91..149]`,
    `[211..269]`, `[-29..+29]`) so the real `sky` dome, Milky Way, constellations, and stars shine directly through
    between the upside-down valleys. Framed by six beveled longitudinal titanium window girders, four slender upper
    window mullion stringers, eight full-360-degree circumferential tension hoop rings, sweeping keel support struts
    under the terrace, sculpted 3D alpine mountain-ring end-caps (`inner radius 50.5 m`), six continuous full-length
    radial spokes, and luminous central axial solar/docking hubs (`radius 17.0 m`).
  - **Procedural world shader (`env_ring_world.gdshader`):** uses shared `SkySys.noise_texture()` and lightweight
    analytical math to paint patchwork agricultural valleys, dark conifer forests, sinuous silver rivers with coastal
    bays and bridges, organic district-rotated night cities with sparkling downtown cores and waterfront cyan accents,
    painterly snow-crowned alpine end-cap peaks with mountain-pass lights, beveled titanium girders with navigation
    beacons, subtle film screen spill, and smoothly interpolated `habitat_time` moods (`mood_weights` eased over
    `0.85 s`).
- **The sky** (`sky`): `mode: "space"`, `all_sky: true`, `latitude: 24.0`, `day_of_year: 205.0`, `hour: 21.2`,
  `facing: 135.0`, `milky_detail: 1.0`, `faint_stars: 3200`, `milky_colour: "#fff5e4"`, `line_colour: "#78b4f4"`.
  Sweeps the detailed Milky Way diagonally across both upper-left and upper-right open space windows flanking the
  upside-down overhead continent.
- **The light** (`light`): `spill: 0.35`, `fill_top: [0.38, 0.36, 0.35]`, `fill_bottom: [0.16, 0.15, 0.14]`,
  `baked_fill: 0.45`, warm bollard bake lamps `[1.0, 0.84, 0.60]` (`lamp_energy: 3.4`, `lamp_range: 7.5`,
  `lamp_cone_deg: 65.0`). Zero live lights.

## Settings & cues

- **Room settings:**
  - `habitat_time` (`Habitat time`: Night city lights, Golden hour, Twilight glow; default Night city lights) — drives
    `env_ring_world.gdshader` (`time_mood` / smoothed `mood_weights`) and the infinity reflecting pool water palette
    live.
  - `terrace_glow` (`Terrace glow`: Warm gold, Orbital cyan, Off; default Warm gold) — binds `kit.cove_colour` and
    `kit.cove` across all terrace, canopy rib, planter, and aft promenade cove ribbons.
  - `sky_windows` (`Sky windows`: Milky Way, Constellations, Quiet stars; default Milky Way) — binds `sky.milky_way`,
    `sky.lines`, and `sky.stars` visible through the cylinder's three open window strips.
- **Cues:**
  - `ritual_chime` on `starting` (requires `setting.ritual`): sounds the gentle `cabin_chime` (`chime.play`).
  - `dim_for_film` on `starting` (`stop_in: ["preshow", "ended"]`): dims `light.house_lamps` to `0.14` (5 s),
    `light.accent` to `0.35` (6 s), and `kit.glow` to `0.45` (6 s), while `RingCylinder` softens smoothly via
    `film_dim` (`0.68..1.0`) so the upside-down world remains visible without competing with the film.
  - `lights_up` on `preshow` / `ended`: brings house lamps, accents, and glow back to `1.0` over `4 s`.
- **Comfort:** completely stationary terrace (zero roll, pitch, or peripheral pass-by motion); subtle city light
  twinkle (`< 0.2 Hz`) and slow water ripples respect the `Motion` setting (freezing cleanly at `0`); zero live lights;
  all physics boxes at least `0.5 m` clear of `(0, 0, 0)`.

## Sound

- `acoustics`: `cinema` preset (`rt60: 0.60`, `damping: 0.48`, `wet: 0.22`, `predelay_ms: 30.0`) for room beds.
  Document film acoustics: `reflect: [0.35, 0.35, 0.42, 0.14, 0.30, 0.38]`, `rt60: 0.58 s`, `wet: 0.34`, `late: 1.25`
  on the `17.0 x 6.5 x 16.0 m` terrace box (`C80: 29.4 dB`, reverb/direct `-21.1 dB`, `T20: 0.47 s`, Sabine
  `alpha: 0.50`, verified by `test_room_acoustics.gd`).
- `sound_bed` `wind`: airy habitat atmospheric breeze around the terrace (`[0, 2.5, -2.0]`, `radius: 6.5`,
  `reach: 10.0`, `pitch: 0.9`, `gain_db: -5.0`, `film_db: -12.0`).
- `sound_bed` `city`: distant low murmur from the overhead upside-down cities (`[0, 30.0, -10.0]`, `reach: 45.0`,
  `gain_db: -4.0`, `film_db: -12.0`).
- `sound_bed` `fountain`: gentle overflow along the forward infinity pool weir (`[0, 0.2, -7.8]`, `reach: 6.0`,
  `gain_db: -5.0`, `film_db: -12.0`).
- `sound_bed` `chime` (`cabin_chime`): opening ritual chime (`[0, 3.2, -6.5]`, `reach: 12.0`, `gain_db: -3.0`,
  `film_db: -8.0`), triggered by `ritual_chime`.
- Measured: `-54.9 dBFS` RMS in the pre-show (peak `-40.2`), `-75.5 dBFS` under a film at the reference level (target
  `-38.0`).

## Measured

- **Vulkan Forward Mobile (lavapipe, `test_room_orbital_ring.gd`, 60 checks, all passed):**
  21 draws (`<= 34`), 47,316 triangles (`<= 90,000`), 0 lights, 0 particles, 9.4 MB of textures, lightmap atlas
  `560 x 448`, `blend_layers` `{mean: 0.01, peak: 1, share: 0.01}`, build `0.7 pace units` (`85 ms`).
- **Breakdown by part:** `PieceSoft` 6 draws / 15,630 tris, `RingCylinder` 1 draw / 10,280 tris, `SkyStars` 1 draw /
  7,190 tris, `Seats` 2 draws / 6,570 tris, `PieceStatic` 4 draws / 3,746 tris, `SkyDome` 1 draw / 2,400 tris,
  `PieceLamps` 1 draw / 904 tris, `RingWater` 1 draw / 336 tris, `PieceCove` 1 draw / 204 tris, `PieceClock` 1 draw /
  32 tris, `PieceGlass` 1 draw / 20 tris, `PieceWindows` 1 draw / 4 tris.

## Not done yet

On the headset: not run.
