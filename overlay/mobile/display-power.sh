#!/usr/bin/env bash
# Display blanking. The CRT starts in the shell as soon as this asks; DPMS follows.
# System suspend and screen locking stay in the power-button adapter.
set -euo pipefail
action=${1:-toggle}
case $action in
    on|off|toggle|preview) ;;
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
shell=${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/omarchy-mobile/shell.qml
state=$XDG_RUNTIME_DIR/omarchy-mobile-crt.state

dpms() {
    hyprctl eval "hl.dispatch(hl.dsp.dpms({ action = \"$1\" }))"
}
dpms_on() {
    hyprctl -j monitors | python3 -c 'import json,sys; monitors=json.load(sys.stdin); raise SystemExit(0 if any(m.get("dpmsStatus") for m in monitors) else 1)'
}
wait_state() {
    local want=$1 i line
    for i in $(seq 1 60); do
        line=$(cat "$state" 2>/dev/null || true)
        [[ $line == "$want" ]] && return 0
        sleep 0.03
    done
    return 1
}
crt() {
    local mode=$1 token
    [[ -f $shell ]] || return 1
    token=$(date +%s%N)
    printf 'pending %s\n' "$token" > "$state"
    quickshell ipc -n -p "$shell" call mobile crt "$mode" "$token" >/dev/null || return 1
    wait_state "settled $token"
}

case $action in
    toggle) dpms_on && action=off || action=on ;;
esac
case $action in
    preview)
        crt off
        crt on
        ;;
    off)
        crt off || true
        dpms disable
        ;;
    on)
        # The shell turns the panel on at the start of the open animation.
        crt on || dpms enable
        ;;
esac
