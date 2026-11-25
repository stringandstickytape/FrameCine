# Giant's study

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/giants_study.env.json` (Other worlds, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_giants_study.gd`. A rainy late-night Victorian study at 10:1 miniature scale where you sit ten
centimetres tall on stitched felt cushions resting on a giant woven cork-and-felt coaster atop a gleaming mahogany desk.
In front of you, a brushed-brass and walnut pocket display stands propped on a giant folded leather notebook and brass
architect's ruler over a gold-tooled green leather desk blotter. To your left rises a 5.8 m leaning stack of gilded
leather-bound volumes, a 2.3 m gleaming brass pocket watch keeping real wall time, a colossal steaming cream-and-cobalt
porcelain teacup, and a lacquered fountain pen with a gold nib. To your right arches a soaring 7.8 m articulated brass
and green-glass banker's desk lamp casting a soft downward volumetric cone over a faceted crystal inkwell, a ceramic pot
bristling with giant coloured cedar pencils, open wire-rimmed spectacles, a brass-handled magnifying glass, and a giant
brass paperclip. Beyond the chamfered mahogany desktop lies a cavernous shadowy timber-panelled study lined with
floor-to-ceiling bookshelves, a glowing fireplace hearth across the back-right wall, and a colossal mullioned
leaded-glass window looking out onto a misty moonlit autumn rainstorm.

## The parts

- **The room frame** (`domestic`, id `room`, `shell` `"kit"`): 16.0 x 8.0 x 18.5 m acoustic and collision enclosure
  (`half_width` 8.0, `front_z` -10.5, `back_z` 8.0, `height` 8.0) with all geometry left to the kit, supplying 6 seat
  slots in 2 rows of 3 (`rows_front` 0, `rows_back` 1, `seats_per_row` 3, `seat_pitch` 1.05, `row_pitch` 1.5).
- **The seats** (`seats`, `model` `"cushion"`): stitched terracotta-and-chestnut felt/corduroy miniature-scale cushions
  resting cleanly atop the giant woven cork-and-felt coaster nook at `y = 0.0`.
- **The giant's desk and study** (`kit`, id `study`; `kit/giants_study.gd`, `bake_lamps` 8, `cove_floor` 0.45):
  - `study_desk`: vast chamfered mahogany desktop (`x = -12..+12 m`, `z = -8.5..+7.5 m`) overlaid with a custom baked
    11.0 x 9.7 m green gold-tooled leather blotter (`LeatherBlotter`, exact 0..1 UVs on `Procedural.maps("leather_blotter")`)
    bordered by four giant stitched saddle-leather corner guards with brass studs; giant circular cork-and-felt coaster
    nook (`r = 2.35 m`, stitched cream rim, brass trim ring) cradling all 6 cushions; brushed-brass and walnut pocket
    display (`screen` 3.80 x 2.14 m at `[0.0, 1.55, -5.2]`) propped on a giant folded leather notebook with crimson
    ribbon bookmark and graduated brass ruler cradle; left-side 5.8 m leaning stack of five leather-bound books with
    gilded spine bands and recessed cream page blocks, 2.3 m gleaming brass pocket watch with curved bow ring, coiled
    chain and working live clock dial (`PieceClock`), colossal 2.95 m glazed cream-and-cobalt ceramic teacup and saucer
    with curved ear handle and dark tea surface, and giant lacquered fountain pen with gold nib and separate cap;
    right-side soaring 7.8 m articulated brass banker's desk lamp with translucent curved shade (`PieceCove`, live
    `desk_lamp` setting), inner opal liner and glowing filament bulb (`PieceLamps`), beaded brass pull chain and soft
    downward volumetric lamp cone (`LampCone`, `env_world_shaft.gdshader`, in group `env_see_through`), faceted crystal
    glass and hinged brass inkwell (`PieceGlass`), glazed stoneware ceramic pot holding seven giant coloured cedar
    pencils, open upright brass wire-rimmed spectacles, brass-handled magnifying glass, and giant brass paperclip.
  - `study_room`: cavernous shadowy timber-panelled study (`x = +/-16 m`, `z = -15.5..+14.5 m`, floor `y = -6.2 m`,
    coffered oak-beamed ceiling `y = +10.2 m`) with desk pedestal drawer cabinets and brass pulls, an empty buttoned
    mahogany desk chair back far aft, floor-to-ceiling bookshelves packed with giant muted leather book blocks, a
    raised carved stone-and-mahogany fireplace hearth on the back-right wall (`PieceWindows` glowing ember bed and slow
    sub-3 Hz flickering flames in `PieceLamps`, flanked by giant brass candlesticks and a circular antique brass-framed
    overmantel mirror), and a colossal two-bay mullioned leaded-glass study window on the left wall framed by pleated
    burgundy velvet curtains.
- **The sky** (`sky`): misty rainy moonlit autumn night (`latitude` 51.5, `day_of_year` 295, `hour` 23.0, `facing` 180,
  `dusk` 0.96, `clouds` 0.45 with warm low `cloud_glow`, gibbous Moon at `moon_bearing` 108, `moon_altitude` 15 framed
  through the colossal left window).
- **The weather** (`weather`): falling autumn rain (`particles` 900, `wind` `[0.0, 0.8]`) strictly outside the giant
  leaded window (`x <= -17.2 m`, zero drops inside), plus two tall rain-beaded window `panes` (`5.75 x 9.40 m` each at
  `x = -15.30 m`) merged into one draw, `mode` bound to `setting.rain`.
- **The atmosphere** (`atmosphere`): two delicate warm cream-white rising steam `fog` layers (`fog_height` 2.0,
  `fog_size` `[2.2, 2.2]`) localized tightly over the giant porcelain teacup at `[-5.60, 2.80, 0.95]`.
- **The light** (`light`): 8 stand-in and hidden bake lamps (warm golden banker's lamp pool, desk bounce, warm left key,
  cool silvery moonlight from the left window, glowing hearth ember and mantel wash, distant library wash, soft coaster
  fill) plus a hidden bake-only moonlight spotlight slanting through the left window; zero live lights.

## Cues and settings

- **Cues:**
  - `dim` during `starting`, `playing`, `intermission`, `credits`: `light.house_lamps` dims to `0.18` over 5 s,
    `light.accent` dims to `0.45` and `study.glow` dims to `0.55` over 7 s while `cove_floor` `0.45` keeps a gentle
    cozy glow on the banker's lamp shade.
  - `lights_up` in `preshow` and `ended`: house lamps, hearth accent and glow rise cleanly back to `1.0` over 4–5 s.
- **Room settings:**
  - `desk_lamp` (`Desk lamp`: Warm brass, Green banker's glow, Dim; default Warm brass).
  - `rain` (`Rain`: Steady rain, Light drizzle, Dry night; default Steady rain).
  - `watch_tick` (`Pocket watch`: Soft tick, Quiet; default Soft tick).

## Sound

- `acoustics` `cinema` (`rt60` 0.72, `damping` 0.62, `wet` 0.20) for the room's beds. Film acoustics: `reflect`
  `[0.36, 0.36, 0.44, 0.28, 0.34, 0.34]`, `rt60` 0.72 s, `wet` 0.42, `late` 1.30 (Sabine mean absorption `alpha` 0.46).
- `sound_bed` `watch` (`giant_clock`) at `[-4.0, 1.3, -2.5]`, `reach` 9.0, `gain_db` -2, `film_db` -10, `level` bound
  to `setting.watch_tick`.
- `sound_bed` `rain` (`rain_glass`) at `[-14.0, 4.5, -2.0]`, `reach` 18.0, `gain_db` -2, `film_db` -10, `level` bound
  to `weather.rain`.
- `sound_bed` `hearth` (`fire`) at `[12.0, 1.5, 6.0]`, `reach` 18.0, `gain_db` -5, `film_db` -12.
- `sound_bed` `cat` (`purr`, one-shot `every` 110 s) at `[9.0, 0.5, 5.0]`, `reach` 16.0, `gain_db` -4, `film_db` -14.

## Measured

From `test_room_giants_study.gd` (Vulkan Forward Mobile via `llvmpipe`, 64 checks, all passed) and
`test_room_acoustics.gd`:

- **Draw calls:** 29 (budget <= 34)
- **Triangles:** 24,147 (budget <= 90,000)
- **Live lights:** 0 (8 hidden bake omni lamps + 1 hidden moonlight bake spotlight)
- **Particles:** 900 (falling autumn rain outside `x <= -17.2 m`)
- **Textures:** 9.2 MB; lightmap bake: 2 static meshes, largest atlas 900 x 688 (budget <= 2048)
- **Blended layers:** mean 0.26, peak 4, share 0.14 (budget <= 1.00)
- **Build time:** 94.9 ms (0.8 pace units, budget <= 4.0)
- **Sight lines:** clear to all 4 screen corners from all 6/6 cushion seats; all physics boxes >= 0.5 m clear of origin
- **Sound:** pre-show -51.3 dBFS RMS (peak -27.3), under film -68.6 dBFS RMS (target -38.0, film -20.0)
- **Acoustics:** box 16.0 x 8.0 x 18.5 m, `rt60` 0.72 s, `wet` 0.42, `late` 1.30 — C80 26.7 dB, reverb/direct -20.0 dB,
  T20 0.60 s, Sabine mean absorption `alpha` 0.46 (in 0.05..0.75)

## Not done yet

On the headset: not run.
