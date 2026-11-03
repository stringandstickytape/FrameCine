# XR spikes: runtime capabilities, passthrough (#71), hand tracking (#72)

A spike behind flags. **Nothing here is tested on the device.** The desktop tests cover the hand skeleton, the
pinch, the controller hand-off and the settings file; the runtime parts need the headset.

Code: `app/scripts/xr_spikes/` (`xr_spikes.gd`, `hands.gd`). Test: `app/tests/test_hands.gd`.

## The capabilities line (always, in XR)

At session start the app logs one line:

```
OpenXR capabilities: hand tracking off (start with --hands); hand interaction profile no; eye gaze no;
refresh rates [72.0, 90.0, 120.0]; blend modes opaque, alpha_blend; extension list: not visible to scripts ...
```

Scripts can see only what the engine's OpenXR interface exposes: hand tracking (active or not), the hand interaction
profile, eye gaze, the refresh rates and the environment blend modes. The engine logs the runtime's full extension
list only with its `--verbose` flag. To get it on the headset:

```
./bin/vr-video-player-engine --path app --display-driver x11 --xr-mode on --verbose -- --quit-after=300 2>&1 \
  | grep "Found OpenXR extension"
```

The extensions to look for are `XR_EXT_hand_tracking`, `XR_EXT_hand_interaction`,
`XR_EXT_hand_tracking_data_source`, `XR_FB_passthrough`, `XR_HTC_passthrough`, `XR_EXT_dpad_binding`, and any
`XR_VALVE_*` or `XR_MNDX_*`. The public runtime list (`docs/research-device.md`) has hand tracking and the
ALPHA_BLEND blend mode, and no `XR_FB_passthrough`.

From PLAYER_REQUESTS on, the engine binds `OpenXRAPIExtension.get_supported_extensions()`. The line then also says yes
or no for each of those extensions, lists the vendor ones and gives the total. The code checks for the method and asks
only while OpenXR runs, so other engines and a desktop run log no error. On the x86_64 fork build in WSL the method
is found; without OpenXR the app does not call it. The list from the headset's runtime is not tested yet; it is
the "OpenXR capabilities" check in `docs/morning-checklist.md`.

## Passthrough (`--passthrough`)

If the runtime offers the ALPHA_BLEND blend mode, the app:

- switches the blend mode to ALPHA_BLEND;
- makes the viewport's background transparent (clear colour alpha 0);
- goes to the void room and sets every environment's background to the clear colour.

The runtime's camera view should then show behind the screen. If ALPHA_BLEND is not offered, the log says so and the
view stays opaque. The headset's cameras are monochrome (`docs/research-device.md`).

Open questions for the device: whether ALPHA_BLEND shows the cameras at all, the latency, and whether the screen's
own alpha needs care.

Arcturus documents this same path (ALPHA_BLEND in `xrEndFrame`) for its colour camera. With the camera plugged in,
the runtime shows colour, with no change in the app. For non-premultiplied alpha it sets
`XR_COMPOSITION_LAYER_UNPREMULTIPLIED_ALPHA_BIT`: check whether half-transparent edges look right. Details in
`research-cameras-and-splats.md`.

## Hand tracking (`--hands`)

- **Skeletons.** For each hand there is an `XRNode3D` on the runtime's hand tracker (`/user/hand_tracker/left` and
  `right`), a `Skeleton3D` with the bone names that `XRHandModifier3D` looks for (`RightIndexTip`, ...), the
  modifier, and a dot on each of the 26 joints. There is no hand mesh.
- **Pinch is the trigger.** Thumb tip to index tip closer than 1.5 cm presses. Farther than 3 cm releases.
- **The index finger is the laser.** The aim pose starts at the index knuckle and points along the finger, smoothed.
  It holds still for 0.25 s when a pinch starts or ends, so the click lands where you pointed.
- **The same path as a controller.** The aim pose and the trigger go to the controller's own tracker
  (`right_hand`, `left_hand`). So the pane's laser, clicks, and play or pause work as they are. A hand feeds its
  tracker only while it holds no controller, that is:
  - the runtime has not moved that tracker's aim pose since the hand last wrote it; and
  - the hand tracker does not say that its data comes from a controller.

Hand tracking is an engine start-up setting (`xr/openxr/extensions/hand_tracking`). It is off in `project.godot`,
so the runtime does not track hands for people who do not use them. `--hands` switches it on through the file
`user://xr_override.cfg`, which `project.godot` names as its settings override:

- From `run.sh` (the package's launcher), `--hands` writes the file before the engine starts, so the first run has
  hands.
- From a plain engine command line, the first run with `--hands` writes the file and logs "start again with
  --hands". The next start has hands.
- A start without `--hands` removes the file (logged), so hand tracking is off again from the start after.
- A file with any other setting in it is never changed or removed.

Open questions for the device:

- Does the runtime give unobstructed hands, and does it also give hands while the controllers are held?
- Does the controller model stay visible at the hand's aim? It is drawn on the controller tracker. If so, app-shell
  can hide it while a hand feeds the tracker.
- Is the index direction a good laser, or is a ray from the shoulder through the hand better?
- The engine also supports the hand interaction profile (`XR_EXT_hand_interaction`). If the runtime offers it, the
  action map could bind pinch and aim directly, and this feed would not be needed. The capabilities line says
  whether it is offered.

## Quad layers (#70)

`--pane-layer` and `--video-layer` hand the pane, or the flat video screen, to the runtime as OpenXR quad layers
(the engine's `OpenXRCompositionLayerQuad`, with a SubViewport as the layer's image). The normal path stays the
default. Code: `app/scripts/xr_spikes/quad_layers.gd`. Test: `app/tests/test_quad_layers.gd`.

Why: normally the pane and the screen are drawn into the eye buffers, and the runtime resamples those again for the
lenses. Two filterings blur small text and fine picture detail. A quad layer is sampled once, straight into the
lens-corrected view.

- **`--pane-layer`:** the pane's own SubViewport (740 x 600 px) is the layer's image, at the pane's pose and size.
  The pane's quad in the scene is not drawn, but its halo is. The layer is composited over everything:
  - The laser and the controller show behind the pane where they cross it.
  - The pane cannot fade, so its fades show as a cut. The layer is on above 50 % opacity.
  - Pointing still works, because it uses the pane's maths, not its mesh.
- **`--video-layer`:** the flat screen as two quad layers, one per eye (`eye_visibility`). Each has a SubViewport
  the size of one eye's picture, at most 3840 px a side, drawn by the video shader with the screen's uniforms for
  that eye.
  - The layers sit behind the scene with a hole punched where the screen is (`sort_order` -1,
    `enable_hole_punch`), so the pane, the laser and subtitles in front still cover the picture.
  - The screen's quad in the scene is not drawn (render layers 0); everything else about the screen stays.
  - Flat screens only, without the curve. 180, 360 and the curved screen keep the normal path.
  - Cost: two extra passes of the video shader at the picture's resolution each frame (one per eye), plus the
    runtime's composition of two more layers. The eye buffers no longer draw the screen's pixels, which saves part
    of that.
- **Without XR** (a desktop) the flags print that they do nothing. The startup log says whether the runtime
  supports the layers natively ("natively supported: true"). If not, Godot draws them as ordinary meshes.

Tested on the desktop, forced on without an XR session (15 checks): the layers are built under the XR origin with
the right viewport, size, eye and order, and follow the pane and the screen. The scene's own quads stop being drawn
and come back when the layers go (360, or the spike removed). With WSLg, the two eyes' viewports of a 3D pattern
show different pictures.

Untested: everything the runtime does. That covers whether the Frame's runtime takes quad layers and hole punching,
how much sharper text and picture look, and the GPU cost.
