#!/usr/bin/env bash
# Run inside the target user's Wayland system. Optional argument: device adapter.
set -euo pipefail
source_dir=$(cd "$(dirname "$0")" && pwd)
config=${XDG_CONFIG_HOME:-$HOME/.config}
data=${XDG_DATA_HOME:-$HOME/.local/share}
state=${XDG_STATE_HOME:-$HOME/.local/state}
device=${1:-}
backup="$state/omarchy-mobile/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup" "$config/quickshell/omarchy-mobile" "$config/omarchy-mobile" \
    "$config/kitty" "$config/hypr" "$config/fastfetch" "$HOME/.local/bin" "$data/omarchy-mobile"
for name in quickshell kitty hypr fastfetch omarchy-mobile; do
    [[ -d "$config/$name" ]] && cp -a "$config/$name" "$backup/$name"
done
install -m644 "$source_dir"/*.qml "$source_dir/qmldir" "$config/quickshell/omarchy-mobile/"
install -m755 "$source_dir/start-mobile.sh" "$HOME/.local/bin/omarchy-mobile-session"
install -m755 "$source_dir/keyboard.sh" "$HOME/.local/bin/omarchy-mobile-keyboard"
install -m755 "$source_dir/display-power.sh" "$HOME/.local/bin/omarchy-mobile-display"
install -m755 "$source_dir/power-button.py" "$HOME/.local/bin/omarchy-mobile-power"
install -m755 "$source_dir/battery.py" "$HOME/.local/bin/omarchy-mobile-battery"
install -m755 "$source_dir/weather.py" "$HOME/.local/bin/omarchy-mobile-weather"
install -m755 "$source_dir/wifi.py" "$HOME/.local/bin/omarchy-mobile-wifi"
install -m755 "$source_dir/volume.py" "$HOME/.local/bin/omarchy-mobile-volume"
install -m755 "$source_dir/theme.py" "$HOME/.local/bin/omarchy-mobile-theme"
install -m644 "$source_dir/hypr-mobile.lua" "$data/omarchy-mobile/hypr-mobile.lua"
cp -a "$source_dir/themes" "$data/omarchy-mobile/"
install -m644 "$source_dir/fastfetch/omarchy.png" "$source_dir/fastfetch/omarchy.txt" \
    "$source_dir/fastfetch/omarchy-wordmark.txt" "$data/omarchy-mobile/"
install -m644 "$source_dir/fastfetch/config.jsonc" "$config/fastfetch/config.jsonc"
mkdir -p "$data/applications"
install -m644 "$source_dir/fastfetch/omarchy-mobile-fastfetch.desktop" "$data/applications/"
if [[ ! -f "$config/kitty/kitty.conf" ]]; then
    install -m644 "$source_dir/kitty.conf" "$config/kitty/kitty.conf"
elif ! grep -qxF 'include mobile-theme.conf' "$config/kitty/kitty.conf"; then
    printf '\ninclude mobile-theme.conf\n' >> "$config/kitty/kitty.conf"
fi
install -m644 "$source_dir/kitty-font.conf" "$config/kitty/mobile-font.conf"
if ! grep -qxF "include mobile-font.conf" "$config/kitty/kitty.conf" 2>/dev/null; then
    printf "\ninclude mobile-font.conf\n" >> "$config/kitty/kitty.conf"
fi
if [[ -n $device ]]; then
    install -m644 "$device/mobile.json" "$config/omarchy-mobile/device.json"
    install -m755 "$device/desktop-prepare.sh" "$config/omarchy-mobile/session-prepare"
    if [[ -f "$device/power-suspend.sh" ]]; then
        install -m755 "$device/power-suspend.sh" "$config/omarchy-mobile/suspend"
    fi
    if [[ -f "$device/wallpaper-apply.sh" ]]; then
        install -m755 "$device/wallpaper-apply.sh" "$config/omarchy-mobile/wallpaper-apply"
    fi
else
    # Standard Hyprland integration; append one user override without resetting it.
    line=$(python3 - "$config/hypr/mobile.lua" <<'PYLUA'
import json,sys
print('dofile(' + json.dumps(sys.argv[1], ensure_ascii=False) + ')')
PYLUA
    )
    grep -qxF "$line" "$config/hypr/hyprland.lua" || printf '\n%s\n' "$line" >> "$config/hypr/hyprland.lua"
fi
"$HOME/.local/bin/omarchy-mobile-theme" sync >/dev/null
if [[ -n $device ]]; then
    # touch1 starts the default config. It delegates to the portable named shell.
    install -m644 "$device/quickshell-bootstrap.qml" "$config/quickshell/shell.qml"
else
    "$HOME/.local/bin/omarchy-mobile-session" launch
fi
printf 'Mobile configuration backup: %s\n' "$backup"
