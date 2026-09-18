#!/usr/bin/env bash
# Classify phone USB after an ABL experiment. Prints one DONE/FAILED/ACTION line.
set -euo pipefail
SECONDS_WAIT="${1:-90}"
LOG="${2:-/tmp/grok-goal-d067b137fc5d/implementer/abl-watch.log}"
REACH=/tmp/grok-goal-d067b137fc5d/implementer/usb-reachability.log
: >"$LOG"
echo "$(date +%H:%M:%S) settle 5s then watch ${SECONDS_WAIT}s" | tee -a "$LOG"
sleep 5
start=$(date +%s)
blips=0
last=""
while [ $(($(date +%s) - start)) -lt "$SECONDS_WAIT" ]; do
  usb=$(lsusb 2>/dev/null | grep -E '18d1:d00d|18d1:4ee7|22d9:|1d6b:0104|1d6b:0103|0525:a4a2|05c6:900e|05c6:9008' || true)
  fb=$(timeout 1 fastboot devices 2>/dev/null | grep -v '^$' || true)
  adb=$(timeout 1 adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print}' || true)
  now=$(date +%H:%M:%S)
  if [ "$usb" != "$last" ]; then
    echo "$now usb='$usb' fb='$fb'" | tee -a "$LOG"
    last="$usb"
    blips=$((blips + 1))
  fi
  if echo "$usb" | grep -q '1d6b:0104\|1d6b:0103\|0525:a4a2'; then
    echo "DONE: gadget $usb" | tee -a "$LOG"
    {
      echo "time=$(date -Is) usb=$usb"
      lsusb
      ip -br link
      ip -br addr
      ping -c 3 -W 1 172.16.42.1 || true
      echo "--- dmesg usb ---"
      dmesg -T | tail -n 80
    } >"$REACH" 2>&1
    echo "wrote $REACH" | tee -a "$LOG"
    exit 0
  fi
  if echo "$usb" | grep -q '05c6:900e\|05c6:9008'; then
    echo "FAILED: crashdump $usb" | tee -a "$LOG"
    exit 1
  fi
  if echo "$fb" | grep -q fastboot || echo "$usb" | grep -q '18d1:d00d'; then
    echo "DONE: fastboot (ABL bounced or PSCI/PON reached bootloader)" | tee -a "$LOG"
    exit 0
  fi
  if echo "$usb" | grep -q '22d9:' && [ -n "$adb" ]; then
    sleep 2
    krn=$(timeout 8 adb shell uname -r 2>/dev/null | tr -d '\r' || true)
    slot=$(timeout 8 adb shell getprop ro.boot.slot_suffix 2>/dev/null | tr -d '\r' || true)
    echo "DONE: android kernel=$krn slot=$slot (fell back or PSCI rebooted to A)" | tee -a "$LOG"
    exit 0
  fi
  sleep 1
done
if [ "$blips" -gt 2 ]; then
  echo "DONE: usb_blips=$blips (likely PSCI reset loop, no stable identity)" | tee -a "$LOG"
  exit 0
fi
echo "FAILED: timeout no USB (${SECONDS_WAIT}s) blips=$blips — hardware reset needed" | tee -a "$LOG"
exit 1
