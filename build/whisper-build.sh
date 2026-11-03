#!/bin/bash
# Builds whisper.cpp (speech to text, MIT) for the app's on-device transcription (app/scripts/voice/whisper_backend.gd,
# build/whisper/README.md, docs/decisions.md D17): the persistent `whisper-server` (HTTP, the app binds it to 127.0.0.1,
# the model loads once), `whisper-cli` and `whisper-bench` for tools/whisper-bench.sh. Run from Windows (no sudo needed):
#   wsl -d Ubuntu -- bash build/whisper-build.sh [TARGET]
# TARGET:  aarch64          the Steam Frame, CPU (NEON, dotprod, i8mm, fp16: Snapdragon 8 Gen 3 has all of them)
#          aarch64-vulkan   the Steam Frame, CPU plus the Vulkan backend (Adreno through Turnip); needs a glslc on the
#                           build host: built once from shaderc (below), with newer Vulkan and SPIR-V headers
#          x86_64           WSL and desktop tests (AVX2/FMA/F16C)
#          all              aarch64, x86_64 and aarch64-vulkan (the default)
# Source:  ~/src/whisper.cpp, a shallow clone of tag $WHISPER_TAG, checked against $WHISPER_COMMIT (not committed
#          anywhere). Build trees ~/src/whisper-build-<target>; prefixes ~/src/whisper-<target>.
# Output:  build/out/whisper/<target>/ in this checkout (or $WHISPER_OUT/<target>): whisper-server, whisper-cli,
#          whisper-bench, BUILDINFO (tag, commit, flags, newest glibc symbol), SHA256SUMS. tools/package.sh copies the
#          aarch64 (and, if present, aarch64-vulkan) server into the package's whisper/ folder.
#
# Linking, as the engine does (platform/linuxbsd use_static_cpp): libstdc++ and libgcc static, glibc dynamic. All of
# whisper and ggml is static (BUILD_SHARED_LIBS=OFF), no OpenMP (ggml's own thread pool, so no libgomp). The aarch64
# binaries need only libc, libm and ld-linux; the newest glibc symbol is checked against the engine's (2.38). The Vulkan
# build also needs libvulkan.so.1, which SteamOS has (the engine uses Vulkan).
# About 2 min for a CPU target on 30 cores; the Vulkan target compiles a few hundred shaders (5 to 10 min), plus about
# 5 min once for shaderc.

set -euo pipefail
WHICH=${1:-all}
WHISPER_TAG=${WHISPER_TAG:-v1.9.5}
WHISPER_COMMIT=${WHISPER_COMMIT:-d1be6fde11ac6e0407606b4e42fe72d34add8037}
SHADERC_TAG=${SHADERC_TAG:-v2026.4}
VULKAN_HEADERS_TAG=${VULKAN_HEADERS_TAG:-v1.4.367}
SRC=$HOME/src/whisper.cpp
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
OUT=${WHISPER_OUT:-$REPO/build/out/whisper}
JOBS=$(( $(nproc) - 2 ))
# The glibc the engine needs at most (aarch64-linux-gnu-objdump -T on the engine); ours must not need a newer one.
GLIBC_MAX=2.38

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$(dirname "$SRC")"
  git clone -q --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp.git "$SRC"
fi
HEAD=$(git -C "$SRC" rev-parse HEAD)
if [ "$HEAD" != "$WHISPER_COMMIT" ]; then
  git -C "$SRC" fetch -q --depth 1 origin tag "$WHISPER_TAG"
  git -C "$SRC" checkout -q -f "$WHISPER_TAG"
  HEAD=$(git -C "$SRC" rev-parse HEAD)
fi
[ "$HEAD" = "$WHISPER_COMMIT" ] || { echo "whisper.cpp $WHISPER_TAG is $HEAD, expected $WHISPER_COMMIT" >&2; exit 1; }
git -C "$SRC" diff --quiet || { echo "$SRC has local changes" >&2; exit 1; }
echo "whisper.cpp source: $WHISPER_TAG $HEAD"

# --- Host tools for the Vulkan target: glslc (shaderc), SPIR-V headers, newer Vulkan headers (vulkan.hpp) ----------
HOSTTOOLS=$HOME/src/whisper-hosttools
vulkan_tools() {
  if [ -x "$HOSTTOOLS/bin/glslc" ] && [ -f "$HOSTTOOLS/include/vulkan/vulkan.hpp" ] &&
     [ -d "$HOSTTOOLS/share/cmake/SPIRV-Headers" ]; then
    return
  fi
  local s=$HOME/src/shaderc
  if [ ! -d "$s/.git" ]; then
    git clone -q --depth 1 --branch "$SHADERC_TAG" https://github.com/google/shaderc.git "$s"
  fi
  (cd "$s" && python3 utils/git-sync-deps > /dev/null)
  cmake -S "$s" -B "$s-build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOSTTOOLS" \
    -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DSPIRV_SKIP_TESTS=ON \
    -DSPIRV_SKIP_EXECUTABLES=ON -DENABLE_GLSLANG_BINARIES=OFF > "$s-build.log" 2>&1 || { tail -30 "$s-build.log"; exit 1; }
  cmake --build "$s-build" -j "$JOBS" --target glslc_exe >> "$s-build.log" 2>&1 || { tail -30 "$s-build.log"; exit 1; }
  mkdir -p "$HOSTTOOLS/bin"
  cp "$s-build/glslc/glslc" "$HOSTTOOLS/bin/glslc"
  cmake -S "$s/third_party/spirv-headers" -B "$s-build-spirv-headers" -DCMAKE_INSTALL_PREFIX="$HOSTTOOLS" \
    -DSPIRV_HEADERS_ENABLE_TESTS=OFF > /dev/null
  cmake --install "$s-build-spirv-headers" > /dev/null
  local vh=$HOME/src/vulkan-headers
  if [ ! -d "$vh/.git" ]; then
    git clone -q --depth 1 --branch "$VULKAN_HEADERS_TAG" https://github.com/KhronosGroup/Vulkan-Headers.git "$vh"
  fi
  cmake -S "$vh" -B "$vh-build" -DCMAKE_INSTALL_PREFIX="$HOSTTOOLS" -DVULKAN_HEADERS_ENABLE_MODULE=OFF > /dev/null
  cmake --install "$vh-build" > /dev/null
  echo "host tools: $("$HOSTTOOLS/bin/glslc" --version | head -1), Vulkan headers $VULKAN_HEADERS_TAG"
}

build() {
  local name=$1
  local dir=$HOME/src/whisper-build-$name
  local prefix=$HOME/src/whisper-$name
  local opts=(
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_BUILD_SERVER=ON
    -DWHISPER_SDL2=OFF -DWHISPER_CURL=OFF
    -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_CCACHE=OFF -DGGML_BACKEND_DL=OFF
    "-DCMAKE_EXE_LINKER_FLAGS=-static-libgcc -static-libstdc++"
  )
  local readelf=readelf objdump=objdump strip=strip
  case $name in
    aarch64|aarch64-vulkan)
      opts+=(-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64
        -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++
        -DCMAKE_AR=/usr/bin/aarch64-linux-gnu-ar -DCMAKE_RANLIB=/usr/bin/aarch64-linux-gnu-ranlib
        # Cortex-X4/A720/A520 (ARMv9.2): everything ggml's ARM kernels use. SVE is left out: ggml's SVE paths are no
        # faster than NEON at a 128-bit vector length.
        -DGGML_CPU_ARM_ARCH=armv8.2-a+fp16+dotprod+i8mm)
      readelf=aarch64-linux-gnu-readelf; objdump=aarch64-linux-gnu-objdump; strip=aarch64-linux-gnu-strip ;;
    x86_64)
      opts+=(-DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_BMI2=ON) ;;
    *) echo "unknown target $name"; exit 1 ;;
  esac
  if [ "$name" = aarch64-vulkan ]; then
    vulkan_tools
    # Headers from the host tools (newer than the distribution's), the arm64 libvulkan.so to link against (multiarch
    # package libvulkan-dev:arm64). vulkan-shaders-gen is built for the host by ggml itself.
    opts+=(-DGGML_VULKAN=ON -DVulkan_GLSLC_EXECUTABLE="$HOSTTOOLS/bin/glslc"
      -DVulkan_INCLUDE_DIR="$HOSTTOOLS/include" -DVulkan_LIBRARY=/usr/lib/aarch64-linux-gnu/libvulkan.so
      -DCMAKE_PREFIX_PATH="$HOSTTOOLS" -DSPIRV-Headers_DIR="$HOSTTOOLS/share/cmake/SPIRV-Headers")
  fi
  rm -rf "$dir" "$prefix"
  cmake -S "$SRC" -B "$dir" -G Ninja "${opts[@]}" > "$dir.log" 2>&1 || { tail -40 "$dir.log"; exit 1; }
  cmake --build "$dir" -j "$JOBS" --target whisper-server whisper-cli whisper-bench >> "$dir.log" 2>&1 ||
    { tail -40 "$dir.log"; exit 1; }
  mkdir -p "$prefix/bin"
  for b in whisper-server whisper-cli whisper-bench; do
    "$strip" -o "$prefix/bin/$b" "$dir/bin/$b"
  done

  # Linkage check: what the binaries need at run time, and the newest glibc symbol version.
  local needed glibc
  needed=$("$readelf" -d "$prefix/bin/whisper-server" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | tr '\n' ' ')
  glibc=$("$objdump" -T "$prefix"/bin/* | grep -o 'GLIBC_[0-9.]*' | sort -Vu | tail -1)
  case " $needed " in *libstdc++*|*libgcc_s*|*libgomp*) echo "$name: unexpected shared library in: $needed" >&2; exit 1 ;; esac
  if [ "$(printf '%s\n%s\n' "${glibc#GLIBC_}" "$GLIBC_MAX" | sort -V | tail -1)" != "$GLIBC_MAX" ]; then
    echo "$name: needs $glibc, newer than the engine's GLIBC_$GLIBC_MAX" >&2; exit 1
  fi

  local out=$OUT/$name
  rm -rf "$out"
  mkdir -p "$out"
  cp "$prefix"/bin/* "$out/"
  cp "$SRC/LICENSE" "$out/LICENSE-whisper.cpp.txt"
  cat > "$out/BUILDINFO" <<EOF
whisper.cpp $WHISPER_TAG $HEAD
target $name
needs $needed
glibc_max $glibc
cpu_arch $(grep -o 'GGML_CPU_ARM_ARCH=[^ ]*' <<< "${opts[*]}" | cut -d= -f2 || echo "x86-64 avx2 fma f16c")
vulkan $([ "$name" = aarch64-vulkan ] && echo "yes (glslc $SHADERC_TAG, headers $VULKAN_HEADERS_TAG)" || echo no)
built $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  (cd "$out" && sha256sum whisper-server whisper-cli whisper-bench > SHA256SUMS)
  echo "== $name: $out (needs: $needed; newest glibc symbol: $glibc)"
  (cd "$out" && ls -l whisper-server whisper-cli whisper-bench | awk '{print "   " $5 "  " $9}' && sed 's/^/   /' SHA256SUMS)
}

case $WHICH in
  all) build aarch64; build x86_64; build aarch64-vulkan ;;
  aarch64|aarch64-vulkan|x86_64) build "$WHICH" ;;
  *) echo "usage: $0 [aarch64|aarch64-vulkan|x86_64|all]"; exit 1 ;;
esac
