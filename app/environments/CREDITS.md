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

## Bathysphere

- `app/environments/bathysphere.env.json`: no asset of its own. The hall, the water, the fish, the glowing creatures
  and the whale are made in code by the systems; its surfaces are library materials (oak planks, dark metal, brass,
  velvet). The whale's song is synthesised.

## Crater

- `app/environments/crater.env.json`: no asset of its own. The tiers, the rocks, the dome, the crater's rim, Earth
  and the stars are made in code by the systems (the stars from the catalogue under "Data"); its surfaces are library
  materials (rough plaster, smooth concrete, dark metal, brushed steel). It makes no sound.
