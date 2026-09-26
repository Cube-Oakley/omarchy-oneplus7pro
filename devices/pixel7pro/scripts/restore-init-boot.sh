#!/usr/bin/env bash
# Put the phone in fastboot, then run this. Flashes the pre-experiment
# init_boot to BOTH slots and boots slot a.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Prefer the compact Magisk init_boot (~2.2M). The 8MB padded original
# wedges this unit's fastboot USB on SendBuffer.
IMG="$ROOT/out/RESTORE-init_boot-compact.img"
if [[ ! -f "$IMG" ]]; then
  IMG="$ROOT/out/RESTORE-init_boot.img"
fi
[[ -f "$IMG" ]] || { echo "missing $IMG"; exit 1; }
fastboot devices | grep -q fastboot || { echo "not in fastboot"; exit 1; }
fastboot flash init_boot_a "$IMG"
fastboot flash init_boot_b "$IMG"
fastboot set_active a
fastboot reboot
echo "restored init_boot on a+b, rebooting"
