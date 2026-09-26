#!/usr/bin/env bash
# Build-only: the camera DT overlays (CCI, CAMSS, PM8009 rails and camera
# slots: the IMX586 main camera, the S5K3M5 telephoto, the IMX481 ultra-wide,
# or all three) and their loader modules for the running native5
# kernel. Checked against the boot FDT read back from the phone
# (out/bluetooth/boot-fdt.dtb).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/camera-overlay"
OUT="$ROOT/out/camera/overlay"
SRC="$ROOT/kernel/camera"
rm -rf "$WORK"
mkdir -p "$OUT"
# variant NAME DEFINE SLOT: one slot per overlay (guacamole-camera.dts).
variant() {
    local name=$1 defines=$2 slot=$3 work="$WORK/$1" flags=()
    for define in $defines; do flags+=(-D"$define"); done
    mkdir -p "$work"
    cpp -nostdinc -undef -D__DTS__ "${flags[@]}" -x assembler-with-cpp -I "$KERNEL/include" \
        "$SRC/guacamole-camera.dts" "$work/camera.dts"
    # Fragments cannot see /soc@0's two-cell addressing or its interrupt parent.
    dtc -@ -Wno-reg_format -Wno-pci_device_reg -Wno-pci_device_bus_num -Wno-simple_bus_reg \
        -Wno-avoid_default_addr_size -Wno-interrupts_property \
        -I dts -O dtb "$work/camera.dts" -o "$work/camera.dtbo"
    fdtoverlay -i "$ROOT/out/bluetooth/boot-fdt.dtb" -o "$work/merged-check.dtb" "$work/camera.dtbo"
    cp "$SRC/camera_overlay.c" "$work/"
    python3 - "$work/camera.dtbo" "$work/camera_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char camera_dtbo[] __aligned(8) = {\n'
                             + ','.join(map(str, blob)) + '\n};\n')
PY
    printf 'obj-m += %s.o\n%s-y := camera_overlay.o\nccflags-y += -DCAMERA_SLOT=\\"%s\\"\n' \
        "$name" "$name" "$slot" > "$work/Makefile"
    make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$work" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
    cp "$work/$name.ko" "$OUT/"
}
variant guacamole_camera CAMERA_MAIN IMX586
cp "$WORK/guacamole_camera/camera.dtbo" "$OUT/camera.dtbo"
variant guacamole_camera_tele CAMERA_TELE S5K3M5
cp "$WORK/guacamole_camera_tele/camera.dtbo" "$OUT/camera-tele.dtbo"
variant guacamole_camera_wide CAMERA_WIDE IMX481
cp "$WORK/guacamole_camera_wide/camera.dtbo" "$OUT/camera-wide.dtbo"
# All three rear cameras, once each works on its own
# (docs/camera-telephoto-20260924.md, docs/camera-ultrawide-20260924.md).
variant guacamole_camera_rear "CAMERA_MAIN CAMERA_TELE CAMERA_WIDE" IMX586,S5K3M5,IMX481
cp "$WORK/guacamole_camera_rear/camera.dtbo" "$OUT/camera-rear.dtbo"
(cd "$OUT" && sha256sum guacamole_camera.ko camera.dtbo guacamole_camera_tele.ko camera-tele.dtbo \
    guacamole_camera_wide.ko camera-wide.dtbo guacamole_camera_rear.ko camera-rear.dtbo > SHA256SUMS)
