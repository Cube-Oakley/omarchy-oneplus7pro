#!/usr/bin/env bash
# Flash only the prepared native2 desktop image on this handset's slot B.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/phone-config.sh"
SERIAL=$(phone_serial)
TEST="$ROOT/out/checkpoints/20260917-native2-test"
ROLLBACK="$ROOT/out/checkpoints/20260916-touch1"
(cd "$TEST" && sha256sum -c SHA256SUMS)
(cd "$ROLLBACK" && sha256sum -c SHA256SUMS)
if ! timeout 5 fastboot devices | awk '{print $1}' | grep -Fxq "$SERIAL"; then
    echo "Phone $SERIAL is not in fastboot; no changes made." >&2
    exit 1
fi
fastboot -s "$SERIAL" getvar current-slot
fastboot -s "$SERIAL" flash boot_b "$TEST/boot.img"
fastboot -s "$SERIAL" flash dtbo_b "$TEST/dtbo.img"
fastboot -s "$SERIAL" set_active b
fastboot -s "$SERIAL" reboot
