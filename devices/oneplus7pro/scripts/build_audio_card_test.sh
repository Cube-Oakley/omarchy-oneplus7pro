#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/audio-card-test"
OUT="$ROOT/out/audio-test"
mkdir -p "$WORK" "$OUT"
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
    -I "$KERNEL/include" -I "$KERNEL/arch/arm64/boot/dts/qcom" \
    "$ROOT/kernel/power/guacamole-audio-card.dts" "$WORK/audio-card.dts"
dtc -@ -I dts -O dtb "$WORK/audio-card.dts" -o "$OUT/audio-card.dtbo"
fdtoverlay -i "$OUT/adsp-merged.dtb" -o "$OUT/audio-card-merged.dtb" "$OUT/audio-card.dtbo"
cp "$ROOT/kernel/power/audio_card_overlay.c" "$WORK/"
python3 - "$OUT/audio-card.dtbo" "$WORK/audio_card_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob=Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char audio_card_dtbo[] __aligned(8) = {\n'+','.join(map(str,blob))+'\n};\n')
PY
printf 'obj-m += guacamole_audio_card.o\nguacamole_audio_card-y := audio_card_overlay.o\n' > "$WORK/Makefile"
printf '#define PUBLISH_ONLY\n#include "audio_card_overlay.c"\n' > "$WORK/audio_card_publish.c"
printf 'obj-m += guacamole_audio_publish.o\nguacamole_audio_publish-y := audio_card_publish.o\n' >> "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/guacamole_audio_card.ko" "$OUT/"
cp "$WORK/guacamole_audio_publish.ko" "$OUT/"
