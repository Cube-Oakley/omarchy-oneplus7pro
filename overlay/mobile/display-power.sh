#!/usr/bin/env bash
# Display blanking only. System suspend and screen locking are separate.
set -euo pipefail
case ${1:-toggle} in
    on) action=enable ;;
    off) action=disable ;;
    toggle) action=toggle ;;
    *) echo 'Usage: omarchy-mobile-display on|off|toggle' >&2; exit 2 ;;
esac
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    for socket in "$XDG_RUNTIME_DIR"/hypr/*/.socket.sock; do
        [[ -S $socket ]] || continue
        instance=${socket%/.socket.sock}
        export HYPRLAND_INSTANCE_SIGNATURE=${instance##*/}
        break
    done
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || exit 1
fi
# Leave the release event before changing DPMS; never sleep in a Lua callback.
sleep 0.15
exec hyprctl eval "hl.dispatch(hl.dsp.dpms({ action = \"$action\" }))"
