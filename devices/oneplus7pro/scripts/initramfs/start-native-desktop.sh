#!/bin/busybox sh
# Start the existing mobile session once native KMS and Adreno are available.
set -eu
ROOT=/newroot
attempt=0
card=
while [ "$attempt" -lt 180 ]; do
    for connector in /sys/class/drm/card*-DSI-*; do
        [ -d "$connector" ] || continue
        name=${connector##*/}
        card=/dev/dri/${name%%-DSI-*}
        break
    done
    if [ -n "$card" ] && [ -c "$card" ] && [ -c /dev/dri/renderD128 ]; then
        break
    fi
    busybox sleep 1
    attempt=$((attempt + 1))
done
[ -n "$card" ] && [ -c "$card" ] && [ -c /dev/dri/renderD128 ] || {
    echo 'Timed out waiting for native DSI and Adreno' >&2
    exit 1
}
export HOME=/root XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1
export AQ_DRM_DEVICES="$card"
busybox mkdir -p "$ROOT/usr/local/sbin"
busybox cp /hypr/run-hypr-native.sh "$ROOT/usr/local/sbin/guacamole-native-desktop"
busybox chmod 755 "$ROOT/usr/local/sbin/guacamole-native-desktop"
busybox chroot "$ROOT" /bin/bash /usr/local/sbin/guacamole-native-desktop \
    > "$ROOT/root/hypr-native.log" 2>&1 < /dev/null &
hypr_pid=$!
attempt=0
ready=false
while [ "$attempt" -lt 25 ]; do
    busybox kill -0 "$hypr_pid" 2>/dev/null || { echo 'Hyprland exited' >&2; exit 1; }
    if busybox chroot "$ROOT" /usr/bin/timeout -k 1 2 /usr/bin/hyprctl -i 0 monitors \
        > "$ROOT/root/native-monitors.log" 2>&1 &&
        busybox grep -q '^Monitor DSI-' "$ROOT/root/native-monitors.log"; then
        ready=true
        break
    fi
    busybox sleep 1
    attempt=$((attempt + 1))
done
"$ready" || { echo 'Hyprland did not expose native DSI' >&2; exit 1; }
busybox chroot "$ROOT" /usr/bin/hyprctl -i 0 reload > "$ROOT/root/native-reload.log" 2>&1
busybox chroot "$ROOT" /usr/bin/hyprctl -i 0 configerrors > "$ROOT/root/native-configerrors.log" 2>&1
if busybox grep -q '[^[:space:]]' "$ROOT/root/native-configerrors.log"; then
    echo 'Hyprland reports configuration errors' >&2
    exit 1
fi
if [ -x "$ROOT/usr/bin/swaybg" ] && [ -f "$ROOT/usr/share/hypr/wall0.png" ]; then
    busybox chroot "$ROOT" /usr/bin/swaybg -i /usr/share/hypr/wall0.png -m fill \
        > "$ROOT/root/swaybg-native.log" 2>&1 < /dev/null &
fi
busybox chroot "$ROOT" /usr/bin/env QT_QPA_PLATFORM=wayland QSG_RHI_BACKEND=opengl QSG_INFO=1 \
    /root/.local/bin/omarchy-mobile-session launch \
    > "$ROOT/root/quickshell-native.log" 2>&1 < /dev/null
busybox sh /hypr/start-touchscreen.sh > "$ROOT/root/native-touch-desktop.log" 2>&1
echo NATIVE_DESKTOP_STARTED
