#!/usr/bin/env bash
# Build-only: the focus actuator drivers for the running #188-#190 native5
# kernel (the 7T Pro's LC898217XC driver, and its AK7374 support patched into
# our ak7375.c) and the actuator identification overlay. Needs the modules
# from build_camera_modules.sh for their symbols. Deploys nothing.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
MEDIA="$ROOT/.work/camera-modules"
WORK="$ROOT/.work/camera-lens"
OUT="$ROOT/out/camera/lens"
SRC="$ROOT/devices/oneplus7pro/kernel/camera"
rm -rf "$WORK"
mkdir -p "$WORK/drivers" "$WORK/overlay" "$OUT"
cp "$SRC/lc898217xc.c" "$KERNEL/drivers/media/i2c/ak7375.c" "$WORK/drivers/"
patch -s -p4 -d "$WORK/drivers" < "$SRC/ak7375-ak7374.patch"
printf 'obj-m += lc898217xc.o ak7375.o\n' > "$WORK/drivers/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK/drivers" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers $MEDIA/mc/Module.symvers $MEDIA/v4l2-core/Module.symvers" modules
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$KERNEL/include" \
    "$SRC/guacamole-camera-lens-probe.dts" "$WORK/overlay/lens-probe.dts"
dtc -@ -I dts -O dtb "$WORK/overlay/lens-probe.dts" -o "$OUT/lens-probe.dtbo"
cp "$SRC/lens_probe_overlay.c" "$WORK/overlay/"
python3 - "$OUT/lens-probe.dtbo" "$WORK/overlay/lens_probe_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char lens_probe_dtbo[] __aligned(8) = {\n'
                             + ','.join(map(str, blob)) + '\n};\n')
PY
printf 'obj-m += guacamole_camera_lens_probe.o\nguacamole_camera_lens_probe-y := lens_probe_overlay.o\n' \
    > "$WORK/overlay/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK/overlay" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/drivers/lc898217xc.ko" "$WORK/drivers/ak7375.ko" "$WORK/overlay/guacamole_camera_lens_probe.ko" "$OUT/"
(cd "$OUT" && sha256sum ./*.ko lens-probe.dtbo > SHA256SUMS)
