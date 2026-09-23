#!/usr/bin/env bash
# Microphone overlay module: MIC BIAS routes and the MultiMedia2 capture link.
# Its q6asm-dai and machine-driver fixes are built by build_audio_modules.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/microphone-test"
OUT="$ROOT/out/audio-test/microphone"
SRC="$ROOT/devices/oneplus7pro/kernel/audio"
rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$KERNEL/include" \
    "$SRC/guacamole-microphone.dts" "$WORK/microphone.dts"
dtc -@ -I dts -O dtb "$WORK/microphone.dts" -o "$OUT/microphone.dtbo"
fdtoverlay -i "$ROOT/out/audio-test/speaker-route-merged.dtb" \
    -o "$OUT/merged.dtb" "$OUT/microphone.dtbo"
cp "$SRC/microphone_overlay.c" "$WORK/"
python3 - "$OUT/microphone.dtbo" "$WORK/microphone_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char microphone_dtbo[] __aligned(8) = {\n'
                             + ','.join(map(str, blob)) + '\n};\n')
PY
printf 'obj-m += guacamole_microphone.o\nguacamole_microphone-y := microphone_overlay.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
rm -f "$OUT"/*.ko "$OUT/sm8150-capture.patch"
cp "$WORK/guacamole_microphone.ko" "$OUT/"
(cd "$OUT" && sha256sum ./*.ko microphone.dtbo merged.dtb > SHA256SUMS)
