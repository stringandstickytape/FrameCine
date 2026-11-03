# Research: Godot 4.7.2 on Steam Frame Turnip (3D not drawn, crash on exit)

Date: 2026-10-30. Web research only; nothing run on the device.
Confidence labels: HIGH = read in source or primary doc; MED = strong evidence, not reproduced; LOW = inference.

## 1. Others render Godot 3D on the same GPU/driver (key context)

- Godot issues filed from a Steam Frame show 3D rendering on stock 4.7.2 Mobile with the same stack:
  "Godot v4.7.2.stable - SteamOS holo on Wayland - X11 display driver ... Vulkan (Mobile) - integrated
  Turnip Adreno (TM) 750". The screenshots show 3D scenes. HIGH (that 3D renders), MED (that their Mesa build matches ours).
  https://github.com/godotengine/godot/issues/124165 , https://github.com/godotengine/godot/issues/124141
- In #124141 the same user also ran the project "in non-xr mode (traditional windowed app)" and reported only
  that VRS had no effect, not missing 3D. MED. https://github.com/godotengine/godot/issues/124141 (first comment)
- Those apps were deployed the normal way (Steam / SteamOS Devkit Client), which also runs under gamescope
  `--backend openvr`. So gamescope alone does not stop Godot 3D. MED. Valve's Godot page:
  https://partner.steamgames.com/doc/steamhardware/steamframe/engines/godot
- Conclusion: the bug is probably in how our process is started (ssh, its environment) or in our project,
  not "Godot cannot draw 3D on Turnip". MED.
- Known Frame + Godot rendering bugs (none match "no 3D at all"):
  - #124165 MSAA 2x + foveation -> garbled image (open, still on master). HIGH.
  - #124141 / #124520 FDM foveation only works when subpasses are off (FXAA on); subsampled images not yet
    supported by SteamVR on Frame (Valve dev comment). Fix PR #124811 (open). HIGH.
    https://github.com/godotengine/godot/pull/124811
  - #124314 `thread_model = Separate` gives worse frame times on Frame (xrBeginFrame blocks). HIGH.
  - #124969 Adreno 750 (Qualcomm driver, Android) black squares from fp16 specular. Not Turnip. HIGH.
- Older: #87801 "Meshes not rendered on Android, Mobile renderer" (Adreno 616, Qualcomm driver) is caused by
  vkCreateGraphicsPipelines failing with logged errors. We see no errors, so probably not the same. MED.
  https://github.com/godotengine/godot/issues/87801

## 2. Valve's FDM layers and the ssh environment

- SteamOS on Frame ships `VK_LAYER_VALVE_rpo` and `VK_LAYER_VALVE_fdm_injection` (explicit layers). Steam
  turns them on per game with `VK_INSTANCE_LAYERS=VK_LAYER_VALVE_rpo:VK_LAYER_VALVE_fdm_injection` and
  `FDM_DEBUG=enable`. There is also an implicit OpenXR layer `XR_APILAYER_VALVE_fdm_injection`
  (`/usr/share/openxr/1/api_layers/implicit.d/`), turned off by `DISABLE_VULKAN_FDM_INJECTION_LAYER=1`. HIGH.
  https://github.com/ValveSoftware/SteamVR-for-Linux/issues/972
- That issue (fixed in SteamOS 20261007): the layer hung vkCreateDevice when launched outside Steam, and it
  hangs again if `/usr/share` appears twice in `XDG_DATA_DIRS`. HIGH (as reported).
- Community reverse-engineering (FramePort): the Vulkan layer also injects a fragment density map into
  `vkCmdBeginRendering` passes. Turning off `VALVE_rpo` fixed "jumping polygons" in some UE games. MED
  (third-party notes). https://github.com/spoopyghosty0/frameport/blob/main/docs/FRAME_RUNTIME.md
- What "fdm_injection" is: Valve's eye-tracked foveation. It makes per-eye density maps at xrCreateSwapchain
  and adds FDM to render passes. It applies to OpenXR apps; a plain X11 app is only affected if the Vulkan layer
  is named in `VK_INSTANCE_LAYERS`. MED.
- If the ssh shell copied gamescope's or Steam's environment to get `DISPLAY`, it may also have copied
  `VK_INSTANCE_LAYERS` / `FDM_*`. LOW (not verified).

## 3. Mesa / Turnip

- No Mesa issue mentions Godot + Turnip drawing nothing. HIGH (searched the GitLab API for godot/turnip/freedreno).
- The Frame's Mesa is a Valve fork: `abc426bb62` and the 0.5.x `e07916b45f` are not upstream commits. Upstream
  fixes may or may not be in it. HIGH. Valve doc says `mesa_version` prints the build; a debug Mesa package
  exists (`deckard-mesa-android-aarch64-debug`, for the Android container).
  https://partner.steamgames.com/doc/steamhardware/steamframe/debugging
- Relevant 2026 Turnip fixes (all FDM-related, so they matter only if an FDM is active):
  - !44274 "Fix missing primitives in FDM due to sample locations mismatch" (merged 2026-09-15). HIGH.
    https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44274
  - !41539 "Don't enable FDM when FDM attachment is UNUSED" (merged 2026-05-14). HIGH.
  - !45670 "Fix fdm store + custom_resolve when HW bin scaling is disabled" (open). HIGH.
  - #15453 "regression: failures around subpass clears with FDM" (open). A lost depth clear would
    give exactly "clear colour, no geometry" with reversed-Z. LOW (as a match).
    https://gitlab.freedesktop.org/mesa/mesa/-/issues/15453
- Other open a7xx bugs: #15792 per-draw transient corruption on a750; #15441 UBO->const lowering flicker;
  #15568 early preamble glitches. HIGH that they exist, LOW that they match.
- Current upstream `TU_DEBUG` flags (tu_util.cc) include, besides the ones already tried: `nofdm`, `nocb`
  (no concurrent binning, a7xx, added 2025-10), `flushall`, `syncdraw`, `nomultipos`, `nolrzfc`,
  `nobinmerging`, `rast_order`, `3d_load`. `IR3_SHADER_DEBUG`: `nouboopt`, `nopreamble`,
  `noearlypreamble`, `nofp16`, `nodescprefetch`, `noaliastex`, `noaliasrt`, `nocache`. HIGH (upstream).
  The Valve fork may lack some. https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/src/freedreno/vulkan/tu_util.cc

## 4. Exit crash (TLS destructor after ICD dlclose)

- Godot 4.7.2 order in `Main::cleanup()`: `finalize_display()` (destroys RenderingDevice -> vkDestroyInstance ->
  loader dlcloses the ICD) runs before `unregister_core_types()`, which does `memdelete(worker_thread_pool)`.
  So WorkerThreadPool threads exit after the driver is unmapped. Master has the same order. HIGH (read source:
  main/main.cpp, core/register_core_types.cpp at tag 4.7.2-stable).
- `__nptl_deallocate_tsd` runs `pthread_key_create` destructors (not C++ `thread_local`, which glibc pins).
  So Turnip, or a library linked into it, made a pthread key with a destructor. HIGH (glibc mechanism), LOW (which code).
- Same bug class in Mesa: sysprof TLS destructor crash on unload (#13571; fix by requiring
  sysprof-capture >= 4.49, !38347; a `-z nodelete` MR !36978 was closed). Perfetto thread outliving dlclose
  (!17454). atexit after dlclose (#11085). Open generic fix !31185 "util: fix crash on dlclose for OpenGL/Vulkan ICD".
  HIGH. https://gitlab.freedesktop.org/mesa/mesa/-/issues/13571 ,
  https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/31185 , https://gitlab.freedesktop.org/mesa/mesa/-/issues/11085
- Loader option: `VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1` stops the loader from unloading drivers in
  vkDestroyInstance (loader built with headers >= 1.3.259). HIGH.
  https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md
- No Godot issue or PR about this crash with Turnip/Mesa was found. Related open: #124799 (crash on exit with
  Separate render thread). HIGH (search result).

## 5. Godot 4.7 switches

- There is no project setting or CLI flag to turn off ubershaders. It is only a driver workaround:
  `driver_workarounds.disable_ubershaders` in `RenderingDeviceDriverVulkan::_check_driver_workarounds`, true only for
  Qualcomm driver compiler "EV031.32.02.". To force it, patch that line to `true`; the renderer then waits
  for specialized pipelines. Verbose log prints "Ubershaders: Disabled/Enabled". HIGH (source).
- Mobile subpass post-process (`using_subpass_post_process` in render_forward_mobile.cpp) is turned off by
  FXAA, glow and other effects. Enabling FXAA is the documented way to leave the subpass path (#124141). HIGH.
- FDM is used only when `rendering/vrs/mode` is not 0 or XR provides a VRS texture; Godot prefers FDM over
  FSR on Qualcomm. With VRS mode 0 and no XR, no FDM attachment is used. HIGH (source).
- `rendering/driver/depth_prepass/disable_for_vendors` defaults to "PowerVR,Mali,Adreno,Apple", so Forward+
  has no depth prepass here. HIGH.
- Useful flags: `--gpu-validation` (Khronos validation layer; Linux glibc copies exist on Frame per FramePort
  notes, MED), `--generate-spirv-debug-info`, `--rendering-method mobile|forward_plus`. HIGH.

## 6. Valve docs

- Valve supports Godot on Frame only through OpenXR (`use_xr`, XROrigin3D/XRCamera3D). The docs do not cover a flat
  X11 Vulkan app started from ssh. HIGH. https://partner.steamgames.com/doc/steamhardware/steamframe/engines/custom
- RenderDoc is installed on Frame: launch with `ENABLE_VULKAN_RENDERDOC_CAPTURE=1` (and `EnableFrameEndMarkers=1`
  if it shows "Not Presenting"). HIGH. https://partner.steamgames.com/doc/steamhardware/steamframe/debugging

## Things to try, in priority order

1. Check the environment: `env | grep -E '^(VK_|FDM|FOVE|DISABLE_VULKAN|MESA|TU_|IR3|ENABLE_|XDG_DATA)'`, then run once with
   `VK_LOADER_DEBUG=layer,driver` to list loaded layers. Then run with `VK_INSTANCE_LAYERS=` (empty) and
   `DISABLE_VULKAN_FDM_INJECTION_LAYER=1`.
2. Compare to a known-good setup: (a) run `vkcube --wsi xlib` (it uses a depth-tested cube) the same way (ssh,
   DISPLAY=:0); (b) run the MRP from #124141 (`frag_dens_map_test.tar.gz`), which renders on Frame; (c) start our
   build through the SteamOS Devkit Client / Steam instead of ssh.
3. Tests inside the project (one change each): quad material `no_depth_test = true`; a ShaderMaterial with
   `POSITION = vec4(VERTEX.xy, 0.5, 1.0);` (skips camera matrices); `get_viewport().debug_draw = DEBUG_DRAW_OVERDRAW`;
   FXAA on (no Mobile subpass); MSAA off. If `no_depth_test` makes the quad appear, the depth clear or test is broken (compare Mesa #15453).
4. RenderDoc capture on device (`ENABLE_VULKAN_RENDERDOC_CAPTURE=1`, or `renderdoccmd capture` over ssh): check that the
   draw exists, its viewport/scissor, depth clear value and compare op, and the vertex shader output.
5. `--gpu-validation` (needs VK_LAYER_KHRONOS_validation on the device); look for errors on the 3D pass.
6. More driver toggles: `MESA_SHADER_CACHE_DISABLE=true`; `TU_DEBUG=nofdm`, `nocb`, `flushall,syncdraw`, `nomultipos`,
   `nolrzfc`; `IR3_SHADER_DEBUG=nouboopt,nopreamble,noearlypreamble,nofp16`. Delete Godot's
   `user://vulkan` pipeline cache between runs.
7. Engine patch: force `driver_workarounds.disable_ubershaders = true` in
   `drivers/vulkan/rendering_device_driver_vulkan.cpp` (rules out an ubershader miscompile).
8. Exit crash: set `VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1` (no LD_PRELOAD needed). Engine fix options:
   at startup, `dlopen("libvulkan_freedreno.so", RTLD_NOW | RTLD_NODELETE)` on Linux; or finish WorkerThreadPool
   before `finalize_display()`. To find the key's owner: in gdb, `break pthread_key_create` with a backtrace and keep the
   calls from libvulkan_freedreno.so (perfetto/sysprof/util code are the likely sources).
9. Mesa version: if a newer SteamOS (0.5.x, Mesa `e07916b45f`) is available, test it. Upstream Turnip fixes after
   2026-09 (!44274, !45670) are FDM-only, so a newer Mesa probably will not fix a non-FDM path.
