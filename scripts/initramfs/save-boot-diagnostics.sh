#!/bin/busybox sh
# Preserve evidence from boots where the display works but USB does not.
set -eu
busybox grep -q ' /newroot ext4 ' /proc/mounts || exit 1
boot_id=$(busybox cat /proc/sys/kernel/random/boot_id)
dest="/newroot/root/bringup-logs/$boot_id"
busybox mkdir -p "$dest"
busybox uname -a > "$dest/kernel.txt"
busybox cat /proc/cmdline > "$dest/cmdline.txt"
busybox cat /proc/cpuinfo > "$dest/cpuinfo.txt"
busybox cat /proc/mounts > "$dest/mounts.txt"

# Capture immediately, then at +15, +45, +90, and +150 seconds.
for delay in 0 15 30 45 60; do
    busybox sleep "$delay"
    {
        busybox cat /proc/uptime
        for state in possible present online offline; do
            echo "CPU $state"
            busybox cat "/sys/devices/system/cpu/$state"
        done
        busybox ls -l /dev/dri 2>/dev/null || true
        busybox ip addr show usb0 2>/dev/null || true
        for udc in /sys/class/udc/*; do
            [ -e "$udc" ] || continue
            echo "$udc"
            busybox cat "$udc/state" "$udc/current_speed" 2>/dev/null || true
        done
        busybox cat /sys/kernel/config/usb_gadget/g1/UDC 2>/dev/null || true
        busybox ps
    } >> "$dest/state.log"
    busybox dmesg > "$dest/dmesg.log.new"
    busybox mv "$dest/dmesg.log.new" "$dest/dmesg.log"
    busybox sync
done
