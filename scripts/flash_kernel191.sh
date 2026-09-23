#!/usr/bin/env bash
# Flash only slot B's boot image: #191 (#190 plus 60/90 Hz panel modes and CPU frequency scaling in the DTB), or #190 back.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/phone-config.sh"
SERIAL=$(phone_serial)
TEST="$ROOT/out/checkpoints/20260923-kernel191"
ROLLBACK="$ROOT/out/checkpoints/20260923-kernel190"
case ${1:-test} in
    test) IMAGE="$TEST" ;;
    rollback) IMAGE="$ROLLBACK" ;;
    *) echo 'Usage: flash_kernel191.sh [test|rollback]' >&2; exit 2 ;;
esac
(cd "$TEST" && sha256sum -c SHA256SUMS)
(cd "$ROLLBACK" && sha256sum -c SHA256SUMS)
if ! timeout 5 fastboot devices | awk '{print $1}' | grep -Fxq "$SERIAL"; then
    echo "Phone $SERIAL is not in fastboot; no changes made." >&2
    exit 1
fi
slot=$(fastboot -s "$SERIAL" getvar current-slot 2>&1)
printf '%s\n' "$slot"
grep -Eq 'current-slot: *b([[:space:]]|$)' <<< "$slot" || {
    echo 'Expected active slot B; no changes made.' >&2; exit 1;
}
fastboot -s "$SERIAL" flash boot_b "$IMAGE/boot.img"
fastboot -s "$SERIAL" reboot
