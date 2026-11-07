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
