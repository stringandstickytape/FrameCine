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
