#!/usr/bin/env bash
# Read-only native display baseline through the pinned USB SSH connection.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/out/native-display-test/runtime}"
mkdir -p "$DEST"
bash "$ROOT/scripts/phone-ssh.sh" '
    uname -a
    cat /proc/sys/kernel/random/boot_id /proc/uptime /proc/cmdline
    cat /sys/devices/system/cpu/online
    cat /sys/kernel/security/lsm 2>/dev/null || true
    ls -l /dev/dri
    cat /proc/bus/input/devices
    for conn in /sys/class/drm/card*-DSI-*; do
        [ -d "$conn" ] || continue
        echo "$conn"
        cat "$conn/status" "$conn/enabled" "$conn/modes"
        card=${conn##*/}
        card=${card%%-DSI-*}
        timeout -k 1 10 modetest -M msm-kms -c -p
    done
    for node in /sys/kernel/debug/dri/*/state; do
        [ -f "$node" ] || continue
        echo "$node"
        cat "$node"
    done
' > "$DEST/state.log" 2>&1
bash "$ROOT/scripts/phone-ssh.sh" 'dmesg' > "$DEST/dmesg.log"
echo "Saved $DEST/state.log and $DEST/dmesg.log"
