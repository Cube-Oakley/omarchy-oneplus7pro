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
# The flash's loader registers PM8150L slave id 5 on the SPMI bus.
for m in guacamole_alert_slider guacamole_haptics aw8697-haptics leds-qcom-flash guacamole_flash; do
    if [[ ! -d /sys/module/${m//-/_} ]]; then
        insmod "$M/$m.ko" && echo "loaded $m" || echo "$m failed to load" >&2
    fi
done
