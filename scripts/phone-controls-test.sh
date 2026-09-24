#!/usr/bin/env bash
# Runs on the phone, one stage per call; nothing unloads, reboot to undo.
# Modules from scripts/build_controls.sh, in /root/controls-bringup/modules.
#   slider  - the alert slider as gpio-keys ("Alert slider", ABS 0x22)
#   haptics - i2c7, the AW8697 node, then its driver
#   flash   - PM8150L slave id 5, its flash block, then leds-qcom-flash
# Details: docs/controls-20260923.md.
set -euo pipefail
D=/root/controls-bringup/modules
[[ $(uname -r) == 6.17.0-sm8150-codex-native5-g379d8fe35c7c-dirty ]]
stage=${1:?usage: phone-controls-test.sh slider|haptics|flash}
(cd "$D" && sha256sum -c --quiet SHA256SUMS)
marker="guacamole controls $stage $(date +%s)"
echo "$marker" > /dev/kmsg
load() { [[ -d /sys/module/${1//-/_} ]] && echo "$1 already loaded" || { insmod "$D/$1.ko"; echo "loaded $1"; }; }
kernel() { dmesg | sed -n "/$marker/,\$p" | tail -n +2; }
case $stage in
slider)
    load guacamole_alert_slider
    sleep 1
    grep -B1 -A4 'Name="Alert slider"' /proc/bus/input/devices || echo "no Alert slider input device"
    ;;
haptics)
    load guacamole_haptics
    sleep 1
    load aw8697-haptics
    sleep 1
    grep -B1 -A4 'Name="Awinic AW8697 haptics"' /proc/bus/input/devices || echo "no haptics input device"
    ;;
flash)
    load leds-qcom-flash
    load guacamole_flash
    sleep 1
    ls /sys/class/leds | grep -E 'torch|flash' || echo "no flash LEDs"
    ;;
*)
    echo "unknown stage $stage" >&2
    exit 1
    ;;
esac
kernel
