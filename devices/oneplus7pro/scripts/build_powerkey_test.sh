#!/usr/bin/env bash
# Build a temporary diagnostic against the prepared native kernel; no flashing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="${KERNEL_TREE:-$ROOT/.work/linux-sm8150-codex-native}"
WORK="${POWERKEY_WORK:-$ROOT/.work/powerkey-test}"
OUT="${POWERKEY_OUT:-$ROOT/out/powerkey-test}"
mkdir -p "$WORK" "$OUT"
cp "$ROOT/kernel/power/powerkey_overlay.c" "$WORK/"
dtc -@ -I dts -O dtb "$ROOT/kernel/power/guacamole-powerkey.dts" -o "$OUT/guacamole-powerkey.dtbo"
fdtoverlay -i "$KERNEL/bringup-guacamole.dtb" -o "$OUT/guacamole-powerkey-test.dtb" "$OUT/guacamole-powerkey.dtbo"
python3 - "$OUT/guacamole-powerkey.dtbo" "$WORK/powerkey_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char powerkey_dtbo[] __aligned(8) = {\n' + ','.join(map(str, blob)) + '\n};\n')
PY
printf 'obj-m += powerkey_overlay.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/powerkey_overlay.ko" "$OUT/"
sha256sum "$OUT/powerkey_overlay.ko" "$OUT/guacamole-powerkey.dtbo" > "$OUT/SHA256SUMS"
