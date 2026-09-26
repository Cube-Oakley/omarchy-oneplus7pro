#!/usr/bin/env bash
# Chroot adapter for the distribution's time-sync service (no systemd PID 1).
set -euo pipefail
if [[ ${1:-} != --locked ]]; then
    exec flock --nonblock --close /run/guacamole-timesync.lock "$0" --locked
fi
pgrep -f '^/usr/lib/systemd/systemd-timesyncd$' >/dev/null && exit 0
install -d -o systemd-timesync -g systemd-timesync -m755 \
    /run/systemd/timesync /var/lib/systemd/timesync
mkdir -p /root/radio-bringup/logs
# Match the packaged unit's service user and clock-only capability. The daemon
# uses the distribution NTP defaults and persists its last known clock on disk.
nohup env SYSTEMD_LOG_TARGET=console SYSTEMD_NSS_RESOLVE_VALIDATE=0 \
    setpriv --reuid=systemd-timesync --regid=systemd-timesync --init-groups \
    --bounding-set=-all,+sys_time --inh-caps=-all,+sys_time \
    --ambient-caps=-all,+sys_time --no-new-privs \
    /usr/lib/systemd/systemd-timesyncd \
    >> /root/radio-bringup/logs/timesync.log 2>&1 < /dev/null &
sleep 1
pgrep -f '^/usr/lib/systemd/systemd-timesyncd$' >/dev/null
