# Research: Godot engine-side plumbing (dmabuf import, sync, video, OpenXR layers)

Scope: patched Godot fork, Linux arm64, Vulkan (Mesa Turnip), Mobile renderer.
Source checked against **`4.7.2-stable`** (our fork base, see `build/build-frame.sh`) and `master` @ `95c0fa5` (4.8-beta, 2026-10-30). All findings below hold on both unless noted.
Line numbers are for `4.7.2-stable`. Link base: `https://github.com/godotengine/godot/blob/4.7.2-stable/`.

Confidence: **H** = read in source / primary doc. **M** = inferred from source + spec. **L** = unverified, test on device.

---

## 0. Headline finding (affects spike 03)

The Khronos OpenXR-Inventory has an entry for the **Steam Frame runtime (SteamVR 2.19.0, added 2026-10-08)**. It lists
`XR_FB_foveation`, `XR_FB_foveation_vulkan`, `XR_FB_foveation_configuration`, `XR_META_foveation_eye_tracked`,
`XR_META_vulkan_swapchain_create_info`, `XR_FB_display_refresh_rate`, `XR_FB_swapchain_update_state`, `XR_FB_space_warp`,
`XR_EXT_frame_synthesis`, `XR_KHR_composition_layer_depth`, `XR_EXT_eye_gaze_interaction`.
It does **not** list `XR_KHR_composition_layer_cylinder`, `_equirect`, `_equirect2` or `_cube`. **H** (inventory) / **L** (on-device; confirm with `xrEnumerateInstanceExtensionProperties` in spike 00).

Consequences:
- Only **quad** layers (core OpenXR 1.0) are available. Flat video can be a quad layer. 180/360/fisheye/EAC must use the **mesh + shader path** in the projection layer. Godot's `OpenXRCompositionLayerEquirect`/`Cylinder` silently produce no layer when the extension is missing (`is_available()` check in `get_composition_layer()`, `openxr_composition_layer_extension.cpp:577`).
- Foveation via `XR_FB_foveation_vulkan` (Godot's existing path) should work on the device without engine changes. See §5.
- The zero-copy **RD texture import (§1) is the critical path**. The custom quad-layer swapchain (§4) is an optimisation for flat video only.

Source: https://github.com/KhronosGroup/OpenXR-Inventory/blob/main/runtimes/valve_steamvr_frame.json

---

## 1. Importing a dmabuf VkImage into RenderingDevice

### What exists
- `RenderingDevice::texture_create_from_extension(type, format, samples, usage, uint64 image, w, h, depth, layers, mipmaps=1)` (`servers/rendering/rendering_device.cpp:1854`). Creates an RD `Texture` around a native `VkImage`. It sets aspect COLOR (or DEPTH if a depth usage bit is set), adds `R8G8B8A8_UNORM/SRGB` as shared formats, and calls `_texture_make_mutable()` so the render graph tracks it. Exposed to script. OpenXR uses it for its swapchain images (`modules/openxr/extensions/platform/openxr_vulkan_extension.cpp:413`). **H**
- Driver side, `RenderingDeviceDriverVulkan::texture_create_from_extension` (`drivers/vulkan/rendering_device_driver_vulkan.cpp:2445`) only creates a `VkImageView`. `viewType = (VkImageViewType)p_type`, `format = RD_TO_VK_FORMAT[p_format]`, identity swizzle, `levelCount = p_mipmaps`, `layerCount = p_array_layers`, and **`aspectMask` hard-coded to COLOR or DEPTH** (line 2462). It does not set `TextureInfo::vk_image` or `vk_create_info`. Barriers and copies use `vk_view_create_info.image`, so they still work. **H**
- Ownership: `texture_free()` (`:2592`) destroys only the view when `allocation.handle` is null. **We own the `VkImage` and `VkDeviceMemory`.** Free the RD texture first. Destroy the image and memory only after the frames in flight have retired. **H**
- `vk_create_info` is zeroed for extension textures. `texture_create_shared()` reads `owner->vk_create_info.usage` when the view format differs (maintenance2 path). **Do not make format-changing shared views of imported textures** unless you patch the driver to fill `vk_create_info`. **H**

### Getting the Vulkan handles
`RD::get_singleton()->get_driver_resource(RD::DRIVER_RESOURCE_LOGICAL_DEVICE | PHYSICAL_DEVICE | TOPMOST_OBJECT (VkInstance) | COMMAND_QUEUE | QUEUE_FAMILY)` (`rendering_device.cpp:8714`, enum in `rendering_device_commons.h`). With a `RID`, `DRIVER_RESOURCE_TEXTURE` returns the `VkImage` and `DRIVER_RESOURCE_TEXTURE_VIEW` returns the view. Godot uses volk with `volkLoadInstance` only, so device-level entry points resolve through the loader. Fetch extension functions with `vkGetDeviceProcAddr` after the extensions are enabled. **H**

### Enabling device extensions
- Add them in `RenderingDeviceDriverVulkan::_initialize_device_extensions()` (`rendering_device_driver_vulkan.cpp:562`) with `_register_requested_device_extension(NAME, false)`. `VK_KHR_external_memory_fd` is **already requested** (line 592, "we don't actually use this", to silence runtime validation noise). Add these:
  `VK_EXT_external_memory_dma_buf`, `VK_EXT_image_drm_format_modifier`, `VK_EXT_queue_family_foreign`, `VK_KHR_external_semaphore_fd`. Also add `VK_KHR_image_format_list` (already present), `VK_KHR_bind_memory2` and `VK_KHR_sampler_ycbcr_conversion` (these two are core in 1.1). **H** (location) / **M** (dependency set, from the Vulkan spec).
- The OpenXR path does not bypass this list. With `XR_KHR_vulkan_enable2`, Godot passes its own `VkDeviceCreateInfo` to `xrCreateVulkanDeviceKHR` through `VulkanHooks::create_vulkan_device` (`openxr_vulkan_extension.cpp:169`). The runtime appends its own extensions. **H**
- Upstream precedent: PR **#114940** (open) adds project setting `rendering/rendering_device/vulkan/additional_device_extensions` and `RD.get_device_enabled_extensions()`. Proposals #13969 and #15210 ask for the same. Cherry-pick it or copy its 19-line driver change. **H**
- Physical device features: `vulkan_1_1_features.samplerYcbcrConversion = 0` (`:1462`). Set it to `1` when supported (query `VkPhysicalDeviceSamplerYcbcrConversionFeatures`). This keeps validation clean when we create multi-planar images. **M**

### YCbCr / multi-planar support
- RD's `DataFormat` enum already contains `G8_B8R8_2PLANE_420_UNORM`, `G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16` and others, mirroring `VkFormat`. **H**
- RD has **no** `VkSamplerYcbcrConversion` support (sampler creation does not chain it, and the feature is disabled). RD has no `TEXTURE_ASPECT_PLANE_*` (only COLOR/DEPTH/STENCIL in `rendering_device_driver.h`). **Confirmed: no YCbCr support.** **H**
- RD **does** support immutable samplers (`shader_create_from_bytecode_with_samplers`, `Uniform::immutable_sampler`). A real YCbCr-sampler path is therefore possible later. **H**
- Recommended spike path: import NV12/P010 as **one multi-planar VkImage** with `VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT` and `VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT`. Make **two RD textures** from the same `VkImage`: plane 0 as `R8_UNORM`/`R16_UNORM`, plane 1 as `R8G8_UNORM`/`R16G16_UNORM`, aspect `PLANE_0/PLANE_1`. Convert YUV to RGB in our shader. This needs the aspect patch that proposal **#15116** describes: an optional `plane` parameter on `texture_create_from_extension`. The author reports that an 8-line patch gave pixel-correct NV12 on AMD, and that without the patch both views silently alias plane 0. **H** (proposal) / **M** (Turnip).
- Risk: Turnip may refuse `MUTABLE_FORMAT` on UBWC-compressed modifiers, or may fall back to uncompressed. If the decoder exports `DRM_FORMAT_MOD_QCOM_COMPRESSED`, plane views may be unavailable. In that case use the immutable-sampler YCbCr path. Check the modifier list in spike 00/02. **L**

### Layout and ownership (important)
- The render graph treats a newly tracked texture as `RESOURCE_USAGE_NONE`, which maps to `TEXTURE_LAYOUT_UNDEFINED` (`rendering_device_graph.cpp:152`). The first sample emits an `UNDEFINED -> SHADER_READ_ONLY` barrier. Per spec this may discard the contents. On UBWC the risk is real. **H** (code) / **M** (effect).
- Correct pattern for externally written dmabufs: acquire barrier `srcQueueFamilyIndex = VK_QUEUE_FAMILY_FOREIGN_EXT`, `oldLayout = GENERAL`, `newLayout = SHADER_READ_ONLY_OPTIMAL`, issued **every time the producer has written a new frame** into that buffer. wlroots does exactly this in `render/vulkan/renderer.c`. RD cannot express a queue-family transfer. **M**
- Needed patch: a new RD call, e.g. `texture_external_acquire(RID)`. It records a raw barrier through a new `RDD::command_pipeline_barrier` overload that takes queue families. It then sets the texture's `draw_tracker->usage` to `RESOURCE_USAGE_TEXTURE_SAMPLE` so the graph does not emit its own UNDEFINED transition. Files: `rendering_device.{h,cpp}`, `rendering_device_driver.h`, `rendering_device_driver_vulkan.{h,cpp}`, and possibly `rendering_device_graph.{h,cpp}` (the graph reorders commands, so add it as a graph command, not as an immediate one). **M**

---

## 2. External synchronisation

- Existing hook: `RenderingDevice::frames[frame].semaphores_to_wait_on` (`rendering_device.h:1818`, private). `_submit_transfer_worker()` already pushes semaphores onto it (`rendering_device.cpp:7278`). `execute_chained_cmds()` passes them as wait semaphores of the frame's first submit (`:8149`). The driver waits at `VK_PIPELINE_STAGE_ALL_COMMANDS_BIT` (`rendering_device_driver_vulkan.cpp:3213`, has a "FIXME: allow specifying stage mask"). **H**
- `RDD::SemaphoreID` is a bare `VkSemaphore` (`semaphore_create`, `:3091`). There is no import API. **H**
- Minimal patch: add public `RenderingDevice::frame_add_wait_semaphore(uint64_t vk_semaphore)` (render thread only), which appends to `semaphores_to_wait_on`. Create the semaphore ourselves and import the sync_file for each frame with `vkImportSemaphoreFdKHR` (`handleType = SYNC_FD_BIT`, `flags = VK_SEMAPHORE_IMPORT_TEMPORARY_BIT`, which the spec requires for sync_fd). The temporary payload is consumed by the wait, so the semaphore can be reused. Proposal #11567 asks for this upstream (open). **H** (hook) / **M** (patch).
- Simpler for spike 02: **use no GPU semaphore at all.** V4L2 stateful and stateless decoders return a CAPTURE buffer from `VIDIOC_DQBUF` only when decoding is complete. FFmpeg-VAAPI/V4L2 `av_hwframe_map` to DRM PRIME has equivalent semantics. If a producer gives a fence, `poll()` the sync_file on the CPU before the RD frame. The hard constraint runs the other way: **do not re-queue a buffer to the decoder while the GPU may still sample it.** Hold each buffer for `RD::get_frame_delay()` + 1 frames, or until the RD frame fence retires. **M**

---

## 3. Video playback architecture and where hardware playback plugs in

- `VideoStreamPlayback` (`scene/resources/video_stream.h`) has virtuals `play/stop/seek/is_playing/set_paused/get_length/get_playback_position/set_audio_track/update(delta)/get_texture()/get_channels/get_mix_rate`. Audio goes out through `mix_callback`. `VideoStream::instantiate_playback()` is the factory. GDVIRTUALs make these overridable from GDExtension/script too. **H**
- `VideoStreamPlayer` (a Control) calls `playback->update(delta * speed_scale)` in `NOTIFICATION_INTERNAL_PROCESS` (`scene/gui/video_stream_player.cpp:166`) and draws `playback->get_texture()` as a Texture2D. **H**
- Theora (`modules/theora/video_stream_theora.cpp:235`, `video_write`) converts YUV to RGBA8 **on the CPU** and calls `ImageTexture::update(img)`. That is a full CPU upload per frame. It is not a model to follow. **H**
- EIRTeam.FFmpeg (GDExtension, 4.1+): software decode, uploads planes, YUV to RGB in an RD compute shader (`ffmpeg_video_stream.cpp`, `yuv_to_rgb_shader_glsl`). It has **no hardware decode** per its docs. It is useful as a reference for the RD compute-conversion pattern only. **H**
- Zero-copy plug point: a new `VideoStreamPlaybackHW` (engine module, e.g. `modules/hwvideo/`) that
  1. decodes on a worker thread and holds a ring of dmabuf-backed `VkImage`s, imported once per buffer (§1);
  2. in `update()`, picks the frame for the current clock and calls `RenderingServer::call_on_render_thread()` to run the external acquire (§1) and a YUV->RGB pass into an RD-owned RGBA (or RGB10A2) texture. Alternatively, skip the pass and sample the planes directly in the sphere shader;
  3. returns from `get_texture()` a `Texture2DRD` (`scene/resources/texture_rd.h`) wrapping that RD texture (`RenderingServer::texture_rd_create`). Any material or `VideoStreamPlayer` can then use it with no CPU upload. **H** (API) / **M** (design)
- For the 360/180 mesh path, sample the two plane textures directly in a spatial shader as two `Texture2DRD` uniforms, with YUV->RGB done in the fragment shader. This saves one full-resolution write and read per frame, which matters on a bandwidth-bound tiler. **M**
- `ExternalTexture` (Android OES / GL only) is not usable here. **H**

---

## 4. OpenXR composition layers in the engine

### How the nodes work
- `OpenXRCompositionLayer{Quad,Cylinder,Equirect}` (`modules/openxr/scene/`) forward state to `OpenXRCompositionLayerExtension` (`modules/openxr/extensions/openxr_composition_layer_extension.{h,cpp}`). Each layer is a `CompositionLayer` held in an `RID_Owner`. Since #109431 (merged 2025-10), state lives on the render thread. **H**
- Per frame (render thread): `on_pre_render()` (`:545`) calls `update_and_acquire_swapchain()` (`:710`). That creates an `OpenXRAPI::OpenXRSwapChainInfo` with usage `SAMPLED|COLOR_ATTACHMENT|MUTABLE_FORMAT` in the main color format, then does `xrAcquire`+`xrWait`. Next it calls `render_target_set_override(subviewport_rt, swapchain_texture)`, so the **SubViewport renders straight into the swapchain image**. In `end_frame`, `get_composition_layer()` (`:577`) releases the image (`update_swapchain_sub_image`, `:690-700`) and returns the `XrCompositionLayer*`. **H**
- Ordering is safe: `RenderingServerDefault::_draw` runs `xr_server->pre_render()`, then viewports, then `RSG::rasterizer->end_frame()` (RD submit, `rendering_server_default.cpp:115`), then `xr_server->end_frame()` (`:119`, xrRelease + xrEndFrame). GPU work is therefore submitted before the release. **H**
- `OpenXRAPI::end_frame()` (`openxr_api.cpp:2653`) gathers layers from every registered **composition layer provider** (`register_composition_layer_provider`, `openxr_api.h:580`) through `get_composition_layer_count/get_composition_layer/get_composition_layer_order`, and sorts them by order with the projection layer at 0. **H**

### Hooks (`modules/openxr/extensions/openxr_extension_wrapper.h`)
`get_requested_extensions`, `on_instance_created`, `on_session_created/destroyed`, `on_pre_render`, `on_main_swapchains_created`, `on_pre_draw_viewport/on_post_draw_viewport`, `get_composition_layer_count/get_composition_layer/get_composition_layer_order`, `set_viewport_composition_layer_and_get_next_pointer`, `set_swapchain_create_info_and_get_next_pointer`, `set_android_surface_swapchain_create_info_and_get_next_pointer`. `on_post_render` exists on master only, not in 4.7.2. **H**

### Can an engine-side extension own its own XrSwapchain and bypass the SubViewport? **Yes, with no OpenXR-module patch.**
- Write an `OpenXRExtensionWrapper` subclass in our module. Register it as a composition-layer provider. Own an `OpenXRAPI::OpenXRSwapChainInfo` (`create/acquire/get_image/release/queue_free`; `get_image()` returns an RD texture RID already wrapped with `texture_create_from_extension`). Ideally, gate everything on the render thread. GDExtension has the same functionality through `OpenXRAPIExtension::openxr_swapchain_create/acquire/get_image/release` (`openxr_api_extension.h:118`). **H**
- In `on_pre_render`: acquire, then write the video frame into `get_image()`. Release in `get_composition_layer()`, as the built-in layer does. **H**
- Write with a **raster draw** (fullscreen triangle into a framebuffer on the swapchain RID), not a compute pass. `openxr_vulkan_extension.cpp` gives swapchain RIDs only `SAMPLING|COLOR_ATTACHMENT` usage (no STORAGE or CAN_COPY_TO), and the runtime expects `COLOR_ATTACHMENT_OPTIMAL` at release. A compute write needs a patch to `get_swapchain_image_data` and leaves the image in GENERAL. **H** (usage flags) / **M** (layout).
- The swapchain format is the main sRGB format with a UNORM view (`openxr_vulkan_extension.cpp` switch). Output must therefore already be sRGB-encoded. To show HDR/10-bit, create the layer swapchain with a different format, for example `R16G16B16A16_SFLOAT` (already mapped). **H**
- Cost note: the layer path is still one decoded-to-RGBA pass into a swapchain image. The compositor then samples it once more. The mesh path samples the decoded planes once into the eye buffer. Measure both in spike 03. **M**
- Baseline needing no patch: `TextureRect(Texture2DRD)` in a SubViewport behind `OpenXRCompositionLayerQuad`. This adds one 2D pass but works today. **H**

### `use_android_surface` (Quest video) as a model
- `OpenXRCompositionLayer.use_android_surface` + `android_surface_size`. With `XR_KHR_android_surface_swapchain`, `create_android_surface()` (`:798`) calls `xrCreateSwapchainAndroidSurfaceKHR`, which returns a `jobject Surface` that is exposed as `JavaObject` (`get_android_surface()`). The app hands the Surface to MediaPlayer/ExoPlayer, and the **runtime** consumes frames. Godot never acquires, renders or releases; `on_pre_render` just returns. `get_composition_layer()` submits `android_surface.swapchain`. Android only, under `#ifdef ANDROID_ENABLED`. **H**
- The model to copy: a `CompositionLayer` variant that owns a non-SubViewport swapchain, selected by a flag, with `update_swapchain_sub_image` returning that swapchain. Our equivalent would be `use_external_texture` + `set_external_texture(RID)`. **M**

---

## 5. Foveation / VRS on Vulkan

- The driver requests both `VK_KHR_fragment_shading_rate` and `VK_EXT_fragment_density_map` (+`_2`, `VK_QCOM_fragment_density_map_offset`). `_choose_vrs_capabilities()` (`rendering_device_driver_vulkan.cpp:1289`) **prefers FDM when vendorID is Qualcomm**. Turnip reports Qualcomm's vendor ID, so FDM is chosen whenever Turnip exposes it. FDM support landed in #99551 (4.5). **H** (code) / **L** (Turnip FDM exposure on this device).
- OpenXR path: with `XR_FB_foveation` + `XR_FB_foveation_vulkan` (+ `XR_META_vulkan_swapchain_create_info`, optional `XR_META_foveation_eye_tracked` gated by `xr/openxr/foveation_eye_tracked`), the **runtime supplies the density-map image** per swapchain image (`openxr_fb_foveation_extension.cpp:100`, `openxr_vulkan_extension.cpp` density_images). `OpenXRInterface::get_vrs_texture()` (`openxr_interface.cpp:1645`) returns it. 4.7 added subsampled images (#116220). **H**
- Without FB foveation, `get_vrs_texture()` falls back to Godot's own `XRVRS::make_vrs_texture()` (`servers/xr/xr_vrs.cpp`), built from eye foci (centre, or eye gaze). This works on any runtime when the GPU has FSR/FDM attachments. **H**
- The Mobile renderer uses it when `Viewport.vrs_mode = VRS_XR` (`render_forward_mobile.cpp`, `get_vrs_texture`). **H**
- Steam Frame lists all the FB/META foveation extensions (§0), so the full runtime-driven, eye-tracked FDM path should engage. For the video use-case, foveation only helps the projection layer (sphere mesh). It does nothing for composition layers. **M**

## 6. Cross-compiling linuxbsd arm64

- Official pipeline: `godot-build-scripts/build-linux/build.sh` sets `PATH=$GODOT_SDK_LINUX_ARM64/bin:...` and runs `scons platform=linuxbsd arch=arm64 production=yes debug_symbols=yes separate_debug_symbols=yes target=template_release`, with no CC override. The SDK is the Godot **buildroot** toolchain `aarch64-godot-linux-gnu_sdk-buildroot.tar.bz2` (gcc 15.2, **glibc 2.34**, X/Wayland/ALSA/Pulse/udev/fontconfig/speechd headers). It is fetched by `build-containers/Dockerfile.linux` from `github.com/godotengine/buildroot/releases/download/godot-2026.05.x-1/`; run `./relocate-sdk.sh` after unpacking. The main repo CI does not build arm64 Linux. **H**
- Our `build/build-frame.sh` uses Ubuntu's `aarch64-linux-gnu-g*` with `CC/CXX/LINK=` overrides. That works: `CC`, `CXX` and `LINK` are SCons options, and `use_sowrap=yes` dlopens system libraries. The binary then needs the host glibc version or newer. Recent SteamOS is fine. Switch to the buildroot SDK for portability. **H** (options) / **M** (glibc).
- **`openxr=yes` is not an option** in 4.7.2 or master. SCons warns about it and ignores it. The module is `module_openxr_enabled` (default on for linuxbsd unless `disable_xr=yes`; `modules/openxr/config.py`). **H**
- Slim template (4.7.2 options):
  ```
  scons platform=linuxbsd arch=arm64 target=template_release production=yes \
    vulkan=yes opengl3=no use_volk=yes accesskit=no sdl=no \
    disable_physics_2d=yes disable_navigation_2d=yes disable_navigation_3d=yes \
    deprecated=no module_mono_enabled=no build_profile=frame.gdbuild
  ```
  `production=yes` implies `lto=auto` and static libstdc++. Keep `wayland`/`x11` on: Godot still needs a DisplayServer window under gamescope. On master (4.8) also add `forward_plus_renderer=no` (#103100) to keep only Mobile. **H** (options) / **M** (exact set).
- Our module will need libdrm/libva or V4L2 headers. Kernel UAPI (`linux/videodev2.h`, `drm/drm_fourcc.h`, `linux/dma-buf.h`) comes with the toolchain's kernel headers, which may be too old for stateless HEVC/AV1 UAPI. Vendor current UAPI headers into the module. **M**

## 7. Display refresh rate

- `OpenXRInterface.display_refresh_rate` (get/set) and `get_available_display_refresh_rates()` (`openxr_interface.h:156`) are backed by `OpenXRDisplayRefreshRateExtension` (`XR_FB_display_refresh_rate`: enumerate/get/request, plus a refresh-changed event that calls `on_refresh_rate_changes`). **H**
- Runtimes that list it per the inventory: **Steam Frame (SteamVR 2.19)**, SteamVR Linux x64, Monado Linux, Quest. On SteamVR, Valve's Unity doc says the extension **only reports the current rate**: `set_display_refresh_rate()` is expected to be a no-op, and the rate is set through `vrpreferences.json` (`preferMinRefreshRate`). See `research-device.md` §5. The Index community post says the same. **M** for the Frame. Test in spike 04, because matching 48/72/90 Hz to the video frame rate matters for judder and power.

---

## Proposed engine patch list

**Spike 02 (dmabuf -> RD texture, zero CPU copy)**
1. `drivers/vulkan/rendering_device_driver_vulkan.cpp` `_initialize_device_extensions()`: request `VK_EXT_external_memory_dma_buf`, `VK_EXT_image_drm_format_modifier`, `VK_EXT_queue_family_foreign`, `VK_KHR_external_semaphore_fd`. Alternatively, cherry-pick #114940. In `_initialize_device()`, enable `samplerYcbcrConversion` when supported.
2. Same file and `.h`, plus `servers/rendering/rendering_device_driver.h`: add a `plane` (aspect) argument to `texture_create_from_extension` (#15116). Add a foreign-queue acquire barrier primitive.
3. `servers/rendering/rendering_device.{h,cpp}`: pass `plane` through. Add `texture_external_acquire(RID)` (barrier + tracker usage reset, recorded through the graph in `rendering_device_graph.{h,cpp}`). Add `frame_add_wait_semaphore()` (optional for the spike).
4. New `modules/hwvideo/`: dmabuf -> `VkImage` import (`vkGetMemoryFdPropertiesKHR`, `VkImportMemoryFdInfoKHR`, `VkImageDrmFormatModifierExplicitCreateInfoEXT`, dedicated allocation), buffer ring with frame-delay retention, `VideoStreamPlaybackHW` returning a `Texture2DRD`, and a YUV->RGB shader.

**Spike 03 (custom quad-layer swapchain)**
1. No OpenXR patch is needed for a first measurement. In `modules/hwvideo/`, add an `OpenXRExtensionWrapper` subclass registered with `register_composition_layer_provider`. It owns an `OpenXRSwapChainInfo`, acquires and blits (raster) in `on_pre_render`, and releases and returns an `XrCompositionLayerQuad` from `get_composition_layer`.
2. Optional, to reuse the node UI: `modules/openxr/extensions/openxr_composition_layer_extension.{h,cpp}` + `modules/openxr/scene/openxr_composition_layer.{h,cpp}`: add `use_external_texture`, modelled on `use_android_surface`.
3. Only if a compute write is wanted: `modules/openxr/extensions/platform/openxr_vulkan_extension.cpp` `get_swapchain_image_data()` adds `STORAGE_BIT`/`CAN_COPY_TO_BIT` when the swapchain usage allows it.

---

## Sources
- Godot source, tag 4.7.2-stable / master 95c0fa5: https://github.com/godotengine/godot (files cited inline)
- Steam Frame OpenXR inventory: https://github.com/KhronosGroup/OpenXR-Inventory/blob/main/runtimes/valve_steamvr_frame.json (also `valve_steamvr_linux64.json`, `monado_linux.json`)
- PR #114940 (additional Vulkan device extensions): https://github.com/godotengine/godot/pull/114940
- Proposal #15116 (plane aspect for texture_create_from_extension): https://github.com/godotengine/godot-proposals/issues/15116
- Proposal #13969 / #15210 (external memory extensions): https://github.com/godotengine/godot-proposals/issues/13969 , https://github.com/godotengine/godot-proposals/issues/15210
- Proposal #11567 (explicit semaphores): https://github.com/godotengine/godot-proposals/issues/11567
- Proposal #8049 (planar YUV textures): https://github.com/godotengine/godot-proposals/issues/8049
- PR #99551 (FDM), #99768 (XR_FB_foveation_vulkan), #112888 (META eye-tracked foveation), #116220 (subsampled), #103100 (renderer compile toggles), #109431 (layers multithread-safe)
- EIRTeam.FFmpeg: https://github.com/EIRTeam/EIRTeam.FFmpeg , docs https://eirteam-docs.readthedocs.io/en/latest/documentation/ffmpeg/ffmpeg_getting_started.html
- Build scripts: https://github.com/godotengine/godot-build-scripts/blob/main/build-linux/build.sh , https://github.com/godotengine/build-containers/blob/main/Dockerfile.linux , https://github.com/godotengine/buildroot
- SteamVR XR_FB_display_refresh_rate note: https://steamcommunity.com/app/250820/discussions/8/3121550424355682585/
- wlroots foreign-queue dmabuf acquire pattern: https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/master/render/vulkan/renderer.c
