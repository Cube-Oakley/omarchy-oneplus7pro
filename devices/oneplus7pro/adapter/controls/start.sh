#!/usr/bin/env bash
# Board controls for the root/chroot session: the alert slider, the vibration
# motor and the rear flash, as runtime overlays and modules built by
# scripts/build_controls.sh. The shell finds them through the input and LED
# classes (omarchy-mobile-controls). Safe to run again; one that fails to load
# does not stop the others. Reboot to unload. Details: docs/controls-20260923.md.
set -euo pipefail
M=/root/controls-bringup/modules
[[ $(uname -r) == 6.17.0-sm8150-codex-native5-g379d8fe35c7c-dirty ]]
exec 8>/run/guacamole-controls.lock
flock -w 60 8
(cd "$M" && sha256sum -c --quiet SHA256SUMS)
load() {
    if [[ ! -d /sys/module/${1//-/_} ]]; then
        insmod "$M/$1.ko" && echo "loaded $1" || echo "$1 failed to load" >&2
    fi
}
load guacamole_alert_slider
load guacamole_haptics
load aw8697-haptics
# The flash's loader reaches the SPMI bus through PM8150L's first slave id,
# which exists only once the boot power overlay has started the bus, some
# 20 s after the desktop.
for i in $(seq 1 240); do
    compgen -G '/sys/bus/spmi/devices/*-04' > /dev/null && break
    sleep 0.5
done
load leds-qcom-flash
load guacamole_flash
