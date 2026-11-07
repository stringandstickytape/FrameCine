# Handoff: agent A (sky and vista), phase 1 of the environments engine

Brief: `phase1_common.md` (the lead has it) and `docs/environments.md`, "The next phase", row A. Owned files:
`app/scripts/env/systems/sky.gd`, `vista.gd`, `app/shaders/env_sky*`, `app/shaders/env_vista*`, the star data.

## Done (committed as WIP, never run)

- `app/environments/sky/bright_stars.json`: about 300 bright stars `[id, RA hours J2000, Dec deg, V mag, B-V]` and
  stick-figure lines for about 50 constellations (pairs of ids). Typed in by hand from Yale Bright Star Catalogue
  values (public domain facts), rounded. No network was used. The faint stars are generated in code, not catalogue.
- `sky.gd`: full `spec()` (mode sky/space/black, latitude, day_of_year, hour (live), facing, dusk (live), the
  gradient colours, glow and its bearing, stars, faint_stars, twinkle (default 0), lines, Milky Way, clouds,
  cloud_colour (live, for film.colour), cloud_screen, wind (motion), aurora (live, for film.quiet), aurora colours,
  bearing and speed (motion), meteors, Earth (bool, bearing, altitude, size, phase, earth_angle (live, for a track),
  earth_turn (motion, max 60))). Action `shooting_star`. `sky_light()` for the vista. Static helpers:
  `catalogue()`, `equatorial()`, `sidereal_hours()`, `star_basis_for()`, `faint_field()`, `noise_texture()`.
- Shaders: `env_sky_common.gdshaderinc` (gradient, cloud cover, shared uniforms), `env_sky.gdshader` (dome:
  gradient, Milky Way from galactic coordinates, aurora, meteor, clouds lit by the screen via env_spill),
  `env_sky_stars`, `env_sky_lines`, `env_sky_earth`.
- `vista.gd` + `env_vista.gdshader`: one mesh, one draw. Shapes: hills, mesas, acropolis (hill, wall, two ruined
  temples, town lamps), birches (bark, branches, snow ground), cypresses, pool (water, coping, lawn, hedge). Live:
  light, floodlight, flood_colour, town_lights, pool_glow, pool_colour, snow, water_motion (motion).

## Decisions and why

- Every sky layer is drawn round the camera (`skip_vertex_transform`, CAMERA_POSITION_WORLD + dir x R) at 175-190 m:
  the camera's far plane is 200 m (`scenes/main.tscn`). The meshes' own vertices sit at that radius too, so
  `env_checks.sight_line` (which reads mesh faces) never sees a small sphere near the seats. `extra_cull_margin` 16384.
- Stars and lines are ArrayMeshes, not MultiMeshes: `env_checks.sight_line` treats every MultiMesh as seats.
- `gi_mode` disabled on all meshes so the lightmap bake ignores them. Sky shaders `fog_disabled`; vista keeps fog.
- blend_mix with alpha only (never blend_mul).
- Film layer: nothing of mine is between the viewer and the screen; sky and vista sit behind it and are hidden by
  the hole punch's depth. No change needed; say so in the report.
- Both systems are kind `sky` (already in KINDS). Compass angles are bearings; `facing` (default 180, south) maps
  them to the room. The vista uses azimuth from the room's front instead.
- "figure" is a PEOPLE_WORD in env_checks: never name a param or id with it (hence `lines`).
- LST = 6.664 + 0.0657098 (day - 1) + 1.0027379 hour (local mean time).

## Left, in order

1. Add the two registry lines in `app/scripts/env/systems/registry.gd`:
   `"sky": "res://scripts/env/systems/sky.gd",` and `"vista": "res://scripts/env/systems/vista.gd",`.
2. Run `test_env_registry` headless; fix parse errors and spec problems (every default must pass its own check;
   the vista `items` default is `[{"shape": "hills"}]`; item fields have no defaults by design).
3. Write `app/tests/test_env_sky.gd`: catalogue reads, every line id exists; Polaris altitude = latitude within 1 deg
   and due north; Betelgeuse > 45 deg and southern at 40 N, 15 Jan, 0 h; Vega near the zenith at 40 N, day 200, 22 h;
   mode black draws nothing; dusk track by film.minutes moves the uniform (use `host.snapshot_override` and
   `signals.fake`); aurora bound to film.quiet with smooth; earth_turn scaled by the Motion setting; a test room
   through `env_checks` (static checks, measure + budget, sight line); a render section under lavapipe (skip when
   headless) that checks the dome draws and stars show. Shaders are only compiled under lavapipe: run it.
4. `app/tests/test_env_vista.gd`: each shape builds, one draw, triangles counted, sky light followed, pool placed,
   a test room (auditorium with `ceiling_cover` 0 + sky + cypresses) through the checks, a lavapipe render.
5. Measure costs, put the measured figures in `spec()` cost.
6. Docs: sections "The sky" and "The vista" in `docs/environments.md`, mark the `sky`, `vista` row built; credit
   the star data in `app/environments/CREDITS.md` (public domain, not CC0 asset: phrase it as data provenance).
7. `tools/i18n.py extract` then `check` (probably no new user-facing words).
8. The full test list in the brief, privacy check, commit with explicit paths, report.

## Test status

Nothing run yet. The WSL runner script used: `wsl -- bash <script>` from the PowerShell tool (the Bash tool
refuses `wsl`). `test_env_registry` passed (83 checks) before these files were added; they are not registered yet.

## Exact next step

Add the registry lines (step 1) and run `test_env_registry` headless.
