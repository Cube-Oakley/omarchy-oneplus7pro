#!/bin/bash
# Native Pixel RAM-session launcher; run after the Weston/input setup helpers.
set -euo pipefail
[[ $(stat -f -c %T /) == tmpfs ]]
[[ $(uname -r) == *-pixel-drm11-* ]]
[[ -c /dev/dri/card0 && -S /run/seatd.sock ]]
[[ -f /root/pixel-hyprland.lua ]]
[[ -x /root/pixel-terminal.sh ]]
if pgrep -x Hyprland >/dev/null; then
    echo 'Hyprland already running; refusing a second instance.' >&2
    exit 1
fi
pkill -x weston || true
for n in {1..30}; do pgrep -x weston >/dev/null || break; sleep 0.1; done
! pgrep -x weston >/dev/null
export XDG_RUNTIME_DIR=/run/user/0 XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland LIBSEAT_BACKEND=seatd
export SEATD_SOCK=/run/seatd.sock AQ_DRM_DEVICES=/dev/dri/card0 AQ_NO_MODIFIERS=1
# GBM has a separate software flag; forcing kms_swrast via the loader alone
# leaves Mesa's GBM software flag false and breaks EGL on this display-only DRM.
export GBM_ALWAYS_SOFTWARE=1 LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
unset MESA_LOADER_DRIVER_OVERRIDE WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE
export HYPRLAND_STARTED_VIA_WRAPPER=1
ulimit -c 0
nohup Hyprland --i-am-really-stupid \
    -c /root/pixel-hyprland.lua >/run/hyprland-pixel.log 2>&1 </dev/null &
hypr_pid=$!
for n in {1..100}; do
    kill -0 "$hypr_pid" || { cat /run/hyprland-pixel.log >&2; exit 1; }
    hypr_socket=$(hyprctl instances 2>/dev/null | awk -v wanted="$hypr_pid" \
        '$1 == "pid:" { pid=$2 } $1 == "wl" && pid == wanted { print $3 }')
    [[ -n "$hypr_socket" && -S "$XDG_RUNTIME_DIR/$hypr_socket" ]] && break
    sleep 0.1
done
[[ -n "$hypr_socket" && -S "$XDG_RUNTIME_DIR/$hypr_socket" ]]
nohup env WAYLAND_DISPLAY="$hypr_socket" \
    weston-terminal --font='DejaVu Sans Mono' --font-size=12 \
    --shell=/root/pixel-terminal.sh >/run/hypr-terminal.log 2>&1 </dev/null &
echo "HYPRLAND_PID=$hypr_pid"
