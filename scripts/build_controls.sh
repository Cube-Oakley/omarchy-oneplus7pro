#!/usr/bin/env bash
# Build-only: the alert slider, vibration motor and rear flash for the running
# native5 kernel, as runtime modules (docs/controls-20260923.md):
#   guacamole_alert_slider.ko  gpio-keys overlay for the slider
#   guacamole_haptics.ko       i2c7 and the AW8697 node
#   aw8697-haptics.ko          the 7T Pro port's AW8697 driver
#   guacamole_flash.ko         PM8150L slave id 5 and its flash block
#   leds-qcom-flash.ko         mainline's driver, not shipped on the phone
# Deploys nothing. scripts/phone-controls-test.sh loads them stage by stage
# for testing; devices/oneplus7pro/controls/start.sh loads them at boot.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/controls"
OUT="$ROOT/out/controls"
DEV="$ROOT/devices/oneplus7pro/kernel"
rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
make_modules() {
    make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$1" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
}

# overlay <name> <dts> <node the overlay adds> <description> <loader source>
overlay() {
    local name=$1 dts=$2 node=$3 description=$4 loader=$5 dir="$WORK/$1"
    mkdir -p "$dir"
    cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$KERNEL/include" "$dts" "$dir/overlay.dts"
    dtc -@ -I dts -O dtb "$dir/overlay.dts" -o "$OUT/$name.dtbo"
    python3 - "$OUT/$name.dtbo" "$dir/overlay.h" "$node" "$description" <<'PY'
from pathlib import Path
import sys
blob = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text(
    'static const unsigned char overlay_dtbo[] __aligned(8) = {\n'
    + ','.join(map(str, blob)) + '\n};\n'
    + '#define OVERLAY_NODE "%s"\n#define OVERLAY_DESCRIPTION "%s"\n' % (sys.argv[3], sys.argv[4]))
PY
    cp "$loader" "$dir/loader.c"
    printf 'obj-m += %s.o\n%s-y := loader.o\n' "$name" "$name" > "$dir/Makefile"
    make_modules "$dir"
    cp "$dir/$name.ko" "$OUT/"
}

overlay guacamole_alert_slider "$DEV/input/guacamole-alert-slider.dts" /alert-slider \
    "Guacamole alert slider (gpio-keys); reboot to remove" "$DEV/input/overlay_loader.c"
overlay guacamole_haptics "$DEV/input/guacamole-haptics.dts" /soc@0/geniqup@8c0000/i2c@89c000/haptics@5a \
    "Guacamole haptics bus and AW8697 node; reboot to remove" "$DEV/input/overlay_loader.c"
overlay guacamole_flash "$DEV/leds/guacamole-flash.dts" /soc@0/spmi@c440000/pmic@5/led-controller@d300/led-0 \
    "Guacamole rear flash" "$DEV/leds/guacamole_flash.c"

mkdir -p "$WORK/drivers"
cp "$DEV/input/aw8697-haptics.c" "$KERNEL/drivers/leds/flash/leds-qcom-flash.c" "$WORK/drivers/"
printf 'obj-m += aw8697-haptics.o leds-qcom-flash.o\n' > "$WORK/drivers/Makefile"
make_modules "$WORK/drivers"
cp "$WORK/drivers/aw8697-haptics.ko" "$WORK/drivers/leds-qcom-flash.ko" "$OUT/"
(cd "$OUT" && sha256sum ./*.ko ./*.dtbo > SHA256SUMS)
ls -l "$OUT"
