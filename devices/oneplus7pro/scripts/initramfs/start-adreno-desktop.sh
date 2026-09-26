#!/bin/busybox sh
# Called after the Arch mounts and seatd are ready; USB is already available.
set -eu
ROOT=/newroot
attempt=0
while [ ! -c /dev/dri/renderD128 ] || [ -L /dev/dri/renderD128 ]; do
    [ "$attempt" -lt 120 ] || { echo 'Timed out waiting for Adreno' >&2; exit 1; }
    busybox sleep 1
    attempt=$((attempt + 1))
done
export HOME=/root XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1
unset GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE LIBGL_ALWAYS_SOFTWARE
busybox chroot "$ROOT" /bin/bash /root/run-hypr.sh > "$ROOT/root/hypr.log" 2>&1 &
hypr_pid=$!
attempt=0
ready=false
while [ "$attempt" -lt 20 ]; do
    busybox kill -0 "$hypr_pid" 2>/dev/null || { echo 'Hyprland exited at startup' >&2; exit 1; }
    if busybox chroot "$ROOT" /usr/bin/timeout -k 1 2 /usr/bin/hyprctl -i 0 monitors \
        > "$ROOT/root/desktop-monitors.log" 2>&1 &&
        busybox grep -q '^Monitor ' "$ROOT/root/desktop-monitors.log"; then
        ready=true
        break
    fi
    busybox sleep 1
    attempt=$((attempt + 1))
done
"$ready" || { echo 'Hyprland did not expose an active monitor' >&2; exit 1; }
busybox chroot "$ROOT" /usr/bin/timeout -k 1 3 /usr/bin/hyprctl -i 0 reload \
    > "$ROOT/root/desktop-reload.log" 2>&1
busybox chroot "$ROOT" /usr/bin/timeout -k 1 3 /usr/bin/hyprctl -i 0 configerrors \
    > "$ROOT/root/desktop-configerrors.log" 2>&1
if busybox grep -q '[^[:space:]]' "$ROOT/root/desktop-configerrors.log"; then
    echo 'Hyprland reports configuration errors; see desktop-configerrors.log' >&2
    exit 1
fi
if [ -x "$ROOT/usr/bin/swaybg" ] && [ -f "$ROOT/usr/share/hypr/wall0.png" ]; then
    busybox chroot "$ROOT" /usr/bin/swaybg -i /usr/share/hypr/wall0.png -m fill \
        > "$ROOT/root/swaybg.log" 2>&1 &
fi
if [ -x "$ROOT/usr/bin/quickshell" ] && [ -f "$ROOT/root/.config/quickshell/shell.qml" ]; then
    busybox chroot "$ROOT" /usr/bin/env QT_QPA_PLATFORM=wayland QSG_RHI_BACKEND=opengl QSG_INFO=1 \
        /usr/bin/quickshell -p /root/.config/quickshell/shell.qml > "$ROOT/root/quickshell.log" 2>&1 &
fi
echo 'Adreno desktop started' > /dev/kmsg
echo 'ADRENO_DESKTOP_STARTED'
