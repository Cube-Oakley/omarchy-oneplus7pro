#!/bin/bash
# Bounded, RAM-only A/B/A diagnostic for the v16 retained-buffer bridge.
set -euo pipefail
[[ $(stat -f -c %T /) == tmpfs ]]
[[ $(uname -r) == *-pixel-display16-* ]]
[[ -r /sys/kernel/debug/dri/0/pixel_timing ]]
control=/sys/module/pixel_handoff/parameters/wait_idle
[[ -w $control ]]
# Linux task comm truncates this executable name to 15 characters.
! pgrep -x weston-simple-e >/dev/null
export XDG_RUNTIME_DIR=/run/user/0
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
[[ -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]]
export LD_LIBRARY_PATH=/opt/pixel-mesa/lib
export GBM_BACKENDS_PATH=/opt/pixel-mesa/lib/gbm
export __EGL_VENDOR_LIBRARY_FILENAMES=/opt/pixel-mesa/share/glvnd/egl_vendor.d/50_mesa.json
unset GBM_ALWAYS_SOFTWARE LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE
original=$(cat "$control")
animator=
cleanup() {
    if [[ -n $animator ]]; then
        kill -TERM "$animator" 2>/dev/null || true
        wait "$animator" 2>/dev/null || true
    fi
    echo "$original" >"$control"
}
trap cleanup EXIT
# Keep one renderer alive across all three phases to avoid launch-time effects.
timeout -k 2 40 stdbuf -oL -eL weston-simple-egl -f >/run/pixel-sync-animation.log 2>&1 &
animator=$!
for mode in N Y N; do
    # Refuse sustained rendering if the already-enabled thermal path is absent/hot.
    temp=$(cat /sys/class/thermal/thermal_zone3/temp)
    (( temp >= 5000 && temp < 55000 ))
    echo "$mode" >"$control"
    echo "BEGIN wait_idle=$mode"
    cat /proc/uptime
    cat /sys/kernel/debug/dri/0/pixel_timing
    sleep 12
    kill -0 "$animator"
    cat /sys/kernel/debug/dri/0/pixel_timing
    cat /sys/class/thermal/thermal_zone3/temp
    echo "END wait_idle=$mode"
done
cat /run/pixel-sync-animation.log
