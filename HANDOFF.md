# Handoff: agent D (sound and music), environments phase 1

Branch `worktree-agent-aa8ead063c343ee1c`. Brief: the scratchpad's `envfound/phase1_common.md` plus agent D's part
(sound_bed, acoustics, music; take over env_synth.gd). main (with agent B's weather, e3998c3) is merged in.

## Done

- `app/scripts/env/env_synth.gd`: the seven old sounds are made exactly as before (checked byte for byte against
  the old file: the cinema's chime is unchanged). New sounds, all synthesised: beds that loop without a seam
  (`projector`, `wall_rumble`, `cicadas`, `radiator`, `rain_glass`, `rain_leaves`, `gas_hiss`) and one-shots
  (`moped`, `train`, `huskies`, `hull_creak`). `make()` is safe on a worker thread; `stream()` caches;
  `level_db()` (a loop's RMS, a one-shot's loudest second), `loudest_db()`, `peak_db()`. Instruments:
  `make_piano_note(base, detune)` (wavetables, two detuned strings, double decay, every 4 semitones from 33 to 97,
  pitch_scale for the rest) and `make_organ_note(midi, stop)` (additive stops flute, principal, full, theatre;
  a chiff; a looped steady part of whole cycles; `organ_pitch_scale()` puts the pitch right). Note cache:
  `piano_key/organ_key/note/put_note`. Desktop times: train 1.1 s, others 0.03-0.5 s, all 17 piano notes 0.8 s,
  48 organ notes 0.27 s.
- `env_doc.gd SOUNDS`: added `moped`, `train`, `huskies`, `hull_creak` (cue-playable). Additive only.
- `registry.gd`: `sound_bed`, `acoustics`, `music` (after atmosphere and weather).
- `systems/acoustics.gd`: makes the bus "Environment room" (sends to Environment, so it is ducked and on the
  slider) with an AudioEffectReverb; presets neutral, small_room, cinema, shopfront, concrete_hall, stone_nave,
  ice, hull, vehicle, outdoors, vacuum; live overrides rt60, damping, wet, predelay_ms, echo (-1 = preset's).
  rt60 maps to the engine's room size by the Freeverb comb formula (`room_size_for`). `film` (bool, default
  OFF): only then `sound_room()` gives spatial audio rt60, film_wet and reflect x6, so the film is never coloured
  unless the room asks. The document's own `acoustics` section still overrides it (env_host merges systems first).
- `systems/sound_bed.gd`: one sound per system instance (own id). Params: sound (incl. `silence`), gain_db,
  level (live, bindable: film.bass, weather.rain, a setting), film_db (-8 default, in starting/playing/credits),
  fade, place (everywhere/at/around), at, to (a one-shot travels), radius, voices, reach, every, jitter, pitch,
  vary. Actions play, stop, start. LEVELS: each sound's designed level, dBFS RMS at the slider's default; the
  player volume is set from the stream's measured level so the bed sits there. Streams made on WorkerThreadPool.
- `systems/music.gd`: piano and organ that play themselves; original generated material (key from seed, common
  progressions, form A A2 B A, a tune per bar from rhythm cells); piano oom-pah + tune, drive (bind to
  film.transient) speeds it up and over 0.65 gives an agitato (dim7 tremolo); restarts its piece on entering
  `starting`. Organ: four-voice chords held across bars, passing notes, tremulant, `flourish` cadence; plays in
  preshow, intermission, ended by default. `plays_in`, `on` (bind to a setting), `film_db` -6, actions play,
  stop, flourish. 12 voices from a player pool.
- `app/tests/env_sound_fixture.gd` (build a doc alone with a listener, set states, measure Environment's RMS and
  peak, envelope, a film tone for the duck, the checks) and `app/tests/test_env_sound_bed.gd`.

## Test status

`test_env_sound_bed` last full run (before the weather merge and two fixes): 82 checks, 4 failed:
- `reach` max was 100 (test room's train uses 300): FIXED (max 500).
- cicadas and radiator measured 1.2 s windows: swells and sparse ticks. FIXED in the test: loops measured over
  their whole length (not yet re-run).
- Since then a `leaves` bed bound to `weather.rain` was added to the test room (not yet run).
Measured at the slider's default (dBFS RMS; film reference -20; target -38): pre-show / in film / under a film
at the reference: projector -51.1/-59.2/-65.9, wall_rumble -48.7/-59.6/-62.5, rain_glass -52.0/-59.9/-67.3,
rain_leaves -51.9/-60.2/-66.8, gas_hiss -58.0/-66.1/-73.1, noise -54.1/-61.9/-69.2; one-shots at their
designed loudest second: moped, train, hull_creak, rumble, whale, gong -52; huskies, creak -54; tick -55;
chime -50. The whole test room in the pre-show: -47.4 dBFS (target -38). So every bed sits 30+ dB under the
film's reference before the duck and 45+ dB under it with a film playing.

## Left, in order

1. Re-run `test_env_sound_bed` (script: `wsl -- bash <scratchpad>/envD/run.sh test_env_sound_bed`; it is about
   3-4 minutes because each loop is measured over its whole length three times). Fix what fails.
2. `app/tests/test_env_music.gd`: piano room (acoustics shopfront, music piano at a place, drive bound to
   film.transient smooth 0.5, on bound to a bool setting `piano`): silent in preshow, plays in starting,
   notes_played rises; the A tune repeats (`_tune(1)` == `_tune(25)`); fake film.transient 1 -> tempo up and an
   agitato bar (add a `bar_kind` var in `_write_bar` to test it); setting off -> voices go to 0. Organ room:
   plays in preshow, `flourish`, silent when playing. Levels: measure with `plays_in ["preshow"]` (no film_db),
   then CALIBRATE `NOTE_DB` in music.gd so the measured level is within 1.5 dB of `LEVELS` (-51 piano, -52 organ;
   NOTE_DB -6 / -11 are guesses, not measured). music.gd has NOT been run at all yet: expect parse errors.
3. `app/tests/test_env_acoustics.gd`: bus made and sending to Environment; presets valid; reverb params follow
   live changes; `film` off -> no rt60 from the system in host.sound_room(); on (via a setting map) -> rt60,
   wet, reflect; the doc's acoustics wins; room freed -> reverb disabled; Film bus untouched. Measure each
   preset's tail with a `tick` through the bus (Fixture.envelope) and report T30-based rt60 against the preset.
4. Docs: a "Sound and music" section in `docs/environments.md` (the three systems, LEVELS table, the bus, the
   film setting off by default, weather binding), mark the sound_bed/acoustics/music rows "built", add the
   "Environment room" bus to "The audio buses" diagram. Plain short sentences.
5. Run `tools/i18n.py extract` then `check` (no new user-facing words expected: system descriptions are not
   translated). Then the brief's test list: test_env_registry, test_environments, test_env_checks,
   test_cinema (lavapipe), test_rooms, test_i18n, test_assistant_coverage_system/_files, test_features, and
   test_env_audio (its "every synthesised sound at the reference level" now covers the new NAMES; they pass
   by construction: whole-length RMS <= -20).
6. Privacy check, commit with explicit paths, report.

## Decisions and why

- One sound per sound_bed instance: bindings work only on top-level params, so a list of beds could not follow
  film.bass or weather.rain.
- Weather is read ONLY through B's channels (`weather.rain`, `weather.wet`) by a binding; no method calls on
  B's system (agreed with agent B by message).
- A sub-bus for the room's reverb rather than an effect on Environment: the thud already has its own binaural
  room reverb and must not get it twice. Cue sounds (`env_audio.play`, the chime) still go straight to
  Environment, dry: unchanged behaviour.
- The film takes the room's reverb only with `acoustics.film` on, default off (the brief's rule).
- Levels are "designed levels" measured at the slider's default, 12 dB+ under the -38 target, so a room with
  two or three beds and a piano still passes; film_db lowers beds while the film plays, on top of the duck.
- Streams and notes are made on worker threads; `finish_loading()` on each system waits (tests). A cue that
  plays a new one-shot (`train`) synchronously via env_audio.play makes it on the main thread once (about 1 s
  on a desktop, more on the headset): prefer sound_bed `every`/`play` for long one-shots. Worth saying to the lead.
- No host hook was added; no foundation file was edited (env_doc.gd SOUNDS and registry.gd are additive).
- Nothing is drawn by these systems, so the film layer (composition layer) question does not arise.

## Gotchas

- Run WSL via the PowerShell tool (`wsl -- bash <script>`); the Bash tool refuses `wsl` from a worktree agent.
- No python on Windows; use the Edit tool (or WSL python3) for edits.
- GDScript: multi-line lambdas inside call arguments fail to parse here; use loops. Untyped `:=` from a Node's
  method result fails: give the type.
- AudioStreamPlayer3D: `attenuation_filter_db = 0` (no distance low-pass), `max_db = 0`, `unit_size = reach`.
