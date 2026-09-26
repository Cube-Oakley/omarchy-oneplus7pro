#!/usr/bin/env bash
# Silent until the phone enumerates or 2pm PDT check-in. One line to stdout.
set -euo pipefail
DEADLINE=$(date -d '2026-09-14 14:00:00 PDT' +%s)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOG="$ROOT/out/usb-watch.log"
mkdir -p "$(dirname "$LOG")"
prev=none
while :; now=$(date +%s); do
  usb=$(lsusb 2>/dev/null | grep -E '18d1:d00d|18d1:4ee7|22d9:|1d6b:0104|0525:a4a2|0525:a4a1|1d6b:0103|1d6b:0109|05c6:9008|05c6:900e' || true)
  fb=$(timeout 1 fastboot devices 2>/dev/null | awk 'NF{print}' || true)
  adb=$(timeout 1 adb devices 2>/dev/null | awk 'NR>1 && NF{print}' || true)
  if echo "$usb" | grep -qE '1d6b:0104|0525:a4a2|0525:a4a1|1d6b:0103|1d6b:0109'; then
    echo "DONE: gadget $usb"
    exit 0
  fi
  if [ -n "$fb" ]; then
    echo "ACTION_REQUIRED: fastboot $fb usb=$usb"
    exit 0
  fi
  if echo "$adb" | grep -qE 'device|recovery|sideload'; then
    echo "ACTION_REQUIRED: adb $adb usb=$usb"
    exit 0
  fi
  if echo "$usb" | grep -qE '05c6:9008|05c6:900e'; then
    echo "ACTION_REQUIRED: edl_or_diag $usb"
    exit 0
  fi
  state=none
  [ -n "$usb" ] && state=usb
  if [ "$state" != "$prev" ]; then
    echo "$(date +%H:%M:%S) state=$state usb='$usb'" >>"$LOG"
    prev=$state
  fi
  if [ "$now" -ge "$DEADLINE" ]; then
    echo "ACTION_REQUIRED: 2pm_checkin no_phone"
    exit 0
  fi
  sleep 3
done
