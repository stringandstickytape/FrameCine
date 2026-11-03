# Spike 04: the Q10C probe

Question: which VkFormat and DRM format modifier does the headset's Turnip take for the decoder's Q10C buffers (UBWC-compressed
TP10, the only 10-bit output of Valve's stock iris module)? One run on the headset answers it. The engine
(`DmabufImage.import_ycbcr()`, PLAYER_Q10C) already tries every candidate the driver lists. The probe says which one gives
the right picture, and how close it is to FFmpeg's decode of the same frame.

Not to be confused with `spikes/04-power` (battery logging), which has the same number.

## Background: what the public Mesa source says

Read in upstream Mesa `main` of 2026-10-31 (`0618bfe0ff`) and in our kernel source trees. The headset runs Valve's build
`deckard-mesa-linux-aarch64 26.3.0_devel+gitabc426bb-1`; commit `abc426bb` is not upstream, so Valve may carry patches
that are not in this list.

- **Upstream Turnip has no TP10.** The hardware formats `FMT6_TP10`, `FMT6_TP10_Y` and `FMT6_TP10_UV` exist only in
  the register XML (`src/freedreno/registers/adreno/a6xx_enums.xml`). No code in `src/freedreno` or `src/gallium` uses
  them, and no commit message mentions TP10.
- **The only modifiers Turnip lists are LINEAR and `DRM_FORMAT_MOD_QCOM_COMPRESSED`** (`0x0500000000000001`).
  `tu_GetPhysicalDeviceFormatProperties2()` adds QCOM_COMPRESSED for every format with optimal tiling where
  `tiling_possible()` and `ubwc_possible()` hold. `tu_get_image_format_properties()` accepts only those two modifiers
  for `VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT` (any other: `VK_ERROR_FORMAT_NOT_SUPPORTED`). QCOM_TILED2 and
  QCOM_TILED3 (`0x...02`, `0x...03`) appear only in the GL driver (`freedreno_resource.c`, `fd6_resource.cc`) and in
  `tu_device.cc` for Android buffers.
- **`G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16` is P010 to Turnip.** `tu6_plane_format()` maps its planes to the
  16-bit `R10X6` and `R10X6G10X6` formats (R16 and R16G16 in the hardware), so with QCOM_COMPRESSED Turnip lays it out
  as UBWC P010 (2 bytes per sample), not TP10 (4 bytes per 3 samples). For a 3840x1600 frame that image needs about
  18.5 MB; the decoder's Q10C buffer is 12,369,920 bytes. Upstream Turnip would refuse the import: the image is larger
  than the dmabuf. Only `G8_B8R8_2PLANE_420_UNORM` has special UBWC handling (`Y8` for plane 0).
- **`drm_fourcc.h` has no QCOM_TIGHT upstream** (Mesa's copy and the 6.18 and 7.2 kernel headers: COMPRESSED 1,
  TILED3 3, TILED2 2). Android's downstream kernel header defines `QCOM_DX` (2), `QCOM_TIGHT` (4) and `QCOM_TILE`
  (8). There, TP10 UBWC is `NV12 + COMPRESSED|DX|TIGHT` (`0x0500000000000007`) and P010 UBWC is `COMPRESSED|DX` (3).
  Upstream later gave 2 and 3 other meanings (TILED2, TILED3).
- **iris's Q10C layout** (`vpu_iris3_buffer.c`, `iris_vdec.c` in `~/src/deckard-kernel/work-6.18.0-ge66bc2ca6f8c-stock`):
  width rounded up to 192, height to 16, pitch `align(W x 4/3, 256)`. The buffer holds Y metadata, then Y, then UV
  metadata, then UV, each padded to 4 KiB. Tiles are 48x4 samples (Y) and 24x4 pairs (UV), with metadata pitches of
  `align(W/48, 64)` and `align(W/2/24, 64)`. For 3840x1600: pitch 5120, Y metadata 53,248 bytes at 0, Y at 53,248,
  UV metadata at 8,245,248, UV at 8,273,920; total 12,369,920, which is the driver's `sizeimage`.
- So the other player's success on the same headset means Valve's Turnip has something upstream lacks: a TP10 layout for
  a 10-bit 2-plane format behind some modifier, or a vendor format. The probe lists what the driver offers and tries
  every combination on a real Q10C frame.

## Build (WSL)

```
cd spikes/04-q10c-probe
make            # q10c-probe: aarch64, dynamic glibc, dlopen()s libvulkan.so.1 (no Vulkan SDK on the device needed)
make host       # q10c-probe-x86_64: the self-test with lavapipe on the PC
make shader     # convert.spv.h from convert.comp (glslangValidator; the header is committed)
```

`q10c-probe` (aarch64) is committed, so the lead can copy it without building. It needs glibc 2.38, which the engine
binaries need too.

## Run (on the headset; the lead runs it)

```
scp spikes/04-q10c-probe/q10c-probe frame:~/q10c-probe
ssh frame
./q10c-probe > q10c-list.txt 2>&1                       # 1. what the driver offers
./q10c-probe --selftest > q10c-selftest.txt 2>&1        # 2. the probe's own pipeline on Turnip (no decoder)
./q10c-probe --scan-formats > q10c-scan.txt 2>&1        # 3. vendor formats in the extension ranges (separate: it queries unknown enums)
./q10c-probe --decode ~/spike01/streams/main10_3832x1596_10s.h265 --capture Q10C --out ~/q10c-out --dump-raw > q10c-decode.txt 2>&1
./q10c-probe --decode ~/spike01/streams/main10_3832x1596_10s.h265 --capture P010 --out ~/q10c-out > q10c-p010.txt 2>&1   # control (patched module)
grep -E "RESULT|SKIPPED|vkCreateImage|Summary" q10c-decode.txt
```

Each decode opens `/dev/video-dec0` once, decodes up to the first frame and keeps that buffer. Then it tries each
candidate and closes the device. Request Q10C explicitly, as the user's headset has the patched module, which offers
P010 by default. Wait a second between runs (the firmware is sensitive to fast open/close).

What the first run lists, per format: features (linear, optimal) and every DRM format modifier with its memory plane
count, features (SAMPLED, MIDPOINT/COSITED_CHROMA, YCBCR_*, DISJOINT), and whether a sampled dmabuf import of
3840x1600 is possible (`combinedImageSamplerDescriptorCount` included). QCOM modifiers 1 to 7 that the driver doesn't list
but its image query accepts are listed as `NOT LISTED but ...`.

What the decode run tries: for G10X6, G16 and G12X4 2-plane 4:2:0 (and `--format N`), every listed non-linear modifier,
plus every QCOM modifier 1 to 7 that the image query accepts (`--all-modifiers`: all of them, and LINEAR as a negative
control). Each is tried with the memory-plane layouts that fit its plane count:

| Layout | Memory planes |
|---|---|
| `meta` | 2: Y at its metadata (0), UV at its metadata (Turnip's QCOM_COMPRESSED convention, as the engine's Q08C import) |
| `data` | 2: Y at its pixels, UV at its pixels |
| `4plane` | Y pixels, UV pixels, Y metadata, UV metadata (the metadata pitches as rowPitch) |
| `1plane` | one plane at 0 |

Per attempt, the probe prints the `vkCreateImage` result and the image's memory size against the dmabuf's. An image
larger than the dmabuf is skipped, never bound: a wrong layout can't read out of bounds. For an import, it also prints
the driver's own plane offsets, pitches and sizes. It then reads the image through a sampler with a YCbCr conversion
(`RGB_IDENTITY`, full range, NEAREST: the raw codes) into a buffer and prints:

```
RESULT Q10C-1000156011-0500000000000001-meta: PLAUSIBLE PICTURE
Y mean 341.2 min 64 max 940 neighbour-diff 6.3, in 48-956: 100.0% | Cb mean 511.0 diff 1.2 | Cr mean 515.3 diff 1.4
```

`PLAUSIBLE PICTURE`: smooth planes (luma neighbours differ by under 40 codes, 90 % of luma in range). `GARBAGE`:
noise (random 10-bit codes differ by about 340). Each result is written to `--out` as `<tag>.yuv` (yuv420p10le of the
visible 3832x1596) and `<tag>.ppm` (a BT.709 preview; `--bt2020` for BT.2020). `--dump-raw` also writes the CAPTURE
buffer's bytes as they are.

Re-running one attempt: `--only <part of the tag>`, for example `--only 1000156011-0500000000000007-meta`.

## Bit-exactness against FFmpeg (on the PC)

```
scp frame:'~/q10c-out/*.yuv' spikes/04-q10c-probe/results/
ffmpeg -i main10_3832x1596_10s.h265 -frames:v 1 -f rawvideo -pix_fmt yuv420p10le ref.yuv     # 18,347,616 bytes
python spikes/04-q10c-probe/compare.py ref.yuv spikes/04-q10c-probe/results/Q10C-*.yuv --size 3832x1596
```

`compare.py` (numpy) prints PSNR and the share of identical samples per plane, and writes a PNG of each. A hardware
decode of HEVC should be bit-exact with FFmpeg's: 100 % identical. Alternatively give the probe `--ref ref.yuv` on the
headset and it prints the same numbers per attempt.

## Self-test results

On the PC (lavapipe, Mesa 25.2.8), `./q10c-probe-x86_64 --selftest`: G10X6, G8 and G16 test patterns through the YCbCr
pass are PASS, 0 of 49,152 samples wrong each. lavapipe returns 10-bit samples as 16-bit unorm (v x 64 / 65535, as
Mesa maps R10X6 to R16), not v / 1023 as the spec says. The pass's `floor(s x 65535/64 + 0.0005)` gives the code either
way. lavapipe has no DRM format modifiers, so the import part can only run on the headset.

## Files

| File | What |
|---|---|
| `q10c_probe.c` | The probe (plain C, libc and libdl only) |
| `convert.comp`, `convert.spv.h` | The YCbCr pass (GLSL, and its SPIR-V for the build) |
| `Makefile` | aarch64 and x86_64 builds |
| `q10c-probe` | The aarch64 binary (sha256 below) |
| `compare.py` | PC: PSNR and identical-sample share against FFmpeg's yuv420p10le, and PNGs |

`q10c-probe` sha256: `90f77deed4752ce41cd27eba99e445d934811d5a9620865a17036fe930cd25db` (Ubuntu aarch64-linux-gnu-gcc,
`make`, 2026-10-31).

Device steps: `docs/morning-checklist.md`, section F, "10-bit without P010", Q1.
