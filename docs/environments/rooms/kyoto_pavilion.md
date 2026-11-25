# Kyoto garden pavilion

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/kyoto_pavilion.env.json` (Cozy retreats, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_kyoto_pavilion.gd`. A serene traditional hinoki-cypress *engawa* garden pavilion open on three
sides to a lantern-lit Kyoto night garden. Woven `tatami_weave` floor mats and six indigo-and-vermilion silk *zabuton*
floor cushions sit beneath a cantilevered exposed-rafter timber roof and warm backlit sliding *shoji* screens, opening
straight onto a mirror-emerald animated koi pond with eighteen living Nishikigoi, an arched vermilion *taiko-bashi*
footbridge, carved granite *yukimi-doro* stone lanterns, a port raked *karesansui* Zen gravel courtyard with a live
tipping bamboo *shishi-odoshi* water-clack basin, and four sculptural weeping cherry / Japanese maple trees that shift
seasonally beneath a moonlit Higashiyama mountain silhouette.

## The parts

- **The room frame** (`domestic`, id `room`, `shell` `kit`): 13.6 m wide (`half_width` 6.8), 12.62 m deep (`front_z`
  -8.42 to `back_z` 4.2), 4.2 m acoustic ceiling height (`vault_rise` 0.0), supplying the screen frame, seat transforms,
  and room metrics while `kit` builds the entire timber pavilion and surrounding Kyoto garden. No default room lamps,
  windows, doors, heaters, fort, or fairy lights. The picture is 5.00 m wide and 2.81 m high (16:9), bottom at 0.845 m,
  centred at `[0.0, 2.25, -8.4]`.
- **The seats** (`seats`, model `cushion`, `from_builders` true): six deep indigo-and-vermilion `velvet` silk *zabuton*
  floor cushions framed by low vermilion-lacquer borders on the woven tatami floor — two rows of three (`rows_front` 0,
  `rows_back` 1, `seats_per_row` 3, `seat_pitch` 1.15 m, `row_pitch` 1.55 m, zero centre aisle), placing the viewer on
  the dead-centre cushion at `(0, 0, 0)` facing `-Z` head-on at the screen, with an odd seat count and an `x = 0.0`
  centre seat in every row and clear sight lines to the screen from every seat.
- **The hinoki pavilion and Kyoto night garden** (`kit`, id `fittings`; `kit/kyoto_pavilion.gd`):
  - `kyoto_engawa`:
    - Raised traditional tatami floor (`y = 0.0`, `x = -2.30..+2.30 m`, `z = -1.18..+2.72 m`) inlaid with procedural
      `tatami_weave` matting (`tiling` 1.5333 m, 3 crisp tatami widths with the centre seat centred on a mat), bordered
      by dark-hinoki *kamachi* sills and strictly non-overlapping warm glossy dark-hinoki *engawa* verandah planks
      (`y = -0.022 m`, wrapping front, port, and starboard edges) over dark under-floor framing, granite foundation
      footings (*kiso-ishi*), a broad port granite *kutsunugi-ishi* step stone, and curved *tobi-ishi* garden stepping
      stones descending to the Zen courtyard.
    - Six slender square hinoki-cypress posts (`oak_veneer` grain, gilt-bronze collars and *masugumi* bracket blocks)
      supporting perimeter tie-beams, transverse cross-beams, traditional *wagoya* roof struts and ridge framing,
      exposed parallel hinoki rafters (*taruki*) with indirect perimeter `PieceCove` uplighting (`cove_floor` 0.36),
      and a gently concave cantilevered hipped roof clad in dark smoked-clay *kawara* tiles with upturned corner
      *onigawara* finials.
    - Aft wall at `z = 2.84 m`: two pairs of softly backlit translucent rice-paper (*washi*) sliding *shoji* screens
      (`PieceCove`) with fine dark-cedar *kumiko* lattice mullions and openwork cedar *ranma* transoms flanking a
      recessed central *tokonoma* display alcove (gnarled *toko-bashira* pillar, dark-lacquered *toko-ita* dais,
      warm indirect back-wall wash, minimalist *sumi-e* mountain and Zen *enso* hanging scroll with roller rod, ivory
      *jikusaki* end-caps, and silk hanging cord, plus a lathed celadon stoneware ikebana vase holding a blossoming
      plum/cherry branch).
    - Low dark-lacquered cedar *chabudai* tea table resting on the front *engawa* (`z = -1.56 m`, tabletop height
      0.30 m, over 0.65 m below the lowest sight line) holding a hinoki tray, lathed cast-iron *kyusu* teapot, two
      stoneware *yunomi* matcha cups, and a vermilion *wagashi* sweet plate.
    - Four square hinoki-and-washi *andon* floor lanterns glowing at the verandah corners (`PieceLamps`, 4 of 8 hidden
      bake omni lamps).
    - Freestanding dark-cypress *torii* / garden pavilion frame rising out of submerged mossy granite piers at the far
      edge of the koi pond around the cinema screen (`z = -8.40 m`), crowned by a sweeping upturned *kasagi* lintel,
      dark *kawara* rain-hood eaves, gilt crest plaque, dark charcoal matte backing, and subtle underside lintel cove.
  - `kyoto_garden` (`KyotoGardenHall`, registered in `c.halls`, 4 draws, 0 live lights):
    - `KyotoPondWater`: opaque animated mirror-emerald koi pond surface (`y = -0.46 m`,
      `res://shaders/env_world_water.gdshader`, `Procedural.caustic_map()`, live clock scaled by Motion, screen spill
      ripples, and subtle lantern/moonlight glints shifting with `setting.lanterns`) wrapping past the front and
      starboard *engawa*, rimmed with smooth mossy river boulders, notched emerald lily pads, and pale-pink lotus buds.
    - Sculpted curved vermilion-lacquered wooden *taiko-bashi* garden footbridge (`x = 5.65 m`, `z = -3.85..+0.55 m`,
      arch crown `+0.50 m`) arching across the starboard pond inlet on dark-cypress pilings with gleaming lathed brass
      *giboshi* finials; three carved granite *yukimi-doro* snow-viewing stone lanterns along the water's edge
      (`PieceLamps`, 3 of 8 hidden bake omni lamps).
    - Port bamboo *shishi-odoshi* water-clack basin (`[-4.25, -0.45, -1.65]`) with mossy granite *tsukubai* basin,
      bamboo supply spout (*kakehi*) with shimmering water stream, woven bamboo privacy screen (*takegaki*), and live
      pivoting `BambooRocker` that tips and snaps back whenever `spout` plays.
    - Port raked *karesansui* Zen gravel courtyard (`x = -11.65..-3.35 m`, `36 x 40` sculpted harmonic wave flutes
      blending into concentric ripples around three mossy dark-andesite *sanzon-seki* boulders), enclosed by a
      weathered earthen-plaster and *kawara*-tile *tsukiji-bei* garden wall and eight clusters of tall segmented Kyoto
      bamboo.
    - Four gnarled multi-limb cherry / Japanese maple trees framing the garden corners (strictly clear of the screen
      sight line) with airy botanical double-sided leaf-fan canopies and cascading weeping blossom curtains
      (`KyotoCanopy`, 1 opaque house-lit draw shifting live between spring sakura pink, autumn crimson-gold maple, and
      summer moonlit emerald via `setting.season`), backed by moonlit Higashiyama mountain ridges (`KyotoHills`).
- **The light** (`light`): cool moonlit indigo top fill (`fill_top` `[0.34, 0.38, 0.50]`) over warm hinoki lantern
  under-fill (`fill_bottom` `[0.24, 0.18, 0.12]`), warm washi bake light (`[1.0, 0.78, 0.46]`, `lamp_energy` 2.8,
  `lamp_range` 8.5), live screen spill (`0.95`), `baked_fill` 0.25, and `glow_colour`/`glow_mix` bound to
  `setting.lanterns`.
- **The Kyoto night sky** (`sky`): `mode` sky at latitude `35.0°` (`hour` 21.5), deep indigo night zenith (`#060b18`)
  and horizon (`#142038`), `stars` 0.88, `faint_stars` 1400, `milky_way` 0.42, soft drifting clouds (`0.24`), and a
  bright waxing gibbous Moon (`moon` 0.92, `moon_bearing` 206°, `moon_altitude` 22°) perched beside the forward *torii*
  eave tip.
- **Wildlife and seasonal petals:**
  - `koi` (`life`, `fish`, 18 instances): living Nishikigoi in Kohaku vermilion-orange, Yamabuki gold, and Platinum
    ivory gliding smoothly inside the shallow L-shaped koi pond (held cleanly at the pond water plane by
    `KyotoGardenHall._sync_koi()`, never floating out of water or entering the pavilion deck or screen sight line).
  - `fireflies` (`life`, `firefly`, 28 instances): soft chartreuse garden fireflies (`personal` 3.6 m, `keep_out` 0.65)
    emerging fully in `summer` (`activity` 1.0) and brightening during darker scenes of the film.
  - `petals` (`weather`, `snow`, 220 particles): gentle drifting blossoms confined strictly to two outside garden areas
    over the koi pond and starboard bridge, tinting live from pink sakura petals to crimson-gold autumn maple leaves and
    pausing cleanly in `summer`.

## Settings and cues

- **Settings:**

  | Setting | Choices | Default | What it moves |
  |---|---|---|---|
  | `season` (`Season`) | `sakura` (`Spring sakura`), `maple` (`Autumn maple`), `summer` (`Summer emerald`) | `sakura` | Live tree canopy and drifting petal tint (`KyotoCanopy` + `petals`), petal fall density (`0.90` / `0.55` / `0.0`), and summer garden firefly activity (`0.18` / `0.12` / `1.0`) |
  | `lanterns` (`Lanterns`) | `washi` (`Warm washi`), `moonlight` (`Moonlit silver`), `dim` (`Dim embers`) | `washi` | Corner *andon* and stone lantern `glow_colour`/`glow_mix`, backlit *shoji* and rafter `PieceCove` brightness and hue, and koi pond glint/reflection palette |
  | `bamboo_spout` (`Bamboo spout`) | `steady` (`Steady clack`), `rare` (`Soft and distant`), `quiet` (`Quiet`) | `steady` | Level of the port bamboo *shishi-odoshi* `bamboo_clack` sound bed (`1.0` / `0.42` / `0.0`, silencing clacks cleanly on `quiet`) |

- **Cues:**
  - `arrive` in `preshow`: triggers a welcoming `spout.play` *shishi-odoshi* clack and raises `light.house_lamps` to
    `1.0` over 3.0 s.
  - `ritual` when `starting` (requires `setting.ritual`): triggers a contemplative `spout.play` clack and dims
    `light.house_lamps` to `0.18` over 5.5 s while the *shoji* and rafter coves keep their `0.36` floor.
  - `dim_direct` when `starting` (requires `ritual` off, `dim` on) and `film_dim` during `playing`/`credits` (requires
    `dim` on): dims `light.house_lamps` to `0.18` over 3.5 s.
  - `end_ritual` when `ended`: triggers a departure `spout.play` clack and restores `light.house_lamps` to `1.0` over
    4.0 s.
- **Timeline:** 8 s start, 6 minutes of credits.

## Sound

- `acoustics` `small_room` (`rt60` 0.48, `damping` 0.62, `wet` 0.18, `predelay_ms` 24.0) for the airy open-eave timber
  pavilion. Document film acoustics: `reflect` `[0.16, 0.16, 0.22, 0.28, 0.08, 0.34]`, `rt60` 0.48 s, `wet` 0.18,
  `late` 0.65 (Sabine mean absorption `alpha` 0.43).
- `sound_bed` `spout` (`bamboo_clack`): periodic hollow bamboo *shishi-odoshi* clack placed at the port bamboo basin
  `[-4.25, 0.15, -1.65]` (`reach` 6.5, `every` 52.0 s, `jitter` 0.25, `gain_db` 0.0, `film_db` -10.0), controlled by
  `setting.bamboo_spout` and triggered on arrival, film start ritual, and film end.
- `sound_bed` `pond` (`fountain`): gentle garden water trickle at the port bamboo basin `[-4.25, 0.10, -1.65]`
  (`reach` 6.0, `gain_db` -1.5, `film_db` -11.0).
- `sound_bed` `crickets` (`crickets`): three quiet garden voices spaced around `[0.0, 0.5, -2.5]` (`radius` 7.5,
  `reach` 8.5, `gain_db` -4.5, `film_db` -12.0).
- `sound_bed` `breeze` (`wind`): whisper-soft night garden breeze (`place` `everywhere`, `gain_db` -6.5,
  `film_db` -12.0).
- Measured by `test_room_kyoto_pavilion.gd` and `test_room_acoustics.gd`: pre-show `-54.1 dBFS` RMS (peak `-32.8 dBFS`),
  under a film at the reference `-73.1 dBFS` RMS (`C80` 43.8 dB, reverb/direct `-31.0 dB`, `T20` 0.38 s, `alpha` 0.43).

## Measured

By `test_room_kyoto_pavilion.gd` (`62 checks, all passed`), `test_room_acoustics.gd` (`195 checks, all passed`),
`test_environments.gd` (`629 checks, all passed`), and `test_env_checks.gd` (`50 checks, all passed`):

- Draws: 25 (limit 34).
- Triangles: 42,732 (limit 90,000).
- Live lights: 0 (8 hidden bake omni lamps).
- Particles: 220 (strictly outside over the garden pond and bridge).
- Textures: 6.5 MB (limit 12.0 MB), lightmap atlas 516 x 432 (limit 1024 x 1024).
- See-through overdraw (`blend_layers`): mean 0.00, peak 1, share 0.00 (limit 1.00).
- Second-build time: 80 ms / 1.1 pace units in `test_environments.gd` (1.0 pace units in `test_room_kyoto_pavilion.gd`;
  limit 2.0).

## Not done yet

On the headset: not run.
