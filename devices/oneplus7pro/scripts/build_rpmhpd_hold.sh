#!/usr/bin/env bash
# Build-only: the RPMh power-domain hold module for the running #188/#189
# native5 kernel. Load it before camcc-sm8150 (see rpmhpd_hold.c). Deploys nothing.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/rpmhpd-hold"
OUT="$ROOT/out/camera/power"
SRC="$ROOT/kernel/power"
rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$KERNEL/include" \
    "$SRC/guacamole-rpmhpd-hold.dts" "$WORK/hold.dts"
dtc -@ -I dts -O dtb "$WORK/hold.dts" -o "$OUT/rpmhpd-hold.dtbo"
if [[ -f "$ROOT/out/bluetooth/boot-fdt.dtb" ]]; then
    fdtoverlay -i "$ROOT/out/bluetooth/boot-fdt.dtb" -o "$WORK/merged-check.dtb" "$OUT/rpmhpd-hold.dtbo"
fi
cp "$SRC/rpmhpd_hold.c" "$WORK/"
python3 - "$OUT/rpmhpd-hold.dtbo" "$WORK/rpmhpd_hold_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char rpmhpd_hold_dtbo[] __aligned(8) = {\n'
                             + ','.join(map(str, blob)) + '\n};\n')
PY
printf 'obj-m += guacamole_rpmhpd_hold.o\nguacamole_rpmhpd_hold-y := rpmhpd_hold.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/guacamole_rpmhpd_hold.ko" "$OUT/"
(cd "$OUT" && sha256sum guacamole_rpmhpd_hold.ko rpmhpd-hold.dtbo > rpmhpd-hold.sha256)
