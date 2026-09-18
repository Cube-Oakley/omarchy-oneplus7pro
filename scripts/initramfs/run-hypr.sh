#!/bin/bash
# Pin KMS to leftover simpledrm (card0). The delayed msm GPU DRM has no CRTC,
# so letting Aquamarine pick it freezes the last Hyprland frame on the panel.
set -e
export HOME=/root
export XDG_RUNTIME_DIR=/run/user/0
mkdir -p "$XDG_RUNTIME_DIR" /root/.config/hypr
chmod 700 "$XDG_RUNTIME_DIR"
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export HYPRLAND_STARTED_VIA_WRAPPER=1
export WLR_RENDERER_ALLOW_SOFTWARE=1
# DPU KMS (card2 / DSI-1) when present; leftover simpledrm otherwise.
if [ -e /dev/dri/card2 ]; then
	export AQ_DRM_DEVICES=/dev/dri/card2
else
	export AQ_DRM_DEVICES=/dev/dri/card0
fi
export WLR_DRM_DEVICES="${AQ_DRM_DEVICES}"
export GALLIUM_DRIVER=llvmpipe
export MESA_LOADER_DRIVER_OVERRIDE=kms_swrast
export LIBGL_ALWAYS_SOFTWARE=1

CFG=/etc/hypr/hyprland.lua
if [ ! -f "$CFG" ]; then
	CFG=/root/.config/hypr/hyprland.lua
fi

# start-hyprland is the 0.56 watchdog wrapper; it does not accept --i-am-really-stupid.
# We run as pid1/root, so invoke Hyprland directly and suppress the watchdog banner
# via HYPRLAND_STARTED_VIA_WRAPPER + misc.disable_watchdog_warning.
exec /usr/bin/Hyprland --i-am-really-stupid -c "$CFG"
