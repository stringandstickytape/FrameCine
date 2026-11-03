# Steam Frame cameras, mixed reality, table surfaces and Gaussian splat rooms

Research date: 2026-10-31. Nothing here is tested on the device. Confidence labels as in `research-device.md`:
- **confirmed**: a primary source states it, or the source code shows it.
- **likely**: indirect or secondary evidence.
- **unknown**: no source found.

Related: passthrough spike (`xr-spikes.md`), idea #71 passthrough window and #53 glTF rooms (`ideas.md`), rooms
(`features.md`, "#52 More environments, #18 photo rooms, #53 glTF rooms").

## 1. Summary

- **No camera API.** Neither Valve nor Arcturus gives apps the camera frames. Arcturus: "A direct camera access API
  is not yet available."
- **Passthrough is plain OpenXR.** An app submits `XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND`. The runtime puts the camera
  view behind the transparent pixels. This is what our `--passthrough` spike already does. It works only for apps
  that run on the Frame, not for PC apps that stream to it.
- **The colour add-on changes only the picture.** With the Arcturus camera plugged in, the same passthrough is in
  colour. Without it, it is the monochrome tracking cameras.
- **No surfaces, no depth, no room mesh.** We found nothing that gives an app a table's plane. Touching the table with
  a controller is the practical way (section 5).
- **Gaussian splat rooms are possible.** The Frame already draws splats (Arcturus's own viewer). We would write our
  own renderer for the Mobile renderer and a placement UI (section 6). Estimate: about 80 to 85 % that a usable version
  works. The open question is the splat count at 90 Hz while video decodes.

## 2. The Arcturus Vision Camera

| Item | Finding | Confidence | Source |
|---|---|---|---|
| What | A third-party colour camera for the Frame's front expansion port. Certified "Steam Frame Compatible". Frame only. | confirmed | [UploadVR](https://www.uploadvr.com/steam-frame-arcturus-vision-camera-color-passthrough/), [Arcturus support](https://arcturus.vision/support) |
| Price | $149. Orders opened 2026-09-15. | confirmed | [Radiance Fields](https://radiancefields.com/arcturus-vision-opens-orders-for-a-149-steam-frame-passthrough-camera) |
| Sensors | Two 32 MP Sony RGB sensors, 64 mm apart. 10 g. The device shows as V4L2 nodes named `arcimx616 ...`, which suggests a Sony IMX616. | confirmed / likely (sensor model) | [UploadVR](https://www.uploadvr.com/steam-frame-arcturus-vision-camera-color-passthrough/), [frame-passthrough-shortcuts](https://github.com/KominoVR/frame-passthrough-shortcuts) |
| Passthrough | 2464x2464 per eye at 60 Hz (default) or 72 Hz. 1232x1232 per eye at up to 144 Hz is experimental. Arcturus warns that higher rates can flicker under artificial light. The homepage says "depth-corrected passthrough". | confirmed | [UploadVR](https://www.uploadvr.com/steam-frame-arcturus-vision-camera-color-passthrough/), [Arcturus](https://arcturus.vision/) |
| Integration | Support ships with the Frame's system software. Plugging in the camera switches passthrough to colour at once, with no restart. It replaces the monochrome view everywhere: the SteamVR dashboard background and every app that uses passthrough. | confirmed | [Arcturus FAQ](https://arcturus.vision/#faq), [Road to VR review](https://www.roadtovr.com/arcturus-vision-camera-review-steam-frame-passthrough-add-on/) |
| Quality | About the same as Quest 3 passthrough. Text on a phone is readable, which is not possible with the built-in cameras. | likely (one review) | [Road to VR review](https://www.roadtovr.com/arcturus-vision-camera-review-steam-frame-passthrough-add-on/) |
| Recording | Arcturus's "Camera" app records stereo video: 2464x2464 per eye at 60 fps or 1232x1232 at 120 fps, 10-bit HLG HDR. It also stores the headset's tracked pose for each frame. Playback can move the picture with that pose ("Stabilized Immersive Playback"). | confirmed | [UploadVR](https://www.uploadvr.com/steam-frame-arcturus-vision-camera-color-passthrough/), [Road to VR review](https://www.roadtovr.com/arcturus-vision-camera-review-steam-frame-passthrough-add-on/) |
| Other apps | "Sync" (Windows and Mac) copies recordings off the headset and converts them for other headsets. "Gaussian XR" is a viewer on the headset for `.ply` and `.sog` splat files. | confirmed | same |
| Splat capture | Advertised. Today it needs command-line tools on a Linux PC with an NVIDIA GPU. | confirmed | same |
| Battery | Active use costs battery. No figure published. The port can supply up to 6 W. | confirmed (cost) / unknown (amount) | [UploadVR](https://www.uploadvr.com/steam-frame-arcturus-vision-camera-color-passthrough/), [Digital Citizen](https://www.digitalcitizen.life/valve-steam-frame-cad-expansion-port-power-gating/) |

## 3. Ways for an app to use the cameras

### 3.1 Official: OpenXR alpha blend (works now)

From Arcturus's developer pages ([developers](https://arcturus.vision/developers),
[Unreal tutorial](https://arcturus.vision/developers/unreal)):

- Check `xrEnumerateEnvironmentBlendModes` for `ALPHA_BLEND`.
- Use a swapchain with alpha. Clear to transparent black. Remove opaque backgrounds.
- Submit `XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND` in `XrFrameEndInfo.environmentBlendMode` to `xrEndFrame`.
- For non-premultiplied alpha, set `XR_COMPOSITION_LAYER_UNPREMULTIPLIED_ALPHA_BIT`.
- "The OpenXR runtime composites the camera background." No raw-camera SDK and no vendor passthrough extension is
  needed.
- "Local VR only": this works for apps that run on the Frame, not for PC apps through streamed VR.
- Unity and native C++/Vulkan samples are available (MIT for Arcturus's own code).

Our spike (`xr-spikes.md`, `--passthrough`) follows these steps. A new check for the device: does Godot's alpha need
the unpremultiplied bit, or do half-transparent edges (the pane's halo, the screen's fade) come out too dark or too
bright?

Valve's Steamworks pages for the Frame (overview, engines, custom, Unity, Unreal, Godot) do not mention passthrough,
blend modes or camera access. The debugging page mentions cameras only for a tracking-diagnostics capture that is sent
to Valve. ([Steamworks: Steam Frame](https://partner.steamgames.com/doc/steamhardware/steamframe),
[debugging](https://partner.steamgames.com/doc/steamhardware/steamframe/debugging))

### 3.2 Unofficial: the private SteamVR camera interface (settings only)

The open-source [frame-passthrough-shortcuts](https://github.com/KominoVR/frame-passthrough-shortcuts) (MIT) switches
between the colour and the monochrome cameras. From its source (`src/openvr_camera_source.cpp`, `src/controller.cpp`):

- `vr::VR_GetGenericInterface("IVRCameraPassthroughInternal_001")`. Vtable slot 9 reads and slot 10 writes a 5-byte
  setting: enabled, stereo, RGB source, disable devignetting, sharpening. Each byte is 0 or 1. The write notifies the
  compositor (event 812).
- The SteamVR setting `camera.roomViewStyle` selects translucent or opaque passthrough.
- It finds the Arcturus sensor by scanning `/sys/class/video4linux/*/name` for `arcimx616 `, and asks whether it is
  connected with ioctl `0x800456c1`. Device numbers are not stable.
- The author verified it only on Frame firmware build 20260918 and warns that it can change with any SteamVR update.

It changes settings only. It never reads camera frames.

### 3.3 Unofficial: raw frames through V4L2 (not tried by anyone we found)

The Arcturus sensor exists as V4L2 nodes, so its frames may be readable while SteamVR does not hold the device. No one
has documented this. It would conflict with system passthrough, could break with a firmware update, and needs the
colour add-on. The built-in tracking cameras are in use for tracking all the time.

### 3.4 Hardware: the expansion port

From Valve's CAD and electrical release, as reported by
[Digital Citizen](https://www.digitalcitizen.life/valve-steam-frame-cad-expansion-port-power-gating/) (Valve's
repository itself refused automated access):

- Two 4-lane MIPI D-PHY v1.2 camera links (up to 2.5 Gbps a lane), camera clocks, trigger and strobe, 400 kHz I2C.
  The camera pins share one PCIe Gen4 lane: "a stereo camera interface or a one-lane PCIe slot, not both at once."
- 3.1 V, 2 A continuous, 6 W at most.
- Power stays on only when a device passes an identification check: the known Arcturus camera on I2C, a power-only
  or PCIe-only strap, or an EEPROM at Valve's address.
- Licence CC BY-NC-SA 4.0. Commercial use: contact Valve for a licence. Valve does not model the colour camera.

This only matters for building hardware. It is out of scope for this app.

## 4. The built-in cameras

| Item | Finding | Confidence | Source |
|---|---|---|---|
| Outward cameras | Four monochrome fisheye cameras for headset and controller tracking. IR illuminators for tracking in the dark. | confirmed (secondary) | [iFixit](https://www.ifixit.com/Device/Steam_Frame) |
| Passthrough | Monochrome, stereo, 1280x1024. Reviewers call it "monotone and low resolution". | likely | [Road to VR specs](https://www.roadtovr.com/?p=125603), [Road to VR review](https://www.roadtovr.com/arcturus-vision-camera-review-steam-frame-passthrough-add-on/) |
| Inward cameras | Two eye-tracking cameras. Apps get gaze through `XR_EXT_eye_gaze_interaction`, not images. | confirmed | [iFixit](https://www.ifixit.com/Device/Steam_Frame), `research-device.md` |
| App access | Hand tracking and eye gaze through OpenXR (`--hands`, the capabilities line). No access to frames. | confirmed (no API found) | `xr-spikes.md` |

The same `ALPHA_BLEND` path shows them. Good enough to find a cup or the sofa, not to read text.

## 5. Table surfaces

- **No API found.** Valve's Frame docs list no scene or plane extension. A search for `XR_EXT_plane_detection` on the
  Frame found only the generic OpenXR spec. The compositor estimates depth for "depth-corrected passthrough", but does
  not expose it.
- **The device check:** the capabilities line lists the runtime's extensions. Look for `XR_EXT_plane_detection`,
  `XR_FB_scene`, `XR_FB_spatial_entity`, and any `XR_VALVE_*` or `XR_MNDX_*`.
- **What the runtime does give:** the stage space (floor at 0) and the play area bounds
  (`xrGetReferenceSpaceBoundsRect`). Nothing about furniture.

### Touch calibration (works without any API)

1. **One touch:** lay a controller flat on the table and press a button. Its tracked height gives a level table plane,
   to a few millimetres. That is better than most camera plane detection.
2. **Corners:** touch three or four corners for the table's outline, or a tilted surface. With `--hands`, a flat palm
   or a fingertip tap on the corners does the same.
3. **Keep it** in stage space, per room, so it is still right next session while the room setup is unchanged.

With passthrough, a virtual table or a screen stand lines up with the real table.

### Camera-based detection

Only through our own stereo depth from the Arcturus V4L2 frames (3.3). It is undocumented, can break with a firmware
update, and needs the add-on. A research project, against about two hours of work for touch calibration.

## 6. Gaussian splat rooms: put the video screen inside a splat

### 6.1 Why it is possible

- **The Frame draws splats already.** Arcturus Gaussian XR runs on the headset and opens `.ply` and `.sog`. No splat
  counts or frame rates are published.
- **The room system fits.** glTF rooms load from `user://rooms` with per-room settings (`[env_<id>]`,
  `[screen_<id>]`). A `splat:<file>` room would follow the same pattern in `scripts/env/env_library.gd`.
- **The screen hooks exist.** `main.screen_pose_override` and the per-room screen pose already move and keep the
  screen (head follow and pin, #33).

### 6.2 Existing Godot add-ons do not fit

| Add-on | Why not | Source |
|---|---|---|
| GDGS (ReconWorldLab/godot-gaussian-splatting), MIT | Needs the Forward+ renderer and a desktop GPU with compute. We use the Mobile renderer (`app/project.godot`). Its importer (`.ply`, `.compressed.ply`, `.splat`, `.sog`) may still be useful to read. | [asset library](https://godotengine.org/asset-library/asset/edit/23773) |
| FoveaCore (zedarvates/FoveaCore), MIT | Pre-release for Godot 4.7. XR support experimental. Desktop builds only. | [asset library](https://www.godotengine.org/asset-library/asset/5420) |

### 6.3 Design

1. **Renderer, without compute shaders**, so it works in the Mobile renderer and avoids turnip compute bugs:
   - The splat data (position, scale, rotation, colour, opacity) goes in textures, loaded once.
   - Each splat is an instanced quad, with alpha blending and no depth write. The vertex shader projects the 3D
     Gaussian to a 2D ellipse per eye.
   - A worker thread sorts the splats by distance from the point between the eyes, about 10 to 20 times a second. Only
     the new order (a texture of indices, 4 bytes a splat) is uploaded.
   - Splats can pop briefly when the head turns fast, because the order is a few frames old. That is an accepted
     limitation.
2. **Draw order:** the room's opaque parts and the screen first, then the splats with the depth test on. Splats then
   wrap correctly around the screen and the pane.
3. **Loader:** PLY (about 250 bytes a splat, so 1 M splats is about 250 MB) and SOG (compressed, much smaller). Decode
   on a worker thread, as photo rooms do.
4. **Fit the splat to the room.** A splat has any scale and any up direction, and no `ScreenAnchor`:
   - **Level:** point at the floor in two or three places, or fit the floor from the splat centres when it loads.
   - **Scale:** match its floor to the real floor height, or enter one known size.
   - **Place the screen:** aim the laser at a wall in the splat. The hit test marches along the ray through a grid of
     splat centres until the density passes a threshold. Grip-drag to adjust. Save the pose per room.
   - Keep the fit in the room's sidecar JSON, like glTF rooms.
5. **Extras:** the screen's light on the splats (a tint by distance from the screen, as the unlit rooms get now), and
   lights-down (#20) dims the splats.

### 6.4 Risks

- **Splat count.** Splats overlap a lot, so they are expensive to draw. Our guess, not measured: hundreds of thousands
  at 90 Hz, not millions, with 4K video decoding at the same time. Foveated rendering helps. Measure on the device
  first.
- **Memory** for big PLY files. SOG removes most of the problem.
- **Getting splats.** From an Arcturus capture it needs Linux, an NVIDIA GPU and the command line today. Phone capture
  apps export PLY.

### 6.5 Effort

- Renderer and loader: about 2 to 3 days.
- Level, scale and screen placement UI: about 1 to 2 days.
- Device tuning: not known until frame time is measured.

## 7. Ideas for this app

- **#71 passthrough window**, already built as a spike: good in colour with the add-on, a "where is my cup" view
  without it.
- **Play Arcturus recordings:** stereo 10-bit HLG with a pose per frame. We already decode 10-bit P010 in hardware.
  Stabilized playback could use the poses. Unknown: the container and how the poses are stored. Needs a sample file.
- **Dim the room, do not hide it:** passthrough around the screen's edges, with the same blend path.
- **Table calibration** (section 5), for a screen stand or a virtual table on the real one.
- **Splat rooms** (section 6).
- **Anything that reads the room** (match the screen's light to the room, pause when someone comes in): needs camera
  frames, so only through 3.3. Wait for an official API.

## 8. Sources

- Arcturus: [homepage and FAQ](https://arcturus.vision/), [developers](https://arcturus.vision/developers),
  [Unreal tutorial](https://arcturus.vision/developers/unreal), [support](https://arcturus.vision/support)
- [UploadVR: Arcturus Vision camera](https://www.uploadvr.com/steam-frame-arcturus-vision-camera-color-passthrough/)
- [Road to VR: review](https://www.roadtovr.com/arcturus-vision-camera-review-steam-frame-passthrough-add-on/),
  [announcement](https://roadtovr.com/steam-frame-color-passthrough-camera-upgrade/),
  [specs](https://www.roadtovr.com/?p=125603)
- [VR.org: the developer side](https://vr.org/articles/steam-frame-color-passthrough-arcturus-vision-149-mixed-reality-developers-2026)
- [Digital Citizen: expansion port CAD release](https://www.digitalcitizen.life/valve-steam-frame-cad-expansion-port-power-gating/)
- [Radiance Fields: orders open](https://radiancefields.com/arcturus-vision-opens-orders-for-a-149-steam-frame-passthrough-camera)
- [KominoVR/frame-passthrough-shortcuts](https://github.com/KominoVR/frame-passthrough-shortcuts) (source read)
- Steamworks: [Steam Frame](https://partner.steamgames.com/doc/steamhardware/steamframe),
  [engines](https://partner.steamgames.com/doc/steamhardware/steamframe/engines),
  [debugging](https://partner.steamgames.com/doc/steamhardware/steamframe/debugging)
- [iFixit: Steam Frame](https://www.ifixit.com/Device/Steam_Frame), [Wikipedia: Steam Frame](https://en.wikipedia.org/wiki/Steam_Frame)
- OpenXR: [XrPlaneDetectorEXT](https://registry.khronos.org/OpenXR/specs/1.1/man/html/XrPlaneDetectorEXT.html)
- Godot add-ons: [GDGS](https://godotengine.org/asset-library/asset/edit/23773),
  [FoveaCore](https://www.godotengine.org/asset-library/asset/5420)
