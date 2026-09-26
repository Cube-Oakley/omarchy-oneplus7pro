#!/usr/bin/env bash
# Build-only: the Bluetooth stack as modules for the running #188/#189 native5
# kernel (its .config already selects them; the phone has no module tree for
# this kernel). Deploys nothing.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/bluetooth-modules"
OUT="$ROOT/out/bluetooth/modules"
# rfkill is a module too; the phone loads this build of it for Wi-Fi.
RFKILL_SYMVERS="$ROOT/.work/native5-radio-modules/rfkill/Module.symvers"
rm -rf "$WORK"
mkdir -p "$WORK/net" "$WORK/drivers" "$WORK/crypto" "$WORK/pwrseq" "$OUT"
copy() {
    rsync -a --exclude '*.o' --exclude '*.cmd' --exclude '.*' --exclude '*.ko' \
        --exclude '*.mod' --exclude '*.mod.c' --exclude 'modules.order' "$1" "$2"
}
copy "$KERNEL/net/bluetooth" "$WORK/net/"
copy "$KERNEL/drivers/bluetooth" "$WORK/drivers/"
# ECDH for Secure Simple Pairing only, not the whole crypto directory.
cp "$KERNEL"/crypto/{ecc.c,ecc_curve_defs.h,ecdh.c,ecdh_helper.c} "$WORK/crypto/"
printf 'obj-m += ecc.o ecdh_generic.o\necdh_generic-y := ecdh.o ecdh_helper.o\n' > "$WORK/crypto/Makefile"
# hci_qca links the power-sequencing core (used by newer WCN chips, not WCN3990).
cp "$KERNEL/drivers/power/sequencing/core.c" "$WORK/pwrseq/"
printf 'obj-m += pwrseq-core.o\npwrseq-core-y := core.o\n' > "$WORK/pwrseq/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 -j"${JOBS:-8}" M="$WORK/pwrseq" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
make -C "$KERNEL" ARCH=arm64 LLVM=1 -j"${JOBS:-8}" M="$WORK/crypto" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
make -C "$KERNEL" ARCH=arm64 LLVM=1 -j"${JOBS:-8}" M="$WORK/net/bluetooth" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers $RFKILL_SYMVERS $WORK/crypto/Module.symvers" modules
make -C "$KERNEL" ARCH=arm64 LLVM=1 -j"${JOBS:-8}" M="$WORK/drivers/bluetooth" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers $WORK/net/bluetooth/Module.symvers $WORK/pwrseq/Module.symvers" modules
rm -f "$OUT"/*.ko
cp "$WORK"/crypto/{ecc,ecdh_generic}.ko "$WORK"/pwrseq/pwrseq-core.ko "$WORK"/net/bluetooth/bluetooth.ko \
    "$WORK"/net/bluetooth/{rfcomm/rfcomm,bnep/bnep,hidp/hidp}.ko \
    "$WORK"/drivers/bluetooth/{btqca,btbcm,hci_uart}.ko "$OUT/"
# Runtime DT overlay: UART13 and the WCN3990 child. Checked against the boot
# FDT read back from the phone when out/bluetooth/boot-fdt.dtb exists.
SRC="$ROOT/kernel/radio/bluetooth"
mkdir -p "$WORK/overlay"
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp -I "$KERNEL/include" \
    "$SRC/guacamole-bluetooth.dts" "$WORK/overlay/bluetooth.dts"
dtc -@ -I dts -O dtb "$WORK/overlay/bluetooth.dts" -o "$OUT/bluetooth.dtbo"
if [[ -f "$ROOT/out/bluetooth/boot-fdt.dtb" ]]; then
    fdtoverlay -i "$ROOT/out/bluetooth/boot-fdt.dtb" -o "$OUT/merged-check.dtb" "$OUT/bluetooth.dtbo"
fi
cp "$SRC/bluetooth_overlay.c" "$SRC/hsuart_alias_shim.c" "$WORK/overlay/"
python3 - "$OUT/bluetooth.dtbo" "$WORK/overlay/bluetooth_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char bluetooth_dtbo[] __aligned(8) = {\n'
                             + ','.join(map(str, blob)) + '\n};\n')
PY
printf 'obj-m += guacamole_bluetooth.o guacamole_hsuart_alias.o\nguacamole_bluetooth-y := bluetooth_overlay.o\nguacamole_hsuart_alias-y := hsuart_alias_shim.o\n' > "$WORK/overlay/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK/overlay" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/overlay/guacamole_bluetooth.ko" "$WORK/overlay/guacamole_hsuart_alias.ko" "$OUT/"
# Load order for insmod (no depmod tree on the phone); the overlay goes last.
# guacamole_hsuart_alias needs kallsyms addresses and is loaded before it
# by the test script, not from this list.
printf '%s\n' ecc ecdh_generic pwrseq-core bluetooth btqca btbcm hci_uart rfcomm bnep hidp \
    guacamole_bluetooth > "$OUT/load-order"
(cd "$OUT" && sha256sum ./*.ko load-order bluetooth.dtbo > SHA256SUMS)
