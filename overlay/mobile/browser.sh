#!/usr/bin/env bash
set -euo pipefail
# Normal desktop users run Chromium directly. The root bring-up session needs
# an explicitly installed adapter that drops privileges before opening websites.
if (( EUID == 0 )); then
    adapter=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-mobile/browser-launch
    if [[ ! -x $adapter ]]; then
        echo 'The unprivileged browser display adapter has not been enabled.' >&2
        exit 1
    fi
    exec "$adapter" "$@"
fi
exec /usr/bin/chromium --ozone-platform=wayland "$@"
