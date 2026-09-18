#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
: "${WAYLAND_DISPLAY:?Launch from a Wayland session}"
state=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-mobile
mkdir -p "$state"
pidfile="$XDG_RUNTIME_DIR/omarchy-mobile-keyboard.pid"
exec 9>"$XDG_RUNTIME_DIR/omarchy-mobile-keyboard.lock"
flock 9
pid=$(cat "$pidfile" 2>/dev/null || true)
if [[ ! $pid =~ ^[0-9]+$ ]] || [[ $(cat "/proc/$pid/comm" 2>/dev/null || true) != wvkbd-mobintl ]]; then
    # Process substitution needs /dev/fd, which minimal boot environments may
    # not provide. Capture first so Python failures also propagate through -e.
    settings_text=$(python3 - "$state/palette.json" <<'PY'
import json,sys
try:
    p=json.load(open(sys.argv[1])); c=p['colors']; d=p.get('device',{})
except (OSError,ValueError,KeyError):
    c={}; d={}
for key,default in [('keyboardHeight',280),('keyboardLandscapeHeight',200)]:
    value=d.get(key,default)
    print(value if isinstance(value,int) and 100 <= value <= 500 else default)
for key,default in [('background','#1a1b26'),('lighter_background','#24283b'),('muted','#414868'),('foreground','#c0caf5'),('accent','#7aa2f7')]:
    print(c.get(key,default).lstrip('#'))
PY
    )
    mapfile -t settings <<< "$settings_text"
    nohup wvkbd-mobintl --auto --hidden -H "${settings[0]}" -L "${settings[1]}" \
        -l simple,special,nav --fn 'JetBrainsMono Nerd Font 16' \
        --bg "${settings[2]}" --fg "${settings[3]}" --fg-sp "${settings[4]}" \
        --text "${settings[5]}" --text-sp "${settings[5]}" \
        --press "${settings[6]}" --press-sp "${settings[6]}" \
        > "$state/keyboard.log" 2>&1 9>&- < /dev/null &
    pid=$!
    printf '%s\n' "$pid" > "$pidfile"
    sleep 0.3
    kill -0 "$pid"
fi
case ${1:-toggle} in
    start) ;;
    show) kill -USR2 "$pid" ;;
    hide) kill -USR1 "$pid" ;;
    toggle) kill -RTMIN "$pid" ;;
    *) echo 'Usage: keyboard.sh start|show|hide|toggle' >&2; exit 2 ;;
esac
