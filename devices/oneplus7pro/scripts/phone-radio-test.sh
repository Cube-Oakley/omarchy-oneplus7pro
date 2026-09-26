#!/usr/bin/env bash
# Staged bring-up on the checked native4/native5 images.
set -euo pipefail
BASE=/root/radio-bringup
release=$(uname -r)
MODULES="$BASE/modules/$release"
if [[ ! -d $MODULES && $release == 6.17.0-sm8150-codex-native4-* ]]; then
    MODULES="$BASE/modules"  # Original native4 layout retained for rollback.
fi
LOG="$BASE/logs"
mkdir -p "$LOG"
[[ $release == 6.17.0-sm8150-codex-native[45]-* ]] || {
    echo 'Requires a checked native4/native5 guard-page image' >&2; exit 1;
}
[[ -d $MODULES ]]
[[ -e /proc/device-tree/reserved-memory/rmtfs-lower-guard@f2900000/no-map &&
   -e /proc/device-tree/reserved-memory/rmtfs-upper-guard@f2b01000/no-map ]]
load() {
    local name=${1//-/_}
    [[ -d /sys/module/$name ]] || insmod "$MODULES/$1.ko"
}
case "${1:-}" in
    prepare)
        (cd "$MODULES" && sha256sum -c SHA256SUMS)
        for module in "$MODULES"/*.ko; do
            [[ $(modinfo -F vermagic "$module") == "$release "* ]] || {
                echo "Module release mismatch: $module" >&2; exit 1;
            }
        done
        for module in qcom_glink_smem qrtr qrtr-smd qcom_common qcom_pil_info qcom_sysmon qcom_q6v5 qcom_q6v5_pas qcom_pd_mapper; do
            load "$module"
        done
        load radio_control_overlay
        sleep 2
        for p in /sys/class/remoteproc/*; do
            if grep -q 'sm8150-mpss-pas' "$p/device/modalias"; then
                echo disabled > "$p/recovery"
            fi
            echo "$p"; cat "$p/name" "$p/state" "$p/firmware"
        done
        ;;
    modem)
        # Verify partition identities before making private lookup links.
        mkdir -p "$BASE/partitions" /var/lib/tqftpserv
        # UFS LUNs get their sdX names in probe-completion order, which changes
        # between boots (#191's faster boot clocks moved LUN 5 from sdf to
        # sde), so find each partition by its GPT name, which must be unique.
        for label in modemst1 modemst2 fsg fsc oem_stanvbk oem_dycnvbk; do
            matches=$(grep -lx "PARTNAME=$label" /sys/class/block/sd*/uevent || true)
            [[ -n $matches && $(wc -l <<< "$matches") -eq 1 ]] ||
                { echo "Expected exactly one partition named $label" >&2; exit 1; }
            device=/dev/$(basename "$(dirname "$matches")")
            actual=$(blkid -p -s PART_ENTRY_NAME -o value "$device")
            [[ "$actual" == "$label" ]] || { echo "Unexpected label: $device" >&2; exit 1; }
            ln -sfn "$device" "$BASE/partitions/$label"
        done
        # Preserve factory radio data. -r uses a RAM shadow for storage writes.
        if ! pgrep -x tqftpserv >/dev/null; then
            nohup "$BASE/bin/tqftpserv" -d > "$LOG/tqftpserv.log" 2>&1 < /dev/null &
        fi
        if ! pgrep -x rmtfs >/dev/null; then
            nohup "$BASE/bin/rmtfs" -r -P -o "$BASE/partitions" -s -v \
                > "$LOG/rmtfs.log" 2>&1 < /dev/null &
        fi
        ;;
    wifi)
        found=false
        for p in /sys/class/remoteproc/*; do
            if grep -q 'sm8150-mpss-pas' "$p/device/modalias" && [[ $(cat "$p/state") == running ]]; then
                found=true
            fi
        done
        "$found" || { echo 'MPSS must be running first' >&2; exit 1; }
        pgrep -x rmtfs >/dev/null
        pgrep -x tqftpserv >/dev/null
        for module in libarc4 rfkill cfg80211 mac80211 ath ath10k_core ath10k_snoc; do
            load "$module"
        done
        load wifi_overlay
        ;;
    *) echo 'Usage: phone-radio-test.sh prepare|modem|wifi' >&2; exit 2 ;;
esac
