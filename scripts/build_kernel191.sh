#!/usr/bin/env bash
# Build-only: kernel #191 = #190 (scripts/build_kernel190.sh) plus
#   - 60 and 90 Hz panel modes (devices/oneplus7pro/kernel/display/
#     panel-60-90hz.patch); 60 Hz stays preferred, so boot is unchanged and
#     the compositor opts in to 90 Hz (docs/smoothness-20260923.md);
#   - CPU frequency scaling enabled in the boot DTB, which retires the
#     guacamole_cpufreq runtime overlay.
# Same .config and release string, so every existing module loads.
# Output: out/checkpoints/20260923-kernel191/.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/.work/linux-sm8150-190"
TREE="$ROOT/.work/linux-sm8150-191"
OUT="$ROOT/out/checkpoints/20260923-kernel191"
[[ -d $BASE ]] || bash "$ROOT/scripts/build_kernel190.sh"
rm -rf "$TREE" "$OUT"
mkdir -p "$OUT"
cp -a --reflink=auto "$BASE" "$TREE"
patch -s -p0 -d "$TREE" < "$ROOT/devices/oneplus7pro/kernel/display/panel-60-90hz.patch"
fdtput -t s "$TREE/bringup-guacamole.dtb" /soc@0/cpufreq@18323000 status okay
make -C "$TREE" ARCH=arm64 LLVM=1 KBUILD_BUILD_VERSION=191 -j"${JOBS:-8}" Image > "$OUT/build.log" 2>&1
BOOT_CMDLINE=$(fdtget -ts "$TREE/bringup-guacamole.dtb" /chosen bootargs) \
    bash "$ROOT/scripts/pack_hdr2_boot.sh" "$TREE/arch/arm64/boot/Image" \
    "$ROOT/out/cpu-test/restore-ramdisk.gz" "$TREE/bringup-guacamole.dtb" "$OUT/boot.img"
cp "$TREE/bringup-guacamole.dtb" "$TREE/.config" "$TREE/include/generated/utsrelease.h" \
    "$TREE/include/generated/utsversion.h" "$OUT/"
(cd "$OUT" && sha256sum boot.img bringup-guacamole.dtb .config utsrelease.h utsversion.h build.log > SHA256SUMS)
