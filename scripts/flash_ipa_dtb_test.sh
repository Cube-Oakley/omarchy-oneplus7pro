#!/usr/bin/env bash
# Flash only slot B's boot image: #189 (#188 plus the embedded IPA DTB), or #188 back.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/phone-config.sh"
SERIAL=$(phone_serial)
TEST="$ROOT/out/checkpoints/20260922-ipa-kernel189-test"
ROLLBACK="$ROOT/out/checkpoints/20260918-mmcx-sleep-test"
case ${1:-test} in
    test) IMAGE="$TEST" ;;
    rollback) IMAGE="$ROLLBACK" ;;
    *) echo 'Usage: flash_ipa_dtb_test.sh [test|rollback]' >&2; exit 2 ;;
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
