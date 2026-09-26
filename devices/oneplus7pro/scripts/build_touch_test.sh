#!/usr/bin/env bash
# Build loadable touch diagnostics for the currently prepared gpu2 kernel.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="${KERNEL_TREE:-$ROOT/.work/linux-sm8150-codex-cpu}"
WORK="${TOUCH_WORK:-$ROOT/.work/touch-test}"
OUT="${TOUCH_OUT:-$ROOT/out/touch-test}"
mkdir -p "$WORK/drivers/input/touchscreen" "$OUT"
cp "$KERNEL/drivers/input/touchscreen/s6sy761.c" "$WORK/drivers/input/touchscreen/"
patch --batch -d "$WORK" -p1 < "$ROOT/kernel/touch/s6sy761-reset.patch"
patch --batch -d "$WORK" -p1 < "$ROOT/kernel/touch/s6sy761-guacamole-probe.patch"
patch --batch -d "$WORK" -p1 < "$ROOT/kernel/touch/s6sy761-resume-irq.patch"
cp "$WORK/drivers/input/touchscreen/s6sy761.c" "$WORK/s6sy761.c"
cp "$KERNEL/drivers/input/evdev.c" "$KERNEL/drivers/input/input-compat.h" "$WORK/"
cp "$ROOT/kernel/touch/touch_overlay.c" "$WORK/"
dtc -@ -I dts -O dtb "$ROOT/kernel/touch/guacamole-touch.dts" -o "$OUT/guacamole-touch.dtbo"
fdtoverlay -i "$KERNEL/bringup-guacamole.dtb" -o "$OUT/guacamole-touch-test.dtb" "$OUT/guacamole-touch.dtbo"
python3 - "$OUT/guacamole-touch.dtbo" "$WORK/touch_dtbo.h" <<'PY'
from pathlib import Path
import sys
b=Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char touch_dtbo[] __aligned(8) = {\n'+','.join(map(str,b))+'\n};\n')
PY
printf 'obj-m += s6sy761.o evdev.o touch_overlay.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 modules_prepare
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/s6sy761.ko" "$WORK/evdev.ko" "$WORK/touch_overlay.ko" "$OUT/"
sha256sum "$OUT/"*.ko "$OUT/guacamole-touch.dtbo" > "$OUT/SHA256SUMS"
