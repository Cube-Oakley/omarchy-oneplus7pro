#!/bin/sh
# Volatile USB-only link. No default route, DNS, or block-device mounts.
log() { printf '<5>PIXEL USB NET: %s\n' "$*" >/dev/kmsg; }
tries=0
while [ ! -e /sys/class/net/usb0 ]; do
    tries=$((tries + 1))
    [ "$tries" -lt 15 ] || { log 'usb0 missing'; exit 1; }
    sleep 1
done
ip link set lo up
ip addr add 10.77.7.1/30 dev usb0 || exit 1
ip link set usb0 up || exit 1
mkdir -p /run/transfer
{
    echo PIXEL_NATIVE_USB_NETWORK
    uname -a
    cat /sys/devices/system/cpu/online
} >/run/transfer/proof.txt
log 'usb0=10.77.7.1/30 ready; transfer listeners are started explicitly via serial'
