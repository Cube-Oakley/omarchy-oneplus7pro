#!/usr/bin/env bash
# Keep the verified GPU boot path and load the tested touch overlay afterward.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="$ROOT/.work/linux-sm8150-codex-cpu"
RAMROOT="$ROOT/.work/codex-touch-initramfs"
mkdir -p "$RAMROOT"
cp -a "$ROOT/.work/codex-gpu-initramfs/." "$RAMROOT/"
install -m 755 "$ROOT/scripts/initramfs/init-touch" "$RAMROOT/init"
install -m 755 "$ROOT/scripts/initramfs/start-touchscreen.sh" "$RAMROOT/hypr/start-touchscreen.sh"
# Prepare matching vermagic before building the loadable modules. Driver
# sources and ABI stay the same as gpu2; only LOCALVERSION changes here.
"$KERNEL/scripts/config" --file "$KERNEL/.config" --set-str LOCALVERSION '-sm8150-codex-touch1'
make -C "$KERNEL" ARCH=arm64 LLVM=1 olddefconfig modules_prepare
bash "$ROOT/scripts/build_touch_test.sh"
mkdir -p "$RAMROOT/hypr/touch"
install -m 644 "$ROOT/out/touch-test/evdev.ko" "$ROOT/out/touch-test/s6sy761.ko" \
    "$ROOT/out/touch-test/touch_overlay.ko" "$RAMROOT/hypr/touch/"
INITRAMFS_ROOT="$RAMROOT" CPU_TEST_NAME=touch1 bash "$ROOT/scripts/rebuild_cpu_test.sh"
