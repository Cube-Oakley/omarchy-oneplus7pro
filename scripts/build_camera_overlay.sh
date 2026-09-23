#!/usr/bin/env bash
# Build-only: the camera DT overlay (CCI0, CAMSS, PM8009 rails, IMX586 slot)
# and its loader module for the running #188/#189 native5 kernel. Checked
# against the boot FDT read back from the phone (out/bluetooth/boot-fdt.dtb).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/camera-overlay"
OUT="$ROOT/out/camera/overlay"
SRC="$ROOT/devices/oneplus7pro/kernel/camera"
rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$KERNEL/include" \
    "$SRC/guacamole-camera.dts" "$WORK/camera.dts"
# Fragments cannot see /soc@0's two-cell addressing or its interrupt parent.
dtc -@ -Wno-reg_format -Wno-pci_device_reg -Wno-pci_device_bus_num -Wno-simple_bus_reg \
    -Wno-avoid_default_addr_size -Wno-interrupts_property \
    -I dts -O dtb "$WORK/camera.dts" -o "$OUT/camera.dtbo"
fdtoverlay -i "$ROOT/out/bluetooth/boot-fdt.dtb" -o "$WORK/merged-check.dtb" "$OUT/camera.dtbo"
cp "$SRC/camera_overlay.c" "$WORK/"
python3 - "$OUT/camera.dtbo" "$WORK/camera_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char camera_dtbo[] __aligned(8) = {\n'
                             + ','.join(map(str, blob)) + '\n};\n')
PY
printf 'obj-m += guacamole_camera.o\nguacamole_camera-y := camera_overlay.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/guacamole_camera.ko" "$OUT/"
(cd "$OUT" && sha256sum guacamole_camera.ko camera.dtbo > SHA256SUMS)
