#!/usr/bin/env bash
# Build the tested eight-core GPU kernel with automatic Adreno desktop startup.
# Requires the prepared source tree and the gpu1 dma-buf fix; never flashes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAMROOT="$ROOT/.work/codex-gpu-initramfs"
mkdir -p "$RAMROOT"
cp -a "$ROOT/.work/codex-cpu-initramfs/." "$RAMROOT/"
install -m 755 "$ROOT/scripts/initramfs/init-adreno" "$RAMROOT/init"
install -m 755 "$ROOT/scripts/initramfs/run-hypr-adreno.sh" "$RAMROOT/hypr/run-hypr.sh"
install -m 755 "$ROOT/scripts/initramfs/start-adreno-desktop.sh" "$RAMROOT/hypr/start-adreno-desktop.sh"
install -m 644 "$ROOT/scripts/initramfs/hyprland-adreno.lua" "$RAMROOT/hypr/hyprland.lua"
# Refuse to build this launcher on top of the kernel that corrupted PRIME buffers.
git -C "$ROOT/.work/linux-sm8150-codex-cpu" apply --reverse --check \
    "$ROOT/kernel/patches/codex-msm-imported-dmabuf-free.patch"
INITRAMFS_ROOT="$RAMROOT" CPU_TEST_NAME=gpu2 bash "$ROOT/scripts/rebuild_cpu_test.sh"
