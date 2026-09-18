#!/usr/bin/env bash
# Flash gpu2: the validated Adreno desktop launcher starts automatically at boot.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/phone-config.sh"
SERIAL=$(phone_serial)
CHECKPOINT="$ROOT/out/checkpoints/20260916-gpu2-desktop"
cd "$CHECKPOINT"
sha256sum -c SHA256SUMS
if ! timeout 5 fastboot devices | awk '{print $1}' | grep -Fxq "$SERIAL"; then
  echo "Phone $SERIAL is not in fastboot; no changes made." >&2
  exit 1
fi
fastboot -s "$SERIAL" getvar current-slot
fastboot -s "$SERIAL" flash boot_b "$CHECKPOINT/boot.img"
fastboot -s "$SERIAL" flash dtbo_b "$CHECKPOINT/dtbo.img"
fastboot -s "$SERIAL" set_active b
fastboot -s "$SERIAL" reboot
