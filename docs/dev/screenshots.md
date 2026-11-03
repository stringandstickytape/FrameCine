# Screenshots over the dev link

Idea #16 in `docs/ideas.md`. The `screenshot` command renders what each eye sees, plus a third-person free camera,
at a reduced size. The pictures reach the PC over the dev link, so an AI session can see what it changed.

## Use

```
python tools/listener.py send screenshot                                  # left, right and third, 512 px
python tools/listener.py send screenshot views='["third"]' size=800 position='[6, 4, 3]' target='[0, 1.2, -3]'
python tools/listener.py send screenshot views='["left"]' size=256 inline=false
```

| Parameter | Default | Meaning |
|---|---|---|
| `views` | `["left", "right", "third"]` | which pictures |
| `size` | 512 | the eye pictures are size x size. The third picture is size wide at 16:9. Between 64 and 2048. |
| `position` | behind and above the head | where the third camera is, `[x, y, z]` in metres, world space |
| `target` | the screen's centre | what the third camera looks at. In 180 and 360 modes, the default is 3 m ahead of the head. |
| `fov` | 70 | the third camera's vertical field of view, in degrees |
| `inline` | true | send the PNG data in the reply |

The reply lists each picture: `view`, `path` on the headset, `width`, `height`, `camera` (its position) and `fov`.
With `inline`, the listener writes each picture to `~/.frame-listener/shots/` and gives its `local_path` instead of
the data. A `screenshot` event announces the same list, without the data, so the log shows every picture taken. On the
headset, the files stay in `user://dev_shots/` as `shot_<n>_<view>.png`.

## How

The command is `app/scripts/dev/dev_shots.gd`. It reuses the snapshot facility, `app/scripts/dev/snapshots.gd`, through
the facility's `render_view()`. That means one offscreen SubViewport that shares the world and renders only while a
picture is taken. The dev link has its own instance, so it never collides with in-headset snapshots (bumper + A, F12).

- **Eye pictures.** In XR, the camera takes each eye's pose and field of view from the runtime
  (`get_transform_for_view`, `get_projection_for_view`). On a desktop, it takes the flat camera's pose, moved 32 mm
  left or right. The video screen and the overlay pick the eye's picture by `VIEW_INDEX`, which is always 0 in a mono
  viewport. While an eye picture renders, they are forced to that eye with `force_eye`, as the screenshot tour does.
- **The third camera** is placed with `looking_at` from `position` to `target`.

## Cost and limits

- Nothing runs until the command arrives. Each picture costs two frames of an extra render at the chosen size, plus a
  PNG encode on the main thread. A 512 px picture encodes in a few milliseconds on the desktop. On the device, expect
  one or two dropped frames per picture.
- **While an eye picture renders,** both of the user's eyes see that eye's picture of the video for about two frames.
  In stereo content this shows as a brief flatness.
- **Nothing renders in `--headless`.** The command then fails with "nothing renders in --headless".
- An eye picture is square and uses one symmetric field of view. The headset's real eye frustum is asymmetric, so
  the edges differ slightly from what the eye sees.

## Tested

On the desktop only, on 2026-10-31, with the stock 4.7.2 Windows build and the Vulkan Mobile renderer. The test used
the flat SBS pattern in the cinema, at 512 px and 384 px. The left picture shows LEFT EYE, the right shows RIGHT EYE,
and the third camera at `[6, 4, 3]` sees the room. The PNGs arrived in the listener's `shots/` folder.

Not tested on the device: XR eye poses, the cost in frames, and how the forced eye looks in the headset.
