#!/bin/bash
# GPU composition on Adreno; simpledrm retains the bootloader panel scanout.
# Requires the msm imported dma-buf fix (gpu1 and later bring-up kernels).
set -eu
export HOME=/root
export XDG_RUNTIME_DIR=/run/user/0
mkdir -p "$XDG_RUNTIME_DIR" /root/.config/hypr
chmod 700 "$XDG_RUNTIME_DIR"
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export HYPRLAND_STARTED_VIA_WRAPPER=1
export AQ_DRM_DEVICES=/dev/dri/card0
export AQ_NO_MODIFIERS=1
unset GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE LIBGL_ALWAYS_SOFTWARE
unset WLR_DRM_DEVICES WLR_RENDERER_ALLOW_SOFTWARE
[ -c /dev/dri/renderD128 ] && [ ! -L /dev/dri/renderD128 ] || {
    echo 'Real Adreno render node is not ready' >&2
    exit 1
}
exec /usr/bin/Hyprland --i-am-really-stupid -c /etc/hypr/hyprland.lua
