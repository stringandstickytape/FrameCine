#!/bin/bash
# One-time WSL (Ubuntu 24.04) setup for cross-compiling the engine fork to Linux arm64.
# Needs sudo. Run once from Windows:
#   wsl -d Ubuntu -- sudo bash build/wsl-setup-arm64.sh
#
# Installs:
#   - aarch64 GCC cross toolchain (crossbuild-essential-arm64)
#   - arm64 as a foreign dpkg architecture, with Ubuntu ports as its apt source, so
#     ':arm64' dev packages (libdrm, ffmpeg, gstreamer, ...) can be pulled into a sysroot later
#   - qemu-user-static + binfmt so arm64 test binaries can be smoke-run on this box
#   - python3-pip/venv, scons, pkg-config
# Godot itself dlopens X11/Wayland/ALSA/PulseAudio/udev/dbus (use_sowrap=yes), so no
# ':arm64' X11 packages are needed for the engine build.

set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

# Restrict the default sources to amd64 and add ports.ubuntu.com for arm64.
# Ubuntu 24.04 uses deb822 (ubuntu.sources); archive.ubuntu.com does not carry arm64.
if ! dpkg --print-foreign-architectures | grep -q arm64; then
  if [ -f /etc/apt/sources.list.d/ubuntu.sources ] && ! grep -q '^Architectures:' /etc/apt/sources.list.d/ubuntu.sources; then
    sed -i '/^Types: deb$/a Architectures: amd64' /etc/apt/sources.list.d/ubuntu.sources
  fi
  cat > /etc/apt/sources.list.d/ubuntu-ports-arm64.sources <<EOF
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports
Suites: $CODENAME $CODENAME-updates $CODENAME-security
Components: main restricted universe multiverse
Architectures: arm64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
  dpkg --add-architecture arm64
fi

apt-get update
apt-get install -y --no-install-recommends \
  crossbuild-essential-arm64 \
  qemu-user-static binfmt-support \
  python3-pip python3-venv pkg-config git git-lfs ninja-build cmake \
  libc6:arm64 libstdc++6:arm64 libgcc-s1:arm64 \
  libdrm-dev:arm64 libgbm-dev:arm64 libegl-dev:arm64 libgl-dev:arm64 libvulkan-dev:arm64 \
  libva-dev:arm64 libv4l-dev:arm64 \
  libavcodec-dev:arm64 libavformat-dev:arm64 libavutil-dev:arm64 libswscale-dev:arm64 libswresample-dev:arm64 \
  libgstreamer1.0-dev:arm64 libgstreamer-plugins-base1.0-dev:arm64 \
  libass-dev:arm64

# scons in a venv owned by the invoking user (Ubuntu 24.04 blocks system pip installs)
USER_HOME=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
sudo -u "${SUDO_USER:-root}" bash -c "python3 -m venv '$USER_HOME/.venv/godot' && '$USER_HOME/.venv/godot/bin/pip' install -q scons"

echo
echo "ok: $(aarch64-linux-gnu-gcc --version | head -1)"
echo "ok: scons $("$USER_HOME/.venv/godot/bin/scons" --version | grep -m1 -oE 'SCons: v[0-9.]+')"
echo "ok: arm64 sysroot packages in /usr/aarch64-linux-gnu and /usr/lib/aarch64-linux-gnu"
