#!/usr/bin/env bash
# Board startup adapter for the temporary root/chroot session.
# A standard-user system should use its normal PipeWire user services instead.
set -euo pipefail
BASE=/root/audio-bringup
[[ $(uname -r) == 6.17.0-sm8150-codex-native5-g379d8fe35c7c-dirty ]]
[[ -f "$BASE/autostart-enabled" ]] || exit 0
exec 8>/run/guacamole-audio-session.lock
flock -n 8 || exit 0
export XDG_RUNTIME_DIR=/run/user/0
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
ready() {
    [[ -d /sys/module/qcom_pd_mapper && -d /sys/module/power_support && -S "$XDG_RUNTIME_DIR/bus" ]] || return 1
    local remote
    for remote in /sys/class/remoteproc/*; do
        [[ -f "$remote/name" ]] || continue
        if [[ $(cat "$remote/name") == modem && $(cat "$remote/state") == running ]]; then return 0; fi
    done
    return 1
}
for attempt in $(seq 1 120); do
    if ready; then break; fi
    sleep 1
done
ready
cd "$BASE"
sha256sum -c AUDIO-SHA256SUMS >/dev/null
[[ -d /sys/module/guacamole_volume_keys ]] || insmod ./guacamole_volume_keys.ko
bash ./phone-audio-test.sh speakers
pcm=$(python3 - <<'PY'
from pathlib import Path
import re
matches=[]
for line in Path('/proc/asound/pcm').read_text().splitlines():
    match=re.match(r'(\d+)-(\d+): MultiMedia1 .*playback', line)
    if match and Path(f'/proc/asound/card{int(match[1])}/id').read_text().strip() == 'Pro':
        matches.append(str(int(match[2])))
assert len(matches)==1, 'Expected exactly one verified playback frontend'
print(matches[0])
PY
)
mkdir -p /etc/alsa/conf.d
sed "s/@PCM_DEVICE@/$pcm/g" "$BASE/config/alsa-quiet.conf" > /etc/alsa/conf.d/99-guacamole-quiet.conf.tmp
mv /etc/alsa/conf.d/99-guacamole-quiet.conf.tmp /etc/alsa/conf.d/99-guacamole-quiet.conf
# Never adopt or kill an unrelated existing audio server.
if pgrep -u 0 -x 'pipewire|pipewire-pulse|wireplumber' >/dev/null; then
    echo 'An audio server already exists; leaving it in place.'
    exit 0
fi
amixer -q -c Pro cset name='Earpiece Mode' Speaker
amixer -q -c Pro cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 1
children=()
cleanup() {
    trap - EXIT INT TERM
    for pid in "${children[@]}"; do kill "$pid" 2>/dev/null || true; done
    for pid in "${children[@]}"; do wait "$pid" 2>/dev/null || true; done
    amixer -q -c Pro cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 0 || true
}
trap cleanup EXIT
trap 'exit 0' INT TERM
pipewire >> "$BASE/pipewire.log" 2>&1 & children+=("$!")
sleep 1
kill -0 "${children[0]}"
wireplumber >> "$BASE/wireplumber.log" 2>&1 & children+=("$!")
pipewire-pulse >> "$BASE/pulse.log" 2>&1 & children+=("$!")
for attempt in $(seq 1 20); do
    if wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q '^Volume:'; then break; fi
    sleep 1
done
wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep '^Volume:'
for pid in "${children[@]}"; do kill -0 "$pid"; done
echo 'AUDIO_READY: internal speakers, fixed -36 dB hardware-path attenuation'
wait -n "${children[@]}"
echo 'An audio service exited; stopping its companion services.' >&2
exit 1
