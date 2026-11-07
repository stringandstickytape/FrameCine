# Handoff: agent G (seats and motion), phase 1 of the environments engine

Brief: the shared phase-1 brief from the lead (it was in the lead's scratchpad, `envfound/phase1_common.md`) plus
G's own: own `systems/seats.gd`, `systems/motion.gd`, and in `auditorium.gd` only the seat model slot.

## Done

- `app/scripts/env/systems/seats.gd`: 11 models (stadium, folding_chair, plush, multiplex, pew, club_chair,
  director, bench_seat, cushion, hide, bean_bag). Forms up and broken (stadium, plush, multiplex). Three ways in:
  builders' `seat_slots()` (agent F's interface, agreed by message), its own rows and places, broken seats over a
  builder's own (the auditorium). Instanced, tint per seat, own chair folds away, collision boxes, pew ends in
  `SeatEnds`. Spec complete.
- `app/scripts/env/systems/motion.gd`: travel, sway, turn; festoon build; actions rise, lower, go, snap, start, stop;
  speed/accel limits enforced by a follower whatever drives `at`; reduced Motion (< 0.25): snap or fade; `in_front`
  things are see-through for the sight line, in group `env_in_front`, and go away by themselves 4 s into the film.
- `auditorium.gd` slot only: `SEAT_MODELS` (8 single models), `seat_model` enum uses it, `seat_mesh(..., model)`
  dispatches to `seats.gd model_mesh()` for non-stadium models; `_build_seats()` passes `seat_model` (one line).
  The stadium path is unchanged.
- `registry.gd`: two lines (seats, motion).
- Tests: `app/tests/test_env_seats.gd` 207 checks all pass; `app/tests/test_env_motion.gd` 61 checks all pass
  (headless); `test_env_registry` 91 pass.
- Docs: `docs/environments.md` sections "The seats system" and "The motion system", rows marked built, auditorium
  `seat_model` row, two open questions (auditorium seat boxes, film layer).

## Left, in order

1. Import the worktree once (`godot --headless --import --path app`; `app/.godot` did not exist, an import was
   started in the background and may not have finished).
2. Run the brief's list: test_env_cinema_render and test_cinema under lavapipe (stadium must stay pixel-identical;
   it should, the stadium code path is untouched), test_environments, test_env_checks, test_rooms, test_i18n,
   test_assistant_coverage_system, test_assistant_coverage_files, test_features.
3. `tools/i18n.py extract` then `check` (expected: no new words; the code has no tr() strings).
4. Optionally run test_env_seats under lavapipe too: it then checks the real MultiMesh instance transforms
   (headless it uses the system's own record, `shown()` / `covered()`).
5. Final report to the lead (items below).

## Decisions and why

- One motion system per moved thing: cue actions are `<id>.<action>` and must be in the spec, so `organ.rise` is
  a motion system with id `organ`.
- Comfort limits (not in the design before): 0.5 m/s, 0.3 m/s², travel turn 20 deg/s, sway 5 deg / 0.1 m / period
  at least 3 s, turn 15 deg/s, turn acceleration 8 deg/s². Each is a `motion` flag and the range's end.
- Reduced Motion threshold 0.25. Under it a cue's fade on `at` snaps to the end it heads for (direction of change).
- Broken seats index the room's seat list (`host.seats()` order). Over the auditorium the seats system zeroes that
  instance in the builder's "Seats" MultiMesh, again (deferred) after every room move.
- Seats' build is lazy (first `on_room_moved` or tick): other systems' `seats()` need their setup first.
- `upholstery`/`frame` default null (nullable): the model's own; the test checks every model default is CC0.
- Slot style map: chair folding_chair, pew pew, bench bench_seat, cushion/tier cushion, club club_chair,
  ring plush, hide hide, director director.

## Must know (not in the code)

- Agent F (env-builders) agreed: `seat_slots()` from params alone (static `seat_slots_for(p)`), rows left to right,
  aisle gaps bigger than width, no seat boxes in F's `collision_shapes()` when a seats system exists, F names its
  MultiMesh "Seats" only for single seats; pews, bench and cushions are F's static meshes when no seats system.
- For the lead: `film_layer.gd _covered()` should also step aside for visible nodes in group `env_in_front`
  (motion's painting and festoon); not done (not G's file).
- For the lead: the auditorium's `collision_shapes_for()` still gives stadium boxes for every `seat_model`;
  `seats.gd model_boxes()` could replace them.
- Running tests: PowerShell `wsl -- bash <script>` works; the Bash tool refuses `wsl`. Python is only in WSL.

## Exact next step

Finish the import, then run test_env_cinema_render under lavapipe.
