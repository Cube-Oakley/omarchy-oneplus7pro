#!/usr/bin/env bash
# Run with sudo/pkexec after enabling NetworkManager's shared USB profile.
set -euo pipefail
USB_IFACE=${1:-enp198s0f0u2}
UPLINK_IFACE=${2:-enp198s0f4u1u1}
ACTION=${3:-enable}
[[ $EUID == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ $ACTION == enable || $ACTION == disable ]] || exit 2
ip -4 address show dev "$USB_IFACE" | grep -q 'inet 172.16.42.2/24' || {
    echo 'USB interface does not have the expected phone-network address.' >&2
    exit 1
}
ip link show dev "$UPLINK_IFACE" >/dev/null
ufw status verbose
prefix=()
[[ $ACTION == disable ]] && prefix=(--force delete)
ufw "${prefix[@]}" allow in on "$USB_IFACE" from 172.16.42.1 to 172.16.42.2 port 53 proto udp comment 'guacamole USB DNS'
ufw "${prefix[@]}" allow in on "$USB_IFACE" from 172.16.42.1 to 172.16.42.2 port 53 proto tcp comment 'guacamole USB DNS'
ufw "${prefix[@]}" route allow in on "$USB_IFACE" out on "$UPLINK_IFACE" from 172.16.42.1 to any comment 'guacamole USB internet'
ufw status verbose
