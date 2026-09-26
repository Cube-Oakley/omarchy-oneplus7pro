#!/usr/bin/env bash
# OnePlus native4/native5 chroot boot adapter. Factory storage stays read-only.
set -euo pipefail
BASE=/root/radio-bringup
[[ -f "$BASE/autostart-enabled" ]] || exit 0
[[ $(uname -r) == 6.17.0-sm8150-codex-native[45]-* ]] || exit 0
if [[ ${1:-} != --locked ]]; then
    # --close prevents long-lived radio daemons from inheriting the lock.
    exec flock --nonblock --close /run/guacamole-radio.lock "$0" --locked
fi
# Fail once per boot, rather than repeatedly booting a faulting modem.
[[ ! -e /run/guacamole-radio.attempted ]] || exit 0
touch /run/guacamole-radio.attempted
echo "RADIO_BOOT $(cat /proc/sys/kernel/random/boot_id) $(uname -r)"
trap 'echo "Radio startup failed at line $LINENO; inspect this log before retrying." >&2' ERR
for attempt in $(seq 1 240); do
    [[ -e /sys/class/power_supply/pm8150b-charger/online ]] && break
    sleep 1
done
[[ -e /sys/class/power_supply/pm8150b-charger/online ]]
bash "$BASE/phone-radio-test.sh" prepare
bash "$BASE/phone-radio-test.sh" modem
sleep 1
pgrep -x rmtfs >/dev/null
pgrep -x tqftpserv >/dev/null
modem=
for candidate in /sys/class/remoteproc/*; do
    if grep -q 'sm8150-mpss-pas' "$candidate/device/modalias"; then
        [[ -z $modem ]] || { echo 'Multiple MPSS devices' >&2; exit 1; }
        modem=$candidate
    fi
done
[[ -n $modem ]]
case $(cat "$modem/state") in
    offline) echo start > "$modem/state" ;;
    running) ;;
    *) echo 'MPSS is not in a safe state to start' >&2; exit 1 ;;
esac
for attempt in $(seq 1 20); do
    [[ $(cat "$modem/state") == running ]] && break
    sleep 1
done
[[ $(cat "$modem/state") == running ]]
bash "$BASE/phone-radio-test.sh" wifi
for attempt in $(seq 1 30); do
    [[ -d /sys/class/net/wlan0 ]] && break
    sleep 1
done
[[ -d /sys/class/net/wlan0 ]]
# Native4's frozen early USB helper still installs a metric-zero default.
# Keep USB as fallback, with its direct SSH subnet route unaffected.
if ip -4 route show default | grep -q 'via 172.16.42.2 dev usb0'; then
    ip route replace default via 172.16.42.2 dev usb0 metric 2000
    ip route del default via 172.16.42.2 dev usb0 metric 0 2>/dev/null || true
fi
bash "$BASE/phone-radio-network.sh"
touch /run/guacamole-radio.ready
echo 'RADIO_READY: NetworkManager can autoconnect saved Wi-Fi profiles.'
