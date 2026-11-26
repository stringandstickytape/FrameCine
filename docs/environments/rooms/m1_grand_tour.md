# M1 Grand Tour

Flagship room of the **Real drives** category (`category: "drive"`), built by **Gemini 4 Neon Extra High**.

- **Document:** `app/environments/m1_grand_tour.env.json`
- **Kit pieces:** `gt_2004_cabin`, `gt_2004_dash` (`app/scripts/env/systems/kit/m1_grand_tour.gd`)
- **Corridor system:** `motorway` (`app/scripts/env/systems/motorway.gd`, `docs/environments/motorway.md`)
- **Tests:** `app/tests/test_room_m1_grand_tour.gd`

## Design

### 2004 British Grand Tourer interior
Sculpted in Blender (`app/environments/m1_grand_tour/gt_2004_interior.glb`, CC0 1.0, 8 VR-optimised material draw groups with metre-scale automotive UVs and 24-ray BVH baked vertex-colour contact ambient occlusion) on a 2004 British coachbuilt grand tourer extended with spacious 4-door saloon rear seating so the viewer sits comfortably dead-centre head-on (`(0, 0, 0)`) on a plush 3-across contoured leather bench (`seating: "bench"`, zero centre aisle; `"shell": "kit"`):

- **Sleek GT greenhouse & coachwork:** Curved Alcantara dome headliner, slim raked A/B/C pillars, seamless trapezoidal side windows framed by dark rubber seals and gleaming chrome daylight-opening brightwork, sculpted power-domed slate bonnet, and aerodynamic static-tinted wing & interior mirrors.
- **Three instant coachbuilt trims** (`setting.trim`): `Saddle & Burr Walnut`, `Charcoal & Dark Walnut`, and `Oxblood & Dark Walnut`, live-tinted via `GtLiveRig` without rebuilding geometry.
- **Twin-wing burr-walnut cockpit:** Silky charcoal upper leather roll, symmetric stitched-hide wings framing clearcoat book-matched walnut veneer flowing into sweeping two-tone walnut door cards with boomerang leather armrests and chrome pull latches, four gleaming knurled-chrome bullseye air vents with turned-chrome organ-stop pull plungers, central chrome-bezel live analogue clock (`PieceClock`, zero brand logo), hooded RHD 4-gauge chrome binnacle with live animated amber-red speedo & tacho needles (`0 -> 70+ mph`), unbranded 4-spoke wheel with alloy shift paddles and drilled sport pedals, and naturally positioned 17°-reclined empty cobra front bucket seats with walnut seatback inlays.
- **Twin synchronised live video screens (zero extra SubViewports):** Primary 16:9 cinema screen (`center: [0.0, 0.99, -0.61]`, `size: [0.48, 0.27]`) anchored cleanly at its top corners to the upper shoulders of both reclined front seatbacks via twin brushed-alloy bridge brackets (leaving the compact burr-walnut rear climate console completely unobstructed underneath and the panoramic windscreen & wide GT side windows open around it), plus a flush inset waterfall `DashScreen` framed by 4+4 chrome-rimmed soft keys that mirrors `Flat.material_override` directly (1 quad, 2 tris, 1 draw).
- **Wipers & wet glass:** Animated twin physical front wiper arms synchronised with `env_gt_windscreen.gdshader`'s live swept clear-arc rain mask. Static tinted exterior & interior mirrors only.

### Real 310 km M1 corridor (London J1 ↔ Leeds J48)
Driven by pre-baked open geographic extracts (`app/environments/routes/m1_route.bin`, `m1_route_meta.json`, `m1_signs_atlas.png` + `.json`, `uk_trees_impostors.png` — fully credited in `app/environments/CREDITS.md` under ODbL 1.0, CC-BY 4.0, OGL 3.0 and CC0 1.0):

- **Route selector:** `Join motorway at` (`London (J1)`, `Chilterns (J10)`, `Watford Gap (J16)`, `Leicester (J21)`, `Ratcliffe (J24)`, `Sheffield (J33)`, `Leeds (J47)`) and `Direction` (`Northbound` / `Southbound`).
- **Pixel-exact UK TSRGD road signs:** 48 offline-rendered UK motorway signs (Diagrams 823/824/825 countdown markers, Diagrams 2904/2905 1-mile & ½-mile fork ADS with black junction-number patches, Diagram 2906 exits, 3-lane overhead gantries with downward TSRGD lane arrows, Motorway Services signs, Ch.7 §10.4 route confirmatory signs, and steady amber dot-matrix `50` signals activating automatically in fog and thunderstorms).
- **Authentic British atmosphere & landmarks:** Per-stretch real OSM lighting (unlit countryside, deep orange SOX, golden SON), central barriers (Armco / concrete step / shrubbed), Lane 1 & oncoming traffic, British trees & hedgerows, National Grid pylons, Chiltern chalk cuttings, Leicester Forest East bridge café, Ratcliffe-on-Soar's 8 hyperbolic cooling towers + flue chimney, Tinsley Viaduct and Emley Moor mast.
- **Spatial audio & overbridge occlusion:** Six custom synths (`gt_w12`, `rain_roof`, `rain_windscreen`, `wiper_swish`, `bridge_whoosh`, `thunder_roll`) with live ~82% roof/windscreen rain occlusion and `bridge_whoosh` triggered beneath every one of the 279 real OSM overbridges.

## Measured budgets

- **Draws:** 28 (headset budget 40)
- **Triangles:** 84,654 (headset budget 400,000)
- **Live lights:** 0
- **Particles:** 550 (budget 4,000)
- **Textures:** 4.3 MB (budget 96 MB)
- **Blend layers:** 0.10 mean, peak 1 (budget 1.0)
- **Build speed:** ~30 ms / 0.20 units (budget 2.5 units)
- **Audio RMS:** -42.4 dBFS pre-show peak stress, -62.4 dBFS under film (target < -38 dBFS)
