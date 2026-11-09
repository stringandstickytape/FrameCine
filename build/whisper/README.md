# On-device speech to text (whisper.cpp)

The assistant takes push-to-talk speech in the headset. Until now a PC transcribed it (`tools/voice.py`,
faster-whisper `small.en`). With the assistant service on the headset, the headset transcribes too: whisper.cpp's
`whisper-server` runs as a child process of the app, bound to 127.0.0.1, with the model loaded once. Nothing is
installed on the device: the server and a model ship in the package's `whisper/` folder. Decision: `docs/decisions.md`
D17.

## Build

From Windows (WSL, no sudo; the same toolchain as the engine, FFmpeg and libsmb2):

```
wsl -d Ubuntu -- bash build/whisper-build.sh [TARGET]
wsl -d Ubuntu -- bash build/whisper-models.sh
```

| Target | For | Output |
|---|---|---|
| `aarch64` | the headset, CPU | `build/out/whisper/aarch64/` |
| `aarch64-vulkan` | the headset, CPU plus the Vulkan backend (Adreno through Turnip) | `build/out/whisper/aarch64-vulkan/` |
| `x86_64` | WSL and desktop tests | `build/out/whisper/x86_64/` |
| `all` (default) | all three | |

- **Source:** whisper.cpp tag `v1.9.5`, commit `d1be6fde11ac6e0407606b4e42fe72d34add8037`, cloned into
  `~/src/whisper.cpp` and checked against that commit. Nothing of it is committed here.
- **Binaries:** `whisper-server` (what the app runs), `whisper-cli` and `whisper-bench` (for the benchmark), stripped.
  Each output folder has `BUILDINFO` (tag, commit, flags, the shared libraries needed, the newest glibc symbol) and
  `SHA256SUMS`.
- **Linking:** as the engine (`use_static_cpp`): libstdc++ and libgcc static, glibc dynamic; whisper and ggml static;
  no OpenMP (ggml's own thread pool, so no libgomp). The aarch64 binaries need only `libc.so.6`, `libm.so.6` and
  `ld-linux-aarch64.so.1`, and no glibc symbol newer than 2.38, the same as the engine (the script fails otherwise).
  The Vulkan build also needs `libvulkan.so.1`, which SteamOS has.
- **CPU:** `-march=armv8.2-a+fp16+dotprod+i8mm`. The Snapdragon 8 Gen 3 (Cortex-X4, A720, A520) has all of them. The
  app reads `/proc/cpuinfo` first and stays off with a clear line on a CPU without them (a Cortex-A53 would stop with
  an illegal instruction). Under `qemu-aarch64 -cpu max` the build reports `NEON = 1 | ARM_FMA = 1 | FP16_VA = 1 |
  MATMUL_INT8 = 1 | DOTPROD = 1` and transcribes the JFK sample correctly.
- **Vulkan:** ggml compiles its shaders on the build host with `glslc`. The script builds `glslc` once from shaderc
  `v2026.4` and installs SPIR-V headers and Vulkan headers `v1.4.367` into `~/src/whisper-hosttools`; it links against
  the distribution's arm64 `libvulkan.so` (multiarch `libvulkan-dev:arm64`). It builds cleanly. The binaries are about
  50 MB each because the shaders are inside.
- **Time:** about 1 min for a CPU target on 30 cores; about 5 min for the Vulkan target the first time (shaderc).

The 2026-10-31 build:

| File | Size (bytes) | SHA-256 |
|---|---|---|
| `aarch64/whisper-server` | 4134248 | `711aa83f935844370553f231d08edc11c564a9f80e8e433c920a8aaccefede56` |
| `aarch64/whisper-cli` | 3937632 | `3c4d8c1016da8135252993af615037729ee6902aebc9030a0e711f067b92d819` |
| `aarch64/whisper-bench` | 3281472 | `45a157768708670274b396eab6f036d8620d525c1aa20e91f1585104926a1419` |
| `aarch64-vulkan/whisper-server` | 49751912 | `e7565a315a33c3be79b98958bc7783a2a7002a574975ba781f0f24c878aac9fe` |
| `aarch64-vulkan/whisper-cli` | 49555296 | `2f8445d9494db00e13eaddc3eef95f9e5d8335826c0161b1b29a8f172c70925e` |
| `aarch64-vulkan/whisper-bench` | 48899136 | `db4b558faaddd0c5c5d9857253be0affcd22f962053e79159ee726e1ca51ec7d` |
| `x86_64/whisper-server` | 4372704 | `d8b63535dca90905b1f30fea8a8c2aac6b0b0cb49f5e9d02831d152b80445f54` |
| `x86_64/whisper-cli` | 4143328 | `984e25af068818de5d9f7b16a8e938870c5d7d2f20add83aaa0a298b50e6cf93` |
| `x86_64/whisper-bench` | 3462432 | `f0d946c135a6b9a665ee262e4fbb44494d8cf623c47b2bb90cebca374f4139d2` |

A rebuild gives other hashes (the build is not bit-reproducible); `SHA256SUMS` in each folder is the reference that
`tools/package.sh` and `tools/morning-deploy.sh` check.

## Models

`build/whisper-models.sh` downloads ggml models from one pinned revision (`5359861c739e955e79d9a303bcbc70fb988958b1`)
of the Hugging Face repository `ggerganov/whisper.cpp` into `build/out/whisper-models/`, and checks each SHA-256. Models
are never committed. Arguments: none (the six quantized files below), `--all` (also the f16 files), or model names.

| Model | Size | Notes |
|---|---|---|
| `tiny.en-q5_1` | 32 MB | the desktop tests |
| `tiny.en-q8_0` | 44 MB | |
| `base.en-q5_1` | 60 MB | |
| `base.en-q8_0` | 82 MB | faster; finals about 3 times quicker than small.en |
| `small.en-q5_1` | 190 MB | |
| `small.en-q8_0` | 264 MB | **the default** (`[voice] whisper_model` "small.en", 6 threads); in the package |
| `tiny.en`, `base.en`, `small.en` (f16) | 78, 148, 488 MB | `--all` only |

The SHA-256 of each file is in the script. A bare name in the setting (`base.en`) takes q8_0, then q5_1, then f16.

## Speech samples

`build/whisper/samples/`, 16 kHz mono 16-bit WAV, for the test and the benchmark. Both are works of the US federal
government, so in the public domain.

| File | Length | Source | Text |
|---|---|---|---|
| `jfk-11s.wav` | 11.0 s | whisper.cpp's `samples/jfk.wav` at the pinned commit (SHA-256 `59dfb9a4...7860e`, unchanged): President Kennedy's inaugural address, 1961 | "And so my fellow Americans, ask not what your country can do for you, ask what you can do for your country." |
| `radio-29s.wav` | 29.1 s | Wikimedia Commons, `George_W._Bush's_weekly_radio_address_(November_1,_2008).oga` (the file whisper.cpp's Makefile fetches as `gb0.ogg`; SHA-256 `b844a36b...3f0c`); the first 29.1 s, cut at a sentence end | "Good morning. This Tuesday is Election Day. After months of spirited debate and vigorous campaigning, ... Republicans, Democrats, and independents can find common ground on at least one point." |

`radio-29s.wav` was made with:
`ffmpeg -i gb0.oga -t 29.1 -af afade=t=out:st=28.95:d=0.15 -ar 16000 -ac 1 -c:a pcm_s16le -map_metadata -1
-fflags +bitexact -flags:a +bitexact radio-29s.wav` (SHA-256 `4689e782b20d3e2c932aff030dadfe500728c9d6a6764cdb48e04c19978be421`).

## In the app

`app/scripts/voice/whisper_backend.gd` (a Node; the API front is `app/scripts/voice/transcriber.gd`):

- `WhisperBackend.ensure(get_tree())` adds the node under the root once, configured from `[voice]` settings and
  `--whisper-*` flags (`docs/USAGE.md`). The assistant calls it when it needs speech; nothing starts at launch.
- It finds `whisper-server` (in `whisper/`, or `whisper/vulkan/` for `whisper_backend = "vulkan"`) next to the engine,
  one folder up (a release's `bin/`), next to the app folder, or in `whisper_dir`; and the model in `whisper/models/`,
  then in `user://whisper-models/`. Missing either, or a CPU without dotprod/i8mm/fp16: `Transcriber.available()` stays
  false and one line says what and where (`Voice: on-device transcription unavailable: no whisper-server in ...`).
- With the server there but no default model (the release package has none), the backend waits and downloads
  `ggml-small.en-q8_0.bin` from the project's `models-1` release the first time voice is used, checks its SHA-256,
  and then starts the server (`app/scripts/voice/model_download.gd`; `docs/framedrop.md` "The speech model").
- It starts the server with `OS.create_process` on 127.0.0.1, a free port, and a random route prefix
  (`--request-path`; any local program or web page could otherwise reach it, and the server allows any origin and can
  swap its model through `/load`), waits on `/health` from a worker thread, then sets `Transcriber.backend = self` and
  logs `Voice: whisper-server ready: model base.en-q8_0, cpu, 4 threads, loaded in N ms`. The server's own output goes
  to `user://whisper-server.log`.
- `transcribe(id, pcm, final)`: the clip goes as a WAV in a multipart POST from a worker thread (a frame never waits).
  Finals: beam 5, the vocabulary prompt (copied from `tools/voice.py`), queued if a request runs. Partials: greedy, no
  temperature fallback, skipped (returns false) while any request runs. Clips under 1 s are padded with silence
  (whisper.cpp skips shorter input). Each taken id gets exactly one `Transcriber.emit_done(id, text, final)`; the text
  is "" on failure (logged), and whisper's markers such as `[BLANK_AUDIO]` are removed.
- If the server dies it is started again once; a second death turns transcription off with a line. The node kills
  the server when it leaves the tree; a small shell watchdog kills it if the engine itself dies.

## Packaging

- `tools/package.sh` puts `whisper/whisper-server`, `whisper/models/ggml-small.en-q8_0.bin`, `BUILDINFO` and
  `SHA256SUMS` in the package (86 MB; executable bits set), and the licences in `LICENSES/` (`whisper.cpp-MIT.txt`,
  `whisper-models-MIT.txt`, rows in `THIRD-PARTY.md`). Flags: `--no-whisper`, `--whisper-model STEM`,
  `--whisper-vulkan` (adds `whisper/vulkan/whisper-server`, 50 MB), `--whisper-bench` (both builds with whisper-cli
  and whisper-bench, every downloaded model, the samples and `tools/whisper-bench.sh`).
- `tools/morning-deploy.sh` copies to `~/spike03/whisper/` (the app finds it next to `spike03/godot_player`): the CPU
  build, the Vulkan server and cli in `vulkan/`, every model in `build/out/whisper-models` (or `--whisper-models
  "base.en-q8_0 small.en-q8_0"`), the samples, and `tools/whisper-bench.sh` to `~/spike03/tools/`. It checks every
  file's SHA-256 on the headset like the rest. `--no-whisper` leaves it out; without a build it skips with a note.

## Benchmark (on the headset)

`tools/whisper-bench.sh` runs `whisper-cli` on both samples with each model, thread count, build and mode (final:
beam 5 with the prompt; partial: greedy, no fallback) and prints one tab-separated line per run: load ms, processing
ms, real-time factor (processing time / audio length; under 1 is faster than real time), peak memory (MB; from
`/usr/bin/time -v`, else from `/proc/<pid>/status`), and the text. The table is also saved as
`~/whisper-bench-<date>-<tag>.tsv`. A header line gives the CPU governors and the load.

After `tools/morning-deploy.sh` (from the PC):

```
# The full matrix: 6 models x threads 4/6/8 x CPU and Vulkan x final/partial x 2 samples (about 20 to 30 min)
ssh frame 'cd ~/spike03 && bash tools/whisper-bench.sh --tag idle'

# The short one: base.en-q8_0 and small.en-q8_0, 4 and 6 threads, finals only
ssh frame 'cd ~/spike03 && bash tools/whisper-bench.sh --quick --tag idle'
```

While a film plays (the real case: the assistant is used during playback). Start a 4K film in the headset first,
then run the bench in a second ssh session while it plays, and compare with the idle numbers; also watch the
player's frame timing in its overlay or log for drops while the bench runs:

```
ssh frame 'cd ~/spike03 && DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot_player --path app --display-driver x11 \
  --xr-mode on -- --file=<a 2160p HEVC film on the headset> --overlay'      # session 1, leave it playing
ssh frame 'cd ~/spike03 && bash tools/whisper-bench.sh --quick --builds "cpu vulkan" --tag film-4k'   # session 2
```

From a package made with `tools/package.sh --whisper-bench`: `cd ~/framecine && bash tools/whisper-bench.sh`.
What to decide from it: the default model (`base.en` unless `small.en` finals stay well under real time with a film
playing), the default thread count, and CPU or Vulkan.

## Tests

`app/tests/test_whisper.gd` (desktop, WSL, the x86_64 build and `tiny.en-q5_1`):

```
wsl -d Ubuntu -- bash -lc 'cd /mnt/c/path/to/FrameCine && \
  ~/src/godot-player/bin/godot.linuxbsd.template_debug.x86_64 --headless --xr-mode off --path app \
  --script res://tests/test_whisper.gd'
```

It checks the WAV and the form, model and folder lookup, the CPU check, a missing binary and a missing model
(unavailable, with the line), then the real server: listening on 127.0.0.1 only (`/proc/net/tcp`, and a refused
connection on the LAN address), nothing answered without the route prefix, the JFK final ("fellow Americans ... ask
not what your country can do for you") while frames go on, a partial skipped while the final runs, a partial on its
own, one restart after a crash and off after the second, the server killed when the node goes, and `ensure()`.
Without the x86_64 build or the model the server part is skipped and reported. `WHISPER_TEST_DIR` and
`WHISPER_TEST_MODEL` point it elsewhere (in a linked worktree, `build/out` is the main checkout's).

## Licences

- whisper.cpp and ggml: MIT (`LICENSE` of the source; copied as `LICENSE-whisper.cpp.txt` next to the binaries and
  as `LICENSES/whisper.cpp-MIT.txt` in the package).
- The models: OpenAI's Whisper weights, MIT (`build/whisper/LICENSE-models.txt`, in the package as
  `LICENSES/whisper-models-MIT.txt`), converted to ggml by the whisper.cpp project.
- The host tools used only to build (shaderc, glslang, SPIRV-Tools, SPIR-V and Vulkan headers): Apache-2.0 or MIT;
  nothing of them ships.
- The samples: public domain (above).

## Device results (2026-10-31, Frame, kernel 6.18, 8 cores)

Finals, `tools/whisper-bench.sh --quick`. Processing time in seconds for the 11 s and the 29 s sample.

| Build | Model | Threads | Idle | With a 2160p 10-bit film decoding in hardware |
|---|---|---|---|---|
| cpu | base.en-q8_0 | 6 | 0.78, 1.32 | 0.83, 1.46 |
| cpu | small.en-q8_0 | 6 | 2.27, 3.48 | 2.30, 3.71 |
| vulkan | base.en-q8_0 | 6 | 0.85, 2.00 | not run |
| vulkan | small.en-q8_0 | 6 | 2.23, 4.27 | not run |

The film showed 0 dropped frames while the clips were transcribed. Vulkan is no faster than the CPU, and the GPU draws
the film, so the CPU build stays the default. small.en is the default for its accuracy; a long sentence takes 2 to 4 s.
