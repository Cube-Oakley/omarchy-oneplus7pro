#!/usr/bin/env bash
# Fresh-boot microphone trial; plays and records nothing. Run on a boot where
# audio autostart was paused, before any sound card exists. Loads the normal
# stack from phone-audio-test.sh, but applies the microphone overlay before
# q6asm-dai probes and uses the id-matching q6asm-dai and per-link SLIMbus
# machine driver staged in mic-trial/. Reboot returns to the installed stack.
set -euo pipefail
BASE=/root/audio-bringup
TRIAL=$BASE/mic-trial
[[ $(uname -r) == 6.17.0-sm8150-codex-native5-g379d8fe35c7c-dirty ]]
exec 9>/run/guacamole-audio-test.lock
flock -n 9
[[ ! -f $BASE/autostart-enabled ]]
[[ ! -d /sys/module/guacamole_audio_card && ! -d /sys/module/snd_soc_sm8150 ]]
cd "$BASE"
sha256sum -c AUDIO-SHA256SUMS >/dev/null
(cd "$TRIAL" && sha256sum -c SHA256SUMS >/dev/null)
modem_running=0
for r in /sys/class/remoteproc/*; do
    if [[ $(cat "$r/name") == modem && $(cat "$r/state") == running ]]; then modem_running=1; fi
done
[[ $modem_running == 1 ]]
cp -an firmware/. /lib/firmware/qcom/sm8150/oneplus/guacamole/
for file in firmware/*; do cmp "$file" "/lib/firmware/qcom/sm8150/oneplus/guacamole/${file##*/}"; done
[[ -d /sys/module/guacamole_volume_keys ]] || insmod ./guacamole_volume_keys.ko
[[ -d /sys/module/guacamole_adsp_test ]] || insmod ./guacamole_adsp_test.ko
adsp_running=0
for attempt in $(seq 1 15); do
    for r in /sys/class/remoteproc/*; do
        if [[ $(cat "$r/name") == adsp && $(cat "$r/state") == running ]]; then adsp_running=1; fi
    done
    [[ $adsp_running == 1 ]] && break
    sleep 1
done
[[ $adsp_running == 1 ]]
insmod ./guacamole_audio_card.ko
insmod ./guacamole_amplifiers.ko
insmod ./guacamole_speaker_route.ko
# Must precede q6asm-dai, which reads its dai@N children once at probe.
insmod "$TRIAL/guacamole_microphone.ko"
python3 "$TRIAL/phone-audio-modules.py"
grep -q 'OnePlus 7 Pro' /proc/asound/cards
for r in /sys/class/remoteproc/*; do printf '%s: ' "$(cat "$r/name")"; cat "$r/state"; done
cat /proc/asound/pcm
echo "deferred: $(cat /sys/kernel/debug/devices_deferred)"
