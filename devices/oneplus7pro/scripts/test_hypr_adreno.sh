#!/bin/busybox sh
# Run on the phone's initramfs shell, after Adreno has appeared.
# Keep the boot launcher unchanged and automatically restore its session.
set -eu
ROOT=/newroot
STAMP=$(busybox cut -d. -f1 /proc/uptime)
LOG="$ROOT/root/hypr-adreno-test-$STAMP"
# Older test kernels corrupt imported GEM buffer references on release.
case "$(busybox uname -r)" in
    *-codex-gpu1-*|*-codex-gpu2-*) ;;
    *) echo 'Requires gpu1 or gpu2 with the imported dma-buf fix.' >&2; exit 1 ;;
esac
[ -c /dev/dri/renderD128 ] && [ ! -L /dev/dri/renderD128 ]
[ -x "$ROOT/usr/bin/Hyprland" ]
busybox mkdir -p "$LOG"
had_quickshell=false
if busybox pidof quickshell >/dev/null; then had_quickshell=true; fi
echo "TEST_LOG=$LOG"
busybox cp "$ROOT/etc/hypr/hyprland.lua" "$LOG/original.lua"
busybox cp "$LOG/original.lua" "$LOG/test.lua"
cat >> "$LOG/test.lua" <<'LUA'
hl.config({ debug = { disable_logs = false, enable_stdout_logs = true } })
LUA

control() {
    busybox chroot "$ROOT" /usr/bin/env XDG_RUNTIME_DIR=/run/user/0 \
        /usr/bin/timeout -k 1 5 /usr/bin/hyprctl -i 0 "$@"
}

restore_desktop() {
    busybox killall Hyprland swaybg 2>/dev/null || true
    busybox sleep 2
    busybox killall -9 Hyprland swaybg 2>/dev/null || true
    busybox sleep 1
    if busybox pidof Hyprland >/dev/null; then
        echo RESTORE_FAILED_HYPRLAND_STUCK_REBOOT_REQUIRED >&2
        return 1
    fi
    # Recreate the startup alias briefly so the known software launcher
    # creates its context before the real render node returns.
    if busybox grep -q 'GALLIUM_DRIVER=llvmpipe' "$ROOT/root/run-hypr.sh" &&
       [ -c /dev/dri/renderD128 ] && [ ! -L /dev/dri/renderD128 ]; then
        busybox mv /dev/dri/renderD128 /dev/dri/renderD128.adreno-save
        busybox ln -s card0 /dev/dri/renderD128
    fi
    busybox chroot "$ROOT" /bin/bash /root/run-hypr.sh > "$LOG/restored.log" 2>&1 &
    busybox sleep 5
    if [ -c /dev/dri/renderD128.adreno-save ]; then
        busybox mv /dev/dri/renderD128.adreno-save /dev/dri/renderD128
    fi
    busybox chroot "$ROOT" /usr/bin/env HOME=/root XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1 \
        /usr/bin/swaybg -i /usr/share/hypr/wall0.png -m fill > "$LOG/restored-swaybg.log" 2>&1 &
    if "$had_quickshell"; then
        busybox chroot "$ROOT" /usr/bin/env \
            -u GALLIUM_DRIVER -u MESA_LOADER_DRIVER_OVERRIDE -u LIBGL_ALWAYS_SOFTWARE \
            HOME=/root XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1 \
            QT_QPA_PLATFORM=wayland QSG_RHI_BACKEND=opengl \
            /usr/bin/quickshell -p /root/.config/quickshell/shell.qml > "$LOG/restored-quickshell.log" 2>&1 &
    fi
    if busybox chroot "$ROOT" /usr/bin/env XDG_RUNTIME_DIR=/run/user/0 \
        /usr/bin/timeout -k 1 5 /usr/bin/hyprctl -i 0 monitors > "$LOG/restored-monitors.log" 2>&1; then
        echo RESTORED_SESSION_CONTROL_RESPONDS
    else
        echo RESTORE_FAILED_CONTROL_UNRESPONSIVE >&2
        return 1
    fi
}
trap restore_desktop EXIT

busybox killall Hyprland swaybg 2>/dev/null || true
busybox sleep 3
busybox chroot "$ROOT" /usr/bin/env \
    -u GALLIUM_DRIVER -u MESA_LOADER_DRIVER_OVERRIDE -u LIBGL_ALWAYS_SOFTWARE \
    HOME=/root XDG_RUNTIME_DIR=/run/user/0 XDG_SESSION_TYPE=wayland \
    XDG_CURRENT_DESKTOP=Hyprland HYPRLAND_STARTED_VIA_WRAPPER=1 \
    AQ_DRM_DEVICES=/dev/dri/card0 AQ_NO_MODIFIERS=1 \
    /usr/bin/timeout -k 3 45 /usr/bin/Hyprland --i-am-really-stupid -c "${LOG#$ROOT}/test.lua" \
    > "$LOG/launch.log" 2>&1 &
test_pid=$!
busybox sleep 10
control reload > "$LOG/reload.log" 2>&1
control configerrors > "$LOG/configerrors.log" 2>&1
busybox chroot "$ROOT" /usr/bin/env XDG_RUNTIME_DIR=/run/user/0 \
    /usr/bin/timeout -k 1 5 /usr/bin/hyprctl -i 0 systeminfo > "$LOG/systeminfo.log" 2>&1 || true
busybox chroot "$ROOT" /usr/bin/env XDG_RUNTIME_DIR=/run/user/0 \
    /usr/bin/timeout -k 1 5 /usr/bin/hyprctl -i 0 monitors all > "$LOG/monitors.log" 2>&1 || true
for color in 2468ac ac6824; do
    busybox killall swaybg 2>/dev/null || true
    busybox chroot "$ROOT" /usr/bin/env HOME=/root XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1 \
        /usr/bin/swaybg -c "#$color" > "$LOG/color-$color.log" 2>&1 &
    busybox sleep 4
    control layers > "$LOG/layers-$color.log" 2>&1 || true
    if [ -x "$ROOT/tmp/read-scanout" ]; then
        busybox chroot "$ROOT" /tmp/read-scanout "${LOG#$ROOT}/color-$color.ppm" \
            > "$LOG/pixels-$color.log" 2>&1
    fi
done
for f in "$ROOT"/run/user/0/hypr/*/hyprland.log; do
    [ -f "$f" ] || continue
    busybox cp "$f" "$LOG/runtime-$(busybox basename "$(busybox dirname "$f")").log"
done
wait "$test_pid" || true
# Copy again after exit so buffered startup and shutdown output is retained.
for f in "$ROOT"/run/user/0/hypr/*/hyprland.log; do
    [ -f "$f" ] || continue
    busybox cp "$f" "$LOG/runtime-$(busybox basename "$(busybox dirname "$f")").log"
done
busybox dmesg > "$LOG/dmesg.log"
busybox sync
echo ADRENO_SESSION_TEST_FINISHED
