#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="${KERNEL_TREE:-$ROOT/.work/linux-sm8150-codex-native}"
WORK="${GAUGE_WORK:-$ROOT/.work/gauge-bus-test}"
OUT="${GAUGE_OUT:-$ROOT/out/gauge-bus-test}"
mkdir -p "$WORK" "$OUT"
cp "$ROOT/devices/oneplus7pro/kernel/power/gauge_bus_overlay.c" "$WORK/"
dtc -@ -I dts -O dtb "$ROOT/devices/oneplus7pro/kernel/power/guacamole-gauge-bus.dts" -o "$OUT/guacamole-gauge-bus.dtbo"
fdtoverlay -i "$KERNEL/bringup-guacamole.dtb" -o "$OUT/guacamole-gauge-bus-test.dtb" "$OUT/guacamole-gauge-bus.dtbo"
python3 - "$OUT/guacamole-gauge-bus.dtbo" "$WORK/gauge_bus_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char gauge_bus_dtbo[] __aligned(8) = {\n' + ','.join(map(str, blob)) + '\n};\n')
PY
printf 'obj-m += gauge_bus_overlay.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/gauge_bus_overlay.ko" "$OUT/"
sha256sum "$OUT/gauge_bus_overlay.ko" "$OUT/guacamole-gauge-bus.dtbo" > "$OUT/SHA256SUMS"
