#!/usr/bin/env bash
# Build-only: kernel #194 = #193 (scripts/build_kernel193.sh) with DSI
# commands and command mode frames kept apart
# (devices/oneplus7pro/kernel/display/dsi-cmd-frame-sync.patch), for the
# brightness flicker (docs/controls-20260923.md). The change is inside the
# built-in msm driver; no structure a runtime module sees changes, the config
# and release string are #193's, so every runtime module loads.
# Output: out/checkpoints/20260924-kernel194/.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/.work/linux-sm8150-193"
TREE="$ROOT/.work/linux-sm8150-194"
OUT="$ROOT/out/checkpoints/20260924-kernel194"
DTB="$TREE/bringup-guacamole.dtb"
[[ -d $BASE ]] || bash "$ROOT/scripts/build_kernel193.sh"
rm -rf "$TREE" "$OUT"
mkdir -p "$OUT"
cp -a --reflink=auto "$BASE" "$TREE"
patch -s -p1 -d "$TREE" < "$ROOT/devices/oneplus7pro/kernel/display/dsi-cmd-frame-sync.patch"
cmp "$BASE/.config" "$TREE/.config"
make -C "$TREE" ARCH=arm64 LLVM=1 KBUILD_BUILD_VERSION=194 -j"${JOBS:-8}" Image > "$OUT/build.log" 2>&1
BOOT_CMDLINE=$(fdtget -ts "$DTB" /chosen bootargs) \
    bash "$ROOT/scripts/pack_hdr2_boot.sh" "$TREE/arch/arm64/boot/Image" \
    "$ROOT/out/cpu-test/restore-ramdisk.gz" "$DTB" "$OUT/boot.img"
cp "$DTB" "$TREE/.config" "$TREE/include/generated/utsrelease.h" \
    "$TREE/include/generated/utsversion.h" "$OUT/"
(cd "$OUT" && sha256sum boot.img bringup-guacamole.dtb .config utsrelease.h utsversion.h build.log > SHA256SUMS)
