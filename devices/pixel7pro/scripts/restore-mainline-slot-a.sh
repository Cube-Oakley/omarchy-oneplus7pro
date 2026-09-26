#!/usr/bin/env bash
# Restore Evolution X kernel+ramdisk on slot A only. Never touches _b.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Matching Sep 8 dump pair + disable-verity. Magisk compact from Sep 9
# plus enabled vbmeta bootlooped (init exit 0x7f00) on 2026-09-12.
# Always restore vendor_kernel_boot_a too — stub-DT flashes replace it.
fastboot flash boot_a "$ROOT/out/device-slot-a/boot.img"
fastboot flash init_boot_a "$ROOT/out/RESTORE-init_boot-dump-compact.img"
fastboot flash vendor_kernel_boot_a "$ROOT/out/device-slot-a/vendor_kernel_boot.img"
fastboot --disable-verity --disable-verification flash vbmeta_a "$ROOT/out/device-slot-a/vbmeta.img"
fastboot set_active a
fastboot reboot
echo "slot A restored to Evolution X"
