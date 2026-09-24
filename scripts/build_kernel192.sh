#!/usr/bin/env bash
# Build-only: kernel #192 = #191 (scripts/build_kernel191.sh) plus
#   - DSI: wait for a command-mode frame to finish before sending a command,
#     which stops the brightness flicker (devices/oneplus7pro/kernel/display/
#     dsi-cmd-mode-idle-wait.patch, docs/controls-20260923.md);
#   - the soft and buddy hard lockup detectors, panicking on a lockup, and a
#     reboot 10 s after a panic;
#   - crash-dump mode cleared at boot (qcom,dload-mode on the SCM node, at
#     TCSR_BOOT_MISC_DETECT, 0x1fd3000), so a crash or watchdog reset reboots
#     instead of stopping in 05c6:900e;
#   - ramoops at the stock 0xa9800000, so the log of a crash survives;
#   - PM8150L's second slave id enabled, so the flash needs no runtime SPMI
#     registration.
# The lockup detectors change no structure a module sees (their interrupt
# storm check, which adds a per-IRQ statistics field, stays off), and the release
# string is unchanged, so every existing module loads.
# Output: out/checkpoints/20260923-kernel192/.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/.work/linux-sm8150-191"
TREE="$ROOT/.work/linux-sm8150-192"
OUT="$ROOT/out/checkpoints/20260923-kernel192"
DTB="$TREE/bringup-guacamole.dtb"
[[ -d $BASE ]] || bash "$ROOT/scripts/build_kernel191.sh"
rm -rf "$TREE" "$OUT"
mkdir -p "$OUT"
cp -a --reflink=auto "$BASE" "$TREE"
patch -s -p1 -d "$TREE" < "$ROOT/devices/oneplus7pro/kernel/display/dsi-cmd-mode-idle-wait.patch"

"$TREE/scripts/config" --file "$TREE/.config" -e SOFTLOCKUP_DETECTOR -e HARDLOCKUP_DETECTOR \
    -d SOFTLOCKUP_DETECTOR_INTR_STORM
make -C "$TREE" ARCH=arm64 LLVM=1 olddefconfig > /dev/null
# Only the lockup detector options may change.
changed=$(diff <(grep '^CONFIG_' "$BASE/.config") <(grep '^CONFIG_' "$TREE/.config") | grep '^[<>]' |
    grep -v -E 'CONFIG_(SOFTLOCKUP_DETECTOR|HARDLOCKUP_DETECTOR|HARDLOCKUP_DETECTOR_BUDDY|HARDLOCKUP_DETECTOR_COUNTS_HRTIMER|LOCKUP_DETECTOR|SOFTLOCKUP_DETECTOR_INTR_STORM|BOOTPARAM_SOFTLOCKUP_PANIC|BOOTPARAM_HARDLOCKUP_PANIC)=' || true)
[[ -z $changed ]] || { printf 'Unexpected config changes:\n%s\n' "$changed" >&2; exit 1; }

fdtput -t s "$DTB" /reserved-memory/ramoops@a9800000 status okay
tcsr=$(fdtget -t x "$DTB" /soc@0/syscon@1f60000 phandle)
fdtput -t x "$DTB" /firmware/scm qcom,dload-mode "$tcsr" 73000
fdtput -t s "$DTB" /soc@0/spmi@c440000/pmic@5 status okay
fdtput -t s "$DTB" /chosen bootargs \
    "$(fdtget -ts "$DTB" /chosen bootargs) panic=10 softlockup_panic=1 nmi_watchdog=panic"

make -C "$TREE" ARCH=arm64 LLVM=1 KBUILD_BUILD_VERSION=192 -j"${JOBS:-8}" Image > "$OUT/build.log" 2>&1
BOOT_CMDLINE=$(fdtget -ts "$DTB" /chosen bootargs) \
    bash "$ROOT/scripts/pack_hdr2_boot.sh" "$TREE/arch/arm64/boot/Image" \
    "$ROOT/out/cpu-test/restore-ramdisk.gz" "$DTB" "$OUT/boot.img"
cp "$DTB" "$TREE/.config" "$TREE/include/generated/utsrelease.h" \
    "$TREE/include/generated/utsversion.h" "$OUT/"
(cd "$OUT" && sha256sum boot.img bringup-guacamole.dtb .config utsrelease.h utsversion.h build.log > SHA256SUMS)
