#!/bin/busybox sh
# Load the verified guacamole touch setup after GPU/USB startup.
# Keeping the overlay loaded until reboot avoids removing live DT consumers.
set -eu
ROOT=/newroot
MODULE_DIR=${1:-/hypr/touch}
if ! busybox pidof systemd-udevd >/dev/null; then
    busybox chroot "$ROOT" /usr/lib/systemd/systemd-udevd --daemon \
        > "$ROOT/root/udevd.log" 2>&1
fi
for module in evdev s6sy761 touch_overlay; do
    if [ ! -d "/sys/module/$module" ]; then
        busybox insmod "$MODULE_DIR/$module.ko"
    fi
done
attempt=0
found=false
while [ "$attempt" -lt 10 ]; do
    for node in /sys/class/input/event*/device/name; do
        [ -f "$node" ] || continue
        if [ "$(busybox cat "$node")" = s6sy761 ]; then
            found=true
            break
        fi
    done
    "$found" && break
    busybox sleep 1
    attempt=$((attempt + 1))
done
"$found" || { echo 'S6SY761 did not register an evdev device' >&2; exit 1; }
# This is a live system rooted through chroot, not an offline image build.
busybox chroot "$ROOT" /usr/bin/env SYSTEMD_IN_CHROOT=0 \
    /usr/bin/udevadm trigger --action=add --subsystem-match=input
busybox chroot "$ROOT" /usr/bin/env SYSTEMD_IN_CHROOT=0 \
    /usr/bin/udevadm settle --timeout=10
busybox chroot "$ROOT" /usr/bin/env XDG_RUNTIME_DIR=/run/user/0 \
    /usr/bin/timeout -k 1 5 /usr/bin/hyprctl -i 0 devices > "$ROOT/root/touch-devices.log" 2>&1
busybox grep -q s6sy761 "$ROOT/root/touch-devices.log" || {
    echo 'Touchscreen exists but Hyprland has not recognized it' >&2
    exit 1
}
echo 'S6SY761 touchscreen ready in Hyprland' > /dev/kmsg
echo TOUCHSCREEN_READY
