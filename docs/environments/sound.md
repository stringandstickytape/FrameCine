# Sound: the buses, the beds, the acoustics and the music

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each part is.

## The audio buses

```
 Master (the Volume slider)
   Film          the player's sound: the stereo stream and the binaural renderer's mix (spatial_audio.gd)
   Environment   the room: the thud, cue sounds; ducked under Film; the Environment sound slider
     Environment room   sound beds and music, through the room's reverb (acoustics.gd)
   Interface     the pane's and the tools' sounds (the spatial tuning's tones)
```

- **The Environment sound slider** (Sound tab): off to full, default -18 dB under the film. Full is 0 dB on the
  Environment bus: a room's sounds are made at the film's reference level (-20 dBFS RMS), so the default puts them
  18 dB under it. `[audio] environment_db`.
- **The room's offset:** the common `ambience_db` setting adds to it; at -25 the room is muted.
- **Ducking:** a compressor on Environment keyed from Film (the engine's sidechain). It ducks the room by about 8 dB
  under a film at the reference level, by about 15 dB under a loud scene and not at all in silence (measured below).
- **The pause rise:** in the pre-show, while paused, in the intermission and after the end, the Environment bus rises by
  the room's `pause_rise_db` (default 3 dB) over 2 s.
- **The film's analysis** (`film_react.gd`, the music card's bars, an assistant room's loudness glows) listens to
  Film, so a room's own sound never drives them.
- **The level check:** `env_audio.gd measure_level()` plays a room's sounds for a few seconds on the Environment bus
  at the slider's default and measures the bus's RMS (`AudioEffectCapture`). `test_env_audio.gd` holds every room under
  `LEVEL_TARGET_DB` (-38 dBFS, the film's reference minus 18 dB) with 2 dB to spare.

Measured (`test_env_audio.gd`, 2026-11-07, desktop: a 220 Hz tone at -20 dBFS RMS on Environment with the bus at
0 dB, a 1 kHz tone on Film; the compressor's threshold -26 dB, ratio 1.75, attack 20 ms, release 300 ms):

| Film | Environment out | Ducked by |
|---|---|---|
| silent | -20.0 dBFS | 0 dB |
| -20 dBFS RMS (the reference) | -27.1 dBFS | 7.1 dB |
| -6 dBFS RMS (loud) | -39.3 dBFS | 19.3 dB |
| stopped again (after 1 s) | -20.1 dBFS | 0 dB |

The engine's compressor reduces by about 2.08 x (the sidechain's peak over the threshold) x (1 - 1 / ratio), much
more than its ratio suggests; the settings were chosen from these tones. The test holds the reference duck between 5
and 12 dB. The cinema's sounds (its chime) measure -46.2 dBFS RMS at the slider's default, under the -38 dBFS target.

## Sound and music

Three systems: `sound_bed` and `acoustics` (kind `sound`) and `music`. Every sound is our own, made by
`scripts/env/env_synth.gd` from noise, oscillators and filters. No samples are bundled. Nothing is drawn, so the
film layer does not matter here. The film must always win: every sound plays on the Environment bus, sits at a
designed level far under the film, sits lower again while the film plays, and is ducked under the film.

### The room's bus

`sound_bed` and `music` play on the bus "Environment room". It sends to Environment, so the ducking, the Environment
sound slider and the room's Ambience all act on it. `acoustics` puts a reverb on it. Without `acoustics` it is dry.
Cue sounds (`env_audio.play`, the chime) and the thud still go straight to Environment, dry, as before.

### `sound_bed`

`scripts/env/systems/sound_bed.gd`. One sound per system, each with its own id. A room has as many as it needs.

| Param | Default | What |
|---|---|---|
| `sound` | `silence` | loops: `projector`, `wall_rumble`, `cicadas`, `radiator`, `rain_glass`, `rain_leaves`, `gas_hiss`, `noise`, `crickets`, `fire`, `drips`, `wind`, `hum`, `deep_hum`, `fountain`, `clock`, `tube_whine`, `bubbles`, `city`, `boat_engine`, `water_lap`; one-shots: `moped`, `train`, `huskies`, `hull_creak`, `rumble`, `tick`, `creak`, `whale`, `chime`, `gong`, `bird`, `purr`, `three_bells`, `candle`, `ice_creak`, `vcr`, `tape_load`, `sonar`, `church_bell`, `tawny_owl`, `hooves`; `silence` plays nothing (the sounds: below) |
| `gain_db` | 0 | dB from the designed level (-30 to +6) |
| `level` | 1 | 0 to 1, live. Bind it: `film.bass` for a rumble through the wall, `weather.rain` or `weather.wet` for rain, a setting |
| `film_db` | -8 | dB lower in `starting`, `playing` and `credits`. Up again in the pre-show, paused, the intermission and the end |
| `fade` | 3 | seconds a change of state takes |
| `place` | `everywhere` | `everywhere` (no direction), `at` (one place), `around` (`voices` places on a circle of `radius` round `at`, each at another point in the loop) |
| `at`, `to`, `reach` | | where; a one-shot with `to` travels there over its length (a moped passing); metres at full level |
| `every`, `jitter` | 0, 0.3 | a one-shot comes back every so many seconds (a far train); 0: only when a cue plays it |
| `pitch`, `vary` | 1, 0.05 | playback pitch; a one-shot's pitch varies each time |

Actions: `play` (a one-shot now), `stop` and `start` (fade the bed out and in). Rain reads the weather only through
the `weather.rain` and `weather.wet` channels, by a binding.

Streams are made on a worker thread the first time, then cached (0.03 to 0.5 s each on a desktop; the train 1.1 s).
A cue that plays a new one-shot with `env_audio.play` makes it on the main thread: use a `sound_bed` with `every`
or its `play` action for the long one-shots.

#### The sounds

All made by `env_synth.gd` from noise, tones and filters. None copies a real sound, jingle or call. Every loop's
tones and swells divide its length, so it has no seam.

| Sound | Loop or one-shot (s) | What it is | For |
|---|---|---|---|
| `projector` | loop 4 | the claw's pull-down 24 times a second, the shutter's whir, the motor's hum | a booth behind |
| `wall_rumble` | loop 8 | low noise and two low tones that swell; bind `level` to `film.bass` | the next screen through a wall |
| `cicadas` | loop 6 | three buzzing voices that swell in turn | a warm night |
| `crickets` | loop 6 | four field crickets, each at its own pitch and steady rate | a summer night, a drive-in |
| `radiator` | loop 16 | metal ticks at odd moments, water trickling | a bedroom, a sitting room |
| `rain_glass` | loop 6 | drops on a pane, now and then a big one, the rain beyond | a window; `level` on `weather.rain` |
| `rain_leaves` | loop 6 | a dense patter on leaves, drips from above | open roofs; `level` on `weather.rain`. For rain on boards, try `pitch` 0.7 |
| `drips` | loop 8 | drops into puddles at odd moments, two steady leaks | after rain; `level` on `weather.wet` |
| `wind` | loop 12 | a broad band that drifts with the gusts, a faint low roar, a thin whistle in the strongest gusts | a clerestory, a doorway, a night wind |
| `fire` | loop 8 | the flames' soft roar and flicker, small crackles, now and then a pop | a wood or coal fire |
| `gas_hiss` | loop 4 | a gas lamp's hiss and a soft roar | gas light |
| `hum` | loop 4 | a motor's hum through glass: the mains' hum, the motor's turning, water in a pipe | a pool's filter pump, a fridge |
| `deep_hum` | loop 8 | low tones beating slowly, with harmonics small speakers can play, low noise, a slow swell | the deep, on a hull |
| `fountain` | loop 6 | many small bubbles over the soft splash of falling water | a courtyard's fountain |
| `clock` | loop 4 | a tick and a slightly duller, slightly early tock each second, through a wooden case | a mantel, a shelf |
| `tube_whine` | loop 2 | a picture tube's line whine at 15 625 Hz and its valves' faint hum. `pitch` 0.648: a 405-line set's 10 125 Hz; 1.007: 15 734 Hz | a CRT telly, very low |
| `noise` | loop 4 | pink noise | under other beds |
| `bubbles` | loop 6 | a vent's bubbles in deep water: bursts of low bubbles (tones that rise as they ring) between quiet spells, the water's soft hiss (since 2026-11-08) | a vent outside the glass |
| `sonar` | one-shot 3 | a sonar's ping: a soft round tone at 1.18 kHz with a faint beat, swelling in over 15 ms and ringing down, a lower octave under it, and 1.25 s later its echo off the sea floor, duller and a third as loud (since 2026-11-08) | a bathysphere's pre-show (a cue's `do`); a cue sound too |
| `moped` | one-shot 8 | a small two-stroke passing, 15 m away at its closest; with `to` it travels | a street below |
| `far_car` | one-shot 34 | a big old car on a highway 78 m off at its closest, 25 m/s: tyres on concrete (the slabs' joints a soft double knock), a V8's low, uneven burble, its pitch riding the passing, duller when far; the level by distance is the 3D player's (`reach` the closest distance), only the far ends fade in it (since 2026-11-08; designed level -56) | the drive-in's highway, with `to` and a cue (`far_car.play` with `car_passes`) |
| `hooves` | one-shot 16 | a horse and cart passing on setts: a walk's four-beat iron knocks on stone (each ringing a little in the stones and the shoes), the iron tyres' rumble with a bump at each joint, the harness's small tinks, fading in and out at the ends; with `to` it travels (since 2026-11-08; designed level -56) | Shopfront 1906's street, with `to` and the `cart` cue |
| `train` | one-shot 40 | a freight train far off: the roll, the rail joints, the horn's two notes early on | far off, `every` |
| `huskies` | one-shot 7 | three far howls and a few yips, an echo | snow |
| `scops_owl` | one-shot 9 | a scops owl's call over the roofs: four soft whistled "tew"s 2.5 s apart, each gliding down from 1.25 to 1.17 kHz, a breath of air, softened by distance (since 2026-11-08) | a warm night, `every` |
| `tawny_owl` | one-shot 7 | a tawny owl in the trees round a church: a hollow "hooo" sliding down from about 420 Hz, a pause, a short "hu", then a long wavering "hoo-oo-oo-oo" (the voice trembling about eight times a second), a breath of air, softened by distance (since 2026-11-08; designed level -58) | a churchyard at night, `every`, far off |
| `hull_creak` | one-shot 3.5 | steel under pressure: stick-slip pulses through a low groan and bright partials | a hull |
| `church_bell` | one-shot 14 | a parish church's bell across the roofs: three strokes 3.2 s apart, each a struck bell's partials (hum, prime, minor third, fifth, octave; damped oscillators, the hum ringing longest), a faint echo off the houses, softened by distance (since 2026-11-08) | before the show (a cue's `do`), far off |
| `city` | loop 12 | a summer city at night from a roof: a low murmur of traffic that swells and settles, a faint hiss, three far engines passing in the loop (since 2026-11-08) | round a roof, from the streets below |
| `boat_engine` | loop 8 | a narrowboat's slow single-cylinder diesel under the stern deck, through a bulkhead: four beats a second, each a 58 Hz thump with its octave and a short knock of the block at 420 Hz, each a little stronger or weaker (32 strengths in the loop); a 29 Hz drone and a low rumble under it; all of it under 600 Hz (since 2026-11-09; designed level -52) | the Narrowboat, astern; `level` on `journey.speed` |
| `water_lap` | loop 12 | water against a steel hull, slow and uneven: a lap every 0.9 to 2.2 s, a band of noise that swells in over 0.15 s and dies away as it falls from 900 to 500 Hz, a drop after every second lap, a soft wash between 250 and 1200 Hz all the time (since 2026-11-09; designed level -57) | a boat's hull |
| `ice_creak` | one-shot 2.6 | a crack that sings down, then a low groan | ice, `every` |
| `candle` | one-shot 0.9 | a candle's flame puffs and wavers, three or four sputters of wax | `every`, very low |
| `three_bells` | one-shot 3.2 | a soft house bell: three struck-bar tones, up a fifth, down a minor third (our own call) | before the show |
| `vcr` | one-shot 4.5 | a video recorder takes a tape: the clunk, the motor threading the tape with its clicks, the heads engaging, the drum's whirr | a cue: the tape goes in |
| `tape_load` | one-shot 8 | a home computer loads from cassette: a pilot tone, a gap, the data's two-tone warble, the tape's hiss | a cue, very low |
| `switch_clunk` | one-shot 0.6 | a telly's power switch: the toggle's snap, the contacts' bounce, the cabinet's knock, the speaker's soft thump | the presentation's `switch_on` and `switch_off` |
| `valve_hum` | one-shot 8 | a valve set warming up: the transformer's hum and a little buzz and the speaker's rush rising over five seconds, settling and fading | a valve set's `switch_on` |
| `crt_off` | one-shot 1.4 | a tube switched off: a soft thunk, a tiny tick, the glass's static crackling faintly | a tube's `switch_off`, very low |
| `channel_clunk` | one-shot 0.45 | a rotary channel knob: the detent's ratchet, the spring's snap into the notch, a knock through the cabinet | the presentation's `channel` |
| `bird`, `purr`, `whale` | one-shot 1.2, 4, 5 | a songbird's call, a cat's purr (two breaths), a whale's song | ambient life's calls (below) |
| `chime`, `gong`, `rumble`, `tick`, `creak` | one-shot | the foundation's sounds | cues |

Cue sounds (`EnvDoc.SOUNDS`, for a cue's `sound` step and ambient life's calls): the foundation's seven, `moped`,
`train`, `huskies`, `hull_creak`, `bird`, `purr`, `three_bells`, `candle`, `ice_creak`, `switch_clunk`, `crt_off`,
`channel_clunk`, `sonar` (not `valve_hum`: 8 s, too long to make on the main thread). A cue's `sound` step plays at
the reference level less its `gain_db`: at 0 dB it reaches the level check's target, so give it -10 or lower. A
`sound_bed` with `play` is the levelled way: it plays at the sound's designed level.

### `acoustics`

`scripts/env/systems/acoustics.gd`. The room's sound character, a reverb on the room's bus.

| Preset | rt60 (s) | damping | wet | predelay (ms) | echo |
|---|---|---|---|---|---|
| `neutral` | 0.3 | 0.6 | 0 (dry) | 20 | 0 |
| `small_room` | 0.35 | 0.7 | 0.12 | 20 | 0 |
| `cinema` | 0.7 | 0.6 | 0.18 | 25 | 0 |
| `shopfront` (pressed tin) | 0.9 | 0.3 | 0.25 | 20 | 0 |
| `concrete_hall` | 2.4 | 0.25 | 0.32 | 60 | 0.35 |
| `stone_nave` | 5.0 | 0.45 | 0.4 | 80 | 0.1 |
| `ice` | 1.1 | 0.1 | 0.25 | 20 | 0 |
| `hull` | 1.4 | 0.2 | 0.3 | 20 | 0.15 |
| `vehicle` | 0.15 | 0.85 | 0.06 | 20 | 0 |
| `outdoors` | 0.2 | 0.5 | 0.04 | 90 | 0 |
| `vacuum` | 0.05 | 1 | 0 (dry) | 20 | 0 |

`rt60`, `damping`, `wet`, `predelay_ms` and `echo` are live; -1 takes the preset's. The engine's reverb is
measured: `TAIL_SECONDS` holds its tail at each room size, and `room_size_for()` picks the size for an rt60. Its
tail is never shorter than about 0.5 s or longer than about 6 s. The short presets use its smallest room with a
little wet.

**The film keeps its own mix.** `film` is off by default. Only with `film` on does `sound_room()` give spatial audio
(`scripts/play/spatial_audio.gd`) the room's rt60, its `film_wet` and its walls' `reflect`, so the film's speakers
ring in the room too. The binaural renderer's code is not changed. The document's own `acoustics` section still goes
over it.

### The film's room: the document's `acoustics` section

Spatial audio (`scripts/play/spatial_audio.gd`, D23) renders the film's speakers in a room: first-order reflections
off the six walls of a box and an 8-line FDN for the late reverb. Each frame it asks the room for
`get_sound_room()` and gives `BinauralRenderer.set_room()` a new room when it differs, so a room's acoustics reach
the renderer when the room loads, when the viewer changes room, and when a setting rebuilds the room. For a room
document, `get_sound_room()` is `env_host.gd sound_room()`: the builders' `sound_room()` (their walls: `box`, and the
speaker layout's `surround_height`, `array`, `array_spacing`), an `acoustics` system's with `film` on, then the
document's `acoustics` section over them. A scene room (`dim_room`, `home_theatre`, `drive_in`, `planetarium`,
`dome`, `passthrough`) gives a constant from its script. Without a room spatial audio uses `STANDARD_ROOM`.

| Key | What reaches the renderer |
|---|---|
| `box` | the walls, the room's frame (default: the builder's). Sizes the reflections' delays, the FDN's delay lines and its predelay (the mean free path) |
| `reflect` | six walls: left, right, floor, ceiling, front (the screen's), back; 0..1 each (default 0.4). A reflection's gain is reflect x wet x direct distance / its path |
| `rt60` | the late reverb's decay (s) |
| `wet` | the room's level: the reflections and the late reverb together; times the viewer's reverb amount (Settings) |
| `late` | the late reverb against the reflections, 0..2 (default 0.5, the renderer's own; since 2026-11-09) |

**The renderer keeps the late reverb's energy the same whatever its rt60** (the FDN is normalised), and that energy is
about (wet x late)² / 8 of the direct sound's (measured about 4 dB lower again, through the HRTF and the lines'
damping). So a longer rt60 alone spreads the same reverb thinner, and `late` is what makes a live room louder. Until
2026-11-09 every room left `late` at 0.5 and kept `wet` at 0.1 to 0.55: every cinema's reverb was 16 to 25 dB under
the direct sound, inaudible, and the rooms sounded alike. Now each room's values come from what it is:

- **The box** is the builder's walls, the room's real size (the Void's is the standard room's, written out, with
  its speakers still on the standard 2.5 m ring: `ring`, `distance`).
- **rt60** by type, checked against the box: Sabine's mean absorption 0.161 V / (S rt60) must be a real one (0.05 to
  0.75; `tests/test_room_acoustics.gd`). A 9 800 m³ hall can't be 0.45 s, so the flagship is 0.8 s.
- **wet and late** for a reverb level that suits the room, from about 9 dB under the direct sound (the nave) to 40 dB
  and more under it (open air). The liveliest room's wet stays at 0.85, so the film's speech stays clear.
- **reflect** from the walls' materials: plaster, stone, concrete, ice and glass high; felt, carpet, seats and an
  open sky low.

Measured by `tests/test_room_acoustics.gd` (an impulse from the picture's centre to the seat through the renderer
with Listener H5; R/D: the reverb and reflections against the direct sound; T20: the decay measured):

| Room | rt60 (s) | wet | late | reflect (L, R, floor, ceiling, front, back) | R/D (dB) | T20 (s) |
|---|---|---|---|---|---|---|
| Nave | 2.8 | 0.85 | 2.0 | 0.45 0.45 0.35 0.4 0.4 0.45 | -9.0 | 2.24 |
| Palace of Culture 1974 (board-marked concrete, an echo between its side walls) | 1.9 | 0.7 | 1.9 | 0.65 0.65 0.2 0.25 0.45 0.3 | -10.8 | 1.49 |
| Bathysphere (steel and glass) | 1.2 | 0.6 | 1.8 | 0.55 0.55 0.3 0.6 0.55 0.55 | -11.2 | 0.94 |
| Atmospheric 1928 (plaster courtyard, a sky for a ceiling) | 1.4 | 0.7 | 1.9 | 0.45 0.45 0.15 0.08 0.3 0.35 | -11.8 | 1.13 |
| Crater (a glass dome) | 1.6 | 0.65 | 1.95 | 0.4 0.4 0.15 0.5 0.4 0.4 | -12.0 | 1.32 |
| Pink Palace (a plaster shell, mirrors) | 1.25 | 0.6 | 1.9 | 0.45 0.45 0.2 0.5 0.25 0.25 | -12.0 | 1.00 |
| Ice cinema (ice blocks, hides) | 0.9 | 0.6 | 1.6 | 0.6 0.6 0.25 0.6 0.5 0.4 | -12.3 | 0.68 |
| Shopfront 1906 (a narrow tin box) | 0.8 | 0.6 | 1.6 | 0.45 0.45 0.35 0.6 0.3 0.4 | -12.4 | 0.62 |
| Streamline 1937 (plaster coves, faience) | 1.1 | 0.6 | 1.8 | 0.4 0.4 0.2 0.35 0.2 0.3 | -13.4 | 0.89 |
| Cinema (the converted cinema) | 0.8 | 0.5 | 1.8 | 0.35 0.35 0.15 0.2 0.2 0.3 | -16.0 | 0.65 |
| Screen 3, 1983 (plasterboard, carpet, foam) | 0.6 | 0.45 | 1.7 | 0.4 0.4 0.15 0.15 0.25 0.35 | -16.8 | 0.48 |
| TV tomorrow (a bare room) | 0.7 | 0.42 | 1.7 | 0.5 0.5 0.35 0.45 0.35 0.45 | -17.1 | 0.55 |
| Reclaimed (half its roof gone) | 0.65 | 0.4 | 1.45 | 0.4 0.4 0.2 0.12 0.35 0.25 | -18.7 | 0.53 |
| Screening room 1962 (walnut, carpet, the window on the left) | 0.4 | 0.35 | 1.3 | 0.5 0.3 0.15 0.3 0.2 0.3 | -19.4 | 0.31 |
| TV rooms 1930 to today | 0.35 to 0.55 | 0.34 to 0.36 | 1.4 to 1.65 | as before | -20 to -22 | 0.29 to 0.45 |
| Flagship (felt, baffles, recliners) | 0.8 | 0.32 | 1.55 | 0.12 0.12 0.15 0.1 0.15 0.1 | -22.7 | 0.66 |
| Pillow Fort 1993 (cushions) | 0.25 | 0.25 | 0.9 | 0.15 0.15 0.15 0.1 0.2 0.15 | -29.0 | 0.22 |
| Rooftop, Athens (open air, a slap off the blind wall) | 0.2 | 0.15 | 0.6 | 0.05 0.05 0.3 0 0.45 0.05 | -42.5 | 0.17 |
| Drive-in 1958 (open air) | 0.15 | 0.12 | 0.5 | 0.02 0.02 0.25 0 0.3 0.02 | -57.3 | 0.18 |
| Void (unchanged) | 0.35 | 0.25 | 0.5 | 0.4 each | -27.7 | 0.23 |

The scene rooms keep their own (late 0.5): Dim room -15.8 dB, Planetarium -16.9, Home theatre -20.1, the car at the
drive-in -22.7 (its reflections arrive within 3 ms: a colour more than a reverb), Passthrough -22.5, Dome -42.3. The
room's own sounds (`sound_bed`, `music`) take the `acoustics` system's reverb, a separate one on the Environment
room bus; `film` there is still off in every room.

### `music`

`scripts/env/systems/music.gd`. An instrument that plays itself. No player is shown: the keys move by themselves.
`held_notes()` gives the notes held down now (MIDI numbers) and `sounding()` whether it plays: a drawn instrument shows
them (since 2026-11-08: Shopfront 1906's player piano, its keys going down with the notes and its roll turning).
It writes its own music as it goes, from the room's seed: a key, two common chord progressions, the form A A2 B A,
and a tune of its own from short rhythms. Never a melody we don't own.

- **`piano`**: a player piano for silent films. The left hand plays oom-pah, the right hand the tune. Each note is two
  slightly detuned strings (`detune_cents`, an upright's honky-tonk). It plays in `starting`, `playing` and
  `credits`, and starts its piece again when the film starts from its start. `drive` (bind it to `film.transient`
  with a `range` such as [0.3, 1]) makes it faster; over 0.65 it plays an agitato (tremolo on a diminished chord)
  until the film calms; under 0.12 it plays sparse.
- **`organ`**: slow chords in four voices, held across bars, with passing notes and a tremulant. Its stops are
  `flute`, `principal`, `full` and `theatre`. It plays in the pre-show, the intermission and the end. `flourish`
  plays a closing cadence and then rests.

Params: `instrument`, `on` (live; bind it to a setting), `gain_db`, `level`, `drive`, `plays_in` (empty: its own
states), `film_db` (-6), `tempo` (0: piano 104, organ 56), `seed`, `mode` (major or minor), `stop`, `tremulant`,
`detune_cents`, `at`, `reach`. Actions: `play` (args: seconds), `stop` (args: seconds to fade), `flourish`. Twelve
voices. The notes are made on a worker thread (the piano's 17 in 0.8 s, the organ's 66 in about 0.4 s on a desktop).

### Levels

Measured (`test_env_sound_bed.gd`, `test_env_music.gd`, 2026-11-07, desktop, headless) on Environment at the
slider's default, in dBFS RMS. The film's reference is -20; the level check's target is -38. "In film" is with
`film_db`; "under a film" adds a 1 kHz tone on Film at the reference level (the duck). A one-shot is its loudest
second.

| Sound | Designed | Alone | In film | Under a film | Peak |
|---|---|---|---|---|---|
| `projector` | -51 | -51.0 | -59.0 | -66.1 | -29.7 |
| `wall_rumble` | -50 | -50.0 | -57.4 | -65.8 | -36.9 |
| `cicadas` | -54 | -53.9 | -61.5 | -70.7 | -33.0 |
| `crickets` | -55 | -55.1 | -62.9 | -70.4 | -36.9 |
| `radiator` | -55 | -55.0 | -62.3 | -73.3 | -21.4 |
| `rain_glass` | -52 | -52.0 | -60.1 | -67.1 | -26.2 |
| `rain_leaves` | -52 | -52.0 | -59.9 | -67.1 | -31.0 |
| `drips` | -56 | -56.0 | -63.3 | -71.8 | -33.6 |
| `wind` | -55 | -55.0 | -65.3 | -72.1 | -39.0 |
| `fire` | -54 | -54.0 | -62.2 | -69.0 | -28.5 |
| `gas_hiss` | -58 | -58.0 | -66.0 | -73.1 | -48.5 |
| `hum` | -58 | -58.0 | -66.0 | -73.1 | -47.7 |
| `deep_hum` | -54 | -54.0 | -63.1 | -68.4 | -41.0 |
| `fountain` | -56 | -56.0 | -64.2 | -71.1 | -41.8 |
| `bubbles` (2026-11-08) | -57 | -57.0 | -64.7 | -72.4 | -36.2 |
| `city` (2026-11-08) | -58 | -58.0 | -66.6 | -73.6 | -45.3 |
| `boat_engine` (2026-11-09) | -52 | -52.0 | -60.0 | -67.1 | -37.0 |
| `water_lap` (2026-11-09) | -57 | -57.0 | -64.1 | -73.6 | -35.4 |
| `clock` | -56 | -56.0 | -64.0 | -71.1 | -19.9 |
| `tube_whine` | -62 | -62.0 | -70.0 | -77.2 | -55.0 |
| `noise` | -54 | -54.0 | -62.0 | -69.1 | -41.2 |
| `sonar` (2026-11-08) | -56 | -56.0 | -64.0 | | -39.7 |
| `moped` | -52 | -52.0 | -60.0 | | -42.9 |
| `train` | -52 | -52.0 | -60.0 | | -40.6 |
| `huskies` | -54 | -54.0 | -62.0 | | -46.0 |
| `scops_owl` (2026-11-08) | -58 | -58.0 | -66.0 | | -41.2 |
| `church_bell` (2026-11-08) | -54 | -54.0 | -62.0 | | -42.5 |
| `hooves` (2026-11-08) | -56 | -56.0 | -64.0 | | -35.7 |
| `hull_creak` | -52 | -52.0 | -60.0 | | -39.3 |
| `ice_creak` | -55 | -55.0 | -63.0 | | -31.0 |
| `candle` | -58 | -58.0 | -66.0 | | -37.5 |
| `three_bells` | -50 | -50.0 | -58.0 | | -40.1 |
| `vcr` | -54 | -54.0 | -62.0 | | -41.3 |
| `tape_load` | -58 | -58.0 | -66.0 | | -56.5 |
| `switch_clunk`, `channel_clunk` | -54, -55 | -54.0, -55.0 | -62.0, -63.0 | | -26.4, -25.5 |
| `valve_hum`, `crt_off` | -58, -60 | -58.0, -60.0 | -66.0, -68.0 | | -49.7, -33.7 |
| `rumble`, `gong`, `whale` | -52 | -52.0 | -60.0 | | -41.6, -41.4, -48.4 |
| `tick`, `creak` | -55, -54 | -55.0, -54.0 | -63.0, -62.0 | | -25.4, -35.4 |
| `chime` | -50 | -50.0 | -58.0 | | -40.1 |
| `bird`, `purr` | -54, -56 | -54.0, -56.0 | -62.0, -64.0 | | -40.7, -38.8 |
| `piano` | -51 | -51.0 | -57.0 | -63.9 | -37.6 |
| `organ` | -52 | -52.0 | -56.6 | -62.8 | -35.3 |

Every bed and instrument sits 29 dB or more under the film's reference on its own, and 42 dB or more under it with a
film playing. The test room with its beds at once (the projector, rain on glass, the wall's rumble, ticks, a moped and
a train) measures -47.1 in the pre-show, 9 dB under the target. The peaks that look high (the clock's and the
radiator's ticks, the fire's crackles, the rain's drops) are short clicks; their RMS is low. A one-shot's "in film" is
its designed level less `film_db`, and the duck takes it lower again under a loud scene.

Measured tails (`test_env_acoustics.gd`, a tick through the room's bus, wet only, T30): cinema 0.71 s (set 0.7),
shopfront 0.88 (0.9), concrete hall 2.41 (2.4), stone nave 4.66 (5.0), ice 1.09 (1.1), hull 1.40 (1.4); the
short presets 0.52 to 0.56 (the engine's shortest).

### Ambient life's calls

`life` plays a creature's call through the host (`play_sound`, then `env_audio.play`) at its `voice_db` (default
-12) on Environment, dry: a 3D player with a unit size of 3 m (full level within 3 m, then down 6 dB each time the
distance doubles) and the engine's distance filter (it dulls the highs). `bird` (three falling whistles and a trill,
1.2 s) and `purr` (a pulse about 25 times a second through a low throat, two breaths, 4 s) are in `EnvDoc.SOUNDS`,
so the birds' calls and the cat's purr sound with no change to `life`. Each is made the first time it plays (about
0.05 to 0.1 s on a desktop).

Measured as `life` plays them (`test_env_sound_bed.gd`, 2026-11-07), the loudest second at the slider's default,
in dBFS. "Designed" is the sound's level in `sound_bed`; a call in the film should sit near its "in film" level.

| Call | `voice_db` | Distance | Heard | Designed | In film |
|---|---|---|---|---|---|
| `bird` | -12 | 3 m | -68.5 | -54 | -62 |
| `bird` | -12 | 8 m (a roof's edge) | -81.0 | -54 | -62 |
| `bird`, no distance filter | -12 | 3 m, 8 m | -58.9, -67.4 | -54 | -62 |
| `purr` | -12 | 1.5 m, 4 m | -53.5, -62.0 | -56 | -64 |
| `whale` | -12 | 3 m | -51.2 | -52 | -60 |
| `whale` | -12 | 22 m (the Bathysphere's song) | -68.4 | -52 | -60 |
| `whale` | -14 (the Bathysphere's now) | 22 m | -70.4 | -52 | -60 |
| `whale` | -6, -4 | 22 m | -62.4, -60.4 | -52 | -60 |

The whale sings only in a quiet scene of the film, about 22 m away in the Bathysphere. At -12 it arrives 8 dB under
its "in film" level, at the room's -14 10 dB under. Give the Bathysphere's whale `voice_db` -4: it then sits at
-60, 40 dB under the film's reference and 22 dB under the target. (The level check in `test_env_life.gd`, -53.8 at
-12, measures the stream's first 1.5 s with no distance.) The cat by the seat is 2.5 dB over its designed level at
-12; a cat that sits within 2 m takes -15. The birds lose about 10 dB to the engine's distance filter (they are high);
at 8 m they are 19 dB under their "in film" level even at -12. Without the filter (`attenuation_filter_db` 0 in
`env_audio.play`, as `sound_bed` and `music` have it) a bird at 8 m at `voice_db` -6 arrives at about -61.

### For the rooms

| Room | Use |
|---|---|
| Shopfront 1906 | `acoustics` `shopfront`; `sound_bed` `projector` in the booth behind, `gas_hiss`, `hooves` (the cart's cue); `music` `piano` at the drawn piano, `drive` on `film.transient`, `on` on a setting |
| Streamline 1937 | `acoustics` `cinema`; `music` `organ`, `flourish` in the ritual |
| Pink Palace | `acoustics` `cinema`; `sound_bed` `three_bells` (`play` in the ritual) or the foundation's `chime` |
| Atmospheric 1928 | `acoustics` `cinema`; `sound_bed` `fountain` `at` the wall fountain, `reach` 8, `gain_db` -4; `crickets` around the courtyard (three voices, `film_db` -18); a `scops_owl` from the stone pine, `every` 55, `film_db` -40; the theatre organ (`music`) before the film |
| Screen 3, 1983 | `acoustics` `small_room` (`rt60` 0.6); `sound_bed` `wall_rumble`, `level` on `film.bass`, `film_db` 0 |
| Drive-in | `acoustics` `outdoors`; `sound_bed` `crickets` around (`radius` 8); `train` far off, `every` 900, `reach` 300 (its horn is in it) |
| Rooftop, Athens | `acoustics` `outdoors` (`rt60` 0.25, `wet` 0.15); `sound_bed` `cicadas` around, `film_db` -14 (they fade as the film starts); `city` around from 6 m below, `gain_db` -2, `film_db` -10; `moped` with `to` and `every`; `church_bell` at the church, `film_db` -30, played by the pre-show's cue; the cat's purr from `life` (`voice_db` -15 within 2 m) |
| Palace of Culture | `acoustics` `concrete_hall`; `sound_bed` `three_bells` before the show |
| Nave | `acoustics` `stone_nave` (`rt60` 3); `sound_bed` `wind` high up, `gain_db` -4; `candle`, `every` 120, `gain_db` -4. No organ, no bells |
| Reclaimed | `acoustics` `outdoors`; `sound_bed` `rain_leaves` around, `level` on `weather.rain`; `drips`, `level` on `weather.wet`; `wind`, `gain_db` -6; the birds' calls from `life` |
| Ice cinema | `acoustics` `ice`; `sound_bed` `huskies`, `every` 300; `wind` by the doorway; `ice_creak`, `every` 240 |
| Bathysphere | `acoustics` `hull` (`rt60` 0.9); `sound_bed` `hull_creak`, `every` 180, to either side; `deep_hum`, `gain_db` -4; `bubbles` at the vent outside; `sonar` pinging in the pre-show (a cue); a far `whale` song in a quiet scene (a cue); the passing whale from `life` at `voice_db` -4 |
| Pillow Fort | `acoustics` `small_room` (`rt60` 0.3); `sound_bed` `radiator`, `rain_glass` on `weather.rain` |
| Screening room 1962 | `acoustics` `small_room` (`rt60` 0.45); `sound_bed` `fire` at the hearth; `hum` at the window (the pool's pump); `three_bells` before the ritual |
| Crater | `sound_bed` `silence`; `acoustics` `vacuum` |
| TV 1930 | `acoustics` `small_room`; `sound_bed` `clock`; `hum`, `gain_db` -4 (the disc's motor). No `tube_whine`: thirty lines on a spinning disc, no tube |
| TV 1953 | `acoustics` `small_room`; `sound_bed` `fire` at the grate (on the Fire setting); `clock`; `rain_glass` on `weather.rain`; `tube_whine` `pitch` 0.648, `gain_db` -4; the cat's purr from `life` |
| TV 1972 | `acoustics` `small_room`; `sound_bed` `radiator`; `clock`; `tube_whine` |
| TV 1983 | `acoustics` `small_room`; `sound_bed` `rain_glass` on `weather.rain`; `tape_load` (`play` in the pre-show: the computer loads); `tube_whine` |
| TV 1987 | `acoustics` `small_room`; `sound_bed` `vcr` (`play` in `starting`: the tape goes in); `clock`; `tube_whine` |
| TV 1993 | `acoustics` `small_room`; `sound_bed` `radiator`, `rain_glass` on `weather.rain`; `vcr` in `starting`; `tube_whine` |
| TV 2005 | `acoustics` `small_room`; no beds (a flat panel is silent) |
| TV 1937 | `acoustics` `small_room`; `sound_bed` `fire` (on the Fire setting); `clock`; `tube_whine` `pitch` 0.648, `gain_db` -4 |
| TV 1966 | `acoustics` `small_room`; `sound_bed` `radiator`; `clock`; `tube_whine` `pitch` 0.648 |
| TV 2002 | `acoustics` `small_room`; `sound_bed` `hum` at the set (its fan), `gain_db` -3 |
| TV today | `acoustics` `small_room` (`rt60` 0.3); `sound_bed` `rain_glass` on `weather.rain`, `gain_db` -6 |
| TV tomorrow | `acoustics` `small_room` (`rt60` 0.3); no beds: a quiet room |
| Narrowboat | `acoustics` `small_room`; `sound_bed` `boat_engine` astern under the deck (`reach` 3, `film_db` -10, `level` on `journey.speed` from 0.4 to 1); `water_lap` everywhere (`gain_db` -2, `film_db` -10); a `tawny_owl` far off (a cue); a `church_bell` far off as the tower comes by (a cue) |
