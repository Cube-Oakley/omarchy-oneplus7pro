#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/amplifier-test"
OUT="$ROOT/out/audio-test"
SRC="$ROOT/kernel/audio"
mkdir -p "$WORK" "$OUT"
dtc -@ -I dts -O dtb "$SRC/guacamole-amplifiers.dts" -o "$OUT/amplifiers.dtbo"
fdtoverlay -i "$OUT/audio-card-merged.dtb" -o "$OUT/amplifiers-merged.dtb" "$OUT/amplifiers.dtbo"
cp "$SRC/amplifiers_overlay.c" "$SRC/tfa9874-probe.c" "$WORK/"
python3 - "$OUT/amplifiers.dtbo" "$WORK/amplifiers_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob=Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char amplifiers_dtbo[] __aligned(8) = {\n'+','.join(map(str,blob))+'\n};\n')
PY
printf 'obj-m += guacamole_amplifiers.o tfa9874-probe.o\nguacamole_amplifiers-y := amplifiers_overlay.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers $ROOT/.work/audio-modules/Module.symvers" modules
cp "$WORK/guacamole_amplifiers.ko" "$WORK/tfa9874-probe.ko" "$OUT/"
