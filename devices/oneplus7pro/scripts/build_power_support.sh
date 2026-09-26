#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="${KERNEL_TREE:?Set the prepared power kernel tree}"
WORK="${POWER_WORK:-$ROOT/.work/power-support}"
OUT="${POWER_OUT:-$ROOT/out/power-desktop-test/power}"
mkdir -p "$WORK" "$OUT"
# Same single-apply, reboot-to-remove guard as the verified power-key loader.
sed 's/powerkey/power_support/g; s/power-key/power-support/g; s/PM8150 power-key/power support/g' \
    "$ROOT/kernel/power/powerkey_overlay.c" > "$WORK/power_support.c"
cp "$ROOT/kernel/power/guacamole-power-support.dts" "$WORK/power-support.dts"
if [[ ${POWER_RTC_SUPPORT:-0} == 1 ]]; then
    python3 - "$WORK/power-support.dts" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
source = p.read_text()
old = '&pm8150_rtc { status = "disabled"; };'
assert source.count(old) == 1
p.write_text(source.replace(old, '&pm8150_rtc { status = "okay"; };'))
PY
fi
dtc -@ -I dts -O dtb "$WORK/power-support.dts" -o "$OUT/guacamole-power-support.dtbo"
fdtoverlay -i "$KERNEL/bringup-guacamole.dtb" -o "$OUT/power-support-test.dtb" "$OUT/guacamole-power-support.dtbo"
python3 - "$OUT/guacamole-power-support.dtbo" "$WORK/power_support_dtbo.h" <<'PY'
from pathlib import Path
import sys
b = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char power_support_dtbo[] __aligned(8) = {\n' + ','.join(map(str, b)) + '\n};\n')
PY
printf 'obj-m += power_support.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/power_support.ko" "$OUT/"
sha256sum "$OUT/power_support.ko" "$OUT/guacamole-power-support.dtbo" > "$OUT/SHA256SUMS"
