# Spike 02 findings — 2026-10-30, Steam Frame (SteamOS 0.4.5, kernel 6.18, Mesa 26.3.0-devel Turnip a750)

Run context: launched from ssh inside the gamescope session (`DISPLAY=:0 --display-driver x11`), SteamVR running.

## RESULT (23:39): spike 02 objective verified on device

With the patched tree built at `-O0` (`PATCHED_O0`), `spikes/02-import/project` renders the NV12 test pattern correctly on
the quad (`nv12_pattern_O0_offscreen.png`): corner colours green/yellow/blue/pink, grey centre, white 8×8 grid, luma ramp —
i.e. plane 0 and plane 1 are sampled from the right planes of one dmabuf-backed multi-planar `VkImage` via
`texture_create_from_extension(..., plane)`, with `texture_external_acquire` and the YUV→RGB shader. Zero CPU copies.
**23:50 — verified in VR:** the same project in `--xr-mode on` with the headset worn shows the pattern correctly on the
quad in both eyes (user-confirmed: colours right, no tearing). The XR eye-buffer path behaves like the flat window.
`run_xr_p0.log`: session IDLE → READY → SYNCHRONIZED → VISIBLE → FOCUSED once the headset was worn, back to VISIBLE /
SYNCHRONIZED when it came off, 12000 frames then clean exit (0; two stock-Godot exit warnings: a spatial-entity signal
disconnect and 2 leaked `InteractionProfile` RIDs). OpenXR 1.1 instance creation fails and Godot falls back to 1.0 as before.
Still to test: the UBWC modifier (`0x0500000000000001`) with decoder-exported `Q08C` buffers.

## What works

- **DmabufImage import on Turnip (the point of the spike): works.** Sampleable NV12 modifiers reported: `0x0` (linear)
  and `0x0500000000000001` (QCOM UBWC → Q08C importable). DRM dumb buffer created on `/dev/dri/card0` under gamescope,
  `import_nv12` succeeded (memory type 0), both plane views created, no RD errors. `run1_forwardplus_noxr.log`.
- **OpenXR from an ssh-launched process: works.** Instance 1.0.54 (1.1 creation fails, Godot falls back), session
  IDLE → READY → SYNCHRONIZED, head pose valid, Valve's `fdm_injection` API layer attaches (swapchain 1728 px).
  Runtime extensions match the Khronos inventory (FB/META foveation, `XR_FB_display_refresh_rate`, `XR_MND_headless`…).
  `run_xr1.log`.
- 2D rendering, the 3D clear, the **procedural sky** (fullscreen pass), and a **Polygon2D** (vertex-buffer 2D draw).

## Problem 1 — exit segfault: ROOT CAUSE FOUND, stock Godot

gdb: thread "WorkerThread 0" in `__GI___nptl_deallocate_tsd` → TLS destructor at an unmapped address.
`LD_PRELOAD=/usr/lib/libvulkan_freedreno.so` → clean exit. The Vulkan loader dlcloses the Turnip ICD at
`vkDestroyInstance` while WorkerThreadPool threads that ran driver code (pipeline compilation) still hold TLS dtors.
Reproduces on the unpatched `4.7.2-stable` baseline. Fix: pin the ICD (RTLD_NODELETE) or finish the worker pool before
destroying the instance — engine patch pending.

## Problem 2 — 3D mesh draws produce nothing: ROOT CAUSE = strict-aliasing UB in stock Godot, exposed by gcc 13 aarch64 -O2

**Resolved 00:03 (2026-10-31), fixed in the fork.** `SceneState::InstanceData` (`render_forward_mobile.h`, and its copy in
`render_forward_clustered.h`) fills its `float[]` members through type-punned pointers:

```cpp
*reinterpret_cast<Vector3 *>(compressed_aabb_position) = p_aabb.position;
*reinterpret_cast<Vector3 *>(compressed_aabb_size) = p_aabb.size;
*reinterpret_cast<Vector4 *>(uv_scale) = p_uv_scale;
*reinterpret_cast<Rect2 *>(lightmap_uv_scale) = p_rect;
```

`-Wstrict-aliasing=1` flags exactly those four lines. In `_fill_instance_data` the stack `InstanceData` is then copied into
the mapped instance SSBO. In the aarch64 `-O2` code (Ubuntu `aarch64-linux-gnu-g++` 13.3.0-6ubuntu2~24.04.1; Godot passes no
`-fno-strict-aliasing` on linuxbsd, so GCC's `-O2` default applies) GCC schedules the 16-byte loads for
that copy *before* the punned stores to `compressed_aabb_*` and `uv_scale`, which strict aliasing permits because a
`Vector3`/`Vector4` store is assumed not to alias `float`. The GPU receives stale stack bytes. The vertex shader always does
`vertex = vertex_in * compressed_aabb_size + compressed_aabb_position` (`scene_forward_mobile.glsl`), so a garbage size
collapses every 3D vertex: the draw is issued and rasterises nothing. That explains the whole table below: every mesh path
fails (including the clip-space shader, which still reads the decoded `VERTEX`), sky and 2D are untouched, Forward+ fails the
same way, `-O0`/`-O1` and `-fno-strict-aliasing` "fix" it, x86 works only because its instruction scheduling happens to keep the
stores first, and Godot's official buildroot gcc-15 templates presumably get lucky the same way.

Bisect (control project, Mobile renderer, 8611 B screenshot = no 3D, 8679 B = quad drawn): whole engine `-O0` → renders;
only `servers/rendering/renderer_rd/` at `-O0` → renders; of its parts only `forward_mobile/ + forward_clustered/` → renders;
only `render_forward_mobile.cpp` → renders (`scene_shader_forward_mobile.cpp` → no); that one file at `-O2 -fno-strict-aliasing`
→ renders, at `-O2` without vectorisation → no, at `-O1` → renders.

Fix (fork `frame/4.7`, commit `baa246e765`): the setters always use the element-wise stores that the `REAL_T_IS_DOUBLE` branch already used; the
`#ifdef` and the casts are gone in both renderers (+4/−36). `-Wstrict-aliasing` is clean and the `-O2` code performs all
`InstanceData` stores before the SSBO copy. Verified on device at full `-O2`: control quad (`ctrl_O2_fixed.png`) and the NV12
test pattern (`nv12_pattern_O2_fixed_window.png`). `build-frame.sh` is back to `optimize=speed`.

Side note: Godot's SConstruct already passes `-ffp-contract=off` to every compile, so the `FPCONTRACT` build below was
identical to the baseline; that test was void rather than negative.

### Elimination chain (kept for the record)

**Resolved 23:28:** the identical unpatched 4.7.2 tree built with `dev_build=yes optimize=none` (`-O0`, same Ubuntu
aarch64-linux-gnu-gcc 13 cross toolchain) **renders the quad** (`ctrl_x_devo0.png`). The `-O2` build does not. 4.6-stable built
with the same toolchain at -O2 also fails. x86 builds of the same tree are fine. Steam Frame users with Godot's official
(buildroot gcc-15) templates report working 3D. → aarch64-specific codegen issue in our build; bisect in progress (glslang
first, then renderer_rd / drivers/vulkan / core; candidate flags: `-ffp-contract=off`, `-fno-strict-aliasing`, no autovectorisation).

Further A/B (23:45): `optimize=none dev_build=no` renders (so it is the optimiser, not `DEV_ENABLED`); `-O2 -ffp-contract=off`
does not; glslang ruled out (device `-O2` build produces byte-identical SPIR-V to x86, and the `-O0` run reused the `-O2`
build's cached SPIR-V). Per-directory `-O0` bisect of the engine in progress.

Bisect step 1 (23:51): everything at `-O2` except `servers/rendering/renderer_rd/**` at `-O0` → **renders**
(`ctrl_O0_renderer_rd.png`). The culprit is in `renderer_rd`; narrowing by subdirectory / file next.
Step 2 (23:58): only `forward_mobile/ + forward_clustered/` at `-O0` renders; `storage_rd/`, the top-level files and
`effects/ + environment/` at `-O0` do not. Splitting `render_forward_mobile.cpp` vs `scene_shader_forward_mobile.cpp` next.
Step 3 (00:03): **`render_forward_mobile.cpp` alone at `-O0` renders**; `scene_shader_forward_mobile.cpp` alone does not.
Leading explanation (agent's reading of the source): `SceneState::InstanceData` (`render_forward_mobile.h`) fills its
`float[]` members through `reinterpret_cast<Vector3 *>` / `Rect2 *` / `Vector4 *` stores (strict-aliasing violation) before
`_fill_instance_data` copies the struct into the mapped instance SSBO; gcc 13 aarch64 at `-O2` may legally drop or reorder
those stores, corrupting the per-instance transform/AABB. Forward+ has the identical pattern (and also failed). Flag variants
(`-fno-strict-aliasing`, no vectorisation, `-O1`) and an `-O2` source fix (memcpy/element-wise stores) are being built.
Step 4 (00:12), `render_forward_mobile.cpp` alone, rest `-O2`: `-O2 -fno-strict-aliasing` **renders**; `-O2 -fno-tree-vectorize
-fno-tree-slp-vectorize` does not; `-O1` renders (gcc only enables `-fstrict-aliasing` from `-O2`). **Confirmed: a strict-aliasing
miscompile of the `InstanceData` setters.** Source fix (element-wise stores, both renderers) being built for `-O2`.

Everything below is the elimination chain that led there.

Symptom: Camera3D + unshaded red QuadMesh 2 m ahead renders as clear colour only; everything else renders.

Bisected (all on the unpatched baseline unless noted; "no" = 8611-byte clear-colour screenshot):

| Test | 3D quad? |
|---|---|
| patched build / baseline build | no / no |
| Mobile / Forward+ | no / no |
| `--no-import --plain` (no DmabufImage, StandardMaterial3D) | no |
| offscreen SubViewport screenshot; `window_can_draw()` = true | no |
| `no_depth_test` + cull off + render_priority; quad ×20 | no |
| hand-built ArrayMesh float positions only / compressed attrs / ImmediateMesh | no / no / no |
| `TU_DEBUG` = sysmem, gmem, noubwc, nolrz, forcebin, nobin, noconform, flushall+syncdraw, nodynamic, nomultipos, nolrzfc, rast_order | no |
| `IR3_SHADER_DEBUG` = nopreamble, nouboopt, nofp16, spillall, nodescprefetch (+ Mesa/Godot shader caches cleared) | no |
| `VK_LOADER_LAYERS_DISABLE` = ~implicit~ (fossilize, MangoHud, gamescope WSI, vram_report_limit) | no |
| `--gpu-validation` (no Khronos validation layer on device, so inert) | no |
| **ProceduralSky WorldEnvironment** (fullscreen pass, no mesh) | **yes** |
| **Polygon2D** (2D, real vertex buffer) | **yes** |
| api_dump frame 100: 3 render passes, 3× `vkCmdDrawIndexed` + 1× `vkCmdDraw`, vertex buffers bound | draw IS issued |
| api_dump detailed: quad draw = 6 indices uint16, 3 vertex bindings (offsets 0/48/0), 4 descriptor sets, 16-byte push constants, viewport 1920×1080, depth clear 0 (reversed-Z) | CPU side sane |
| **ubershaders disabled** (`NOUBER` build, Turnip workaround) | no |
| **clip-space vertex shader** (`POSITION = vec4(VERTEX.xy*0.8, 0.5, 1)`, unshaded, no depth test, no cull) | no |
| stock Mesa 26.2.2 Turnip from the Flatpak runtime via `VK_DRIVER_FILES` (Vulkan 1.4.354) | no |
| Steam's env: `ENABLE_GAMESCOPE_WSI=1` + `GAMESCOPE_WAYLAND_DISPLAY` (gamescope surface created) | no |
| Valve layers `VK_LAYER_VALVE_fdm_injection` (loads) / `VK_LAYER_VALVE_rpo` (fails to load) | no |
| **vkcube over ssh** (LunarG screenshot layer capture) | **yes** — plain Vulkan 3D with depth works in this launch context |

Exit crash: the engine fix (pin Vulkan ICDs/layers with RTLD_NODELETE after instance creation, `rendering_context_driver_vulkan.cpp`)
is **verified on device** ("Vulkan: keeping /usr/lib/libvulkan_freedreno.so loaded until exit.", exit 0). The documented loader
env `VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1` also works as a no-patch workaround.

Research (`docs/research-turnip.md`): Steam Frame users report working 3D on stock 4.7.2 Mobile / X11 / Turnip 750 (godot
#124165, #124141) with Godot's official templates (buildroot gcc 15). Ours is built with Ubuntu's aarch64 gcc 13 and the
same tree renders correctly on x86 — so a compiler-dependent aarch64 miscompile in the engine (e.g. the bundled glslang that
produces the scene shader's SPIR-V at runtime) is the leading hypothesis. Tests in flight: unoptimized `-O0` build, 4.6-stable
build, and the official 4.7.2 arm64 binary (needs a human launch).

Conclusion so far: the quad's draw reaches the GPU with vertex buffers bound and produces no fragments; vertex fetch
works for 2D; depth, culling, layers and Turnip's tiling/compiler knobs are not it. Remaining suspects: the 3D scene
shader pipeline (ubershader path — `NOUBER` build variant pending), the instance-data SSBO / scene uniform sets, or a
Mesa 26.3-devel regression specific to that shader. A RenderDoc capture (`renderdoccmd` 1.46 is on the device; no
analysis tooling on the PC yet) is the next step if the ubershader variant doesn't resolve it.

Noted for later: in XR mode the window mirror is a 1728×1728 black square; whether the eye buffers show the quad is
untested (same scene shader, so expected to fail until Problem 2 is fixed).
