#!/usr/bin/env bash
# Native5 RTC/touch-resume image, with the verified native4 Wi-Fi rollback.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/phone-config.sh"
SERIAL=$(phone_serial)
TEST="$ROOT/out/checkpoints/20260917-native5-test"
ROLLBACK="$ROOT/out/checkpoints/20260917-native4-test"
case ${1:-test} in
    test) IMAGE="$TEST" ;;
    rollback) IMAGE="$ROLLBACK" ;;
    *) echo 'Usage: flash_suspend_desktop.sh [test|rollback]' >&2; exit 2 ;;
esac
(cd "$TEST" && sha256sum -c SHA256SUMS)
(cd "$ROLLBACK" && sha256sum -c SHA256SUMS)
if ! timeout 5 fastboot devices | awk '{print $1}' | grep -Fxq "$SERIAL"; then
    echo "Phone $SERIAL is not in fastboot; no changes made." >&2
    exit 1
fi
fastboot -s "$SERIAL" getvar current-slot
fastboot -s "$SERIAL" flash boot_b "$IMAGE/boot.img"
fastboot -s "$SERIAL" flash dtbo_b "$IMAGE/dtbo.img"
fastboot -s "$SERIAL" set_active b
fastboot -s "$SERIAL" reboot
