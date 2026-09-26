#!/usr/bin/env bash
# OnePlus native KMS launcher; scanout node is selected by the outer init.
set -eu
export HOME=/root XDG_RUNTIME_DIR=/run/user/0
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
: "${AQ_DRM_DEVICES:?Native display device must be selected first}"
test -c "$AQ_DRM_DEVICES"
test -c /dev/dri/renderD128
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=Hyprland
export HYPRLAND_STARTED_VIA_WRAPPER=1 AQ_NO_MODIFIERS=1
unset GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE LIBGL_ALWAYS_SOFTWARE
unset WLR_DRM_DEVICES WLR_RENDERER_ALLOW_SOFTWARE
exec /usr/bin/Hyprland --i-am-really-stupid -c /etc/hypr/hyprland.lua
