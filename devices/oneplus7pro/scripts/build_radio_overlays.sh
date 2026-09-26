#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="${KERNEL_TREE:-$ROOT/.work/linux-sm8150-codex-wifi}"
OUT="${RADIO_OUTPUT:-$ROOT/out/wifi-desktop-test}"
NAME="${RADIO_TEST_NAME:-native4}"
for stage in radio-control wifi; do
    WORK="${RADIO_OVERLAY_WORK:-$ROOT/.work/overlay}-$stage"
    mkdir -p "$WORK"
    dtc -@ -I dts -O dtb "$ROOT/kernel/power/guacamole-$stage.dts" \
        -o "$OUT/$stage.dtbo"
    fdtoverlay -i "$OUT/$NAME.dtb" -o "$OUT/$stage-merged.dtb" "$OUT/$stage.dtbo"
    cp "$ROOT/kernel/power/radio_overlay.c" "$WORK/radio_overlay.c"
    python3 - "$OUT/$stage.dtbo" "$WORK/radio_dtbo.h" "$stage" <<'PY'
from pathlib import Path
import sys
b=Path(sys.argv[1]).read_bytes()
node='/smem' if sys.argv[3]=='radio-control' else '/soc@0/wifi@18800000'
Path(sys.argv[2]).write_text('#define TEST_NODE "'+node+'"\nstatic const unsigned char radio_dtbo[] __aligned(8) = {\n'+','.join(map(str,b))+'\n};\n')
PY
    # Distinct module names let both stages coexist until the next reboot.
    name=${stage//-/_}_overlay
    printf 'obj-m += %s.o\n%s-y := radio_overlay.o\n' "$name" "$name" > "$WORK/Makefile"
    make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" \
        KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
    cp "$WORK/$name.ko" "$OUT/modules/"
done
(cd "$OUT/modules" && sha256sum ./*.ko > SHA256SUMS)
