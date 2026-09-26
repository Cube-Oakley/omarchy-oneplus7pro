#!/usr/bin/env bash
# On fastboot: restore Lineage to slot A, flash GDSC/SMMU 6.17 to slot B, reboot B.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOS="$ROOT/.work/firmware/payload-out"
BOOT="$ROOT/out/pmos/boot-embed-fbusb.img"
DTBO="$ROOT/out/dtbo-filtered-fbusb.img"
LOG="$ROOT/out/flash-gdsc.log"
DEADLINE=$(date -d '2026-09-16 23:59:00 PDT' +%s)
WATCH="$ROOT/scripts/watch_abl_usb.sh"
SCRATCH=/tmp/grok-goal-d067b137fc5d/implementer

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }

[ -s "$BOOT" ] || { echo "missing $BOOT"; exit 1; }
[ -s "$DTBO" ] || { echo "missing $DTBO"; exit 1; }

log "waiting for fastboot to flash FB+USB clk_ignore baked"
while :; do
  if timeout 2 fastboot devices 2>/dev/null | grep -q fastboot; then
    break
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "ACTION_REQUIRED: still_no_fastboot"
    exit 0
  fi
  sleep 2
done

log "fastboot seen"
fastboot getvar current-slot 2>&1 | tee -a "$LOG" || true

log "restore Lineage to slot A"
fastboot flash boot_a "$LOS/boot.img"
fastboot flash dtbo_a "$LOS/dtbo.img"
fastboot --disable-verity --disable-verification flash vbmeta_a "$LOS/vbmeta.img" || fastboot flash vbmeta_a "$LOS/vbmeta.img"

log "flash 6.17 FB+USB no freeze to slot B"
fastboot flash boot_b "$BOOT"
fastboot flash dtbo_b "$DTBO"
fastboot --disable-verity --disable-verification flash vbmeta_b "$LOS/vbmeta.img" || true
fastboot set_active b
log "reboot slot B"
fastboot reboot

"$WATCH" 90 "$SCRATCH/usb-gdsc.log"
rc=$?
log "watch rc=$rc"
exit "$rc"
