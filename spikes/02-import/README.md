# Spike 02: dmabuf → VkImage → RenderingDevice, zero copy

Goal: show that a dmabuf written outside Vulkan (later: the V4L2 decoder from spike 01) can be sampled by Godot's
Mobile renderer with no CPU or GPU copy. One NV12 dmabuf is imported once as one multi-planar `VkImage`. Two
RenderingDevice textures are made from it, one per plane (Y as `R8`, CbCr as `R8G8` at half size). A spatial shader
converts Y'CbCr to RGB while it samples them.

This spike needs no decoder. `DmabufImage.import_test_pattern()` makes its own NV12 dmabuf (a DRM dumb buffer, or
`/dev/udmabuf` if that fails), writes a test pattern into it with the CPU, and imports it with `DRM_FORMAT_MOD_LINEAR`.

## What was patched (engine tree `~/src/godot-frame`, branch `frame/4.7`, not committed)

| File | Change |
|---|---|
| `drivers/vulkan/rendering_device_driver_vulkan.cpp` | On Linux, request `VK_EXT_external_memory_dma_buf`, `VK_EXT_image_drm_format_modifier`, `VK_EXT_queue_family_foreign` and `VK_KHR_external_semaphore_fd` (all optional). Query `samplerYcbcrConversion` and enable it if supported. `texture_create_from_extension()` takes a plane (-1, 0, 1 or 2); a plane sets the view aspect to `VK_IMAGE_ASPECT_PLANE_n_BIT`. Record `vk_image` in `TextureInfo`. Record the queue family of each command pool and command buffer. New `command_texture_external_acquire/release()` record the foreign queue family ownership transfer barrier. |
| `drivers/vulkan/rendering_device_driver_vulkan.h` | Declarations. Public `is_device_extension_enabled()` and `is_sampler_ycbcr_conversion_enabled()`. |
| `servers/rendering/rendering_device_driver.h` | `p_plane` on `texture_create_from_extension()`. New virtuals `command_texture_external_acquire/release()`, no-op by default. |
| `drivers/d3d12/rendering_device_driver_d3d12.{h,cpp}`, `drivers/metal/rendering_device_driver_metal.{h,cpp}` | New signature; fail if a plane is requested. (Not compiled here: Linux build only.) |
| `servers/rendering/rendering_device_graph.{h,cpp}` | New graph command `TYPE_TEXTURE_EXTERNAL_TRANSFER`. It is recorded as a change of usage (to `TEXTURE_SAMPLE` on acquire, to `GENERAL` on release), so it counts as a write and the graph orders it after earlier users and before later ones. The graph adds no barrier of its own for it: the driver command does the layout transition. |
| `servers/rendering/rendering_device.{h,cpp}` | `texture_create_from_extension(..., mipmaps = 1, plane = -1)`. New `texture_external_acquire(texture, aliases = [])` and `texture_external_release(texture, aliases = [])`: one barrier for the whole image, and the tracking of every alias (other plane views of the same image) is updated. These check that the aliases share the image and that acquire and release alternate. Script bindings included. |
| `servers/rendering/rendering_device.compat.inc` | Compatibility binding for the old 10-argument `texture_create_from_extension` (only built with `deprecated=yes`). |
| `modules/hwvideo/` (new) | `DmabufImage` (RefCounted, script-visible): `import_nv12()`, `import_test_pattern()`, `get_plane_rid()`, `acquire()`, `release()`, `free_image()`, `get_supported_nv12_modifiers()`. Builds on `linuxbsd` with Vulkan only. Uses kernel UAPI headers from the toolchain (no libdrm). |
| `drivers/vulkan/rendering_context_driver_vulkan.cpp` | Fix for a segfault at exit (stock 4.7.2 has it too). The Vulkan loader unloads the driver at `vkDestroyInstance`, but Godot's worker threads exit later and run thread-specific destructors that the driver registered. After instance creation, every loaded library that exports `vk_icdGetInstanceProcAddr` (drivers) or `vkNegotiateLoaderLayerInterfaceVersion` (layers) is promoted to `RTLD_NODELETE`. Linux only. Verified on the Frame: exit 0, log line `Vulkan: keeping /usr/lib/libvulkan_freedreno.so loaded until exit.` `VK_LOADER_DISABLE_DYNAMIC_LIBRARY_UNLOADING=1` gives the same result on stock builds. |

Not in the tree: `results/nouber-disable-ubershaders-turnip.patch`. It disables ubershaders on Turnip (Mobile and Forward+). Result on the Frame: meshes still not drawn, so it was reverted.

Also changed in this repo: `build/build-frame.sh` builds `template_debug` with `disable_path_overrides=no`. Without
that, an export template rejects `--path` and can't run a project folder. It also builds `template_debug` with
`debug_symbols=yes`, for symbolised crash backtraces.

### How `DmabufImage.import_nv12()` works

1. Checks that the extensions and `samplerYcbcrConversion` are enabled. Checks that the modifier is in the device's
   NV12 modifier list, is sampleable, and has as many memory planes as offsets were given. Checks
   `vkGetPhysicalDeviceImageFormatProperties2` for NV12 + modifier + `MUTABLE_FORMAT` + dmabuf import.
2. `vkCreateImage`: `G8_B8R8_2PLANE_420_UNORM`, `DRM_FORMAT_MODIFIER_EXT` tiling with explicit plane layouts,
   `MUTABLE_FORMAT` + `VkImageFormatListCreateInfo {NV12, R8, R8G8}` (required for mutable + modifier tiling), not
   disjoint, `SAMPLED`, external memory `DMA_BUF`, initial layout `UNDEFINED`.
3. `vkGetMemoryFdPropertiesKHR` for the memory types. Checks the dmabuf size with `lseek`. `dup` of the fd, then
   `vkAllocateMemory` with `VkImportMemoryFdInfoKHR` + `VkMemoryDedicatedAllocateInfo`, then `vkBindImageMemory`.
4. `texture_create_from_extension` twice: plane 0 as `R8_UNORM` (w×h), plane 1 as `R8G8_UNORM` (w/2×h/2).
5. Teardown: `free_image()` frees the RD textures at once. The image and memory go on a pending list and are destroyed
   once `frame_delay + 1` frames have been drawn. The list is checked on every import, acquire, release and free, which
   a decoder does every frame; there is no RenderingServer signal hook. At engine shutdown the list is dropped, not
   destroyed: the RenderingDevice still holds the plane views until it is finalized after the modules, so the process exit
   releases the images.

`import_test_pattern(w, h, "host")` skips the dmabuf: a linear NV12 image in host-visible Vulkan memory, written
through a mapping. It tests the plane views, the ownership-transfer graph command and the shader on any Vulkan driver.
`"host-split"` does the same with two images bound to the same memory, one per plane view, as `import_nv12()` makes them
for a UBWC dmabuf (see spike 03, "UBWC capture (Q08C)"). `--cycle` releases and acquires the image every frame, as a
player does. Both were run on lavapipe (2026-10-31): byte-identical screenshots, 149 cycles without errors.

The ownership protocol for a decoder: `acquire()` after `VIDIOC_DQBUF` returns the buffer, sample, `release()` before
`VIDIOC_QBUF` gives it back. Re-queue only after the RD frame in which `release()` was recorded has completed on the GPU.

## Verified vs not verified

Verified (in WSL, no GPU):
- The arm64 `template_debug` build compiles and links with all patches and the module, with no warnings. D3D12 and
  Metal were edited but not compiled.
- Under `qemu-aarch64-static`, headless: the binary starts, `DmabufImage` and the new `RenderingDevice` methods are
  registered with their defaults, and the project's GDScript parses. (Headless has no RenderingDevice, so nothing was
  imported.)
- On an x86_64 build of the same tree, on lavapipe (Mesa 25.2) under Xvfb, with `--device=host`: the quad shows the
  correct pattern (green top left, yellow top right, blue bottom left, pink bottom right, white grid), in both Mobile
  and Forward+, and the process exits cleanly. So the plane views, the graph's acquire command and the shader work.
  Lavapipe has no `VK_EXT_image_drm_format_modifier`, so the dmabuf import itself was not run there.

Verified on the Frame (run 1, Turnip, Mesa 26.3.0-devel):
- Sampleable NV12 modifiers: `0x0` (linear) and `0x500000000000001` (`DRM_FORMAT_MOD_QCOM_COMPRESSED`).
- A DRM dumb buffer can be made on `/dev/dri/card0` with gamescope running. `import_nv12` accepted the linear layout
  (pitch 2048, chroma at 2211840) and both plane textures were made, with no RD errors.

Not verified (needs the device):
- That the plane views give correct pixels on Turnip (run 1 screenshot showed no quad; see "What to look for").
- UBWC (`Q08C`, `DRM_FORMAT_MOD_QCOM_COMPRESSED`): plane views on a compressed image. Turnip refuses `MUTABLE_FORMAT`
  with that modifier when the view formats compress differently (R8 and R8G8), so `import_nv12()` falls back to two
  images, one view format each. This spike only imports linear; spike 03's PLAYER_UBWC tries the decoder's Q08C buffers.
- Validation-layer cleanliness of the first acquire (the image was created `UNDEFINED`, and the acquire barrier says
  `GENERAL`), and of the plane format list (see the assumptions below).

## Run on the Frame

From Windows (build first: `wsl -d Ubuntu -- bash build/build-frame.sh template_debug`):

```
scp build/out/godot.linuxbsd.template_debug.arm64 frame:spike02/
scp -r spikes/02-import/project frame:spike02/
```

On the Frame (`ssh frame`):

```
cd ~/spike02
chmod +x godot.linuxbsd.template_debug.arm64

# Flat camera first (no SteamVR needed). --quit-after makes it exit by itself over ssh.
./godot.linuxbsd.template_debug.arm64 --path project --verbose --xr-mode off -- --no-xr --quit-after=300

# Then in the headset, with SteamVR running:
./godot.linuxbsd.template_debug.arm64 --path project --verbose

# With validation layers, if VK_LAYER_KHRONOS_validation is installed on the device:
VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation ./godot.linuxbsd.template_debug.arm64 --path project --verbose --xr-mode off -- --no-xr --quit-after=300
```

Do not pass `--rendering-driver vulkan` on its own: when a driver is given on the command line without
`--rendering-method`, Godot ignores the project's renderer and picks Forward+ (`main/main.cpp`, "Set a default
renderer if none selected"). The project already selects Vulkan and Mobile. If you need the flag, also pass
`--rendering-method mobile`. The first line of output must say `Forward Mobile`.

The `template_debug` binary now has debug symbols (about 1.2 GB), so a crash prints a symbolised backtrace.

If the flat run has no display (ssh session), set `WAYLAND_DISPLAY`/`DISPLAY` from the desktop session, or add
`--display-driver wayland`. Other user arguments: `--device=/dev/dri/renderD128` etc. (dumb buffers need a KMS
`card` node).

## What to look for

Console:
- `Sampleable NV12 modifiers: 0x0, ...`: the list Turnip gives. Note whether `0x0` (linear) is there, and which
  `0x05...` (Qualcomm) modifiers are there. That decides the spike 01 export path.
- `DmabufImage: test pattern 1920x1080 in a DRM dumb buffer|udmabuf, pitch ..., chroma at offset ...`
- With `--verbose`: `DmabufImage: imported 1920x1080 NV12, modifier 0x0, ...` and the memory plane layouts that the
  driver reports. These should equal what we passed in.
- Any `ERROR:` from `import_nv12` names the step that failed (modifier not listed, format query refused, plane layout
  refused, import refused).

On the quad (1.92 m × 1.08 m, 2 m in front, at eye height):
- **Correct:** brightness rises from left to right, with a white grid of 8×8 cells. The colour changes in both
  directions: dark green at top left, yellow at top right, blue at bottom left, pink/magenta at bottom right. The
  centre is mid grey.
- **Plane 1 aliases plane 0** (the bug that proposal #15116 describes): the colour changes only from left to right,
  and the grid lines show up in the colour as well as the brightness.
- **Grey or garbage, or stripes:** wrong pitch or offset, or the driver ignored the explicit layout. Compare with the
  verbose plane layouts.
- **Black or uniform:** the import or the acquire failed (see errors), or the contents were lost to a layout
  transition from `UNDEFINED`.
- **No quad at all (only the clear colour):** not an import problem. Even with no textures the quad draws (pink, as
  with Godot's default white textures). Check that the window is actually drawn (`can_draw`), or render into an
  offscreen viewport. The verbose line `MultiUmaBuffer 'RENDER_LIST_OPAQUE' used a total of 0 buffers` is not evidence:
  it also appears when the quad is drawn correctly (it refers to a render list that was never used).
- To check the plane views and shader without a dmabuf, run with `-- --no-xr --device=host`.
- Validation errors to look for: `VUID-VkImageMemoryBarrier-*` (ownership transfer or layout), `VUID-VkImageCreateInfo-*`
  (plane layouts, format list), `VUID-VkImageViewCreateInfo-*` (plane view formats).

## Assumptions not verified (spec or driver)

- The view format list `{G8_B8R8_2PLANE_420_UNORM, R8_UNORM, R8G8_UNORM}` is valid. VUID-VkImageCreateInfo-pNext-06722
  requires the listed formats to be "compatible" with the image format. Plane formats are compatible with the plane,
  not with the multi-planar format's class. The validation layers accept this, as far as we know. Some drivers may not.
- Image barriers on a non-disjoint multi-planar image use `VK_IMAGE_ASPECT_COLOR_BIT`, which covers every plane.
  The graph's own barriers for the plane textures also use COLOR.
- Acquire from `VK_QUEUE_FAMILY_FOREIGN_EXT` with `oldLayout = GENERAL` keeps the contents (what wlroots does),
  including on the first acquire of an image created with `UNDEFINED`.
- Turnip accepts a linear NV12 layout with a 256-byte-aligned pitch and the chroma plane at a 4 KiB-aligned offset.
- `vkGetDeviceProcAddr` and volk's loader trampolines are enough for the device functions (Godot only calls
  `volkLoadInstance`).
- The CPU writes reach the GPU: dumb buffers on msm are write-combined; `DMA_BUF_IOCTL_SYNC` is called around the
  writes. If udmabuf memory is mapped cached on the GPU side, the pattern may be stale.
- The acquire barrier waits on nothing (`srcStage = TOP_OF_PIPE`). This is correct only if the producer has finished
  before the frame is submitted: V4L2 `DQBUF` gives that. With a producer fence, wait for it first (sync_file `poll`,
  or the `frame_add_wait_semaphore` patch in `docs/research-godot.md` §2).
