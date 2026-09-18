#!/usr/bin/env bash
# Build the stock RTC driver and a single-node overlay for the running native4.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL=${KERNEL_TREE:-$ROOT/.work/linux-sm8150-codex-wifi}
WORK="$ROOT/.work/rtc-test"
OUT="$ROOT/out/rtc-test"
mkdir -p "$WORK" "$OUT"
cp "$KERNEL/drivers/rtc/rtc-pm8xxx.c" "$WORK/"
cp "$ROOT/devices/oneplus7pro/kernel/power/rtc_overlay.c" "$WORK/"
cp "$ROOT/devices/oneplus7pro/kernel/power/rtc_parent.c" "$WORK/"
dtc -@ -I dts -O dtb "$ROOT/devices/oneplus7pro/kernel/power/guacamole-rtc.dts" \
    -o "$OUT/guacamole-rtc.dtbo"
fdtoverlay -i "$KERNEL/bringup-guacamole.dtb" -o "$OUT/rtc-test.dtb" \
    "$ROOT/out/wifi-desktop-test/power/guacamole-power-support.dtbo" \
    "$OUT/guacamole-rtc.dtbo"
python3 - "$OUT/guacamole-rtc.dtbo" "$WORK/rtc_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char rtc_dtbo[] __aligned(8) = {\n' + ','.join(map(str, blob)) + '\n};\n')
PY
printf 'obj-m += rtc-pm8xxx.o rtc_overlay.o rtc_parent.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/rtc-pm8xxx.ko" "$WORK/rtc_overlay.ko" "$WORK/rtc_parent.ko" "$OUT/"
(cd "$OUT" && sha256sum ./*.ko guacamole-rtc.dtbo rtc-test.dtb > SHA256SUMS)
