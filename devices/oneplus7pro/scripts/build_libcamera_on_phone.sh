#!/usr/bin/env bash
# Runs on the host: builds libcamera 0.7.2 with the OnePlus camera patches on
# the phone and installs it to /opt/libcamera-guacamole, leaving the system
# libcamera untouched. Use it with
#   LD_LIBRARY_PATH=/opt/libcamera-guacamole/lib /opt/libcamera-guacamole/bin/cam
# Patches 0001-0010 and imx586.yaml are the OnePlus 7T Pro bring-up's
# (Robin Snyders, hotdog-linux-bringup); 0011 lets full-resolution frames
# fall back from the 32 MiB CMA heap, and 0012 points the GPU path's
# statistics at the whole visible frame. The phone needs meson, ninja,
# python-jinja, python-yaml and python-ply. Details: docs/camera-20260922.md.
# Do not stream the camera while this builds: a capture started during the
# full-load build crashed the phone into 05c6:900e.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=0.7.2
SHA512=b317cdc96f61682ee0bf26dfb7c4d6441db9a9c5
PATCHES="$ROOT/adapter/camera/libcamera"
WORK="$ROOT/.work/libcamera"
PREFIX=/opt/libcamera-guacamole
mkdir -p "$WORK"
tarball="$WORK/libcamera-v$VERSION.tar.gz"
[[ -s $tarball ]] || curl -fsSL -o "$tarball" \
    "https://gitlab.freedesktop.org/camera/libcamera/-/archive/v$VERSION/libcamera-v$VERSION.tar.gz"
[[ $(sha512sum "$tarball" | cut -c1-40) == "$SHA512" ]] || { echo "libcamera tarball checksum mismatch" >&2; exit 1; }
src="$WORK/src"
rm -rf "$src" && mkdir -p "$src"
tar xzf "$tarball" -C "$src"
for patch in "$PATCHES"/00*.patch; do
    patch -d "$src/libcamera-v$VERSION" -p1 -s --no-backup-if-mismatch < "$patch"
done
tar czf - -C "$src" "libcamera-v$VERSION" | bash "$ROOT/scripts/phone-ssh.sh" "
    set -e
    mkdir -p /root/camera-bringup/build && cd /root/camera-bringup/build
    rm -rf libcamera-v$VERSION && tar xzf - && cd libcamera-v$VERSION
    meson setup out --prefix=$PREFIX --buildtype=release -Dpipelines=simple -Dipas=simple \
        -Dcam=enabled -Dcam-output-kms=disabled -Dcam-output-sdl2=disabled -Dgstreamer=disabled \
        -Dqcam=disabled -Dpycamera=disabled -Ddocumentation=disabled -Dlc-compliance=disabled \
        -Dtracing=disabled -Dv4l2=false -Dtest=false -Dwerror=false > /dev/null
    ninja -C out
    meson install -C out --quiet
    sync"
bash "$ROOT/scripts/phone-ssh.sh" "mkdir -p $PREFIX/share/libcamera/ipa/simple && cat > $PREFIX/share/libcamera/ipa/simple/imx586.yaml && sync" \
    < "$PATCHES/imx586.yaml"
bash "$ROOT/scripts/phone-ssh.sh" "cat > $PREFIX/share/libcamera/ipa/simple/s5k3m5.yaml && sync" \
    < "$PATCHES/s5k3m5.yaml"
bash "$ROOT/scripts/phone-ssh.sh" "cat > $PREFIX/share/libcamera/ipa/simple/imx481.yaml && sync" \
    < "$PATCHES/imx481.yaml"
echo "installed to $PREFIX"
