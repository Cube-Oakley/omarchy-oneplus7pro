#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/speaker-test"
OUT="$ROOT/out/audio-test"
SRC="$ROOT/kernel/audio"
mkdir -p "$WORK" "$OUT"
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$KERNEL/include" \
    "$SRC/guacamole-speaker-route.dts" "$WORK/speaker-route.dts"
dtc -@ -I dts -O dtb "$WORK/speaker-route.dts" -o "$OUT/speaker-route.dtbo"
fdtoverlay -i "$OUT/amplifiers-merged.dtb" -o "$OUT/speaker-route-merged.dtb" "$OUT/speaker-route.dtbo"
cp "$SRC/speaker_route_overlay.c" "$SRC/tfa9874.c" "$WORK/"
python3 - "$OUT/speaker-route.dtbo" "$WORK/speaker_route_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob=Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char speaker_route_dtbo[] __aligned(8) = {\n'+','.join(map(str,blob))+'\n};\n')
PY
printf 'obj-m += guacamole_speaker_route.o snd-soc-tfa9874.o\nguacamole_speaker_route-y := speaker_route_overlay.o\nsnd-soc-tfa9874-y := tfa9874.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers $ROOT/.work/audio-modules/Module.symvers" modules
cp "$WORK/guacamole_speaker_route.ko" "$WORK/snd-soc-tfa9874.ko" "$OUT/"
