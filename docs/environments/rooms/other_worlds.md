# Other worlds: the six rooms

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

The Other worlds category (`category` `world`, listed under **Other worlds** in the Room tab): six impossible sanctuaries
to watch a film — underground caverns, orbital megastructures, floating sky temples, alien cloud cities, flooded classical
ruins, and miniature scale worlds. Every room is 100% procedural (zero bundled assets, zero people, zero real marks, zero
live lights) and has a room page of its own. All six are built by **Gemini 4 Neon Extra High**.

## The list

| # | Room | State | What it is | Measured (draws / tris / MB) |
|---|---|---|---|---|
| 1 | Cenote cavern | **built** ([`cenote_cavern.md`](cenote_cavern.md)) | underground karst limestone sinkhole and crystal grotto with turquoise cenote pool, jagged jungle oculus open to the tropical night sky and Moon, volumetric light shafts, glowing mineral crystals, fireflies, timber boardwalk and carved basalt screen pylons | 21 / 52,555 / 6.4 MB |
| 2 | Orbital ring | **built** ([`orbital_ring.md`](orbital_ring.md)) | cantilevered travertine and titanium observation terrace inside a colossal rotating O'Neill cylinder habitat where upside-down valleys, silver rivers, alpine end-caps and night cities curve overhead between real open Milky Way space windows | 21 / 47,316 / 9.4 MB |
| 3 | Cloud temple | **built** ([`cloud_temple.md`](cloud_temple.md)) | open-air circular white-marble sky sanctuary suspended above an endless golden-dusk sea of clouds, with 16 fluted Ionic columns, mosaic medallion floor, sky-reflecting water basin, four bronze tripod braziers, distant floating ruin islands and sunset-to-Milky-Way skies | 17 / 36,174 / 5.3 MB |
| 4 | Venus aerostat | **built** ([`venus_aerostat.md`](venus_aerostat.md)) | gilded hammered-copper and brass Art Nouveau observation gondola suspended 52 km above Venus inside sunlit golden-amber cloud canyons beneath a glowing ivory buoyant gas envelope, with hanging fern terrariums, companion aerostats, spectrometer console and circular airlock | 21 / 54,872 / 9.3 MB |
| 5 | Sunken rotunda | **built** ([`sunken_rotunda.md`](sunken_rotunda.md)) | flooded classical marble Atlantis rotunda on the sunlit sea floor: mosaic dais, 12 fluted columns under a ruined coffered dome oculus, knee-deep rippling peristyle canal, amphorae, coral, underwater light shafts, caustics, schooling fish, jellies, overhead manta ray and rare whale | 21 / 50,703 / 6.3 MB |
| 6 | Giants study | **built** ([`giants_study.md`](giants_study.md)) | 10:1 miniature-scale late-night rainy study where you sit 10 cm tall on a stitched coaster on a giant mahogany desk: gold-tooled green leather blotter, propped brass pocket display, 5.8 m stack of leather books, steaming porcelain teacup, working 2.3 m pocket watch, 7.8 m banker's lamp, inkwell, pencils, spectacles and distant roaring fireplace | 29 / 24,147 / 9.2 MB |

## Shared additions

- **Category:** `"world": "Other worlds"` in `app/scripts/env/env_doc.gd` (`ROOM_GROUPS`) with its group help text in `app/ui/room_tab.gd`.
- **Shared shaders:** `app/shaders/env_world_water.gdshader` (opaque animated rippling reflective water with dual-layer caustics and live film screen spill) and `app/shaders/env_world_shaft.gdshader` (soft Fresnel-feathered additive volumetric light shafts).
- **Room-specific world shaders:** `app/shaders/env_ring_world.gdshader` (O'Neill cylinder valleys, rivers and night cities), `app/shaders/env_cloud_sea.gdshader` (360-degree sunlit-to-starlit cloud sea), and `app/shaders/env_venus_clouds.gdshader` (Venusian golden-amber cloud canyons with slow sub-0.25 Hz sheet lightning).
- **Procedural patterns:** `mosaic_medallion` and `leather_blotter` in `app/scripts/env/systems/kit/procedural.gd`.
- **Synthesised sounds:** `cavern_hum`, `cloud_wind`, `temple_bell`, `aerostat_hum`, and `giant_clock` in `app/scripts/env/env_synth.gd` and `app/scripts/env/systems/sound_bed.gd`.
