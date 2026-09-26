#!/usr/bin/env bash
# Runs on the phone, one stage per call; nothing unloads, reboot to undo.
#   power         - RPMh hold, then camcc; checks the rail votes did not move
#   bus [SLOT]    - media, CCI and CAMSS drivers, the camera overlay for SLOT,
#                   PM8009 rebind, the focus actuator; no sensor is powered
#   sensor [SLOT] - the sensor driver: powers SLOT and reads its ID
# SLOT is main (IMX586, the default), tele (S5K3M5), wide (IMX481) or rear
# (all three); one per boot, since the first overlay refuses a second.
# Details: docs/camera-20260922.md, docs/camera-telephoto-20260924.md,
# docs/camera-ultrawide-20260924.md.
set -euo pipefail
D=/root/camera-bringup
[[ $(uname -r) == 6.17.0-sm8150-codex-native5-g379d8fe35c7c-dirty ]]
stage=${1:?usage: phone-camera-test.sh power|bus|sensor [main|tele|wide|rear]}
case ${2:-main} in
    main) overlay=guacamole_camera; sensors=imx586; client=-001a ;;
    tele) overlay=guacamole_camera_tele; sensors=s5k3m5; client=-0010 ;;
    wide) overlay=guacamole_camera_wide; sensors=imx481; client=-001a ;;
    rear) overlay=guacamole_camera_rear; sensors="imx586 s5k3m5 imx481"; client='-001a|-0010' ;;
    *) echo 'SLOT is main, tele, wide or rear' >&2; exit 2 ;;
esac
log=$D/$stage-$(date +%Y%m%d-%H%M%S).log
marker="guacamole camera $stage $(date +%s)"
load() { [[ -d /sys/module/${1//-/_} ]] && echo "$1 already loaded" || { insmod "$2/$1.ko"; echo "loaded $1"; }; }
kernel() { dmesg | sed -n "/$marker/,\$p" | grep -vE 'memory leak will occur'; }
echo "$marker" > /dev/kmsg
{
case $stage in
power)
    (cd "$D/power" && sha256sum -c --quiet SHA256SUMS)
    . "$D/power/arc.sh"
    load rpmh_votes "$D/power"
    echo "before: synced=$(synced) $(arc)"
    load guacamole_rpmhpd_hold "$D/power"
    load camcc-sm8150 "$D/power"
    sleep 2
    echo "after:  synced=$(synced) $(arc)"
    ;;
bus)
    [[ -d /sys/module/camcc_sm8150 && -d /sys/module/guacamole_rpmhpd_hold ]]
    (cd "$D/modules" && sha256sum -c --quiet SHA256SUMS)
    (cd "$D/overlay" && sha256sum -c --quiet SHA256SUMS)
    for m in $(grep -vxE 'i2c-qcom-cci|imx586|s5k3m5|imx481' "$D/modules/load-order"); do load "$m" "$D/modules"; done
    # The CCI driver loads only after the overlay: probing mid-apply let the
    # I2C core take its i2c-bus@N nodes for clients, which failed the apply.
    load "$overlay" "$D/overlay"
    # LDO1/3/4 of PM8009 are new children of an already bound device.
    pm8009=18200000.rsc:pm8009-rpmh-regulators
    echo "$pm8009" > /sys/bus/platform/drivers/qcom-rpmh-regulator/unbind
    echo "$pm8009" > /sys/bus/platform/drivers/qcom-rpmh-regulator/bind
    load i2c-qcom-cci "$D/modules"
    # The sensor completes only once its focus actuator has bound.
    (cd "$D/lens" && sha256sum -c --quiet SHA256SUMS)
    load lc898217xc "$D/lens"
    load ak7375 "$D/lens"
    sleep 2
    kernel
    echo '=== i2c adapters'; grep -H . /sys/bus/i2c/devices/i2c-*/name | grep -i cci || true
    echo '=== clients'; ls /sys/bus/i2c/devices | grep -E -- "$client|-007[24]|-000c" || true
    echo '=== pm8009'; for r in /sys/class/regulator/regulator.*; do
        [[ $(readlink -f "$r/device") == */$pm8009 ]] && echo "$(cat "$r/name") $(cat "$r/microvolts" 2>/dev/null) users=$(cat "$r/num_users")"; done
    echo '=== bound'; for p in ac4a000.cci ac4b000.cci acb3000.camss; do echo "$p $(readlink /sys/bus/platform/devices/$p/driver || echo unbound)"; done
    ;;
sensor)
    [[ -d /sys/module/$overlay ]]
    for sensor in $sensors; do load "$sensor" "$D/modules"; done
    sleep 2
    kernel
    echo '=== media'; ls /dev/media* /dev/video* /dev/v4l-subdev* 2>/dev/null | tr '\n' ' '; echo
    ;;
esac
} 2>&1 | tee "$log"
echo "log: $log"
