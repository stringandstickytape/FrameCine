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

No bundled asset. The hall, its seats and stage, the river and everything that goes by it (willows, trees, poplars,
the fence, cottages, lights, ridges, steamers, the tower and wharves), the sky and its stars are made in code by the
systems (`cabin.gd`, `kit.gd`, `passing.gd`, `sky.gd`; the stars from the catalogue under "Data") on library
materials (`painted_wall`, `wood_panelling`, `oak_planks`, `velvet`, `felt`, `dark_metal`, the kit's `oak_veneer`,
all CC0). Its sounds (the paddle wheel, water, crickets and train) are synthesised.
