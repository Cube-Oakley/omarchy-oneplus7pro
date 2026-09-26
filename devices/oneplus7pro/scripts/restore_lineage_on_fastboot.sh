#!/usr/bin/env bash
# Wait until guacamole shows up in fastboot, then restore Lineage 23.2 slot A.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOS="$ROOT/.work/firmware/payload-out"
LOG="$ROOT/out/restore-lineage.log"
DEADLINE=$(date -d '2026-09-15 23:59:00 PDT' +%s)

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOG"; }

log "waiting for fastboot to restore Lineage"

while :; do
  if timeout 2 fastboot devices 2>/dev/null | grep -q fastboot; then
    break
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "ACTION_REQUIRED: 2pm_checkin still_no_fastboot"
    exit 0
  fi
  sleep 2
done

log "fastboot seen"
fastboot getvar current-slot 2>&1 | tee -a "$LOG" || true
fastboot getvar unlocked 2>&1 | tee -a "$LOG" || true
fastboot oem device-info 2>&1 | tee -a "$LOG" || true

log "flash Lineage boot/dtbo/vbmeta to both slots"
fastboot flash boot_a "$LOS/boot.img"
fastboot flash boot_b "$LOS/boot.img"
fastboot flash dtbo_a "$LOS/dtbo.img"
fastboot flash dtbo_b "$LOS/dtbo.img"
fastboot --disable-verity --disable-verification flash vbmeta_a "$LOS/vbmeta.img" || fastboot flash vbmeta_a "$LOS/vbmeta.img"
fastboot --disable-verity --disable-verification flash vbmeta_b "$LOS/vbmeta.img" || true
fastboot set_active a
log "reboot"
fastboot reboot

result=timeout
for i in $(seq 1 60); do
  usb=$(lsusb 2>/dev/null | grep -E '18d1:d00d|22d9:|1d6b:0104' || true)
  fb=$(timeout 2 fastboot devices 2>/dev/null || true)
  adb=$(timeout 2 adb devices 2>/dev/null | awk 'NR>1 && NF{print}' || true)
  if echo "$usb" | grep -q '22d9:'; then
    sleep 3
    slot=$(timeout 8 adb shell getprop ro.boot.slot_suffix 2>/dev/null | tr -d '\r' || true)
    krn=$(timeout 8 adb shell uname -r 2>/dev/null | tr -d '\r' || true)
    ver=$(timeout 8 adb shell getprop ro.lineage.version 2>/dev/null | tr -d '\r' || true)
    result="lineage slot=$slot kernel=$krn ver=$ver"
    break
  fi
  if echo "$fb" | grep -q fastboot; then
    result="bounced_fastboot"
    break
  fi
  if echo "$usb" | grep -q '18d1:d00d'; then
    result="fastboot_usb"
    break
  fi
  sleep 1
done
log "RESULT $result"
echo "DONE: $result"
exit 0
