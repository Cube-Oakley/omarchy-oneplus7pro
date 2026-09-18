#!/usr/bin/env bash
# Run in a terminal, with an existing NetworkManager Wi-Fi profile.
set -u
if [[ $# -eq 0 ]]; then
    nmcli -f SSID,SIGNAL,SECURITY device wifi list
    printf '\nWi-Fi network name: '
    IFS= read -r network
else
    network=$1
fi
[[ -n "$network" ]] || exit 1
exec python3 "$(dirname -- "$0")/wifi-connect.py" "$network"
