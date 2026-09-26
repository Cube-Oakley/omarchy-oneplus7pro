#!/usr/bin/env bash
# Chroot service lifecycle for the native4 Wi-Fi adapter.
set -euo pipefail
BASE=/root/radio-bringup
mkdir -p "$BASE/logs" /run/dbus
if [[ ! -s /etc/machine-id ]]; then
    dbus-uuidgen > /etc/machine-id
    chmod 444 /etc/machine-id
fi
if ! dbus-send --system --dest=org.freedesktop.DBus --type=method_call \
    --print-reply / org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
    dbus-daemon --system --fork --nopidfile
fi
if ! pgrep -x NetworkManager >/dev/null; then
    nohup NetworkManager --no-daemon --config "$BASE/NetworkManager-test.conf" \
        > "$BASE/logs/NetworkManager.log" 2>&1 < /dev/null &
fi
for attempt in $(seq 1 20); do
    if nmcli -t -f DEVICE,STATE device status 2>/dev/null; then
        if [[ -x /usr/local/sbin/guacamole-time-sync ]]; then
            /usr/local/sbin/guacamole-time-sync || echo 'Time-sync service failed; see timesync.log' >&2
        fi
        exit 0
    fi
    sleep 1
done
echo 'NetworkManager did not become ready' >&2
exit 1
