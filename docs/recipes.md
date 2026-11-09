# Scene recipes

Idea #30 in `docs/ideas.md`. Anything built over the dev link (`docs/dev/scene-control.md`) can be saved as a room.
That room is offered as an environment from then on, next to void, dim room and cinema.

## Use

```
L="python tools/listener.py"
$L send spawn ...                      # build things (they go under the main scene's Remote node)
$L send save_recipe "Box room"         # user://recipes/Box room.tscn; replace=true to overwrite
$L send list_recipes
$L send load_recipe "Box room"         # the same as: set environment "recipe:Box room"
$L send delete_recipe "Box room"
```

Next time, pick the room in the pane's Room tab (it is in the environment list), or start with
`--env=recipe:<name>`. The E key on a desktop cycles through recipes too.

## What is saved

`save_recipe` writes one scene, `user://recipes/<name>.tscn`. On the device that is
`~/.local/share/godot/app_userdata/FrameCine/recipes/`. The scene is:

- **The root,** with `app/scripts/dev/recipe_environment.gd`. It extends the environment interface
  (`environments/vr_environment.gd`), and holds the room's light, `ambient_level` and `screen_glow`, as they were at
  saving with the room light applied, plus the screen width.
- **ScreenAnchor:** a marker where the screen was at saving, so the room opens with the screen there.
- **Base:** an instance of the built-in environment it was built in. It is saved as a reference to that scene file,
  so later changes to the cinema show in the recipe too. The cinema's masking border still follows the screen.
- **Built:** a copy of everything under the main scene's `Remote` node. glTF models and generated meshes are saved
  inside the file. Scenes spawned from a file stay references to that file.

Recipes are plain `.tscn` text, so they can be edited, copied between devices, or committed to a repository.
Settings such as screen size and room light are then remembered per recipe, like any environment.

## How the app lists them

`app/scripts/dev/recipes.gd` has no dependencies. `main.gd` calls it through `all_environments()`, which returns the
built-in `ENVIRONMENTS` followed by one row per file in `user://recipes`. The environment list, `set_environment`,
`--env` and the E key all use it. Without saved recipes it costs one folder check. The commands are in
`app/scripts/dev/recipe_commands.gd` and exist in dev mode only. Playing a saved recipe needs no dev mode.

## Tested

On the desktop only, on 2026-10-31, with the stock 4.7.2 Windows build, rendered. The test covered:

- a box and a ball spawned in the cinema with the screen at 6 m, saved;
- saving the same name again, refused without `replace`;
- `list_recipes`;
- the environment switched to void and the live nodes freed, then `load_recipe`. A screenshot showed the cinema,
  the box, the ball and the 6 m screen.
- a fresh start with `--env=recipe:testroom`, which built the Base, Built and ScreenAnchor nodes again.

Not tested on the device: a recipe with a large glTF model, and loading time in XR.
