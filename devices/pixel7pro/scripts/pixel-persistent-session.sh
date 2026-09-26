#!/bin/bash
# Executed inside the persistent Arch root by the recovery initramfs.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin HOME=/root USER=root LOGNAME=root
[[ $(cat /etc/omarchy-mobile-pixel-root) == v1 ]]
[[ $(stat -f -c %T /) == ext2/ext3 ]]
mkdir -p /run/sshd /run/omarchy-mobile
for n in {1..30}; do
    ip -4 addr show dev usb0 | grep -q '10.77.7.1/30' && break
    sleep 1
done
/usr/bin/sshd -t -f /etc/ssh/sshd_config.pixel
/usr/bin/sshd -f /etc/ssh/sshd_config.pixel -E /run/sshd-pixel.log
echo 1 >/sys/module/pixel_acpm/parameters/activate
sleep 1
# The thermal path must be active before enabling CPU scaling and the GPU.
zones=(/sys/class/thermal/thermal_zone*/temp)
[[ ${#zones[@]} -ge 7 ]]
for zone in "${zones[@]}"; do
    temp=$(cat "$zone")
    [[ $temp -gt 0 && $temp -lt 80000 ]]
done
echo 1 >/sys/module/pixel_acpm/parameters/cpufreq
echo 1 >/sys/module/pixel_gpu/parameters/domains
sleep 1
echo 1 >/sys/module/pixel_gpu/parameters/cycle
echo 1 >/sys/module/pixel_gpu/parameters/render
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    echo schedutil >"$policy/scaling_governor"
done
insmod /proc/1/root/lib/modules/pixel/pixel-powerkey.ko
insmod /proc/1/root/lib/modules/pixel/pixel_touch_input.ko probe=1 seconds=0
/root/pixel-gpu-session-start.sh
date -u +%FT%TZ >>/var/log/pixel-native-boots.log
