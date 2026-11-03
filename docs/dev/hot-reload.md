# Hot-reload on the device

Idea #3 in `docs/ideas.md`. Change a shader, an environment, a theme or a script on the PC, push it, and see the
change in the headset without taking it off or restarting the app.

## Use

1. Start the app with `--dev`, or set `hot_reload = true` under `[dev]` in `settings.cfg`. On the device:

   ```
   DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot_player --path app --display-driver x11 --xr-mode on -- --dev
   ```

2. On the PC, from Git Bash or WSL:

   ```
   tools/push-app.sh            # copy app/ to the device once
   tools/push-app.sh --watch    # then copy each changed file within about a second
   tools/push-app.sh --dry-run  # list what would be copied
   ```

   The script copies to `~/spike03/app` on the host `frame`. Set `FRAME_HOST` and `FRAME_APP_DIR` to change them.
   It uses rsync when both ends have it; otherwise it sends a tar stream over ssh. It skips `.godot/` and `docs/`,
   keeps file times, and never deletes anything on the device.

3. Each reload prints one line in the app's log:

   ```
   Hot-reload: gdshader res://shaders/video.gdshader (1.0 ms)
   Hot-reload: gd res://environments/cinema.gd (4.9 ms): 1 live instance(s) keep their state; _ready() not run again
   Hot-reload: environment cinema instanced again (1.0 ms)
   Hot-reload: gd res://scripts/video_screen.gd (24.0 ms): does not compile (errors above), the old version stays
   ```

When the PC listener is on (see `control-protocol.md`), each reload is also sent to the PC as a `reload` event.

## What reloads, and how

The watcher is `app/scripts/dev/hot_reload.gd`. It checks the time and size of each file twice a second. Every two
seconds it also lists the folders again to find new files. A change takes effect once the file has been unchanged for
150 ms, so a half-copied file is not read.

| File | What happens |
|---|---|
| `.gdshader`, `.gdshaderinc` | The cached shader is loaded again with `CACHE_MODE_REPLACE`. The existing `Shader` object takes the new code, so every material that uses it recompiles. An include tells the shaders that use it. |
| `.tres`, `.res` | The same. The cached resource, such as a theme, a material or a mesh, takes the new properties and emits `changed`. |
| `.gd` | The new source is first compiled as a throwaway copy. If it fails, the errors are logged and the old script stays. If it compiles, the cached `GDScript` gets the new source and `reload(true)`. Live instances keep their member values and run the new functions from their next call. `_ready()` does not run again. |
| `.tscn` | The cached scene is replaced. Live instances are not rebuilt. |
| anything under `environments/` | After the reload, the current environment is instanced again from its scene, so scene, script and property changes all show. |

A file that nothing has loaded yet is skipped with the note "not loaded, nothing to do". The next load reads it from
disk anyway.

## Limits

- **Script state.** A new member variable starts at null in live instances, not at its initialiser. Static variables
  are reset in a template build, which is what the device runs. Signals connected in `_ready()` stay connected to the
  old function names. When in doubt, restart.
- **Lambdas.** Connected lambdas are carried over by the engine where it can match them. A lambda whose function was
  removed stops working.
- **The main scene.** `scenes/main.tscn` and nodes made in `_ready()` are not rebuilt. The `reload app` command (see
  `control-protocol.md`) instances the main scene again.
- **The watcher itself.** A change to `scripts/dev/hot_reload.gd` needs a restart.
- **Time resolution.** File times have one-second resolution. Two saves within one second that keep the same size
  are seen as one change.
- **Relative preloads.** The throwaway compile has no path, so a `preload()` with a relative path fails there. The
  app uses `res://` paths everywhere.

## Cost

- **Off,** which is the default: `dev_host.gd`'s `attach()` reads three settings and returns. No node is made, and
  no other dev script is even compiled. `dev_host.gd` has no dependencies, so an error in a dev script can't stop the
  app from starting with dev mode off.
- **On:** about 60 file checks twice a second on the main thread, measured at well under a millisecond. Nothing
  else runs per frame.

## Tested

On the desktop only, on 2026-10-31. The test used the stock 4.7.2 Windows build and the fork's x86_64 template build
(`template_debug`), headless. A shader, an environment script, a new function in a live script and a script with a
syntax error were all edited while the app ran. The environment was instanced again, and the broken script was
refused while the old one kept running.

Not tested on the device: the push script, rsync on the device, and reloading during XR rendering.
