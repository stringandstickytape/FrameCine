# Room assets credits

Every asset a room in this folder bundles, besides the library materials (`app/materials/CREDITS.md`) and the object
library's own. Each is CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/); nothing else is bundled
(`docs/environments.md`, "The checks"). A room's document lists the same in its `credits`.

The rooms' sounds are synthesised by `app/scripts/env/env_synth.gd`: ours, no samples.

| Asset | Title | Source | Author | Licence | Checked |
|---|---|---|---|---|---|

## Data

- `app/environments/sky/bright_stars.json` (the sky system's bright stars and constellation lines): the positions,
  magnitudes and colour indices of 395 bright stars are facts about the sky, in the public domain, as given in
  the Yale Bright Star Catalogue (5th revised edition, public domain). They were typed in by hand
  and rounded, not downloaded. The constellation lines are the usual stick figures, drawn as pairs of star names. No
  asset of anyone else's: no image, no texture, no file copied. The faint stars are generated in code
  (`app/scripts/env/systems/sky.gd`, `faint_field()`); the sky's noise, Earth's surface and the vista's shapes are
  made in code too.

## Atmospheric 1928

`atmospheric_1928.env.json` bundles nothing of its own: the hall, the kit's pieces, the sky (the bright stars above)
and the cypresses are made in code; its surfaces are library materials (`app/materials/CREDITS.md`).

## Palace of Culture 1974

`palace_of_culture_1974.env.json` bundles nothing of its own: the hall, the sky, the birches and the snow are made in
code; its surfaces, the mosaic among them, are library materials (`app/materials/CREDITS.md`).

## Flagship

`flagship.env.json` bundles nothing of its own: the hall is made in code; its surfaces are library materials
(`app/materials/CREDITS.md`).

## Screen 3 - 1983 (`screen_3_1983.env.json`)

No bundled asset. The hall, the seats, the partition, the swirling carpet and the water stain are the systems' own
shapes and procedural patterns on library materials (`woven_upholstery`, `black_leather`, `felt`, `oak_veneer`,
`acoustic_foam`, `rough_plaster`, the auditorium's defaults); the worn print's dust, scratches and weave are the
presentation system's shader.

## Drive-in - 1958 (`drive_in_1958.env.json`)

No bundled asset. The lot, the car, the screen tower, the snack bar and its neon letters are the systems' own shapes
on library materials (`smooth_concrete` and the builders' defaults); the sky's stars are the sky system's catalogue
(above), the mesas and the moths are made in code.

## Screening room 1962 (`screening_room_1962`)

No bundled assets. The walnut room, its painting, the club chairs, the pool and the night sky are made in code by the
systems (`domestic`, `seats`, `sky`, `vista`) on library materials; the painting's abstract picture is generated
(`procedural.gd`).

## Athens rooftop summer cinema (`rooftop_athens`)

No bundled assets. The terrace, the director's chairs, the bougainvillea, the acropolis on its hill, the sky, the
planes' lights and the cat are made in code by the systems (`terrace`, `seats`, `kit`, `vista`, `sky`, `life`) on
library materials.

## Pillow Fort 1993 (`pillow_fort_1993`)

No bundled assets. The bedroom, the fort, the fairy lights, the telly, the cushions and the rain are made in code by
the systems (`domestic`, `seats`, `weather`, `presentation`) on library materials.

## Nave (`nave.env.json`)

No bundled asset. The nave, its pews, candle stands and rose window are built in code (`nave.gd`, `seats.gd`,
`procedural.gd`) on library materials (`rough_plaster`, `white_marble`, `checker_marble_tiles`, `velvet`, `brass`, the
pews' `oak_veneer` and `walnut_veneer`, all CC0).

## Reclaimed (`reclaimed.env.json`)

No bundled asset. The hall, the ivy and ferns, the sky, the rain, the puddle, the mist, the birds, fireflies and the
deer are built in code (`auditorium.gd`, `kit.gd`, `sky.gd`, `weather.gd`, `atmosphere.gd`, `life.gd`) on library
materials (`painted_brick`, `rough_plaster`, `rustic_planks`, `velvet`, and the auditorium's defaults, all CC0). The
stars are the sky's public-domain data above.

## Ice cinema (`ice_cinema.env.json`)

No bundled asset. The ice room, the hides, the aurora, the stars and the breath are built in code (`domestic.gd`,
`seats.gd`, `sky.gd`, `atmosphere.gd`) on library materials (the ice style's `white_marble`, `rough_plaster`,
`smooth_plaster`, `felt`, the hide's `plush_carpet`, all CC0), with the ice-block pattern drawn in `procedural.gd`.

## Bathysphere

- `app/environments/bathysphere.env.json`: no asset of its own. The hall, the water, the fish, the glowing creatures
  and the whale are made in code by the systems; its surfaces are library materials (oak planks, dark metal, brass,
  velvet). The whale's song is synthesised.

## Crater

- `app/environments/crater.env.json`: no asset of its own. The tiers, the rocks, the dome, the crater's rim, Earth
  and the stars are made in code by the systems (the stars from the catalogue under "Data"); its surfaces are library
  materials (rough plaster, smooth concrete, dark metal, brushed steel). It makes no sound.

## Narrowboat (`narrowboat.env.json`)

No bundled asset. The saloon, its stove, rug and sideboard, the canal and everything that goes by it (reeds, willows,
trees, the hedge, the fence, cottages, bridges, boats, the tower, the wharf), the sky and its stars are made in code
by the systems (`cabin.gd`, `kit.gd`, `passing.gd`, `sky.gd`; the stars from the catalogue under "Data") on library
materials (`painted_wall`, `oak_veneer`, `oak_planks`, `dark_metal`, `oxblood_leather`, `walnut_veneer`, the kit's
`woven_carpet` and `oak_veneer`, all CC0). Its sounds (the engine, the water, the owl, the bell) are synthesised.

## Showboat 1927 (`showboat_1927.env.json`)

No bundled asset. The hall, its seats, stage and proscenium, the river and everything that goes by it (willows,
trees, poplars, the fence, cottages, lights, ridges, buoys, steamers, the tower and wharves), the sky and its stars
are made in code by the systems (`cabin.gd`, `kit.gd`, `passing.gd`, `sky.gd`; the stars from the catalogue under
"Data") on library materials (`painted_wall`, `wood_panelling`, `oak_planks`, `velvet`, `felt`, `dark_metal`,
`brass`, the kit's `oak_veneer`, all CC0). Its sounds (the paddle wheel, water, crickets and train) are synthesised.

## Liner 1936 (`liner_1936.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The Art Deco lounge, its seats, proscenium, torchières, pelmets, bulkhead clock, swaying velvet drapes,
promenade railings, open sea, channel buoys, harbour lights, piers, breakwater lighthouses, passing ocean liners, sky and
stars are made in code by the systems (`cabin.gd`, `kit.gd`, `motion.gd`, `passing.gd`, `sky.gd`; the stars from the
catalogue under "Data") on library materials (`smooth_plaster`, `walnut_veneer`, `woven_carpet`, `brass`, `brushed_steel`,
`oak_planks`, `velvet`, all CC0). Its sounds (the turbines, ocean wash, hull creak and ship's horn) are synthesised.

## Night ferry 1994 (`night_ferry_1994.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The 1994 cross-Channel ferry video lounge, its Pullman recliners, moulded armrests, woven linen
antimacassars, flip-up seatback tray tables, ceiling-bracketed 4:3 CRT television and locked VCR shelf cage, fluorescent
ceiling grid, night-crossing cove strips, laminate window-bay tables with cups and timetables, red fire-hose cabinet,
geometric EXIT sign, ship's bulkhead clock, exterior deck rails with orange lifebuoys, 1994 moquette carpet pattern,
salt-streaked rain storm panes, open sea, channel buoys, coastal lights, Ro-Ro ferry ports, breakwater lighthouses with
rotating volumetric beams, passing container freighters, sky and stars are made in code by the systems (`cabin.gd`,
`seats.gd`, `kit.gd`, `kit/ferry_1994.gd`, `passing.gd`, `weather.gd`, `presentation.gd`, `sky.gd`; the stars from the
catalogue under "Data") on library materials (`painted_wall`, `woven_carpet`, `woven_upholstery`, `linen`, `dark_metal`,
`brushed_steel`, `brass`, `smooth_concrete`, all CC0). Its sounds (the twin marine diesels, heavy hull wash, rain on
storm glass, hull creaks, VCR mechanism, CRT flyback whine, boarding PA chime and ship's horn) are synthesised.

## Cinema coach 1935 (`cinema_coach_1935.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The 1935 express cinema carriage, its mahogany panelling, plush claret seats, curved brass-hooded Art
Deco screen cove with sunburst crest, slotted brass speaker apron, pleated tabs, diamond-netting brass luggage racks,
holland blinds with crimson tassels, brass coat hooks, emergency cord, aft frosted vestibule grille, route plaques,
working bulkhead clock, 8 swaying opal tulip carriage lamps, Art Deco runner carpet, autumn countryside, telegraph poles,
semaphore signals, water towers, wayside stations, railway tunnel blackout, sky and stars are made in code by the systems
(`cabin.gd`, `kit.gd`, `kit/cinema_coach_1935.gd`, `kit/procedural.gd`, `motion.gd`, `passing.gd`, `presentation.gd`,
`sky.gd`; the stars from the catalogue under "Data") on library materials (`wood_panelling`, `walnut_veneer`,
`smooth_plaster`, `woven_carpet`, `velvet`, `brass`, `dark_metal`, `linen`, all CC0). Its sounds (rail joints, steam
train whistle, projector and wind) are synthesised.

## Night sleeper 1929 (`night_sleeper_1929.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The 1929 Art Deco sleeping compartment, its inlaid walnut and mahogany marquetry panels, sliding
frosted-glass corridor door, claret velvet lower berth with pillow and wool blanket, stowed upper berth with brass straps
and ladder, drawn-back velvet curtains, brass luggage rack and leather valise, working brass railway clock, stepped
ceiling medallion with sapphire night lamp, folding window-side table with twin-reel 16 mm home projector, teacup and
timetable, brass-capped roller linen screen, falling snow, snowbound alpine pines, silver birches, wayside stations,
semaphore signals, sky and stars are made in code by the systems (`cabin.gd`, `kit.gd`, `kit/night_sleeper_1929.gd`,
`kit/procedural.gd`, `atmosphere.gd`, `weather.gd`, `passing.gd`, `presentation.gd`, `sky.gd`; the stars from the
catalogue under "Data") on library materials (`walnut_veneer`, `wood_panelling`, `smooth_plaster`, `woven_carpet`,
`velvet`, `brass`, `dark_metal`, `linen`, `white_marble`, all CC0). Its sounds (rail joints, tabletop projector, wind and
train whistle) are synthesised.

## Dome car 1955 (`dome_car_1955.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The 1955 stainless-steel observation dome car, its curved glazed roof and brushed stainless purlins,
sculpted coral observation recliners with linen antimacassars and chrome cupholder arms, atomic saucer table lamps,
recessed turquoise dome valances and aisle floor strips, aft boomerang emblems and sunburst clock, mid-century weave
carpet, Southwest desert red-rock mesas, saguaro cacti, desert water towers, semaphore signals, wayside stations, sky,
Milky Way and shooting stars are made in code by the systems (`cabin.gd`, `seats.gd`, `kit.gd`, `kit/dome_car_1955.gd`,
`kit/procedural.gd`, `passing.gd`, `sky.gd`; the stars from the catalogue under "Data") on library materials
(`brushed_steel`, `painted_wall`, `woven_carpet`, `woven_upholstery`, `linen`, `dark_metal`, `brass`, all CC0). Its
sounds (rail joints, desert wind, crickets and diesel chime horn) are synthesised.

## Airship 1931 (`airship_1931.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The 1931 rigid airship promenade lounge, its outward-leaning observation windows, exposed duralumin
triangular lattice ring-girders and deckhead trusses, tubular guardrails, brass sill binoculars, Art Deco cream and
aluminium screen proscenium with frosted torchières, aft navigation chart table, great-circle route map, credenza,
altitude plaque and modernist clock, featherweight brushed-aluminium baby grand piano with 61 animated keys, Deco carpet,
moonlit cloud sea, cloud banks, sleeping coastal lights, illuminated mooring masts, sky and stars are made in code by the
systems (`cabin.gd`, `kit.gd`, `kit/airship_1931.gd`, `kit/procedural.gd`, `passing.gd`, `music.gd`, `sky.gd`; the stars
from the catalogue under "Data") on library materials (`smooth_plaster`, `oak_veneer`, `woven_carpet`, `woven_upholstery`,
`brushed_steel`, `dark_metal`, `brass`, `white_marble`, all CC0). Its sounds (airship engines, wind, chime and
self-playing piano) are synthesised.

## Jet 1964 (`jet_1964.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The 1964 first-class transpolar jet cabin, its arched narrow-body fuselage with oval windows, ceiling
16 mm twin-reel projector and beam haze, recessed fluorescent valances, pull-down bulkhead screen with cassette and pull
ring, backlit geometric seatbelt/no-smoking placard, burnt-orange recliners with sandstone shells, ivory antimacassars,
flip-up tray tables and dual-hole air-tube armrests, aft champagne-gold galley curtains, polar route plaque and sunburst
clock, mid-century weave carpet, moonlit cloud sea, cloud banks, 1960s jetport terminals, Aurora Borealis, sky and stars
are made in code by the systems (`cabin.gd`, `seats.gd`, `kit.gd`, `kit/jet_1964.gd`, `kit/procedural.gd`,
`atmosphere.gd`, `passing.gd`, `presentation.gd`, `sky.gd`; the stars from the catalogue under "Data") on library
materials (`painted_wall`, `walnut_veneer`, `woven_carpet`, `woven_upholstery`, `linen`, `brushed_steel`, `dark_metal`,
`brass`, all CC0). Its sounds (pressurised jet cabin drone, ceiling projector and cabin boarding chime) are synthesised.
