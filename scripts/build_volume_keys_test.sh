#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/volume-keys-test"
OUT="$ROOT/out/audio-test"
SRC="$ROOT/devices/oneplus7pro/kernel/audio"
mkdir -p "$WORK" "$OUT"
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$KERNEL/include" \
    "$SRC/guacamole-volume-keys.dts" "$WORK/volume-keys.dts"
dtc -@ -I dts -O dtb "$WORK/volume-keys.dts" -o "$OUT/volume-keys.dtbo"
fdtoverlay -i "$OUT/amplifiers-merged.dtb" -o "$OUT/volume-keys-merged.dtb" "$OUT/volume-keys.dtbo"
cp "$SRC/volume_keys_overlay.c" "$WORK/"
python3 - "$OUT/volume-keys.dtbo" "$WORK/volume_keys_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob=Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char volume_keys_dtbo[] __aligned(8) = {\n'+','.join(map(str,blob))+'\n};\n')
PY
printf 'obj-m += guacamole_volume_keys.o\nguacamole_volume_keys-y := volume_keys_overlay.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers $ROOT/.work/audio-modules/Module.symvers" modules
cp "$WORK/guacamole_volume_keys.ko" "$OUT/"
