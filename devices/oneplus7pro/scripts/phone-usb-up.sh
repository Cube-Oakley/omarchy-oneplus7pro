#!/usr/bin/env bash
# touch1 keeps the original raw USB shell; use it to start persistent services.
# Run on the host after the Arch desktop has appeared (~110 seconds from boot).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -s "$ROOT/out/network-test/known_hosts" ]] || {
    echo 'SSH must be provisioned and its host key pinned first.' >&2; exit 1;
}
# Require the directly connected phone subnet; never send the bootstrap via LAN.
ip -4 route get 172.16.42.1 | grep -q 'src 172.16.42.2' || {
    echo 'The host USB interface must have 172.16.42.2/24.' >&2; exit 1;
}
if ! nc -z -w 2 172.16.42.1 22; then
    result=$(printf '\nexec 2>&1\nbusybox sh /newroot/usr/local/sbin/guacamole-usb-services\nexit\n' |
        timeout 15 nc -N 172.16.42.1 23)
    printf '%s\n' "$result"
    [[ $result == *USB_SSH_READY* || $result == *USB_SSH_ALREADY_RUNNING* ]] || exit 1
fi
# Sync only after authenticating the phone; no functioning RTC/NTP service yet.
bash "$ROOT/scripts/phone-ssh.sh" "date -u -s @$(date +%s); ip route; getent ahostsv4 mirror.archlinuxarm.org"
echo 'USB ready. Connect with: bash scripts/phone-ssh.sh'
