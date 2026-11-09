# The rooms

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

## The cinema set

Every room keeps the cross-cutting rules: a "dim during the film" setting, seat picking by pointing, its own
acoustics, music only from our synthesiser or CC0 samples (many sample sets are CC-BY and cannot be bundled), no
people.

| # | Room | Builders and kits | Light, sky, atmosphere | Life, sound, music | Timeline and cues | Screen | Settings |
|---|---|---|---|---|---|---|---|
| 1 | Shopfront picture house, 1906 | `shopfront` (`edwardian`: pressed tin, a drawn player piano, its own tin booth, the street outside), folding chairs (`seats`) | gas lamps (`light`, flicker), a dusty beam (`screen_frame`, `atmosphere`) | projector clatter behind (`sound_bed`), a player piano that plays along (`music`, `film.transient`) | the piano starts in `starting` | a framed sheet | piano on or off |
| 2 | Atmospheric, 1928 | `auditorium` with `ceiling_cover` 0, thirteen courtyard houses (balconies, towers, a loggia, an oriel, an arcade, lit windows), a palace gate with organ grilles and drapes, lions, cypresses, palms, a stone pine (`kit`) | an open dusk `sky` with real stars, a crescent moon, clouds lit by the town and the screen (`film.colour`); lanterns and floods baked | a wall fountain, crickets, a scops owl (`sound_bed`), a theatre organ before the film (`music`) | the courtyard goes to bed with the film (windows out one by one), curtains part (`showing`) | | clouds, organ |
| 3 | Streamline, 1937 | `auditorium` dressed by the moderne kit (`kit/streamline.gd`): a stepped ceiling of coves, faience, jade and chrome bands round the hall and a bowed circle front, reeded pilasters, shell lights, a rising-sun carpet; a stepped proscenium round a rising sun, organ grilles, a clock | coves that cycle colours and then follow the film at a glow (`kit` `cove_*`, `film.colour`) | an organ (`music`) | the console rises lit from the pit and the organ plays as the room opens and at the end, a cadence and the console down as the film starts (`motion`) | a festoon curtain up behind the proscenium's head (`motion`) | cove colours |
| 4 | Screen 3, 1983 | `auditorium` with `partition_z` (a subdivided balcony), plasterboard, swirly carpet, one broken seat, a water stain (picture) | smoke haze in the beam (`atmosphere`), a flickering exit sign (`flicker`) | rumble through the wall (`sound_bed`, `film.bass`) | | gate weave, a slight tilt (`presentation`) | weave and tilt |
| 5 | Drive-in, 1958 | `terrace` (the lot), a convertible's bench seat (`vehicle`), a screen tower, a neon snack bar (`kit`) | dusk to stars over the film (`sky`, film-time tracks), mesas (`vista`) | moths in the beam (`life`), a far freight train (`sound_bed`, `every`) | | the window speaker (`presentation`) | tinny speaker |
| 6 | Screening room, 1962 | `domestic` (walnut), club chairs (`seats`), a bar cart (objects) | a pool glowing through the window (`vista`) | | a painting slides up to show the screen (`motion`, ritual) | | |
| 7 | Rooftop summer cinema, Athens | `terrace` (`city`: the roof by hand), director's chairs | the city all round and a floodlit temple on its hill (`terrace` `city`), plane lights, moths (`life`) | cicadas, the city's murmur, mopeds, a church bell (`sound_bed`), a cat on the wall (`life`) | | a screen painted on a wall | |
| 8 | Pink Palace | `auditorium` dressed by the shell kit (`kit/pink_palace.gd`): a fluted shell vault, five scalloped rings round the screen, mirrors, pilasters, a wave frieze, a buttoned balcony, a shell carpet | troughs that drift pink to blue and then follow the film at a glow (`kit` `cove_*`, `film.colour`); a sunburst dome whose lamps swell and fall (a kit of its own), a chandelier of glass shells | the house bells (`sound_bed`) | the bells, the festoon rises (`motion`) | a festoon with a gold fringe (`motion` `festoon_fringe`) | |
| 9 | Palace of Culture, 1974 | `auditorium`, board-marked concrete, ochre curtains | a mosaic wall that glitters in the screen's light (material, `film.colour`), snow and birches outside (`vista`, `weather`) | an echoey hall (`acoustics`) | | | snow |
| 10 | Flagship | `auditorium`: steep rake, black walls | blue step lights (`light`) | | the ritual | a huge curved screen | seat choice |
| 11 | Nave | `nave`, pews (`seats`) | a dim rose window, candles (`light`, flicker), the film's light climbing the stone | reverb (`acoustics`) | | in the chancel | candles |
| 12 | Reclaimed | `auditorium` with `ceiling_cover` 0.5 and `shell` `kit`; the ruin, ivy, a birch, ferns and wildflowers (`kit`, `ruin_*`) | stars (`sky`), dynamic `weather` (rain into a puddle that reflects the film) | birds, fireflies, an occasional deer (`life`) | | a patched sheet | weather |
| 13 | Ice cinema | `domestic` (`shell` `kit`) with the ice hall's pieces (`kit`: blocks, carvings, a vault with skylights, a snowfield outside), hides (`seats`) | candles inside the ice, the film's colours through the front wall, the aurora in the window and the skylights (`sky`), breath fog (`atmosphere`), snow outside (`weather`) | far huskies, ice creaks (`sound_bed`) | candles down and the aurora settles with the film | | aurora |
| 14 | Bathysphere | `dome_hall` (glass; the sea floor, kelp, coral, a sunken bell, a vent, marine snow, floodlights; portholes, rivets, gauges, a sonar console) | the water by depth, Snell's window and shafts, caustics (`light`) | schools of fish, glowing creatures drawn to the screen, a manta overhead, a rare whale in a quiet scene (`life`, cue with `cooldown`), hull creaks, the vent's bubbles, a sonar ping, a far song (`sound_bed`) | floodlights down with the film, the scope dims, pings in the pre-show | | depth, lights outside, whale |
| 15 | Crater | `terrace` (`lunar`: a Moon base's amphitheatre, the plain, the crater's wall, a base, a lander, a rover) under a `dome_hall` (`geodesic`, airlocks, trays) | Earth as itself turning over the screen (`sky` `earth_detail`), the Milky Way when the lights dim, the crater's peaks in the sun | silence (no bed) | the dome's lamps out, the strips low | | Earth's speed |
| 16 | Void | `mirror_floor` | black | | | | ripple |
| 17 | Pillow Fort, 1993 | `domestic` (cushions, a bedsheet), a tree, a tin of sweets (objects) | fairy lights (`light`, flicker), rain on the window (`weather`) | a ticking radiator (`sound_bed`) | the VCR flashes 12:00 (object widget) | a CRT telly (`presentation`, TV-era display) | the telly fills the opening |

## Journeys

A cabin that goes somewhere for as long as the film lasts: the scenery goes by outside its windows, a pause holds it,
and a film of known length arrives as it ends (`cabin`, `passing`). The Room tab lists them under Journeys
(`category` `journey`).

| # | Room | Builders and kits | Light, sky, atmosphere | Life, sound, music | Timeline and cues | Screen | Settings |
|---|---|---|---|---|---|---|---|
| 1 | Narrowboat | `cabin` (a canal boat's saloon: leaning walls, an arched roof, round-cornered windows, wall lamps), a stove, a rug and a sideboard (`kit`) | dusk to night over the film (`sky`, film-time tracks); reeds, willows, a hedge, bridges, a village's lights and a wharf going by (`passing`), mist later on | an owl, a far church bell, the engine (following `journey.speed`) and water on the hull (`sound_bed`) | the lamps down with the film, the bell as the church comes by | on the front bulkhead | |

## TV-era rooms

The same `presentation` chain makes the TV-era rooms: source (a broadcast, a tape, a disc), transmission (aerial
noise, ghosting, a weak signal), display (a mechanical-scan set's orange glow, 1930; a round-cornered CRT; a
shadow mask; a flat panel). Each era is a preset of the chain plus a `domestic` room. Names are pastiche, never the
real mark (the names check).

## Time travel

One film, and while it plays the room moves forward through the history of television, an era at a time
(`scripts/env/time_travel.gd`, `main.features.time_travel`; the Room tab's Television group: Time travel, and Over
the film or every 5, 10 or 15 minutes; the assistant's `time_travel`). The eras are the TV rooms whose ids start
`tv_`, in the order of their year (`tv_today` and `tv_future` last); the Pillow Fort is not an era. Turned on in a
room that is not an era, it goes to the first at once. Over the film, the rest of the film is shared by the eras
still to come (at least a minute each). The countdown runs only while the film plays; it stops itself at the last
era, at the end of the film, on a new file, and when the viewer picks a room that is not an era. The film plays on
through each change: only the room changes.
