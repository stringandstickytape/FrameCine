# Bookshop loft

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/bookshop_loft.env.json` (Cozy retreats, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_bookshop_loft.gd`. A warm walnut-and-oak timber mezzanine loft perched overlooking a winding
two-storey antique bookshop after closing on a rainy night. Six tufted oxblood-and-cognac Chesterfield leather club
armchairs sit in two centred rows of three on a hand-loomed woven wool rug over wide honey-walnut floorboards, looking
across a turned-oak and gleaming brass mezzanine balustrade to the cinema screen recessed into a grand central mahogany
arched bookcase bay. Beyond the balustrade, an open central atrium well drops 3.4 m down into the warm-lit ground-floor
bookshop with an oak shopkeeper's reading table piled with open folios, stacked book crates, a brass floor lamp, a
woven runner rug, and a glowing cast-iron parlor stove. Towering two-storey floor-to-ceiling mahogany bookshelves lined
with nearly two thousand jewel-toned leather and cloth volumes wrap both storeys, served by three slender oak-and-brass
rolling library ladders on horizontal brass rails. Slanted attic roof rafters and collar beams rise to a warm timber
ridge pierced by four tall rain-beaded dormer skylights revealing the dark indigo rainy night sky, crescent Moon, and
neighbouring rain-wet slate chimney roofs. Flanking mahogany reading tables hold glowing emerald-glass banker's lamps,
stacked hardcovers, a glazed porcelain teacup and saucer, a brass magnifying glass, and a vintage brass terrestrial
globe; behind the seats, an aft-port staircase descends past framed bookshop prints beside a tall carved oak-case
grandfather clock keeping real wall time.

## The parts

- **The room frame** (`domestic`, id `room`, `shell` `"kit"`): 11.2 x 5.8 x 13.8 m acoustic and collision enclosure
  (`half_width` 5.6, `front_z` -8.4, `back_z` 5.4, `height` 5.8) with all geometry left to the kit, supplying 6 seat
  slots in 2 centred rows of 3 (`rows_front` 0, `rows_back` 1, `seats_per_row` 3, `seat_pitch` 1.25, `row_pitch` 1.75)
  with zero centre aisle and a dead-centre head-on seat at `(0.0, 0.0, 0.0)` facing `-Z`.
- **The seats** (`seats`, `model` `"club_chair"`): deep tufted oxblood-and-cognac Chesterfield leather armchairs
  (`tufted_leather` over `red_hardwood` feet, `variation` 0.45) resting on the woven mezzanine reading rug.
- **The bookshop loft and shelves** (`kit`, id `bookshop`; `kit/bookshop_loft.gd`, `bake_lamps` 8, `cove_floor` 0.42):
  - `bookshop_mezzanine`: two-storey timber hall (`x = +/-5.60 m`, `z = -8.40..+5.40 m`, lower floor `y = -3.40 m`,
    mezzanine deck `y = 0.0 m`, eaves `y = 3.60 m`, timber ridge `y = 5.90 m`), open central atrium well
    (`x = -3.65..+3.65 m`, `z = -7.30..-2.05 m`) supported by six turned walnut gallery columns and carved corbels,
    turned-oak and brass mezzanine balustrade kept strictly at `y = 0.86 m` (clearing every seat's sight line to the
    screen bottom by >= 0.24 m), baked static woven `nordic_rug` rugs (`MezzanineRug`, deep burgundy/ochre/cream) under
    the armchairs and across the lower atrium floor, slanted attic rafters, collar tie-beams, king-posts, and four tall
    mullioned dormer skylights (`PieceGlass`) looking onto neighbouring wet-slate roofs and brick chimney stacks;
    grand central mahogany arched bookcase bay framing the screen (`center: [0.0, 2.25, -7.6]`, `size: [4.6, 2.59]`)
    with fluted pilasters, dentil pediment cornice, semicircular arch crown, and indirect cornice uplight (`PieceCove`);
    flanking mahogany reading tables with glowing emerald-glass banker's lamps (`PieceCove` + `PieceLamps`), stacked
    hardcovers, glazed porcelain teacup and saucer, brass magnifying glass, and vintage brass terrestrial globe; six
    warm amber-glass pendant lamps; aft-port descending oak staircase with mahogany wainscoting, framed botanical and
    celestial plates, and brass wall sconce; tall carved oak-case grandfather clock against the aft wall with live
    working dial (`PieceClock`), glazed waist door (`PieceGlass`), gleaming brass pendulum bob, weights, and urn
    finials.
  - `bookshop_shelves`: towering floor-to-ceiling mahogany bookshelves with dark mahogany back panels lining both the
    lower atrium (`y = -3.40..-0.34 m`) and the upper mezzanine walls (port, starboard, front flanks, and aft wall
    flanking the grandfather clock), packed with richly varied jewel-toned leather and cloth book spines (varied
    heights, depths, leaning books, horizontal folio stacks, and gilt highlights batched into two shared soft surfaces);
    three slender oak-and-brass rolling library ladders hooked onto horizontal brass rail bars; lower bookshop atrium
    oak shopkeeper's reading table (`y = -3.40 m`) piled with open ivory folios, hardcover stacks, and glowing banker's
    lamp, slatted wooden book crates, tall brass floor lamp, and a warm cast-iron bookshop parlor stove (`PieceWindows`
    + slow flickering ember core in `PieceLamps`).
- **The sky** (`sky`): rainy dark indigo night (`latitude` 51.5, `day_of_year` 302, `hour` 22.5, `facing` 180, `dusk`
  0.98, `clouds` 0.48 with warm town `cloud_glow`, silver crescent Moon at `moon_bearing` 123.5, `moon_altitude` 29.5,
  `moon_phase` 0.24 framed through the port forward dormer skylight).
- **The weather** (`weather`): falling night rain (`particles` 800, `wind` `[0.0, 0.65]`) strictly outside the port and
  starboard dormers (`|x| >= 6.2 m`, zero drops inside), plus four vertical rain-beaded dormer `panes` (`1.84 x 1.62 m`
  each) merged into one `RainPane` draw call, `mode` bound to `setting.rain`.
- **The light** (`light`): 8 stand-in and hidden bake omni lamps (port and starboard reading tables, port and starboard
  pendant lanterns, screen pediment cornice uplight, warm lower bookshop atrium pool, aft clock and stairwell fill,
  cool skylight fill) plus 2 hidden bake-only dormer moonlight spotlights; zero live lights.

## Cues and settings

- **Cues:**
  - `dim` during `starting`, `playing`, `intermission`, `credits`: `light.house_lamps` dims to `0.18` over 5 s,
    `light.accent` dims to `0.45` and `bookshop.glow` dims to `0.50` over 7 s while `cove_floor` `0.42` holds a warm
    cozy glow on the banker's lamps and pediment arch.
  - `lights_up` in `preshow` and `ended`: house lamps, accent, and glow return smoothly to `1.0` over 4–5 s.
- **Room settings:**
  - `lamps` (`Reading lamps`: Warm amber, Emerald banker, Dim; default Warm amber).
  - `rain` (`Rain`: Steady rain, Light drizzle, Clear night; default Steady rain).
  - `clock` (`Grandfather clock`: Soft tick, Quiet, Off; default Soft tick).

## Sound

- `acoustics` `small_room` (`rt60` 0.44, `damping` 0.72, `wet` 0.16) for the room's beds. Film acoustics: `reflect`
  `[0.28, 0.28, 0.34, 0.22, 0.26, 0.26]`, `rt60` 0.44 s, `wet` 0.34, `late` 1.05 (Sabine mean absorption `alpha` 0.55).
- `sound_bed` `clock` (`grand_clock`) at `[0.0, 1.8, 4.6]`, `reach` 8.0, `gain_db` -2, `film_db` -12, `level` bound to
  `setting.clock`.
- `sound_bed` `rain` (`rain_glass`) at `[-4.8, 4.4, -1.5]`, `reach` 12.0, `gain_db` -2, `film_db` -12, `level` bound to
  `weather.rain`.
- `sound_bed` `stove` (`fire`) at `[-2.9, 0.2, -6.5]`, `reach` 10.0, `gain_db` -8, `film_db` -14.
- `sound_bed` `cat` (`purr`, one-shot `every` 110 s) at `[2.4, 0.3, 1.4]`, `reach` 8.0, `gain_db` -5, `film_db` -14.

## Measured

From `test_room_bookshop_loft.gd` (Vulkan Forward Mobile via `llvmpipe`, 71 checks, all passed) and
`test_room_acoustics.gd`:

- **Draw calls:** 27 (budget <= 34)
- **Triangles:** 50,168 (budget <= 90,000)
- **Live lights:** 0 (8 hidden bake omni lamps + 2 hidden dormer moonlight bake spotlights)
- **Particles:** 800 (falling night rain strictly outside `|x| >= 6.2 m`)
- **Textures:** 8.2 MB (budget <= 12.0 MB); lightmap bake: 2 static meshes, largest atlas 648 x 492 (budget <= 1024 x 1024)
- **Blended layers:** mean 0.03, peak 3, share 0.01 (budget < 1.00)
- **Build time:** 111.5 ms (1.5 pace units, target < 2.0)
- **Sight lines:** clear to all screen corners from all 6/6 club armchair seats; dead-centre head-on seat at
  `(0.0, 0.0, 0.0)` facing `-Z`; every row odd-count with `x = 0.0`; mezzanine balustrade clears screen bottom by
  >= 0.24 m from every seat; all kit physics boxes >= 0.5 m clear of origin
- **Sound:** pre-show -51.2 dBFS RMS (peak -28.6), under film -68.5 dBFS RMS (target -38.0, film -20.0)
- **Acoustics:** box 11.2 x 5.8 x 13.8 m, `rt60` 0.44 s, `wet` 0.34, `late` 1.05 — C80 34.0 dB, reverb/direct -21.2 dB,
  T20 0.34 s, Sabine mean absorption `alpha` 0.55 (in 0.04..0.75)

## Not done yet

On the headset: not run.
