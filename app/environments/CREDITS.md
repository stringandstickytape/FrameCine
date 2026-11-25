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

## The Salon 1870 (`salon_1870.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The 1870 Victorian submarine velvet salon, its riveted wrought-iron pressure hull ribs, two monumental
bolted-brass circular viewports with animated 10-blade mechanical brass iris shutters, mahogany diamond-lattice
bookcases, terrestrial globe, naturalist credenzas, armillary sphere, chambered shell sculpture, marine chronometer,
compass binnacle, ballast valve manifold, 21-pipe aft salon organ, Chesterfield club chairs, Art Deco runner carpet,
caustics-lit seabed, giant kelp forests, coral sea rocks, sunken galleon wrecks, hydrothermal volcanic vents, schooling
fish, bioluminescent jellies, gliding manta ray and whale are made in code by the systems (`cabin.gd`, `seats.gd`,
`kit.gd`, `kit/salon_1870.gd`, `kit/procedural.gd`, `passing.gd`, `life.gd`, `music.gd`, `sky.gd`) on library materials
(`wood_panelling`, `walnut_veneer`, `velvet`, `dark_metal`, `brass`, `tufted_leather`, `woven_carpet`, `white_marble`,
all CC0). Its sounds (hull hum, water wash, vent bubbles, hull creaks, brass engine-room telegraph bell and pipe organ)
are synthesised.

## Coach trip 1988 (`coach_trip_1988.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The 1988 overnight express touring coach, its 1988 swirly moquette carpet, drawn burgundy driver's
curtain, overhead ceiling-mounted 4:3 CRT television and top-shelf video recorder flashing `12:00` beside rental tape
cases, luggage racks with eyeball vents and night strips, tied-back cream window curtains, red break-glass hammer boxes,
recliners with woven linen antimacassars, flip-down tray tables and net magazine pockets, aft vestibule door, backlit
EXIT placard, working quartz clock, wind-drifting rain panes, wet asphalt motorway, distant sodium highway lamps,
direction gantries, motorway services, sky and stars are made in code by the systems (`cabin.gd`, `seats.gd`, `kit.gd`,
`kit/coach_trip_1988.gd`, `kit/procedural.gd`, `passing.gd`, `weather.gd`, `presentation.gd`, `sky.gd`; the stars from
the catalogue under "Data") on library materials (`painted_wall`, `corduroy`, `walnut_veneer`, `wood_panelling`,
`woven_carpet`, `woven_upholstery`, `brown_leather`, `brushed_steel`, `dark_metal`, all CC0). Its sounds (rear coach
diesel, VCR tape load, CRT whine, rain on glass and motorway wind) are synthesised.

## Back seat 2004 (`back_seat_2004.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The 2004 family car back seat, its clamshell roof-mounted flip-down portable LCD screen and courtesy
map lamps, contoured empty front seats with map pockets, paperback and road atlas, glowing 2004 dashboard dials, hooded
`23:14` stereo clock, illuminated climate knobs, steering wheel, gearstick and travel mug, rear bench with draped wool
tartan blanket, cushions, disc carry-case, wired headphones and heated tailgate glass, sideways-drifting raindrops on
four car panes, damp asphalt motorway, distant highway lamps, direction gantries, motorway services, sky and stars are
made in code by the systems (`cabin.gd`, `kit.gd`, `kit/back_seat_2004.gd`, `kit/procedural.gd`, `passing.gd`,
`weather.gd`, `presentation.gd`, `sky.gd`; the stars from the catalogue under "Data") on library materials
(`melange_fabric`, `plush_carpet`, `woven_upholstery`, `painted_wall`, `brushed_steel`, `dark_metal`, all CC0). Its
sounds (car motorway engine/tyres, rain on car glass and roof wind) are synthesised.

## Sky lift (`sky_lift.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The orbital elevator climber car, its curved glazed roof canopy, structural titanium ribs, glowing
carbon-ribbon tether spine, status displays, contour recliners, orbital valance coves, aft airlock bulkhead, mid-century
weave carpet, ocean tether launch platform, drifting cloud banks, tether guide collars, orbital ring docking station,
atmospheric-to-space sky transition, Earth's curved limb (`earth_map.gd`) and 360-degree stars are made in code by the
systems (`cabin.gd`, `seats.gd`, `kit.gd`, `kit/sky_lift.gd`, `kit/procedural.gd`, `passing.gd`, `sky.gd`; the stars
from the catalogue under "Data") on library materials (`painted_wall`, `brushed_steel`, `dark_metal`, `woven_carpet`,
`woven_upholstery`, all CC0). Its sounds (electromagnetic climber hum, fading atmospheric wind and docking chime) are
synthesised.

## Moon ferry (`moon_ferry.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The retro-future cislunar passenger liner, its curved glazed canopy, crimson contour recliners,
stepped white structural cabin frames, overhead valance and floor-guide coves, forward telemetry console, aft circular
airlock hatch and star-chart display, mid-century weave carpet, 360-degree deep space Milky Way, shrinking Earth
(`earth_map.gd`), growing cratered Moon, lunar regolith plain and glowing Crater lunar base are made in code by the
systems (`cabin.gd`, `seats.gd`, `kit.gd`, `kit/moon_ferry.gd`, `kit/procedural.gd`, `passing.gd`, `sky.gd`; the stars
from the catalogue under "Data") on library materials (`painted_wall`, `brushed_steel`, `dark_metal`, `woven_carpet`,
`woven_upholstery`, all CC0). Its sounds (quiet life-support murmur and cabin arrival chime) are synthesised.

## Mars train (`mars_train.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The pressurised Martian rover-train cabin, its ribbed habitat bulkheads, expedition recliners,
indirect raceway and floor-guide coves, geology sample rack with core canisters, forward telemetry console, aft round
airlock door, Martian topography placard, mid-century weave carpet, pale-blue Martian sunset and small solar disc,
cratered rust-ochre regolith, swirling dust devils, Martian rocks, red mesas, glowing domed Martian night colony, sky
and stars are made in code by the systems (`cabin.gd`, `seats.gd`, `kit.gd`, `kit/mars_train.gd`, `kit/procedural.gd`,
`passing.gd`, `sky.gd`; the stars from the catalogue under "Data") on library materials (`painted_wall`, `brushed_steel`,
`dark_metal`, `woven_carpet`, `woven_upholstery`, all CC0). Its sounds (electric rover-train drive, thin Martian wind
and arrival chime) are synthesised.

## Cenote cavern (`cenote_cavern.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The underground limestone sinkhole, tiered viewing island, timber boardwalk bridge, arched grotto
portal, karst cavern dome, stalactites, stalagmites, jungle oculus roots/vines/ferns, carved basalt screen pylons,
hanging bronze lanterns, faceted mineral crystals, emerald-turquoise cenote pool (`env_world_water.gdshader`),
volumetric moonlight/dusk shafts (`env_world_shaft.gdshader`), fireflies, mist, sky and stars are made in code by the
systems (`domestic.gd`, `seats.gd`, `kit.gd`, `kit/cenote_cavern.gd`, `kit/procedural.gd`, `life.gd`, `atmosphere.gd`,
`sky.gd`; the stars from the catalogue under "Data") on library materials (all CC0). Its sounds (cavern hum, drips,
water lap and crickets) are synthesised.

## Orbital ring (`orbital_ring.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The cantilevered travertine and titanium observation terrace, crescent sapphire infinity pool
(`env_world_water.gdshader`), gull-wing canopy ribs, glass balustrades, cedar planters with bamboo and cypresses,
moulded cedar lounge-chair shells, working orbital clock, backlit geometric schematic displays, colossal rotating
O'Neill cylinder interior shell with land valleys, silver rivers, snow-crowned alpine end-caps, radial spokes and night
cities (`env_ring_world.gdshader`), sky and stars are made in code by the systems (`domestic.gd`, `seats.gd`, `kit.gd`,
`kit/orbital_ring.gd`, `sky.gd`; the stars from the catalogue under "Data") on library materials (all CC0). Its sounds
(wind, distant city murmur, fountain and cabin chime) are synthesised.

## Cloud temple (`cloud_temple.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The floating stepped white-marble sky sanctuary, inlaid brass astrolabe floor rings, procedural mosaic
medallion (`mosaic_medallion`), 16 fluted Ionic columns, broken classical entablatures, carved marble benches, twilight
reflecting water basin (`env_world_water.gdshader`), fluted screen pylons, four bronze tripod braziers with flickering
flames, aft brass armillary altar, 360-degree sunlit-to-starlit cloud sea (`env_cloud_sea.gdshader`), distant floating
ruin islands, volumetric sunset shafts (`env_world_shaft.gdshader`), sky and stars are made in code by the systems
(`domestic.gd`, `seats.gd`, `kit.gd`, `kit/cloud_temple.gd`, `kit/procedural.gd`, `sky.gd`; the stars from the catalogue
under "Data") on library materials (all CC0). Its sounds (cloud wind, brazier fire and temple bell) are synthesised.

## Venus aerostat (`venus_aerostat.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The octagonal hammered-copper and brass Art Nouveau cloud gondola, parquet floor with brass compass
rose, mezzanine filigree gallery, arched panoramic bays, glowing overhead buoyant gas envelope and rigging, hanging
glass fern terrariums, atmospheric barometer and spectrometer console, working astronomical clock, riveted circular
airlock, 360-degree golden-amber Venusian cloud canyons (`env_venus_clouds.gdshader`), companion aerostat silhouettes
and golden cloud shafts (`env_world_shaft.gdshader`) are made in code by the systems (`domestic.gd`, `seats.gd`,
`kit.gd`, `kit/venus_aerostat.gd`, `sky.gd`) on library materials (all CC0). Its sounds (aerostat hum, distant cloud
rumble and chime) are synthesised.

## Sunken rotunda (`sunken_rotunda.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The flooded classical Atlantis marble rotunda, stepped circular mosaic dais (`mosaic_medallion`),
knee-deep rippling peristyle canal (`env_world_water.gdshader`), 12 fluted columns with one romantically ruined breach
and tumbled drums, coffered open-oculus dome, monumental wave-scroll screen pylons, waterproof bronze lanterns,
terracotta amphorae, coral, sea-ferns, distant outer aqueduct arches, underwater light shafts (`env_world_shaft.gdshader`),
caustics, schooling fish, bioluminescent jellies, manta ray and whale are made in code by the systems (`domestic.gd`,
`seats.gd`, `kit.gd`, `kit/sunken_rotunda.gd`, `kit/procedural.gd`, `life.gd`, `sky.gd`) on library materials (all CC0).
Its sounds (deep hum, water lap, vent bubbles, temple bell and whale song) are synthesised.

## Giants study (`giants_study.env.json`, built by Gemini 4 Neon Extra High)

No bundled asset. The 10:1 miniature-scale late-night Victorian study desk, baked gold-tooled green leather blotter
(`leather_blotter`), stitched felt coaster nook, brushed-brass and walnut pocket display on folded notebook and ruler,
leaning gilded leather book stack, working 2.3 m brass pocket watch, steaming porcelain teacup and saucer, lacquered
fountain pen, soaring 7.8 m banker's desk lamp with light cone (`env_world_shaft.gdshader`), crystal inkwell, ceramic
pencil pot, brass spectacles, magnifying glass, paperclip, shadowy bookshelves, roaring fireplace hearth, colossal
leaded window, rain panes, sky and stars are made in code by the systems (`domestic.gd`, `seats.gd`, `kit.gd`,
`kit/giants_study.gd`, `kit/procedural.gd`, `weather.gd`, `atmosphere.gd`, `sky.gd`; the stars from the catalogue under
"Data") on library materials (all CC0). Its sounds (magnified pocket watch tick, rain on glass, distant fire and
sleeping-cat purr) are synthesised.
