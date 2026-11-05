# Dolby Vision: what plays, what is approximated, and the RPU work left

Written 2026-11-05, after a profile 5 web encode played with a purple and green cast and was fixed the same evening.
Companion to `docs/features.md` #85 (HDR tone mapping). The tools are in `tools/dovi/`.

## The profiles, as the player sees them

| Profile | What the base layer is | The player |
|---|---|---|
| 7 (UHD disc) | HDR10 base, an enhancement layer and an RPU in the stream | shows the HDR10 base; enhancement layer and RPU ignored |
| 8.1 / 8.4 (disc encodes, some web) | HDR10 (8.1) or HLG (8.4) base, RPU | shows the base as HDR10 / HLG; RPU ignored |
| 5 (web streaming) | **no HDR10 base**: the planes are Dolby's IPT-PQ-c2 signal, RPU; the file declares no colour (transfer, primaries and matrix "unspecified") | since 2026-11-05: converted in the shader (`dovi` uniform); the RPU's colour matrices are known, its reshaping curves are **not read** |

Before the fix, a profile 5 file was read as BT.709 SDR, which is what "unspecified" falls back to, and IPT shown as
Y'CbCr is purple and green. The profile comes from the container's DOVI configuration record
(`MediaSource.get_video_info()["dolby_vision_profile"]`; `media_source_extras.cpp` reads it with FFmpeg's
`AV_PKT_DATA_DOVI_CONF`), so the player knows before the first frame.

## What the profile 5 path does now

`scripts/play/hdr_tone_map.gd describe()`: profile 5 means PQ, BT.2020, limited range, `dovi = 1`. The status line
says "Dolby Vision profile 5 (IPT, as PQ)".

`shaders/video_common.gdshaderinc`, with `dovi == 1`:

1. The range step (limited to full) on all three planes, as for any limited-range file. P and T end up centred on 0.
2. `DOVI_IPT_TO_LMS * vec3(I, P, T)`: PQ-encoded L'M'S'. The matrix is the RPU's `ycc_to_rgb_matrix`, which is the
   same in every profile 5 RPU seen so far (one film, every frame dumped):
   `[1, 0.09753418, 0.20520020; 1, -0.11389160, 0.13317871; 1, 0.03259277, -0.67687988]`, offsets `0, 0.5, 0.5`.
3. `pq_to_nits()` per channel: linear LMS.
4. `DOVI_LMS_TO_RGB * lms`: linear BT.2020 RGB. This matrix was **fitted**, not taken from a specification (below).
5. From there the ordinary HDR10 path: BT.2020 to BT.709, the tone map, sRGB encoding.

`tests/test_hdr.gd` draws reference white and a saturated red as I'P'T' codes through the real shader (lavapipe or
WSLg) and expects what the PQ Y'CbCr path gives for the same light, within 8-bit rounding.

### Why the LMS to RGB matrix is fitted

The RPU gives `rgb_to_lms_matrix`, which in profile 5 is only the inverse of a 2 % crosstalk
(`[1.0425, -0.0213, -0.0213; ...]`), so a fixed LMS to BT.2020 RGB matrix has to come from somewhere else. Two
published candidates, the IPT (Ebner and Fairchild) LMS as used for Dolby's IPT-PQ and BT.2100's ICtCp LMS, with and
without the crosstalk step, were each about 5 % out against ground truth, and they disagree with each other.

Ground truth: the same film exists as a profile 8 disc encode, whose base layer is honest HDR10. `tools/dovi/frame_grid`
decodes one frame of each file in software and prints 48 x 27 block means of the planes; `align_dovi.py` found the two
encodes 23 frames apart (0.959 s, constant, luma correlation 0.9999 once aligned); `fit_dovi.py` turns the HDR10 blocks
into linear RGB, the IPT blocks into linear LMS through steps 1 to 3, and solves the 3 x 3 by least squares over five
frames (5445 blocks, near-black and clipped ones left out):

```
3.14443  -2.23166   0.09499
-0.79663   1.90617  -0.10497
-0.06416  -0.02069   1.10503
```

Median relative error 0.8 %, 90th percentile 2.8 %, mean luminance ratio 1.000. The rows sum to about 1, so white
stays white. It absorbs the crosstalk. It was fitted on one film: a second profile 5 and profile 8 pair of another film
would confirm it (or show a per-title trim, which would point back at the RPU).

## What is not read: the reshaping curves

Every frame's RPU also carries `mapping`: per component, up to 8 pieces between pivots, each a polynomial (order up to
2) or an MMR, that maps the stored base-layer values to the signal the colour matrices expect. It is how a 12-bit
signal is carried in 10-bit planes and how the base layer's tone can change per scene.

In the file on hand the curves are the same on every frame and in every piece:

```
I:    y = 1.168664 x - 0.073059     (= 1024/876 x - 64/876: limited to full range, luma)
P, T: y = 1.142578 x - 0.071429     (= 1024/896 x - 64/896: limited to full range, chroma)
```

That is exactly the shader's range step, so nothing is lost for this file. A file whose curves bend, or change by
scene, would play without the cast but with contrast and saturation a little off in those scenes. How common that is
in profile 5 streaming content is unknown: one file is the whole sample. `tools/dovi/dovi_dump` prints the curves of
any file, so the question is answerable per file.

### Reading the RPU on the headset: the plan

The hardware decoder gets the raw NAL units and hands back bare frames; the RPU (NAL type 62, "unspecified") never
reaches the app. FFmpeg parses it only inside its own HEVC decoder. So:

1. **Engine, `modules/hwvideo`:** in the demux path that feeds the V4L2 decoder, find NAL type 62 in each video packet
   and parse it. FFmpeg's parser is `libavcodec/dovi_rpu.h` (`ff_dovi_rpu_parse()`, `ff_dovi_get_metadata()`), a
   private header, but the module links FFmpeg statically from source, so it can include it. Alternative: a small own
   parser of the few fields needed (the header, `coef_log2_denom`, the mapping's pivots and polynomial coefficients;
   MMR pieces can be refused). Output per frame: for each of three components, the pivots (as 0..1), and per piece
   three polynomial coefficients. Attach it to the frame's `get_video_info()`-like per-frame data, or a
   `get_dolby_reshaping()` the app polls when `frame_key()` changes.
2. **App:** `hdr_tone_map.gd` (or the film layer's uniform copy) sets the curves as uniforms when they change: the RPU
   says `scene_refresh_flag`, and in practice they change rarely. Uniforms: `dovi_pivots[3 x 9]`, `dovi_coef[3 x 8 x 3]`,
   `dovi_pieces[3]`.
3. **Shader:** before step 2, for each component find the piece (compare against the pivots), evaluate the polynomial,
   and skip the fixed range step. Eight compares and a quadratic per channel per pixel: cheap next to the PQ `pow`s.
4. **Fallback:** no RPU parsed, or an MMR piece: the fixed range step, as now.
5. **Test:** the curves of the file on hand reproduce the range step within 0.3 % (the difference between 1024/876 and
   255/219); a synthetic curve test in `test_hdr.gd` with a bent polynomial, checked against the same evaluation in
   GDScript; on the headset, a file whose curves bend, once there is one.

Also worth taking from the RPU when it is parsed: `source_min_pq` and `source_max_pq` (the file on hand says 62 and
3696 of 4095: about 0.005 and 1000 nits), which would give the tone map the real content range instead of the 1000 nit
default a profile 5 file gets (it has no MaxCLL).

## The tools (`tools/dovi/`)

All run in WSL against the static FFmpeg of `build/ffmpeg-build.sh` (`~/src/ffmpeg-x86_64-all`): the player's own
`ffmpeg` tool build has no `ffprobe`, no `showinfo` and no `null` muxer, so these small programs read the metadata
directly.

| Tool | Does |
|---|---|
| `probe.sh <folder> [name part]` | each HEVC / HDR file's video line and DOVI configuration record (profile, compatibility id) |
| `dovi_dump.c` (`build.sh`) | decodes frames in software until one carries DOVI metadata; prints the RPU header, colour block (matrices, offsets, source min / max PQ) and the reshaping curves per component |
| `frame_grid.c` (`build.sh`) | block means of the planes of one frame (or a run of frames) at a time, 10-bit aware |
| `align_dovi.py` | the frame offset between two encodes, from runs of frames (`frame_seq.sh`) |
| `fit_dovi.py` | the LMS to RGB least-squares fit against an HDR10 encode of the same master (`frame_grid.sh`) |

Film names never go in the repository: the scripts take a folder and a name fragment on the command line.

## Open questions for tomorrow

- A second profile 5 title, ideally with a profile 8 or HDR10 twin, to confirm the fitted matrix and see whether real
  reshaping curves occur.
- Whether to read the RPU in the engine (the plan above) or wait for a file that needs it.
- `source_min_pq` / `source_max_pq` from the RPU as the tone map's content range for profile 5.
- The Q10C hardware path gives the planes as P010-like 10-bit; the fit was done on FFmpeg's software decode of the same
  file. The two should agree to the bit, but it has not been checked.
