# Nave

Part of the environments engine: [`docs/environments.md`](../../environments.md) has the design and says where each part is.

`app/environments/nave.env.json`. *A Gothic nave at night, the screen in the chancel: piers rising into rib vaults,
candles on iron stands and coronae, coloured glass and a rose window in the moonlight.* The deep pass (2026-11-08)
answered "continue working on the environments one-by-one like you did with the bathysphere, really improving their
quality, imagination, delight, detail, lighting and so on. Better to do a smaller number of incredible superb ones
than a large number not so" (the user). Before it the room was the plain nave: round columns, a barrel vault, flat
quads for windows, the seats system's pews, the film's spill (4.5) lighting every wall. The seats, the eye height and
the screen are where they were; the church is drawn by the nave builder's `gothic` style (`kit/nave_gothic.gd`).

- **The architecture** (from the seat, 16.6 m to the vault's crown over a nave 7.6 m between its piers): four bays
  of 3.5 m. Clustered piers of pale limestone, each a round core with four dark polished shafts (a Purbeck-like
  marble, ringed halfway, on their own bases), an octagonal plinth, moulded bases, a capital in stiff-leaf foliage
  (eight three-lobed clumps curling out under a round abacus). Pointed arcade arches of two chamfered orders under a
  hood mould. Over them a string course, a triforium of four small pointed openings a bay into the dark passage
  behind, on dark colonnettes, a second string course, and a clerestory of two-light windows (a mullion, two pointed
  lights, a circle in the head: bar tracery at the glass, splayed reveals, sloping sills). Vaulting shafts rise from
  each pier's capital, ringed at the string courses, to small foliage capitals where the vault springs.
- **The vaults:** quadripartite rib vaults over the nave, the chancel and both aisles: webs of lime-washed stone
  (darker towards the crown), moulded diagonal and transverse ribs, wall ribs over the clerestory's lunettes, a
  foliage boss at each crossing. The crown is lost in shadow above the candles.
- **The aisles:** two-light windows of coloured glass in every bay (three designs in turn: flowers in roundels, a
  diaper of quatrefoils on ruby, a vine winding on blue), wall shafts, a stone bench along the wall's foot; a lancet
  of warm glass in each aisle's east wall beside the chancel.
- **The chancel:** a chancel arch of two orders on continuous mouldings with dark shafts in the angles and a hood,
  cut through a wall that rises to the vault; three worn steps with rounded nosings; a wider chancel (8.8 m) with a
  two-light window either side and its own vault. Over the screen, in the east wall, the rose window (4.2 m): stone
  tracery at the glass (a hub, twelve spokes, the lights' pointed heads, a ring, twelve circles in the outer band) in a
  moulded ring, over a picture of our own glass (a gold flower at the hub, twelve lights of blue with a jewel each and
  ruby borders, roundels of green and gold), brighter to the upper right where the Moon is.
- **The reredos:** the screen framed as an altarpiece in dark oak picked out in gilt, no figures: a buttress either
  side in three stages with sunk panels, gablets, pinnacles with crockets and finials; over the picture a frieze of
  twenty-two small pointed arches under a moulded cornice and a cresting of gilt leaves; under it a panelled dado of
  blind tracery. The picture and its masking stay clear by 0.17 m.
- **The floor:** flagstones laid in courses, each its own size, shade and tilt (a few millimetres), in mortar, the
  aisles' worn paler; larger flags in the chancel. Six ledger stones of dark polished marble let into it (the aisles,
  and two across the nave before the chancel step), each with a border line, a roundel and rows of worn letters no one
  can read now (our own: random letters, nearly half their strokes worn away).
- **The pews:** the church draws them (so the bake lights them): a seat board, an apron, a panelled back leaning
  back under a moulded top rail, a book ledge for the row behind with a few hymn books lying on it (dark cloth), carved
  ends with poppy-head finials (three lobes, at most 1.21 m: every seat's sight line is checked) and a sunk panel; a
  hassock worked in wool at most places, each its own muted colour.
- **Fittings:** a hymn board on the south pier nearest the chancel, turned to the pews, with four numbers painted on
  black slips (117, 364, 52, 408: our own); the west doors of oak boards with iron strap hinges and a ring in a
  pointed doorway under a three-light west window; the stone bench along the aisles.
- **The light:** candlelight against moonlight in deep shadow, baked. Iron pricket stands in the chancel either side
  of the screen (two a side, or four), each a tripod, a turned stem, a drip pan and a thick candle (ivory wax lit
  through near the flame, a drip, the pool glowing: emission in vertex colours) with its flame (the Ice cinema's flame
  picture on crossed quads); three iron coronae over the nave (a hoop with a cresting of leaves, twelve candles each,
  hung on chains from the bosses), the front one high over the screen's view; a votive stand of twenty small lights in
  cups of ruby, amber and blue glass in the north aisle's east end. Each stand, corona and the votive stand is a
  hidden light for the bake only (and a stand-in lamp until the bake). The Moon: high in the south, its light through
  each south window as a narrow spot for the bake, a soft cool patch on the floor, the pews and the piers opposite;
  the south aisle's glass carried along the moonlight onto the aisle's floor as a faint wash of its own colours
  (`MoonPool`, additive, small). The north windows' glass shows dimmer than the moonlit south. The film's spill is
  soft (0.6): the stone near the screen takes the film's colour, the far church stays dim and only tinted.
- **Systems:** `light` (spill 0.6, a dim warm fill, `baked_fill` 0.5), `nave` (`style` `gothic`, `vault` `rib`,
  the chancel at z -6.5 and 4 m deep, 4 pews in front and 5 behind, 9 places each, bay 3.5, piers 5 m to their
  capitals, the vault springing at 12 m, rose radius 2.1, three coronae), `screen_frame` (masking, no beam),
  `acoustics` `stone_nave`, `sound_bed` (wind, candle, owl, bell). No `seats` system.
- **Setting:** Candles (`candles`: none, a few, many): none, the church by moonlight and the film alone (the
  coronae hang unlit, no flames, no candle light in the bake); a few (the default), two stands a side, the coronae
  and the votive lights; many, four stands a side. The nave builds again; the headset bakes again. The flames flicker
  under 3 Hz, a tenth of their light at most (the builders' flicker; common Flickering lights holds them).
- **Cues:** `candles_down` (with the film: the chancel's candles to 20 % over 7 s, the coronae to 30 % and the
  votives to 35 % over 9 s, the rose to 0.12 over 6 s, the windows to 0.2 over 8 s; the house lights' level takes the
  bake down with them), `candles_up` (the pre-show and the end: all back over 5 to 6 s), `bell_preshow` (every five
  minutes before the film, the bell in the tower), `bell_after` (6 s after the end, the bell).
- **Comfort:** the flames waver gently under 3 Hz; nothing moves in the film; nothing stands between a seat and the
  picture (tested from every seat, with many candles too); no candle within the picture's frame from the seat (the
  stands beside it, the coronae high over the nave); the moonlight's pools never move.
- **Measured** (`tests/test_room_nave.gd`, headless, 2026-11-08): 19 draws, 112 510 triangles, no live light, no
  particles, 7.5 MB. Before the pass: 14 draws, 8 290 triangles, 7.0 MB. By part: the carving (piers, capitals,
  mouldings, ribs, tracery, bosses) 64.8k triangles in 1 draw, the walls 10.2k, the corona candles 7.9k, the vaults'
  webs 7.3k, the iron 6.9k, the dark shafts 3.9k, the gilt 3.5k, the oak 3.4k, the cloth 1.3k, the floor 0.8k, the
  chancel candles 0.9k, the votives 0.6k, the glass 0.4k, the flames, the rose, the pool and the masking a few hundred.
  The bake: nine static meshes, 0.70 M texels in their atlases, the largest 588 x 440; the lightmap 1024 x 1024, one
  layer (6.3 MB); about 11 s under lavapipe (a CPU; the headset's GPU should bake faster, but that is
  to be timed there). The textures made at load: the stone's three sets of maps (256 and two 128), the
  windows' atlas (one 96 x 256 cell for each kind of window) and the rose (320 x 320).
- **The costs to watch on the Frame:** fill is small: every surface is opaque on the house shader (the stone's maps,
  no loops), the only blended layers are the flames (small quads), the masking and the moonlight's pools on the
  aisle's floor (a few square metres, seen at a slant). Geometry is moderate (112k triangles, mostly the carving in
  one draw). The bake's time on the headset is the thing to judge (0.7 M texels, 13 lights for it with a few candles;
  15 with many); the load's texture making (a few hundred thousand pixels in GDScript) is the second.
- **The render** (lavapipe, `test_room_nave.gd` with `NAVE_BAKE`): from the seat, left, right, up, back and a side
  seat, in the pre-show and with a film; close in the pre-show: the chancel and the reredos, the rose, a corona, the
  hymn board, a pew's end, a ledger stone, the moonlight's pool, the votive stand. (The render takes the stand-in
  picture out of the bake: on the headset the screen is not under the room.)
- **Sound:** a long stone reverb on the room's own sounds (`acoustics` `stone_nave`, rt60 3); a faint wind high in
  the vault (`wind`, two voices 13 m up, `gain_db` -4, 12 dB lower in the film); now and then a candle's gutter by the
  chancel's stands (`candle`, `every` 120, its `level` on the Candles setting); a tawny owl in the churchyard's trees
  (`tawny_owl`, new, `every` 150, 29 m off to the north, 14 dB lower in the film: a whisper); the bell in the tower
  over the west end (`church_bell` at `pitch` 0.82, deeper than the Athens rooftop's), only by the cues before the
  film and after it. No organ. The film's own `acoustics` section (since 2026-11-09: rt60 2.8, wet 0.85, late 2, the reverb
  9 dB under the direct sound; before, rt60 1.6, wet 0.4, 20 dB under it, inaudible) is live but keeps the film's
  speech clear ("The film's room: the document's `acoustics` section"). Measured (`test_room_nave.gd`, the slider's default): -56.0 dBFS RMS in the pre-show, -76.5 under
  a film at the reference level (before the pass -55.3 and -70.5).
- **To judge on the Frame:** the bake's time and the frame time; the candles' level in the film (20 %, the coronae
  30 %); whether the moonlight reads (cool patches on the north piers and the south aisle's floor, the pools' colour);
  the hymn board's place (it hangs to the right of the picture's view); the owl's and the bell's levels by ear.
