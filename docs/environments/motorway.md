# The motorway system

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each part is.

`app/scripts/env/systems/motorway.gd`, kind `journey` (`moves_viewer: false`). Streams a real-world road corridor past a stationary vehicle cabin at authentic cruising speed (~70 mph / 31.29 m/s, scaled by `comfort.motion`, held cleanly when playback pauses). Built for the **Real drives** category (`category: "drive"`).

## Bundled route data (`app/environments/routes/`)

A motorway room points the system at five compact offline-baked files under `res://environments/routes/`:

| File | Role | Licence |
|---|---|---|
| `m1_route.bin` | 310.03 km M1 corridor sampled every 100 m (3,101 records × 76 bytes = 236 KB): heading, curvature, smoothed bare-earth elevation, grade, 11 lateral DEM heights, 11 lateral land-cover RGBs, OSM lighting/barrier/viaduct/chalk/woodland flags and river-valley mist | ODbL 1.0 / CC-BY 4.0 |
| `m1_route_meta.json` | 54 real M1 junctions, 10 Service Areas, 279 real OSM overbridges (chainage, width, skew, road/rail/foot), 649 skyline objects (National Grid pylons, chimneys, turbines) and 5 major landmarks | ODbL 1.0 |
| `m1_signs_atlas.png` + `.json` | 48 pixel-exact UK TSRGD motorway road signs packed into one 2048×2048 atlas: Diagrams 823/824/825 countdown markers, Diagrams 2904/2905 1-mile & ½-mile fork ADS with black junction-number patches, Diagram 2906 exits, 3-lane overhead gantries with downward TSRGD lane arrows, Motorway Services signs, Ch.7 §10.4 route confirmatory signs, and steady amber dot-matrix `50` / blank signals | OGL 3.0 (atlas) / CC0 (JSON) |
| `uk_trees_impostors.png` | 4×4 alpha-cutout British trees and hedgerow shrubs (oak, ash, beech, birch, sycamore, hawthorn, Scots pine, poplar, blackthorn, buddleia, gorse, bramble, cherry laurel) | CC0 1.0 |

## Rendering and draw budget (7 draws total)

1. **`MotorwayRoad`** (`env_motorway_road.gdshader`) — Curved 6-lane motorway ribbon with UK 2 m/7 m dashed markings, red/white/amber cat's-eyes, wet grazing reflections, per-stretch SOX/SON streetlamp pools and dipped xenon headlight cones.
2. **`MotorwayTerrain`** (`env_motorway_terrain.gdshader`) — Left & right countryside strips driven by live 64×11 streaming height & WorldCover colour `ImageTexture`s, steep Chiltern chalk cuttings, distant sodium urban glow and automatic low-DEM river-valley mist.
3. **`MotorwayTrees`** (`env_motorway_trees.gdshader`) — Crossed-quad alpha-scissored (`ALPHA_SCISSOR_THRESHOLD`, 0.00 blend overdraw) British trees & hedgerows weighted by real OSM woodland density.
4. **`MotorwaySigns`** (`env_motorway_signs.gdshader`) — Instanced retroreflective UK TSRGD signs and self-lit amber dot-matrix `50` gantry signals.
5. **`MotorwayHardware`** (`env_motorway_props.gdshader`) — Instanced central barriers (Armco / concrete step / shrubbed), SOX/SON streetlamp columns, steel portal gantries, 279 real OSM overbridges, Leicester Forest East bridge café, National Grid pylons, and Lane 1 / oncoming traffic.
6. **`MotorwayTowers`** (`env_motorway_props.gdshader`) — Instanced hyperbolic cooling towers (Ratcliffe-on-Soar's 8 towers + flue chimney), Emley Moor mast, brick chimneys and turbines.
7. **`MotorwayHalos`** (`env_motorway_halo.gdshader`) — Soft additive glow halos on streetlamps, active amber matrix signals and distant vehicle lights in fog/night.

## Parameters and live telemetry

- `start_at` (`london_j1`, `chilterns_j10`, `watford_gap_j16`, `leicester_j21`, `ratcliffe_j24`, `sheffield_j33`, `leeds_j47`) & `direction` (`northbound`, `southbound`): swaps lateral DEM/colours, sign schedules and travel sign cleanly in real time.
- `time_mode` (`morning`, `afternoon`, `golden`, `dusk`, `night`, `progress`) & `weather_mode` (`mixed`, `clear`, `overcast`, `fog`, `rain`, `storm`): drives the sibling `sky` and `weather` systems directly via `set_param()`, activates steady amber `50` matrix signals in fog/storms, triggers comfort-safe ~1.15 s cloud-sheet lightning (respecting `Flickering lights`) with delayed `thunder_roll`, and drives wiper sweep & wet glass.
- **Overbridge audio occlusion:** binary-searches all 279 real OSM overbridges every tick; passing under a deck triggers `bridge_whoosh` and smoothly dips `rain_roof` and `rain_windscreen` via `sound_bed.external_gain` (~82% attenuation).
- Publishes `journey.speed`, `journey.progress`, `weather.rain` and `weather.wet` channels plus `current_km()`, `speed_mph()`, `rain_level()`, `wet_level()`, `wiper_phase()`, `under_bridge()`, `bridge_shelter()` and `matrix_active()`.
