#!/bin/bash
# Start the shared mobile overlay already installed in the Pixel RAM root.
set -euo pipefail
[[ $(stat -f -c %T /) == tmpfs ]]
[[ $(uname -r) == *-pixel-drm11-* ]]
export XDG_RUNTIME_DIR=/run/user/0
instances=$(hyprctl instances -j)
read -r HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY < <(
    printf '%s' "$instances" | python3 -c '
import json,sys
items=json.load(sys.stdin)
if len(items) != 1:
    raise SystemExit("Expected exactly one Pixel Hyprland instance")
print(items[0]["instance"], items[0]["wl_socket"])
')
export HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
[[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]]
export QT_QPA_PLATFORM=wayland QSG_RHI_BACKEND=opengl
export GBM_ALWAYS_SOFTWARE=1 LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
unset MESA_LOADER_DRIVER_OVERRIDE
/root/.local/bin/omarchy-mobile-session launch
# Start the hidden keyboard explicitly as well: the shell's asynchronous setup
# can finish after its first frame, and replay must not depend on that timing.
/root/.local/bin/omarchy-mobile-keyboard start
