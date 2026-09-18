#!/usr/bin/env bash
# Keep native2's early boot wallpaper aligned with the persistent theme.
set -euo pipefail
image=${1:-}
[[ -n $image && -f $image ]] || exit 0
image=$(realpath -- "$image")
fallback=/usr/share/hypr/wall0.png
[[ $(readlink "$fallback" 2>/dev/null || true) == "$image" ]] && exit 0
backup=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-mobile/backups/boot-wallpaper
mkdir -p "$backup"
if [[ ! -e "$backup/wall0.png" && ! -L "$backup/wall0.png" && -e $fallback ]]; then
    cp -a "$fallback" "$backup/wall0.png"
fi
temporary=$(mktemp -d /usr/share/hypr/.wallpaper.XXXXXXXX)
link=$temporary/wall0.png
trap 'rm -f -- "$link"; rmdir -- "$temporary"' EXIT
ln -s -- "$image" "$link"
mv -Tf -- "$link" "$fallback"
