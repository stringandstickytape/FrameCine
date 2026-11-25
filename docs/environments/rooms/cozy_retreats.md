# Cozy retreats: the six rooms

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

The Cozy retreats category (`category` `retreat`, listed under **Cozy retreats** in the Room tab): six warm, intimate
hideaways sheltered from the weather — an alpine snowed-in A-frame chalet, a stormy Atlantic lighthouse watchroom with a
rotating Fresnel lens, a rainy oak-canopy treehouse, a lantern-lit Kyoto koi-garden pavilion, a midnight Victorian
glasshouse, and a two-storey antique bookshop loft after closing. Every room is 100% procedural (zero bundled assets,
zero people, zero real marks, zero live lights), seats the viewer dead-centre head-on in an odd-numbered row with zero
centre aisle (`seats_per_row: 3`, `(0, 0, 0)` facing `-Z`), and has a room page of its own. All six are built by
**Gemini 4 Neon Extra High**.

## The list

| # | Room | State | What it is | Measured (draws / tris / MB) |
|---|---|---|---|---|
| 1 | Snowed-in cabin | **built** ([`snowed_in_cabin.md`](snowed_in_cabin.md)) | steep alpine timber A-frame chalet snowed in on a moonlit winter night: roaring river-stone fireplace with dancing flames and copper kettle, woven `nordic_rug`, steaming cocoa on a live-edge cedar table, wagon-wheel chandelier, sleeping loft, wooden skis and heavy alpine snowfall outside the gable glass | 28 / 57,628 / 9.1 MB |
| 2 | Lighthouse watchroom | **built** ([`lighthouse_watchroom.md`](lighthouse_watchroom.md)) | circular whitewashed-stone and riveted cast-iron coastal lighthouse lantern room perched 26 m above a stormy Atlantic headland: helical diamond storm-glass cage with rain panes, live rotating brass-and-crystal Fresnel lens sweeping twin golden beams above the screen, oak chart desk, telescope, chronometer clock, spiral stair hatch, Atlantic surf and coastal foghorn | 27 / 36,630 / 7.6 MB |
| 3 | Rainy treehouse | **built** ([`rainy_treehouse.md`](rainy_treehouse.md)) | cedar-plank and pitched corrugated-tin canopy hideaway 14 m up in a gnarled mossy oak tree: wide propped-open timber shutters, festooned fairy lanterns, cedar-stump tea table, hinged trapdoor and rope ladder, curving 34-slat wooden rope suspension bridge into misty neighbouring oaks, tin-roof rain and drifting fireflies | 23 / 56,816 / 6.4 MB |
| 4 | Kyoto garden pavilion | **built** ([`kyoto_pavilion.md`](kyoto_pavilion.md)) | serene traditional hinoki-cypress *engawa* verandah inlaid with `tatami_weave` matting, backlit *shoji* sliding screens and *tokonoma* alcove, opening onto an animated mirror-emerald koi pond with 18 swimming Nishikigoi, curved vermilion footbridge, raked *karesansui* Zen gravel, granite stone lanterns, tipping bamboo *shishi-odoshi* water clack and seasonal cherry/maple trees | 25 / 42,732 / 6.5 MB |
| 5 | Greenhouse at night | **built** ([`night_greenhouse.md`](night_greenhouse.md)) | curved Victorian wrought-iron and ribbed-glass barrel-vault conservatory in the midnight rain: terracotta-and-slate `quarry_tiles` floor with cast-iron heating grate, rose-brick dwarf walls, kentia and fan palms, fruiting dwarf lemon and tangerine trees, hanging fern baskets, glass bell cloches, drip fountain, warm mist and rain-streaked glass vault | 25 / 76,796 / 7.2 MB |
| 6 | Bookshop loft | **built** ([`bookshop_loft.md`](bookshop_loft.md)) | warm walnut-and-oak mezzanine loft overlooking a two-storey antique bookshop after closing: turned-oak and brass balustrade above an open atrium well, floor-to-ceiling jewel-toned bookshelves on both storeys, three rolling brass library ladders, Chesterfield armchairs on a `nordic_rug`, emerald banker's lamps, tall oak grandfather clock, rain-beaded dormer skylights and sleeping shop-cat purr | 27 / 50,168 / 8.2 MB |

## Shared additions

- **Category:** `"retreat": "Cozy retreats"` in `app/scripts/env/env_doc.gd` (`ROOM_GROUPS`) with its group help text in `app/ui/room_tab.gd`.
- **Procedural patterns:** `tatami_weave` (traditional woven *igusa* rush tatami matting with dark pine brocade *heri* borders) and `nordic_rug` (hand-loomed wool oatmeal-cream, crimson, spruce and ochre geometric diamond cabin rug) in `app/scripts/env/systems/kit/procedural.gd`.
- **Synthesised sounds:** `foghorn`, `ocean_surf`, `bamboo_clack`, `rain_tin`, and `grand_clock` in `app/scripts/env/env_synth.gd` and `app/scripts/env/systems/sound_bed.gd`.
