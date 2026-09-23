#!/usr/bin/env bash
# Runs on the phone: starts Bluetooth through the board start script
# (guacamole-bluetooth-start) and shows the kernel's view of the bring-up.
# Loading happens once per boot; a second run only reports. Never rmmod
# hci_uart (its serdev remove path panicked on the 7T Pro); reboot to undo.
set -euo pipefail
D=/root/bluetooth-bringup
log=$D/load-$(date +%Y%m%d-%H%M%S).log
marker="guacamole bluetooth test $(date +%s)"
echo "$marker" > /dev/kmsg
{
    /usr/local/sbin/guacamole-bluetooth-start || echo "START FAILED: $?"
    dmesg | sed -n "/$marker/,\$p" | grep -vE 'socket layer|protocol .* registered|memory leak will occur'
    echo '=== controller'
    btmgmt info 2>&1 | sed -E 's/([0-9A-F]{2}:){5}[0-9A-F]{2}/<addr>/g' | head -6
} 2>&1 | tee "$log"
echo "log: $log"
