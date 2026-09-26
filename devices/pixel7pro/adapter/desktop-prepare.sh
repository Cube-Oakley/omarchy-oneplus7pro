#!/bin/bash
# Development adapter for the verified Pixel RAM session. No hardware writes.
set -euo pipefail
[[ $(stat -f -c %T /) == tmpfs ]]
case $(uname -r) in
    *-pixel-drm11-*|*-pixel-gpu15-*|*-pixel-display16-*|*-pixel-scanout17-*|*-pixel-panel18-*) ;;
    *) echo 'Expected a validated Pixel desktop kernel.' >&2; exit 1 ;;
esac
config=/root/pixel-hyprland.lua
[[ -f $config ]]
line='dofile("/root/.config/hypr/mobile.lua")'
if ! grep -qxF "$line" "$config"; then
    cp -a "$config" "$config.before-mobile"
    printf '\n%s\n' "$line" >> "$config"
fi
hyprctl reload
errors=$(hyprctl configerrors)
[[ -z ${errors//[[:space:]]/} ]] || { printf '%s\n' "$errors" >&2; exit 1; }
