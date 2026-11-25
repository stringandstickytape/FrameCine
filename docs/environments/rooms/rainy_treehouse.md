# Rainy treehouse

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/rainy_treehouse.env.json` (Cozy retreats, built by **Gemini 4 Neon Extra High**), tested by
`app/tests/test_room_rainy_treehouse.gd`. A hand-built cedar-plank and pitched-corrugated-tin canopy hideaway nestled
14 metres up inside the sprawling gnarled boughs of an ancient mossy forest oak on a warm rainy twilight night. Two
rows of three oversized corduroy bean bags sit on a thick woven Nordic diamond rug with a dead-centre head-on seat at
the origin facing a cinema screen framed in hand-lashed cedar poles and rolled canvas weather flaps. Six wide
propped-open timber shutter awnings open onto lush misty forest canopy and glistening outside-only rain curtains while
strings of warm brass and paper fairy lanterns glow across the exposed cedar rafters and tin roof, fireflies drift
through the mossy branches, and an open balcony doorway leads onto a curving wooden-slat rope suspension bridge
vanishing into neighbouring oaks.

## The parts

- **The treehouse layout** (`domestic`, id `room`, `shell` `kit`): 8.8 x 4.6 x 10.6 m acoustic box (`half_width` 4.4 m,
  `front_z` -6.2 m, `back_z` 4.4 m, `height` 3.1 m, `vault_rise` 1.5 m) with plain domestic shell, windows, doors and
  ceiling lamps omitted so the hand-crafted timber treehouse owns the view. The picture is 4.20 m wide and 2.36 m high
  (16:9), its bottom 0.87 m up, centred at `[0.0, 2.05, -5.4]`.
- **The seats** (`seats`, model `bean_bag`): two rows of three oversized chestnut-terracotta `corduroy` bean bags
  (`rows_front` 0, `rows_back` 1, `seats_per_row` 3, `seat_pitch` 1.15 m, `row_pitch` 1.55 m, zero centre aisle). Six
  seat transforms, always with a dead-centre seat at `(0.0, 0.0, 0.0)` facing `-Z` head-on and an odd seat count with an
  `x = 0.0` seat in every row; clear sight lines to the screen from every seat.
- **The treehouse cabin, roof, props and rope bridge** (`kit`, piece `treehouse_deck`, `kit/rainy_treehouse.gd`):
  - Weathered honey-cedar plank interior floor (`rustic_planks`), notched around the aft-starboard hinged trapdoor hatch
    and host oak trunk, encircled by a wrap-around slatted cedar lookout deck (`|x| = 5.12 m`, `z = -6.32..+5.65 m`) with
    rustic split-cedar X-braced balustrades and diagonal under-deck timber knee struts.
  - Timber-framed cedar walls (`|x| = 4.15 m`, `z = -5.75..+4.15 m`) with six wide planked shutter windows hinged along
    the top and propped wide open at 73°–74° on twin wooden stay rods to serve as rain awnings framing the misty forest.
  - Pitched weathered corrugated-tin roof (`Procedural` `"corrugated"` over `brushed_steel`, seven overlapping panels per
    slope) with deep overhanging rain eaves (`|x| <= 5.12 m`, `z = -6.55..+5.15 m`), galvanized ridge cap and gutters,
    exposed cedar rafters, purlins, high king-post collar ties (`y = 3.88 m`), and fitted octagonal cedar floor and roof
    collars scribed tightly around the living oak trunk.
  - Hand-lashed cedar-pole cinema screen surround with hemp cross-lashings, canvas tension cords, rolled weathered
    canvas weather flaps tied clear of the screen edges, and a built-in under-screen cedar storage bench holding a folded
    wool blanket and coiled hemp climbing rope.
  - Baked static woven floor rug (`NordicRug` via `TreehouseHall`, `Procedural.maps("nordic_rug")` with exact 0..1 UVs,
    braided moss-green trim, cream fringe tassels and four plump moss, ochre and berry floor throw pillows).
  - Low cedar-stump and slatted-plank coffee table (`y_top = 0.36 m`, strictly below all sight lines) with a woven moss
    tea runner, forest-pine enamel teapot with brass finial, two enamel camp mugs filled with tea, a glowing brass oil
    hurricane lantern (`PieceGlass` + `PieceLamps`) and a stack of three hardcover field guides.
  - Port cedar windowsill shelf holding three glowing jam-jar candles, a gleaming telescoping brass spyglass on a swivel
    cradle aimed into the rainy canopy, a painted spruce-teal tin biscuit box with brass latch, and a potted fern.
  - Aft Z-braced cedar balcony door swung open onto the rear deck, a three-tier naturalist's bookshelf stocked with
    journals and specimen jars, a framed brass-inlaid nocturnal star chart and round brass barometer on the aft wall, a
    starboard-hinged open cedar trapdoor hatch revealing a 14-rung wooden rope ladder descending 5.2 m into the branches,
    and a curving 34-slat wooden rope suspension bridge (`z = +5.65..+23.6 m`) flanked by hemp cable handrails and
    post-mounted brass lanterns leading to a distant oak landing platform.
  - Four interior rafter festoon garlands and three exterior eave garlands of glowing pleated paper and brass fairy
    lanterns (`PieceCove`, `cove_floor` 0.38, live-bound to `setting.lanterns`, backed by two live-tinted `c.footlights`),
    five hanging wrought-iron and brass cabin storm lanterns (`PieceLamps`, backed by six hidden `c.lamps` bake omnis
    including the coffee-table oil lantern), plus one hidden cool-silver moonlight `SpotLight3D` for lightmap baking.
- **The ancient host oak and surrounding misty woodland** (`kit`, piece `treehouse_canopy`, `kit/rainy_treehouse.gd`):
  - Monumental fluted gnarled mossy oak trunk rising through the aft-starboard corner (`x = 3.95, z = 2.35`, from
    `-15.0 m` to `+14.5 m`) with interior root buttresses, upper corner boughs passing seamlessly into the roof rafters,
    massive twisting under-deck cradle boughs, flanking screen-side limbs and soaring overhead crown limbs clothed in
    billowing multi-lobe organic mossy-green oak canopy clusters kept strictly outside the dry cabin and screen corridor.
  - 21 tall neighbouring ancient oak and cedar trunks (`11..38 m` out, encircling 360° including the destination oak for
    the rope bridge) with tiered twilight-lit foliage crowns above rolling dark-emerald forest canopy mounds and a
    shadowed woodland floor at `y = -14.5 m`.
- **The sky, rain, mist and fireflies** (`sky`, `weather`, `atmosphere`, `life`):
  - Warm rainy Pacific-Northwest twilight night (`latitude` 47.5°, `hour` 21.2..23.2) whose clouds, stars, Milky Way and
    crescent Moon respond live to `setting.rain`.
  - Three outside-only rain curtains (`2,400` GPU particles, zero inward wind, positioned `>= 0.53 m` outside the dry
    corrugated-tin eaves so zero drops ever clip inside the cabin) and two soft low pine-mist layers held below the deck
    (`fog_center` `[0.0, -4.8, -2.0]`, `fog_height` 3.8 m).
  - 36 golden-chartreuse `firefly` insects (`#d4f552`, `keep_out` 0.75 m, `personal` 2.5 m, strictly clear of the sight
    line) whose active count follows `setting.fireflies` and whose glow brightens smoothly when `weather.rain` eases.

## Cues, tracks and settings

- **Tracks** (by `film.progress`): `sky.hour` advances smoothly from `21.2` to `23.2` (`2 s` smooth). Timeline: 7 s
  start, 6 minutes of credits.
- **Cues:**
  - `lanterns_down` when `starting` or `playing`: dims `light.house_lamps` to `0.18` over 5 s while the fairy lantern
    garlands keep their `0.38` `cove_floor`.
  - `lanterns_up` in `preshow` and `ended`: restores `light.house_lamps` to `1.0` over 4 s.
- **Room settings:**
  - `rain` (`Canopy rain`: Steady rain, Light drizzle, Clear after rain; default Steady rain — drives outside-only
    rainfall, roof and canopy rain audio levels, forest mist, twilight cloud cover, star visibility and firefly glow).
  - `lanterns` (`Fairy lanterns`: Warm amber, Forest gold, Dim embers; default Warm amber — shifts the fairy lantern
    garlands and live rafters footlights between campfire honey-amber, luminous woodland gold and quiet embers).
  - `fireflies` (`Fireflies`: Many, Few, Off; default Many — controls how many fireflies dance outside the windows and
    oak boughs).

## Sound

- `acoustics` `small_room` (`rt60` 0.42 s, `damping` 0.68, `wet` 0.16) for the room's ambient sound beds. Document film
  acoustics on the 8.8 x 4.6 x 10.6 m box: `reflect` `[0.28, 0.28, 0.34, 0.32, 0.26, 0.26]`, `rt60` 0.42 s, `wet` 0.30,
  `late` 0.88 (Sabine mean absorption `alpha` 0.451).
- `sound_bed` `tin_roof` (`rain_tin`): placed overhead on the corrugated tin roof (`[0.0, 3.8, -0.5]`, `reach` 6.5 m,
  `gain_db` -4, `film_db` -11, `level` bound to `weather.rain`).
- `sound_bed` `canopy_rain` (`rain_leaves`): placed around the oak canopy at radius 6.5 m (`reach` 6.5 m, 4 voices,
  `gain_db` -6, `film_db` -11, `level` bound to `weather.rain`).
- `sound_bed` `breeze` (`wind`): placed around the treetops at radius 8.0 m (`reach` 8.0 m, 2 voices, `gain_db` -6,
  `film_db` -12).
- `sound_bed` `owl` (`tawny_owl`): distant forest owl call (`[-9.0, 3.2, -10.5]`, `reach` 16.0 m, `every` 130 s,
  `gain_db` -4, `film_db` -15).
- Measured by `test_room_rainy_treehouse.gd`: pre-show `-51.3 dBFS` RMS (peak `-38.4`), under a reference film
  `-69.5 dBFS` RMS.

## Measured

By `test_room_rainy_treehouse.gd` under Vulkan Forward Mobile (`lavapipe`, `67 checks, all passed`):

- Draws: 23 (limit 34).
- Triangles: 56,816 (limit 90,000).
- Live lights: 0 (6 hidden bake omnis and 1 hidden moonlight spot).
- Particles: 2,400 (outside-only rain curtains `>= 0.53 m` past dry eaves).
- Textures: 6.4 MB; lightmap atlas 712 x 528 (`PieceStatic` and `NordicRug`).
- Blended layers: mean 0.00, peak 2, share 0.00 (limit 1.00).
- Build time: 127.0 ms (1.4 pace units; limit 2.0).
- Sight lines: clear from all 6 seats; dead-centre head-on seat at `(0.0, 0.0, 0.0)` facing `-Z` and odd seat count per
  row verified.

## Not done yet

On the headset: not run.
