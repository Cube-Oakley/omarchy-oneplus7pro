#!/usr/bin/env bash
# Wait for fastboot, flash the current bring-up boot.img to slot A, observe USB.
# Restores Lineage boot_a if FLASH_RESTORE_LINEAGE=1 or the bring-up image is missing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${FLASH_IMG:-$ROOT/out/pmos/boot-entrylayout.img}"
LOS_BOOT="$ROOT/.work/firmware/payload-out/boot.img"
LOS_VBMETA="$ROOT/.work/firmware/payload-out/vbmeta.img"
VBMETA_DIS="${VBMETA_DIS:-/tmp/vbmeta-disabled.img}"
LOG="$ROOT/out/flash-slotA.log"
TIMEOUT_BOOT="${TIMEOUT_BOOT:-45}"

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }

wait_fastboot() {
  local i
  for i in $(seq 1 40); do
    if timeout 2 fastboot devices 2>/dev/null | grep -q fastboot; then
      return 0
    fi
    sleep 1
  done
  return 1
}

classify() {
  local i usb fb adb slot krn
  for i in $(seq 1 "$TIMEOUT_BOOT"); do
    usb=$(lsusb 2>/dev/null | grep -E '18d1:d00d|22d9:|1d6b:0104|0525:a4a2|0525:a4a1|1d6b:0103|1d6b:0109' || true)
    fb=$(timeout 2 fastboot devices 2>/dev/null || true)
    adb=$(timeout 2 adb devices 2>/dev/null | awk 'NR>1 && NF{print}' || true)
    if echo "$usb" | grep -qE '1d6b:0104|0525:a4a2|0525:a4a1|1d6b:0103|1d6b:0109'; then
      echo "gadget $usb"
      return 0
    fi
    if echo "$fb" | grep -q fastboot; then
      echo "fastboot $usb"
      return 0
    fi
    if echo "$adb" | grep -qE 'device|recovery|sideload'; then
      slot=$(timeout 6 adb shell getprop ro.boot.slot_suffix 2>/dev/null | tr -d '\r')
      krn=$(timeout 6 adb shell uname -r 2>/dev/null | tr -d '\r')
      echo "adb slot=$slot kernel=$krn usb=$usb"
      return 0
    fi
    sleep 1
  done
  echo "timeout $(lsusb | grep -E '18d1|22d9|1d6b|0525' || echo none)"
}

log "wait for fastboot"
if ! wait_fastboot; then
  log "no fastboot"
  echo NO_FASTBOOT
  exit 2
fi
fastboot getvar current-slot 2>&1 | tee -a "$LOG" || true
fastboot getvar unlocked 2>&1 | tee -a "$LOG" || true

if [ "${FLASH_RESTORE_LINEAGE:-0}" = 1 ] || [ ! -s "$IMG" ]; then
  log "RESTORE Lineage boot_a + vbmeta_a"
  fastboot flash boot_a "$LOS_BOOT"
  fastboot flash vbmeta_a "$LOS_VBMETA" || fastboot flash vbmeta_a --disable-verity --disable-verification "$LOS_VBMETA" || true
  fastboot set_active a
  fastboot reboot
  result=$(classify)
  log "RESULT $result"
  echo "$result"
  exit 0
fi

log "FLASH $IMG -> boot_a"
fastboot flash boot_a "$IMG"
if [ -s "$VBMETA_DIS" ]; then
  fastboot flash vbmeta_a "$VBMETA_DIS" || true
else
  fastboot --disable-verity --disable-verification flash vbmeta_a "$LOS_VBMETA" || true
fi
fastboot set_active a
fastboot reboot
result=$(classify)
log "RESULT $result"
echo "$result"
