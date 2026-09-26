#!/bin/bash
# Run inside the Pixel Arch RAM root after the hardware mobile session settles.
# Verify the client is actually fullscreen; do not mislabel a tiled sample.
set -euo pipefail
[[ $(stat -f -c %T /) == tmpfs ]]
[[ $(uname -r) == *-pixel-scanout17-* || $(uname -r) == *-pixel-panel18-* ]]
! pgrep -x weston-simple-e >/dev/null
export XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1
export LD_LIBRARY_PATH=/opt/pixel-mesa/lib GBM_BACKENDS_PATH=/opt/pixel-mesa/lib/gbm
export __EGL_VENDOR_LIBRARY_FILENAMES=/opt/pixel-mesa/share/glvnd/egl_vendor.d/50_mesa.json
export HYPRLAND_INSTANCE_SIGNATURE=$(hyprctl instances -j | python -c 'import sys,json; print(json.load(sys.stdin)[0]["instance"])')
unset GBM_ALWAYS_SOFTWARE LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE
check_temps() {
    local t
    local zones=(/sys/class/thermal/thermal_zone*/temp)
    [[ ${#zones[@]} == 7 ]]
    for zone in "${zones[@]}"; do
        t=$(cat "$zone"); (( t >= 5000 && t < 55000 )) || return 1
    done
}
check_temps
cat /sys/kernel/debug/dri/0/pixel_scanout
timeout -k 2 180 stdbuf -oL -eL weston-simple-egl -f -o &
pid=$!
cleanup() {
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    cat /sys/kernel/debug/dri/0/pixel_scanout
}
trap cleanup EXIT
fullscreen_ready() {
    hyprctl clients -j | python -c 'import json,sys; clients=json.load(sys.stdin); sys.exit(not any(c["class"] == "org.freedesktop.weston.simple-egl" and c["fullscreen"] == 2 for c in clients))'
}
for n in {1..30}; do fullscreen_ready && break; sleep 0.1; done
if ! fullscreen_ready; then
    echo 'Demo did not become fullscreen; stop and let desktop startup finish before retrying.' >&2
    exit 1
fi
hyprctl clients -j
for ((n=0; n<90; n++)); do
    kill -0 "$pid" 2>/dev/null || break
    check_temps
    sleep 2
done
