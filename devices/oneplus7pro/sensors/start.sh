#!/usr/bin/env bash
# Sensors for the root/chroot session (docs/sensors-20260924.md), once per boot:
# start the sensor DSP (SLPI) with the chosen firmware set, rebuild the tree
# hexagonrpcd serves it (vendor files and a fresh copy of persist's registry;
# persist is only read), and start hexagonrpcd, whose single attach creates
# the sensors domain. The steps are phone-sensors-test.sh's, installed as
# /root/sensors-bringup/bin/sensors-test. Then iio-sensor-proxy, which reads
# the sensors through libssc and serves them on D-Bus (net.hadess.SensorProxy);
# its udev rule (81-guacamole-sensors.rules) adds the accelerometer. SLPI
# cannot be restarted: to change anything, reboot. Installed as
# /usr/local/sbin/guacamole-sensors-start and enabled by
# /root/sensors-bringup/autostart-enabled.
set -euo pipefail
BASE=/root/sensors-bringup
FW=/lib/firmware/qcom/sm8150/oneplus/guacamole
[[ -f $BASE/autostart-enabled ]] || exit 0
# Kernel #193's carve-out map; the SLPI overlay refuses older ones anyway.
if ! uname -v | grep -Eq '^#(19[3-9]|2[0-9][0-9]) '; then
    echo 'Kernel before #193: sensors not started.'
    exit 0
fi
exec 8>/run/guacamole-sensors.lock
flock -n 8 || exit 0
[[ ! -e /run/guacamole-sensors.attempted ]] || exit 0
touch /run/guacamole-sensors.attempted
echo "SENSORS_BOOT $(cat /proc/sys/kernel/random/boot_id) $(date -Is)"
trap 'echo "Sensor startup failed at line $LINENO." >&2' ERR
# pd-mapper must serve SLPI's domains before the sensors domain exists; the
# radio start loads it. Start after the radio, so the DSPs boot one at a time.
for _ in $(seq 1 300); do
    [[ -e /run/guacamole-radio.ready ]] && break
    sleep 1
done
[[ -e /run/guacamole-radio.ready ]] || echo 'Radio not ready after 300 s; continuing.'
[[ -d /sys/module/qcom_pd_mapper ]]
set=$(cat "$BASE/firmware/active")
(cd "$FW" && sha256sum -c --quiet "$BASE/firmware/$set/SHA256SUMS")
echo "SLPI firmware set $set"
bash "$BASE/bin/sensors-test" start
bash "$BASE/bin/sensors-test" tree
bash "$BASE/bin/sensors-test" serve
ls -t "$BASE"/logs/hexagonrpcd-*.log | tail -n +11 | xargs -r rm --
touch /run/guacamole-sensors.ready
echo 'SENSORS_READY'
# iio-sensor-proxy 3.9 takes its D-Bus name before it has found the sensors,
# and a claim in between is lost; start it once the accelerometer publishes.
# There is no system manager here to activate it on demand.
for _ in $(seq 1 40); do
    python3 "$BASE/bin/ssc_census.py" accel | grep -E '^accel +[0-9a-f]{32}' >/dev/null && break
    sleep 1
done
if ! pgrep -x iio-sensor-prox >/dev/null; then
    setsid /usr/lib/iio-sensor-proxy > "$BASE/logs/iio-sensor-proxy.log" 2>&1 < /dev/null &
    echo "iio-sensor-proxy $!"
fi
