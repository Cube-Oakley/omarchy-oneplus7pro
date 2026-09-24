#!/usr/bin/env bash
# Sensor DSP milestone 1 on the phone (docs/sensors-20260924.md). Run through
#   bash scripts/phone-ssh.sh 'bash -s check' < scripts/phone-sensors-test.sh
#   check   kernel #193's carve-outs and pool in place; GPU, modem, ADSP,
#           Wi-Fi and audio as on #192
#   start   load fastrpc and the SLPI overlay: SLPI boots at once (auto
#           boot), with crash recovery disabled as soon as it appears, since
#           SLPI cannot be restarted. Reboot to stop.
#   tree    build the tree hexagonrpcd serves the sensor DSP: the stock vendor
#           files (scripts/build_sensor_vendor.sh, copied to vendor-tree/), a
#           writable copy of persist's registry (persist is only read), with
#           the fields in registry-patches.json changed, and socinfo as
#           Android shows it. Keeps a pristine copy.
#   serve   start hexagonrpcd once: its first attach creates the sensors
#           domain, which cannot be attached again until a reboot.
#   firmware SET
#           install SLPI firmware set SET (firmware/SET/ with SHA256SUMS:
#           00121 is this phone's OxygenOS 12 image, older sets come from
#           OxygenOS 10) as the one SLPI boots; only before SLPI starts.
set -euo pipefail
MODULES=/root/sensors-bringup/modules/$(uname -r)
DT=/proc/device-tree/reserved-memory
BASE=/root/sensors-bringup
SERVED=$BASE/served
ATTACHED=/run/guacamole-sensors.attached

reg() { od -An -tx1 -v "$DT/$1/reg" | tr -d ' \n'; }

case "${1:-}" in
    check)
        uname -v
        uname -v | grep -Eq '^#(19[3-9]|2[0-9][0-9]) ' || { echo 'Not kernel #193 or later' >&2; exit 1; }
        [[ $(reg memory@97300000) == 00000000981000000000000001400000 ]] ||
            { echo "SLPI region: $(reg memory@97300000)" >&2; exit 1; }
        [[ -e $DT/fastrpc-shared-pool/reusable ]] || { echo 'No FastRPC pool' >&2; exit 1; }
        dmesg | grep -E 'fastrpc-shared-pool|Reserved memory: created' || true
        for p in /sys/class/remoteproc/*; do
            printf '%s %s %s\n' "$p" "$(cat "$p/name")" "$(cat "$p/state")"
        done
        dmesg | grep -iE 'zap|adreno|a640|msm_dpu|\[drm\].*(error|fail)' | tail -8 || true
        ls /dev/dri/
        ip -br addr show wlan0 || true
        cat /proc/asound/cards
        ;;
    start)
        uname -v | grep -Eq '^#(19[3-9]|2[0-9][0-9]) ' || { echo 'Not kernel #193 or later' >&2; exit 1; }
        (cd "$MODULES" && sha256sum -c --quiet SHA256SUMS)
        if [[ -d /sys/module/camcc_sm8150 || -d /sys/module/qcom_camss ]]; then
            echo 'Camera stack loaded; reboot without it first' >&2; exit 1
        fi
        [[ -d /sys/module/fastrpc ]] || insmod "$MODULES/fastrpc.ko"
        (
            for _ in $(seq 1 3000); do
                for p in /sys/class/remoteproc/*; do
                    if [[ $(cat "$p/name" 2>/dev/null) == slpi ]]; then
                        echo disabled > "$p/recovery"
                        echo "$p: slpi, recovery $(cat "$p/recovery")"
                        exit 0
                    fi
                done
                sleep 0.01
            done
            echo 'SLPI remoteproc never appeared' >&2
        ) &
        watcher=$!
        insmod "$MODULES/guacamole_slpi.ko"
        wait "$watcher"
        slpi=
        for p in /sys/class/remoteproc/*; do
            [[ $(cat "$p/name") == slpi ]] && slpi=$p
        done
        [[ -n $slpi ]]
        for _ in $(seq 1 30); do
            [[ $(cat "$slpi/state") == running ]] && break
            sleep 1
        done
        echo "SLPI state: $(cat "$slpi/state")"
        ls -la /dev/fastrpc-* 2>&1 || true
        dmesg | grep -iE 'slpi|dsps|2400000|fastrpc|pd.mapper|remoteproc|qcom_q6v5' | tail -30 || true
        ;;
    tree)
        [[ ! -e $ATTACHED ]] || { echo 'hexagonrpcd has attached this boot; its tree is in use' >&2; exit 1; }
        (cd "$BASE/vendor-tree" && sha256sum -c --quiet SHA256SUMS)
        persist=$(blkid -t PARTLABEL=persist -o device | head -1)
        [[ -b $persist ]] && ! grep -q "^$persist " /proc/mounts
        # Android's /sys/devices/soc0 strings; the stock configs only accept
        # MTP and 339. SMEM says hardware platform 8 (MTP), subtype 0.
        info=/sys/kernel/debug/qcom_socinfo
        [[ $(cat $info/hardware_platform) == 8 && $(cat $info/hardware_platform_subtype) == 0 &&
           $(cat /sys/devices/soc0/soc_id) == 339 ]]
        rm -rf "$SERVED.new"
        mkdir -p "$SERVED.new/sensors" "$SERVED.new/socinfo" "$SERVED.new/acdb"
        cp -a "$BASE/vendor-tree/sensors/config" "$BASE/vendor-tree/sensors/sns_reg.conf" "$SERVED.new/sensors/"
        cp -a "$BASE/vendor-tree/dsp" "$SERVED.new/"
        # debugfs opens the filesystem read-only.
        debugfs -R "rdump /sensors/registry/registry $SERVED.new/sensors" "$persist" 2>&1 | grep -v '^debugfs' || true
        for f in sns_reg_version sns_reg_ctrl file1 file2; do
            debugfs -R "dump /sensors/registry/$f $SERVED.new/sensors/$f" "$persist" 2>&1 | grep -v '^debugfs' || true
            [[ -e $SERVED.new/sensors/$f ]]
        done
        # Changed fields (registry-patches.json, no per-device values) go into
        # the served copy only; the DSP keeps a field whose version is above
        # its configuration's.
        if [[ -f $BASE/registry-patches.json ]]; then
            python3 - "$BASE/registry-patches.json" "$SERVED.new/sensors/registry" <<'PY'
import json, sys
from pathlib import Path
patches, registry = json.loads(Path(sys.argv[1]).read_text()), Path(sys.argv[2])
for group, fields in patches.items():
    path = registry / group
    entry = json.loads(path.read_text())
    entry[group].update(fields)
    path.write_text(json.dumps(entry))
    print('registry patch: %s (%s)' % (group, ', '.join(sorted(fields))))
PY
        fi
        printf 'MTP\n' > "$SERVED.new/socinfo/hw_platform"
        printf 'Unknown\n' > "$SERVED.new/socinfo/platform_subtype"
        printf '0\n' > "$SERVED.new/socinfo/platform_subtype_id"
        printf '%s\n' "$(cat $info/platform_version)" > "$SERVED.new/socinfo/platform_version"
        printf '%s\n' "$(cat /sys/devices/soc0/soc_id)" > "$SERVED.new/socinfo/soc_id"
        printf '%s\n' "$(cat /sys/devices/soc0/revision)" > "$SERVED.new/socinfo/revision"
        tar -C "$SERVED.new" -czf "$BASE/served-pristine.tar.gz" .
        chmod 600 "$BASE/served-pristine.tar.gz"
        rm -rf "$SERVED"
        mv "$SERVED.new" "$SERVED"
        echo "config $(ls "$SERVED/sensors/config" | wc -l), registry $(ls "$SERVED/sensors/registry" | wc -l), dsp $(ls "$SERVED/dsp/sdsp" | wc -l)"
        head -c 200 "$SERVED"/socinfo/* | tr '\n' ' '; echo
        ;;
    serve)
        [[ ! -e $ATTACHED ]] || { echo 'hexagonrpcd already attached this boot; reboot first' >&2; exit 1; }
        ! pgrep -x hexagonrpcd >/dev/null
        slpi=
        for p in /sys/class/remoteproc/*; do
            [[ $(cat "$p/name") == slpi ]] && slpi=$p
        done
        [[ -n $slpi && $(cat "$slpi/state") == running && -c /dev/fastrpc-sdsp ]]
        [[ -d /sys/module/qcom_pd_mapper && -d $SERVED/sensors/registry ]]
        mkdir -p "$BASE/logs"
        log=$BASE/logs/hexagonrpcd-$(date +%Y%m%d-%H%M%S).log
        touch "$ATTACHED"
        setsid "$BASE/bin/hexagonrpcd" -f /dev/fastrpc-sdsp -s -R "$SERVED" -d sdsp </dev/null >>"$log" 2>&1 &
        echo "hexagonrpcd $! logging to $log"
        sleep 20
        pgrep -ax hexagonrpcd || echo 'hexagonrpcd exited' >&2
        echo "SLPI state: $(cat "$slpi/state")"
        wc -l < "$log"
        grep -v -E '^(open|read|write|close|stat|seek)' "$log" | tail -15 || true
        dmesg | grep -iE 'slpi|dsps|fastrpc|smmu|remoteproc2' | tail -15 || true
        ;;
    firmware)
        set=${2:?firmware set}
        FW=/lib/firmware/qcom/sm8150/oneplus/guacamole
        for p in /sys/class/remoteproc/*; do
            [[ $(cat "$p/name") != slpi ]] || { echo 'SLPI has started this boot; reboot first' >&2; exit 1; }
        done
        (cd "$BASE/firmware/$set" && sha256sum -c --quiet SHA256SUMS)
        [[ -e $BASE/firmware/$set/slpi.mdt ]]
        rm -f "$FW"/slpi.mdt "$FW"/slpi.b[0-9][0-9] "$FW"/slpir.jsn "$FW"/slpius.jsn
        cp "$BASE/firmware/$set"/slpi* "$FW/"
        printf '%s\n' "$set" > "$BASE/firmware/active"
        (cd "$FW" && ls slpi* | wc -l)
        strings -n 8 "$FW"/slpi.b* | grep -m1 -o 'SLPI\.HY\.[0-9.]*-[0-9]*[^ ]*' || true
        ;;
    *)
        echo 'Usage: phone-sensors-test.sh check|start|tree|serve|firmware SET' >&2
        exit 2
        ;;
esac
