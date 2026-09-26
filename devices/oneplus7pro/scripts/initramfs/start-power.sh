#!/bin/busybox sh
# Keep the verified USB/GPU/touch/display ordering, then enable power hardware.
set -eu
attempt=0
while ! busybox grep -q NATIVE_DESKTOP_STARTED /newroot/root/native-desktop-start.log; do
    [ "$attempt" -lt 180 ] || { echo 'Power setup: desktop did not become ready'; exit 1; }
    busybox sleep 1
    attempt=$((attempt + 1))
done
busybox insmod /hypr/power/power_support.ko
attempt=0
while [ ! -f /sys/class/power_supply/pm8150b-charger/online ]; do
    [ "$attempt" -lt 30 ] || { echo 'Power setup: charger probe incomplete'; exit 1; }
    busybox sleep 1
    attempt=$((attempt + 1))
done
busybox cat /sys/class/power_supply/pm8150b-charger/uevent
busybox cat /sys/class/power_supply/bq27541-0/uevent
echo POWER_SUPPORT_READY
echo 'guacamole-init: POWER_SUPPORT_READY' > /dev/kmsg
