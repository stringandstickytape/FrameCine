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

## Screen 3 - 1983 (`screen_3_1983.env.json`)

No bundled asset. The hall, the seats, the partition, the swirling carpet and the water stain are the systems' own
shapes and procedural patterns on library materials (`woven_upholstery`, `black_leather`, `felt`, `oak_veneer`,
`acoustic_foam`, `rough_plaster`, the auditorium's defaults); the worn print's dust, scratches and weave are the
presentation system's shader.

## Drive-in - 1958 (`drive_in_1958.env.json`)

No bundled asset. The lot, the car, the screen tower, the snack bar and its neon letters are the systems' own shapes
on library materials (`smooth_concrete` and the builders' defaults); the sky's stars are the sky system's catalogue
(above), the mesas and the moths are made in code.
