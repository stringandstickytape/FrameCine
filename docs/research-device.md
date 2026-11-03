# Steam Frame: video decode and GPU driver research

Research date: 2026-10-30. Confidence labels:
- **confirmed**: a primary source states it, or a reproducible on-device report shows it.
- **likely**: indirect or secondary evidence.
- **unknown**: no source found.

Many of the key facts come from community bug reports on `ValveSoftware/SteamOS`. Valve has not acknowledged most of them. Each one comes from a single on-device report, so the on-device survey must check them again.

## 1. Hardware and OS

| Item | Finding | Confidence | Source |
|---|---|---|---|
| SoC | Snapdragon 8 Gen 3 (Arm64). Device tree compatible `qcom,sm8650`. | confirmed | [Steamworks: compatibility](https://partner.steamgames.com/doc/steamhardware/steamframe/compatibility), [SteamOS #2954](https://github.com/ValveSoftware/SteamOS/issues/2954) |
| Frame-specific SoC bin or clocks | No source. Qualcomm ships 3.0, 3.3 and 3.4 GHz prime-core versions. | unknown | [Qualcomm 8 Gen 3 brief](https://docs.qualcomm.com/bundle/publicresource/87-71408-1_REV_C_Snapdragon_8_gen_3_Mobile_Platform_Product_Brief.pdf) |
| GPU | Adreno 750, reported by Vulkan as "Turnip Adreno (TM) 750" | confirmed | [SteamOS #2946](https://github.com/ValveSoftware/SteamOS/issues/2946) |
| RAM | 16 GB unified LPDDR5X | confirmed (secondary) | [Wikipedia](https://en.wikipedia.org/wiki/Steam_Frame) |
| Panels | 2160x2160 per eye, LCD, pancake lenses | confirmed (secondary) | [Wikipedia](https://en.wikipedia.org/wiki/Steam_Frame) |
| Refresh rates | 72, 80, 90, 120 and 144 Hz (144 is experimental). Default 72 Hz, default render size 1728x1728 per eye. | confirmed | [Steamworks: vrpreferences](https://partner.steamgames.com/doc/steamhardware/steamframe/vrpreferences), [Wikipedia](https://en.wikipedia.org/wiki/Steam_Frame) |
| Eye tracking | Yes. OpenXR exposes it through `XR_EXT_eye_gaze_interaction` and `XR_META_foveation_eye_tracked`. | confirmed | [Steamworks: custom engines](https://partner.steamgames.com/doc/steamhardware/steamframe/engines/custom) |
| Storage | 256 GB or 1 TB UFS, plus a microSD slot | confirmed (secondary) | [Wikipedia](https://en.wikipedia.org/wiki/Steam_Frame) |
| Wi-Fi | Wi-Fi 7, 2x2, two radios (5 GHz and 6 GHz). A Wi-Fi 6E USB adapter for the PC is in the box. Bluetooth 5.3 or 5.4 (sources disagree). | confirmed (secondary) | [Wikipedia](https://en.wikipedia.org/wiki/Steam_Frame) |
| Passthrough cameras | Four monochrome tracking cameras. A colour passthrough camera (Arcturus Vision, $149) is a third-party accessory for the expansion port. No camera API; see `research-cameras-and-splats.md`. | confirmed | [Wikipedia](https://en.wikipedia.org/wiki/Steam_Frame), [Arcturus](https://arcturus.vision/developers) |
| OS | SteamOS (Arch-based). Builds are numbered 0.3.0 (stable, Sept 2026) to 0.5.6 (preview, Oct 2026), with `VARIANT_ID=vr`. The read-only root can be unlocked with `steamos-readonly disable`, and `pacman` is available. | confirmed | [Steamworks: debugging](https://partner.steamgames.com/doc/steamhardware/steamframe/debugging), [SteamOS #2869](https://github.com/ValveSoftware/SteamOS/issues/2869), [#2954](https://github.com/ValveSoftware/SteamOS/issues/2954) |
| aarch64 Arch base | "Holo Core", an aarch64 port of Arch built by Collabora | confirmed | [Collabora blog](https://www.collabora.com/news-and-blog/news-and-events/building-an-arch-linux-aarch64-port-for-holo-core.html) |
| Kernel | Stable: `linux-618-deckard` 6.18.0 (for example `6.18.0-gfbdbca41fd45`, `6.18.0-g83913f38113c`). Preview/hotfix: `linux-72-deckard` 7.2.0 (`7.2.0-g588c8cf61681`). The platform code name is "deckard". | confirmed | [SteamOS #2869](https://github.com/ValveSoftware/SteamOS/issues/2869), [#2902](https://github.com/ValveSoftware/SteamOS/issues/2902), [#2954](https://github.com/ValveSoftware/SteamOS/issues/2954) |
| Kernel source | The only copy found is an unofficial community mirror (`evlaV/deckard-linux-no-oopsies`). No official Valve repository was found. | likely | [mirror](https://github.com/evlaV/deckard-linux-no-oopsies) |
| System Mesa | Valve's docs say `mesa_version` reports a version "like 25.3.0-devel". Reports give Vulkan 1.4.362 Turnip, and Turnip 26.2.2 inside a Flatpak, which can be the Flatpak runtime's Mesa. Valve's debug package name is `deckard-mesa-android-aarch64-debug`. | likely | [Steamworks: debugging](https://partner.steamgames.com/doc/steamhardware/steamframe/debugging), [#2946](https://github.com/ValveSoftware/SteamOS/issues/2946), [#2882](https://github.com/ValveSoftware/SteamOS/issues/2882) |

## 2. Hardware video decoder (VPU)

**Driver.** The shipping kernel uses Valve's fork of Qualcomm's **iris** driver, not `venus` and not mainline iris. The module is `drivers/media/platform/qcom/vcodec/iris/iris.ko`, with driver `iris_driver` and card `iris_decoder`. The device node is `/dev/video-dec0`, a symlink to `/dev/video22`. The firmware is `qcom/vpu/vpu33_4v.mbn` (`video-firmware.3.4`). The fork appears to come from Qualcomm's unmerged Dec 2023 iris v2 series. SteamOS ships an `iris-driver-rebind.service`, which suggests firmware crashes are a known problem. **confirmed (on-device reports)**: [#2869](https://github.com/ValveSoftware/SteamOS/issues/2869), [#2865](https://github.com/ValveSoftware/SteamOS/issues/2865), [#2954](https://github.com/ValveSoftware/SteamOS/issues/2954)

**Interface.** V4L2 **stateful** memory-to-memory (M2M) decoder, using the MPLANE buffer types. It sends `V4L2_EVENT_SOURCE_CHANGE`. **confirmed**: [#2869](https://github.com/ValveSoftware/SteamOS/issues/2869)

### Codecs on the shipping Frame kernel

| Codec | Status on the Frame | Confidence | Source |
|---|---|---|---|
| H.264 | Works and is stable in sequential sessions (about 1000 fps at 1080p). It can crash when there are many parallel sessions or fast session create/destroy cycles (firmware error 0x5000003, then a kernel oops). The 7.2 preview kernel still has the bug. | confirmed | [#2865](https://github.com/ValveSoftware/SteamOS/issues/2865), [#2902](https://github.com/ValveSoftware/SteamOS/issues/2902) |
| HEVC Main (8-bit) | Offered and works. A third-party streaming client decodes it to NV12 linear and imports it into Vulkan. | confirmed | [#2882](https://github.com/ValveSoftware/SteamOS/issues/2882), [#2946](https://github.com/ValveSoftware/SteamOS/issues/2946) |
| HEVC Main10 | Decodes correctly and fast (7680x3840 at 146 fps), but on the stock module **only into `Q10C` (TP10 UBWC)**. If NV12 is requested, the decoder writes the low 8 bits of each sample, so the picture is garbage. **`P010` is not offered** (our patched module adds it). Upstream Turnip can't sample Q10C: it has no TP10 code, and its `G10X6` 2-plane UBWC layout is P010. Another player on the headset imports Q10C as a multi-planar image with a DRM modifier and samples it through a YCbCr sampler, so Valve's Turnip (26.3.0_devel+gitabc426bb) likely can. Which format and modifier is what `spikes/04-q10c-probe` finds out; PLAYER_Q10C tries the driver's candidates and checks the picture (2026-10-31, not yet run). | confirmed (Q10C only); likely (YCbCr import) | [#2946](https://github.com/ValveSoftware/SteamOS/issues/2946), `spikes/04-q10c-probe/README.md` |
| VP9 | Offered (`VP90`, 128x128 to 8192x8192, profiles 0 and 2). **Sequential sessions work** (our run, 2026-10-31, kernel 6.18.0-ge66bc2ca6f8c: 8-bit to NV12 and 10-bit to Q10C at about 1000 fps with 0 errors; VP9 and HEVC sessions one after another; five VP9 runs in a row). **Two sessions at once crash the firmware**: the rebind service reloads it within a second, both sessions get `DQBUF` `EINVAL`, and killing the process afterwards oopsed the kernel ("exited with preempt_count 1") and needed a reboot. The player keeps one hardware VP9 session at a time. **The third sequential session crashed the firmware** in the player run of 2026-10-31 (`0x5000003`, reloaded; the software fallback took over) after two clean sessions, while whole superframes (alt-ref + shown frame in one buffer) went to OUTPUT. Another player on the device splits them first (FFmpeg's `vp9_superframe_split`); since PLAYER_Q10C so does ours, one frame per OUTPUT buffer. Device run of 2026-10-31 with the split: five 8-bit sessions in a row clean; then a 10-bit (Profile 2, Q10C) session clean and the next one crashed the firmware at its start (`0x5000003`, reloaded, software fallback, the next session clean in hardware). So the split helps; the crash is not gone. | confirmed (crash); unknown (cause) | [#2865](https://github.com/ValveSoftware/SteamOS/issues/2865), `spikes/03-player/README.md` "Hardware VP9" |
| AV1 | **Not exposed.** The firmware has AV1 code, but the fork has no AV1 support (checked on 6.18 and on the 7.2 hotfix kernel). A community-built module enables it: 4K60 and 8K30 decoded cleanly, and 8K60 stalled at start-up. | confirmed | [#2954](https://github.com/ValveSoftware/SteamOS/issues/2954), [PoC](https://github.com/mmis1000/steamframe-iris-av1-poc) |
| 4:2:2 | No 4:2:2 capture formats listed (`Q08C NV12 NV21 Q10C AB24 QC24`). The Qualcomm brief does not mention 4:2:2. | likely not | [#2946](https://github.com/ValveSoftware/SteamOS/issues/2946) |
| Capture formats (HEVC) | `Q08C` (NV12 UBWC), `NV12`, `NV21`, `Q10C`, `AB24`, `QC24`. `AB24` output is not valid RGBA. | confirmed | [#2946](https://github.com/ValveSoftware/SteamOS/issues/2946) |

### Spec deviations in the fork that a client must work around

- OUTPUT formats do not set `V4L2_FMT_FLAG_DYN_RESOLUTION`.
- `G_FMT` on CAPTURE stays at 384x256 until the source-change event arrives.
- The driver can DMA a full frame into a CAPTURE buffer that is too small. This causes SMMU faults and a client SIGSEGV.
- Result: GStreamer's `v4l2videodec` takes its legacy path and crashes. A client must wait for `SOURCE_CHANGE` before it allocates CAPTURE buffers.
- Confidence: **confirmed**. Source: [#2869](https://github.com/ValveSoftware/SteamOS/issues/2869)

### Mainline iris, for comparison and future backports

- SM8650 support since **v6.16** ([cae67e94e46a](https://git.kernel.org/torvalds/c/cae67e94e46a)).
- AV1 decode since **v7.0** ([10ac84abd481](https://git.kernel.org/torvalds/c/10ac84abd481)).
- 10-bit decode with **linear P010** since **v7.2** ([65c06d2edded](https://git.kernel.org/torvalds/c/65c06d2edded) and its series).
- Confidence: **confirmed** (kernel git: each commit is reachable from the stated tag and not from the tag before it).

### 8K60 ceiling

- Qualcomm's product brief says only "Hardware-accelerated H.265, VP9, AV1 decoder" and gives no resolution or fps ceiling ([brief](https://docs.qualcomm.com/bundle/publicresource/87-71408-1_REV_C_Snapdragon_8_gen_3_Mobile_Platform_Product_Brief.pdf)).
- Mainline platform data for sm8650:
  - `max_frame_width/height` = 8192
  - `max_mbpf` = 8192x4352/256
  - `max_core_mbps` = 7680x4320/256 x 60, which is an 8K60 budget
  - Sources: [iris_platform_vpu3x.c](https://github.com/torvalds/linux/blob/v7.3/drivers/media/platform/qcom/iris/iris_platform_vpu3x.c), [iris_platform_sm8550.h](https://github.com/torvalds/linux/blob/v7.3/drivers/media/platform/qcom/iris/iris_platform_sm8550.h), [iris_platform_common.h](https://github.com/torvalds/linux/blob/v7.3/drivers/media/platform/qcom/iris/iris_platform_common.h)
- 8192x4096 at 60 fps (a common size for 8K VR video) is about 1% over that budget. 7680x3840 at 60 fps is inside it.
- The HEVC Main10 test at 7680x3840 and 146 fps (above) shows that raw throughput is not the limit for HEVC.
- Assessment: **likely** that 8K60 HEVC works (8-bit to NV12, and 10-bit to Q10C). **unknown** for linear NV12 bandwidth at 8K60, for the fork's own limits, and for AV1 8K60, which stalled in the community test.

### Software decode baseline

On-device FFmpeg software decode of HEVC Main10, using all cores ([#2946](https://github.com/ValveSoftware/SteamOS/issues/2946)):
- About 4K at 103 fps
- About 6K at 58 fps
- About 8K at 31 fps

dav1d AV1 4K60 uses about 1.4 to 1.7 big cores ([#2954](https://github.com/ValveSoftware/SteamOS/issues/2954)). **confirmed (single report)**

## 3. Mesa Turnip (Adreno 750 is a7xx)

Sources: Mesa `main` as of 2026-10-30: [docs/features.txt](https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/docs/features.txt) and [tu_device.cc](https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/src/freedreno/vulkan/tu_device.cc).

| Extension | Turnip status | Confidence |
|---|---|---|
| `VK_KHR_video_queue` / `video_decode_h264/h265/av1` | **Not implemented.** Not in tu's extension table. No Turnip Vulkan Video merge request found in a GitLab search. | confirmed (absent) |
| `VK_EXT_external_memory_dma_buf`, `VK_KHR_external_memory_fd` | Done | confirmed |
| `VK_EXT_image_drm_format_modifier` | Done. Turnip advertises P010 (`G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16`) with LINEAR and `QCOM_COMPRESSED` modifiers ([#2946](https://github.com/ValveSoftware/SteamOS/issues/2946)). | confirmed |
| `VK_KHR_sampler_ycbcr_conversion` | Done | confirmed |
| `VK_KHR_fragment_shading_rate` | Done on a7xx and later, if the hardware has attachment shading rate | confirmed |
| `VK_EXT_fragment_density_map` (+ `_offset`, `VK_QCOM_fragment_density_map_offset`, `VK_VALVE_fragment_density_map_layered`) | Done | confirmed |
| Sampling TP10 / `Q10C` (10-bit UBWC) from V4L2 | Gives garbage, per one report, when read as plane views. Upstream Turnip has no TP10 format; Valve's build may, through a YCbCr sampler (D14 in `docs/decisions.md`, `spikes/04-q10c-probe`). Our try (2026-10-31): each Q10C plane imported as a 32-bit UBWC image a third of the width (the layouts match exactly) and unpacked in the shader; as RGBA8 the picture is noise that keeps the coarse shapes (cause being analysed from a plane dump); A2B10G10R10 can't be wrapped by Godot's `texture_rd_create()`. See `spikes/03-player/README.md`. | confirmed (our device run) |
| Importing `Q08C` (NV12 UBWC) | Works: two images over the dmabuf with the same 2-plane layout, one view format each (Turnip drops UBWC when R8 and R8G8 views share one image). Byte-identical to NV12, less GPU time. | confirmed (our device run, 2026-10-31) |

Demonstrated zero-copy path:
- FFmpeg `hevc_v4l2m2m` produces `AV_PIX_FMT_DRM_PRIME` frames (NV12 linear, one object, two planes).
- libplacebo imports each frame into Turnip with `VkImportMemoryFdInfoKHR`.
- The result is shown in an OpenXR projection layer at 4320x2160 and 120 fps.
- Confidence: **confirmed**. Source: [#2882](https://github.com/ValveSoftware/SteamOS/issues/2882)

Known bug in this path: re-importing a dmabuf on every frame hit a kernel NULL dereference in `msm_gem_import`'s error path. The upstream fix is [e6863b085606](https://git.kernel.org/torvalds/c/e6863b085606f632082192d847d8d578013d4a66) (v7.3-rc1), and it is not in 6.18.

## 4. Native ARM64 Linux apps

- **Valve's guidance:** most developers should ship Windows x86 and run it through Proton and FEX. For custom engines Valve recommends "Android 10 or Linux Arm64". Valve recommends OpenXR, and OpenVR also works. **confirmed**: [compatibility](https://partner.steamgames.com/doc/steamhardware/steamframe/compatibility), [custom engines](https://partner.steamgames.com/doc/steamhardware/steamframe/engines/custom)
- **Runtime:**
  - The SteamOS Devkit Client offers "Steam Linux Runtime 3.0 ARM64 (Sniper)" for Linux ARM64 binaries ([loadgames](https://partner.steamgames.com/doc/steamhardware/steamframe/loadgames)).
  - Valve's SLR guide lists "Steam Linux Runtime 4.0 for arm64" (`steam://install/4185400`). It recommends steamrt4 (Debian 13) for new titles ([SLR guide](https://gitlab.steamos.cloud/steamrt/steam-runtime-tools/-/blob/main/docs/slr-for-game-developers.md)).
  - Graphics drivers come from the host.
  - **confirmed**
- **Steamworks SDK:** ships Linux ARM64 and Android ARM64 libraries from version 1.63. **confirmed**: [custom engines](https://partner.steamgames.com/doc/steamhardware/steamframe/engines/custom)
- **Arm64 depots:** no Valve page found that documents setting up arm64 depots or launch options. **unknown**
- **Deployment:**
  - Use the SteamOS Devkit Client, or ssh/adb/rdp in Developer Mode (user `steamos`, host `frame`).
  - RenderDoc runs on the device.
  - Perf overlay data and CSV recordings are in `~/.local/share/Steam/logs`.
  - Valve's extra perf tools are at [frame-developer-tools](https://gitlab.steamos.cloud/frame-public/frame-developer-tools).
  - **confirmed**: [debugging](https://partner.steamgames.com/doc/steamhardware/steamframe/debugging)
- **FEX:**
  - Valve's FEX translates x86 code and forwards OpenGL/Vulkan calls to native host libraries ([compatibility](https://partner.steamgames.com/doc/steamhardware/steamframe/compatibility)).
  - A FEX maintainer estimates a 10–30% CPU penalty on average. Emulating the x86 memory model (TSO) is the largest cost ([FEX discussion](https://github.com/FEX-Emu/FEX/discussions/5349)).
  - No Frame-specific benchmarks were found.
  - **likely**
  - Not relevant if we ship natively.

## 5. SteamVR as the OpenXR runtime on the Frame

| Extension | Status | Confidence | Source |
|---|---|---|---|
| `XR_FB_foveation`, `_configuration`, `_vulkan`, `XR_FB_swapchain_update_state`, `XR_META_foveation_eye_tracked`, `XR_META_vulkan_swapchain_create_info` | Supported and recommended | confirmed | [custom engines](https://partner.steamgames.com/doc/steamhardware/steamframe/engines/custom) |
| `XR_EXT_eye_gaze_interaction` | Supported | confirmed | same |
| `XR_KHR_composition_layer_depth`, `XR_EXT_frame_synthesis`, `XR_FB_space_warp` | Recommended for reprojection | confirmed | [perf criteria](https://partner.steamgames.com/doc/steamhardware/steamframe/compat/perf_criteria) |
| `XR_EXT_render_model`, `XR_EXT_interaction_render_model`, `XR_VALVE_frame_controller_interaction` | Supported or recommended | confirmed | [compat](https://partner.steamgames.com/doc/steamhardware/steamframe/compat), [input](https://partner.steamgames.com/doc/steamhardware/steamframe/input) |
| `XR_FB_display_refresh_rate` | Present, but SteamVR "only expose[s] the currently in-use refresh rate". An app **cannot request** a rate this way. Use `vrpreferences.json` (`preferMinRefreshRate`, `preferResolution`, `preferHalfFramerate`, `preferMotionSmoothingMode`) at the root of the package. | confirmed | [Unity page](https://partner.steamgames.com/doc/steamhardware/steamframe/engines/unity), [vrpreferences](https://partner.steamgames.com/doc/steamhardware/steamframe/vrpreferences) |
| `XR_KHR_vulkan_enable` / `vulkan_enable2` (also `opengl_es_enable`, `XR_MNDX_egl_enable`) | Listed | confirmed | [Khronos OpenXR-Inventory: valve_steamvr_frame.json](https://github.com/KhronosGroup/OpenXR-Inventory/blob/main/runtimes/valve_steamvr_frame.json) (SteamVR 2.19.0, added 2026-10-08) |
| `XR_KHR_composition_layer_equirect` / `equirect2` / `cylinder` / `cube` | **Not listed.** Only core projection and quad layers are available. The player must draw the sphere or dome itself in a projection layer. | confirmed (absent in 2.19.0) | same |
| Passthrough | `XR_FB_passthrough` is not listed. The `ALPHA_BLEND` environment blend mode is listed alongside `OPAQUE`, which may give a passthrough backdrop. The built-in cameras are monochrome. | confirmed (list) / unknown (behaviour) | same, [Wikipedia](https://en.wikipedia.org/wiki/Steam_Frame) |
| Other listed extensions of interest | `XR_META_recommended_layer_resolution`, `XR_META_performance_metrics`, `XR_EXT_hand_tracking`, `XR_EXT_user_presence`, `XR_EXT_view_configuration_views_change`, `XR_KHR_visibility_mask` | confirmed | same |

To re-check on the device:
1. Run a small native arm64 program that calls `xrEnumerateInstanceExtensionProperties` and checks `XrSystemProperties`. The OpenXR SDK's `hello_xr` also logs the extension list.
2. Find the runtime manifest with `cat ~/.config/openxr/1/active_runtime.json`, or look under `/usr/share/openxr/1/`.
3. Check `vrserver.txt` in `cdl` for the runtime's own log.

## 6. Decode plumbing on Qualcomm Linux

- **FFmpeg `*_v4l2m2m` (upstream):**
  - Decoders exist for h264, hevc, mpeg1/2/4, h263, vc1, vp8 and vp9. There is **no AV1** and **no DRM_PRIME / dmabuf output**: frames are copied out to system-memory pixel formats ([v4l2_m2m_dec.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/v4l2_m2m_dec.c); last functional change 2023).
  - The system ffmpeg on the Frame has `h264_v4l2m2m`, `hevc_v4l2m2m` and `vp9_v4l2m2m` ([#2865](https://github.com/ValveSoftware/SteamOS/issues/2865)).
  - The DRM_PRIME output seen in #2882 implies a patched FFmpeg in that Flatpak. **likely** (not verified)
  - **confirmed** for the upstream facts.
- **FFmpeg Vulkan Video hwaccel:** needs a driver video queue. Turnip has none, so it is **not usable**. **confirmed** (follows from section 3)
- **GStreamer:**
  - iris is stateful, so the plugin is `v4l2videodec` / `v4l2h264dec` in gst-plugins-good, not `v4l2codecs`, which is for stateless decoders ([docs](https://gstreamer.freedesktop.org/documentation/v4l2codecs/index.html)).
  - The system GStreamer 1.24.2 has these elements, but on the Frame they crash for the format-flag reason in section 2 ([#2869](https://github.com/ValveSoftware/SteamOS/issues/2869)).
  - **confirmed**
- **Valve's own client:** the arm64 Steam `streaming_client` decodes only through a V4L2 stateful decoder (`/dev/video-dec*`). It uses DMABUF CAPTURE buffers taken from libdrm dumb buffers and imports them into Vulkan. The UI labels this "V4L2 Vulkan hardware decoding". This is a reverse-engineered description from a third party, so it is **likely**. ([DroidDeck PR #1638](https://github.com/Droid-Deck/DroidDeck/pull/1638))
- **Hardware decode outside Android:**
  - Demonstrated on the Frame: section 2, plus 4320x2160 at 120 fps HEVC in OpenXR (#2882).
  - Demonstrated on Snapdragon X Elite laptops with mainline iris, which hit the same `0x5000003` firmware error ([x1e-nixos-config#201](https://github.com/kuruczgy/x1e-nixos-config/issues/201), as cited in #2865).
  - **confirmed**

## Implications for the player

**Most viable decode path.** Write our own V4L2 stateful client for `/dev/video-dec0`. Do not use FFmpeg's v4l2m2m decoder. Use FFmpeg only for demux and parsing.

How the client works:
- Wait for `SOURCE_CHANGE` before allocating CAPTURE buffers.
- Allocate a fixed CAPTURE pool, either with `VIDIOC_EXPBUF` or with imported DMABUF buffers.
- Import each buffer once into Vulkan, using `VK_EXT_image_drm_format_modifier` and dma_buf, and cache it by buffer index.
- Sample NV12 through `VkSamplerYcbcrConversion`, and render the sphere or dome ourselves into OpenXR projection layers. SteamVR 2.19.0 on the Frame has no equirect or cylinder layers.

Why this path:
- It is the same path Valve's streaming client appears to use.
- A third party has shown it working at 4320x2160 and 120 fps.
- Importing each buffer once avoids the per-frame dmabuf import churn behind #2882.

Vulkan Video is not available.

**Codec reality today (6.18 kernel):**
- 8-bit H.264 and HEVC: hardware decode works.
- HEVC Main10: on the stock module only `Q10C` (re-checked 2026-10-31: after SOURCE_CHANGE the 6.18 driver offers only `Q10C` for a Main10 stream). The player takes P010 when a kernel offers it (mainline 7.2 does; the patched module was removed, `docs/decisions.md` D21), else Q10C through the GPU's YCbCr sampler (PLAYER_Q10C; works on the device since 2026-10-31), else decodes in software up to 1080p (`SoftwareVideoDecoder`).
- AV1: software only (dav1d).
- VP9: hardware decode works one session at a time; two sessions at once crash the firmware and can oops the kernel
  when the process exits. The player opens at most one hardware VP9 session and decodes a second one in software
  (`docs/decisions.md` D13).

Design for a fragile driver:
- Keep one long-lived decoder session. Avoid parallel sessions and fast open/close cycles.
- Expect the firmware to reload, and recover from it.
- Never SIGKILL a process that is stuck in a decode ioctl.

**Refresh rate.** Set it through `vrpreferences.json`. The app cannot switch it at runtime. Pick 120 Hz for 60 fps content and 90 Hz for 30, 45 or 90 fps content.

**Questions the on-device survey must settle:**
1. Exact kernel, iris module, firmware and Mesa versions on the current stable and preview builds. Is a mainline-iris kernel, or the P010 or AV1 backports, scheduled or already in preview?
2. `v4l2-ctl --list-formats-out/-ext`, `--list-framesizes` and profile/level controls for each codec. The real maximum resolution and fps per codec in the fork, including 8192x4096 at 60 fps HEVC 8-bit, 7680x3840 at 60 fps, and two simultaneous sessions (for stereo or top-bottom splits).
3. Does `VIDIOC_EXPBUF` work on CAPTURE? Does CAPTURE accept imported `V4L2_MEMORY_DMABUF` buffers? Which DRM modifiers does Turnip accept for NV12 import (LINEAR vs `QCOM_COMPRESSED`/UBWC Q08C)? Measure the bandwidth and power difference at 8K.
4. Sustained 8K60 HEVC decode plus 2160x2160 stereo rendering at 120 Hz without thermal throttling. Measure power with the perf overlay and CSV recording.
5. Confirm the OpenXR extension list on the current SteamVR build, since the Khronos inventory is for 2.19.0. Check the refresh-rate enumeration result, and what `ALPHA_BLEND` shows.
6. Does `/dev/video-dec0` work from inside the Steam Linux Runtime arm64 container (sniper or steamrt4)? Which runtime does the Devkit Client offer now?
7. Is P010 or 10-bit linear output available in the preview kernel? If it is not, does a TP10 UBWC detile in a compute shader make sense? (Not likely, because UBWC is compressed.)
